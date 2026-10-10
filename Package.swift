// swift-tools-version: 6.0
import PackageDescription

// Fidget —— 仅面向 Apple Silicon 的 macOS 闲时鼠标移动工具。
//
// 分层：
//   FidgetCore   纯 Swift 逻辑（设置模型、状态机、移动轨迹、计划表、统计），无 AppKit 依赖，可完全单元测试。
//   FidgetSystem macOS 系统适配层（CoreGraphics / IOKit / AppKit / ServiceManagement / Carbon）。
//   FidgetApp    SwiftUI 界面、菜单栏控制器、组合根；以库的形式存在便于测试。
//   Fidget       可执行壳，仅调用 FidgetApp.run()。
let package = Package(
    name: "Fidget",
    defaultLocalization: "en",
    platforms: [.macOS(.v11)],
    products: [
        .executable(name: "Fidget", targets: ["Fidget"]),
        .library(name: "FidgetCore", targets: ["FidgetCore"]),
        .library(name: "FidgetSystem", targets: ["FidgetSystem"]),
        // Xcode 工程（project.yml）通过该库产品链接全部应用代码。
        .library(name: "FidgetApp", targets: ["FidgetApp"]),
    ],
    targets: [
        .target(name: "FidgetCore"),
        .target(name: "FidgetSystem", dependencies: ["FidgetCore"]),
        .target(
            name: "FidgetApp",
            dependencies: ["FidgetCore", "FidgetSystem"],
            resources: [.process("Resources")]
        ),
        .executableTarget(name: "Fidget", dependencies: ["FidgetApp"]),
        .testTarget(name: "FidgetCoreTests", dependencies: ["FidgetCore"]),
        .testTarget(name: "FidgetSystemTests", dependencies: ["FidgetSystem"]),
        .testTarget(name: "FidgetAppTests", dependencies: ["FidgetApp"]),
    ],
    swiftLanguageModes: [.v6]
)
