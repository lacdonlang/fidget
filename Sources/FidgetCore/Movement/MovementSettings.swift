import Foundation

/// 移动轨迹的形状。
public enum MovementPattern: String, Codable, CaseIterable, Sendable, Identifiable {
    /// 水平轻推后回到原点，方向逐次交替。
    case nudge
    /// 以原点为起点画一个小圆。
    case circle
    /// 小正方形。
    case square
    /// 8 字形（李萨如曲线）。
    case figureEight
    /// 原点附近的随机游走。
    case randomWalk

    public var id: String { rawValue }
}

public struct MovementSettings: Codable, Equatable, Sendable {
    public var pattern: MovementPattern
    /// 离原点的最大距离（像素）。
    public var amplitude: Double
    /// 一次完整移动的总时长（毫秒）。
    public var durationMilliseconds: Int
    /// 移动结束后回到原点。
    public var returnToOrigin: Bool
    /// 隐形模式：1 像素、几乎瞬时、必定回到原点；肉眼不可察觉但足以重置系统闲置计时。
    public var invisibleMode: Bool

    public init(
        pattern: MovementPattern = .nudge,
        amplitude: Double = 8,
        durationMilliseconds: Int = 300,
        returnToOrigin: Bool = true,
        invisibleMode: Bool = false
    ) {
        self.pattern = pattern
        self.amplitude = amplitude
        self.durationMilliseconds = durationMilliseconds
        self.returnToOrigin = returnToOrigin
        self.invisibleMode = invisibleMode
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = MovementSettings()
        pattern = c.lenient(.pattern, default: d.pattern)
        amplitude = c.lenient(.amplitude, default: d.amplitude)
        durationMilliseconds = c.lenient(.durationMilliseconds, default: d.durationMilliseconds)
        returnToOrigin = c.lenient(.returnToOrigin, default: d.returnToOrigin)
        invisibleMode = c.lenient(.invisibleMode, default: d.invisibleMode)
    }

    public func validated() -> MovementSettings {
        var s = self
        s.amplitude = SettingsLimits.amplitude.clamping(amplitude.isFinite ? amplitude : MovementSettings().amplitude)
        s.durationMilliseconds = SettingsLimits.durationMilliseconds.clamping(durationMilliseconds)
        return s
    }

    /// 隐形模式会覆盖其他参数，这里给出真正用于生成轨迹的有效参数。
    public var effective: MovementSettings {
        guard invisibleMode else { return validated() }
        return MovementSettings(pattern: .nudge, amplitude: 1, durationMilliseconds: 50, returnToOrigin: true, invisibleMode: true)
    }
}
