import Cocoa

/// 마지막 글자 사라짐 방지.
/// 클릭이나 앱 전환(⌘Tab)이 일어나면 맥은 포커스가 이미 넘어간 뒤에 입력기에 '입력 끝'을 알린다.
/// 그때 조합 중이던 글자를 보내면 Electron 앱(Claude 등)·터미널은 떠난 칸으로 온 글자를 버린다.
/// 그래서 클릭·왼쪽 ⌘가 앱에 전달되기 직전에 가로채 조합 중인 글자를 먼저 확정하고, 원래 동작은 그대로 보낸다.
/// (손쉬운 사용 권한 필요. 조합 중인 글자가 없으면 아무것도 하지 않는다)
enum CommitGuard {
    private static var tap: CFMachPort?

    static func start() {
        let types: [CGEventType] = [.leftMouseDown, .rightMouseDown, .otherMouseDown, .flagsChanged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }
        guard let t = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, _ in
                switch type {
                case .tapDisabledByTimeout, .tapDisabledByUserInput:
                    CommitGuard.reenable()
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
