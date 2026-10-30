import XCTest
@testable import HangulCore

/// 안드판 TextToolsTest의 한↔영 부분 이식
final class HanEnConverterTests: XCTestCase {
    func testDubeol() {
        let c = HanEnConverter(layout: Layouts.dubeol)
        XCTAssertEqual(c.toKorean("dkssudgktpdy"), "안녕하세요")
        XCTAssertEqual(c.toLatin("안녕하세요"), "dkssudgktpdy")
        XCTAssertEqual(c.toLatin("닭"), "ekfr")
        XCTAssertEqual(c.toLatin("갔다"), "rkTek")
        XCTAssertEqual(c.toLatin("ㅗ디ㅣㅐ"), "hello")
        XCTAssertTrue(HanEnConverter.containsHangul("abcㅎ"))
    }

    func testSebeol() {
        let c = HanEnConverter(layout: Layouts.l390)
        XCTAssertEqual(c.toKorean("mfskgw"), "한글")
        XCTAssertEqual(c.toLatin("한글"), "mfskgw")
        XCTAssertEqual(c.toLatin("없다"), "jtXuf")
        XCTAssertEqual(c.toLatin("꽃"), "kkvZ")
        XCTAssertEqual(HanEnConverter(layout: Layouts.l391).toLatin("닮"), "ufF")
    }

    /// 모아치기로 순서가 섞인 경우: 글자만으로는 원래 키를 못 되살린다 → 키 기록 사용
    func testMoachigiNeedsKeyLog() {
        let c = HanEnConverter(layout: Layouts.l390)
        let typed = c.toKorean("jinseok")
        XCTAssertEqual(typed, "ㅇㅁ션ㅊㄱ")
        XCTAssertEqual(c.toLatin(typed), "jinesok")
        XCTAssertEqual(c.convertWord(typed, log: "jinseok", toKorean: false), "jinseok")
        XCTAssertEqual(c.toKorean("android"), "싱채미")
    }
}
