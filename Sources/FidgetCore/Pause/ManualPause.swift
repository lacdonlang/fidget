import Foundation

/// 用户手动暂停。`until` 为 nil 表示无限期，直到手动恢复。
public struct ManualPause: Equatable, Sendable {
    public var until: Date?

    public init(until: Date?) {
        self.until = until
    }
}

/// 菜单里的暂停预设。
public enum PausePreset: String, CaseIterable, Sendable, Identifiable {
    case minutes15, minutes30, hour1, hours2, hours4, restOfDay, indefinite

    public var id: String { rawValue }

    public var minutes: Int? {
        switch self {
        case .minutes15: 15
        case .minutes30: 30
        case .hour1: 60
        case .hours2: 120
        case .hours4: 240
        case .restOfDay, .indefinite: nil
        }
    }

    /// 计算恢复时刻；无限期返回 nil。
    public func until(from now: Date, calendar: Calendar) -> Date? {
        if let minutes { return now.addingTimeInterval(Double(minutes) * 60) }
        guard self == .restOfDay else { return nil }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86_400)
        return calendar.startOfDay(for: tomorrow)
    }
}
