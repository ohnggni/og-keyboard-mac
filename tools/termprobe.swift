// 터미널 화면의 마지막 줄을 손쉬운 사용으로 읽을 수 있는지 확인 (암호 프롬프트 자동 영문 가능성 확인용)
// 실행: swift tools/termprobe.swift [--tree]  (Ctrl+C로 끝). 실행한 터미널 앱에 손쉬운 사용 권한 필요.
// --tree: 커서 칸 대신 창 전체 요소를 훑어 글자가 있는 마지막 요소를 찾는다 (Termix 등 웹 기반 터미널용)
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

/// 창 아래 요소를 훑어 글자가 있는 요소들의 (역할, 글자)를 모은다 (최대 4000개)
func collect(_ e: AXUIElement, _ out: inout [(String, String)], _ budget: inout Int, depth: Int = 0) {
    guard budget > 0, depth < 40 else { return }
    budget -= 1
    let role = str(e, "AXRole") ?? "?"
    for k in ["AXValue", "AXTitle", "AXDescription"] {
        if let t = str(e, k)?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { out.append((role, t)); break }
    }
    var c: CFTypeRef?
    guard AXUIElementCopyAttributeValue(e, kAXChildrenAttribute as CFString, &c) == .success, let kids = c as? [AXUIElement] else { return }
    for k in kids { collect(k, &out, &budget, depth: depth + 1) }
}

let treeMode = CommandLine.arguments.contains("--tree")
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
    let name = app.bundleIdentifier ?? "?"
    if treeMode {
        var w: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ax, kAXFocusedWindowAttribute as CFString, &w) == .success, let win = w else { return }
        var out: [(String, String)] = []
        var budget = 4000
        collect(win as! AXUIElement, &out, &budget)
        let tail = out.suffix(3).map { "\($0.0)「\(String($0.1.split(whereSeparator: \.isNewline).last ?? "").suffix(60))」" }.joined(separator: " / ")
        let line = "[\(name)] 글자 있는 요소 \(out.count)개 · 마지막 3개: \(tail)"
        if line != last { print(line); last = line }
        return
    }
    var f: CFTypeRef?
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
