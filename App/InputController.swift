import Cocoa
import InputMethodKit
import os

let log = Logger(subsystem: "kr.ogapp.inputmethod.OGKeyboard", category: "key")

/// 한/영 상태 (1단계: 모든 앱 공통. 앱별 기억은 나중에)
enum ModeState {
    static var hangul = true
    static var layout = Layouts.l390
}

/// 맥 가상 키 코드 (Carbon kVK_*)
private enum Key {
    static let delete: UInt16 = 51
    static let space: UInt16 = 49
    static let rightOption: UInt16 = 61
}

/// NX_DEVICERALTKEYMASK: 오른쪽 Option이 눌려 있음
private let rightOptionMask: UInt = 0x40

@objc(OGInputController)
final class InputController: IMKInputController {

    private let engine = HangulEngine()
    /// 오른쪽 Option을 누른 채 다른 키를 눌렀는지 (그랬으면 뗄 때 전환하지 않음)
    private var rightOptionDown = false
    private var rightOptionUsed = false

    // MARK: 시스템 콜백

    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask([.keyDown, .flagsChanged]).rawValue)
    }

    override func activateServer(_ sender: Any!) {
        // 키 → 글자 변환을 US 배열로 고정 (자판 표가 US 기준)
        (sender as? IMKTextInput)?.overrideKeyboard(withKeyboardNamed: "com.apple.keylayout.US")
        engine.dubeol = ModeState.layout.dubeol
        rightOptionDown = false
    }

    override func deactivateServer(_ sender: Any!) {
        commit(sender)
    }

    override func commitComposition(_ sender: Any!) {
        commit(sender)
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event = event else { return false }
        if event.type == .flagsChanged { return handleFlags(event, sender) }
        if event.type != .keyDown { return false }

        if rightOptionDown { rightOptionUsed = true }

        // Cmd/Ctrl/Option 조합 단축키: 조합 확정 후 앱으로
        let mods = event.modifierFlags.intersection([.command, .control, .option])
        if !mods.isEmpty {
            commit(sender)
            return false
        }

        // 영문 모드: 그대로 통과
        if !ModeState.hangul {
            commit(sender)
            return false
        }

        if event.keyCode == Key.delete {
            if engine.backspace() {
                updateMarked(sender)
                return true
            }
            return false
        }

        if event.keyCode == Key.space {
            insert(engine.flush() + " ", sender)
            return true
        }

        guard let ascii = asciiOf(event) else {
            // 엔터·탭·방향키 등: 조합만 확정하고 키는 앱이 처리
            commit(sender)
            return false
        }

        let v = ModeState.layout.map(ascii)
        if HangulEngine.isJamo(v) {
            let committed = engine.input(v)
            if !committed.isEmpty { insert(committed, sender) }
            updateMarked(sender)
        } else {
            insert(engine.flush() + String(UnicodeScalar(UInt32(v))!), sender)
        }
        return true
    }

    // MARK: 오른쪽 Option 짧게 = 한/영

    private func handleFlags(_ event: NSEvent, _ sender: Any!) -> Bool {
        log.info("flags keyCode=\(event.keyCode, privacy: .public) raw=0x\(String(event.modifierFlags.rawValue, radix: 16), privacy: .public)")
        guard event.keyCode == Key.rightOption else {
            if rightOptionDown { rightOptionUsed = true }
            return false
        }
        let down = event.modifierFlags.rawValue & rightOptionMask != 0
        if down {
            rightOptionDown = true
            rightOptionUsed = false
        } else if rightOptionDown {
            rightOptionDown = false
            if !rightOptionUsed { toggleMode(sender) }
        }
        return false
    }

    private func toggleMode(_ sender: Any!) {
        commit(sender)
        ModeState.hangul.toggle()
        log.info("toggle → \(ModeState.hangul ? "한글" : "영문", privacy: .public)")
        ModeIndicator.shared.show(hangul: ModeState.hangul)
    }

    // MARK: 도우미

    /// 누른 키의 ASCII(0x21~0x7E). Caps Lock은 1단계에선 무시하고 Shift만 반영.
    private func asciiOf(_ event: NSEvent) -> Int? {
        guard let s = event.charactersIgnoringModifiers, s.unicodeScalars.count == 1,
              var c = s.unicodeScalars.first?.value else { return nil }
        let shift = event.modifierFlags.contains(.shift)
        if c >= 0x41 && c <= 0x5a && !shift { c += 0x20 }       // Caps Lock 대문자 → 소문자
        else if c >= 0x61 && c <= 0x7a && shift { c -= 0x20 }
        guard c >= 0x21 && c <= 0x7e else { return nil }
        return Int(c)
    }

    private func textClient(_ sender: Any!) -> IMKTextInput? {
        if let c = sender as? IMKTextInput { return c }
        if let c = client() { return c }
        return nil
    }

    private func insert(_ text: String, _ sender: Any!) {
        guard !text.isEmpty else { return }
        textClient(sender)?.insertText(text, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
    }

    private func updateMarked(_ sender: Any!) {
        let s = engine.composing()
        textClient(sender)?.setMarkedText(s,
            selectionRange: NSRange(location: (s as NSString).length, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
    }

    private func commit(_ sender: Any!) {
        if engine.isEmpty { return }
        insert(engine.flush(), sender)
    }
}
