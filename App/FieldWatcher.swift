import Cocoa
import Carbon
import ApplicationServices

/// 영문·숫자 칸 자동 영문: 아이디·이메일·비밀번호·전화·카드·날짜·인증번호 칸 등에 들어가면 영문으로, 나오면 원래대로.
/// 손쉬운 사용 정보로 지금 포커스된 칸을 알아본다 (권한 필요). 주소창·검색창은 건드리지 않는다.
enum FieldWatcher {
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "autoEnglishFields") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "autoEnglishFields")
            if !newValue { restore() }
            watch(NSWorkspace.shared.frontmostApplication)
        }
    }

    private static var observer: AXObserver?
    /// 감시 중인 앱 (포커스 알림이 오면 이 앱에 지금 포커스된 칸을 다시 묻는다)
    private static var watchedApp: AXUIElement?
    /// 마지막으로 본 칸 (같은 칸에 대한 알림이 여러 번 와도 한 번만 처리)
    private static var lastElement: AXUIElement?
    /// 영문 칸에 처음 들어가기 직전의 한/영. 영문 칸들을 다 벗어나면 이것으로 되돌린다 (nil = 바꾼 적 없음)
    private static var originalHangul: Bool?
    private static var switchedApp: String?

    /// 크롬 계열은 이 값을 켜야 웹페이지 입력칸 정보를 넘겨준다
    private static let chromium: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.microsoft.edgemac", "com.brave.Browser",
        "com.naver.Whale", "company.thebrowser.Browser", "com.vivaldi.Vivaldi", "org.chromium.Chromium",
    ]
    private static var manualEnabled = Set<pid_t>()
    /// 앱에 칸 정보를 묻는 일은 여기서만 한다. 입력기 본체(메인 스레드)가 그 앱을 기다리며 멈추지 않게
    /// (그 앱도 입력기의 답을 기다리는 중이라 메인에서 물으면 서로 기다려 클릭이 늦어짐)
    private static let queue = DispatchQueue(label: "kr.ogapp.fieldwatcher", qos: .userInitiated)
    /// 한 번 물을 때 최대 대기 시간
    private static let timeout: Float = 0.25

    // DIAG(B16 임시): 포커스 세대 번호. 포커스 알림마다 늘린다 (메인에서만). 진단 끝나면 정리
    private static var focusGen = 0
    private static func diag(_ s: String) { keyLog.info("B16DIAG \(s, privacy: .public)") }

    static func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { n in
            watch(n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
        }
        watch(NSWorkspace.shared.frontmostApplication)
    }

    // MARK: 감시

    private static func watch(_ app: NSRunningApplication?) {
        leaveOnAppChange()
        if let o = observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(o), .defaultMode)
            observer = nil
        }
        watchedApp = nil
        guard enabled, AXIsProcessTrusted(), let app = app,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        let pid = app.processIdentifier
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, timeout)
        if let id = app.bundleIdentifier, chromium.contains(id), !manualEnabled.contains(pid) {
            manualEnabled.insert(pid)
            queue.async { AXUIElementSetAttributeValue(axApp, "AXManualAccessibility" as CFString, kCFBooleanTrue) }
        }
        var obs: AXObserver?
        guard AXObserverCreate(pid, { _, element, _, _ in FieldWatcher.focusChanged(element) }, &obs) == .success,
              let o = obs else { return }
        AXObserverAddNotification(o, axApp, kAXFocusedUIElementChangedNotification as CFString, nil)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(o), .defaultMode)
        observer = o
        watchedApp = axApp
        // 지금 포커스된 칸도 확인 (작업 줄에서)
        focusGen += 1
        let g = focusGen, t0 = Date()
        diag("앱감시 g=\(g) \(app.bundleIdentifier ?? "?")")
        queue.async {
            var f: CFTypeRef?
            guard AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &f) == .success,
                  let f = f else { return }
            classify(f as! AXUIElement, gen: g, queuedAt: t0)
        }
    }

    /// 포커스가 바뀌었다는 알림(메인): 칸 알아보기는 작업 줄로 넘긴다
    private static func focusChanged(_ e: AXUIElement) {
        guard enabled else { return }
        focusGen += 1
        let g = focusGen, t0 = Date()
        diag("포커스 g=\(g) 한글=\(ModeState.hangul) 보안입력=\(IsSecureEventInputEnabled())")
        checkFocus(gen: g, queuedAt: t0, fallback: e)
        // B16: 알림이 실제 포커스 이동보다 먼저 오면 그 순간엔 아직 이전 칸(이름 칸 등)이 답으로 온다 (간헐 증상).
        // 조금 뒤 두 번 더 물어 바로잡는다. 같은 칸이면 apply가 걸러낸다.
        for delay in [0.25, 0.7] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard g == focusGen else { return }
                checkFocus(gen: g, queuedAt: Date(), fallback: nil, recheck: true)
            }
        }
    }

    /// 입력기가 새 칸에 연결될 때 (사파리는 칸마다 다시 연결): 포커스 알림이 늦거나 없을 때의 대비
    static func recheckNow() {
        guard enabled, watchedApp != nil else { return }
        focusGen += 1
        let g = focusGen
        diag("입력기 연결 g=\(g)")
        checkFocus(gen: g, queuedAt: Date(), fallback: nil, recheck: true)
    }

    /// 작업 줄에서 앱에 지금 포커스된 칸을 묻고 판정한다.
    /// B16: 사파리는 웹페이지 칸으로 옮겨도 알림에 바깥 그룹(AXGroup)을 실어 보낸다 (실기 axprobe로 확인:
    /// 앱에 직접 물으면 AXTextField·주민등록번호가 나옴). 그래서 알림 요소 대신 앱에 지금 포커스된 칸을 묻는다.
    private static func checkFocus(gen g: Int, queuedAt t0: Date, fallback: AXUIElement?, recheck: Bool = false) {
        let app = watchedApp
        queue.async {
            var target = fallback
            if let app = app {
                var f: CFTypeRef?
                if AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &f) == .success, let f = f {
                    target = (f as! AXUIElement)
                }
            }
            guard let t = target else { return }
            classify(t, gen: g, queuedAt: t0, recheck: recheck)
        }
    }

    /// 작업 줄: 칸 종류를 알아보고 결과만 메인으로
    private static func classify(_ e: AXUIElement, gen: Int, queuedAt t0: Date, recheck: Bool = false) {
        let start = Date()
        AXUIElementSetMessagingTimeout(e, timeout)
        let (english, kind) = isEnglishFieldDiag(e)
        let end = Date()
        DispatchQueue.main.async {
            let wait = start.timeIntervalSince(t0), work = end.timeIntervalSince(start)
            diag(String(format: "%@판정 g=%d 최신=%d 대기 %.2fs 판정 %.2fs → %@ [%@]", recheck ? "재확인 " : "", gen, focusGen, wait, work, english ? "영문" : "그대로", kind))
            apply(e, english, gen: gen, recheck: recheck)
        }
    }

    /// 칸마다 따로 판단한다 (윈도우와 같은 방식):
    ///  - 영문 칸에 들어올 때마다 그 칸은 영문으로 시작. 칸 안에서 직접 한글로 바꾸면 그 칸에서만 존중
    ///  - 영문 칸들을 다 벗어나 일반 칸으로 가면, 처음 영문 칸에 들어오기 직전 상태로 되돌림
    private static func apply(_ e: AXUIElement, _ english: Bool, gen: Int = -1, recheck: Bool = false) {
        guard enabled, InputSources.ogIsCurrent else { diag("적용안함 g=\(gen) (꺼짐 또는 OG 아님)"); return }
        // B16: 이미 다음 칸으로 옮겨간 뒤 도착한 낡은 결과는 버린다 (지금 칸을 뒤집지 않게)
        if gen >= 0 && gen < focusGen { diag("버림 g=\(gen) 최신=\(focusGen) (낡은 결과)"); return }
        if let last = lastElement, CFEqual(last, e) { if !recheck { diag("적용안함 g=\(gen) (같은 칸)") }; return }
        if recheck { diag("재확인으로 바로잡음 g=\(gen)") }
        lastElement = e
        diag("적용 g=\(gen)\(gen == focusGen ? "" : " ⚠️낡은결과") 영문칸=\(english) 한글=\(ModeState.hangul) 원래=\(originalHangul.map { "\($0)" } ?? "없음")")
        if english {
            // 영문 칸 묶음의 시작: 그 직전 상태를 기억 (원래 영문이었으면 나갈 때도 영문 그대로)
            if originalHangul == nil {
                originalHangul = ModeState.hangul
                switchedApp = ModeState.currentApp
            }
            guard ModeState.hangul else { return }
            InputController.active?.commit(nil)
            ModeState.setTransient(hangul: false)
            ModeIndicator.shared.show(hangul: false)
            keyLog.info("영문 칸 → 영문")
        } else {
            restore()
        }
    }

    /// 영문 칸에 들어오기 직전 상태로 되돌린다
    private static func restore() {
        guard let orig = originalHangul else { return }
        originalHangul = nil
        guard ModeState.hangul != orig else { return }
        ModeState.setTransient(hangul: orig)
        ModeIndicator.shared.show(hangul: orig)
        keyLog.info("영문 칸 나감 → \(orig ? "한글" : "영문", privacy: .public)")
    }

    /// 앱이 바뀔 때: 새 앱의 한/영은 앱별 기억이 정한다. 기억이 없으면 원래대로.
    private static func leaveOnAppChange() {
        lastElement = nil
        guard let orig = originalHangul else { return }
        originalHangul = nil
        let now = ModeState.currentApp
        if now == switchedApp || !ModeState.hasSaved(now) {
            if ModeState.hangul != orig { ModeState.setTransient(hangul: orig) }
        }
    }

    // MARK: 칸 알아보기

    /// DIAG: 판정 + 칸 종류 요약 (역할·역할설명만, 입력값은 남기지 않음)
    private static func isEnglishFieldDiag(_ e: AXUIElement) -> (Bool, String) {
        let english = isEnglishField(e)
        let kind = [str(e, kAXRoleAttribute as String), str(e, kAXRoleDescriptionAttribute as String)].compactMap { $0 }.joined(separator: "/")
        return (english, kind)
    }

    /// 칸 정보를 모아 규칙(HangulCore/FieldRules)으로 판단
    static func isEnglishField(_ e: AXUIElement) -> Bool {
        var label: String?
        var t: CFTypeRef?
        if AXUIElementCopyAttributeValue(e, "AXTitleUIElement" as CFString, &t) == .success, let te = t {
            let el = te as! AXUIElement
            AXUIElementSetMessagingTimeout(el, timeout)
            label = str(el, "AXValue") ?? str(el, "AXTitle")
        }
        let f = FieldRules.Field(
            role: str(e, kAXRoleAttribute as String),
            subrole: str(e, kAXSubroleAttribute as String),
            roleDescription: str(e, kAXRoleDescriptionAttribute as String),
            texts: [str(e, "AXTitle"), str(e, "AXDescription"), str(e, "AXHelp"), label].compactMap { $0 },
            placeholder: str(e, "AXPlaceholderValue"),
            domIdentifier: str(e, "AXDOMIdentifier"),
            identifier: str(e, "AXIdentifier"),
            classList: str(e, "AXDOMClassList"))
        let english = FieldRules.isEnglish(f)
        keyLog.debug("칸: role=\(f.role ?? "-", privacy: .public) sub=\(f.subrole ?? "-", privacy: .public) → \(english ? "영문" : "그대로", privacy: .public)")
        return english
    }

    private static func str(_ e: AXUIElement, _ name: String) -> String? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success, let v = v else { return nil }
        if let s = v as? String { return s.isEmpty ? nil : s }
        if let a = v as? [String] { return a.joined(separator: " ") }
        return nil
    }
}

/// 보안 입력(비밀번호 칸 등)이 켜져 있으면 맥이 모든 입력기를 막는다. 안 풀렸을 때 누가 쥐고 있는지 알려준다.
enum SecureInput {
    static var holder: NSRunningApplication? {
        guard IsSecureEventInputEnabled() else { return nil }
        let root = IORegistryEntryFromPath(kIOMainPortDefault, "IOService:/")
        guard root != 0 else { return nil }
        defer { IOObjectRelease(root) }
        guard let users = IORegistryEntryCreateCFProperty(root, "IOConsoleUsers" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [[String: Any]] else { return nil }
        for u in users {
            if let pid = u["kCGSSessionSecureInputPID"] as? Int, pid > 0 {
                return NSRunningApplication(processIdentifier: pid_t(pid))
            }
        }
        return nil
    }
}
