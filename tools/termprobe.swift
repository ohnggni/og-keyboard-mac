// 터미널 화면의 마지막 줄을 손쉬운 사용으로 읽을 수 있는지 확인 (암호 프롬프트 자동 영문 가능성 확인용)
// 실행: swift tools/termprobe.swift  (Ctrl+C로 끝). 실행한 터미널 앱에 손쉬운 사용 권한 필요.
// 앞에 있는 앱의 커서 칸에서 글자를 읽어 마지막 줄(최대 80자)이 바뀔 때마다 출력한다.
import Cocoa
import ApplicationServices

guard AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary) else {
    print("이 터미널 앱에 손쉬운 사용 권한이 필요합니다 (시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용). 켠 뒤 다시 실행하십시오.")
    exit(1)
}

func str(_ e: AXUIElement, _ name: String) -> String? {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success else { return nil }
    return v as? String
}

var last = ""
var enabled = Set<pid_t>()
print("다른 터미널 앱을 앞으로 가져가 sudo 등으로 암호 프롬프트를 띄워 보십시오.")
Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
    guard let app = NSWorkspace.shared.frontmostApplication,
          app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
    let ax = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetMessagingTimeout(ax, 0.3)
    if !enabled.contains(app.processIdentifier) {
        AXUIElementSetAttributeValue(ax, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        enabled.insert(app.processIdentifier)
    }
    var f: CFTypeRef?
    let name = app.bundleIdentifier ?? "?"
    guard AXUIElementCopyAttributeValue(ax, kAXFocusedUIElementAttribute as CFString, &f) == .success, let focused = f else {
        let line = "[\(name)] 커서 칸 없음"
        if line != last { print(line); last = line }
        return
    }
    let e = focused as! AXUIElement
    let role = str(e, "AXRole") ?? "?"
    let value = str(e, "AXValue") ?? ""
    let lines = value.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    let tail = lines.last.map { String($0.suffix(80)) } ?? "(글자 없음)"
    let line = "[\(name)] \(role) 전체 \(value.count)자 · 마지막 줄: \(tail)"
    if line != last { print(line); last = line }
}
RunLoop.main.run()
