import Foundation

/// 영문·숫자로 쓰는 입력칸인지 알아보는 규칙 (로그인·전화·카드·날짜·인증번호 등).
/// 윈도우는 웹페이지가 칸 종류(tel·number·email·url·password)를 표준 방식으로 알려줘 입력기가 영문으로 바꾸지만,
/// 맥은 그 정보가 입력기에 오지 않아 칸 이름·안내 글자·웹페이지 ID로 짐작한다.
public enum FieldRules {

    /// 칸 정보
    public struct Field {
        public var role: String?          // AXRole
        public var subrole: String?       // AXSubrole
        public var roleDescription: String?
        public var texts: [String]        // 칸 이름, 설명, 안내 글자(placeholder), 이름표
        public var placeholder: String?
        public var domIdentifier: String? // 웹페이지 칸 id
        public var identifier: String?    // AXIdentifier (앱 고유 이름, 예: 사파리 주소창)
        public var classList: String?

        public init(role: String? = nil, subrole: String? = nil, roleDescription: String? = nil,
                    texts: [String] = [], placeholder: String? = nil, domIdentifier: String? = nil,
                    identifier: String? = nil, classList: String? = nil) {
            self.role = role; self.subrole = subrole; self.roleDescription = roleDescription
            self.texts = texts; self.placeholder = placeholder; self.domIdentifier = domIdentifier
            self.identifier = identifier; self.classList = classList
        }
    }

    /// 글자 칸으로 보는 역할 (그 밖의 버튼·본문 등은 대상 아님)
    static let textRoles: Set<String> = ["AXTextField", "AXIncrementor", "AXDateField", "AXDateTimeArea"]

    /// 칸 이름·설명에 들어 있으면 영문 칸 (소문자로 비교)
    static let phrases: [String] = [
        // 로그인
        "이메일", "메일 주소", "아이디", "비밀번호", "계정", "사용자 이름", "로그인",
        "email", "e-mail", "password", "passwd", "username", "user name", "user id", "login", "sign in", "account",
        // 전화
        "휴대폰", "휴대전화", "핸드폰", "전화번호", "전화 번호", "연락처", "휴대번호",
        "phone", "mobile", "telephone", "tel.",
        // 카드·결제
        "카드번호", "카드 번호", "유효기간", "유효 기간", "보안코드", "보안 코드", "cvc", "cvv", "계좌번호", "계좌 번호",
        "card number", "credit card", "expiration", "expiry", "security code",
        // 날짜
        "생년월일", "생일", "날짜", "yyyy", "yymmdd", "mm/dd", "mm/yy", "date of birth", "birthday", "birth date",
        // 인증·코드
        "인증번호", "인증 번호", "인증코드", "인증 코드", "보안문자", "확인 코드", "확인코드", "otp",
        "verification", "one-time", "captcha", "promo code", "coupon code",
        // 번호류
        "우편번호", "주민등록번호", "주민번호", "사업자등록번호", "사업자 번호", "사업자번호", "외국인등록번호",
        "숫자만", "숫자로", "zip", "postal code", "postcode",
        // 주소류
        "웹사이트", "홈페이지", "도메인", "website", "url", "ip 주소", "ip address",
    ]

    /// 웹페이지 칸 id를 쪼갠 낱말에 있으면 영문 칸 (hp1 → hp, phoneNumber → phone/number, card_no → card/no)
    static let tokens: Set<String> = [
        "id", "pw", "pwd", "uid", "userid", "loginid", "login", "username", "email", "mail", "account", "passwd", "password",
        "phone", "mobile", "tel", "hp", "cell", "cellphone", "handphone",
        "card", "cardno", "ccnum", "cc", "cvc", "cvv", "csc", "exp", "expiry", "expire",
        "birth", "birthday", "bday", "dob", "date", "yyyy", "yy", "mm", "dd", "year", "month", "day",
        "zip", "zipcode", "postcode", "postal", "otp", "authcode", "auth", "verify", "verification", "captcha", "code",
        "number", "num", "amount", "price", "qty", "quantity",
        "url", "website", "homepage", "domain", "ip",
        "ssn", "rrn", "jumin", "bizno", "acct", "bank",
    ]

