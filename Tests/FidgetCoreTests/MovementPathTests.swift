import CoreGraphics
import Foundation
import Testing
@testable import FidgetCore

@Suite("移动轨迹")
struct MovementPathTests {
    let origin = CGPoint(x: 500, y: 400)
    let bounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    func path(_ settings: MovementSettings, sequence: Int = 0, origin: CGPoint? = nil, bounds: CGRect? = nil, seed: UInt64 = 1) -> MovementPath {
        var rng = SeededRandomNumberGenerator(seed: seed)
        return MovementPathGenerator.makePath(settings: settings, origin: origin ?? self.origin, bounds: bounds ?? self.bounds, sequence: sequence, rng: &rng)
    }

    @Test("每种图案都生成非空轨迹且不超出振幅", arguments: MovementPattern.allCases)
    func withinAmplitude(pattern: MovementPattern) {
        let s = MovementSettings(pattern: pattern, amplitude: 20, durationMilliseconds: 500)
        let p = path(s)
        #expect(!p.points.isEmpty)
        for pt in p.points {
            let d = hypot(pt.x - p.origin.x, pt.y - p.origin.y)
            #expect(d <= 20 * 1.001, "pattern \(pattern) 超出振幅: \(d)")
        }
    }

    @Test("回到原点选项决定终点", arguments: MovementPattern.allCases)
    func returnToOrigin(pattern: MovementPattern) {
        let back = path(MovementSettings(pattern: pattern, amplitude: 10, returnToOrigin: true))
        #expect(back.points.last == back.origin)
        let stay = path(MovementSettings(pattern: pattern, amplitude: 10, returnToOrigin: false))
        // 圆和 8 字天然回到原点；其余图案应停在远离原点处。
        if pattern == .circle || pattern == .figureEight {
            #expect(stay.points.last == stay.origin)
        } else {
            #expect(stay.points.last != stay.origin)
        }
    }

    @Test("步数与时长匹配，并受上下限约束")
    func stepCount() {
        let short = path(MovementSettings(amplitude: 10, durationMilliseconds: 50))
        #expect(short.points.count >= MovementPathGenerator.minSteps)
        let normal = path(MovementSettings(amplitude: 10, durationMilliseconds: 1000))
        #expect(normal.points.count == 60)
        let long = path(MovementSettings(amplitude: 10, durationMilliseconds: 3000))
        #expect(long.points.count <= MovementPathGenerator.maxSteps)
        #expect(abs(normal.stepInterval - 1.0 / 60) < 1e-6)
    }

    @Test("隐形模式只有极少的点且距离 1 像素")
    func invisibleMode() {
        let p = path(MovementSettings(pattern: .circle, amplitude: 50, durationMilliseconds: 2000, invisibleMode: true))
        #expect(p.points.count <= 3)
        #expect(p.points.last == p.origin)
        let far = p.points.map { hypot($0.x - p.origin.x, $0.y - p.origin.y) }.max() ?? 0
        #expect(far <= 1.0001 && far > 0)
    }

    @Test("轻推方向逐次交替")
    func nudgeAlternates() {
        let a = path(MovementSettings(pattern: .nudge, amplitude: 10, returnToOrigin: false), sequence: 0)
        let b = path(MovementSettings(pattern: .nudge, amplitude: 10, returnToOrigin: false), sequence: 1)
        #expect(a.points.last!.x > origin.x)
        #expect(b.points.last!.x < origin.x)
    }

    @Test("随机游走在相同种子下可复现，不同种子下不同")
    func randomWalkDeterminism() {
        let s = MovementSettings(pattern: .randomWalk, amplitude: 30)
        #expect(path(s, seed: 7) == path(s, seed: 7))
        #expect(path(s, seed: 7) != path(s, seed: 8))
    }

    @Test("靠近屏幕角落时起点向内收，轨迹不越界")
    func cornerSafety() {
        let s = MovementSettings(pattern: .square, amplitude: 20, returnToOrigin: true)
        let p = path(s, origin: CGPoint(x: 0, y: 0))
        #expect(p.origin.x >= 20 && p.origin.y >= 20)
        for pt in p.points {
            #expect(bounds.insetBy(dx: 1, dy: 1).contains(pt) || bounds.insetBy(dx: 1, dy: 1).maxX == pt.x || bounds.insetBy(dx: 1, dy: 1).maxY == pt.y)
            #expect(pt.x >= 1 && pt.y >= 1 && pt.x <= 1919 && pt.y <= 1079)
        }
        let far = path(s, origin: CGPoint(x: 1920, y: 1080))
        #expect(far.origin.x <= 1900 && far.origin.y <= 1060)
    }

    @Test("未知显示器边界时不做裁剪")
    func noBoundsNoClamp() {
        let p = path(MovementSettings(pattern: .nudge, amplitude: 10), origin: CGPoint(x: 0, y: 0), bounds: .zero)
        #expect(p.origin == .zero)
    }

    @Test("总时长等于步数乘以步长")
    func totalDuration() {
        let p = path(MovementSettings(amplitude: 10, durationMilliseconds: 600))
        #expect(p.totalDuration == p.stepInterval * Double(p.points.count))
    }
}

@Suite("指针执行器")
@MainActor
struct PointerMoverTests {
    @Test("按轨迹逐点移动并报告指针动了")
    func performsAllSteps() async {
        let controller = FakePointerController()
        let mover = PointerMover(controller: controller, sleep: { _ in }, now: { Date(timeIntervalSince1970: 1000) })
        var rng = SeededRandomNumberGenerator(seed: 1)
        let path = mover.makePath(settings: MovementSettings(pattern: .nudge, amplitude: 10, durationMilliseconds: 200), sequence: 0, rng: &rng)
        let result = await mover.perform(path: path)
        #expect(controller.moves == path.points)
        #expect(result.pointerMoved)
        #expect(controller.position == path.origin)
        #expect(!mover.isMoving)
    }

    @Test("指针纹丝不动时报告失败")
    func reportsFailureWhenPointerStuck() async {
        let controller = FakePointerController()
        controller.honorsMoves = false
        let mover = PointerMover(controller: controller, sleep: { _ in })
        var rng = SeededRandomNumberGenerator(seed: 1)
        let path = mover.makePath(settings: MovementSettings(pattern: .circle, amplitude: 10), sequence: 0, rng: &rng)
        let result = await mover.perform(path: path)
        #expect(!result.pointerMoved)
        #expect(controller.moves.count == path.points.count)
    }

    @Test("关闭校验时总是视为成功")
    func noVerify() async {
        let controller = FakePointerController()
        controller.honorsMoves = false
        let mover = PointerMover(controller: controller, sleep: { _ in })
        var rng = SeededRandomNumberGenerator(seed: 1)
        let path = mover.makePath(settings: MovementSettings(), sequence: 0, rng: &rng)
        let result = await mover.perform(path: path, verify: false)
        #expect(result.pointerMoved)
    }
}
