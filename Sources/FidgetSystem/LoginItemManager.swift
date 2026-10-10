import Foundation
import ServiceManagement

/// 登录时启动。只有以 .app 形式运行时才可用。
/// - macOS 13+ 用 SMAppService，出现在“系统设置 → 通用 → 登录项”里，可能需要用户批准；
/// - macOS 11–12 没有 SMAppService，改为在 ~/Library/LaunchAgents 放一个登录时执行 `open -b <bundle id>` 的启动项。
@MainActor
public final class LoginItemManager {
    public enum Status: Equatable, Sendable {
        case enabled, disabled, requiresApproval, notFound, unavailable
    }

    private let launchAgent: LaunchAgentLoginItem?

    public init() {
        launchAgent = Bundle.main.bundleIdentifier.map { LaunchAgentLoginItem(bundleIdentifier: $0) }
    }

    public var isAvailable: Bool { launchAgent != nil && Bundle.main.isAppBundle }

    public var status: Status {
        guard isAvailable, let launchAgent else { return .unavailable }
        guard #available(macOS 13, *) else { return launchAgent.isEnabled ? .enabled : .disabled }
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .notRegistered: return .disabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        @unknown default: return .unavailable
        }
    }

    public func setEnabled(_ enabled: Bool) throws {
        guard isAvailable, let launchAgent else { return }
        guard #available(macOS 13, *) else { return try launchAgent.setEnabled(enabled) }
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    /// 在 macOS 12 上开启过登录启动、之后升级了系统：把旧启动项换成 SMAppService，避免开关显示“关”却仍在登录时启动。
    public func migrateLaunchAgentIfNeeded() {
        guard #available(macOS 13, *), isAvailable, let launchAgent, launchAgent.isEnabled else { return }
        do {
            try SMAppService.mainApp.register()
            try launchAgent.setEnabled(false)
            Log.shared.info("已把旧的登录启动项迁移到 SMAppService", category: .system)
        } catch {
            Log.shared.error("迁移登录启动项失败: \(error)", category: .system)
        }
    }

    /// 打开系统的登录项设置（只有 macOS 13+ 的“需要批准”状态会用到）。
    public func openSystemSettings() {
        if #available(macOS 13, *) { SMAppService.openSystemSettingsLoginItems() }
    }
}

/// macOS 11–12 的登录启动实现：用户级 LaunchAgent，登录时通过 LaunchServices 按 bundle id 打开应用，
/// 不依赖应用所在路径，用户移动 .app 后依然有效。
public struct LaunchAgentLoginItem: Sendable {
    public let bundleIdentifier: String
    public let plistURL: URL

    public init(
        bundleIdentifier: String,
        directory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
    ) {
        self.bundleIdentifier = bundleIdentifier
        plistURL = directory.appendingPathComponent("\(bundleIdentifier).login.plist")
    }

    public var label: String { "\(bundleIdentifier).login" }

    public var propertyList: [String: Any] {
        [
            "Label": label,
            "ProgramArguments": ["/usr/bin/open", "-b", bundleIdentifier],
            "RunAtLoad": true,
            "LimitLoadToSessionType": "Aqua",
        ]
    }

    public var isEnabled: Bool { FileManager.default.fileExists(atPath: plistURL.path) }

    public func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: propertyList, format: .xml, options: 0)
            try data.write(to: plistURL, options: .atomic)
        } else if isEnabled {
            try FileManager.default.removeItem(at: plistURL)
        }
    }
}
