// swift-tools-version: 5.9
// MemeDesk — macOS 桌面表情包播放器
//
// 两种使用方式：
//   1) ./Scripts/build.sh            —— 仅用 Xcode Command Line Tools 打出可直接运行的 .app
//   2) xed Package.swift             —— 用 Xcode 打开 SwiftPM 包（推荐调试）
import PackageDescription

let package = Package(
    name: "MemeDesk",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MemeDesk", targets: ["MemeDesk"]),
    ],
    targets: [
        // MemeDesk 与 MemeDeskShared 编进同一个 module，与 Xcode 工程（Xcode/project.yml）
        // 的处理保持一致，因此两边都不需要 import MemeDeskShared。
        .executableTarget(
            name: "MemeDesk",
            path: "Sources",
            sources: ["MemeDesk", "MemeDeskShared"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("UniformTypeIdentifiers"),
                .linkedFramework("ImageIO"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
    ]
)
