import Foundation

/// F2: 터미널에서 암호·계정을 묻는 순간 알아보기 (영문 자동 전환용)
public enum PromptRules {
    /// 화면 마지막 줄이 암호·계정 프롬프트인가 (`[sudo] password for ubuntu:`, `Password:`, `Enter passphrase for key '…':` 등)
    /// ssh 첫 접속의 `(yes/no/[fingerprint])?`도 포함. 낱말이 들어 있고 줄이 `:`나 `?`로 끝나야 한다 → `echo password` 같은 명령 줄은 걸리지 않음
    private static let promptRegex = try! NSRegularExpression(
        pattern: #"(password|passphrase|passcode|\bpin\b|\botp\b|verification code|\blogin\b|username|user name|암호|비밀번호|인증\s*번호|yes/no)[^\n]{0,100}[:?]$"#,
        options: [.caseInsensitive])

    /// 화면을 못 읽는 터미널(Termix 등)용: Enter 직전에 친 명령이 암호를 물을 만한가
    private static let commandRegex = try! NSRegularExpression(
        pattern: #"^(sudo|su|doas|ssh|passwd|kinit|docker\s+login|gh\s+auth\s+login|npm\s+login|(mysql|mariadb)\b.*\s-p)(\s|$)"#,
        options: [])

    public static func isSecretPrompt(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, t.count <= 160 else { return false }
        return promptRegex.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) != nil
    }

    public static func asksSecret(command: String) -> Bool {
        let t = command.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return false }
        return commandRegex.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) != nil
    }

    /// 글자 전체에서 빈 줄이 아닌 마지막 줄
    public static func lastLine(_ text: String) -> String? {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty }
    }
}
