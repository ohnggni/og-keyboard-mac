import Cocoa

/// 한자·기호·이모지 후보 창. 한 쪽에 9개, 숫자키·화살표·클릭으로 고른다. (안드판 HanjaPopup과 같은 모양)
final class CandidatePanel {
    static let shared = CandidatePanel()
    static let pageSize = 9

    /// 클릭으로 고르면 불림 (전체 목록 기준 번호)
    var onPick: ((Int) -> Void)?

    private var panel: NSPanel?
    private let stack = NSStackView()

    private let bg = NSColor(srgbRed: 0.118, green: 0.122, blue: 0.137, alpha: 1)
    private let highlight = NSColor(srgbRed: 0.231, green: 0.510, blue: 0.965, alpha: 1)
    private let dim = NSColor(srgbRed: 0.612, green: 0.639, blue: 0.686, alpha: 1)

    var isVisible: Bool { panel?.isVisible ?? false }

    /// 후보를 그린다. caret: 커서 위치(화면 좌표, 없으면 nil → 화면 아래 가운데)
    func show(title: String, items: [HanjaEntry], selected: Int, caret: NSRect?) {
        let panel = self.panel ?? makePanel()
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let page = selected / Self.pageSize
        let pages = (items.count + Self.pageSize - 1) / Self.pageSize
        let header = label("\(title)  \(page + 1)/\(pages)   1–9 / Space 선택 · ← → 쪽 · Esc", size: 11, color: dim)
        stack.addArrangedSubview(header)
        stack.setCustomSpacing(6, after: header)

        let start = page * Self.pageSize
        for i in start..<min(items.count, start + Self.pageSize) {
            stack.addArrangedSubview(row(items[i], number: i - start + 1, index: i, selected: i == selected))
        }

        let size = stack.fittingSize
        let frame = NSRect(origin: origin(for: size, caret: caret), size: size)
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    // MARK: 그리기

    private func row(_ e: HanjaEntry, number: Int, index: Int, selected: Bool) -> NSView {
        let num = label("\(number)", size: 12, color: dim)
        num.widthAnchor.constraint(equalToConstant: 16).isActive = true
        let main = label(e.text, size: 20, color: .white)
        let isJamoKey = e.key.count == 1 && e.key.first.map(HanjaDict.isCompatConsonant) == true
        let sub = !e.meaning.isEmpty ? e.meaning : (e.emoji || isJamoKey) ? "" : e.key
        let meaning = label(sub, size: 12, color: selected ? NSColor(white: 0.9, alpha: 1) : dim)
        meaning.lineBreakMode = .byTruncatingTail
        meaning.widthAnchor.constraint(lessThanOrEqualToConstant: 260).isActive = true

        let h = NSStackView(views: [num, main, meaning])
        h.orientation = .horizontal
        h.alignment = .centerY
        h.spacing = 8
        h.edgeInsets = NSEdgeInsets(top: 3, left: 8, bottom: 3, right: 12)
        h.wantsLayer = true
        h.layer?.cornerRadius = 8
        if selected { h.layer?.backgroundColor = highlight.cgColor }

        let click = ClickGesture(target: self, action: #selector(clicked(_:)))
        click.index = index
        h.addGestureRecognizer(click)
        return h
    }

    @objc private func clicked(_ g: ClickGesture) {
        onPick?(g.index)
    }

    private func label(_ s: String, size: CGFloat, color: NSColor) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = .systemFont(ofSize: size)
        l.textColor = color
        return l
    }

    private func origin(for size: NSSize, caret: NSRect?) -> NSPoint {
        let screen = NSScreen.screens.first { s in caret.map { s.frame.contains($0.origin) } ?? false }
            ?? NSScreen.main ?? NSScreen.screens[0]
        let vf = screen.visibleFrame
        guard let c = caret, c.origin != .zero else {
            return NSPoint(x: vf.midX - size.width / 2, y: vf.minY + 80)
        }
        // 커서 아래에, 화면 밖으로 나가면 위로
        var x = c.minX
        var y = c.minY - size.height - 4
        if y < vf.minY { y = c.maxY + 4 }
        x = min(max(x, vf.minX), vf.maxX - size.width)
        y = min(max(y, vf.minY), vf.maxY - size.height)
        return NSPoint(x: x, y: y)
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
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
        stack.spacing = 0
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

private final class ClickGesture: NSClickGestureRecognizer {
    var index = 0
}
