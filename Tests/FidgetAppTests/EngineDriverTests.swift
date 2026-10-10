import Combine
import Foundation
import Testing
@testable import FidgetApp
@testable import FidgetCore

@Suite("引擎驱动")
@MainActor
struct EngineDriverTests {
    func makeSettings() -> FidgetCore.Settings {
        var s = FidgetCore.Settings.default
        s.idleThresholdSeconds = 10
        s.jiggleIntervalSeconds = 5
        s.general.hasCompletedOnboarding = true
        return s
    }

    @Test("完整回路：闲置后移动、合成事件被忽略、按间隔重复、用户回来即停")
    func fullLoop() async {
        let h = DriverHarness(settings: makeSettings())
        await h.step(advance: 0, systemIdle: 0)
        #expect(h.model.live.status.kind == .watching)
        #expect(h.model.isAccessibilityTrusted)

        await h.step(advance: 10, systemIdle: 10)
        #expect(h.model.live.status.kind == .active)
        #expect(!h.pointer.moves.isEmpty)
        #expect(h.model.live.statistics.totalJiggles == 1)
        #expect(h.model.lastJiggle?.pointerMoved == true)
        #expect(h.pointer.position == h.model.lastJiggle?.path.origin)

        // 系统闲置计时被我们自己的事件归零，但引擎应继续视为闲置。
        await h.step(advance: 1, systemIdle: 1)
        #expect(h.model.live.status.kind == .active)
        #expect(h.model.live.statistics.totalJiggles == 1)

        await h.step(advance: 4, systemIdle: 5)
        #expect(h.model.live.statistics.totalJiggles == 2)

        // 用户回来了
        await h.step(advance: 2, systemIdle: 0)
        #expect(h.model.live.status.kind == .watching)
        #expect(h.model.live.diagnostics.realIdleSeconds == 0)
    }

    @Test("缺少权限时阻塞，授权后立即工作")
    func permission() async {
        let h = DriverHarness(settings: makeSettings(), trusted: false)
        await h.step(advance: 0, systemIdle: 100)
        #expect(h.model.live.status == .blocked(.accessibilityPermission))
        #expect(h.pointer.moves.isEmpty)
        h.accessibility.trusted = true
        await h.step(advance: 1, systemIdle: 101)
        #expect(h.model.live.status.kind == .active)
        #expect(!h.pointer.moves.isEmpty)
    }

    @Test("指针不动时累计失败并给出警告")
    func failures() async {
        let h = DriverHarness(settings: makeSettings())
        h.pointer.honorsMoves = false
        await h.step(advance: 0, systemIdle: 100)
        await h.step(advance: 5, systemIdle: 105)
        await h.step(advance: 1, systemIdle: 106)
        #expect(h.model.warnings == [.pointerDidNotMove(failures: 2)])
        #expect(h.model.live.statistics.totalJiggles == 0)
    }

    @Test("暂停、恢复、切换与总开关")
    func pauseResumeToggle() async {
        let h = DriverHarness(settings: makeSettings())
        await h.step(advance: 0, systemIdle: 0)
        h.driver.pause(.minutes15)
        #expect(h.model.live.status.kind == .paused)
        #expect(h.model.manualPause?.until == h.clock.now.addingTimeInterval(900))
        h.driver.toggle() // 暂停中切换 = 恢复
        #expect(h.model.manualPause == nil)
        #expect(h.model.live.status.kind == .watching)
        h.driver.toggle() // 否则 = 停用
        #expect(h.model.live.status == .off)
        h.driver.setEnabled(true)
        #expect(h.model.live.status.kind == .watching)
        h.driver.pause(minutes: nil)
        #expect(h.model.live.status == .paused(.manual(until: nil)))
        h.driver.resume()
        #expect(h.model.live.status.kind == .watching)
    }

    @Test("定时暂停到期自动恢复")
    func pauseExpiry() async {
        let h = DriverHarness(settings: makeSettings())
        await h.step(advance: 0, systemIdle: 0)
        h.driver.pause(minutes: 1)
        await h.step(advance: 30, systemIdle: 30)
        #expect(h.model.live.status.kind == .paused)
        await h.step(advance: 31, systemIdle: 61)
        #expect(h.model.manualPause == nil)
        #expect(h.model.live.status.kind == .active)
    }

