import Cocoa
import InputMethodKit

/// 열려 있는 이모지 창 상태
struct EmojiSession {
    var tabs: [EmojiGroup]
    var group: Int
    var selected: Int
    var caret: NSRect?
    var client: IMKTextInput
    /// 터미널용 '보이지 않는 조합 글자'를 걸어둔 대상 (한자 후보 창과 같은 이유)
    var placeholderClient: IMKTextInput?
}

private let notFound = NSRange(location: NSNotFound, length: NSNotFound)

extension InputController {

    /// 오른쪽 Option 두 번: 분류별 이모지 창
    func openEmojiPanel(_ sender: Any!) {
        guard let client = textClient(sender) else { return }
        closeHanja()
        commit(sender)
        let tabs = EmojiData.tabs
        guard !tabs.isEmpty else { ModeIndicator.shared.showMark("😀"); return }
        var rect = NSRect.zero
        _ = client.attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
        var s = EmojiSession(tabs: tabs, group: 0, selected: 0, caret: rect == .zero ? nil : rect, client: client)
        if Terminals.contains(client.bundleIdentifier() ?? "") {
            client.setMarkedText("\u{200B}", selectionRange: NSRange(location: 1, length: 0), replacementRange: notFound)
            s.placeholderClient = client
        }
        emojiSession = s
        EmojiPanel.shared.onPick = { [weak self] e in self?.pickEmoji(e) }
        EmojiPanel.shared.onGroup = { [weak self] i in
            guard let self = self, var s = self.emojiSession, i < s.tabs.count else { return }
            s.group = i
            s.selected = 0
            self.emojiSession = s
            self.redrawEmoji()
        }
        redrawEmoji()
    }

    private func redrawEmoji() {
        guard let s = emojiSession else { return }
        EmojiPanel.shared.show(tabs: s.tabs, group: s.group, selected: s.selected, caret: s.caret)
    }

    func closeEmoji() {
        if let c = emojiSession?.placeholderClient {
            c.setMarkedText("", selectionRange: NSRange(location: 0, length: 0), replacementRange: notFound)
        }
        emojiSession = nil
        EmojiPanel.shared.hide()
    }

    private func pickEmoji(_ e: String) {
        guard let s = emojiSession else { return }
        closeEmoji()
        s.client.insertText(e, replacementRange: notFound)
        EmojiData.addRecent(e)
        TypedText.clearTextOnly()
        keyLog.info("이모지 \(e, privacy: .public)")
    }

    /// 이모지 창이 열려 있을 때의 키. 처리했으면 true.
    func handleEmojiKey(_ event: NSEvent) -> Bool {
        guard var s = emojiSession, s.group < s.tabs.count else { return false }
        let n = s.tabs[s.group].items.count
        let cols = EmojiPanel.cols, page = EmojiPanel.page
        switch event.keyCode {
        case HanjaKey.right: s.selected = min(n - 1, s.selected + 1)
        case HanjaKey.left: s.selected = max(0, s.selected - 1)
        case HanjaKey.down: s.selected = min(n - 1, s.selected + cols)
        case HanjaKey.up: s.selected = max(0, s.selected - cols)
        case HanjaKey.pageDown: s.selected = min(n - 1, (s.selected / page + 1) * page)
        case HanjaKey.pageUp: s.selected = max(0, (s.selected / page - 1) * page)
        case HanjaKey.tab:
            let k = s.tabs.count
            s.group = event.modifierFlags.contains(.shift) ? (s.group + k - 1) % k : (s.group + 1) % k
            s.selected = 0
        case HanjaKey.space, HanjaKey.returnKey, HanjaKey.enter:
            if s.selected < n { pickEmoji(s.tabs[s.group].items[s.selected].emoji) }
            return true
        case HanjaKey.escape, 51:   // Esc, Backspace
            closeEmoji()
            return true
        default:
            return false
        }
        emojiSession = s
        redrawEmoji()
        return true
    }
}
