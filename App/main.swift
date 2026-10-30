import Cocoa
import Carbon
import InputMethodKit

let bundleID = Bundle.main.bundleIdentifier ?? "kr.ogapp.inputmethod.OGKeyboard"
let connectionName = Bundle.main.infoDictionary?["InputMethodConnectionName"] as? String
    ?? "kr.ogapp.inputmethod.OGKeyboard_Connection"

/// dev.sh가 설치 직후 `--install`로 부름: 입력 소스를 시스템에 등록하고 켠다.
func registerAndEnable() {
    let url = Bundle.main.bundleURL as CFURL
    let err = TISRegisterInputSource(url)
    print("등록: \(err == noErr ? "성공" : "오류 \(err)")")

    let filter = [kTISPropertyBundleID as String: bundleID] as CFDictionary
    guard let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource],
          !list.isEmpty else {
        print("입력 소스를 못 찾음 — 로그아웃 후 다시 실행하거나 시스템 설정에서 직접 추가")
        return
    }
    for src in list {
        let e = TISEnableInputSource(src)
        print("켜기: \(e == noErr ? "성공" : "오류 \(e)")")
    }
}

if CommandLine.arguments.contains("--install") {
    registerAndEnable()
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let server = IMKServer(name: connectionName, bundleIdentifier: bundleID)
StatusBar.shared.setup()
// 클릭하면 커서가 옮겨졌을 수 있으니 글자 기록을 끊는다 (마우스 전역 감시는 권한 불필요)
NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { _ in
    TypedText.clear()
}
NSLog("OGKeyboard 시작 (\(bundleID))")
app.run()
