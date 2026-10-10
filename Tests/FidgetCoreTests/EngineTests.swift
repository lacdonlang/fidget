import Foundation
import Testing
@testable import FidgetCore

/// 用“秒数偏移”驱动引擎的小型模拟器，让测试读起来像时间线。
struct EngineSim {
    var engine = Engine()
    var settings: Settings
    let base = Fixture.date(2026, 10, 12, 10, 0) // 周一 10:00
    /// 最近一次 HID 事件（含合成事件）的时间偏移。
    var lastHIDEvent: TimeInterval = 0
    var trusted = true
    var environment = EnvironmentSnapshot()
    var manualPause: ManualPause?
    var inProgress = false
    /// 模拟的移动是否真的让指针动了。
    var pointerMoves = true

    init(settings: Settings = Settings.default) {
        self.settings = settings
    }

    func now(_ t: TimeInterval) -> Date { base.addingTimeInterval(t) }

    /// 模拟用户在 t 时刻有真实输入。
    mutating func userInput(at t: TimeInterval) { lastHIDEvent = max(lastHIDEvent, t) }

    mutating func tick(_ t: TimeInterval) -> EngineOutput {
        let input = EngineInput(
            now: now(t),
            settings: settings,
            systemIdleSeconds: t - lastHIDEvent,
            isAccessibilityTrusted: trusted,
            environment: environment,
            manualPause: manualPause,
            isJiggleInProgress: inProgress,
            calendar: Fixture.calendar
        )
        let out = engine.tick(input)
        // 模拟驱动层：执行移动会产生合成事件，并在 0.3 秒后结束。
        for effect in out.effects {
            switch effect {
            case .performJiggle:
                lastHIDEvent = max(lastHIDEvent, t + 0.3)
                engine.noteJiggleFinished(at: now(t + 0.3), pointerMoved: pointerMoves)
            case .clearManualPause:
                manualPause = nil
            }
        }
        return out
    }

    func jiggles(_ out: EngineOutput) -> Int {
        out.effects.filter { if case .performJiggle = $0 { true } else { false } }.count
    }
}

@Suite("引擎状态机")
struct EngineTests {
    @Test("关闭时状态为 off，且释放电源断言")
    func off() {
        var sim = EngineSim()
        sim.settings.isEnabled = false
        sim.settings.keepAwake.preventDisplaySleep = true
        let out = sim.tick(0)
        #expect(out.status == .off)
        #expect(out.powerAssertions == .none)
        #expect(sim.jiggles(out) == 0)
    }

    @Test("缺少辅助功能权限时阻塞")
    func blocked() {
        var sim = EngineSim()
        sim.trusted = false
        let out = sim.tick(100)
        #expect(out.status == .blocked(.accessibilityPermission))
        #expect(sim.jiggles(out) == 0)
    }

    @Test("达到闲置阈值前处于 watching，达到后立即移动")
    func watchingThenActive() {
        var sim = EngineSim()
        sim.settings.idleThresholdSeconds = 60
        sim.userInput(at: 0)
        let early = sim.tick(30)
        guard case let .watching(idle, remaining) = early.status else { Issue.record("应为 watching"); return }
        #expect(idle == 30 && remaining == 30)
        #expect(sim.jiggles(early) == 0)

        let at = sim.tick(60)
        guard case let .active(idle2, count, next) = at.status else { Issue.record("应为 active"); return }
        #expect(idle2 == 60)
        #expect(count == 1)
        #expect(next == 60)
        #expect(sim.jiggles(at) == 1)
        if case let .performJiggle(_, sequence) = at.effects.first(where: { if case .performJiggle = $0 { true } else { false } })! {
            #expect(sequence == 0)
        }
    }

