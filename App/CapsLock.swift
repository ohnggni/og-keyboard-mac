import Cocoa
import IOKit
import IOKit.hidsystem

/// 대문자 고정 상태를 직접 켜고 끈다 (Caps Lock 짧게 = 한/영 처리용)
enum CapsLock {
    static func set(_ on: Bool) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        var connect: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connect) == KERN_SUCCESS else { return }
        defer { IOServiceClose(connect) }
        IOHIDSetModifierLockState(connect, Int32(kIOHIDCapsLockState), on)
    }

    /// Caps Lock 키가 지금 물리적으로 눌려 있는지
    static var isPressed: Bool {
        CGEventSource.keyState(.hidSystemState, key: 57)
    }
}
