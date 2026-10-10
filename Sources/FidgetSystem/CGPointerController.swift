import AppKit
import CoreGraphics
import FidgetCore

/// 用 CoreGraphics 事件投递移动指针。坐标系与 CGDisplayBounds 一致（主屏左上角为原点，y 向下）。
///
/// 投递到 HID 事件层的合成事件会真正移动光标并重置系统闲置计时，这正是让 Slack 之类的应用认为
/// “用户仍在操作”的关键；代价是进程必须获得辅助功能权限，否则事件会被系统静默丢弃。
@MainActor
public final class CGPointerController: PointerControlling {
    public init() {}

    public func currentPosition() -> CGPoint {
        if let location = CGEvent(source: nil)?.location { return location }
        // 兜底：把 AppKit 的坐标翻转到 CG 坐标系。
        let p = NSEvent.mouseLocation
        let height = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: p.x, y: height - p.y)
    }

    public func move(to point: CGPoint) {
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }

    public func displayBounds(containing point: CGPoint) -> CGRect {
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        let result = CGGetDisplaysWithPoint(point, UInt32(displays.count), &displays, &count)
        if result == .success, count > 0 {
            return CGDisplayBounds(displays[0])
        }
        return CGDisplayBounds(CGMainDisplayID())
    }
}
