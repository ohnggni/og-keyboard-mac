import Cocoa
import Carbon
import IOKit.hid
import ApplicationServices

/// F1: 권한·설정 점검. 빠진 권한을 보여주고 맥 설정의 해당 화면으로 바로 보낸다.
/// 개발자 서명이 없어 업데이트마다 권한이 풀리는 문제(O2)도 여기서 '초기화 후 다시 요청'으로 사용자가 직접 고칠 수 있다.
enum Permissions {
    enum State { case ok, missing, unknown }

    struct Item {
        let title: String
        let detail: String       // 무엇에 쓰는지 / 없으면 어떻게 되는지
        let state: State
        let required: Bool       // 필수(빨강 경고) / 권장
        let settingsURL: String
    }

    static let bundleID = Bundle.main.bundleIdentifier ?? "kr.ogapp.inputmethod.OGKeyboard"

    static var accessibility: Bool { AXIsProcessTrusted() }
    static var inputMonitoring: Bool { IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted }

    /// 입력 소스 목록에 OG키보드가 켜져 있는지
    static var inputSourceEnabled: Bool {
        let filter = [kTISPropertyBundleID as String: bundleID] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource] else { return false }
        return list.contains { s in
            guard let v = TISGetInputSourceProperty(s, kTISPropertyInputSourceIsEnabled) else { return false }
            return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(v).takeUnretainedValue())
        }
    }

    /// 시스템 설정 'Caps Lock으로 라틴 입력 소스 전환' (켜져 있으면 Caps Lock 한/영과 충돌). 읽을 수 없으면 nil
    static var capsSwitchesLatin: Bool? {
        guard let v = UserDefaults(suiteName: "com.apple.HIToolbox")?.object(forKey: "TISRomanSwitchState") as? Int else { return nil }
        return v != 0
    }

    /// 꼭 필요한 권한이 다 있는지 (메뉴 경고·자동 안내 기준)
    static var allRequiredGranted: Bool { accessibility && inputMonitoring && inputSourceEnabled }

    static let accessibilityURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    static let inputMonitoringURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
    static let keyboardURL = "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"

    static var items: [Item] {
        let caps = capsSwitchesLatin
        return [
            Item(title: "손쉬운 사용",
                 detail: "영문·숫자 칸 자동 영문, 클릭·앱 전환 때 마지막 글자 지키기, 터미널의 한자·바로잡기에 씁니다. 없으면 이 기능들이 동작하지 않습니다.",
                 state: accessibility ? .ok : .missing, required: true, settingsURL: accessibilityURL),
            Item(title: "입력 모니터링",
                 detail: "Caps Lock 한/영 전환에 씁니다 (누른 시간을 재기 위해). 없으면 Caps Lock 한/영이 동작하지 않습니다.",
                 state: inputMonitoring ? .ok : .missing, required: true, settingsURL: inputMonitoringURL),
            Item(title: "입력 소스에 OG키보드 추가",
                 detail: "키보드 → 입력 소스 → 편집 → + → 한국어 → OG키보드. 목록에 없으면 로그아웃 후 다시 로그인하십시오.",
                 state: inputSourceEnabled ? .ok : .missing, required: true, settingsURL: keyboardURL),
            Item(title: "'Caps Lock으로 라틴 입력 소스 전환' 끄기",
                 detail: "키보드 → 입력 소스 → 편집 화면에 있습니다. 켜져 있으면 맥이 Caps Lock을 가로채 순정 입력기로 바꿉니다.",
                 state: caps == nil ? .unknown : (caps! ? .missing : .ok), required: false, settingsURL: keyboardURL),
        ]
    }

    /// 업데이트 뒤 권한이 풀렸을 때: 목록의 OGKeyboard 항목을 지우고(tccutil reset) 다시 요청한다
    static func resetAndRequest(completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            var ok = true
            for service in ["Accessibility", "ListenEvent"] {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
                p.arguments = ["reset", service, bundleID]
                do { try p.run(); p.waitUntilExit(); ok = ok && p.terminationStatus == 0 } catch { ok = false }
            }
            DispatchQueue.main.async {
                keyLog.info("권한 초기화 \(ok ? "성공" : "실패", privacy: .public)")
                requestAll()
                completion(ok)
            }
        }
    }

    /// 두 권한 요청 창을 띄운다 (이미 있으면 아무 일 없음)
    static func requestAll() {
        let opt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opt)
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    static func open(_ url: String) {
        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
    }

    /// 권한을 켠 뒤 적용: 입력기를 끝내면 다음 글자를 칠 때 맥이 다시 띄운다
    static func restartInputMethod() {
        keyLog.info("입력기 다시 시작")
        InputController.active?.commit(nil)
        exit(0)
    }
}

/// 권한·설정 점검 창 (1초마다 상태를 다시 읽어 바로 반영)
final class PermissionWindow: NSObject, NSWindowDelegate {
    static let shared = PermissionWindow()

    private var window: NSWindow?
    private let rows = NSStackView()
    private var timer: Timer?
    private var lastSignature = ""
    /// 창을 연 뒤 빠져 있던 필수 권한이 켜졌는지 (켜졌으면 '다시 시작' 안내를 강조)
    private var openedWithMissing = false
    private let note = NSTextField(wrappingLabelWithString: "")

