import Foundation
import Testing
@testable import FidgetCore

@Suite("计划表")
struct ScheduleTests {
    let cal = Fixture.calendar

    @Test("关闭计划表时任何时刻都有效")
    func disabledAlwaysActive() {
        let s = ScheduleSettings(isEnabled: false, activeDays: [], startMinute: 0, endMinute: 0)
        #expect(s.isActive(at: Fixture.monday, calendar: cal))
        #expect(s.nextActiveDate(after: Fixture.monday, calendar: cal) == Fixture.monday)
    }

    @Test("普通窗口：开始含、结束不含")
    func normalWindowBoundaries() {
        let s = ScheduleSettings(isEnabled: true, activeDays: Weekday.workdays, startMinute: 9 * 60, endMinute: 18 * 60)
        #expect(s.isActive(at: Fixture.date(2026, 10, 12, 9, 0), calendar: cal))
        #expect(s.isActive(at: Fixture.date(2026, 10, 12, 17, 59), calendar: cal))
        #expect(!s.isActive(at: Fixture.date(2026, 10, 12, 18, 0), calendar: cal))
        #expect(!s.isActive(at: Fixture.date(2026, 10, 12, 8, 59), calendar: cal))
    }

    @Test("周末不在工作日集合内")
    func weekendExcluded() {
        let s = ScheduleSettings(isEnabled: true, activeDays: Weekday.workdays, startMinute: 9 * 60, endMinute: 18 * 60)
        #expect(!s.isActive(at: Fixture.date(2026, 10, 17, 12, 0), calendar: cal)) // 周六
        #expect(!s.isActive(at: Fixture.date(2026, 10, 18, 12, 0), calendar: cal)) // 周日
    }

    @Test("跨午夜窗口归属于开始日")
    func overnightWindow() {
        // 周一 22:00 – 周二 06:00
        let s = ScheduleSettings(isEnabled: true, activeDays: [.monday], startMinute: 22 * 60, endMinute: 6 * 60)
        #expect(s.isOvernight)
        #expect(s.isActive(at: Fixture.date(2026, 10, 12, 23, 30), calendar: cal)) // 周一深夜
        #expect(s.isActive(at: Fixture.date(2026, 10, 13, 2, 0), calendar: cal)) // 周二凌晨
        #expect(!s.isActive(at: Fixture.date(2026, 10, 13, 6, 0), calendar: cal)) // 周二 06:00 结束
        #expect(!s.isActive(at: Fixture.date(2026, 10, 13, 23, 30), calendar: cal)) // 周二深夜：周二不是工作日
        #expect(!s.isActive(at: Fixture.date(2026, 10, 12, 2, 0), calendar: cal)) // 周一凌晨：周日不是工作日
    }

    @Test("开始等于结束表示全天")
    func startEqualsEndMeansAllDay() {
        let s = ScheduleSettings(isEnabled: true, activeDays: [.monday, .tuesday], startMinute: 8 * 60, endMinute: 8 * 60)
        #expect(s.isActive(at: Fixture.date(2026, 10, 12, 3, 0), calendar: cal) == false) // 周一凌晨属于周日
        #expect(s.isActive(at: Fixture.date(2026, 10, 12, 12, 0), calendar: cal))
        #expect(s.isActive(at: Fixture.date(2026, 10, 13, 3, 0), calendar: cal)) // 周二凌晨属于周一
    }

    @Test("下一次恢复时刻：同日稍后、次日、跨周末")
    func nextActiveDate() {
        let s = ScheduleSettings(isEnabled: true, activeDays: Weekday.workdays, startMinute: 9 * 60, endMinute: 18 * 60)
        #expect(s.nextActiveDate(after: Fixture.date(2026, 10, 12, 7, 0), calendar: cal) == Fixture.date(2026, 10, 12, 9, 0))
        #expect(s.nextActiveDate(after: Fixture.date(2026, 10, 12, 19, 0), calendar: cal) == Fixture.date(2026, 10, 13, 9, 0))
        #expect(s.nextActiveDate(after: Fixture.date(2026, 10, 16, 19, 0), calendar: cal) == Fixture.date(2026, 10, 19, 9, 0)) // 周五晚 → 下周一
        let inside = Fixture.date(2026, 10, 12, 10, 0)
        #expect(s.nextActiveDate(after: inside, calendar: cal) == inside)
    }

    @Test("没有任何工作日时返回 nil")
    func noDays() {
        let s = ScheduleSettings(isEnabled: true, activeDays: [], startMinute: 9 * 60, endMinute: 18 * 60)
        #expect(!s.isActive(at: Fixture.monday, calendar: cal))
        #expect(s.nextActiveDate(after: Fixture.monday, calendar: cal) == nil)
    }

    @Test("日历工具：一天中的分钟数与星期")
    func calendarHelpers() {
        let d = Fixture.date(2026, 10, 12, 13, 45)
        #expect(cal.minuteOfDay(of: d) == 13 * 60 + 45)
        #expect(cal.date(atMinuteOfDay: 9 * 60 + 30, on: d) == Fixture.date(2026, 10, 12, 9, 30))
        #expect(cal.weekday(of: d) == .monday)
    }

    @Test("星期按 firstWeekday 排序")
    func weekdayOrdering() {
        #expect(Weekday.ordered(firstWeekday: 2).first == .monday)
        #expect(Weekday.ordered(firstWeekday: 2).last == .sunday)
        #expect(Weekday.ordered(firstWeekday: 1).first == .sunday)
        #expect(Weekday.ordered(firstWeekday: 99).first == .sunday)
        #expect(Weekday.sunday.previous == .saturday)
        #expect(Weekday.saturday.next == .sunday)
    }
}
