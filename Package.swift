// swift-tools-version:5.9
// 조합기(HangulCore)와 그 테스트만 패키지로 관리한다. 입력기 앱 본체는 dev.sh가 swiftc로 직접 묶는다.
import PackageDescription

let package = Package(
    name: "OGKeyboard",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "HangulCore", path: "Sources/HangulCore"),
        .testTarget(name: "HangulCoreTests", dependencies: ["HangulCore"], path: "Tests/HangulCoreTests"),
    ]
)
