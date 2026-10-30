// 입력 소스가 바뀔 때마다 시각·소스·앞에 있는 앱을 찍는다: swift tools/watch.swift (Ctrl+C로 끝)
import Cocoa
import Carbon

func current() -> String {
    let s = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    guard let v = TISGetInputSourceProperty(s, kTISPropertyInputSourceID) else { return "?" }
    return Unmanaged<CFString>.fromOpaque(v).takeUnretainedValue() as String
}

let fmt = DateFormatter()
fmt.dateFormat = "HH:mm:ss.SSS"
func log(_ what: String) {
    let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
    print("\(fmt.string(from: Date()))  \(what.padding(toLength: 10, withPad: " ", startingAt: 0))  소스=\(current())  앞앱=\(app)")
    fflush(stdout)
}

log("시작")
DistributedNotificationCenter.default().addObserver(
    forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
    object: nil, queue: .main) { _ in log("소스변경") }
NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { _ in log("앱전환") }
RunLoop.main.run()
