import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import Testing
@testable import FidgetCore
@testable import FidgetSystem

/// 这些测试直接触碰 macOS API，在本机与 CI 的 GUI 会话中运行；需要辅助功能权限的用例在未授权时跳过。
@Suite("系统适配层", .serialized)
struct SystemIntegrationTests {
    @Test("空闲时间返回有限非负值")
    func idleProvider() {
        let idle = CGIdleTimeProvider().secondsSinceLastInput()
        #expect(idle.isFinite && idle >= 0)
    }

    @Test("指针位置落在某个显示器内，且能取到包含它的显示器边界")
    @MainActor
    func pointerPositionAndBounds() {
        let controller = CGPointerController()
        let p = controller.currentPosition()
        let bounds = controller.displayBounds(containing: p)
        #expect(!bounds.isEmpty)
        #expect(p.x.isFinite && p.y.isFinite)
    }

    @Test("有辅助功能权限时，移动 1 像素再移回会真正改变指针位置", .enabled(if: AXIsProcessTrusted(), "需要辅助功能权限"))
    @MainActor
    func pointerMoves() async throws {
        let controller = CGPointerController()
        let mover = PointerMover(controller: controller)
        var rng = SeededRandomNumberGenerator(seed: 1)
        let path = mover.makePath(settings: MovementSettings(invisibleMode: true), sequence: 0, rng: &rng)
        let result = await mover.perform(path: path)
        #expect(result.pointerMoved)
        #expect(result.endedAt >= result.startedAt)
    }

    @Test("电源断言可以创建并释放")
    @MainActor
    func powerAssertions() {
        let controller = IOPowerAssertionController()
        controller.apply(PowerAssertionState(preventDisplaySleep: true, preventSystemSleep: true))
        #expect(controller.current != .none)
        controller.apply(.none)
        #expect(controller.current == .none)
        controller.apply(.none) // 幂等
    }

    @Test("电源来源与显示器断言探测不会崩溃")
    func probes() {
        _ = PowerSourceProbe().isOnBattery()
        let holders = DisplaySleepAssertionProbe().holders(excludingPID: ProcessInfo.processInfo.processIdentifier)
        for h in holders { #expect(h.pid > 0) }
    }

    @Test("锁屏状态查询与环境快照")
    @MainActor
    func environmentSnapshot() {
        let provider = SystemEnvironmentProvider()
        let snapshot = provider.snapshot(needsRunningApps: true, needsDisplaySleepProbe: true)
        #expect(!snapshot.runningBundleIdentifiers.isEmpty)
        #expect(!provider.screenState.isConsideredLocked)
    }

    @Test("运行中应用列表与 .app 读取")
    @MainActor
    func runningApps() {
        let finder = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
        let app = RunningApps.app(at: finder)
        #expect(app?.bundleIdentifier == "com.apple.finder")
        #expect(RunningApps.app(at: URL(fileURLWithPath: "/nonexistent.app")) == nil)
        #expect(RunningApps.icon(forBundleIdentifier: "com.apple.finder") != nil)
    }

    @Test("设置与统计文件存储：往返、缺失、损坏")
    func fileStores() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fidget-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = JSONFileStore.settings(at: dir.appendingPathComponent("settings.json"))
        #expect(try store.load() == Settings.default)
        var s = Settings.default
        s.idleThresholdSeconds = 1 // 保存时会被校验收敛
        s.movement.pattern = .figureEight
        try store.save(s)
        let loaded = try store.load()
        #expect(loaded.movement.pattern == .figureEight)
        #expect(loaded.idleThresholdSeconds == SettingsLimits.idleThresholdSeconds.lowerBound)

        try Data("{not json".utf8).write(to: store.url)
        #expect(try store.load() == Settings.default)
        let backups = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.contains("corrupt") }
        #expect(backups.count == 1)

        let stats = JSONFileStore.statistics(at: dir.appendingPathComponent("statistics.json"))
        var st = try stats.load()
        st.recordJiggle(at: Date(), calendar: .current)
        try stats.save(st)
        #expect(try stats.load().totalJiggles == 1)
    }

    @Test("文件日志写入并可关闭")
    func fileLogging() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fidget-logs-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        Log.shared.enableFileLogging(directory: dir)
        Log.shared.info("hello from tests", category: .engine)
        let url = try #require(Log.shared.fileURL)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("hello from tests"))
        #expect(text.contains("[engine]"))
        Log.shared.disableFileLogging()
        #expect(Log.shared.fileURL == nil)
    }

    @Test("全局快捷键：Carbon 修饰键映射与注册/注销")
    @MainActor
    func hotKeys() {
        #expect(HotKeyCenter.carbonModifiers([.command]) == 256)
        #expect(HotKeyCenter.carbonModifiers([.shift]) == 512)
        #expect(HotKeyCenter.carbonModifiers([.option]) == 2048)
        #expect(HotKeyCenter.carbonModifiers([.control]) == 4096)
        let center = HotKeyCenter()
        center.register(HotKey(keyCode: 122, modifiers: [.command, .option, .control])) // ⌃⌥⌘F1，极不可能冲突
        #expect(center.isRegistered)
        center.unregister()
        #expect(!center.isRegistered)
        center.register(HotKey(keyCode: 0, modifiers: [])) // 非法，不应注册
        #expect(!center.isRegistered)
    }

    @Test("登录项管理在非 .app 环境下安全降级")
    @MainActor
    func loginItems() throws {
        let manager = LoginItemManager()
        if !manager.isAvailable {
            #expect(manager.status == .unavailable)
            try manager.setEnabled(true) // 应为空操作
        }
    }

    @Test("辅助功能权限查询不会崩溃")
    @MainActor
    func accessibility() {
        _ = AccessibilityPermission().isTrusted()
    }
}
