import CoreGraphics
import Foundation

/// 一次移动的完整轨迹：按 `stepInterval`（秒）的节奏依次把指针移动到 `points` 中的每个点。
public struct MovementPath: Equatable, Sendable {
    /// 轨迹起点（可能因为靠近屏幕边缘而被微调过）。
    public var origin: CGPoint
    /// 绝对坐标序列，不包含起点本身。
    public var points: [CGPoint]
    public var stepInterval: TimeInterval

    public init(origin: CGPoint, points: [CGPoint], stepInterval: TimeInterval) {
        self.origin = origin
        self.points = points
        self.stepInterval = stepInterval
    }

    public var totalDuration: TimeInterval { stepInterval * Double(points.count) }
}

/// 可复现的伪随机数发生器（SplitMix64），用于测试与轨迹预览。
public struct SeededRandomNumberGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
