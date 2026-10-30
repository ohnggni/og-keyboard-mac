/// 세벌식(첫가끝 분리 입력) 한글 조합기. 안드로이드판 HangulEngine.java를 그대로 옮김.
///
/// 입력: 첫가끝 자모(U+1100~U+11FF). 결과: 확정 문자열 + 조합 중 문자열.
/// 백스페이스는 자모 단위로 되돌린다 (ㄼ → ㄹ, ㅘ → ㅗ).
final class HangulEngine {

    private var cho = 0, jung = 0, jong = 0
    /// 백스페이스용: 각 입력 직전 상태 (cho, jung, jong)
    private var history: [(Int, Int, Int)] = []

    static func isCho(_ c: Int) -> Bool { c >= 0x1100 && c <= 0x1112 }
    static func isJung(_ c: Int) -> Bool { c >= 0x1161 && c <= 0x1175 }
    static func isJong(_ c: Int) -> Bool { c >= 0x11a8 && c <= 0x11c2 }
    static func isJamo(_ c: Int) -> Bool { isCho(c) || isJung(c) || isJong(c) }

    var isEmpty: Bool { cho == 0 && jung == 0 && jong == 0 }

    /// 모아치기: 한 글자 안에서 초·중·종성을 어떤 순서로 쳐도 빈 자리에 채워 넣는다.
    var moachigi = true
    /// 두벌식: 자음이 받침이 될지 다음 글자 초성이 될지 엔진이 정한다 (도깨비불 처리)
    var dubeol = false

    /// 자모 하나를 넣는다. 확정돼서 앞으로 밀려난 글자를 돌려준다(없으면 "").
    func input(_ c: Int) -> String {
        if dubeol { return inputDubeol(c) }
        return moachigi ? inputMoachigi(c) : inputSequential(c)
    }

    // MARK: 두벌식

    private func inputDubeol(_ c: Int) -> String {
        if Self.isCho(c) {
            if jung == 0 {
                if cho == 0 { push(); cho = c; return "" }
                let committed = flush()
                push(); cho = c
                return committed
            }
            if cho == 0 {
                let committed = flush()
                push(); cho = c
                return committed
            }
            let j = Self.choToJong(c)
            if jong == 0 && j != 0 { push(); jong = j; return "" }
            if jong != 0 && j != 0 {
                let comb = Self.combineJongDubeol(jong, j)
                if comb != 0 { push(); jong = comb; return "" }
            }
            let committed = flush()
            push(); cho = c
            return committed
        }
        if Self.isJung(c) {
            if jong != 0 {
                // 받침을 떼어 다음 글자 초성으로
                var keep = 0
                let move: Int
                if let split = Self.splitJong(jong) { keep = split.0; move = Self.jongToCho(split.1) }
                else { move = Self.jongToCho(jong) }
                jong = keep
                let committed = composing()
                cho = 0; jung = 0; jong = 0
                history.removeAll()
                push(); cho = move
                push(); jung = c
                return committed
            }
            if jung != 0 {
                let comb = Self.combine(jung, c)
                if comb != 0 { push(); jung = comb; return "" }
                let committed = flush()
                push(); jung = c
                return committed
            }
            push(); jung = c
            return ""
        }
        return ""
    }

    private static let choToJongTable = [
        0x11a8, 0x11a9, 0x11ab, 0x11ae, 0, 0x11af, 0x11b7, 0x11b8, 0, 0x11ba,
        0x11bb, 0x11bc, 0x11bd, 0, 0x11be, 0x11bf, 0x11c0, 0x11c1, 0x11c2]

    private static func choToJong(_ cho: Int) -> Int { choToJongTable[cho - 0x1100] }

    static func jongToCho(_ jong: Int) -> Int {
        if let i = choToJongTable.firstIndex(of: jong) { return 0x1100 + i }
        return 0
    }

    /// 겹자모를 두 조각으로 (ㄲ→ㄱㄱ, ㅘ→ㅗㅏ, ㄺ→ㄹㄱ). 홑자모면 nil
    static func decompose(_ jamo: Int) -> (Int, Int)? {
        for r in combos where r.2 == jamo { return (r.0, r.1) }
        return nil
    }

    /// 두벌식 겹받침: ㄱㄱ→ㄲ, ㅅㅅ→ㅆ은 받침에서 합치지 않음(쌍자음은 Shift로 침)
    private static func combineJongDubeol(_ a: Int, _ b: Int) -> Int {
        a == b ? 0 : combine(a, b)
    }

    /// 겹받침을 (남을 받침, 넘어갈 받침)으로. 홑받침이면 nil
    private static func splitJong(_ jong: Int) -> (Int, Int)? {
        for r in combos where r.2 == jong && isJong(r.0) && r.0 != r.1 { return (r.0, r.1) }
        return nil
    }

    // MARK: 세벌식

