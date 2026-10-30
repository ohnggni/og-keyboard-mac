import Cocoa

/// 텍스트 단축어 관리 창: 목록에서 추가·수정·삭제, 고른 줄은 지금 시각으로 펼친 미리보기
final class ShortcutsWindow: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    static let shared = ShortcutsWindow()

    private var window: NSWindow?
    private let table = NSTableView()
    private let preview = NSTextField(wrappingLabelWithString: "")
    private var items: [Shortcut] = []

    func show() {
        items = ShortcutStore.all
        let w = window ?? makeWindow()
        table.reloadData()
        updatePreview()
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    // MARK: 창

    private func makeWindow() -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
                         styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.title = "OG키보드 — 텍스트 단축어"
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.center()

        for (id, title, width) in [("trigger", "이름", 120.0), ("template", "내용", 380.0)] {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            c.title = title
            c.width = width
            c.isEditable = true
            table.addTableColumn(c)
        }
        table.dataSource = self
        table.delegate = self
        table.usesAlternatingRowBackgroundColors = true
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        let add = NSButton(title: "추가", target: self, action: #selector(addRow))
        let remove = NSButton(title: "삭제", target: self, action: #selector(removeRow))
        let reset = NSButton(title: "기본 단축어 다시 넣기", target: self, action: #selector(restoreDefaults))
        let buttons = NSStackView(views: [add, remove, NSView(), reset])
        buttons.orientation = .horizontal

        preview.textColor = .secondaryLabelColor
        let help = NSTextField(wrappingLabelWithString:
            "사용법: 이름을 치고 오른쪽 Option → 후보 맨 위의 단축어를 고르면 내용으로 바뀝니다.\n"
            + "내용에 쓸 수 있는 값: {날짜} {날짜:M월 d일} {시간} {요일} {클립보드} {커서}\n"
            + "날짜 계산: {날짜+1} {날짜-2} {요일+1} {날짜+1주} {날짜+1달} {날짜-1년}\n"
            + "참고: 세벌식 390에서 ; 는 ㅂ 자리라 이름 앞에 ; 를 붙이는 건 권하지 않습니다.")
        help.font = .systemFont(ofSize: 11)
        help.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [scroll, buttons, preview, help])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        for v in [scroll, buttons, preview, help] {
            v.translatesAutoresizingMaskIntoConstraints = false
            v.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -28).isActive = true
        }
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        w.contentView = content
        window = w
        return w
    }

    // MARK: 표

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, objectValueFor col: NSTableColumn?, row: Int) -> Any? {
        col?.identifier.rawValue == "trigger" ? items[row].trigger : items[row].template
    }

    func tableView(_ tableView: NSTableView, setObjectValue obj: Any?, for col: NSTableColumn?, row: Int) {
        let v = (obj as? String ?? "").trimmingCharacters(in: col?.identifier.rawValue == "trigger" ? .whitespacesAndNewlines : [])
        if col?.identifier.rawValue == "trigger" { items[row].trigger = v } else { items[row].template = v }
        save()
    }

    func tableViewSelectionDidChange(_ notification: Notification) { updatePreview() }

    private func updatePreview() {
        let r = table.selectedRow
        guard r >= 0, r < items.count else {
            preview.stringValue = "줄을 고르면 지금 펼친 결과가 여기 보입니다."
            return
        }
        let x = TextShortcuts.expand(items[r].template, now: Date(), clipboard: "(클립보드 내용)")
        preview.stringValue = "미리보기: " + x.before + (x.after.isEmpty ? "" : "▏" + x.after)
    }

    // MARK: 버튼

    @objc private func addRow() {
        items.append(Shortcut(trigger: "새이름", template: "내용"))
        table.reloadData()
        let r = items.count - 1
        table.selectRowIndexes([r], byExtendingSelection: false)
        table.editColumn(0, row: r, with: nil, select: true)
        save()
    }

    @objc private func removeRow() {
        let r = table.selectedRow
        guard r >= 0, r < items.count else { return }
        items.remove(at: r)
        table.reloadData()
        save()
    }

    @objc private func restoreDefaults() {
        let have = Set(items.map(\.trigger))
        items += TextShortcuts.defaults.filter { !have.contains($0.trigger) }
        table.reloadData()
        save()
    }

    private func save() {
        ShortcutStore.all = items.filter { !$0.trigger.isEmpty }
        updatePreview()
    }

    func windowWillClose(_ notification: Notification) {
        window?.makeFirstResponder(nil)   // 편집 중이던 칸도 저장
        save()
    }
}
