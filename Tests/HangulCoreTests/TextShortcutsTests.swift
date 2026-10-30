import XCTest
@testable import HangulCore

/// 안드판 TextToolsTest의 단축어 부분 이식 (2026-10-24 토요일 09:05 기준)
final class TextShortcutsTests: XCTestCase {
    private var oct24: Date {
        var c = DateComponents()
        c.year = 2026; c.month = 10; c.day = 24; c.hour = 9; c.minute = 5
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    private func x(_ t: String, _ clip: String? = nil) -> String {
        TextShortcuts.expand(t, now: oct24, clipboard: clip).text
    }

    func testExpandTokens() {
        XCTAssertEqual(x("{날짜}"), "2026-10-24")
        XCTAssertEqual(x("{날짜:M월 d일} {요일}"), "10월 24일 토요일")
        XCTAssertEqual(x("{시간}"), "09:05")
        XCTAssertEqual(x("{클립보드}!", "복사됨"), "복사됨!")
        let e = TextShortcuts.expand("안녕하세요 {커서}님", now: oct24, clipboard: nil)
        XCTAssertEqual(e.before, "안녕하세요 ")
        XCTAssertEqual(e.after, "님")
        XCTAssertEqual(x("{없는값}"), "{없는값}")
        XCTAssertEqual(x("{날짜+1:M월 d일} {요일+1}"), "10월 25일 일요일")
        XCTAssertEqual(x("{날짜-2:M월 d일} {요일-2}"), "10월 22일 목요일")
        XCTAssertEqual(x("{날짜+1주}"), "2026-10-31")
        XCTAssertEqual(x("{날짜+1달}"), "2026-11-24")
        XCTAssertEqual(x("{날짜-1년}"), "2025-10-24")
        XCTAssertEqual(x("{날짜+8}"), "2026-11-01")
    }

    func testMatchTrigger() {
        let all = [Shortcut(trigger: "날짜", template: "{날짜}"), Shortcut(trigger: ";메일", template: "a@b.c")]
        XCTAssertEqual(TextShortcuts.match(all, before: "오늘 날짜").count, 1)
        XCTAssertEqual(TextShortcuts.match(all, before: "날짜").count, 1)
        XCTAssertEqual(TextShortcuts.match(all, before: "생년월일날짜").count, 0)
        XCTAssertEqual(TextShortcuts.match(all, before: "보내 ;메일").first?.trigger, ";메일")
    }
}
