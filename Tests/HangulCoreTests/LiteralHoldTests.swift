import XCTest
@testable import HangulCore

/// B12: 어느 키를 조합 중 글자로 걸어둬야 하는지
final class LiteralHoldTests: XCTestCase {
    private func held(_ layout: Layout) -> String {
        var out = ""
        for c in 0x21...0x7e where LiteralHold.needsHold(ascii: c, value: layout.map(c)) {
            out.unicodeScalars.append(UnicodeScalar(UInt8(c)))
        }
        return out
    }

    func test390() {
        // Termix 실측: Shift+쉼표·마침표(2·3)만 깨지고 Shift+M(1)·J(4)는 정상
        XCTAssertEqual(held(Layouts.l390), "<>")
        XCTAssertFalse(LiteralHold.needsHold(ascii: 0x4d, value: Layouts.l390.map(0x4d)))   // M → 1
    }

    func testOtherLayouts() {
        XCTAssertEqual(held(Layouts.noShift), "<>")
        XCTAssertEqual(held(Layouts.dubeol), "")                       // 두벌식은 기호를 바꾸지 않음
        let h391 = held(Layouts.l391)
        XCTAssertTrue(h391.contains("-") && h391.contains("[") && h391.contains("<"), h391)   // 391은 Shift 없는 기호도
    }

    func testJamoAndSameCharNotHeld() {
        XCTAssertFalse(LiteralHold.needsHold(ascii: 0x6b, value: 0x1100))   // k → ㄱ
        XCTAssertFalse(LiteralHold.needsHold(ascii: 0x2e, value: 0x2e))     // . → .
    }
}
