import Foundation
import Testing
@testable import FidgetCore

@Suite("统计")
struct StatisticsTests {
    @Test("记录移动并按日滚动")
    func recordAndRollOver() {
        var s = Statistics()
        let cal = Fixture.calendar
        s.recordJiggle(at: Fixture.date(2026, 10, 12, 23, 59), calendar: cal)
        s.recordJiggle(at: Fixture.date(2026, 10, 12, 23, 59, 30), calendar: cal)
        #expect(s.totalJiggles == 2 && s.todayJiggles == 2)
        #expect(s.todayKey == "2026-10-12")
        s.recordJiggle(at: Fixture.date(2026, 10, 13, 0, 0, 1), calendar: cal)
        #expect(s.totalJiggles == 3 && s.todayJiggles == 1)
        #expect(s.todayKey == "2026-10-13")
        s.rollOverIfNeeded(now: Fixture.date(2026, 10, 14), calendar: cal)
        #expect(s.todayJiggles == 0)
    }

    @Test("累计运行时间忽略非法值")
    func running() {
        var s = Statistics()
        s.accumulateRunning(seconds: 1.5)
        s.accumulateRunning(seconds: -3)
        s.accumulateRunning(seconds: .nan)
        #expect(s.totalRunningSeconds == 1.5)
    }

    @Test("重置保留首次启动时间")
    func reset() {
        var s = Statistics(totalJiggles: 5, firstLaunchAt: Fixture.monday)
        s.reset()
        #expect(s.totalJiggles == 0)
        #expect(s.firstLaunchAt == Fixture.monday)
    }

    @Test("JSON 往返")
    func codable() throws {
        let s = Statistics(totalJiggles: 7, todayJiggles: 2, todayKey: "2026-10-12", lastJiggleAt: Fixture.monday, totalRunningSeconds: 42, firstLaunchAt: Fixture.monday)
        let decoded = try JSONDecoder().decode(Statistics.self, from: JSONEncoder().encode(s))
        #expect(decoded == s)
        #expect(try JSONDecoder().decode(Statistics.self, from: Data("{}".utf8)) == Statistics())
    }
}

@Suite("暂停预设")
struct PausePresetTests {
    @Test("各预设的恢复时刻")
    func untilDates() {
        let now = Fixture.date(2026, 10, 12, 10, 30)
        let cal = Fixture.calendar
        #expect(PausePreset.minutes15.until(from: now, calendar: cal) == now.addingTimeInterval(15 * 60))
        #expect(PausePreset.hours4.until(from: now, calendar: cal) == now.addingTimeInterval(4 * 3600))
        #expect(PausePreset.restOfDay.until(from: now, calendar: cal) == Fixture.date(2026, 10, 13, 0, 0))
        #expect(PausePreset.indefinite.until(from: now, calendar: cal) == nil)
    }
}

@Suite("快捷键")
struct HotKeyTests {
    @Test("显示字符串按 ⌃⌥⇧⌘ 顺序")
    func display() {
        let k = HotKey(keyCode: 38, modifiers: [.command, .shift, .control, .option])
        #expect(k.displayString == "⌃⌥⇧⌘J")
        #expect(HotKey(keyCode: 122, modifiers: []).displayString == "F1")
        #expect(HotKey(keyCode: 200, modifiers: [.command]).displayString == "⌘Key 200")
    }

    @Test("合法性：需要修饰键，功能键例外")
    func validity() {
        #expect(!HotKey(keyCode: 0, modifiers: []).isValid)
        #expect(!HotKey(keyCode: 0, modifiers: [.shift]).isValid)
        #expect(HotKey(keyCode: 0, modifiers: [.command]).isValid)
        #expect(HotKey(keyCode: 96, modifiers: []).isValid)
    }

    @Test("JSON 往返")
    func codable() throws {
        let k = HotKey(keyCode: 49, modifiers: [.option])
        #expect(try JSONDecoder().decode(HotKey.self, from: JSONEncoder().encode(k)) == k)
    }
}

@Suite("时长格式化")
struct DurationFormattingTests {
    @Test("倒计时样式")
    func clock() {
        #expect(DurationFormatting.clock(0) == "0:00")
        #expect(DurationFormatting.clock(42.9) == "0:42")
        #expect(DurationFormatting.clock(725) == "12:05")
        #expect(DurationFormatting.clock(3723) == "1:02:03")
        #expect(DurationFormatting.clock(-5) == "0:00")
    }

    @Test("取整到好看的刻度")
    func snap() {
        #expect(DurationFormatting.snapToNiceSeconds(7) == 5)
        #expect(DurationFormatting.snapToNiceSeconds(8) == 10)
        #expect(DurationFormatting.snapToNiceSeconds(100) == 105)
        #expect(DurationFormatting.snapToNiceSeconds(1000) == 1020)
        #expect(DurationFormatting.snapToNiceSeconds(4000) == 3900)
    }
}

@Suite("URL 命令")
struct AppCommandTests {
    @Test("解析各类命令", arguments: [
        ("fidget://enable", AppCommand.enable),
        ("fidget://off", .disable),
        ("fidget://toggle", .toggle),
        ("fidget://pause", .pause(minutes: nil)),
        ("fidget://pause?minutes=30", .pause(minutes: 30)),
        ("fidget://pause?minutes=-3", .pause(minutes: nil)),
        ("fidget://resume", .resume),
        ("fidget://move", .moveNow),
        ("FIDGET://Settings", .openSettings(section: nil)),
        ("fidget://settings?section=movement", .openSettings(section: "movement")),
        ("fidget://setup", .openOnboarding),
    ])
    func parse(raw: String, expected: AppCommand) {
        #expect(AppCommandParser.parse(URL(string: raw)!) == expected)
    }

    @Test("非本应用 scheme 或未知命令返回 nil")
    func rejects() {
        #expect(AppCommandParser.parse(URL(string: "https://example.com/pause")!) == nil)
        #expect(AppCommandParser.parse(URL(string: "fidget://dance")!) == nil)
    }
}

@Suite("加锁的值")
struct LockedTests {
    @Test("并发修改不丢失更新")
    func concurrentIncrements() async {
        let counter = Locked(0)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 8 {
                group.addTask {
                    for _ in 0 ..< 1000 { counter.withLock { $0 += 1 } }
                }
            }
        }
        #expect(counter.withLock { $0 } == 8000)
    }
}
