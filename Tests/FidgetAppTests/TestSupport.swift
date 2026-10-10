import CoreGraphics
import Foundation
@testable import FidgetApp
@testable import FidgetCore
@testable import FidgetSystem

/// 可手动推进的时钟。
final class FakeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var _now: Date
    init(_ now: Date = Date(timeIntervalSince1970: 1_800_000_000)) { _now = now }
    var now: Date { lock.withLock { _now } }
    func advance(_ seconds: TimeInterval) { lock.withLock { _now = _now.addingTimeInterval(seconds) } }
}

final class FakeIdleTime: IdleTimeProviding, @unchecked Sendable {
    var seconds: TimeInterval = 0
    func secondsSinceLastInput() -> TimeInterval { seconds }
}

@MainActor
final class FakePointer: PointerControlling {
    var position = CGPoint(x: 400, y: 300)
    var moves: [CGPoint] = []
    var honorsMoves = true
    func currentPosition() -> CGPoint { position }
    func move(to point: CGPoint) {
        moves.append(point)
        if honorsMoves { position = point }
    }
    func displayBounds(containing point: CGPoint) -> CGRect { CGRect(x: 0, y: 0, width: 1440, height: 900) }
}

/// 内存版存储。
final class InMemoryStore<Value: Sendable>: ValueStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) { self.value = value }

    func load() throws -> Value { lock.withLock { value } }
    func save(_ value: Value) throws { lock.withLock { self.value = value } }
}

@MainActor
final class FakePower: PowerAssertionControlling {
    var current = PowerAssertionState.none
    var history: [PowerAssertionState] = []
    func apply(_ state: PowerAssertionState) { current = state; history.append(state) }
}

@MainActor
final class FakeEnvironment: EnvironmentProviding {
    var snapshot = EnvironmentSnapshot()
    var requests: [(apps: Bool, probe: Bool)] = []
    func snapshot(needsRunningApps: Bool, needsDisplaySleepProbe: Bool) -> EnvironmentSnapshot {
        requests.append((needsRunningApps, needsDisplaySleepProbe))
        return snapshot
    }
}

@MainActor
final class FakeAccessibility: AccessibilityPermissionChecking {
    var trusted: Bool
    var promptCount = 0
    init(trusted: Bool) { self.trusted = trusted }
    func isTrusted() -> Bool { trusted }
    func requestPermission() { promptCount += 1 }
    func openSystemSettings() {}
    func resetPermission() async {}
}

/// 把假服务装配成驱动，返回所有可操控的句柄。
@MainActor
struct DriverHarness {
    let clock = FakeClock()
    let idle = FakeIdleTime()
    let pointer = FakePointer()
    let power = FakePower()
    let environment = FakeEnvironment()
    let accessibility: FakeAccessibility
    let model: AppModel
    let driver: EngineDriver

    init(settings: FidgetCore.Settings = .default, trusted: Bool = true) {
        accessibility = FakeAccessibility(trusted: trusted)
        model = AppModel(settings: settings)
        let clock = clock
        let services = AppServices(
            idleTime: idle, pointer: pointer, power: power, environment: environment, accessibility: accessibility,
            settingsStore: InMemoryStore(settings), statisticsStore: InMemoryStore(Statistics()),
            now: { clock.now }
        )
        driver = EngineDriver(model: model, services: services, sleep: { _ in })
    }

    /// 推进时间并上报系统闲置秒数，然后 tick；随后让异步移动任务跑完。
    func step(advance: TimeInterval, systemIdle: TimeInterval) async {
        clock.advance(advance)
        idle.seconds = systemIdle
        driver.tick()
        await settle()
    }

    func settle() async {
        for _ in 0 ..< 20 { await Task.yield() }
    }
}

enum PackagePaths {
    static var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
}
