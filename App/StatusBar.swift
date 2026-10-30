import Cocoa

/// 메뉴바 아이콘: 현재 한/영 상태('가' / 'A') + 메뉴(자판 선택 등)
final class StatusBar: NSObject {
    static let shared = StatusBar()

    private var item: NSStatusItem?

    func setup() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.menu = makeMenu()
        self.item = item
        update()
    }

    /// 한/영·자판이 바뀔 때마다 호출
    func update() {
        guard let button = item?.button else { return }
        button.title = ModeState.hangul ? "가" : "A"
        button.font = .systemFont(ofSize: 14, weight: .semibold)
        button.toolTip = "OG키보드 — \(ModeState.hangul ? "한글" : "영문") · \(ModeState.layout.name)"
        if let menu = item?.menu { refreshChecks(menu) }
    }

    // MARK: 메뉴

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        let header = NSMenuItem(title: "자판", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for layout in Layouts.all {
            let mi = NSMenuItem(title: layout.name, action: #selector(selectLayout(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = layout.id
            menu.addItem(mi)
        }
        menu.addItem(.separator())
        let remember = NSMenuItem(title: "앱별 한/영 기억", action: #selector(toggleRemember), keyEquivalent: "")
        remember.target = self
        remember.tag = 1
        menu.addItem(remember)
        let clear = NSMenuItem(title: "앱별 기억 지우기", action: #selector(clearRemember), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
        let term = NSMenuItem(title: "지금 앱을 터미널처럼 다루기", action: #selector(toggleTerminal), keyEquivalent: "")
        term.target = self
        term.tag = 2
        menu.addItem(term)
        menu.addItem(.separator())
        let sc = NSMenuItem(title: "텍스트 단축어…", action: #selector(openShortcuts), keyEquivalent: "")
        sc.target = self
        menu.addItem(sc)
        let clip = NSMenuItem(title: "클립보드 기록 (Ctrl+Option+V)", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        let on = NSMenuItem(title: "기록하기", action: #selector(toggleClip), keyEquivalent: "")
        on.target = self
        on.tag = 3
        sub.addItem(on)
        sub.addItem(.separator())
        for (i, (name, _)) in ClipboardHistory.keepOptions.enumerated() {
            let k = NSMenuItem(title: "보관: \(name)", action: #selector(setClipKeep(_:)), keyEquivalent: "")
            k.target = self
            k.tag = 100 + i
            sub.addItem(k)
        }
        sub.addItem(.separator())
        let wipe = NSMenuItem(title: "기록 지우기", action: #selector(clearClips), keyEquivalent: "")
        wipe.target = self
        sub.addItem(wipe)
        sub.delegate = self
        clip.submenu = sub
        menu.addItem(clip)
        menu.addItem(.separator())
        let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let about = NSMenuItem(title: "OG키보드 \(ver)", action: nil, keyEquivalent: "")
        about.isEnabled = false
        menu.addItem(about)
        return menu
    }

    private func refreshChecks(_ menu: NSMenu) {
        for mi in menu.items {
            if mi.tag == 1 { mi.state = ModeState.rememberPerApp ? .on : .off; continue }
            if mi.tag == 3 { mi.state = ClipboardHistory.shared.enabled ? .on : .off; continue }
            if mi.tag >= 100 {
                mi.state = ClipboardHistory.keepOptions[mi.tag - 100].1 == ClipboardHistory.shared.keep ? .on : .off
                continue
            }
            if mi.tag == 2 {
                let app = ModeState.currentApp ?? ""
                mi.isEnabled = !app.isEmpty && !Terminals.bundleIDs.contains(app)
                mi.state = Terminals.contains(app) ? .on : .off
                continue
            }
            guard let id = mi.representedObject as? String else { continue }
            mi.state = id == ModeState.layout.id ? .on : .off
        }
    }

    @objc private func toggleRemember() {
        ModeState.rememberPerApp.toggle()
    }

    @objc private func toggleClip() { ClipboardHistory.shared.enabled.toggle() }
    @objc private func clearClips() { ClipboardHistory.shared.clear() }
    @objc private func setClipKeep(_ sender: NSMenuItem) {
        ClipboardHistory.shared.keep = ClipboardHistory.keepOptions[sender.tag - 100].1
    }

    @objc private func openShortcuts() {
        ShortcutsWindow.shared.show()
    }

    @objc private func toggleTerminal() {
        guard let app = ModeState.currentApp else { return }
        var ids = Terminals.userIDs
        if ids.contains(app) { ids.remove(app) } else { ids.insert(app) }
        Terminals.userIDs = ids
        update()
    }

    @objc private func clearRemember() {
        ModeState.clearAppModes()
    }

    @objc private func selectLayout(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        ModeState.layout = Layouts.byId(id)
    }
}

extension StatusBar: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshChecks(menu)
    }
}
