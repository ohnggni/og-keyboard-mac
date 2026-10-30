import XCTest
@testable import HangulCore

/// 안드로이드판 HangulEngineTest를 옮긴 회귀 테스트. 키 문자열은 US 배열 기준, \u{8} = 백스페이스.
final class HangulEngineTests: XCTestCase {

    private func type(_ layout: Layout, _ keys: String) -> String {
        let e = HangulEngine()
        e.dubeol = layout.dubeol
        var out = ""
        for k in keys.unicodeScalars {
            if k == "\u{8}" {
                if !e.backspace() && !out.isEmpty { out.removeLast() }
                continue
            }
            let v = layout.map(Int(k.value))
            if HangulEngine.isJamo(v) { out += e.input(v) }
            else { out += e.flush() + String(UnicodeScalar(UInt32(v))!) }
        }
        return out + e.flush()
    }

    private func check(_ keys: String, _ want: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(type(Layouts.l390, keys), want, "390 [\(keys)]", file: file, line: line)
    }

    private func check2(_ keys: String, _ want: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(type(Layouts.dubeol, keys), want, "2 [\(keys)]", file: file, line: line)
    }

    private func check391(_ keys: String, _ want: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(type(Layouts.l391, keys), want, "391 [\(keys)]", file: file, line: line)
    }

    func testDubeolsik() {
        check2("gksrmf", "한글")
        check2("ekfr", "닭")
        check2("ekfrk", "달가")
        check2("rkTdj", "갔어")
        check2("rkTj", "가써")
        check2("dhk", "와")
        check2("dhkTek", "왔다")
        check2("tkfkd", "사랑")
        check2("rr", "ㄱㄱ")
        check2("Rhc", "꽃")
        check2("dlTsms", "있는")
        check2("ekfr\u{8}", "달")
        check2("qjqtk", "법사")
        check2("qjqt", "벖")
        check2("dkswms", "안즌")
        check2("dksgdk", "않아")
        check2("Hello", "ㅗ디ㅣㅐ")
    }

    func testLayout391() {
        check391("mfskgw", "한글")
        check391("jtXuf", "없다")
        check391("ufF", "닮")
        check391(";fW", "밭")
        check391("ufD", "닯")
        check391("jG", "얘")
        check391("JKL", "123")
        check391("kf!", "갂")
    }

    func testLayoutsAreComplete() {
        for l in Layouts.all {
            for c in 0x21...0x7e {
                XCTAssertNotEqual(l.map(c), 0, "\(l.id) missing \(UnicodeScalar(UInt8(c)))")
            }
        }
    }

    func testTyping() {
        check("mfskgw", "한글")
        check("nc;twndx", "세벌식")
        check("jvf2uf", "왔다")
        check("kfX", "값")
        check("kf3q", "값")
        check("ufD", "닭")
        check("ufwx", "닭")
        check("kkvZ", "꽃")
        check("j8nf", "의사")
        check("jgdnf", "의사")
        check("jvr", "왜")
        check("j/f", "와")
        check("j9t", "워")
        check("ufC", "닮")
        check("mfs\u{8}", "하")
        check("ufwx\u{8}", "달")
        check("jvf\u{8}", "오")
        check("kfmf\u{8}\u{8}", "가")
        check("kfmf\u{8}\u{8}\u{8}", "")
        check("mf.", "하.")
        check("JKL N", "456 0")
        check("kx", "ㄱㄱ")
        check("f", "ㅏ")
        check("kf2", "갔")
        check("kfF", "갂")
        check("kfqq", "갔")
        check("kfxx", "갂")
        check("jd2", "있")
        check(";fF", "밖")
        check("fks", "간")
        check("sfk", "간")
        check("ksf", "간")
        check("fmskgw", "한글")
        check("tjXuf", "없다")
        check("jtXfu", "없다")
        check("kfkf", "가가")
        check("kfsfk", "간가")
        check("jvf", "와")
        check("vjf", "와")
        check("ss", "ㄴㄴ")
    }
}
