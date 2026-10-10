import AppKit
import CoreGraphics
import Foundation

/// 跟踪锁屏、屏保与登录会话前后台状态。
@MainActor
public final class ScreenStateMonitor {
    public private(set) var isLocked: Bool
    public private(set) var isScreensaverActive = false
    public private(set) var isSessionActive = true
    public private(set) var isSystemAsleep = false

    /// 这几种状态下移动鼠标都没有意义。
    public var isConsideredLocked: Bool { isLocked || isScreensaverActive || !isSessionActive || isSystemAsleep }

    private var tokens: [NSObjectProtocol] = []

    public init() {
        isLocked = Self.queryScreenLocked()
        let dnc = DistributedNotificationCenter.default()
        observe(dnc, Notification.Name("com.apple.screenIsLocked")) { $0.isLocked = true }
        observe(dnc, Notification.Name("com.apple.screenIsUnlocked")) { $0.isLocked = false }
        observe(dnc, Notification.Name("com.apple.screensaver.didstart")) { $0.isScreensaverActive = true }
        observe(dnc, Notification.Name("com.apple.screensaver.didstop")) { $0.isScreensaverActive = false }
        let wnc = NSWorkspace.shared.notificationCenter
        observe(wnc, NSWorkspace.sessionDidResignActiveNotification) { $0.isSessionActive = false }
        observe(wnc, NSWorkspace.sessionDidBecomeActiveNotification) { $0.isSessionActive = true }
        observe(wnc, NSWorkspace.willSleepNotification) { $0.isSystemAsleep = true }
        observe(wnc, NSWorkspace.didWakeNotification) { monitor in
            monitor.isSystemAsleep = false
            monitor.isLocked = Self.queryScreenLocked() // 睡眠期间的锁屏通知可能丢失，唤醒后重新查询
        }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, handler: @escaping @MainActor (ScreenStateMonitor) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                handler(self)
            }
        }
        tokens.append(token)
    }

    static func queryScreenLocked() -> Bool {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        if let number = dict["CGSSessionScreenIsLocked"] as? NSNumber { return number.boolValue }
        return false
    }
}
