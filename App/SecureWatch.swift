import Cocoa
import Carbon

/// B16: 보안 입력(비밀번호 칸·인증 보안 모듈 등)이 켜지면 맥이 모든 입력기를 막는다.
/// 사용자는 한/영이 안 먹거나 먹통이라고 느끼므로, 켜질 때와 풀릴 때 표시창으로 알린다.
/// 3초 넘게 다른 앱이 쥐고 있으면 그 앱 이름을 알린다.
/// 보안 입력 중에는 맥이 입력기를 순정(ABC)으로 바꾸고, 풀리면 되돌려야 하는데 자주 순정에 남겨 둔다 (실기).
/// 입력기가 바뀔 때 보안 입력이 켜져 있었으면 '맥이 바꾼 것'으로 보고, 풀리면 시간과 상관없이 OG키보드로 되돌린다.
/// 보안 입력이 꺼진 상태에서 바뀐 것은 사용자가 직접 바꾼 것이므로 건드리지 않는다.
enum SecureWatch {
    private static var on = false
    private static var since = Date()
    private static var warnedStuck = false
    /// 마지막으로 본 입력기가 OG키보드였는지 (바뀜 알림에서 '어디서 어디로'를 알기 위해)
    private static var lastWasOG = false
    /// 보안 입력 때문에 맥이 OG키보드 → 순정으로 바꿨음 (풀리면 되돌림)
    private static var systemSwitched = false

    static func start() {
        lastWasOG = InputSources.ogIsCurrent
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main) { _ in sourceChanged() }
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in tick() }
    }

    /// 입력기가 바뀜: 보안 입력 중이면 맥이 바꾼 것, 아니면 사용자가 바꾼 것
    private static func sourceChanged() {
        let og = InputSources.ogIsCurrent
        let secure = IsSecureEventInputEnabled()
        if lastWasOG && !og && secure {
            systemSwitched = true
            keyLog.info("보안 입력 때문에 순정으로 바뀜 → 풀리면 되돌림")
        } else if og {
            systemSwitched = false
        } else if !secure && !og {
            if systemSwitched { keyLog.info("보안 입력 밖에서 직접 바꿈 → 되돌리지 않음") }
            systemSwitched = false
        }
        lastWasOG = og
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
            keyLog.info("보안 입력 풀림 (되돌릴 것=\(systemSwitched, privacy: .public))")
            restoreIfNeeded()
        } else if !now && systemSwitched {
            restoreIfNeeded()   // 맥이 늦게 다시 순정으로 돌려놓는 경우까지 계속 확인
        }
    }

    private static func restoreIfNeeded() {
        guard systemSwitched, !InputSources.ogIsCurrent else { return }
        if let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier, Fallback.apps.contains(app) { return }
        let ok = InputSources.select(InputSources.ogID)
        keyLog.info("보안 입력 뒤 순정에 남음 → OG키보드로 되돌림 \(ok ? "성공" : "실패", privacy: .public)")
        if ok { ModeIndicator.shared.show(hangul: ModeState.hangul) }
    }
}
