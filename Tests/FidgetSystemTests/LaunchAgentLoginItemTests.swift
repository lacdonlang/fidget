import Foundation
import Testing
@testable import FidgetSystem

/// macOS 11–12 没有 SMAppService，登录启动改用用户级 LaunchAgent。
@Suite("登录启动项（LaunchAgent）")
struct LaunchAgentLoginItemTests {
    func makeItem() -> (LaunchAgentLoginItem, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fidget-agents-\(UUID().uuidString)")
        return (LaunchAgentLoginItem(bundleIdentifier: "com.example.fidget", directory: dir), dir)
    }

    @Test("开启写入启动项、关闭删除；重复操作安全")
    func enableAndDisable() throws {
        let (item, dir) = makeItem()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(!item.isEnabled)
        try item.setEnabled(false) // 未开启时关闭是空操作
        try item.setEnabled(true)
        try item.setEnabled(true)
        #expect(item.isEnabled)
        #expect(item.plistURL.lastPathComponent == "com.example.fidget.login.plist")
        try item.setEnabled(false)
        #expect(!item.isEnabled)
    }

    @Test("启动项内容：登录时按 bundle id 打开应用，不依赖安装路径")
    func propertyList() throws {
        let (item, dir) = makeItem()
        defer { try? FileManager.default.removeItem(at: dir) }
        try item.setEnabled(true)
        let plist = try #require(NSDictionary(contentsOf: item.plistURL) as? [String: Any])
        #expect(plist["Label"] as? String == "com.example.fidget.login")
        #expect(plist["ProgramArguments"] as? [String] == ["/usr/bin/open", "-b", "com.example.fidget"])
        #expect(plist["RunAtLoad"] as? Bool == true)
        #expect(plist["LimitLoadToSessionType"] as? String == "Aqua")

        let lint = Process()
        lint.executableURL = URL(fileURLWithPath: "/usr/bin/plutil")
        lint.arguments = ["-lint", "-s", item.plistURL.path]
        try lint.run()
        lint.waitUntilExit()
        #expect(lint.terminationStatus == 0)
    }
}