    @Test("电源断言跟随状态")
    func powerAssertions() async {
        var s = makeSettings()
        s.keepAwake.preventDisplaySleep = true
        let h = DriverHarness(settings: s)
        await h.step(advance: 0, systemIdle: 0)
        #expect(h.power.current.preventDisplaySleep)
        h.driver.pause(.indefinite)
        #expect(!h.power.current.preventDisplaySleep)
        h.driver.resume()
        #expect(h.power.current.preventDisplaySleep)
        h.driver.stop()
        #expect(h.power.current == .none)
    }

    @Test("规则关闭时不采集昂贵的环境信息")
    func lazyEnvironment() async {
        let h = DriverHarness(settings: makeSettings())
        await h.step(advance: 0, systemIdle: 0)
        #expect(h.environment.requests.last?.apps == false)
        #expect(h.environment.requests.last?.probe == false)
        h.model.settings.rules.appRules = [AppRule(bundleIdentifier: "a", displayName: "A")]
        h.model.settings.rules.pauseWhenOtherAppPreventsDisplaySleep = true
        await h.step(advance: 1, systemIdle: 1)
        #expect(h.environment.requests.last?.apps == true)
        #expect(h.environment.requests.last?.probe == true)
    }

    @Test("立即移动在任何状态下都会执行并计入统计")
    func moveNow() async {
        let h = DriverHarness(settings: makeSettings())
        await h.step(advance: 0, systemIdle: 0)
        h.driver.moveNow()
        await h.settle()
        #expect(!h.pointer.moves.isEmpty)
        #expect(h.model.live.statistics.totalJiggles == 1)
        // 手动移动产生的合成事件不应被当作用户输入
        await h.step(advance: 0.5, systemIdle: 0.3)
        #expect(h.model.live.diagnostics.realIdleSeconds > 0.4)
    }

    @Test("统计累计工作时长并按日滚动")
    func statisticsRunningTime() async {
        let h = DriverHarness(settings: makeSettings())
        await h.step(advance: 0, systemIdle: 0)
        await h.step(advance: 3, systemIdle: 3)
        #expect(h.model.live.statistics.totalRunningSeconds == 3)
        h.driver.setEnabled(false)
        await h.step(advance: 3, systemIdle: 6)
        #expect(h.model.live.statistics.totalRunningSeconds == 3)
    }

    @Test("同一轮 run loop 里的多次 setNeedsTick 只重算一次")
    func coalescedTick() async {
        let h = DriverHarness(settings: makeSettings())
        await h.step(advance: 0, systemIdle: 0)
        let before = h.environment.requests.count
        h.driver.setNeedsTick()
        h.driver.setNeedsTick()
        h.driver.setNeedsTick()
        await h.settle()
        #expect(h.environment.requests.count == before + 1)
    }

    @Test("每秒的 tick 只通知运行数据，设置界面不随之重算")
    func tickPublishesOnlyLiveState() async {
        let h = DriverHarness(settings: makeSettings())
        await h.step(advance: 0, systemIdle: 0)
        var modelChanges = 0
        var liveChanges = 0
        let subscriptions = [
            h.model.objectWillChange.sink { modelChanges += 1 },
            h.model.live.objectWillChange.sink { liveChanges += 1 },
        ]
        for second in 1 ... 5 {
            await h.step(advance: 1, systemIdle: Double(second))
        }
        #expect(modelChanges == 0)
        #expect(liveChanges > 0)
        withExtendedLifetime(subscriptions) {}
    }

    @Test("设置变更回调触发")
    func settingsChangeCallback() async {
        let h = DriverHarness(settings: makeSettings())
        var calls = 0
        h.model.onSettingsChanged = { _, _ in calls += 1 }
        h.model.settings.idleThresholdSeconds = 30
        h.model.settings.idleThresholdSeconds = 30 // 相同值不触发
        #expect(calls == 1)
    }
}

@Suite("诊断报告")
@MainActor
struct DiagnosticsReportTests {
    @Test("包含关键字段")
    func report() {
        let model = AppModel(settings: .default)
        model.live.status = .watching(idleSeconds: 1, remainingSeconds: 59)
        let text = DiagnosticsReport.text(model: model)
        #expect(text.contains("status: watching"))
        #expect(text.contains("accessibility:"))
        #expect(text.contains("settings: idle=60.0s"))
    }
}
