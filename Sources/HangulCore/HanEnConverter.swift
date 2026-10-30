/// 한/영을 잘못 놓고 친 글자 되돌리기 (안드판 HanEnConverter.java 이식).
///  - 영문 → 한글: 같은 키를 현재 자판으로 다시 친 결과 (dkssud → 안녕, 두벌식)
///  - 한글 → 영문: 그 글자를 치려면 눌렀어야 할 키 (안녕 → dkssud)
final class HanEnConverter {
    private let layout: Layout
    private let moachigi: Bool
    private var reverse: [Int: String] = [:]

    /// 같은 값을 내는 키가 여럿이면 Shift 없는 키를 먼저 쓴다
    private static let keyPreference = Array(
        "abcdefghijklmnopqrstuvwxyz0123456789`-=[]\\;',./"
        + "ABCDEFGHIJKLMNOPQRSTUVWXYZ~!@#$%^&*()_+{}|:\"<>?")

    init(layout: Layout, moachigi: Bool = true) {
        self.layout = layout
        self.moachigi = moachigi
        for k in Self.keyPreference.reversed() {
            reverse[layout.map(Int(k.unicodeScalars.first!.value))] = String(k)
        }
    }

    static func containsHangul(_ s: String) -> Bool {
        s.unicodeScalars.contains { (0xac00...0xd7a3).contains($0.value) || (0x3131...0x318e).contains($0.value) }
    }

    /// 영문 키 입력을 현재 자판의 한글로
    func toKorean(_ latin: String) -> String {
        let e = HangulEngine()
        e.dubeol = layout.dubeol
        e.moachigi = moachigi
        var out = ""
        for k in latin.unicodeScalars {
            let v = layout.map(Int(k.value))
            if HangulEngine.isJamo(v) { out += e.input(v) }
            else { out += e.flush(); out.unicodeScalars.append(UnicodeScalar(UInt32(v))!) }
        }
        return out + e.flush()
    }

    /// 한글을 그걸 치는 영문 키로
    func toLatin(_ text: String) -> String {
        var out = ""
        for u in text.unicodeScalars {
            let c = Int(u.value)
            if c >= 0xac00 && c <= 0xd7a3 {
                let idx = c - 0xac00
                out += keys(for: 0x1100 + idx / (21 * 28))
                out += keys(for: 0x1161 + (idx % (21 * 28)) / 28)
                let t = idx % 28
                if t != 0 { out += keys(for: 0x11a7 + t) }
            } else if c >= 0x3131 && c <= 0x314e {
                out += keys(for: Self.compatConsonant(u))
            } else if c >= 0x314f && c <= 0x3163 {
                out += keys(for: 0x1161 + (c - 0x314f))
            } else if let k = reverse[c], !HangulEngine.isJamo(c) {
                out += k
            } else {
                out.unicodeScalars.append(u)
            }
        }
        return out
    }

    private func keys(for jamo: Int) -> String {
        if let k = reverse[jamo] { return k }
        if layout.dubeol && HangulEngine.isJong(jamo) {
            let cho = HangulEngine.jongToCho(jamo)
            if cho != 0 { return keys(for: cho) }
        }
        if let p = HangulEngine.decompose(jamo) { return keys(for: p.0) + keys(for: p.1) }
        return ""
    }

    private static let choCompat = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ".unicodeScalars)
    private static let jongCompat = Array("ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ".unicodeScalars)

    /// 홀로 쓰인 자음(ㄱ, ㄳ …)을 첫가끝 코드로: 초성에 있으면 초성, 없으면 받침
    private static func compatConsonant(_ c: UnicodeScalar) -> Int {
        if let i = choCompat.firstIndex(of: c) { return 0x1100 + i }
        if let j = jongCompat.firstIndex(of: c) { return 0x11a8 + j }
        return Int(c.value)
    }

    /// 낱말 하나 바꾸기. 키 기록 중 다시 쳐본 결과가 이 낱말과 같은 게 있으면 그 키를 그대로 쓴다(모아치기 대비).
    /// 전부 대문자인 영문 낱말은 Caps Lock이 켜진 채 친 것으로 보고 소문자 키로 한글 변환.
    func convertWord(_ word: String, logs: [String], toKorean: Bool) -> String {
        if toKorean {
            if Self.containsHangul(word) { return word }
            let letters = word.unicodeScalars.filter { ($0.value >= 0x41 && $0.value <= 0x5a) || ($0.value >= 0x61 && $0.value <= 0x7a) }
            let allCaps = letters.count >= 2 && letters.allSatisfy { $0.value <= 0x5a }
            return self.toKorean(allCaps ? word.lowercased() : word)
        }
        if let log = logs.first(where: { !$0.isEmpty && self.toKorean($0) == word }) { return log }
        return Self.containsHangul(word) ? toLatin(word) : word
    }

    func convertWord(_ word: String, log: String?, toKorean: Bool) -> String {
        convertWord(word, logs: log.map { [$0] } ?? [], toKorean: toKorean)
    }
}
