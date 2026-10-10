import FidgetCore
import FidgetSystem
import Foundation

/// 把纯逻辑引擎接到真实世界：每秒采样一次输入、执行副作用、更新模型与统计。
@MainActor
final class EngineDriver {
    let model: AppModel
    let services: AppServices
    private let mover: PointerMover

    private var engine = Engine()
    private var timer: Timer?
    private var rng = SystemRandomNumberGenerator()
    private var lastTickAt: Date?
    private var lastStatusKind: EngineStatus.Kind?
    private var tickScheduled = false
    private static let tickInterval: TimeInterval = 1

    init(model: AppModel, services: AppServices, sleep: @escaping PointerMover.Sleeper = PointerMover.taskSleep) {
        self.model = model
        self.services = services
        mover = PointerMover(controller: services.pointer, sleep: sleep, now: services.now)
    }

    // MARK: - 生命周期

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = Self.tickInterval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        services.power.apply(.none)
        model.live.diagnostics.assertions = .none
    }

    // MARK: - 用户动作

    func setEnabled(_ enabled: Bool) {
        guard model.settings.isEnabled != enabled else { return }
        model.settings.isEnabled = enabled
        Log.shared.info(enabled ? "用户启用" : "用户停用", category: .engine)
        tick()
    }

    func pause(_ preset: PausePreset) {
        pause(until: preset.until(from: services.now(), calendar: .current), label: preset.rawValue)
    }

    /// `minutes` 为 nil 表示无限期暂停。
    func pause(minutes: Int?) {
        pause(until: minutes.map { services.now().addingTimeInterval(Double($0) * 60) }, label: minutes.map { "\($0) min" } ?? "indefinite")
    }

    private func pause(until: Date?, label: String) {
        model.manualPause = ManualPause(until: until)
        Log.shared.info("手动暂停: \(label)", category: .engine)
        tick()
    }

    func resume() {
        guard model.manualPause != nil else { return }
        model.manualPause = nil
        Log.shared.info("手动恢复", category: .engine)
        tick()
    }

    func toggle() {
        if model.manualPause != nil {
            resume()
        } else {
            setEnabled(!model.settings.isEnabled)
        }
    }

    /// 立即执行一次移动（无视状态），用于测试权限与手感。
    func moveNow() {
        engine.requestJiggle()
        tick()
    }

    /// 设置变更后尽快重新评估；同一轮 run loop 内的多次变更（例如拖动滑杆）合并为一次。
    func setNeedsTick() {
        guard !tickScheduled else { return }
        tickScheduled = true
        Task { [weak self] in
            guard let self else { return }
            tickScheduled = false
            tick()
        }
    }

    // MARK: - Tick

    func tick() {
        let now = services.now()
        let settings = model.settings
        let trusted = services.accessibility.isTrusted()
        update(model, \.isAccessibilityTrusted, trusted)

        let environment = services.environment.snapshot(
            needsRunningApps: !settings.rules.appRules.isEmpty && settings.rules.appRuleMode == .running,
            needsDisplaySleepProbe: settings.rules.pauseWhenOtherAppPreventsDisplaySleep
        )
        let systemIdle = services.idleTime.secondsSinceLastInput()
        let output = engine.tick(EngineInput(
            now: now,
            settings: settings,
            systemIdleSeconds: systemIdle,
            isAccessibilityTrusted: trusted,
            environment: environment,
            manualPause: model.manualPause,
            isJiggleInProgress: mover.isMoving,
            calendar: .current
        ))
        apply(output)

        var statistics = model.live.statistics
        if let last = lastTickAt, output.status.isRunning {
            statistics.accumulateRunning(seconds: now.timeIntervalSince(last))
        }
        statistics.rollOverIfNeeded(now: now, calendar: .current)
        update(model.live, \.statistics, statistics)
        lastTickAt = now

        update(model.live, \.diagnostics, LiveState.Diagnostics(
            systemIdleSeconds: systemIdle,
            realIdleSeconds: output.realIdleSeconds,
            environment: environment,
            assertions: services.power.current,
            engineMemory: engine.memory
        ))
    }

    /// 只在值真的变化时写入模型。`@Published` 每次赋值都会通知订阅者（哪怕值相同），
    /// 而每秒的 tick 大多不改变状态，这样界面不会被无谓地通知重算。
    private func update<Root: AnyObject, Value: Equatable>(_ root: Root, _ keyPath: ReferenceWritableKeyPath<Root, Value>, _ value: Value) {
        if root[keyPath: keyPath] != value { root[keyPath: keyPath] = value }
    }

    private func apply(_ output: EngineOutput) {
        if output.status.kind != lastStatusKind {
            Log.shared.info("状态: \(lastStatusKind.map { "\($0)" } ?? "nil") → \(output.status.kind)", category: .engine)
            lastStatusKind = output.status.kind
        }
        update(model.live, \.status, output.status)
        update(model, \.warnings, output.warnings)
        services.power.apply(output.powerAssertions)
        for effect in output.effects {
            switch effect {
            case let .performJiggle(movement, sequence):
                startJiggle(movement, sequence: sequence)
            case .clearManualPause:
                model.manualPause = nil
                Log.shared.info("定时暂停到期，自动恢复", category: .engine)
            }
        }
    }

    private func startJiggle(_ movement: MovementSettings, sequence: Int) {
        let path = mover.makePath(settings: movement, sequence: sequence, rng: &rng)
        let verify = model.settings.advanced.verifyPointerMovement
        Task { [weak self] in
            guard let self else { return }
            let result = await mover.perform(path: path, verify: verify)
            engine.noteJiggleFinished(at: result.endedAt, pointerMoved: result.pointerMoved)
            model.lastJiggle = result
            if result.pointerMoved {
                model.live.statistics.recordJiggle(at: result.endedAt, calendar: .current)
                Log.shared.debug("移动完成: \(movement.pattern.rawValue) \(path.points.count) 步, 起点 \(path.origin)", category: .engine)
            } else {
                Log.shared.error("指针没有移动（连续 \(engine.memory.consecutiveFailures) 次），请检查辅助功能权限", category: .engine)
            }
        }
    }
}
