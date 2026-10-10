import Foundation

/// 应用规则：列表中的应用处于指定状态时暂停移动。
public struct AppRule: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var bundleIdentifier: String
    public var displayName: String

    public var id: String { bundleIdentifier }

    public init(bundleIdentifier: String, displayName: String) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
    }
}

public enum AppRuleMode: String, Codable, CaseIterable, Sendable, Identifiable {
    /// 只要应用在运行就暂停。
    case running
    /// 仅当应用位于最前时暂停。
    case frontmost
    public var id: String { rawValue }
}

public struct RuleSettings: Codable, Equatable, Sendable {
    /// 锁屏、屏保或会话切出时暂停（移动鼠标在这些状态下没有意义）。
    public var pauseWhenScreenLocked: Bool
    /// 使用电池供电时暂停，避免白白耗电。
    public var pauseOnBattery: Bool
    /// 其他应用正在阻止显示器休眠（视频播放、演示、视频会议）时暂停。
    public var pauseWhenOtherAppPreventsDisplaySleep: Bool
    public var appRules: [AppRule]
    public var appRuleMode: AppRuleMode

    public init(
        pauseWhenScreenLocked: Bool = true,
        pauseOnBattery: Bool = false,
        pauseWhenOtherAppPreventsDisplaySleep: Bool = false,
        appRules: [AppRule] = [],
        appRuleMode: AppRuleMode = .running
    ) {
        self.pauseWhenScreenLocked = pauseWhenScreenLocked
        self.pauseOnBattery = pauseOnBattery
        self.pauseWhenOtherAppPreventsDisplaySleep = pauseWhenOtherAppPreventsDisplaySleep
        self.appRules = appRules
        self.appRuleMode = appRuleMode
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = RuleSettings()
        pauseWhenScreenLocked = c.lenient(.pauseWhenScreenLocked, default: d.pauseWhenScreenLocked)
        pauseOnBattery = c.lenient(.pauseOnBattery, default: d.pauseOnBattery)
        pauseWhenOtherAppPreventsDisplaySleep = c.lenient(.pauseWhenOtherAppPreventsDisplaySleep, default: d.pauseWhenOtherAppPreventsDisplaySleep)
        appRules = c.lenient(.appRules, default: d.appRules)
        appRuleMode = c.lenient(.appRuleMode, default: d.appRuleMode)
    }

    /// 去重并剔除空 bundle id。
    public func validated() -> RuleSettings {
        var s = self
        var seen = Set<String>()
        s.appRules = appRules.filter { rule in
            let id = rule.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, !seen.contains(id) else { return false }
            seen.insert(id)
            return true
        }
        return s
    }

    /// 根据环境快照判断应用规则是否命中，返回命中的规则。
    public func matchingAppRule(in environment: EnvironmentSnapshot) -> AppRule? {
        switch appRuleMode {
        case .running:
            return appRules.first { environment.runningBundleIdentifiers.contains($0.bundleIdentifier) }
        case .frontmost:
            guard let front = environment.frontmostBundleIdentifier else { return nil }
            return appRules.first { $0.bundleIdentifier == front }
        }
    }
}
