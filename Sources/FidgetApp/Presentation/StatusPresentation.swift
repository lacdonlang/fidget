import AppKit
import FidgetCore
import Foundation

/// 把引擎状态映射为界面文案与菜单栏图标。纯函数，便于测试。
struct StatusPresentation: Equatable {
    var kind: EngineStatus.Kind
    var title: String
    var detail: String
    /// 菜单栏图标 SF Symbol 名称。
    var symbolName: String
    /// 菜单栏可选的倒计时文本。
    var countdown: String?

    static func make(status: EngineStatus, settings: Settings, now: Date, calendar: Calendar = .current) -> StatusPresentation {
        let kind = status.kind
        let symbolName = symbol(settings.general.menuBarIconStyle, kind)
        switch status {
        case .off:
            return StatusPresentation(kind: kind, title: L.t("status.off.title"), detail: L.t("status.off.detail"), symbolName: symbolName)
        case .blocked:
            return StatusPresentation(kind: kind, title: L.t("status.blocked.title"), detail: L.t("status.blocked.detail"), symbolName: symbolName)
        case let .paused(reason):
            return StatusPresentation(kind: kind, title: L.t("status.paused.title"), detail: pauseDetail(reason, now: now, calendar: calendar), symbolName: symbolName)
        case let .watching(idle, remaining):
            let detail = L.f("status.watching.detail", humanDuration(idle), humanDuration(remaining))
            return StatusPresentation(kind: kind, title: L.t("status.watching.title"), detail: detail, symbolName: symbolName, countdown: DurationFormatting.clock(remaining))
        case let .active(idle, count, next):
            let detail = L.f("status.active.detail", humanDuration(idle), count, humanDuration(next))
            return StatusPresentation(kind: kind, title: L.t("status.active.title"), detail: detail, symbolName: symbolName, countdown: DurationFormatting.clock(next))
        }
    }

    static func pauseDetail(_ reason: PauseReason, now: Date, calendar: Calendar) -> String {
        switch reason {
        case let .manual(until):
            guard let until else { return L.t("status.paused.manual.indefinite") }
            return L.f("status.paused.manual.until", timeString(until, now: now, calendar: calendar))
        case .screenLocked:
            return L.t("status.paused.screenLocked")
        case .onBattery:
            return L.t("status.paused.onBattery")
        case let .outsideSchedule(resumesAt):
            guard let resumesAt else { return L.t("status.paused.schedule.never") }
            return L.f("status.paused.schedule", timeString(resumesAt, now: now, calendar: calendar))
        case let .app(rule):
            return L.f("status.paused.app", rule.displayName)
        case .otherAppPreventsDisplaySleep:
            return L.t("status.paused.media")
        }
    }

    /// 同一天只显示时刻，否则显示“周几 时刻”。
    static func timeString(_ date: Date, now: Date, calendar: Calendar) -> String {
        LocalizedFormatters.with { calendar.isDate(date, inSameDayAs: now) ? $0.time.string(from: date) : $0.dayTime.string(from: date) }
    }

    /// 带秒的时刻，例如“14:05:09”。
    static func clockTime(_ date: Date) -> String {
        LocalizedFormatters.with { $0.timeWithSeconds.string(from: date) }
    }

    /// 相对时间，例如“3 分钟前”。
    static func relativeTime(_ date: Date, now: Date = Date()) -> String {
        LocalizedFormatters.with { $0.relative.localizedString(for: date, relativeTo: now) }
    }

    static func humanDuration(_ seconds: TimeInterval) -> String {
        LocalizedFormatters.with { $0.duration.string(from: max(0, seconds.rounded())) } ?? DurationFormatting.clock(seconds)
    }

    /// 菜单栏图标：暂停与缺权限用固定符号，其余按用户选择的风格区分关闭 / 监测中 / 工作中。
    /// 比 macOS 11 新的符号在旧系统上换成替代品（见 `Symbols`）。
    static func symbol(_ style: MenuBarIconStyle, _ kind: EngineStatus.Kind) -> String {
        Symbols.name(preferredSymbol(style, kind))
    }

