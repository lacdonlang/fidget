import Foundation

/// 环境快照：由系统层每个 tick 采集，核心层据此评估暂停规则。
public struct EnvironmentSnapshot: Equatable, Sendable {
    /// 锁屏、屏保运行中或当前登录会话不在前台。
    public var isScreenLocked: Bool
    public var isOnBattery: Bool
    /// 正持有“阻止显示器休眠”断言的其他进程（通常意味着在播放视频 / 演示 / 视频会议），供规则与诊断共用。
    public var displaySleepHolders: [String]
    public var runningBundleIdentifiers: Set<String>
    public var frontmostBundleIdentifier: String?

    public init(
        isScreenLocked: Bool = false,
        isOnBattery: Bool = false,
        displaySleepHolders: [String] = [],
        runningBundleIdentifiers: Set<String> = [],
        frontmostBundleIdentifier: String? = nil
    ) {
        self.isScreenLocked = isScreenLocked
        self.isOnBattery = isOnBattery
        self.displaySleepHolders = displaySleepHolders
        self.runningBundleIdentifiers = runningBundleIdentifiers
        self.frontmostBundleIdentifier = frontmostBundleIdentifier
    }

    public var otherAppPreventsDisplaySleep: Bool { !displaySleepHolders.isEmpty }
}

/// 引擎每个 tick 的输入。全部为值类型，便于在测试里构造任意场景。
public struct EngineInput: Sendable {
    public var now: Date
    public var settings: Settings
    /// 系统上报的距上次 HID 事件的秒数（包含我们自己合成的事件）。
    public var systemIdleSeconds: TimeInterval
    public var isAccessibilityTrusted: Bool
    public var environment: EnvironmentSnapshot
    public var manualPause: ManualPause?
    /// 上一次移动是否仍在执行中（执行是异步的）。
    public var isJiggleInProgress: Bool
    public var calendar: Calendar

    public init(
        now: Date,
        settings: Settings,
        systemIdleSeconds: TimeInterval,
        isAccessibilityTrusted: Bool = true,
        environment: EnvironmentSnapshot = EnvironmentSnapshot(),
        manualPause: ManualPause? = nil,
        isJiggleInProgress: Bool = false,
        calendar: Calendar = .current
    ) {
        self.now = now
        self.settings = settings
        self.systemIdleSeconds = systemIdleSeconds
        self.isAccessibilityTrusted = isAccessibilityTrusted
        self.environment = environment
        self.manualPause = manualPause
        self.isJiggleInProgress = isJiggleInProgress
        self.calendar = calendar
    }
}

public enum PauseReason: Equatable, Sendable {
    case manual(until: Date?)
    case screenLocked
    case onBattery
    case outsideSchedule(resumesAt: Date?)
    case app(AppRule)
    case otherAppPreventsDisplaySleep
}

public enum BlockReason: Equatable, Sendable {
    case accessibilityPermission
}

/// 引擎状态。关联值只用于展示；比较“种类”请用 `kind`。
public enum EngineStatus: Equatable, Sendable {
    case off
    case blocked(BlockReason)
    case paused(PauseReason)
    /// 用户仍活跃，等待达到闲置阈值。
    case watching(idleSeconds: TimeInterval, remainingSeconds: TimeInterval)
    /// 已闲置，正在按间隔移动鼠标。
    case active(idleSeconds: TimeInterval, jiggleCount: Int, nextJiggleInSeconds: TimeInterval)

    public enum Kind: Equatable, Sendable { case off, blocked, paused, watching, active }

    public var kind: Kind {
        switch self {
        case .off: .off
        case .blocked: .blocked
        case .paused: .paused
        case .watching: .watching
        case .active: .active
        }
    }

    /// 处于“工作中”（watching 或 active）。
    public var isRunning: Bool { kind == .watching || kind == .active }
}

public enum EngineEffect: Equatable, Sendable {
    /// 执行一次移动；`sequence` 单调递增，用于交替方向。执行完毕后驱动层须调用 `noteJiggleFinished`。
    case performJiggle(MovementSettings, sequence: Int)
    /// 手动暂停已到期，驱动层应清除它。
    case clearManualPause
}

public enum EngineWarning: Equatable, Sendable {
    /// 连续多次移动后指针位置都没有变化，通常是辅助功能权限被撤销或系统拒绝了事件。
    case pointerDidNotMove(failures: Int)
}

public struct EngineOutput: Equatable, Sendable {
    public var status: EngineStatus
    public var effects: [EngineEffect]
    public var warnings: [EngineWarning]
    /// 此刻应持有的电源断言。驱动层每个 tick 直接应用，控制器自身保证幂等。
    public var powerAssertions: PowerAssertionState
    /// 扣除合成事件后的“真实闲置秒数”。
    public var realIdleSeconds: TimeInterval

    public init(
        status: EngineStatus,
        effects: [EngineEffect] = [],
        warnings: [EngineWarning] = [],
        powerAssertions: PowerAssertionState = .none,
        realIdleSeconds: TimeInterval = 0
    ) {
        self.status = status
        self.effects = effects
        self.warnings = warnings
        self.powerAssertions = powerAssertions
        self.realIdleSeconds = realIdleSeconds
    }
}
