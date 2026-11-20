import XCTest
@testable import HangulCore

/// 영문 칸 알아보기 규칙. 실제 사이트에서 흔한 칸 모양으로 확인.
final class FieldRulesTests: XCTestCase {
    private func web(_ texts: [String] = [], placeholder: String? = nil, id: String? = nil,
                     role: String = "AXTextField", subrole: String? = nil) -> FieldRules.Field {
        FieldRules.Field(role: role, subrole: subrole, roleDescription: "텍스트 필드", texts: texts,
                         placeholder: placeholder, domIdentifier: id)
    }
    private func en(_ f: FieldRules.Field, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(FieldRules.isEnglish(f), "영문이어야 함: \(f)", file: file, line: line)
    }
    private func ko(_ f: FieldRules.Field, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(FieldRules.isEnglish(f), "한글이어야 함: \(f)", file: file, line: line)
    }

    func testLogin() {
        en(web(["아이디 또는 전화번호"], id: "id"))                       // 네이버
        en(web(subrole: "AXSecureTextField"))                            // 비밀번호
        en(web(["Email or phone"], id: "identifierId"))                  // 구글
        en(web([], placeholder: "name@example.com"))
    }

    /// B16: 대법원 전자가족관계등록시스템·간편인증(oacx) 실측 칸 (axprobe)
    func testCourtAndSimpleAuth() {
        en(web(["주민등록번호 앞자리", "주민등록번호 앞자리"], id: "rrn1"))
        en(web(["주민등록번호", "주민번호 앞자리"], placeholder: "주민번호 앞자리", id: "oacx_num1"))
        en(web(["주민등록번호 뒷자리"], placeholder: "뒷자리", subrole: "AXSecureTextField"))
        en(web(["휴대폰 번호", "휴대폰번호 뒷자리 여덟자리"], placeholder: "12341234", id: "oacx_phone2"))
        ko(web(["성명", "배우자 성명"], id: "addNm"))
    }

    func testPhone() {
        en(web(["휴대폰 번호"]))
        en(web([], placeholder: "010-0000-0000"))
        en(web([], placeholder: "예) 01012345678"))
        en(web([], id: "hp1"))
        en(web([], id: "mobileNo"))
        en(web(["연락처"]))
    }

    func testCard() {
        en(web(["카드번호"]))
        en(web([], placeholder: "0000 0000 0000 0000"))
        en(web([], placeholder: "MM/YY"))
        en(web(["CVC"]))
        en(web([], id: "cardNo2"))
        en(web(["유효기간 (월/년)"]))
    }

    func testDateAndCodes() {
        en(web(["생년월일 8자리"]))
        en(web([], placeholder: "YYYY-MM-DD"))
        en(web([], id: "birth_yyyy"))
        en(web(["인증번호 6자리"]))
        en(web(["우편번호"]))
        en(web([], role: "AXIncrementor"))                               // 숫자 칸
        en(web(["웹사이트 주소"]))
    }

    /// 브라우저가 알려주는 칸 종류 (실제 측정값: 사파리·크롬·엣지, 한국어·영어 맥)
    func testInputTypeFromRoleDescription() {
        func typed(_ desc: String, role: String = "AXTextField") -> FieldRules.Field {
            FieldRules.Field(role: role, roleDescription: desc)
        }
        en(typed("전화번호 필드"))      // 사파리 tel
        en(typed("숫자 필드"))          // 사파리 number
        en(typed("이메일 필드"))        // 사파리 email
        en(typed("URL 필드"))           // 사파리 url
        en(typed("전화번호"))           // 크롬 tel
        en(typed("이메일"))             // 크롬 email
        en(typed("URL"))                // 크롬 url
        en(typed("증감자", role: "AXIncrementor"))   // 크롬 number·date
        en(typed("스테퍼", role: "AXIncrementor"))   // 사파리 date
        en(typed("telephone field"))
        en(typed("number field"))
        en(typed("email field"))
        ko(typed("텍스트 필드"))
        ko(typed("text field"))
        ko(FieldRules.Field(role: "AXTextField", subrole: "AXSearchField", roleDescription: "텍스트 필드 검색"))
    }

    func testStaysKorean() {
        ko(web(["이름"], id: "name"))
        ko(web(["주소"], id: "addr1"))
        ko(web(["상세 주소"], id: "addr_detail"))
        ko(web(["검색어를 입력해 주세요."], id: "query"))
        ko(web(["메시지 입력"], id: "chat"))
        ko(web(["받는 분 이름"]))
        ko(web(["제목"], id: "subject"))
        ko(FieldRules.Field(role: "AXTextField", texts: ["주소창 및 검색창"], classList: "OmniboxViewViews"))
        ko(FieldRules.Field(role: "AXTextField", subrole: "AXSearchField", texts: ["Search"]))
        ko(FieldRules.Field(role: "AXTextArea", texts: ["전화번호"]))      // 여러 줄 글상자는 대상 아님
    }

    func testSplitWords() {
        XCTAssertEqual(FieldRules.splitWords("phoneNumber1"), ["phone", "number"])
        XCTAssertEqual(FieldRules.splitWords("card_no-2"), ["card", "no"])
        XCTAssertEqual(FieldRules.splitWords("hp1"), ["hp"])
    }
}
