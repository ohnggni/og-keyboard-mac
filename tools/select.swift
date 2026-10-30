// 4초 뒤(그사이 대상 앱을 앞으로) OG키보드를 직접 고르고, 실제로 바뀌었는지 확인: swift tools/select.swift
import Cocoa
import Carbon

func current() -> String {
    let s = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    guard let v = TISGetInputSourceProperty(s, kTISPropertyInputSourceID) else { return "?" }
    return Unmanaged<CFString>.fromOpaque(v).takeUnretainedValue() as String
}

print("4초 안에 사파리 주소창을 클릭해 두세요…"); fflush(stdout)
Thread.sleep(forTimeInterval: 4)
let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
let filter = [kTISPropertyInputSourceID as String: "kr.ogapp.inputmethod.OGKeyboard"] as CFDictionary
guard let src = (TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource])?.first else {
    print("OG키보드 입력 소스를 못 찾음"); exit(1)
}
print("앞 앱: \(app), 고르기 전: \(current())")
let err = TISSelectInputSource(src)
print("TISSelectInputSource 결과: \(err == noErr ? "성공" : "오류 \(err)")")
for t in [0.2, 1.0, 2.0] {
    Thread.sleep(forTimeInterval: t == 0.2 ? 0.2 : 0.8)
    print("  \(t)초 뒤: \(current())")
}
