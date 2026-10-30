// 입력 소스 속성 비교용 진단: swift tools/tis.swift
import Carbon

let list = TISCreateInputSourceList(nil, false).takeRetainedValue() as! [TISInputSource]
for s in list {
    func p(_ k: CFString) -> Any? {
        guard let v = TISGetInputSourceProperty(s, k) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(v).takeUnretainedValue()
    }
    let id = p(kTISPropertyInputSourceID) as? String ?? ""
    guard id.contains("OGKeyboard") || id.lowercased().contains("korean") || id.hasSuffix(".ABC") else { continue }
    print(id)
    print("   종류:", p(kTISPropertyInputSourceType) ?? "-",
          "| 영문가능:", p(kTISPropertyInputSourceIsASCIICapable) ?? "-",
          "| 선택가능:", p(kTISPropertyInputSourceIsSelectCapable) ?? "-")
    print("   언어:", (p(kTISPropertyInputSourceLanguages) as? [String])?.joined(separator: ",") ?? "-")
}
