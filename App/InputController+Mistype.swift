import Cocoa
import InputMethodKit

/// 바로잡기 연속 실행 상태 (2초 안에 다시 길게 누르면 한 낱말씩 앞으로)
private enum MistypeChain {
    static var at: Date?
    /// 이미 바꾼 부분 (커서 바로 앞까지)
    static var tail = ""
    static var logs: [String] = []
    static var words = 0
    static var toKorean = true
    static let window: TimeInterval = 2
}

extension InputController {

    /// 오른쪽 Command 길게: 커서 앞 낱말을 반대 언어로 다시 쓰고 한/영도 전환 (안드판과 같음)
    func convertMistype(_ sender: Any!) {
        guard let client = textClient(sender) else { return }
        closeHanja()
        let conv = HanEnConverter(layout: ModeState.layout, moachigi: engine.moachigi)
        let composing = engine.composing()
        let sel = client.selectedRange()
        let marked = client.markedRange()
        let app = client.bundleIdentifier() ?? ""
        let isTerminal = Terminals.contains(app)

        // 1) 드래그로 선택한 영역 전체 (일반 앱)
        if !isTerminal, composing.isEmpty, sel.location != NSNotFound, sel.length > 0,
           let t = client.attributedSubstring(from: sel)?.string, !t.isEmpty {
            let toKorean = !HanEnConverter.containsHangul(t)
            let out = convertTokens(t, conv, toKorean: toKorean)
            client.insertText(out, replacementRange: sel)
            KeyLog.clear()
            MistypeChain.at = nil
            switchMode(to: toKorean)
            keyLog.info("바로잡기 선택 [\(t, privacy: .public)] → [\(out, privacy: .public)]")
            return
        }

        // 2) 커서 앞 글자: 앱에서 읽기 (조합 글자는 아직 화면에만 있으니 그 앞까지 읽고 붙인다)
        let anchor: Int? = composing.isEmpty
            ? (sel.location != NSNotFound ? sel.location : nil)
            : (marked.location != NSNotFound ? marked.location : nil)
        var read: String?
        if !isTerminal, let a = anchor {
            if a == 0 { read = "" }
            else {
                let start = max(0, a - 200)
                read = client.attributedSubstring(from: NSRange(location: start, length: a - start))?.string
            }
        }
        let known = String(TypedText.text.suffix(4))
        let useClient = read != nil && (known.isEmpty || read!.hasSuffix(known))

        commit(sender)   // 조합 글자 확정 (기록에도 들어감)

        let full: String
        if useClient, let r = read { full = r + composing }
        else if KeySender.trusted { full = TypedText.text }
        else {
            KeySender.requestTrust()
            ModeIndicator.shared.showMark("⇄")
            return
        }

        // 연속 실행인지: 2초 안이고, 지난번에 바꾼 글자가 그대로 커서 앞에 있을 때
        let now = Date()
        var chaining = MistypeChain.at.map { now.timeIntervalSince($0) < MistypeChain.window } ?? false
        if chaining && !full.hasSuffix(MistypeChain.tail) { chaining = false }
        if !chaining {
            MistypeChain.logs = KeyLog.newestFirst
            MistypeChain.words = 0
            MistypeChain.tail = ""
        }
        let tail = MistypeChain.tail

        // 남은 부분에서 맨 끝 낱말과 그 뒤 공백
        let rest = Array(full.dropLast(tail.count))
        var i = rest.count
        while i > 0 && rest[i - 1].isWhitespace { i -= 1 }
        var j = i
        while j > 0 && !rest[j - 1].isWhitespace { j -= 1 }
        let word = String(rest[j..<i]), sep = String(rest[i...])
        guard !word.isEmpty else {
            ModeIndicator.shared.showMark("⇄")
            MistypeChain.at = nil
            return
        }

        let toKorean = chaining ? MistypeChain.toKorean : !HanEnConverter.containsHangul(word)
        // 같은 위치의 기록을 먼저, 그다음 나머지 기록 전체에서 내용이 맞는 것
        let w = MistypeChain.words
        let logs = (w < MistypeChain.logs.count ? [MistypeChain.logs[w]] : []) + MistypeChain.logs
        let out = conv.convertWord(word, logs: logs, toKorean: toKorean)
        let oldRegion = word + sep + tail
        let newRegion = out + sep + tail

        if useClient, let a = anchor {
            let cursor = a + (composing as NSString).length
            let n = (oldRegion as NSString).length
            client.insertText(newRegion, replacementRange: NSRange(location: max(0, cursor - n), length: n))
        } else {
            KeySender.backspaces(oldRegion.count)
            KeySender.type(newRegion)
        }
        TypedText.replaceSuffix(count: oldRegion.count, with: newRegion)
        KeyLog.clear()

        MistypeChain.tail = newRegion
        MistypeChain.words += 1
        MistypeChain.toKorean = toKorean
        MistypeChain.at = now
        keyLog.info("바로잡기[\(app, privacy: .public)] \(useClient ? "앱" : "키흉내", privacy: .public) [\(word, privacy: .public)] → [\(out, privacy: .public)] 기록 \(logs.count)개 연속 \(MistypeChain.words)")
        if !chaining { switchMode(to: toKorean) }
        else { ModeIndicator.shared.show(hangul: toKorean) }
    }

    /// 선택 영역: 낱말마다 바꾸고(뒤 낱말부터 키 기록을 맞춰 봄) 공백은 그대로
    private func convertTokens(_ text: String, _ conv: HanEnConverter, toKorean: Bool) -> String {
        var tokens: [String] = []
        var cur = ""
        var curSpace: Bool?
        for ch in text {
            let sp = ch.isWhitespace
            if curSpace != nil && curSpace != sp { tokens.append(cur); cur = "" }
            cur.append(ch)
            curSpace = sp
        }
        if !cur.isEmpty { tokens.append(cur) }
        let logs = KeyLog.newestFirst
        var w = 0
        for k in tokens.indices.reversed() where !(tokens[k].first?.isWhitespace ?? true) {
            tokens[k] = conv.convertWord(tokens[k], logs: (w < logs.count ? [logs[w]] : []) + logs, toKorean: toKorean)
            w += 1
        }
        return tokens.joined()
    }

    private func switchMode(to hangul: Bool) {
        if ModeState.hangul != hangul { ModeState.hangul = hangul }
        ModeIndicator.shared.show(hangul: hangul)
    }
}
