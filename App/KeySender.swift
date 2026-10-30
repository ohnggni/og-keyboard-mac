import Cocoa
import ApplicationServices

/// 입력기가 넣었거나 앱으로 그냥 흘려보낸 글자 기록 (커서를 옮기거나 클릭하면 끊김).
/// 앱에서 커서 앞 글자를 못 읽을 때(터미널 등) 이 기록을 '커서 앞 글자'로 쓴다.
enum TypedText {
    private(set) static var text = ""
    private static let maxLength = 64

    static func append(_ s: String) {
        text += s
        if text.count > maxLength { text = String(text.suffix(maxLength)) }
    }

    static func dropLast() {
        if !text.isEmpty { text.removeLast() }
        KeyLog.dropCurrent()
    }

    static func clear() {
        text = ""
        KeyLog.endWord()   // 키 기록은 남긴다: 바로잡기가 "다시 쳐서 같은 글자일 때만" 쓰므로 안전
    }

    /// 클릭: 커서 위치를 모르게 되니 글자 기록만 끊고, 키 기록은 둔다(바로잡기가 내용으로 맞춰 봄)
    static func clearTextOnly() {
        text = ""
    }

    /// 바로잡기로 끝부분을 바꿨을 때 기록도 맞춘다
    static func replaceSuffix(count: Int, with s: String) {
        text = String(text.dropLast(count)) + s
    }
}

/// 실제로 누른 키 기록 (바로잡기용). 모아치기로 친 글자는 글자만 보고는 키 순서를 되살릴 수 없어서 필요.
enum KeyLog {
    /// 지금 치는 낱말의 키
    private(set) static var current = ""
    /// 끝난 낱말들 (오래된 것부터)
    private static var words: [String] = []

    static func key(_ c: Character) {
        if current.count < 64 { current.append(c) }
    }

    /// 스페이스: 지금 낱말을 끝난 목록으로
    static func endWord() {
        if !current.isEmpty {
            words.append(current)
            if words.count > 50 { words.removeFirst() }
        }
        current = ""
    }

    /// 조합 중 Backspace: 지금 낱말만 못 믿게 됨
    static func dropCurrent() {
        current = ""
    }

    static func clear() {
        current = ""
        words = []
    }

    /// [지금 낱말, 바로 앞 낱말, …]
    static var newestFirst: [String] {
        (current.isEmpty ? [] : [current]) + words.reversed()
    }
}

/// 앱이 '그 자리 바꾸기'를 지원하지 않을 때: Backspace와 글자를 키 입력처럼 흉내 내서 보낸다.
/// 손쉬운 사용 권한 필요.
enum KeySender {
    /// 우리가 보낸 이벤트 표시 (입력기로 되돌아와도 건드리지 않게)
    static let marker: Int64 = 0x4F47_4B42 // "OGKB"

    static var trusted: Bool { AXIsProcessTrusted() }

    /// 권한이 없으면 시스템 설정 안내 창을 띄운다 (한 번만)
    private static var asked = false
    static func requestTrust() {
        guard !asked else { return }
        asked = true
        let opt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opt)
    }

    static func backspaces(_ n: Int) {
        let src = CGEventSource(stateID: .combinedSessionState)
        for _ in 0..<n {
            for down in [true, false] {
                let e = CGEvent(keyboardEventSource: src, virtualKey: 51, keyDown: down)
                e?.flags = []   // 오른쪽 Command를 누른 채 불릴 수 있음 → Cmd+Backspace(줄 지우기)가 되지 않게
                post(e)
            }
        }
    }

    /// 커서를 왼쪽으로 n칸 (단축어 {커서})
    static func arrowLeft(_ n: Int) {
        guard trusted else { return }
        let src = CGEventSource(stateID: .combinedSessionState)
        for _ in 0..<n {
            for down in [true, false] {
                let e = CGEvent(keyboardEventSource: src, virtualKey: 123, keyDown: down)
                e?.flags = []
                post(e)
            }
        }
    }

    static func type(_ s: String) {
        let src = CGEventSource(stateID: .combinedSessionState)
        // 한 이벤트에 UTF-16 16개까지: 글자(이모지 포함)가 잘리지 않게 묶는다
        var chunk: [UniChar] = []
        func flush() {
            guard !chunk.isEmpty else { return }
            for down in [true, false] {
                let e = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: down)
                e?.flags = []
                e?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                post(e)
            }
            chunk = []
        }
        for ch in s {
            let u = Array(String(ch).utf16)
            if chunk.count + u.count > 16 { flush() }
            chunk += u
        }
        flush()
    }

    private static func post(_ e: CGEvent?) {
        guard let e = e else { return }
        if e.type == .keyDown {
            pending += 1
            busyUntil = Date().addingTimeInterval(1)
        }
        e.setIntegerValueField(.eventSourceUserData, value: marker)
        e.post(tap: .cgSessionEventTap)
    }

    /// 우리가 보낸 키가 아직 도착 중인 동안 (일부 앱은 표시값을 지워서 넘겨줌 → 시간과 키 종류로도 판단)
    private static var busyUntil = Date.distantPast
    private static var pending = 0

    static func isOurs(_ event: NSEvent) -> Bool {
        if event.cgEvent?.getIntegerValueField(.eventSourceUserData) == marker {
            pending = max(0, pending - 1)
            return true
        }
        guard pending > 0, Date() < busyUntil else { pending = 0; return false }
        // Backspace(51) 또는 글자를 실어 보낸 키(0번 키에 ASCII가 아닌 글자)
        let chars = event.characters ?? ""
        let looksOurs = event.keyCode == 51 || event.keyCode == 123
            || (event.keyCode == 0 && !chars.isEmpty && !chars.unicodeScalars.allSatisfy(\.isASCII))
        if looksOurs { pending -= 1 }
        return looksOurs
    }
}

/// 커서 앞 글자를 앱에서 읽어도 믿을 수 없는 앱 (터미널류)
enum Terminals {
    static let bundleIDs: Set<String> = [
        "com.googlecode.iterm2", "com.apple.Terminal", "net.kovidgoyal.kitty", "org.alacritty",
        "com.github.wez.wezterm", "com.mitchellh.ghostty", "dev.warp.Warp-Stable", "co.zeit.hyper",
        "com.karmaa.termix",
    ]

    /// 메뉴에서 직접 지정한 앱 (목록에 없는 터미널용)
    static var userIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "terminalApps") ?? []) }
        set { UserDefaults.standard.set(Array(newValue).sorted(), forKey: "terminalApps") }
    }

    static func contains(_ id: String) -> Bool {
        bundleIDs.contains(id) || userIDs.contains(id)
    }
}
