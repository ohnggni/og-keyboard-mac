import XCTest
@testable import HangulCore

/// F2: 터미널 암호 프롬프트 알아보기
final class PromptRulesTests: XCTestCase {
    func testPrompts() {
        for s in ["[sudo] password for ubuntu:", "Password:", "Password: ", "Enter passphrase for key '/Users/a/.ssh/id_ed25519':",
                  "ubuntu@10.0.0.2's password:", "Password for 'https://x@github.com':", "login:", "Username:",
                  "Enter PIN:", "Verification code:", "암호:", "비밀번호:", "Retype new password:", "Are you sure you want to continue connecting (yes/no/[fingerprint])?"] {
            XCTAssertTrue(PromptRules.isSecretPrompt(s), s)
        }
    }

    func testNotPrompts() {
        for s in ["ohnggni@Mac ~ %", "echo password", "Last login: Tue Nov 17 06:21:00 on ttys001", "ping: cannot resolve",
                  "grep -r password .", "ubuntu@dellubuntu:~$", ""] {
            XCTAssertFalse(PromptRules.isSecretPrompt(s), s)
        }
    }

    func testCommands() {
        for c in ["sudo apt update", "sudo -k; sudo ls", "su -", "ssh ubuntu@dellubuntu", "passwd", "mysql -u root -p", "docker login"] {
            XCTAssertTrue(PromptRules.asksSecret(command: c), c)
        }
        for c in ["ls", "sudoku", "echo sudo", "ssh-keygen", "mysql -u root", "supervisorctl status", ""] {
            XCTAssertFalse(PromptRules.asksSecret(command: c), c)
        }
    }

    func testLastLine() {
        XCTAssertEqual(PromptRules.lastLine("a\nb  \n\n  "), "b")
        XCTAssertNil(PromptRules.lastLine("\n \n"))
    }
}
