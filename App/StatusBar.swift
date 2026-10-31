import Cocoa

/// 메뉴바 아이콘(OG 배지 + 가/A) + 메뉴
final class StatusBar: NSObject {
    static let shared = StatusBar()

    private var item: NSStatusItem?
    private var headerItem: NSMenuItem?

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
        button.toolTip = "OG키보드 — \(Self.stateName(caps: caps)) · \(ModeState.layout.name)"
        if let h = headerItem { fillHeader(h) }
    }

    private static func stateName(caps: Bool) -> String {
        caps ? "대문자 고정" : (ModeState.hangul ? "한글" : "영문")
    }

    // MARK: 메뉴바 아이콘

    /// 템플릿 이미지(흑백): 밝은·어두운 메뉴바에 맞춰 시스템이 색을 바꾼다.
    /// [OG] 작은 배지(글자를 뚫음) + 상태 글자. 대문자 고정이면 상태 글자를 테두리 칸에 넣는다.
    static func icon(hangul: Bool, caps: Bool) -> NSImage {
        let og = NSAttributedString(string: "OG", attributes: [
            .font: NSFont.systemFont(ofSize: 7, weight: .heavy),
            .foregroundColor: NSColor.black,
            .kern: -0.2,
        ])
        let glyph = NSAttributedString(string: (hangul && !caps) ? "가" : "A", attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.black,
        ])
        let h: CGFloat = 16
        let ogSize = og.size(), gSize = glyph.size()
        let badge = NSSize(width: ceil(ogSize.width) + 4, height: 10)
        let gap: CGFloat = 2.5
        let boxW = max(ceil(gSize.width) + 5, 15)
        let width = ceil(badge.width + gap + (caps ? boxW : gSize.width) + 0.5)

        let image = NSImage(size: NSSize(width: width, height: h), flipped: false) { _ in
            let ctx = NSGraphicsContext.current?.cgContext
            // OG 배지: 꽉 찬 알약에 글자를 뚫는다
            let b = NSRect(x: 0, y: (h - badge.height) / 2, width: badge.width, height: badge.height)
            NSColor.black.setFill()
            NSBezierPath(roundedRect: b, xRadius: 2.5, yRadius: 2.5).fill()
            ctx?.saveGState()
            ctx?.setBlendMode(.destinationOut)
            og.draw(at: NSPoint(x: b.midX - ogSize.width / 2, y: b.midY - ogSize.height / 2))
            ctx?.restoreGState()

            let x = badge.width + gap
            if caps {
                let box = NSRect(x: x, y: 1, width: boxW, height: h - 2)
                let path = NSBezierPath(roundedRect: box.insetBy(dx: 0.6, dy: 0.6), xRadius: 3, yRadius: 3)
                path.lineWidth = 1.2
                NSColor.black.setStroke()
                path.stroke()
                glyph.draw(at: NSPoint(x: box.midX - gSize.width / 2, y: box.midY - gSize.height / 2))
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
        static let remember = 1, terminal = 2, clipOn = 3, fallback = 4, appName = 5, autoEnglish = 6, header = 10, secure = 11, keepBase = 100
    }

    private func makeMenu() -> NSMenu {
        let menu = newMenu()

        // 지금 상태 한 줄
        let header = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        header.tag = Tag.header
        headerItem = header
        fillHeader(header)
        menu.addItem(header)
        let secure = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        secure.tag = Tag.secure
        secure.isHidden = true
        menu.addItem(secure)
        menu.addItem(.separator())

        // 자판
        let layouts = newMenu()
        for layout in Layouts.all {
            let mi = item(layout.name, #selector(selectLayout(_:)))
            mi.representedObject = layout.id
            layouts.addItem(mi)
        }
        menu.addItem(sub("자판", symbol: "keyboard", layouts))
        menu.addItem(.separator())

        // 입력 도우미
        menu.addItem(item("텍스트 단축어…", #selector(openShortcuts), symbol: "text.badge.plus"))

        let clip = newMenu()
        clip.addItem(item("기록하기", #selector(toggleClip), tag: Tag.clipOn))
        clip.addItem(.separator())
        clip.addItem(caption("보관 시간"))
        for (i, (name, _)) in ClipboardHistory.keepOptions.enumerated() {
            clip.addItem(item(name, #selector(setClipKeep(_:)), tag: Tag.keepBase + i))
        }
        clip.addItem(.separator())
        clip.addItem(item("기록 지우기", #selector(clearClips), symbol: "trash"))
        let clipItem = sub("클립보드 기록", symbol: "doc.on.clipboard", clip)
        clipItem.attributedTitle = titleWithHint("클립보드 기록", "⌃⌥V")
        menu.addItem(clipItem)
        menu.addItem(.separator())

        // 앱별 설정
        let thisApp = newMenu()
        let name = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        name.tag = Tag.appName
        thisApp.addItem(name)
        thisApp.addItem(.separator())
        thisApp.addItem(item("터미널처럼 다루기", #selector(toggleTerminal), tag: Tag.terminal, symbol: "terminal"))
        thisApp.addItem(item("순정 입력기 쓰기", #selector(toggleFallback), tag: Tag.fallback, symbol: "arrow.uturn.backward.circle"))
        menu.addItem(sub("이 앱에서", symbol: "macwindow", thisApp))

        let memory = newMenu()
        memory.addItem(item("앱마다 마지막 한/영 기억", #selector(toggleRemember), tag: Tag.remember))
        memory.addItem(item("기억 지우기", #selector(clearRemember), symbol: "trash"))
        menu.addItem(sub("앱별 한/영 기억", symbol: "arrow.triangle.2.circlepath", memory))
        menu.addItem(item("로그인 칸에서 자동 영문", #selector(toggleAutoEnglish), tag: Tag.autoEnglish, symbol: "key"))
        menu.addItem(.separator())

        menu.addItem(item("사용법…", #selector(openHelp), symbol: "book"))
        menu.addItem(item("OG키보드 정보…", #selector(openAbout), symbol: "info.circle"))
        return menu
    }

    private func newMenu() -> NSMenu {
        let m = NSMenu()
        m.autoenablesItems = false
        m.delegate = self
        return m
    }

    private func item(_ title: String, _ action: Selector, tag: Int = 0, symbol: String? = nil) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: "")
        mi.target = self
        mi.tag = tag
        if let s = symbol { mi.image = NSImage(systemSymbolName: s, accessibilityDescription: nil) }
        return mi
    }

    private func sub(_ title: String, symbol: String, _ menu: NSMenu) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        mi.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        mi.submenu = menu
        return mi
    }

    /// 회색 작은 글씨 (하위 메뉴 안의 소제목)
    private func caption(_ text: String) -> NSMenuItem {
        let mi = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        mi.isEnabled = false
        mi.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        return mi
    }

    /// "제목   ⌃⌥V" 처럼 오른쪽에 회색 단축키 힌트
    private func titleWithHint(_ title: String, _ hint: String) -> NSAttributedString {
        let s = NSMutableAttributedString(string: title, attributes: [.font: NSFont.menuFont(ofSize: 0)])
        s.append(NSAttributedString(string: "   " + hint, attributes: [
            .font: NSFont.menuFont(ofSize: 0),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]))
        return s
    }

    /// 맨 위 상태 줄: [색 점] 한글 · 세벌식 390
    private func fillHeader(_ mi: NSMenuItem) {
        let caps = CapsLock.isOn
        let color = caps ? ModeIndicator.orange : (ModeState.hangul ? ModeIndicator.blue : ModeIndicator.green)
        let s = NSMutableAttributedString(string: "●  ", attributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: color,
        ])
        s.append(NSAttributedString(string: Self.stateName(caps: caps), attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.labelColor,
        ]))
        s.append(NSAttributedString(string: "  ·  " + ModeState.layout.name, attributes: [
            .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        mi.attributedTitle = s
        mi.isEnabled = true   // 회색으로 흐려지지 않게 (누르면 아무 일 없음)
    }

    /// 메뉴를 연 순간 앞에 있는 앱 (메뉴바를 눌러도 앞 앱은 그대로)
    private var frontApp: NSRunningApplication? { NSWorkspace.shared.frontmostApplication }
    private var frontID: String { frontApp?.bundleIdentifier ?? ModeState.currentApp ?? "" }

    private func refreshChecks(_ menu: NSMenu) {
        let app = frontID
        for mi in menu.items {
            switch mi.tag {
            case Tag.header: fillHeader(mi)
            case Tag.appName:
                mi.isEnabled = false
                mi.attributedTitle = NSAttributedString(string: frontApp?.localizedName ?? "지금 앱", attributes: [
                    .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ])
            case Tag.secure: fillSecure(mi)
            case Tag.autoEnglish: mi.state = FieldWatcher.enabled ? .on : .off
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

    @objc private func toggleAutoEnglish() { FieldWatcher.enabled.toggle() }

    /// 보안 입력이 켜져 있으면 경고 줄을 보여준다 (비밀번호 칸 밖인데 한글이 안 될 때의 원인)
    private func fillSecure(_ mi: NSMenuItem) {
        guard let h = SecureInput.holder else { mi.isHidden = true; return }
        mi.isHidden = false
        mi.isEnabled = true
        let s = NSMutableAttributedString(string: "⚠️  보안 입력 켜짐 · \(h.localizedName ?? "알 수 없는 앱")", attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: ModeIndicator.orange,
        ])
        s.append(NSAttributedString(string: "\n      비밀번호 칸이 아닌데도 한글이 안 되면 이 앱을 종료하십시오", attributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        mi.attributedTitle = s
    }

    @objc private func toggleRemember() { ModeState.rememberPerApp.toggle() }
    @objc private func clearRemember() { ModeState.clearAppModes() }

    @objc private func toggleTerminal() {
        let app = frontID
        guard !app.isEmpty else { return }
        var ids = Terminals.userIDs
        if ids.contains(app) { ids.remove(app) } else { ids.insert(app) }
        Terminals.userIDs = ids
    }

    @objc private func toggleFallback() {
        let app = frontID
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
