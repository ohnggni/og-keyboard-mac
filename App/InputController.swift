import Cocoa
import InputMethodKit
import os

let keyLog = Logger(subsystem: "kr.ogapp.inputmethod.OGKeyboard", category: "key")

/// 한/영 상태와 자판. 한/영은 앱별로 기억 (켜져 있을 때)
enum ModeState {
    private static let defaults = UserDefaults.standard

    /// 잠깐 바꾸는 것(로그인 칸 자동 영문 등)은 앱별 기억에 남기지 않는다
    static var transient = false

    static var hangul = true {
        didSet {
            if !transient, rememberPerApp, let app = currentApp, appModes[app] != hangul {
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
        // 같은 앱 안에서 칸만 옮긴 경우(사파리는 칸마다 입력기를 다시 시작함)는 건드리지 않는다.
        // 그러지 않으면 영문 칸 자동 전환 같은 잠깐의 상태가 앱 기억으로 덮어써진다.
        guard app != currentApp else { return }
        currentApp = app
        guard rememberPerApp, let app = app, let saved = appModes[app], saved != hangul else { return }
        hangul = saved
        keyLog.info("앱 \(app, privacy: .public) → \(saved ? "한글" : "영문", privacy: .public)")
    }

    static func hasSaved(_ app: String?) -> Bool {
        guard let app = app else { return false }
        return appModes[app] != nil
    }

    /// 기억에 남기지 않고 한/영 바꾸기
    static func setTransient(hangul h: Bool) {
        transient = true
        hangul = h
        transient = false
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
    static let capsLock: UInt16 = 57
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
    /// 열려 있는 이모지 창 (InputController+Emoji.swift)
    var emojiSession: EmojiSession?
    /// B12: Chromium 터미널에서 기호 키가 바꾼 글자를 조합 중 글자로 잠깐 걸어둔 것 (다음 키·확정 때 넣음)
    var pendingLiteral = ""
    /// 확정 안 된 글자가 있는지 (조합 중 한글 또는 걸어둔 글자)
    var hasComposition: Bool { !engine.isEmpty || !pendingLiteral.isEmpty }
    /// 오른쪽 Option 두 번 누르기 판단용
    private var lastOptionTap: Date?
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

    /// 지금 입력을 받는 컨트롤러 (장치에서 들은 Caps Lock 한/영을 넘겨줄 곳)
    static weak var active: InputController?

    override func activateServer(_ sender: Any!) {
        InputController.active = self
        // 키 → 글자 변환을 US 배열로 고정 (자판 표가 US 기준)
        (sender as? IMKTextInput)?.overrideKeyboard(withKeyboardNamed: "com.apple.keylayout.US")
        engine.dubeol = ModeState.layout.dubeol
        tapKey = nil
        TypedText.clear()
        ModeState.activate(app: textClient(sender)?.bundleIdentifier())
    }

    override func deactivateServer(_ sender: Any!) {
        closeHanja()
        closeEmoji()
        commit(sender)
    }

    override func commitComposition(_ sender: Any!) {
        commit(sender)
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event = event else { return false }
        if event.type == .flagsChanged { return handleFlags(event, sender) }
        if event.type != .keyDown { return false }
        let ours = KeySender.isOurs(event)
        // DIAG(B15 임시): 키마다 번호·우리 키 판정·표식·한/영·기록 길이 (글자 내용은 남기지 않음). 진단 끝나면 제거
        keyLog.info("DIAG key=\(event.keyCode, privacy: .public) n=\(event.characters?.count ?? -1, privacy: .public) ours=\(ours, privacy: .public) mark=\(event.cgEvent?.getIntegerValueField(.eventSourceUserData) == KeySender.marker, privacy: .public) han=\(ModeState.hangul, privacy: .public) typed=\(TypedText.text.count, privacy: .public)")
        if ours { return false }   // 우리가 흉내 내 보낸 키는 그대로 통과

        // B12: 걸어둔 글자가 있으면 먼저 처리. Backspace는 그 글자만 지우고, 그 밖의 키는 넣은 뒤 평소대로
        if !pendingLiteral.isEmpty {
            if event.keyCode == Key.delete && event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
                pendingLiteral = ""
                updateMarked(sender)
                return true
            }
            commit(sender)
        }

        if tapKey != nil { tapUsed = true }

        // 이모지 창이 열려 있으면 먼저: 이동/넣기, 그 외 키는 창 닫고 평소대로
        if emojiSession != nil {
            if handleEmojiKey(event) { return true }
            closeEmoji()
        }

        // 한자 후보 창이 열려 있으면 먼저: 고르기/넘기기, 그 외 키는 창 닫고 평소대로
        if hanja != nil {
            if handleHanjaKey(event, sender) { return true }
            closeHanja()
        }

        // Ctrl+Option+V: 클립보드 기록 (안드판 Ctrl+Alt+V)
        if event.modifierFlags.intersection([.command, .control, .option, .shift]) == [.control, .option],
           event.keyCode == 9 {
            openClipboard(sender)
            return true
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
            let literal = String(UnicodeScalar(UInt32(v))!)
            if LiteralHold.needsHold(ascii: ascii, value: v), holdsLiterals(sender) {
                // B12: 바꾼 기호를 바로 넣으면 Chromium 터미널(xterm.js)이 원래 키 글자를 대신 찍는다 →
                // 조합 중 글자로 걸어둬 keydown이 '입력기 처리 중'으로 가게 하고, 다음 키·확정 때 넣는다
                let composed = engine.flush()
                if !composed.isEmpty { insert(composed, sender) }
                pendingLiteral = literal
                updateMarked(sender)
                keyLog.debug("B12 걸어둠 \(literal, privacy: .public)")
            } else {
                insert(engine.flush() + literal, sender)
            }
        }
        return true
    }

    /// B12: 바꾼 기호를 걸어둘 앱인지 — 터미널로 다루는 Chromium·Electron 앱 (Termix 등 xterm.js 기반)
    private func holdsLiterals(_ sender: Any!) -> Bool {
        guard let id = textClient(sender)?.bundleIdentifier() else { return false }
        return Terminals.contains(id) && ChromiumApps.contains(id)
    }

    // MARK: 단독 탭: 오른쪽 Command = 한/영, 오른쪽 Option = 한자

    private func handleFlags(_ event: NSEvent, _ sender: Any!) -> Bool {
        keyLog.debug("flags keyCode=\(event.keyCode, privacy: .public) raw=0x\(String(event.modifierFlags.rawValue, radix: 16), privacy: .public)")
        // 입력기로 오는 이벤트엔 좌우 구분 비트가 빠져 있음 → 키 코드로 오른쪽을 구분하고 수식 비트로 누름/뗌 판단
        let flag: NSEvent.ModifierFlags
        switch event.keyCode {
        case Key.rightCommand: flag = .command
        case Key.rightOption: flag = .option
        case Key.capsLock:
            return false   // Caps Lock은 CapsMonitor가 장치에서 직접 처리
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
            let now = Date()
            if let last = lastOptionTap, now.timeIntervalSince(last) < 0.4 {
                // 두 번: 이모지 전체 창
                lastOptionTap = nil
                closeHanja()
                openEmojiPanel(sender)
            } else {
                lastOptionTap = now
                if emojiSession != nil { closeEmoji() }
                else if hanja != nil { closeHanja() }
                else { startHanja(sender) }
            }
        default: break
        }
    }

    func toggleMode(_ sender: Any!) {
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
        keyLog.debug("key code=\(event.keyCode, privacy: .public) chars=\(event.characters?.count ?? 0)자")
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
        let s = engine.composing() + pendingLiteral
        textClient(sender)?.setMarkedText(s,
            selectionRange: NSRange(location: (s as NSString).length, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
    }

    func commit(_ sender: Any!) {
        guard hasComposition else { return }
        let text = engine.flush() + pendingLiteral
        pendingLiteral = ""
        insert(text, sender)
    }
}
