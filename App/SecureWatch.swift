import Cocoa
import Carbon

/// B16: 보안 입력(비밀번호 칸·인증 보안 모듈 등)이 켜지면 맥이 모든 입력기를 막는다.
/// 사용자는 한/영이 안 먹거나 먹통이라고 느끼므로, 켜질 때와 풀릴 때 표시창으로 알린다.
/// 3초 넘게 다른 앱이 쥐고 있으면 그 앱 이름을 알린다.
/// 풀리면 맥이 원래 입력기로 되돌려야 하는데, 보안 칸을 빠르게 오가 켜짐·꺼짐이 반복되면 순정(ABC)에 남겨 버린다
/// (실기 로그: 풀린 뒤 계속 'OG 아님'). 켜지기 직전에 OG키보드였으면 풀린 뒤 직접 되돌린다.
enum SecureWatch {
    private static var on = false
    private static var since = Date()
    private static var warnedStuck = false
    /// 보안 입력 전에 OG키보드를 쓰고 있었는지. 풀린 직후엔 맥이 아직 순정에 두므로 바로 다시 기록하면 안 된다
    /// (실기: 보안 칸을 두 번 이상 오가면 두 번째부터 '원래 순정'으로 기록돼 순정에 남음)
    private static var wantOG = false
    /// 마지막으로 풀린 때. 이 뒤 3초 동안은 wantOG를 유지하고, 순정에 남아 있으면 되돌린다
    private static var releasedAt = Date.distantPast
    private static let keepWindow: TimeInterval = 3

    static func start() {
        wantOG = InputSources.ogIsCurrent
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in tick() }
    }

    private static func tick() {
        let now = IsSecureEventInputEnabled()
        if now && !on {
            on = true
            since = Date()
            warnedStuck = false
            ModeIndicator.shared.showSecure("보안 입력")
            keyLog.info("보안 입력 켜짐 (\(SecureInput.holder?.localizedName ?? "?", privacy: .public)) OG였음=\(wantOG, privacy: .public)")
        } else if now && on && !warnedStuck && Date().timeIntervalSince(since) > 3 {
            // 비밀번호 칸을 떠났는데도 남아 있으면 쥐고 있는 앱이 앞 앱이 아님 → 그 앱을 알려준다
            if let h = SecureInput.holder, h.processIdentifier != NSWorkspace.shared.frontmostApplication?.processIdentifier {
                warnedStuck = true
                ModeIndicator.shared.showSecure("\(h.localizedName ?? "다른 앱") 보안 입력")
                keyLog.info("보안 입력 안 풀림: \(h.localizedName ?? "?", privacy: .public)이(가) 쥐고 있음")
            }
        } else if !now && on {
            on = false
            releasedAt = Date()
            keyLog.info("보안 입력 풀림")
        } else if !now {
            let og = InputSources.ogIsCurrent
            if Date().timeIntervalSince(releasedAt) < keepWindow {
                // 풀린 직후: OG였는데 순정에 남아 있으면 되돌린다 (몇 번이고)
                if wantOG && !og, let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier, !Fallback.apps.contains(app) {
                    let ok = InputSources.select(InputSources.ogID)
                    keyLog.info("보안 입력 뒤 순정에 남음 → OG키보드로 되돌림 \(ok ? "성공" : "실패", privacy: .public)")
                    if ok { ModeIndicator.shared.show(hangul: ModeState.hangul) }
                }
            } else {
                // 평소: 지금 입력기를 기억 (사용자가 직접 바꾼 것도 여기서 반영)
                wantOG = og
            }
        }
    }
}
