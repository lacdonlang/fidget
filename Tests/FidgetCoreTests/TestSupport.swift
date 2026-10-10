import Foundation
@testable import FidgetCore

/// 测试统一使用固定时区的公历，避免受机器本地设置影响。
enum Fixture {
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }()

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day
        comps.hour = hour; comps.minute = minute; comps.second = second
        return calendar.date(from: comps)!
    }

    /// 2026-10-12 是周一。
    static let monday = date(2026, 10, 12, 10, 0)
}

/// 内存版指针控制器：记录每次移动，可模拟“没有权限、指针不动”的情况。
@MainActor
final class FakePointerController: PointerControlling {
    var position: CGPoint
    var bounds: CGRect
    var moves: [CGPoint] = []
    var honorsMoves = true

    init(position: CGPoint = CGPoint(x: 500, y: 400), bounds: CGRect = CGRect(x: 0, y: 0, width: 1920, height: 1080)) {
        self.position = position
        self.bounds = bounds
    }

    func currentPosition() -> CGPoint { position }

    func move(to point: CGPoint) {
        moves.append(point)
        if honorsMoves { position = point }
    }

    func displayBounds(containing point: CGPoint) -> CGRect { bounds }
}
