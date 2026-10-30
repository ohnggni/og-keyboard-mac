import Foundation

/// 텍스트 단축어 (안드판 TextShortcuts.java 이식).
///
/// 내용에 쓸 수 있는 값:
///   {날짜} 2026-10-24 · {날짜:M월 d일} 형식 지정 · {시간} 19:20 · {요일} 토요일
///   날짜 계산: {날짜+1} 내일, {날짜-2} 그제, {요일+1}, {날짜+1주}, {날짜+1달}, {날짜-1년}
///   {클립보드} 지금 복사된 내용 · {커서} 넣은 뒤 커서 위치
struct Shortcut: Equatable, Codable {
    var trigger: String
    var template: String
}

enum TextShortcuts {
    static let defaults: [Shortcut] = [
        Shortcut(trigger: "날짜", template: "{날짜}"),
        Shortcut(trigger: "시간", template: "{시간}"),
        Shortcut(trigger: "지금", template: "{시간}"),
        Shortcut(trigger: "오늘", template: "{날짜:M월 d일} {요일}"),
        Shortcut(trigger: "내일", template: "{날짜+1:M월 d일} {요일+1}"),
        Shortcut(trigger: "모레", template: "{날짜+2:M월 d일} {요일+2}"),
        Shortcut(trigger: "어제", template: "{날짜-1:M월 d일} {요일-1}"),
        Shortcut(trigger: "그제", template: "{날짜-2:M월 d일} {요일-2}"),
    ]

    /// 펼친 결과: 커서 앞 / 커서 뒤
    struct Expanded: Equatable {
        var before: String
        var after: String
        var text: String { before + after }
    }

    private static let token = try! NSRegularExpression(
        pattern: "\\{(날짜|시간|요일|클립보드|커서)(?:([+-]\\d+)(일|주|달|개월|년)?)?(?::([^}]*))?\\}")
    private static let cursorMark = "\u{0}"

    static func expand(_ template: String, now: Date, clipboard: String?) -> Expanded {
        let ns = template as NSString
        var out = ""
        var last = 0
        for m in token.matches(in: template, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            func group(_ i: Int) -> String? {
                let r = m.range(at: i)
                return r.location == NSNotFound ? nil : ns.substring(with: r)
            }
            let name = group(1)!, fmt = group(4)
            let when = shift(now, amount: group(2), unit: group(3))
            switch name {
            case "날짜": out += format(fmt ?? "yyyy-MM-dd", when)
            case "시간": out += format(fmt ?? "HH:mm", when)
            case "요일": out += format(fmt ?? "EEEE", when)
            case "클립보드": out += clipboard ?? ""
            default: out += cursorMark
            }
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        guard let r = out.range(of: cursorMark) else { return Expanded(before: out, after: "") }
        return Expanded(before: String(out[..<r.lowerBound]),
                        after: String(out[r.upperBound...]).replacingOccurrences(of: cursorMark, with: ""))
    }

    /// {날짜+1}, {날짜-1주} 같은 날짜 계산
    private static func shift(_ now: Date, amount: String?, unit: String?) -> Date {
        guard let a = amount, let n = Int(a.replacingOccurrences(of: "+", with: "")) else { return now }
        let cal = Calendar(identifier: .gregorian)
        switch unit {
        case nil, "일": return cal.date(byAdding: .day, value: n, to: now) ?? now
        case "주": return cal.date(byAdding: .day, value: 7 * n, to: now) ?? now
        case "달", "개월": return cal.date(byAdding: .month, value: n, to: now) ?? now
        default: return cal.date(byAdding: .year, value: n, to: now) ?? now
        }
    }

    private static func format(_ pattern: String, _ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = pattern
        return f.string(from: date)
    }

    /// 커서 앞 글자의 끝과 맞는 단축어들. 낱말 단위(이름 앞이 처음이거나 공백), 긴 이름 먼저.
    static func match(_ all: [Shortcut], before text: String) -> [Shortcut] {
        all.filter { s in
            guard !s.trigger.isEmpty, text.hasSuffix(s.trigger) else { return false }
            let rest = text.dropLast(s.trigger.count)
            return rest.isEmpty || rest.last!.isWhitespace
        }.sorted { $0.trigger.count > $1.trigger.count }
    }
}
