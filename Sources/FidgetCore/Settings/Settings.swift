import Foundation

/// 顶层设置模型。所有字段都有默认值；解码时缺失的键回退到默认值，保证配置文件向前兼容。
public struct Settings: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    /// 总开关。
    public var isEnabled: Bool
    /// 用户真实输入停止多久后开始移动鼠标（秒）。
    public var idleThresholdSeconds: Double
    /// 处于闲置状态时，每隔多久移动一次（秒）。
    public var jiggleIntervalSeconds: Double
    public var movement: MovementSettings
    public var schedule: ScheduleSettings
    public var rules: RuleSettings
    /// 工作期间（监测中 / 工作中）额外持有的电源断言。
    public var keepAwake: PowerAssertionState
    public var general: GeneralSettings
    public var advanced: AdvancedSettings

    public init(
        schemaVersion: Int = Settings.currentSchemaVersion,
        isEnabled: Bool = true,
        idleThresholdSeconds: Double = 60,
        jiggleIntervalSeconds: Double = 60,
        movement: MovementSettings = MovementSettings(),
        schedule: ScheduleSettings = ScheduleSettings(),
        rules: RuleSettings = RuleSettings(),
        keepAwake: PowerAssertionState = .none,
        general: GeneralSettings = GeneralSettings(),
        advanced: AdvancedSettings = AdvancedSettings()
    ) {
        self.schemaVersion = schemaVersion
        self.isEnabled = isEnabled
        self.idleThresholdSeconds = idleThresholdSeconds
        self.jiggleIntervalSeconds = jiggleIntervalSeconds
        self.movement = movement
        self.schedule = schedule
        self.rules = rules
        self.keepAwake = keepAwake
        self.general = general
        self.advanced = advanced
    }

    public static let `default` = Settings()

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings.default
        schemaVersion = c.lenient(.schemaVersion, default: d.schemaVersion)
        isEnabled = c.lenient(.isEnabled, default: d.isEnabled)
        idleThresholdSeconds = c.lenient(.idleThresholdSeconds, default: d.idleThresholdSeconds)
        jiggleIntervalSeconds = c.lenient(.jiggleIntervalSeconds, default: d.jiggleIntervalSeconds)
        movement = c.lenient(.movement, default: d.movement)
        schedule = c.lenient(.schedule, default: d.schedule)
        rules = c.lenient(.rules, default: d.rules)
        keepAwake = c.lenient(.keepAwake, default: d.keepAwake)
        general = c.lenient(.general, default: d.general)
        advanced = c.lenient(.advanced, default: d.advanced)
    }

    // MARK: - 校验

    /// 返回把所有数值收敛到合法范围后的副本。UI 与持久化层都应使用该方法，避免出现“0 秒间隔”这类病态配置。
    public func validated() -> Settings {
        var s = self
        s.schemaVersion = Settings.currentSchemaVersion
        s.idleThresholdSeconds = SettingsLimits.idleThresholdSeconds.clamping(s.idleThresholdSeconds)
        s.jiggleIntervalSeconds = SettingsLimits.jiggleIntervalSeconds.clamping(s.jiggleIntervalSeconds)
        s.movement = s.movement.validated()
        s.schedule = s.schedule.validated()
        s.rules = s.rules.validated()
        return s
    }
}

/// 各项设置的合法范围，UI 的滑杆与校验逻辑共用同一份常量。
public enum SettingsLimits {
    public static let idleThresholdSeconds: ClosedRange<Double> = 5 ... 7200
    public static let jiggleIntervalSeconds: ClosedRange<Double> = 5 ... 7200
    public static let amplitude: ClosedRange<Double> = 1 ... 300
    public static let durationMilliseconds: ClosedRange<Int> = 50 ... 3000
    public static let minuteOfDay: ClosedRange<Int> = 0 ... (24 * 60 - 1)
}

extension ClosedRange {
    public func clamping(_ value: Bound) -> Bound {
        Swift.min(Swift.max(value, lowerBound), upperBound)
    }
}
