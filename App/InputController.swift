import Cocoa
import InputMethodKit
import os

let keyLog = Logger(subsystem: "kr.ogapp.inputmethod.OGKeyboard", category: "key")

/// 한/영 상태와 자판. 한/영은 앱별로 기억 (켜져 있을 때)
enum ModeState {
    private static let defaults = UserDefaults.standard

    static var hangul = true {
        didSet {
            if rememberPerApp, let app = currentApp, appModes[app] != hangul {
                appModes[app] = hangul
                defaults.set(appModes, forKey: "appModes")
            }
            StatusBar.shared.update()
        }
    }
    static var layout = Layouts.byId(defaults.string(forKey: "layout") ?? "390") {
        didSet {
            defaults.set(layout.id, forKey: "layout")
            StatusBar.shared.update()
        }
    }

    /// 지금 입력 중인 앱(번들 ID)
    private(set) static var currentApp: String?
    private static var appModes = defaults.dictionary(forKey: "appModes") as? [String: Bool] ?? [:]

    static var rememberPerApp: Bool {
        get { defaults.object(forKey: "rememberPerApp") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "rememberPerApp"); StatusBar.shared.update() }
    }

    /// 입력창이 활성화될 때: 그 앱의 마지막 한/영으로. 처음 보는 앱은 지금 상태 그대로.
    static func activate(app: String?) {
        currentApp = app
        guard rememberPerApp, let app = app, let saved = appModes[app], saved != hangul else { return }
        hangul = saved
        keyLog.info("앱 \(app, privacy: .public) → \(saved ? "한글" : "영문", privacy: .public)")
    }

    static func clearAppModes() {
        appModes = [:]
        defaults.removeObject(forKey: "appModes")
    }
}

/// 맥 가상 키 코드 (Carbon kVK_*)
private enum Key {
    static let delete: UInt16 = 51
    static let space: UInt16 = 49
    static let rightCommand: UInt16 = 54
    static let rightOption: UInt16 = 61
}

@objc(OGInputController)
final class InputController: IMKInputController {

    private let engine = HangulEngine()
    /// 눌려 있는 '단독 탭' 후보 수식키(오른쪽 Command/Option). 누른 채 다른 키를 쓰면 tapUsed → 뗄 때 무시
    private var tapKey: UInt16? = nil
    private var tapUsed = false

    // MARK: 시스템 콜백

    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask([.keyDown, .flagsChanged]).rawValue)
    }

    override func activateServer(_ sender: Any!) {
        // 키 → 글자 변환을 US 배열로 고정 (자판 표가 US 기준)
        (sender as? IMKTextInput)?.overrideKeyboard(withKeyboardNamed: "com.apple.keylayout.US")
        engine.dubeol = ModeState.layout.dubeol
        tapKey = nil
        ModeState.activate(app: textClient(sender)?.bundleIdentifier())
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

        if tapKey != nil { tapUsed = true }

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

        engine.dubeol = ModeState.layout.dubeol
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

    // MARK: 단독 탭: 오른쪽 Command = 한/영, 오른쪽 Option = 한자(예정)

    private func handleFlags(_ event: NSEvent, _ sender: Any!) -> Bool {
        keyLog.info("flags keyCode=\(event.keyCode, privacy: .public) raw=0x\(String(event.modifierFlags.rawValue, radix: 16), privacy: .public)")
        // 입력기로 오는 이벤트엔 좌우 구분 비트가 빠져 있음 → 키 코드로 오른쪽을 구분하고 수식 비트로 누름/뗌 판단
        let flag: NSEvent.ModifierFlags
        switch event.keyCode {
        case Key.rightCommand: flag = .command
        case Key.rightOption: flag = .option
        default:
            if tapKey != nil { tapUsed = true }
            return false
        }
        if event.modifierFlags.contains(flag) {
            if tapKey == event.keyCode { return false }   // 크롬·Electron 앱은 같은 신호를 두 번 보냄 → 무시
            if tapKey != nil { tapUsed = true }           // 다른 탭 키를 누른 채 눌렀으면 둘 다 무효
            else { tapKey = event.keyCode; tapUsed = false }
        } else if tapKey == event.keyCode {
            let used = tapUsed
            tapKey = nil
            if !used { onTap(event.keyCode, sender) }
        }
        return false
    }

    private func onTap(_ keyCode: UInt16, _ sender: Any!) {
        switch keyCode {
        case Key.rightCommand: toggleMode(sender)
        case Key.rightOption: keyLog.info("한자 키 (아직 미구현)")
        default: break
        }
    }

    private func toggleMode(_ sender: Any!) {
        commit(sender)
        ModeState.hangul.toggle()
        keyLog.info("toggle → \(ModeState.hangul ? "한글" : "영문", privacy: .public)")
        ModeIndicator.shared.show(hangul: ModeState.hangul)
    }

    // MARK: 도우미

    /// 누른 키의 ASCII(0x21~0x7E). Caps Lock은 1단계에선 무시하고 Shift만 반영.
    private func asciiOf(_ event: NSEvent) -> Int? {
        // charactersIgnoringModifiers는 입력기 쪽에서 Shift까지 빼버림(Shift+1 → "1") → characters 사용.
        // Cmd/Ctrl/Option 조합은 이 함수 전에 걸러지므로 여기선 Shift·Caps Lock만 반영됨.
        keyLog.debug("key code=\(event.keyCode, privacy: .public) chars=\(event.characters ?? "", privacy: .public) ign=\(event.charactersIgnoringModifiers ?? "", privacy: .public)")
        guard let s = event.characters, s.unicodeScalars.count == 1,
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