    func show() {
        let w = window ?? makeWindow()
        openedWithMissing = !Permissions.allRequiredGranted
        lastSignature = ""
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    /// 처음 설치·업데이트 직후 필수 권한이 빠져 있으면 한 번 자동으로 연다 (빌드마다 한 번)
    static func showIfNeededAfterLaunch() {
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let key = "permissionPromptBuild"
        guard !Permissions.allRequiredGranted, UserDefaults.standard.string(forKey: key) != build else { return }
        UserDefaults.standard.set(build, forKey: key)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { shared.show() }
    }

    func windowWillClose(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
    }

    // MARK: 그리기

    private func makeWindow() -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "OG키보드 — 권한 및 설정 점검"
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.center()

        let title = NSTextField(labelWithString: "OG키보드가 제대로 동작하려면 아래 항목이 모두 ✅ 여야 합니다.")
        title.font = .systemFont(ofSize: 13, weight: .semibold)

        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 10

        let troubleTitle = NSTextField(labelWithString: "켜져 있는데도 안 될 때 (업데이트 직후 등)")
        troubleTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        let troubleText = NSTextField(wrappingLabelWithString:
            "업데이트하면 맥이 OG키보드를 다른 앱으로 보고 권한을 무시할 수 있습니다. "
            + "'권한 초기화 후 다시 요청'을 누르면 목록의 OG키보드 항목을 지우고 다시 요청합니다. "
            + "설정에서 다시 켠 뒤 '입력기 다시 시작'을 누르십시오.")
        troubleText.font = .systemFont(ofSize: 12)
        troubleText.textColor = .secondaryLabelColor

        let reset = NSButton(title: "권한 초기화 후 다시 요청", target: self, action: #selector(resetPermissions))
        let restart = NSButton(title: "입력기 다시 시작", target: self, action: #selector(restartIM))
        let buttons = NSStackView(views: [reset, restart])
        buttons.spacing = 8

        note.font = .systemFont(ofSize: 12, weight: .medium)
        note.textColor = ModeIndicator.blue

        let stack = NSStackView(views: [title, rows, separator(), troubleTitle, troubleText, buttons, note])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 18, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        for v in [rows, troubleText, note] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            v.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40).isActive = true
        }

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor),
        ])
        w.contentView = content
        window = w
        return w
    }

    private func separator() -> NSView {
        let b = NSBox()
        b.boxType = .separator
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: 520).isActive = true
        return b
    }

    private func refresh() {
        let items = Permissions.items
        let sig = items.map { "\($0.state)" }.joined()
        if sig != lastSignature {
            lastSignature = sig
            rows.arrangedSubviews.forEach { $0.removeFromSuperview() }
            for it in items { rows.addArrangedSubview(row(it)) }
            StatusBar.shared.update()
        }
        if openedWithMissing && Permissions.allRequiredGranted {
            note.stringValue = "✅ 필수 권한이 모두 켜졌습니다. '입력기 다시 시작'을 눌러 적용하십시오."
        } else if !Permissions.allRequiredGranted {
            note.stringValue = ""
        }
    }

    private func row(_ it: Permissions.Item) -> NSView {
        let symbol: String, color: NSColor
        switch it.state {
        case .ok: symbol = "checkmark.circle.fill"; color = .systemGreen
        case .missing: symbol = it.required ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill"
                       color = it.required ? .systemRed : .systemOrange
        case .unknown: symbol = "questionmark.circle"; color = .secondaryLabelColor
        }
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = color
        icon.symbolConfiguration = .init(pointSize: 18, weight: .regular)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 24).isActive = true

        let suffix = it.state == .unknown ? " (직접 확인)" : (it.required ? "" : " (권장)")
        let title = NSTextField(labelWithString: it.title + suffix)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        let detail = NSTextField(wrappingLabelWithString: it.detail)
        detail.font = .systemFont(ofSize: 11.5)
        detail.textColor = .secondaryLabelColor
        detail.translatesAutoresizingMaskIntoConstraints = false
        detail.widthAnchor.constraint(equalToConstant: 360).isActive = true
        let text = NSStackView(views: [title, detail])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2

        let button = NSButton(title: "설정 열기", target: self, action: #selector(openSetting(_:)))
        button.identifier = NSUserInterfaceItemIdentifier(it.settingsURL)
        button.isHidden = it.state == .ok

        let h = NSStackView(views: [icon, text, NSView(), button])
        h.orientation = .horizontal
        h.alignment = .top
        h.spacing = 10
        return h
    }

    // MARK: 동작

    @objc private func openSetting(_ sender: NSButton) {
        guard let url = sender.identifier?.rawValue else { return }
        // 권한 항목은 요청도 함께 보내 목록에 OGKeyboard가 나타나게 한다
        if url == Permissions.accessibilityURL || url == Permissions.inputMonitoringURL { Permissions.requestAll() }
        Permissions.open(url)
    }

    @objc private func resetPermissions() {
        note.stringValue = "초기화하는 중…"
        Permissions.resetAndRequest { [weak self] ok in
            self?.note.stringValue = ok
                ? "목록의 OG키보드 항목을 지우고 다시 요청했습니다. 설정에서 두 권한을 켠 뒤 '입력기 다시 시작'을 누르십시오."
                : "초기화하지 못했습니다. 설정에서 OGKeyboard를 −로 지우고 +로 다시 추가하십시오 (~/Library/Input Methods/OGKeyboard.app)."
            self?.openedWithMissing = true
            Permissions.open(Permissions.accessibilityURL)
        }
    }

    @objc private func restartIM() {
        Permissions.restartInputMethod()
    }
}
