import Combine
import FidgetCore
import FidgetSystem
import Foundation

/// 界面的唯一数据源。所有状态由 `EngineDriver` 与 `AppDelegate` 更新，视图与菜单栏图标只读取并通过动作回调修改。
///
/// 每个 tick 都可能变化的运行数据（状态、统计、诊断）放在 `live` 里单独发布：
/// `ObservableObject` 任一属性变化都会让所有订阅者重算，拆开后设置界面只在设置变化时重算，
/// 只有真正显示运行数据的视图才每秒刷新。
@MainActor
final class AppModel: ObservableObject {
    @Published var settings: Settings {
        didSet {
            guard settings != oldValue else { return }
            onSettingsChanged?(oldValue, settings)
        }
    }

    @Published var warnings: [EngineWarning] = []
    @Published var manualPause: ManualPause?
    @Published var isAccessibilityTrusted = false
    @Published var loginItemStatus: LoginItemManager.Status = .unavailable
    @Published var lastJiggle: JiggleResult?
    @Published var lastError: String?

    let live: LiveState
    let updates = UpdateState()

    var onSettingsChanged: ((Settings, Settings) -> Void)?

    init(settings: Settings = .default, statistics: Statistics = Statistics()) {
        self.settings = settings
        live = LiveState(statistics: statistics)
    }

    /// “登录时启动”开关显示的状态：已启用或已注册但等待用户在系统设置中批准都视为开。
    var launchAtLogin: Bool { loginItemStatus == .enabled || loginItemStatus == .requiresApproval }
}

/// 在线更新的状态（见 `UpdateController`），设置界面据此显示开关与上次检查时间。
@MainActor
final class UpdateState: ObservableObject {
    /// 当前构建能否在线更新（调试构建、未打包运行时不能）。
    @Published var isAvailable = false
    @Published var automaticallyChecks = true
    @Published var automaticallyInstalls = false
    @Published var lastCheck: Date?
}

/// 每个 tick 都可能变化的运行数据。
@MainActor
final class LiveState: ObservableObject {
    struct Diagnostics: Equatable {
        var systemIdleSeconds: TimeInterval = 0
        var realIdleSeconds: TimeInterval = 0
        var environment = EnvironmentSnapshot()
        var assertions = PowerAssertionState.none
        var engineMemory = Engine.Memory()
    }

    @Published var status: EngineStatus = .off
    @Published var statistics: Statistics
    @Published var diagnostics = Diagnostics()

    init(statistics: Statistics) {
        self.statistics = statistics
    }
}
