import Foundation

/// 텍스트 단축어 저장 (UserDefaults, JSON)
enum ShortcutStore {
    private static let key = "shortcuts"

    static var all: [Shortcut] {
        get {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let list = try? JSONDecoder().decode([Shortcut].self, from: data) else { return TextShortcuts.defaults }
            return list
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) { UserDefaults.standard.set(data, forKey: key) }
        }
    }
}
