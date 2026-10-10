import FidgetCore
import Foundation
import IOKit.ps
import IOKit.pwr_mgt

/// 通过 IOPMAssertion 阻止显示器/系统因闲置而休眠。
@MainActor
public final class IOPowerAssertionController: PowerAssertionControlling {
    public private(set) var current = PowerAssertionState.none
    private var displayAssertion: IOPMAssertionID = 0
    private var systemAssertion: IOPMAssertionID = 0

    public init() {}

    /// 幂等：只在与当前状态不同时创建或释放断言。
    public func apply(_ state: PowerAssertionState) {
        guard state != current else { return }
        Log.shared.info("电源断言: \(state)", category: .system)
        if state.preventDisplaySleep != current.preventDisplaySleep {
            toggle(&displayAssertion, on: state.preventDisplaySleep, type: kIOPMAssertionTypePreventUserIdleDisplaySleep, reason: "Fidget: keep display awake")
        }
        if state.preventSystemSleep != current.preventSystemSleep {
            toggle(&systemAssertion, on: state.preventSystemSleep, type: kIOPMAssertionTypePreventUserIdleSystemSleep, reason: "Fidget: keep system awake")
        }
        current = state
    }

    private func toggle(_ id: inout IOPMAssertionID, on: Bool, type: String, reason: String) {
        if on {
            guard id == 0 else { return }
            var newID: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), reason as CFString, &newID)
            if result == kIOReturnSuccess { id = newID } else { Log.shared.error("创建电源断言失败: \(type) (\(result))", category: .system) }
        } else {
            guard id != 0 else { return }
            IOPMAssertionRelease(id)
            id = 0
        }
    }
}

/// 读取当前供电来源。
public struct PowerSourceProbe: Sendable {
    public init() {}

    public func isOnBattery() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue()
        else { return false }
        return (type as String) == kIOPMBatteryPowerKey
    }
}

/// 检查是否有其他进程持有“阻止显示器休眠”断言——这通常意味着用户在看视频、演示或开会。
public struct DisplaySleepAssertionProbe: Sendable {
    public struct Holder: Equatable, Sendable, CustomStringConvertible {
        public var pid: Int
        public var name: String
        public var type: String

        /// 例如 "Playing video (PreventUserIdleDisplaySleep)"；没有断言名称时用 pid 代替。
        public var description: String { "\(name.isEmpty ? "pid \(pid)" : name) (\(type))" }
    }

    static let displayAssertionTypes: Set<String> = [kIOPMAssertionTypePreventUserIdleDisplaySleep, kIOPMAssertionTypeNoDisplaySleep]

    public init() {}

    /// 返回除 `excludingPID` 之外所有持有显示器断言的进程。
    public func holders(excludingPID: Int32) -> [Holder] {
        var raw: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&raw) == kIOReturnSuccess,
              let dict = raw?.takeRetainedValue() as? [AnyHashable: Any]
        else { return [] }
        var holders: [Holder] = []
        for (key, value) in dict {
            guard let pidNumber = key as? NSNumber, let assertions = value as? [[String: Any]] else { continue }
            let pid = pidNumber.intValue
            if pid == Int(excludingPID) { continue }
            for assertion in assertions {
                guard let type = assertion[kIOPMAssertionTypeKey as String] as? String, Self.displayAssertionTypes.contains(type) else { continue }
                if let level = assertion[kIOPMAssertionLevelKey as String] as? NSNumber, level.intValue != kIOPMAssertionLevelOn { continue }
                let name = (assertion[kIOPMAssertionNameKey as String] as? String) ?? ""
                holders.append(Holder(pid: pid, name: name, type: type))
            }
        }
        return holders.sorted { $0.pid < $1.pid }
    }
}
