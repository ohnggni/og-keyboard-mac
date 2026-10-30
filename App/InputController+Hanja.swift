import Cocoa
import InputMethodKit

/// 사전은 처음 쓸 때 한 번만 올린다 (hanja.dat 5.6MB, 메모리 매핑)
enum Dicts {
    static let hanja = Bundle.main.url(forResource: "hanja", withExtension: "dat").flatMap { HanjaDict(url: $0) }
    static let emoji = Bundle.main.url(forResource: "emoji", withExtension: "dat").flatMap { HanjaDict(url: $0, emoji: true) }
}

/// 한자 후보를 고른 뒤 무엇을 바꿀지
enum HanjaReplace {
    /// 앱에서 드래그로 선택한 범위를 통째로
    case selection(NSRange)
    /// 커서 앞 글자 (end = 커서 위치, UTF-16)
    case before(end: Int)
    /// 앱 글자를 못 읽음(터미널 등): 입력기 기록 기준으로 Backspace 흉내 + 글자 보내기
    case keystrokes
    /// 못 읽고 손쉬운 사용 권한도 없음: 조합 중인 글자만
    case composingOnly
}

struct HanjaSession {
    var items: [HanjaEntry]
    var selected = 0
    var title: String
    var replace: HanjaReplace
    var caret: NSRect?
    /// 터미널용: 후보 창이 떠 있는 동안 걸어둔 '보이지 않는 조합 글자'를 지울 대상
    var placeholderClient: IMKTextInput? = nil
}

private let notFound = NSRange(location: NSNotFound, length: NSNotFound)

extension InputController {

    // MARK: 열기

    func startHanja(_ sender: Any!) {
        guard let client = textClient(sender) else { return }
        guard Dicts.hanja != nil else {
            keyLog.error("한자 사전을 못 읽음")
            return
        }
        let composing = engine.composing()
        let sel = client.selectedRange()
        let marked = client.markedRange()
        var items: [HanjaEntry] = []
        var replace: HanjaReplace

        if composing.isEmpty, sel.location != NSNotFound, sel.length > 0,
           let t = client.attributedSubstring(from: sel)?.string.trimmingCharacters(in: .whitespacesAndNewlines),
           !t.isEmpty {
            // 선택 영역 통째로
            items = (Dicts.hanja?.lookup(t) ?? []) + (Dicts.emoji?.lookup(t) ?? [])
            replace = .selection(sel)
            keyLog.info("한자: 선택 [\(t, privacy: .public)]")
        } else {
            // 커서 앞 글자 읽기: 조합 중이면 조합 글자 앞, 아니면 커서 앞
            let anchor: Int? = !composing.isEmpty
                ? (marked.location != NSNotFound ? marked.location : nil)
                : (sel.location != NSNotFound ? sel.location : nil)
            var before: String?
            if let a = anchor {
                if a == 0 { before = "" }
                else {
                    let start = max(0, a - 12)
                    before = client.attributedSubstring(from: NSRange(location: start, length: a - start))?.string
                }
            }
            // 앱에서 읽은 글자를 믿을 수 있나: 터미널류가 아니고, 입력기 기록과 끝이 맞을 때
            let app = client.bundleIdentifier() ?? ""
            let known = String(TypedText.text.suffix(4))
            let trustRead = before != nil && !Terminals.contains(app)
                && (known.isEmpty || before!.hasSuffix(known))
            if trustRead, let b = before {
                replace = .before(end: anchor! + (composing as NSString).length)
                items = HanjaDict.candidates(before: b + composing, hanja: Dicts.hanja, emoji: Dicts.emoji)
                commit(sender)   // 조합 글자는 확정해 두고 바꿀 때 범위로 교체
            } else if KeySender.trusted {
                commit(sender)   // 확정하면 기록에도 들어감
                replace = .keystrokes
                items = HanjaDict.candidates(before: TypedText.text, hanja: Dicts.hanja, emoji: Dicts.emoji)
            } else {
                KeySender.requestTrust()
                replace = .composingOnly
                items = HanjaDict.candidates(before: composing, hanja: Dicts.hanja, emoji: Dicts.emoji)
            }
            keyLog.info("한자[\(app, privacy: .public)]: 앱글자 [\(before ?? "(못 읽음)", privacy: .public)] 기록 [\(TypedText.text, privacy: .public)] 조합 [\(composing, privacy: .public)] 방식 \(String(describing: replace), privacy: .public) 후보 \(items.count)")
        }

        guard !items.isEmpty else {
            ModeIndicator.shared.showMark("漢")
            return
        }

        let first = items[0]
        let title = first.key.count == 1 && first.key.first.map(HanjaDict.isCompatConsonant) == true ? "기호"
            : items.allSatisfy(\.emoji) ? "이모지" : "한자"
        var session = HanjaSession(items: items, title: title, replace: replace, caret: caretRect(client))
        if case .keystrokes = replace {
            // iTerm2 등은 조합 글자가 없으면 입력기가 처리한 키(Enter·Space·숫자)도 자기가 또 처리함
            // → 폭 0 글자를 조합 중으로 걸어 키가 새지 않게
            client.setMarkedText("\u{200B}", selectionRange: NSRange(location: 1, length: 0), replacementRange: notFound)
            session.placeholderClient = client
        }
        hanja = session
        CandidatePanel.shared.onPick = { [weak self] i in self?.pickHanja(i, client) }
        redrawHanja()
    }

