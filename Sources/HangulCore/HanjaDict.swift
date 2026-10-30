import Foundation

/// 한자·기호·이모지 후보 하나
struct HanjaEntry: Equatable {
    /// 바꿀 대상 글자 (지울 길이 기준)
    let key: String
    /// 후보에 보이고 실제로 넣을 글자
    let text: String
    /// 뜻·설명 (없으면 "")
    let meaning: String
    let emoji: Bool
    /// 텍스트 단축어면 펼칠 내용 (그 외엔 nil)
    var template: String? = nil
    /// 실제로 넣을 글자가 보이는 글자와 다를 때 (클립보드 기록: 보이는 건 줄인 미리보기)
    var insert: String? = nil
}

/// 한자 사전 조회. 파일(UTF-8 바이트 순 정렬, 한 줄 = 음\t한자|뜻\t...)을 통째로 올려 이진 탐색.
/// 안드판 HanjaDict.java와 같은 형식(hanja.dat, emoji.dat)을 그대로 쓴다.
final class HanjaDict {
    private let bytes: [UInt8]
    private let emoji: Bool

    init?(url: URL, emoji: Bool = false) {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        bytes = [UInt8](data)
        self.emoji = emoji
    }

    /// 음(한글)·자음으로 후보를 찾는다. 없으면 빈 목록.
    func lookup(_ key: String) -> [HanjaEntry] {
        guard !key.isEmpty else { return [] }
        let target = Array(key.utf8)
        let pos = lowerBound(target)
        guard pos < bytes.count else { return [] }
        var end = pos
        while end < bytes.count && bytes[end] != 0x0a { end += 1 }
        guard let line = String(bytes: bytes[pos..<end], encoding: .utf8) else { return [] }
        let cells = line.split(separator: "\t", omittingEmptySubsequences: false)
        guard cells.first.map(String.init) == key else { return [] }
        return cells.dropFirst().compactMap { c -> HanjaEntry? in
            guard !c.isEmpty else { return nil }
            if let bar = c.firstIndex(of: "|") {
                return HanjaEntry(key: key, text: String(c[..<bar]), meaning: String(c[c.index(after: bar)...]), emoji: emoji)
            }
            return HanjaEntry(key: key, text: String(c), meaning: "", emoji: emoji)
        }
    }

    /// 키가 target 이상인 첫 줄의 시작 위치
    private func lowerBound(_ target: [UInt8]) -> Int {
        var lo = 0, hi = bytes.count
        while lo < hi {
            let mid = (lo + hi) / 2
            let s = nextLineStart(mid)
            if s >= hi { hi = mid; continue }
            if compare(keyAt(s), target) < 0 { lo = s + 1 } else { hi = mid }
        }
        return nextLineStart(lo)
    }

    private func nextLineStart(_ pos: Int) -> Int {
        if pos == 0 { return 0 }
        var i = pos - 1
        while i < bytes.count {
            if bytes[i] == 0x0a { return i + 1 }
            i += 1
        }
        return bytes.count
    }

    private func keyAt(_ pos: Int) -> ArraySlice<UInt8> {
        var e = pos
        while e < bytes.count && bytes[e] != 0x09 && bytes[e] != 0x0a { e += 1 }
        return bytes[pos..<e]
    }

    private func compare(_ a: ArraySlice<UInt8>, _ b: [UInt8]) -> Int {
        for (x, y) in zip(a, b) where x != y { return Int(x) - Int(y) }
        return a.count - b.count
    }

    // MARK: 도우미

    /// 끝에 붙은 한글 음절(가~힣) 덩어리. 최대 max자.
    static func trailingHangul(_ s: String, max: Int = 6) -> String {
        var out: [Character] = []
        for ch in s.reversed() {
            guard out.count < max, let v = ch.unicodeScalars.first?.value,
                  ch.unicodeScalars.count == 1, v >= 0xac00 && v <= 0xd7a3 else { break }
            out.append(ch)
        }
        return String(out.reversed())
    }

    /// 낱자 자음(ㄱ~ㅎ)인지 — 기호표 키
    static func isCompatConsonant(_ ch: Character) -> Bool {
        guard ch.unicodeScalars.count == 1, let v = ch.unicodeScalars.first?.value else { return false }
        return v >= 0x3131 && v <= 0x314e
    }

    /// 커서 앞 글자로 후보 모으기: 긴 낱말부터(대한민국 → 大韓民國 … 國), 한글이 없고 끝이 자음이면 기호표
    static func candidates(before: String, hanja: HanjaDict?, emoji: HanjaDict?, maxWord: Int = 6) -> [HanjaEntry] {
        var items: [HanjaEntry] = []
        let run = trailingHangul(before, max: maxWord)
        let chars = Array(run)
        if !chars.isEmpty {
            for len in stride(from: chars.count, through: 1, by: -1) {
                let key = String(chars[(chars.count - len)...])
                items += hanja?.lookup(key) ?? []
                items += emoji?.lookup(key) ?? []
            }
        } else if let last = before.last, isCompatConsonant(last) {
            items += hanja?.lookup(String(last)) ?? []
        }
        return items
    }
}