    private func inputMoachigi(_ c: Int) -> String {
        var committed = ""
        if Self.isCho(c) {
            if cho == 0 { push(); cho = c; return "" }
            if jung == 0 && jong == 0 {
                let comb = Self.combine(cho, c)
                if comb != 0 { push(); cho = comb; return "" }
            }
            committed = flush()
            push(); cho = c
        } else if Self.isJung(c) {
            if jung == 0 { push(); jung = c; return "" }
            let comb = Self.combine(jung, c)
            if comb != 0 { push(); jung = comb; return "" }
            committed = flush()
            push(); jung = c
        } else if Self.isJong(c) {
            if jong == 0 && (cho != 0 || jung != 0) { push(); jong = c; return "" }
            if jong != 0 {
                let comb = Self.combine(jong, c)
                if comb != 0 { push(); jong = comb; return "" }
            }
            committed = flush()
            push(); jong = c
        }
        return committed
    }

    /// 순서대로 치기(초→중→종). 모아치기를 끈 경우.
    private func inputSequential(_ c: Int) -> String {
        var committed = ""
        if Self.isCho(c) {
            if cho != 0 && jung == 0 && jong == 0 {
                let comb = Self.combine(cho, c)
                if comb != 0 { push(); cho = comb; return "" }
            }
            if !isEmpty { committed = flush() }
            push(); cho = c
        } else if Self.isJung(c) {
            if jung == 0 && jong == 0 { push(); jung = c; return "" }
            if jung != 0 && jong == 0 {
                let comb = Self.combine(jung, c)
                if comb != 0 { push(); jung = comb; return "" }
            }
            committed = flush()
            push(); jung = c
        } else if Self.isJong(c) {
            if jung != 0 && jong == 0 { push(); jong = c; return "" }
            if jong != 0 {
                let comb = Self.combine(jong, c)
                if comb != 0 { push(); jong = comb; return "" }
            }
            committed = flush()
            push(); jong = c
        }
        return committed
    }

    // MARK: 공통

    /// 자모 하나 되돌리기. 조합 중인 게 없었으면 false.
    @discardableResult
    func backspace() -> Bool {
        if isEmpty { return false }
        if let prev = history.popLast() { (cho, jung, jong) = prev }
        else { cho = 0; jung = 0; jong = 0 }
        return true
    }

    /// 조합 중인 글자를 확정하고 비운다.
    func flush() -> String {
        let s = composing()
        cho = 0; jung = 0; jong = 0
        history.removeAll()
        return s
    }

    /// 지금 조합 중인 글자(화면 표시용).
    func composing() -> String {
        if isEmpty { return "" }
        if cho != 0 && jung != 0 {
            let ci = cho - 0x1100, vi = jung - 0x1161, ti = jong == 0 ? 0 : jong - 0x11a7
            return String(UnicodeScalar(UInt32(0xac00 + (ci * 21 + vi) * 28 + ti))!)
        }
        var s = ""
        if cho != 0 { s.append(Self.choCompat[cho - 0x1100]) }
        if jung != 0 { s.append(Character(UnicodeScalar(UInt32(0x314f + jung - 0x1161))!)) }
        if jong != 0 { s.append(Self.jongCompat[jong - 0x11a8]) }
        return s
    }

    private func push() { history.append((cho, jung, jong)) }

    private static let choCompat = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ")
    private static let jongCompat = Array("ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ")

    /// libhangul hangul-combination-default (세벌식에 해당하는 것만)
    private static let combos: [(Int, Int, Int)] = [
        (0x1100, 0x1100, 0x1101), (0x1103, 0x1103, 0x1104), (0x1107, 0x1107, 0x1108),
        (0x1109, 0x1109, 0x110a), (0x110c, 0x110c, 0x110d),
        (0x1169, 0x1161, 0x116a), (0x1169, 0x1162, 0x116b), (0x1169, 0x1175, 0x116c),
        (0x116e, 0x1165, 0x116f), (0x116e, 0x1166, 0x1170), (0x116e, 0x1175, 0x1171),
        (0x1173, 0x1175, 0x1174),
        (0x11a8, 0x11a8, 0x11a9), (0x11a8, 0x11ba, 0x11aa), (0x11ab, 0x11bd, 0x11ac),
        (0x11ab, 0x11c2, 0x11ad), (0x11af, 0x11a8, 0x11b0), (0x11af, 0x11b7, 0x11b1),
        (0x11af, 0x11b8, 0x11b2), (0x11af, 0x11ba, 0x11b3), (0x11af, 0x11c0, 0x11b4),
        (0x11af, 0x11c1, 0x11b5), (0x11af, 0x11c2, 0x11b6), (0x11b8, 0x11ba, 0x11b9),
        (0x11ba, 0x11ba, 0x11bb),
    ]

    private static func combine(_ a: Int, _ b: Int) -> Int {
        for r in combos where r.0 == a && r.1 == b { return r.2 }
        return 0
    }
}
