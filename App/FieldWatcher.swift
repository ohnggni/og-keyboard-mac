import Cocoa
import Carbon
import ApplicationServices

/// 로그인 칸 자동 영문: 아이디·이메일·비밀번호 칸에 들어가면 영문으로, 나오면 원래대로.
/// 손쉬운 사용 정보로 지금 포커스된 칸을 알아본다 (권한 필요). 주소창·검색창은 건드리지 않는다.
enum FieldWatcher {
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "autoEnglishFields") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "autoEnglishFields")
            if !newValue, autoSwitched { restore() }
            watch(NSWorkspace.shared.frontmostApplication)
        }
    }

    private static var observer: AXObserver?
    private static var inEnglishField = false
    /// 우리가 영문으로 바꿔 둔 상태인지, 어느 앱에서였는지
    private static var autoSwitched = false
    private static var switchedApp: String?

    /// 크롬 계열은 이 값을 켜야 웹페이지 입력칸 정보를 넘겨준다
    private static let chromium: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.microsoft.edgemac", "com.brave.Browser",
        "com.naver.Whale", "company.thebrowser.Browser", "com.vivaldi.Vivaldi", "org.chromium.Chromium",
    ]
    private static var manualEnabled = Set<pid_t>()

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
        guard enabled, AXIsProcessTrusted(), let app = app,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        let pid = app.processIdentifier
        let axApp = AXUIElementCreateApplication(pid)
        if let id = app.bundleIdentifier, chromium.contains(id), !manualEnabled.contains(pid) {
            AXUIElementSetAttributeValue(axApp, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            manualEnabled.insert(pid)
        }
        var obs: AXObserver?
        guard AXObserverCreate(pid, { _, element, _, _ in FieldWatcher.focusChanged(element) }, &obs) == .success,
              let o = obs else { return }
        AXObserverAddNotification(o, axApp, kAXFocusedUIElementChangedNotification as CFString, nil)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(o), .defaultMode)
        observer = o
        // 지금 포커스된 칸도 바로 확인
        var f: CFTypeRef?
        if AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &f) == .success, let f = f {
            focusChanged(f as! AXUIElement)
        }
    }

    private static func focusChanged(_ e: AXUIElement) {
        guard enabled, InputSources.ogIsCurrent else { return }
        let english = isEnglishField(e)
        if english && !inEnglishField {
            inEnglishField = true
            if ModeState.hangul {
                InputController.active?.commit(nil)
                ModeState.setTransient(hangul: false)
                autoSwitched = true
                switchedApp = ModeState.currentApp
                ModeIndicator.shared.show(hangul: false)
                keyLog.info("로그인 칸 → 영문")
            }
        } else if !english && inEnglishField {
            inEnglishField = false
            if autoSwitched { restore() }
        }
    }

    /// 칸을 나가면 한글로 되돌린다 (칸 안에서 직접 한글로 바꿨으면 이미 한글이라 그대로)
    private static func restore() {
        autoSwitched = false
        if !ModeState.hangul {
            ModeState.setTransient(hangul: true)
            ModeIndicator.shared.show(hangul: true)
            keyLog.info("로그인 칸 나감 → 한글")
        }
    }

    /// 앱이 바뀔 때: 새 앱의 한/영은 앱별 기억이 정한다. 기억이 없으면 원래(한글)로.
    private static func leaveOnAppChange() {
        inEnglishField = false
        guard autoSwitched else { return }
        autoSwitched = false
        let now = ModeState.currentApp
        if now == switchedApp || !ModeState.hasSaved(now) {
            if !ModeState.hangul { ModeState.setTransient(hangul: true) }
        }
    }

    // MARK: 칸 알아보기

    private static let koreanWords = ["이메일", "메일", "아이디", "비밀번호", "계정", "사용자 이름"]
    private static let englishWords = ["email", "e-mail", "password", "passwd", "username", "user name", "login", "account"]
    private static let tokens: Set<String> = ["id", "pw", "uid", "userid", "loginid", "email", "mail", "account", "passwd", "password", "login", "username"]

    static func isEnglishField(_ e: AXUIElement) -> Bool {
        let sub = str(e, kAXSubroleAttribute as String)
        if sub == "AXSecureTextField" { return true }
        guard str(e, kAXRoleAttribute as String) == "AXTextField", sub != "AXSearchField" else { return false }
        let ident = str(e, "AXIdentifier") ?? ""
        let cls = str(e, "AXDOMClassList") ?? ""
        if ident.contains("ADDRESS") || ident.contains("SEARCH") || cls.contains("Omnibox") { return false }

        var label = ""
        var t: CFTypeRef?
        if AXUIElementCopyAttributeValue(e, "AXTitleUIElement" as CFString, &t) == .success, let te = t {
            label = str(te as! AXUIElement, "AXValue") ?? str(te as! AXUIElement, "AXTitle") ?? ""
        }
        let text = [str(e, "AXTitle"), str(e, "AXDescription"), str(e, "AXPlaceholderValue"), label]
            .compactMap { $0 }.joined(separator: " ").lowercased()
        if text.contains("검색") || text.contains("search") { return false }
        if koreanWords.contains(where: text.contains) || englishWords.contains(where: text.contains) { return true }
        let words = (text + " " + (str(e, "AXDOMIdentifier") ?? "").lowercased())
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        return words.contains(where: tokens.contains)
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
