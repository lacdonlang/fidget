import Foundation
import Testing
@testable import FidgetCore

@Suite("设置模型")
struct SettingsTests {
    @Test("默认值本身就是合法的")
    func defaultsAreValid() {
        let s = Settings.default
        #expect(s.validated() == s)
        #expect(s.isEnabled)
        #expect(s.idleThresholdSeconds == 60)
        #expect(s.rules.pauseWhenScreenLocked)
    }

    @Test("JSON 往返不丢失任何字段")
    func roundTrip() throws {
        var s = Settings.default
        s.idleThresholdSeconds = 120
        s.movement = MovementSettings(pattern: .figureEight, amplitude: 42, durationMilliseconds: 800, returnToOrigin: false, invisibleMode: false)
        s.schedule = ScheduleSettings(isEnabled: true, activeDays: [.monday, .sunday], startMinute: 22 * 60, endMinute: 6 * 60)
        s.rules.appRules = [AppRule(bundleIdentifier: "us.zoom.xos", displayName: "zoom.us")]
        s.rules.appRuleMode = .frontmost
        s.general.hotKey = HotKey(keyCode: 38, modifiers: [.command, .option])
        s.general.languageOverride = "zh-Hans"
        s.general.appearance = .light
        s.keepAwake = PowerAssertionState(preventDisplaySleep: true)
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(Settings.self, from: data)
        #expect(decoded == s)
    }

    @Test("缺失字段与类型错误都回退到默认值")
    func lenientDecoding() throws {
        let json = """
        {"schemaVersion": 1, "idleThresholdSeconds": "oops", "movement": {"pattern": "circle"}, "rules": 5,
         "general": {"launchAtLogin": true, "menuBarIconStyle": "bolt", "appearance": "sepia"}, "keepAwake": {"preventSystemSleep": true}}
        """
        let s = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        #expect(s.idleThresholdSeconds == Settings.default.idleThresholdSeconds)
        #expect(s.movement.pattern == .circle)
        #expect(s.movement.amplitude == MovementSettings().amplitude)
        #expect(s.rules == RuleSettings())
        #expect(s.general.menuBarIconStyle == .bolt, "旧版本里已删除的键会被忽略")
        #expect(s.general.appearance == .system, "不认识的外观回退为跟随系统")
        #expect(s.keepAwake == PowerAssertionState(preventSystemSleep: true))
    }

    @Test("空对象也能解码为默认设置")
    func emptyObject() throws {
        let s = try JSONDecoder().decode(Settings.self, from: Data("{}".utf8))
        #expect(s == Settings.default)
    }

    @Test("校验会把越界数值收敛到范围内")
    func validationClamps() {
        var s = Settings.default
        s.idleThresholdSeconds = 1
        s.jiggleIntervalSeconds = 1_000_000
        s.movement.amplitude = 0
        s.movement.durationMilliseconds = 10
        s.schedule.startMinute = -5
        s.schedule.endMinute = 5000
        s.rules.appRules = [
            AppRule(bundleIdentifier: "a", displayName: "A"),
            AppRule(bundleIdentifier: "a", displayName: "A dup"),
            AppRule(bundleIdentifier: "  ", displayName: "blank"),
        ]
        let v = s.validated()
        #expect(v.idleThresholdSeconds == SettingsLimits.idleThresholdSeconds.lowerBound)
        #expect(v.jiggleIntervalSeconds == SettingsLimits.jiggleIntervalSeconds.upperBound)
        #expect(v.movement.amplitude == SettingsLimits.amplitude.lowerBound)
        #expect(v.movement.durationMilliseconds == SettingsLimits.durationMilliseconds.lowerBound)
        #expect(v.schedule.startMinute == 0)
        #expect(v.schedule.endMinute == 1439)
        #expect(v.rules.appRules.count == 1)
    }

    @Test("隐形模式的有效参数固定为 1 像素且回到原点")
    func invisibleEffective() {
        let m = MovementSettings(pattern: .circle, amplitude: 100, durationMilliseconds: 2000, returnToOrigin: false, invisibleMode: true)
        let e = m.effective
        #expect(e.amplitude == 1)
        #expect(e.returnToOrigin)
        #expect(e.pattern == .nudge)
        #expect(e.durationMilliseconds <= 100)
    }
}
