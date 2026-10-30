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

/// 한자 후보 창 키 처리용
enum HanjaKey {
    static let tab: UInt16 = 48, space: UInt16 = 49, returnKey: UInt16 = 36, enter: UInt16 = 76, escape: UInt16 = 53
    static let left: UInt16 = 123, right: UInt16 = 124, down: UInt16 = 125, up: UInt16 = 126
    static let pageUp: UInt16 = 116, pageDown: UInt16 = 121
}

@objc(OGInputController)
final class InputController: IMKInputController {

    let engine = HangulEngine()
    /// 열려 있는 한자 후보 (InputController+Hanja.swift)
    var hanja: HanjaSession?
    /// 눌려 있는 '단독 탭' 후보 수식키(오른쪽 Command/Option). 누른 채 다른 키를 쓰면 tapUsed → 뗄 때 무시
    private var tapKey: UInt16? = nil
    private var tapUsed = false
    /// 오른쪽 Command 길게 = 바로잡기
    private var longWork: DispatchWorkItem?
    private var longFired = false
    private let longPressDelay = 0.4

    // MARK: 시스템 콜백

    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask([.keyDown, .flagsChanged]).rawValue)
    }

    override func activateServer(_ sender: Any!) {
        // 키 → 글자 변환을 US 배열로 고정 (자판 표가 US 기준)
        (sender as? IMKTextInput)?.overrideKeyboard(withKeyboardNamed: "com.apple.keylayout.US")
        engine.dubeol = ModeState.layout.dubeol
        tapKey = nil
        TypedText.clear()
        ModeState.activate(app: textClient(sender)?.bundleIdentifier())
    }

    override func deactivateServer(_ sender: Any!) {
        closeHanja()
        commit(sender)
    }

    override func commitComposition(_ sender: Any!) {
        commit(sender)
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event = event else { return false }
        if event.type == .flagsChanged { return handleFlags(event, sender) }
        if event.type != .keyDown { return false }
        if KeySender.isOurs(event) { return false }   // 우리가 흉내 내 보낸 키는 그대로 통과

        if tapKey != nil { tapUsed = true }

        // 한자 후보 창이 열려 있으면 먼저: 고르기/넘기기, 그 외 키는 창 닫고 평소대로
        if hanja != nil {
            if handleHanjaKey(event, sender) { return true }
            closeHanja()
        }

        // Cmd/Ctrl/Option 조합 단축키: 조합 확정 후 앱으로
        let mods = event.modifierFlags.intersection([.command, .control, .option])
        if !mods.isEmpty {
            commit(sender)
            TypedText.clear()
            return false
        }

        // 영문 모드: 그대로 통과 (글자는 기록만)
        if !ModeState.hangul {
            commit(sender)
            noteEnglish(event)
            return false
        }

        if event.keyCode == Key.delete {
            if engine.backspace() {
                KeyLog.dropCurrent()
                updateMarked(sender)
                return true
            }
            TypedText.dropLast()
            return false
        }

        if event.keyCode == Key.space {
            insert(engine.flush() + " ", sender)
            KeyLog.endWord()
            return true
        }

        guard let ascii = asciiOf(event) else {
            // 엔터·탭·방향키 등: 조합만 확정하고 키는 앱이 처리
            commit(sender)
            TypedText.clear()
            return false
        }

        engine.dubeol = ModeState.layout.dubeol
        KeyLog.key(Character(UnicodeScalar(UInt32(ascii))!))
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

    // MARK: 단독 탭: 오른쪽 Command = 한/영, 오른쪽 Option = 한자

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
            else {
                tapKey = event.keyCode
                tapUsed = false
                longFired = false
                longWork?.cancel()
                if event.keyCode == Key.rightCommand {
                    // 길게 누르면 바로잡기 (누른 채 다른 키를 쓰면 취소)
                    let work = DispatchWorkItem { [weak self] in
                        guard let self = self, self.tapKey == Key.rightCommand, !self.tapUsed else { return }
                        self.longFired = true
                        self.convertMistype(sender)
                    }
                    longWork = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + longPressDelay, execute: work)
                }
            }
        } else if tapKey == event.keyCode {
            let used = tapUsed || longFired
            tapKey = nil
            longWork?.cancel()
            if !used { onTap(event.keyCode, sender) }
        }
        return false
    }

    private func onTap(_ keyCode: UInt16, _ sender: Any!) {
        switch keyCode {
        case Key.rightCommand: toggleMode(sender)
        case Key.rightOption:
            if hanja != nil { closeHanja() } else { startHanja(sender) }
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

    func textClient(_ sender: Any!) -> IMKTextInput? {
        if let c = sender as? IMKTextInput { return c }
        if let c = client() { return c }
        return nil
    }

    /// 영문 모드에서 앱으로 흘려보낸 키를 기록 (Backspace는 한 글자 지움, 그 밖의 특수키는 기록 끊음)
    private func noteEnglish(_ event: NSEvent) {
        if event.keyCode == Key.delete { TypedText.dropLast(); return }
        if let s = event.characters, !s.isEmpty, s.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7f && $0.value < 0xf700 }) {
            TypedText.append(s)
            if s == " " { KeyLog.endWord() }
            else if s.count == 1, let ch = s.first, ch.isASCII { KeyLog.key(ch) }
        } else {
            TypedText.clear()
        }
    }

    func insert(_ text: String, _ sender: Any!) {
        guard !text.isEmpty else { return }
        TypedText.append(text)
        textClient(sender)?.insertText(text, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
    }

    func updateMarked(_ sender: Any!) {
        let s = engine.composing()
        textClient(sender)?.setMarkedText(s,
            selectionRange: NSRange(location: (s as NSString).length, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
    }

    func commit(_ sender: Any!) {
        if engine.isEmpty { return }
        insert(engine.flush(), sender)
    }
}
