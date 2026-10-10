import Foundation

/// 加锁保护的可变值，用法同 `OSAllocatedUnfairLock`（那个需要 macOS 13，这里要支持到 macOS 11）。
public final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    public init(_ value: Value) {
        self.value = value
    }

    public func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try body(&value)
    }
}
