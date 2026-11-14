import Cocoa

/// 마지막 글자 사라짐 방지.
/// 클릭이나 앱 전환(⌘Tab)이 일어나면 맥은 포커스가 이미 넘어간 뒤에 입력기에 '입력 끝'을 알린다.
/// 그때 조합 중이던 글자를 보내면 Electron 앱(Claude 등)·터미널은 떠난 칸으로 온 글자를 버린다.
/// 그래서 클릭·왼쪽 ⌘가 앱에 전달되기 직전에 가로채 조합 중인 글자를 먼저 확정하고, 원래 동작은 그대로 보낸다.
/// (손쉬운 사용 권한 필요. 조합 중인 글자가 없으면 아무것도 하지 않는다)
///
/// B15: 맥 터미널은 Enter 등 일부 키를 입력기에 넘기지 않는다 (실기 DIAG: Enter keyDown이 입력기에 안 옴).
/// 그래서 글자 기록(TypedText)이 줄을 넘어 남아 다음 줄 바로잡기에 섞였다 → 여기서 키를 보고 기록을 끊는다.
enum CommitGuard {
    private static var tap: CFMachPort?

    static func start() {
        let types: [CGEventType] = [.leftMouseDown, .rightMouseDown, .otherMouseDown, .flagsChanged, .keyDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }
        guard let t = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, _ in
                switch type {
                case .tapDisabledByTimeout, .tapDisabledByUserInput:
                    CommitGuard.reenable()
                case .keyDown:
                    CommitGuard.noteKey(event)
                case .flagsChanged:
                    // 왼쪽 ⌘(55)를 누를 때만: ⌘Tab·⌘단축키 직전에 확정 (오른쪽 ⌘는 한/영 키라 제외)
                    if event.getIntegerValueField(.keyboardEventKeycode) == 55, event.flags.contains(.maskCommand) {
                        CommitGuard.flush()
                    }
                default:
                    CommitGuard.flush()
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: nil)
        else {
            keyLog.info("확정 보호를 켜지 못함 (손쉬운 사용 권한 필요)")
            return
        }
        tap = t
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, t, 0), .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        keyLog.info("확정 보호 켜짐")
    }

    /// 줄 바꿈·커서 이동·단축키면 글자 기록을 끊는다 (입력기가 이 키를 받든 못 받든)
    private static let breakKeys: Set<Int64> = [
        36, 76,                 // Return, 키패드 Enter
        48, 53,                 // Tab, Esc
        123, 124, 125, 126,     // 방향키
        115, 119, 116, 121, 117 // Home, End, PageUp, PageDown, Forward Delete
    ]

    /// 입력기가 아직 받지 못한 Backspace 수 (입력기가 받으면 claimBackspace로 가져감)
    private static var unclaimedBackspaces = 0

    /// 입력기가 Backspace를 직접 받았으면 탭 쪽 처리를 취소 (두 번 지우지 않게)
    static func claimBackspace() {
        if unclaimedBackspaces > 0 { unclaimedBackspaces -= 1 }
    }

    private static func noteKey(_ event: CGEvent) {
        if event.getIntegerValueField(.eventSourceUserData) == KeySender.marker { return }   // 우리가 보낸 키
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        // B15: 맥 터미널은 조합 글자가 없으면 Backspace도 입력기에 안 넘긴다 (실기 DIAG).
        // 입력기가 0.05초 안에 받지 않으면 여기서 기록의 마지막 글자를 지운다.
        if code == 51 && event.flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty {
            unclaimedBackspaces += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                guard unclaimedBackspaces > 0 else { return }
                unclaimedBackspaces -= 1
                if let c = InputController.active, c.hanja != nil || c.emojiSession != nil { return }
                TypedText.dropLast()
            }
            return
        }
        // ⌥Backspace(낱말 지우기)도 기록을 끊는다
        let shortcut = !event.flags.intersection([.maskCommand, .maskControl]).isEmpty
            || (code == 51 && event.flags.contains(.maskAlternate))
        guard breakKeys.contains(code) || shortcut else { return }
        // 입력기가 이 키를 받으면 조합 확정·기록이 먼저 처리되도록 조금 뒤에 끊는다
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if let c = InputController.active, c.hanja != nil || c.emojiSession != nil { return }   // 후보 창 안의 이동
            TypedText.clear()
        }
    }

    private static func reenable() {
        if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
    }

    /// 조합 중인 글자가 있으면 지금 칸에 확정 (한자·이모지 창이 열려 있으면 그 창이 처리하므로 건드리지 않음)
    private static func flush() {
        guard let c = InputController.active, c.hasComposition,
              c.hanja == nil, c.emojiSession == nil else { return }
        c.commit(nil)
        keyLog.debug("클릭·⌘ 전에 조합 글자 확정")
    }
}
