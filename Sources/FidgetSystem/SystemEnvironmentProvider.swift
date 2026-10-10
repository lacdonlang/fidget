import AppKit
import FidgetCore
import Foundation

/// 汇总各系统探针，生成引擎需要的环境快照。昂贵的查询带 5 秒缓存。
@MainActor
public final class SystemEnvironmentProvider: EnvironmentProviding {
    public let screenState: ScreenStateMonitor
    private let powerSource = PowerSourceProbe()
    private let assertionProbe = DisplaySleepAssertionProbe()
    private static let cacheInterval: TimeInterval = 5
    private var batteryCache: (at: Date, value: Bool)?
    private var holdersCache: (at: Date, value: [String])?
    private var runningAppsCache: (at: Date, value: Set<String>)?

    public init(screenState: ScreenStateMonitor = ScreenStateMonitor()) {
        self.screenState = screenState
    }

    public func snapshot(needsRunningApps: Bool, needsDisplaySleepProbe: Bool) -> EnvironmentSnapshot {
        var snapshot = EnvironmentSnapshot()
        snapshot.isScreenLocked = screenState.isConsideredLocked
        snapshot.isOnBattery = cached(&batteryCache) { powerSource.isOnBattery() }
        if needsDisplaySleepProbe {
            snapshot.displaySleepHolders = cached(&holdersCache) {
                assertionProbe.holders(excludingPID: ProcessInfo.processInfo.processIdentifier).map(\.description)
            }
        }
        if needsRunningApps {
            snapshot.runningBundleIdentifiers = cached(&runningAppsCache) {
                Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
            }
        }
        snapshot.frontmostBundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier // 很便宜，总是采集
        return snapshot
    }

    private func cached<Value>(_ cache: inout (at: Date, value: Value)?, _ compute: () -> Value) -> Value {
        let now = Date()
        if let cache, now.timeIntervalSince(cache.at) < Self.cacheInterval { return cache.value }
        let value = compute()
        cache = (now, value)
        return value
    }
}

/// 可供用户加入规则列表的运行中应用。
public struct RunningApp: Identifiable, Hashable, Sendable {
    public var bundleIdentifier: String
    public var name: String
    public var id: String { bundleIdentifier }
}

@MainActor
public enum RunningApps {
    /// 普通（有 Dock 图标的）应用，按名称排序。
    public static func regularApps() -> [RunningApp] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let id = app.bundleIdentifier, let name = app.localizedName else { return nil }
                return RunningApp(bundleIdentifier: id, name: name)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// 从 .app 路径读取 bundle id 与名称。
    public static func app(at url: URL) -> RunningApp? {
        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return nil }
        let name = (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
            ?? (bundle.infoDictionary?["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return RunningApp(bundleIdentifier: id, name: name)
    }

    private static var iconCache: [String: NSImage] = [:]

    /// 应用图标（LaunchServices 查询与图标加载结果按 bundle id 缓存，避免每次界面刷新都重复查询）。
    public static func icon(forBundleIdentifier id: String) -> NSImage? {
        if let icon = iconCache[id] { return icon }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        iconCache[id] = icon
        return icon
    }
}
