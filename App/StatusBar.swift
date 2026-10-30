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
        let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let about = NSMenuItem(title: "OG키보드 \(ver)", action: nil, keyEquivalent: "")
        about.isEnabled = false
        menu.addItem(about)
        return menu
    }

    private func refreshChecks(_ menu: NSMenu) {
        for mi in menu.items {
            guard let id = mi.representedObject as? String else { continue }
            mi.state = id == ModeState.layout.id ? .on : .off
        }
    }

    @objc private func selectLayout(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        ModeState.layout = Layouts.byId(id)
    }
}
