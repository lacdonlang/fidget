import CoreGraphics
import Foundation

/// 指针控制抽象。系统层用 CoreGraphics 实现；测试用内存实现。
@MainActor
public protocol PointerControlling: AnyObject {
    func currentPosition() -> CGPoint
    /// 把指针移动到指定位置。是否真的移动了由调用方读回位置判断。
    func move(to point: CGPoint)
    /// 包含指定点的显示器边界；未知时返回 `.zero`。
    func displayBounds(containing point: CGPoint) -> CGRect
}

/// 一次移动的执行结果。
public struct JiggleResult: Equatable, Sendable {
    public var startedAt: Date
    public var endedAt: Date
    /// 执行期间是否观察到指针位置发生过变化；为 false 通常意味着缺少辅助功能权限。
    public var pointerMoved: Bool
    public var path: MovementPath

    public init(startedAt: Date, endedAt: Date, pointerMoved: Bool, path: MovementPath) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.pointerMoved = pointerMoved
        self.path = path
    }
}

/// 按轨迹驱动指针的执行器；睡眠与时钟都可注入，测试可瞬时完成。
@MainActor
public final class PointerMover {
    /// 等待指定秒数。
    public typealias Sleeper = @Sendable (TimeInterval) async -> Void

    /// 默认的步进等待。
    public static let taskSleep: Sleeper = { try? await Task.sleep(nanoseconds: UInt64(max(0, $0) * 1_000_000_000)) }

    private let controller: PointerControlling
    private let sleep: Sleeper
    private let now: @Sendable () -> Date
    public private(set) var isMoving = false

    public init(
        controller: PointerControlling,
        sleep: @escaping Sleeper = PointerMover.taskSleep,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.controller = controller
        self.sleep = sleep
        self.now = now
    }

    /// 以指针当前位置为起点生成轨迹。
    public func makePath(settings: MovementSettings, sequence: Int, rng: inout some RandomNumberGenerator) -> MovementPath {
        let origin = controller.currentPosition()
        let bounds = controller.displayBounds(containing: origin)
        return MovementPathGenerator.makePath(settings: settings, origin: origin, bounds: bounds, sequence: sequence, rng: &rng)
    }

    public func perform(path: MovementPath, verify: Bool = true) async -> JiggleResult {
        isMoving = true
        defer { isMoving = false }
        let start = now()
        let before = controller.currentPosition()
        var moved = !verify
        for point in path.points {
            controller.move(to: point)
            await sleep(path.stepInterval)
            if !moved, controller.currentPosition() != before { moved = true }
        }
        return JiggleResult(startedAt: start, endedAt: now(), pointerMoved: moved, path: path)
    }
}
