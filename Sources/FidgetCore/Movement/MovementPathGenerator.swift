import CoreGraphics
import Foundation

/// 根据移动设置生成具体轨迹。纯函数，便于测试与界面预览。
public enum MovementPathGenerator {
    /// 轨迹采样率：每秒 60 个点，和显示刷新率匹配即可显得平滑。
    public static let samplesPerSecond = 60.0
    public static let minSteps = 2
    public static let maxSteps = 240

    /// - Parameters:
    ///   - origin: 指针当前位置。
    ///   - bounds: 指针所在显示器的边界；传入空矩形表示不限制。
    ///   - sequence: 本轮闲置期内的第几次移动，用于交替方向。
    public static func makePath(
        settings: MovementSettings,
        origin: CGPoint,
        bounds: CGRect,
        sequence: Int,
        rng: inout some RandomNumberGenerator
    ) -> MovementPath {
        let effective = settings.effective
        let amplitude = effective.amplitude
        let safeOrigin = safeOrigin(for: origin, amplitude: amplitude, in: bounds)

        var relative = unitWaypoints(for: effective.pattern, sequence: sequence, rng: &rng)
        if effective.returnToOrigin, let last = relative.last, last != .zero {
            relative.append(.zero)
        }

        let durationSeconds = Double(effective.durationMilliseconds) / 1000
        let steps = (minSteps ... maxSteps).clamping(Int((durationSeconds * samplesPerSecond).rounded()))
        let sampled = resample(polylineFromOrigin: relative, count: steps)
        let absolute = sampled.map { unit -> CGPoint in
            let p = CGPoint(x: safeOrigin.x + unit.x * amplitude, y: safeOrigin.y + unit.y * amplitude)
            return clamp(p, to: bounds.isEmpty ? nil : bounds.insetBy(dx: 1, dy: 1))
        }
        return MovementPath(origin: safeOrigin, points: absolute, stepInterval: durationSeconds / Double(steps))
    }

    // MARK: - 形状定义（单位空间，振幅为 1，起点为原点）

    static func unitWaypoints(for pattern: MovementPattern, sequence: Int, rng: inout some RandomNumberGenerator) -> [CGPoint] {
        switch pattern {
        case .nudge:
            let direction: CGFloat = sequence.isMultiple(of: 2) ? 1 : -1
            return [CGPoint(x: direction, y: 0)]
        case .square:
            // 边长取 1/√2，使对角顶点到原点的距离恰好为一个振幅。
            let s: CGFloat = (sequence.isMultiple(of: 2) ? 1 : -1) / CGFloat(2).squareRoot()
            return [CGPoint(x: s, y: 0), CGPoint(x: s, y: s), CGPoint(x: 0, y: s)]
        case .circle:
            // 圆心 (0.5, 0)，半径 0.5，从原点出发绕一圈回到原点；方向逐次交替。
            let sign: CGFloat = sequence.isMultiple(of: 2) ? 1 : -1
            let segments = 48
            return (1 ... segments).map { i in
                let theta = CGFloat.pi + 2 * CGFloat.pi * CGFloat(i) / CGFloat(segments)
                return CGPoint(x: 0.5 + 0.5 * cos(theta), y: sign * 0.5 * sin(theta))
            }
        case .figureEight:
            let segments = 64
            return (1 ... segments).map { i in
                let t = 2 * CGFloat.pi * CGFloat(i) / CGFloat(segments)
                return CGPoint(x: sin(t), y: 0.5 * sin(2 * t))
            }
        case .randomWalk:
            return (0 ..< 6).map { _ in
                // 极坐标均匀采样单位圆盘。
                let r = sqrt(Double.random(in: 0 ... 1, using: &rng))
                let angle = Double.random(in: 0 ..< 2 * Double.pi, using: &rng)
                return CGPoint(x: r * cos(angle), y: r * sin(angle))
            }
        }
    }

    // MARK: - 采样与几何工具

    /// 把从原点出发的折线按弧长均匀重采样为 `count` 个点（不含起点，含终点），并施加缓动使起止更柔和。
    static func resample(polylineFromOrigin waypoints: [CGPoint], count: Int) -> [CGPoint] {
        let vertices = [CGPoint.zero] + waypoints
        var cumulative: [CGFloat] = [0]
        for i in 1 ..< vertices.count {
            cumulative.append(cumulative[i - 1] + distance(vertices[i - 1], vertices[i]))
        }
        guard let total = cumulative.last, total > 0 else {
            return Array(repeating: .zero, count: count)
        }
        return (1 ... count).map { i in
            let t = smoothstep(CGFloat(i) / CGFloat(count))
            return point(alongPolyline: vertices, cumulative: cumulative, at: t * total)
        }
    }

    static func point(alongPolyline vertices: [CGPoint], cumulative: [CGFloat], at length: CGFloat) -> CGPoint {
        var index = 1
        while index < cumulative.count - 1, cumulative[index] < length { index += 1 }
        let segmentStart = cumulative[index - 1]
        let segmentLength = cumulative[index] - segmentStart
        let fraction = segmentLength > 0 ? (length - segmentStart) / segmentLength : 1
        let a = vertices[index - 1], b = vertices[index]
        return CGPoint(x: a.x + (b.x - a.x) * fraction, y: a.y + (b.y - a.y) * fraction)
    }

    static func smoothstep(_ t: CGFloat) -> CGFloat {
        let x = (0 ... 1).clamping(t)
        return x * x * (3 - 2 * x)
    }

    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    static func clamp(_ p: CGPoint, to rect: CGRect?) -> CGPoint {
        guard let rect, !rect.isNull, !rect.isEmpty else { return p }
        return CGPoint(x: (rect.minX ... rect.maxX).clamping(p.x), y: (rect.minY ... rect.maxY).clamping(p.y))
    }

    /// 起点距屏幕边缘不足一个振幅时向内收一点，避免轨迹反复触碰角落触发“触发角”。
    static func safeOrigin(for origin: CGPoint, amplitude: Double, in bounds: CGRect) -> CGPoint {
        guard !bounds.isEmpty else { return origin }
        let inset = CGFloat(amplitude) + 2
        let safe = bounds.insetBy(dx: inset, dy: inset)
        if safe.isNull || safe.width <= 0 || safe.height <= 0 {
            return CGPoint(x: bounds.midX, y: bounds.midY)
        }
        return clamp(origin, to: safe)
    }
}
