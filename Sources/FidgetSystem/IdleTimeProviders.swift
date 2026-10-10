import CoreGraphics
import FidgetCore
import Foundation

/// 通过 CoreGraphics 读取当前登录会话距上次任意输入事件的秒数。
/// 合成事件（包括我们自己投递的）同样会重置该计时，所以核心层需要自行区分。
public struct CGIdleTimeProvider: IdleTimeProviding {
    public init() {}

    public func secondsSinceLastInput() -> TimeInterval {
        // ~0 即 kCGAnyInputEventType，表示任意输入事件。
        let anyInput = CGEventType(rawValue: ~0)!
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }
}
