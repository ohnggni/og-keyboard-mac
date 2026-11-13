/// B12: Chromium·Electron 터미널(xterm.js)에서 기호 키가 원래 글자로 찍히는 문제의 판단 규칙.
///
/// 입력기가 키 하나를 처리하며 조합 글자 없이 1자만 넣으면, Chromium은 원래 키 정보(key='<')로 keydown을 보내고
/// 넣은 글자('2')는 뒤따르는 keypress로 보낸다. xterm.js는 한 글자 키를 keydown의 key로 바로 셸에 보내고
/// keypress를 버린다(단, key가 A~Z 대문자면 keypress로 미룸). 그래서 자판이 기호 키를 다른 글자로 바꾸는 경우만 깨진다.
/// 이때 바뀐 글자를 조합 중 글자(marked text)로 잠깐 걸어두면 Chromium이 keydown을 '입력기 처리 중'(229)으로 보내
/// xterm.js가 조합 경로로 받는다.
public enum LiteralHold {
    /// 이 키가 만든 글자를 조합 중 글자로 걸어둬야 하는지
    /// - ascii: 실제로 눌린 키의 글자 (Shift 반영)
    /// - value: 자판이 바꾼 결과
    public static func needsHold(ascii: Int, value: Int) -> Bool {
        if HangulEngine.isJamo(value) { return false }   // 자모는 원래 조합 경로
        if value == ascii { return false }                // 원래 글자 그대로면 문제없음
        if ascii >= 0x41 && ascii <= 0x5a { return false } // A~Z는 xterm.js가 keypress로 미뤄 정상
        return true
    }
}
