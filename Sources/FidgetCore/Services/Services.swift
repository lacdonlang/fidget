import Foundation

/// 系统闲置时间来源。
public protocol IdleTimeProviding: Sendable {
    /// 距上次任意 HID 事件的秒数。
    func secondsSinceLastInput() -> TimeInterval
}

/// 电源断言控制。`apply` 必须是幂等的：驱动层每个 tick 都会调用。
@MainActor
public protocol PowerAssertionControlling: AnyObject {
    var current: PowerAssertionState { get }
    func apply(_ state: PowerAssertionState)
}

/// 环境快照采集。昂贵的采集项（运行中的进程列表、其他进程的断言列表）按需开启。
@MainActor
public protocol EnvironmentProviding: AnyObject {
    func snapshot(needsRunningApps: Bool, needsDisplaySleepProbe: Bool) -> EnvironmentSnapshot
}

/// 辅助功能权限。
@MainActor
public protocol AccessibilityPermissionChecking: AnyObject {
    func isTrusted() -> Bool
    /// 弹出系统授权提示（会把应用加入列表）。
    func requestPermission()
    /// 打开系统设置中的辅助功能页面。
    func openSystemSettings()
    /// 删掉系统里的授权记录再重新申请。记录来自签名不同的旧版本时，列表里的开关看似打开，系统却不认。
    func resetPermission() async
}

/// 单个值（设置、统计）的持久化存储。
public protocol ValueStore<Value>: Sendable {
    associatedtype Value: Sendable
    func load() throws -> Value
    func save(_ value: Value) throws
}
