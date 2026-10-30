import Cocoa

/// 메뉴바 아이콘: 작은 'OG' + 지금 상태('가' / 'A', 대문자 고정이면 꽉 찬 칸의 'A') + 메뉴
final class StatusBar: NSObject {
    static let shared = StatusBar()

    private var item: NSStatusItem?

    func setup() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.menu = makeMenu()
        self.item = item
        update()
    }

    /// 한/영·자판·대문자 고정이 바뀔 때마다 호출
    func update() {
        guard let button = item?.button else { return }
        let caps = CapsLock.isOn
        button.title = ""
        button.image = Self.icon(hangul: ModeState.hangul, caps: caps)
        let state = caps ? "대문자 고정" : (ModeState.hangul ? "한글" : "영문")
        button.toolTip = "OG키보드 — \(state) · \(ModeState.layout.name)"
    }

    /// 템플릿 이미지(흑백)라 밝은·어두운 메뉴바에 맞춰 시스템이 색을 바꾼다
    static func icon(hangul: Bool, caps: Bool) -> NSImage {
        let og = NSAttributedString(string: "OG", attributes: [
            .font: NSFont.systemFont(ofSize: 7.5, weight: .semibold),
            .foregroundColor: NSColor.black.withAlphaComponent(0.65),
        ])
        let glyph = NSAttributedString(string: (hangul && !caps) ? "가" : "A", attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.black,
        ])
        let ogSize = og.size(), gSize = glyph.size()
        let h: CGFloat = 16, gap: CGFloat = 1.5
        let boxW = max(gSize.width + 5, 15)
        let width = ceil(ogSize.width + gap + (caps ? boxW : gSize.width))
        let image = NSImage(size: NSSize(width: width, height: h), flipped: false) { _ in
            og.draw(at: NSPoint(x: 0, y: (h - ogSize.height) / 2 - 1))
            let x = ogSize.width + gap
            if caps {
                // 꽉 찬 칸에 'A'를 뚫어서 그림
                let box = NSRect(x: x, y: 0.5, width: boxW, height: h - 1)
                NSColor.black.setFill()
                NSBezierPath(roundedRect: box, xRadius: 3, yRadius: 3).fill()
                let ctx = NSGraphicsContext.current?.cgContext
                ctx?.saveGState()
                ctx?.setBlendMode(.destinationOut)
                glyph.draw(at: NSPoint(x: box.midX - gSize.width / 2, y: box.midY - gSize.height / 2))
                ctx?.restoreGState()
            } else {
                glyph.draw(at: NSPoint(x: x, y: (h - gSize.height) / 2))
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    // MARK: 메뉴

    private enum Tag {
        static let remember = 1, terminal = 2, clipOn = 3, fallback = 4, keepBase = 100
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        let header = NSMenuItem(title: "자판", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for layout in Layouts.all {
            let mi = item("  " + layout.name, #selector(selectLayout(_:)))
            mi.representedObject = layout.id
            menu.addItem(mi)
        }
        menu.addItem(.separator())
        menu.addItem(item("앱별 한/영 기억", #selector(toggleRemember), tag: Tag.remember))
        menu.addItem(item("앱별 기억 지우기", #selector(clearRemember)))
        menu.addItem(item("지금 앱을 터미널처럼 다루기", #selector(toggleTerminal), tag: Tag.terminal))
        menu.addItem(item("지금 앱에서는 순정 입력기 쓰기", #selector(toggleFallback), tag: Tag.fallback))
        menu.addItem(.separator())
        menu.addItem(item("텍스트 단축어…", #selector(openShortcuts)))

        let clip = NSMenuItem(title: "클립보드 기록 (Ctrl+Option+V)", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        sub.delegate = self
        sub.addItem(item("기록하기", #selector(toggleClip), tag: Tag.clipOn))
        sub.addItem(.separator())
        for (i, (name, _)) in ClipboardHistory.keepOptions.enumerated() {
            sub.addItem(item("보관: \(name)", #selector(setClipKeep(_:)), tag: Tag.keepBase + i))
        }
        sub.addItem(.separator())
        sub.addItem(item("기록 지우기", #selector(clearClips)))
        clip.submenu = sub
        menu.addItem(clip)

        menu.addItem(.separator())
        menu.addItem(item("사용법…", #selector(openHelp)))
        menu.addItem(item("OG키보드 정보…", #selector(openAbout)))
        return menu
    }

    private func item(_ title: String, _ action: Selector, tag: Int = 0) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: "")
        mi.target = self
        mi.tag = tag
        return mi
    }

    /// 메뉴를 열 때 앞에 있는 앱 (메뉴바를 눌러도 앞 앱은 그대로)
    private var frontApp: String {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ModeState.currentApp ?? ""
    }

    private func refreshChecks(_ menu: NSMenu) {
        let app = frontApp
        for mi in menu.items {
            switch mi.tag {
            case Tag.remember: mi.state = ModeState.rememberPerApp ? .on : .off
            case Tag.clipOn: mi.state = ClipboardHistory.shared.enabled ? .on : .off
            case Tag.terminal:
                mi.isEnabled = !app.isEmpty && !Terminals.bundleIDs.contains(app)
                mi.state = Terminals.contains(app) ? .on : .off
            case Tag.fallback:
                mi.isEnabled = !app.isEmpty
                mi.state = Fallback.apps.contains(app) ? .on : .off
            case let t where t >= Tag.keepBase:
                mi.state = ClipboardHistory.keepOptions[t - Tag.keepBase].1 == ClipboardHistory.shared.keep ? .on : .off
            default:
                if let id = mi.representedObject as? String { mi.state = id == ModeState.layout.id ? .on : .off }
            }
        }
    }

    // MARK: 동작

    @objc private func selectLayout(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        ModeState.layout = Layouts.byId(id)
    }

    @objc private func toggleRemember() { ModeState.rememberPerApp.toggle() }
    @objc private func clearRemember() { ModeState.clearAppModes() }

    @objc private func toggleTerminal() {
        let app = frontApp
        guard !app.isEmpty else { return }
        var ids = Terminals.userIDs
        if ids.contains(app) { ids.remove(app) } else { ids.insert(app) }
        Terminals.userIDs = ids
    }

    @objc private func toggleFallback() {
        let app = frontApp
        guard !app.isEmpty else { return }
        Fallback.toggle(app)
    }

    @objc private func openShortcuts() { ShortcutsWindow.shared.show() }
    @objc private func toggleClip() { ClipboardHistory.shared.enabled.toggle() }
    @objc private func clearClips() { ClipboardHistory.shared.clear() }
    @objc private func setClipKeep(_ sender: NSMenuItem) {
        ClipboardHistory.shared.keep = ClipboardHistory.keepOptions[sender.tag - Tag.keepBase].1
    }
    @objc private func openHelp() { HelpWindow.shared.show() }
    @objc private func openAbout() { HelpWindow.shared.showAbout() }
}

extension StatusBar: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshChecks(menu)
    }
}