    static func preferredSymbol(_ style: MenuBarIconStyle, _ kind: EngineStatus.Kind) -> String {
        switch (style, kind) {
        case (_, .blocked): "exclamationmark.triangle"
        case (_, .paused): "pause.circle"
        case (.cursor, .off): "cursorarrow.slash"
        case (.cursor, .watching): "cursorarrow"
        case (.cursor, .active): "cursorarrow.motionlines"
        case (.mouse, .off): "computermouse"
        case (.mouse, .watching): "computermouse"
        case (.mouse, .active): "computermouse.fill"
        case (.bolt, .off): "bolt.slash"
        case (.bolt, .watching): "bolt"
        case (.bolt, .active): "bolt.fill"
        case (.eye, .off): "eye.slash"
        case (.eye, .watching): "eye"
        case (.eye, .active): "eye.fill"
        case (.dot, .off): "circle.dotted"
        case (.dot, .watching): "circle"
        case (.dot, .active): "circle.fill"
        }
    }

    /// 设置界面里图标样式选择器用的代表性符号。
    static func previewSymbol(for style: MenuBarIconStyle) -> String { symbol(style, .active) }
}

extension MovementPattern {
    var localizedName: String { L.t("pattern.\(rawValue)") }
    var symbolName: String {
        switch self {
        case .nudge: "arrow.left.and.right"
        case .circle: "circle"
        case .square: "square"
        case .figureEight: "infinity"
        case .randomWalk: "shuffle"
        }
    }
}

extension PausePreset {
    var localizedName: String { L.t("pause.\(rawValue)") }
}

extension MenuBarIconStyle {
    var localizedName: String { L.t("iconStyle.\(rawValue)") }
}

extension AppRuleMode {
    var localizedName: String { L.t("rules.appMode.\(rawValue)") }
}

extension AppearancePreference {
    var localizedName: String { L.t("appearance.\(rawValue)") }

    /// 对应的系统外观；nil 表示跟随系统。
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

extension PowerAssertionState {
    /// 例如“阻止显示器休眠 · 阻止系统休眠”；都没有时为“无”。
    var localizedSummary: String {
        var parts: [String] = []
        if preventDisplaySleep { parts.append(L.t("keepAwake.display")) }
        if preventSystemSleep { parts.append(L.t("keepAwake.system")) }
        return parts.isEmpty ? L.t("common.none") : parts.joined(separator: " · ")
    }
}

extension Weekday {
    /// 本地化的单字符/短名称，例如“一”或“M”。
    func shortName(calendar: Calendar = L.calendar) -> String { symbol(in: calendar.veryShortWeekdaySymbols) }

    func fullName(calendar: Calendar = L.calendar) -> String { symbol(in: calendar.weekdaySymbols) }

    private func symbol(in symbols: [String]) -> String {
        symbols.indices.contains(rawValue - 1) ? symbols[rawValue - 1] : "\(rawValue)"
    }
}

/// 界面上的日期与时长格式化器。跟随界面语言（`L.locale`），语言切换后按需重建；经锁串行使用。
private struct LocalizedFormatters {
    let locale: Locale
    let time: DateFormatter
    let timeWithSeconds: DateFormatter
    let dayTime: DateFormatter
    let duration: DateComponentsFormatter
    let relative: RelativeDateTimeFormatter

    private static let cache = Locked<LocalizedFormatters?>(nil)

    static func with<Result>(_ body: (LocalizedFormatters) -> Result) -> Result {
        let locale = L.locale
        return cache.withLock { cached in
            if cached?.locale != locale { cached = LocalizedFormatters(locale: locale) }
            return body(cached!)
        }
    }

    private init(locale: Locale) {
        self.locale = locale
        time = DateFormatter()
        time.locale = locale
        time.dateStyle = .none
        time.timeStyle = .short
        timeWithSeconds = DateFormatter()
        timeWithSeconds.locale = locale
        timeWithSeconds.dateStyle = .none
        timeWithSeconds.timeStyle = .medium
        dayTime = DateFormatter()
        dayTime.locale = locale
        dayTime.setLocalizedDateFormatFromTemplate("EEE HH:mm")
        duration = DateComponentsFormatter()
        duration.calendar = L.calendar
        duration.unitsStyle = .abbreviated
        duration.allowedUnits = [.hour, .minute, .second]
        duration.maximumUnitCount = 2
        relative = RelativeDateTimeFormatter()
        relative.locale = locale
        relative.dateTimeStyle = .named
    }
}