    private func caretRect(_ client: IMKTextInput) -> NSRect? {
        var rect = NSRect.zero
        _ = client.attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
        return rect == .zero ? nil : rect
    }

    private func redrawHanja() {
        guard let h = hanja else { return }
        CandidatePanel.shared.show(title: h.title, items: h.items, selected: h.selected, caret: h.caret)
    }

    func closeHanja() {
        if let c = hanja?.placeholderClient {
            c.setMarkedText("", selectionRange: NSRange(location: 0, length: 0), replacementRange: notFound)
        }
        hanja = nil
        CandidatePanel.shared.hide()
    }

    // MARK: 키

    /// 후보 창이 열려 있을 때의 키. 처리했으면 true, 아니면(다른 키) false.
    func handleHanjaKey(_ event: NSEvent, _ sender: Any!) -> Bool {
        guard var h = hanja else { return false }
        let n = h.items.count
        let page = h.selected / CandidatePanel.pageSize
        let pageSize = CandidatePanel.pageSize

        if event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
           let ch = event.characters, ch.count == 1, let d = Int(ch), (1...9).contains(d) {
            let idx = page * pageSize + d - 1
            if idx < n, let c = textClient(sender) { pickHanja(idx, c) }
            return true
        }

        switch event.keyCode {
        case HanjaKey.down: h.selected = min(n - 1, h.selected + 1)
        case HanjaKey.up: h.selected = max(0, h.selected - 1)
        case HanjaKey.tab:
            h.selected = event.modifierFlags.contains(.shift) ? max(0, h.selected - 1) : min(n - 1, h.selected + 1)
        case HanjaKey.right, HanjaKey.pageDown: h.selected = min(n - 1, (page + 1) * pageSize)
        case HanjaKey.left, HanjaKey.pageUp: h.selected = max(0, (page - 1) * pageSize)
        // Space도 선택: Enter를 입력기보다 먼저 가로채는 앱 대비 (안드판과 같음)
        case HanjaKey.space, HanjaKey.returnKey, HanjaKey.enter:
            if let c = textClient(sender) { pickHanja(h.selected, c) }
            return true
        case HanjaKey.escape:
            closeHanja()
            return true
        default:
            return false
        }
        hanja = h
        redrawHanja()
        return true
    }

    // MARK: 고르기

    func pickHanja(_ index: Int, _ client: IMKTextInput) {
        guard let h = hanja, index < h.items.count else { return }
        let e = h.items[index]
        closeHanja()   // 보이지 않는 조합 글자부터 지우고 바꾼다
        switch h.replace {
        case .selection(let r):
            client.insertText(e.text, replacementRange: r)
        case .before(let end):
            let n = (e.key as NSString).length
            client.insertText(e.text, replacementRange: NSRange(location: max(0, end - n), length: n))
        case .keystrokes:
            KeySender.backspaces(e.key.count)
            KeySender.type(e.text)
        case .composingOnly:
            _ = engine.flush()
            client.insertText(e.text, replacementRange: notFound)
        }
        TypedText.clear()
        keyLog.info("한자 선택 \(e.key, privacy: .public) → \(e.text, privacy: .public)")
    }
}
