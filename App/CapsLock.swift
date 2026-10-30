import Cocoa
import Carbon
import IOKit
import IOKit.hid
import IOKit.hidsystem

/// 대문자 고정 상태를 직접 켜고 끈다
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

    static var isOn: Bool {
        CGEventSource.flagsState(.hidSystemState).contains(.maskAlphaShift)
    }
}

/// Caps Lock 키의 누름·뗌을 키보드 장치에서 직접 듣는다 (입력기에는 뗌 신호가 오지 않아서).
/// 짧게(0.4초 미만) = 한/영 + 대문자 고정 되돌림, 길게 = 대문자 고정 유지. '입력 모니터링' 권한 필요.
final class CapsMonitor {
    static let shared = CapsMonitor()

    /// 짧게 눌렀을 때 (OG키보드가 지금 입력 소스일 때만 불림)
    var onTap: (() -> Void)?
    private var manager: IOHIDManager?
    private var downAt: Date?
    /// 한글 상태에서 대문자 고정을 켰으면, 풀 때 한글로 돌아간다
    private var restoreHangul = false
    private let longPress: TimeInterval = 0.4

    func start() {
        if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) != kIOHIDAccessTypeGranted {
            keyLog.info("입력 모니터링 권한 요청")
            IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
        let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(m, [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard,
        ] as CFDictionary)
        IOHIDManagerSetInputValueMatching(m, [
            kIOHIDElementUsagePageKey: kHIDPage_KeyboardOrKeypad,
            kIOHIDElementUsageKey: kHIDUsage_KeyboardCapsLock,
        ] as CFDictionary)
        let me = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(m, { ctx, _, _, value in
            guard let ctx = ctx else { return }
            let monitor = Unmanaged<CapsMonitor>.fromOpaque(ctx).takeUnretainedValue()
            let pressed = IOHIDValueGetIntegerValue(value) != 0
            DispatchQueue.main.async { monitor.handle(pressed: pressed) }
        }, me)
        IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let r = IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone))
        keyLog.info("Caps Lock 감시 시작: \(r == kIOReturnSuccess ? "성공" : "오류 \(r)", privacy: .public)")
        manager = m
    }

    private func handle(pressed: Bool) {
        if pressed {
            if downAt == nil { downAt = Date() }   // 장치가 여럿이면 같은 누름이 두 번 올 수 있음
            return
        }
        guard let start = downAt else { return }
        downAt = nil
        let held = Date().timeIntervalSince(start)
        guard Self.ogIsCurrent else { return }
        // 뗄 때쯤엔 맥이 이미 대문자 고정을 바꿔 둔 상태
        let on = CapsLock.isOn
        keyLog.info("Caps Lock \(held, format: .fixed(precision: 2), privacy: .public)초, 대문자 고정 \(on ? "켜짐" : "꺼짐", privacy: .public)")
        if held < longPress && on {
            CapsLock.set(false)        // 짧게: 방금 켜진 대문자 고정을 되돌리고 한/영
            onTap?()
        } else if on {
            // 길게: 대문자 고정 = 영문 대문자. 한글이었으면 영문으로 바꾸고, 풀 때 한글로 되돌린다
            if ModeState.hangul {
                InputController.active?.commit(nil)
                restoreHangul = true
                ModeState.hangul = false
            }
            ModeIndicator.shared.showCaps()
        } else {
            // 대문자 고정 해제: 길게 누르기 전 상태로
            if restoreHangul {
                restoreHangul = false
                ModeState.hangul = true
            }
            ModeIndicator.shared.show(hangul: ModeState.hangul)
        }
    }

    /// 지금 입력 소스가 OG키보드인지
    static var ogIsCurrent: Bool {
        let s = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let v = TISGetInputSourceProperty(s, kTISPropertyInputSourceID) else { return false }
        let id = Unmanaged<CFString>.fromOpaque(v).takeUnretainedValue() as String
        return id.hasPrefix(Bundle.main.bundleIdentifier ?? "kr.ogapp.inputmethod.OGKeyboard")
    }
}
