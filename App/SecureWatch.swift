import Cocoa
import Carbon

/// B16: 보안 입력(비밀번호 칸·인증 보안 모듈 등)이 켜지면 맥이 모든 입력기를 막는다.
/// 사용자는 한/영이 안 먹거나 먹통이라고 느끼므로, 켜질 때와 풀릴 때 표시창으로 알린다.
/// 풀리면 맥이 OG키보드를 되살리므로 따로 할 일은 없다. 3초 넘게 다른 앱이 쥐고 있으면 그 앱 이름을 알린다.
enum SecureWatch {
    private static var on = false
    private static var since = Date()
    private static var warnedStuck = false

    static func start() {
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in tick() }
    }

    private static func tick() {
        let now = IsSecureEventInputEnabled()
        if now && !on {
            on = true
            since = Date()
            warnedStuck = false
            ModeIndicator.shared.showSecure("보안 입력")
            keyLog.info("보안 입력 켜짐 (\(SecureInput.holder?.localizedName ?? "?", privacy: .public))")
        } else if now && on && !warnedStuck && Date().timeIntervalSince(since) > 3 {
            // 비밀번호 칸을 떠났는데도 남아 있으면 쥐고 있는 앱이 앞 앱이 아님 → 그 앱을 알려준다
            if let h = SecureInput.holder, h.processIdentifier != NSWorkspace.shared.frontmostApplication?.processIdentifier {
                warnedStuck = true
                ModeIndicator.shared.showSecure("\(h.localizedName ?? "다른 앱") 보안 입력")
                keyLog.info("보안 입력 안 풀림: \(h.localizedName ?? "?", privacy: .public)이(가) 쥐고 있음")
            }
        } else if !now && on {
            on = false
            keyLog.info("보안 입력 풀림")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if InputSources.ogIsCurrent { ModeIndicator.shared.show(hangul: ModeState.hangul) }
            }
        }
    }
}
