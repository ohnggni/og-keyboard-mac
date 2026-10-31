// 커서가 있는 입력칸의 손쉬운 사용 정보를 출력 (이메일·비밀번호 칸 자동 영문 전환 가능성 확인용)
// 실행: swift tools/axprobe.swift  (Ctrl+C로 끝). 실행한 터미널 앱에 손쉬운 사용 권한 필요.
// 입력한 내용(값)은 출력하지 않는다.
import Cocoa
import ApplicationServices

guard AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary) else {
    print("이 터미널 앱에 손쉬운 사용 권한이 필요합니다 (시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용). 켠 뒤 다시 실행하십시오.")
    exit(1)
}

func attr(_ e: AXUIElement, _ name: String) -> String? {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success, let v = v else { return nil }
    if let s = v as? String { return s.isEmpty ? nil : s }
    if let a = v as? [String] { return a.isEmpty ? nil : a.joined(separator: ",") }
    if let n = v as? NSNumber { return n.stringValue }
    return nil
}

var last = ""
var enabled = Set<pid_t>()
Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
    guard let app = NSWorkspace.shared.frontmostApplication else { return }
    let ax = AXUIElementCreateApplication(app.processIdentifier)
    // 크롬·Electron은 이 값을 켜야 웹 내용의 정보를 넘겨줌
    if !enabled.contains(app.processIdentifier) {
        AXUIElementSetAttributeValue(ax, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        enabled.insert(app.processIdentifier)
    }
    var f: CFTypeRef?
    guard AXUIElementCopyAttributeValue(ax, kAXFocusedUIElementAttribute as CFString, &f) == .success,
          let focused = f else { return }
    let e = focused as! AXUIElement
    let keys = ["AXRole", "AXSubrole", "AXRoleDescription", "AXPlaceholderValue", "AXTitle", "AXDescription",
                "AXHelp", "AXIdentifier", "AXDOMIdentifier", "AXDOMClassList", "AXAutocompleteValue"]
    var parts: [String] = []
    for k in keys { if let v = attr(e, k) { parts.append("\(k.dropFirst(2))=\(v)") } }
    // 이름표가 바로 위 요소에 있는 경우
    var t: CFTypeRef?
    if AXUIElementCopyAttributeValue(e, "AXTitleUIElement" as CFString, &t) == .success, let te = t {
        if let v = attr(te as! AXUIElement, "AXValue") ?? attr(te as! AXUIElement, "AXTitle") { parts.append("Label=\(v)") }
    }
    parts.append("SecureInput=\(IsSecureEventInputEnabled() ? "켜짐" : "꺼짐")")
    let line = "[\(app.bundleIdentifier ?? "?")] " + parts.joined(separator: " | ")
    if line != last { print(line); fflush(stdout); last = line }
}
print("감시 중… 사파리·크롬 로그인 화면의 이메일·아이디·비밀번호 칸을 차례로 클릭해 보십시오.")
RunLoop.main.run()
