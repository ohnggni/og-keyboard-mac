import Cocoa

/// 이모지 분류 데이터 (안드판 emoji_groups.txt: 분류이름 ⇥ 이모지|이름 ⇥ …)
struct EmojiGroup {
    let name: String
    let items: [(emoji: String, name: String)]
}

enum EmojiData {
    static let groups: [EmojiGroup] = {
        guard let url = Bundle.main.url(forResource: "emoji_groups", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            let cells = line.split(separator: "\t").map(String.init)
            guard cells.count > 1 else { return nil }
            let items = cells.dropFirst().compactMap { c -> (emoji: String, name: String)? in
                let p = c.split(separator: "|", maxSplits: 1).map(String.init)
                guard let e = p.first, !e.isEmpty else { return nil }
                return (emoji: e, name: p.count > 1 ? p[1] : "")
            }
            return EmojiGroup(name: cells[0], items: items)
        }
    }()

    private static let names: [String: String] = {
        var d: [String: String] = [:]
        for g in groups { for i in g.items where d[i.emoji] == nil { d[i.emoji] = i.name } }
        return d
    }()

    static var recent: [String] {
        UserDefaults.standard.stringArray(forKey: "recentEmoji") ?? []
    }

    static func addRecent(_ e: String) {
        var r = recent.filter { $0 != e }
        r.insert(e, at: 0)
        UserDefaults.standard.set(Array(r.prefix(32)), forKey: "recentEmoji")
    }

    /// 창에 보일 분류들: 최근 쓴 것이 있으면 맨 앞에 '최근'
    static var tabs: [EmojiGroup] {
        let r = recent
        let recentGroup = EmojiGroup(name: "최근", items: r.map { (emoji: $0, name: names[$0] ?? "") })
        return (r.isEmpty ? [] : [recentGroup]) + groups
    }
}

/// 이모지 전체 창: 분류 탭 + 8×5 격자 (안드판 EmojiPanel과 같은 배치)
final class EmojiPanel {
    static let shared = EmojiPanel()
    static let cols = 8, rows = 5, page = cols * rows

    var onPick: ((String) -> Void)?
    var onGroup: ((Int) -> Void)?

    private var panel: NSPanel?
    private let stack = NSStackView()
    private let bg = NSColor(srgbRed: 0.118, green: 0.122, blue: 0.137, alpha: 1)
    private let highlight = NSColor(srgbRed: 0.231, green: 0.510, blue: 0.965, alpha: 1)
    private let dim = NSColor(srgbRed: 0.612, green: 0.639, blue: 0.686, alpha: 1)

    func show(tabs: [EmojiGroup], group: Int, selected: Int, caret: NSRect?) {
        let panel = self.panel ?? makePanel()
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard group < tabs.count else { return }
        let g = tabs[group]
        let pages = max(1, (g.items.count + Self.page - 1) / Self.page)
        let pageNo = selected / Self.page

        let header = label("\(g.name)  \(pageNo + 1)/\(pages)   방향키 이동 · Tab 분류 · Enter 넣기 · Esc", size: 11, color: dim)
        stack.addArrangedSubview(header)

        // 분류 탭
        let tabRow = NSStackView()
        tabRow.orientation = .horizontal
        tabRow.spacing = 4
        for (i, t) in tabs.enumerated() {
            let l = label(t.name, size: 12, color: i == group ? .white : dim)
            let box = wrap(l, selected: i == group, inset: NSEdgeInsets(top: 3, left: 7, bottom: 3, right: 7))
            let click = IndexClick(target: self, action: #selector(tabClicked(_:)))
            click.index = i
            box.addGestureRecognizer(click)
            tabRow.addArrangedSubview(box)
        }
        stack.addArrangedSubview(tabRow)

        // 격자
        let start = pageNo * Self.page
        for r in 0..<Self.rows {
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 2
            for c in 0..<Self.cols {
                let i = start + r * Self.cols + c
                let cell: NSView
                if i < g.items.count {
                    let l = label(g.items[i].emoji, size: 22, color: .white)
                    l.alignment = .center
                    let box = wrap(l, selected: i == selected, inset: NSEdgeInsets(top: 2, left: 4, bottom: 2, right: 4))
                    let click = IndexClick(target: self, action: #selector(cellClicked(_:)))
                    click.index = i
                    click.emoji = g.items[i].emoji
                    box.addGestureRecognizer(click)
                    cell = box
                } else {
                    cell = NSView()
                }
                cell.translatesAutoresizingMaskIntoConstraints = false
                cell.widthAnchor.constraint(equalToConstant: 38).isActive = true
                cell.heightAnchor.constraint(equalToConstant: 36).isActive = true
                row.addArrangedSubview(cell)
            }
            stack.addArrangedSubview(row)
            if start + (r + 1) * Self.cols >= g.items.count { break }
        }

        let name = selected < g.items.count ? g.items[selected].name : ""
        stack.addArrangedSubview(label(name.isEmpty ? " " : name, size: 12, color: dim))

        let size = stack.fittingSize
        panel.setFrame(NSRect(origin: origin(for: size, caret: caret), size: size), display: true)
        panel.orderFrontRegardless()
    }

    func hide() { panel?.orderOut(nil) }

    @objc private func cellClicked(_ g: IndexClick) { if let e = g.emoji { onPick?(e) } }
    @objc private func tabClicked(_ g: IndexClick) { onGroup?(g.index) }

    // MARK: 그리기

    private func label(_ s: String, size: CGFloat, color: NSColor) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = .systemFont(ofSize: size)
        l.textColor = color
        return l
    }

    private func wrap(_ v: NSView, selected: Bool, inset: NSEdgeInsets) -> NSView {
        let s = NSStackView(views: [v])
        s.edgeInsets = inset
        s.wantsLayer = true
        s.layer?.cornerRadius = 7
        if selected { s.layer?.backgroundColor = highlight.cgColor }
        return s
    }

    private func origin(for size: NSSize, caret: NSRect?) -> NSPoint {
        let screen = NSScreen.screens.first { s in caret.map { s.frame.contains($0.origin) } ?? false }
            ?? NSScreen.main ?? NSScreen.screens[0]
        let vf = screen.visibleFrame
        guard let c = caret, c.origin != .zero else {
            return NSPoint(x: vf.midX - size.width / 2, y: vf.minY + 80)
        }
        var y = c.minY - size.height - 4
        if y < vf.minY { y = c.maxY + 4 }
        let x = min(max(c.minX, vf.minX), vf.maxX - size.width)
        return NSPoint(x: x, y: min(max(y, vf.minY), vf.maxY - size.height))
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 260),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .popUpMenu
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        p.becomesKeyOnlyIfNeeded = true

        let content = NSView()
        content.wantsLayer = true
        content.layer?.backgroundColor = bg.cgColor
        content.layer?.cornerRadius = 14
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        p.contentView = content
        panel = p
        return p
    }
}

final class IndexClick: NSClickGestureRecognizer {
    var index = 0
    var emoji: String?
}
