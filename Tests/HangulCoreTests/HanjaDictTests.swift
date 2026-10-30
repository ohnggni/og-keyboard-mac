import XCTest
@testable import HangulCore

final class HanjaDictTests: XCTestCase {
    private static let res = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("App/Resources")
    private let hanja = HanjaDict(url: res.appendingPathComponent("hanja.dat"))
    private let emoji = HanjaDict(url: res.appendingPathComponent("emoji.dat"), emoji: true)

    func testLoads() {
        XCTAssertNotNil(hanja)
        XCTAssertNotNil(emoji)
    }

    func testLookup() {
        XCTAssertTrue(hanja!.lookup("대한민국").contains { $0.text == "大韓民國" })
        XCTAssertTrue(hanja!.lookup("국").contains { $0.text == "國" })
        XCTAssertFalse(hanja!.lookup("ㄱ").isEmpty)              // 기호표
        XCTAssertTrue(hanja!.lookup("없는낱말쀍").isEmpty)
        XCTAssertTrue(emoji!.lookup("고양이").contains { $0.emoji })
    }

    func testCandidatesLongestFirst() {
        let c = HanjaDict.candidates(before: "우리 대한민국", hanja: hanja, emoji: nil)
        XCTAssertEqual(c.first?.key, "대한민국")
        XCTAssertTrue(c.contains { $0.key == "국" })
        XCTAssertFalse(c.contains { $0.key.contains("리") })   // 띄어쓰기 앞은 안 봄
    }

    func testSymbolTable() {
        let c = HanjaDict.candidates(before: "abc ㄷ", hanja: hanja, emoji: nil)
        XCTAssertFalse(c.isEmpty)
        XCTAssertEqual(c.first?.key, "ㄷ")
    }

    func testTrailingHangul() {
        XCTAssertEqual(HanjaDict.trailingHangul("abc한글"), "한글")
        XCTAssertEqual(HanjaDict.trailingHangul("한글 "), "")
        XCTAssertEqual(HanjaDict.trailingHangul("가나다라마바사", max: 3), "마바사")
    }
}
