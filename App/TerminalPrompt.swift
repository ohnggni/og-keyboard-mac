import Cocoa
import ApplicationServices

/// F2: 터미널에서 암호·계정을 물으면 잠깐 영문으로.
/// - 화면을 읽을 수 있는 터미널(iTerm2·맥 터미널): Enter 뒤 화면 마지막 줄이 프롬프트 모양이면 (`PromptRules.isSecretPrompt`)
/// - 화면을 못 읽는 터미널(Termix 등): Enter 직전에 친 명령이 sudo·ssh 등이면 (`PromptRules.asksSecret`)
/// 다음 Enter·Ctrl+C에서 원래대로. 그 사이 직접 한글로 바꿨으면 그대로 둔다. 앱별 기억에는 남기지 않는다.
/// 설정은 '영문·숫자 칸에서 자동 영문'(FieldWatcher.enabled)을 함께 쓴다.
enum TerminalPrompt {
    /// 우리가 영문으로 바꿨는지 (바꿨으면 다음 Enter에 한글로 되돌림)
    private static var switched = false
    /// Enter마다 늘림: 이전 Enter의 늦은 확인이 뒤늦게 적용되지 않게
    private static var generation = 0
    private static let queue = DispatchQueue(label: "kr.ogapp.terminalprompt")
    private static let delays: [Double] = [0.3, 0.8, 1.5, 3.0]

    /// 이벤트 탭이 Enter를 볼 때 (입력기가 그 키를 받는지와 상관없이). line = Enter 직전 줄에 친 글자(입력기 기록)
    static func onEnter(line: String) {
        restore()
        guard FieldWatcher.enabled, InputSources.ogIsCurrent,
              let app = NSWorkspace.shared.frontmostApplication,
              let id = app.bundleIdentifier, Terminals.contains(id) else { return }
        generation += 1
        let gen = generation
        let pid = app.processIdentifier
        schedule(step: 0, gen: gen, pid: pid, line: line)
    }

    /// Ctrl+C: 프롬프트를 그만둔 것으로 보고 원래대로
    static func onCancel() {
        generation += 1
        restore()
    }

    /// 직접 한/영을 바꾸면 되돌리기를 그만둔다
    static func userToggled() { switched = false }

    private static func schedule(step: Int, gen: Int, pid: pid_t, line: String) {
        guard step < delays.count else { return }
        let wait = delays[step] - (step > 0 ? delays[step - 1] : 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
            guard gen == generation, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
            queue.async {
                let screen = readLastLine(pid)
                DispatchQueue.main.async {
                    guard gen == generation else { return }
                    switch screen {
                    case .unreadable:
                        // 화면을 못 읽는 터미널: 명령으로 판단 (한 번만)
                        if PromptRules.asksSecret(command: line) { switchToEnglish("명령") }
                    case .line(let l):
                        if PromptRules.isSecretPrompt(l) { switchToEnglish("화면") }
                        else { schedule(step: step + 1, gen: gen, pid: pid, line: line) }
                    }
                }
            }
        }
    }

    private enum Screen { case unreadable, line(String) }

    /// 앞 앱의 커서 칸 글자에서 마지막 줄 (백그라운드에서, 0.3초 넘으면 포기)
    private static func readLastLine(_ pid: pid_t) -> Screen {
        let ax = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(ax, 0.3)
        var f: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ax, kAXFocusedUIElementAttribute as CFString, &f) == .success,
              let focused = f else { return .unreadable }
        let e = focused as! AXUIElement
        var r: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(e, kAXRoleAttribute as CFString, &r)
        var v: CFTypeRef?
        guard (r as? String) == "AXTextArea",
              AXUIElementCopyAttributeValue(e, kAXValueAttribute as CFString, &v) == .success,
              let text = v as? String, !text.isEmpty else { return .unreadable }
        return .line(PromptRules.lastLine(text) ?? "")
    }

    private static func switchToEnglish(_ how: String) {
        guard ModeState.hangul else { return }
        InputController.active?.commit(nil)
        ModeState.setTransient(hangul: false)
        ModeIndicator.shared.show(hangul: false)
        switched = true
        keyLog.info("터미널 암호 프롬프트(\(how, privacy: .public)) → 영문")
    }

    private static func restore() {
        guard switched else { return }
        switched = false
        guard !ModeState.hangul else { return }   // 그 사이 직접 한글로 바꿨으면 그대로
        ModeState.setTransient(hangul: true)
        ModeIndicator.shared.show(hangul: true)
        keyLog.info("터미널 암호 입력 끝 → 한글")
    }
}
