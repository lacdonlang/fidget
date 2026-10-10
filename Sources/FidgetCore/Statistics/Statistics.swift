import Foundation

/// 使用统计。按自然日滚动“今日”计数。
public struct Statistics: Codable, Equatable, Sendable {
    public var totalJiggles: Int
    public var todayJiggles: Int
    /// 今日计数所属日期，格式 yyyy-MM-dd（基于本地日历）。
    public var todayKey: String
    public var lastJiggleAt: Date?
    /// 累计处于工作状态（watching / active）的秒数。
    public var totalRunningSeconds: Double
    public var firstLaunchAt: Date?

    public init(
        totalJiggles: Int = 0,
        todayJiggles: Int = 0,
        todayKey: String = "",
        lastJiggleAt: Date? = nil,
        totalRunningSeconds: Double = 0,
        firstLaunchAt: Date? = nil
    ) {
        self.totalJiggles = totalJiggles
        self.todayJiggles = todayJiggles
        self.todayKey = todayKey
        self.lastJiggleAt = lastJiggleAt
        self.totalRunningSeconds = totalRunningSeconds
        self.firstLaunchAt = firstLaunchAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Statistics()
        totalJiggles = c.lenient(.totalJiggles, default: d.totalJiggles)
        todayJiggles = c.lenient(.todayJiggles, default: d.todayJiggles)
        todayKey = c.lenient(.todayKey, default: d.todayKey)
        lastJiggleAt = c.lenient(.lastJiggleAt, default: d.lastJiggleAt)
        totalRunningSeconds = c.lenient(.totalRunningSeconds, default: d.totalRunningSeconds)
        firstLaunchAt = c.lenient(.firstLaunchAt, default: d.firstLaunchAt)
    }

    public static func dayKey(for date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// 如果日期变了就清零今日计数。
    public mutating func rollOverIfNeeded(now: Date, calendar: Calendar) {
        let key = Self.dayKey(for: now, calendar: calendar)
        if key != todayKey {
            todayKey = key
            todayJiggles = 0
        }
    }

    public mutating func recordJiggle(at date: Date, calendar: Calendar) {
        rollOverIfNeeded(now: date, calendar: calendar)
        totalJiggles += 1
        todayJiggles += 1
        lastJiggleAt = date
    }

    public mutating func accumulateRunning(seconds: Double) {
        guard seconds.isFinite, seconds > 0 else { return }
        totalRunningSeconds += seconds
    }

    public mutating func reset() {
        self = Statistics(firstLaunchAt: firstLaunchAt)
    }
}
