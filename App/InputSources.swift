import Cocoa
import Carbon

/// 입력 소스(TIS) 도우미 + 순정 피난: 지정한 앱이 앞에 오면 순정 입력기로, 벗어나면 OG키보드로
enum InputSources {
    static let ogID = Bundle.main.bundleIdentifier ?? "kr.ogapp.inputmethod.OGKeyboard"

    static var currentID: String {
        let s = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let v = TISGetInputSourceProperty(s, kTISPropertyInputSourceID) else { return "" }
        return Unmanaged<CFString>.fromOpaque(v).takeUnretainedValue() as String
    }

    static var ogIsCurrent: Bool { currentID.hasPrefix(ogID) }

    @discardableResult
    static func select(_ id: String) -> Bool {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        guard let src = (TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource])?.first else { return false }
        return TISSelectInputSource(src) == noErr
    }

    /// 켜져 있는 입력 소스 중 피난처: 순정 세벌식 390 → 다른 순정 한국어 → ABC
    static var nativeID: String {
        let list = (TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource]) ?? []
        let ids: [String] = list.compactMap { s in
            guard let v = TISGetInputSourceProperty(s, kTISPropertyInputSourceID),
                  let sel = TISGetInputSourceProperty(s, kTISPropertyInputSourceIsSelectCapable),
                  CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(sel).takeUnretainedValue()) else { return nil }
            return Unmanaged<CFString>.fromOpaque(v).takeUnretainedValue() as String
        }
        if ids.contains("com.apple.inputmethod.Korean.390Sebulshik") { return "com.apple.inputmethod.Korean.390Sebulshik" }
        if let k = ids.first(where: { $0.hasPrefix("com.apple.inputmethod.Korean.") }) { return k }
        return "com.apple.keylayout.ABC"
    }
}

/// 순정 피난: OG키보드와 맞지 않는 앱은 그 앱에 있을 때만 순정 입력기를 쓴다
enum Fallback {
    private static let key = "fallbackApps"
    /// 우리가 순정으로 바꿔 둔 상태인지 (그래야 벗어날 때 OG키보드로 되돌림)
    private static var switchedAway = false

    static var apps: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: key) ?? []) }
        set { UserDefaults.standard.set(Array(newValue).sorted(), forKey: key) }
    }

    static func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { n in
            let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            apply(app?.bundleIdentifier)
        }
    }

    static func apply(_ app: String?) {
        guard let app = app else { return }
        if apps.contains(app) {
            if InputSources.ogIsCurrent {
                let to = InputSources.nativeID
                switchedAway = InputSources.select(to)
                keyLog.info("순정 피난: \(app, privacy: .public) → \(to, privacy: .public)")
            }
        } else if switchedAway {
            switchedAway = false
            InputSources.select(InputSources.ogID)
            keyLog.info("순정 피난 끝: \(app, privacy: .public) → OG키보드")
        }
    }

    static func toggle(_ app: String) {
        var a = apps
        if a.contains(app) {
            a.remove(app)
            apps = a
            if switchedAway { switchedAway = false; InputSources.select(InputSources.ogID) }
        } else {
            a.insert(app)
            apps = a
            apply(app)
        }
    }
}
