import FidgetCore
import FidgetSystem
import Foundation

/// 组合根：应用运行所需的全部系统服务。测试注入替身。
@MainActor
struct AppServices {
    var idleTime: IdleTimeProviding
    var pointer: PointerControlling
    var power: PowerAssertionControlling
    var environment: EnvironmentProviding
    var accessibility: AccessibilityPermissionChecking
    var settingsStore: any ValueStore<Settings>
    var statisticsStore: any ValueStore<Statistics>
    var loginItems: LoginItemManager?
    var hotKeys: HotKeyCenter?
    var now: @Sendable () -> Date = { Date() }

    /// 真实 macOS 实现。
    static func live() -> AppServices {
        AppServices(
            idleTime: CGIdleTimeProvider(),
            pointer: CGPointerController(),
            power: IOPowerAssertionController(),
            environment: SystemEnvironmentProvider(),
            accessibility: AccessibilityPermission(),
            settingsStore: JSONFileStore.settings(),
            statisticsStore: JSONFileStore.statistics(),
            loginItems: LoginItemManager(),
            hotKeys: HotKeyCenter()
        )
    }
}