    @Test("合成事件不会被当成真实输入：闲置继续累积，按间隔重复移动")
    func syntheticEventsAreIgnored() {
        var sim = EngineSim()
        sim.settings.idleThresholdSeconds = 60
        sim.settings.jiggleIntervalSeconds = 30
        sim.userInput(at: 0)
        _ = sim.tick(60) // 第一次移动
        let t61 = sim.tick(61)
        guard case let .active(idle, count, next) = t61.status else { Issue.record("应保持 active"); return }
        #expect(idle == 61)
        #expect(count == 1)
        #expect(abs(next - 29) < 0.001)
        #expect(sim.jiggles(t61) == 0)
        #expect(sim.jiggles(sim.tick(89)) == 0)
        let t90 = sim.tick(90)
        #expect(sim.jiggles(t90) == 1)
        if case let .active(_, count2, _) = t90.status { #expect(count2 == 2) } else { Issue.record("应为 active") }
        if case let .performJiggle(_, sequence) = t90.effects.first(where: { if case .performJiggle = $0 { true } else { false } })! {
            #expect(sequence == 1)
        }
    }

    @Test("真实输入会把状态拉回 watching 并重置计数")
    func realInputResets() {
        var sim = EngineSim()
        sim.settings.idleThresholdSeconds = 60
        sim.userInput(at: 0)
        _ = sim.tick(60)
        _ = sim.tick(120)
        sim.userInput(at: 130)
        let out = sim.tick(131)
        guard case let .watching(idle, _) = out.status else { Issue.record("应为 watching"); return }
        #expect(idle == 1)
        // 再次闲置 60 秒后从序号 0 重新开始
        let again = sim.tick(190)
        #expect(sim.jiggles(again) == 1)
        if case let .active(_, count, _) = again.status { #expect(count == 1) }
    }

    @Test("移动进行中不会叠加新的移动")
    func noOverlap() {
        var sim = EngineSim()
        sim.settings.idleThresholdSeconds = 10
        sim.settings.jiggleIntervalSeconds = 5
        sim.userInput(at: 0)
        _ = sim.tick(10)
        sim.inProgress = true
        #expect(sim.jiggles(sim.tick(15)) == 0)
        #expect(sim.jiggles(sim.tick(20)) == 0)
        sim.inProgress = false
        #expect(sim.jiggles(sim.tick(21)) == 1)
    }

    @Test("手动暂停：定时暂停到期后自动清除并恢复")
    func manualPauseExpires() {
        var sim = EngineSim()
        sim.settings.idleThresholdSeconds = 10
        sim.userInput(at: 0)
        sim.manualPause = ManualPause(until: sim.now(100))
        let paused = sim.tick(50)
        #expect(paused.status == .paused(.manual(until: sim.now(100))))
        #expect(sim.jiggles(paused) == 0)
        let resumed = sim.tick(100)
        #expect(resumed.effects.contains(.clearManualPause))
        #expect(resumed.status.kind == .active)
        #expect(sim.jiggles(resumed) == 1)
        #expect(sim.manualPause == nil)
    }

    @Test("无限期暂停不会自动恢复")
    func indefinitePause() {
        var sim = EngineSim()
        sim.manualPause = ManualPause(until: nil)
        let out = sim.tick(100_000)
        #expect(out.status == .paused(.manual(until: nil)))
        #expect(!out.effects.contains(.clearManualPause))
    }

    @Test("规则优先级：锁屏 > 电池 > 计划表 > 应用 > 其他应用阻止休眠")
    func rulePriority() {
        var sim = EngineSim()
        sim.settings.rules.pauseOnBattery = true
        sim.settings.rules.pauseWhenOtherAppPreventsDisplaySleep = true
        sim.settings.schedule = ScheduleSettings(isEnabled: true, activeDays: Weekday.workdays, startMinute: 9 * 60, endMinute: 18 * 60)
        let zoom = AppRule(bundleIdentifier: "us.zoom.xos", displayName: "zoom.us")
        sim.settings.rules.appRules = [zoom]
        sim.environment = EnvironmentSnapshot(
            isScreenLocked: true, isOnBattery: true, displaySleepHolders: ["Keynote (PreventUserIdleDisplaySleep)"],
            runningBundleIdentifiers: ["us.zoom.xos"], frontmostBundleIdentifier: nil
        )
        #expect(sim.tick(0).status == .paused(.screenLocked))
        sim.environment.isScreenLocked = false
        #expect(sim.tick(1).status == .paused(.onBattery))
        sim.environment.isOnBattery = false
        // 周一 10:00 在计划表窗口内，把时间推到晚上 20:00 验证计划表
        let evening: TimeInterval = 10 * 3600
        let out = sim.tick(evening)
        #expect(out.status == .paused(.outsideSchedule(resumesAt: Fixture.date(2026, 10, 13, 9, 0))))
        sim.settings.schedule.isEnabled = false
        #expect(sim.tick(evening + 1).status == .paused(.app(zoom)))
        sim.environment.runningBundleIdentifiers = []
        #expect(sim.tick(evening + 2).status == .paused(.otherAppPreventsDisplaySleep))
        sim.environment.displaySleepHolders = []
        #expect(sim.tick(evening + 3).status.kind == .active)
    }

    @Test("应用规则的“最前”模式只看最前应用")
    func frontmostAppRule() {
        var sim = EngineSim()
        let zoom = AppRule(bundleIdentifier: "us.zoom.xos", displayName: "zoom.us")
        sim.settings.rules.appRules = [zoom]
        sim.settings.rules.appRuleMode = .frontmost
        sim.environment.runningBundleIdentifiers = ["us.zoom.xos"]
        #expect(sim.tick(0).status.kind != .paused)
        sim.environment.frontmostBundleIdentifier = "us.zoom.xos"
        #expect(sim.tick(1).status == .paused(.app(zoom)))
    }

    @Test("电源断言只在工作中持有用户开启的那些")
    func powerAssertions() {
        var sim = EngineSim()
        sim.settings.keepAwake.preventDisplaySleep = true
        sim.userInput(at: 0)
        #expect(sim.tick(1).powerAssertions == PowerAssertionState(preventDisplaySleep: true))
        sim.manualPause = ManualPause(until: nil)
        #expect(sim.tick(2).powerAssertions == .none)
        sim.manualPause = nil
        sim.settings.isEnabled = false
        #expect(sim.tick(3).powerAssertions == .none)
    }

    @Test("连续移动失败会产生警告，成功一次即清零")
    func warnings() {
        var sim = EngineSim()
        sim.settings.idleThresholdSeconds = 10
        sim.settings.jiggleIntervalSeconds = 5
        sim.pointerMoves = false
        sim.lastHIDEvent = -100
        #expect(sim.tick(0).warnings.isEmpty) // 第 1 次移动，失败结果在 tick 之后才回报
        #expect(sim.tick(5).warnings.isEmpty) // 此时只记了 1 次失败；本次是第 2 次
        #expect(sim.tick(6).warnings == [.pointerDidNotMove(failures: 2)])
        sim.pointerMoves = true
        _ = sim.tick(10)
        #expect(sim.tick(11).warnings.isEmpty)
    }

    @Test("立即移动无视状态、只执行一次，且同样被识别为合成事件")
    func requestedJiggle() {
        var sim = EngineSim()
        sim.settings.idleThresholdSeconds = 60
        sim.userInput(at: 0)
        _ = sim.tick(10)
        sim.engine.requestJiggle()
        let moved = sim.tick(20)
        #expect(sim.jiggles(moved) == 1)
        #expect(moved.status.kind == .watching)
        #expect(sim.jiggles(sim.tick(21)) == 0)
        guard case let .watching(idle, _) = sim.tick(30).status else { Issue.record("应为 watching"); return }
        #expect(idle == 30, "合成事件不应重置真实闲置时间")
        sim.settings.isEnabled = false
        sim.engine.requestJiggle()
        #expect(sim.jiggles(sim.tick(31)) == 1)
    }

    @Test("启动时系统已闲置很久会立刻进入 active")
    func alreadyIdleAtLaunch() {
        var sim = EngineSim()
        sim.lastHIDEvent = -3600
        let out = sim.tick(0)
        #expect(out.status.kind == .active)
        #expect(sim.jiggles(out) == 1)
    }
}
