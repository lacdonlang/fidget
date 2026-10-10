import Foundation

/// 菜单栏图标样式；具体的 SF Symbol 名称由界面层决定，核心层只保存语义。
public enum MenuBarIconStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    case cursor, mouse, bolt, eye, dot
    public var id: String { rawValue }
}

/// 应用的外观（设置等窗口、弹出面板与菜单）；菜单栏图标跟随菜单栏，不受影响。
public enum AppearancePreference: String, Codable, CaseIterable, Sendable, Identifiable {
    case system, light, dark
    public var id: String { rawValue }
}

public struct GeneralSettings: Codable, Equatable, Sendable {
    public var menuBarIconStyle: MenuBarIconStyle
    /// 在菜单栏图标旁显示倒计时文本。
    public var showCountdownInMenuBar: Bool
    /// 全局快捷键：切换启用/暂停。nil 表示未设置。
    public var hotKey: HotKey?
    /// 是否已经完成首次引导。
    public var hasCompletedOnboarding: Bool
    /// 界面语言覆盖（如 "zh-Hans"）；nil 表示跟随系统。
    public var languageOverride: String?
    /// 浅色 / 深色外观；默认跟随系统。
    public var appearance: AppearancePreference

    public init(
        menuBarIconStyle: MenuBarIconStyle = .cursor,
        showCountdownInMenuBar: Bool = false,
        hotKey: HotKey? = nil,
        hasCompletedOnboarding: Bool = false,
        languageOverride: String? = nil,
        appearance: AppearancePreference = .system
    ) {
        self.menuBarIconStyle = menuBarIconStyle
        self.showCountdownInMenuBar = showCountdownInMenuBar
        self.hotKey = hotKey
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.languageOverride = languageOverride
        self.appearance = appearance
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GeneralSettings()
        menuBarIconStyle = c.lenient(.menuBarIconStyle, default: d.menuBarIconStyle)
        showCountdownInMenuBar = c.lenient(.showCountdownInMenuBar, default: d.showCountdownInMenuBar)
        hotKey = c.lenient(.hotKey, default: d.hotKey)
        hasCompletedOnboarding = c.lenient(.hasCompletedOnboarding, default: d.hasCompletedOnboarding)
        languageOverride = c.lenient(.languageOverride, default: d.languageOverride)
        appearance = c.lenient(.appearance, default: d.appearance)
    }
}

public struct AdvancedSettings: Codable, Equatable, Sendable {
    /// 将日志写入 ~/Library/Logs/Fidget/，用于排查“鼠标没有动”之类的问题。
    public var fileLoggingEnabled: Bool
    /// 每次移动后读回指针位置以确认移动确实发生（可发现权限丢失）。
    public var verifyPointerMovement: Bool

    public init(fileLoggingEnabled: Bool = false, verifyPointerMovement: Bool = true) {
        self.fileLoggingEnabled = fileLoggingEnabled
        self.verifyPointerMovement = verifyPointerMovement
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AdvancedSettings()
        fileLoggingEnabled = c.lenient(.fileLoggingEnabled, default: d.fileLoggingEnabled)
        verifyPointerMovement = c.lenient(.verifyPointerMovement, default: d.verifyPointerMovement)
    }
}

/// 电源断言组合。既是用户设置（工作时要额外持有哪些断言），也是引擎每个 tick 给出的期望状态。
public struct PowerAssertionState: Codable, Equatable, Sendable, CustomStringConvertible {
    /// 通过 IOPMAssertion 阻止显示器因闲置而休眠。
    public var preventDisplaySleep: Bool
    /// 阻止系统因闲置而休眠（显示器仍可关闭）。
    public var preventSystemSleep: Bool

    public init(preventDisplaySleep: Bool = false, preventSystemSleep: Bool = false) {
        self.preventDisplaySleep = preventDisplaySleep
        self.preventSystemSleep = preventSystemSleep
    }

    public static let none = PowerAssertionState()

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        preventDisplaySleep = c.lenient(.preventDisplaySleep, default: false)
        preventSystemSleep = c.lenient(.preventSystemSleep, default: false)
    }

    /// 用于日志与诊断报告。
    public var description: String { "display=\(preventDisplaySleep) system=\(preventSystemSleep)" }
}
