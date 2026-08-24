// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "trackpad_pro",
    platforms: [.macOS(.v13)],
    targets: [
        // 私有框架 MultitouchSupport 的 C 声明（结构体布局 + 函数原型）
        .target(
            name: "CMultitouch",
            path: "Sources/CMultitouch",
            linkerSettings: [
                .unsafeFlags(["-F", "/System/Library/PrivateFrameworks", "-framework", "MultitouchSupport"])
            ]
        ),
        .executableTarget(
            name: "trackpad_pro",
            dependencies: ["CMultitouch"],
            path: "Sources/trackpad_pro",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
            ]
        ),
    ]
)
