import Foundation

/// 星期，数值与 `Calendar` 的 weekday 一致（1 = 周日）。
public enum Weekday: Int, Codable, CaseIterable, Sendable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    public var previous: Weekday { Weekday(rawValue: rawValue == 1 ? 7 : rawValue - 1)! }
    public var next: Weekday { Weekday(rawValue: rawValue == 7 ? 1 : rawValue + 1)! }

    public static let workdays: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]

    /// 按日历的 firstWeekday 排列，供界面显示。
    public static func ordered(firstWeekday: Int) -> [Weekday] {
        let start = Weekday(rawValue: (1 ... 7).contains(firstWeekday) ? firstWeekday : 1)!
        var result: [Weekday] = []
        var day = start
        for _ in 0 ..< 7 {
            result.append(day)
            day = day.next
        }
        return result
    }
}

extension Calendar {
    /// 从当天 0:00 起的分钟数。
    public func minuteOfDay(of date: Date) -> Int {
        let c = dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// `day` 所在那天的第 `minuteOfDay` 分钟。
    public func date(atMinuteOfDay minuteOfDay: Int, on day: Date) -> Date? {
        date(bySettingHour: minuteOfDay / 60, minute: minuteOfDay % 60, second: 0, of: day)
    }

    public func weekday(of date: Date) -> Weekday? {
        Weekday(rawValue: component(.weekday, from: date))
    }
}

/// 计划表：只在指定的星期与时间窗口内工作。
/// 当 `endMinute <= startMinute` 时表示跨午夜窗口（例如 22:00 – 06:00），窗口归属于开始日。
public struct ScheduleSettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var activeDays: Set<Weekday>
    /// 从当天 0:00 起的分钟数。
    public var startMinute: Int
    public var endMinute: Int

    public init(
        isEnabled: Bool = false,
        activeDays: Set<Weekday> = Weekday.workdays,
        startMinute: Int = 9 * 60,
        endMinute: Int = 18 * 60
    ) {
        self.isEnabled = isEnabled
        self.activeDays = activeDays
        self.startMinute = startMinute
        self.endMinute = endMinute
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ScheduleSettings()
        isEnabled = c.lenient(.isEnabled, default: d.isEnabled)
        activeDays = c.lenient(.activeDays, default: d.activeDays)
        startMinute = c.lenient(.startMinute, default: d.startMinute)
        endMinute = c.lenient(.endMinute, default: d.endMinute)
    }

    public func validated() -> ScheduleSettings {
        var s = self
        s.startMinute = SettingsLimits.minuteOfDay.clamping(startMinute)
        s.endMinute = SettingsLimits.minuteOfDay.clamping(endMinute)
        return s
    }

    public var isOvernight: Bool { endMinute <= startMinute }

    /// 给定时刻是否处于工作窗口内。计划表关闭时恒为 true。
    public func isActive(at date: Date, calendar: Calendar) -> Bool {
        guard isEnabled else { return true }
        guard let weekday = calendar.weekday(of: date) else { return true }
        let minute = calendar.minuteOfDay(of: date)
        if isOvernight {
            return (activeDays.contains(weekday) && minute >= startMinute)
                || (activeDays.contains(weekday.previous) && minute < endMinute)
        }
        return activeDays.contains(weekday) && minute >= startMinute && minute < endMinute
    }

    /// 下一次进入工作窗口的时刻；若此刻已在窗口内则返回 `date` 本身；没有任何工作日时返回 nil。
    public func nextActiveDate(after date: Date, calendar: Calendar) -> Date? {
        guard isEnabled else { return date }
        if isActive(at: date, calendar: calendar) { return date }
        guard !activeDays.isEmpty else { return nil }
        let today = calendar.startOfDay(for: date)
        for offset in 0 ... 7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let weekday = calendar.weekday(of: day),
                  activeDays.contains(weekday),
                  let start = calendar.date(atMinuteOfDay: startMinute, on: day)
            else { continue }
            if start > date { return start }
        }
        return nil
    }
}
