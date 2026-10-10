import Foundation

/// 核心状态机。纯值类型：每个 tick 接收输入快照，返回状态与副作用，不直接触碰任何系统 API。
///
/// 关键难点是区分“用户的真实输入”与“我们自己合成的鼠标事件”：系统闲置计时会被合成事件重置，
/// 因此引擎记录每次移动的时间窗口，落在窗口内的 HID 事件被视为自己的，不更新“最后真实输入时间”。
/// 所有移动（到点的自动移动与用户请求的立即移动）都由引擎发出，窗口的开始与结束因此只在这里维护。
public struct Engine: Sendable {
    public struct Memory: Equatable, Sendable {
        public var lastRealInputAt: Date?
        /// 最近一次合成事件窗口 [start, end]；end 为 nil 表示移动仍在进行。
        public var syntheticWindowStart: Date?
        public var syntheticWindowEnd: Date?
        /// 本轮闲置期内最近一次自动移动的开始时刻与次数；离开 active 时清零。
        public var lastJiggleStartedAt: Date?
        public var jiggleCount = 0
        /// 单调递增的移动序号，用于交替方向。
        public var sequence = 0
        /// 用户请求了一次立即移动，下一个 tick 发出。
        public var jiggleRequested = false
        /// 连续“指针没有动”的次数。
        public var consecutiveFailures = 0

        public init() {}
    }

    public private(set) var memory = Memory()

    /// 合成事件窗口两侧的容差，吸收事件投递与时间采样之间的抖动。
    static let syntheticTolerance: TimeInterval = 0.75
    /// 连续多少次移动失败后发出警告。
    static let failureWarningThreshold = 2

    public init() {}

    // MARK: - 移动生命周期

    /// 请求立即移动一次（无视当前状态），由下一个 tick 发出。
    public mutating func requestJiggle() {
        memory.jiggleRequested = true
    }

    /// 驱动层在一次移动执行完毕后回报结果。
    public mutating func noteJiggleFinished(at date: Date, pointerMoved: Bool) {
        if memory.syntheticWindowStart == nil { memory.syntheticWindowStart = date }
        memory.syntheticWindowEnd = date
        memory.consecutiveFailures = pointerMoved ? 0 : memory.consecutiveFailures + 1
    }

    // MARK: - Tick

    public mutating func tick(_ input: EngineInput) -> EngineOutput {
        var effects: [EngineEffect] = []
        let now = input.now
        let settings = input.settings

        // 1. 真实输入 vs 合成输入
        updateRealInput(observed: now.addingTimeInterval(-max(0, input.systemIdleSeconds)), now: now)
        let realIdle = max(0, now.timeIntervalSince(memory.lastRealInputAt ?? now))

        // 2. 手动暂停到期
        var manualPause = input.manualPause
        if let until = manualPause?.until, until <= now {
            effects.append(.clearManualPause)
            manualPause = nil
        }

        // 3. 决定状态
        let status: EngineStatus
        var jiggleDue = false
        if !settings.isEnabled {
            status = .off
        } else if !input.isAccessibilityTrusted {
            status = .blocked(.accessibilityPermission)
        } else if let pause = manualPause {
            status = .paused(.manual(until: pause.until))
        } else if let reason = Self.rulePauseReason(settings: settings, environment: input.environment, now: now, calendar: input.calendar) {
            status = .paused(reason)
        } else if realIdle < settings.idleThresholdSeconds {
            status = .watching(idleSeconds: realIdle, remainingSeconds: settings.idleThresholdSeconds - realIdle)
        } else {
            if !input.isJiggleInProgress, shouldJiggle(now: now, interval: settings.jiggleIntervalSeconds) {
                jiggleDue = true
                memory.lastJiggleStartedAt = now
                memory.jiggleCount += 1
            }
            let next = memory.lastJiggleStartedAt.map { max(0, settings.jiggleIntervalSeconds - now.timeIntervalSince($0)) } ?? 0
            status = .active(idleSeconds: realIdle, jiggleCount: memory.jiggleCount, nextJiggleInSeconds: next)
        }

        if status.kind != .active {
            memory.lastJiggleStartedAt = nil
            memory.jiggleCount = 0
        }

        // 4. 移动：到点的自动移动与用户请求的立即移动合并为一次，并打开合成事件窗口。
        if jiggleDue || memory.jiggleRequested, !input.isJiggleInProgress {
            effects.append(.performJiggle(settings.movement, sequence: memory.sequence))
            memory.sequence += 1
            memory.syntheticWindowStart = now
            memory.syntheticWindowEnd = nil
        }
        memory.jiggleRequested = false

        // 5. 警告
        let failures = memory.consecutiveFailures
        let warnings: [EngineWarning] = failures >= Self.failureWarningThreshold ? [.pointerDidNotMove(failures: failures)] : []

        return EngineOutput(
            status: status,
            effects: effects,
            warnings: warnings,
            // 电源断言：仅在工作中（watching / active）持有用户开启的那些。
            powerAssertions: status.isRunning ? settings.keepAwake : .none,
            realIdleSeconds: realIdle
        )
    }

    // MARK: - 内部逻辑

    private mutating func updateRealInput(observed: Date, now: Date) {
        guard let current = memory.lastRealInputAt else {
            memory.lastRealInputAt = observed
            return
        }
        guard observed > current else { return }
        if let start = memory.syntheticWindowStart {
            let end = memory.syntheticWindowEnd ?? now
            let lower = start.addingTimeInterval(-Self.syntheticTolerance)
            let upper = end.addingTimeInterval(Self.syntheticTolerance)
            if observed >= lower, observed <= upper { return } // 这是我们自己的事件
        }
        memory.lastRealInputAt = observed
    }

    private func shouldJiggle(now: Date, interval: TimeInterval) -> Bool {
        guard let last = memory.lastJiggleStartedAt else { return true }
        return now.timeIntervalSince(last) >= interval
    }

    /// 规则优先级：锁屏 > 电池 > 计划表 > 应用 > 其他应用阻止休眠。
    static func rulePauseReason(settings: Settings, environment: EnvironmentSnapshot, now: Date, calendar: Calendar) -> PauseReason? {
        let rules = settings.rules
        if rules.pauseWhenScreenLocked, environment.isScreenLocked { return .screenLocked }
        if rules.pauseOnBattery, environment.isOnBattery { return .onBattery }
        if settings.schedule.isEnabled, !settings.schedule.isActive(at: now, calendar: calendar) {
            return .outsideSchedule(resumesAt: settings.schedule.nextActiveDate(after: now, calendar: calendar))
        }
        if let rule = rules.matchingAppRule(in: environment) { return .app(rule) }
        if rules.pauseWhenOtherAppPreventsDisplaySleep, environment.otherAppPreventsDisplaySleep { return .otherAppPreventsDisplaySleep }
        return nil
    }
}