    /// 브라우저가 칸 종류를 '역할 설명'으로 알려주는 경우 (input type=tel·number·email·url).
    /// 사파리: "전화번호 필드", "숫자 필드", "이메일 필드", "URL 필드" / 크롬·엣지: "전화번호", "이메일", "URL"
    /// 맥 언어가 영어면 "telephone field", "number field", "email field", "URL field" 등
    static let typeDescriptions: [String] = [
        "전화번호", "숫자 필드", "이메일", "url",
        "telephone", "phone", "number field", "email", "e-mail",
    ]

    /// 이 낱말이 있으면 영문 칸이 아님 (검색창, 이름, 한글 주소 등)
    static let excludes: [String] = ["검색", "search", "받는 분", "받는분", "메시지", "message", "메모", "제목", "내용", "댓글"]

    public static func isEnglish(_ f: Field) -> Bool {
        // 비밀번호 칸
        if f.subrole == "AXSecureTextField" { return true }
        guard let role = f.role, textRoles.contains(role), f.subrole != "AXSearchField" else { return false }
        // 브라우저 주소창
        let ident = f.identifier ?? "", cls = f.classList ?? ""
        if ident.contains("ADDRESS") || ident.contains("SEARCH") || cls.contains("Omnibox") { return false }

        // 웹페이지가 칸 종류를 밝힌 경우가 가장 확실 (윈도우와 같은 기준)
        let desc = (f.roleDescription ?? "").lowercased()
        if typeDescriptions.contains(where: desc.contains) { return true }

        let text = (f.texts + [f.placeholder ?? "", f.roleDescription ?? ""]).joined(separator: " ").lowercased()
        if excludes.contains(where: text.contains) { return false }
        // 숫자 칸·날짜 칸 (브라우저가 역할로 알려주는 경우)
        if role == "AXIncrementor" || role == "AXDateField" || role == "AXDateTimeArea" { return true }
        if phrases.contains(where: text.contains) { return true }
        if let p = f.placeholder, looksLikeFormat(p) { return true }
        let words = splitWords(text + " " + (f.domIdentifier ?? ""))
        return words.contains(where: tokens.contains)
    }

    /// 안내 글자가 서식 견본인지: "010-0000-0000", "YYYY-MM-DD", "MM/YY", "0000 0000 0000 0000", "name@example.com"
    static func looksLikeFormat(_ s: String) -> Bool {
        var t = s.trimmingCharacters(in: .whitespaces)
        // "예) 010-1234-5678", "예: 2000-01-01", "ex) 01012345678" 같은 앞머리 떼기
        for prefix in ["예)", "예:", "예 :", "예시)", "예시:", "ex)", "ex:", "e.g.", "eg)"] where t.lowercased().hasPrefix(prefix) {
            t = String(t.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            break
        }
        guard !t.isEmpty else { return false }
        if t.contains("@") && !t.contains(" ") { return true }
        let allowed = CharacterSet(charactersIn: "0123456789-/.:()+ _*xXYyMmDd#")
        guard t.unicodeScalars.allSatisfy(allowed.contains) else { return false }
        let digits = t.filter(\.isNumber).count
        let ymd = t.uppercased().contains("YY") || t.uppercased().contains("MM") || t.uppercased().contains("DD")
        return digits >= 3 || ymd
    }

    /// 낱말 쪼개기: 낙타 표기·밑줄·하이픈·숫자를 경계로 (phoneNumber1 → phone, number)
    static func splitWords(_ s: String) -> [String] {
        var out: [String] = []
        var cur = ""
        var prevLower = false
        for ch in s {
            if ch.isLetter && ch.isASCII {
                if ch.isUppercase && prevLower { out.append(cur); cur = "" }
                cur.append(ch)
                prevLower = ch.isLowercase
            } else {
                if !cur.isEmpty { out.append(cur); cur = "" }
                prevLower = false
            }
        }
        if !cur.isEmpty { out.append(cur) }
        return out.map { $0.lowercased() }
    }
}
