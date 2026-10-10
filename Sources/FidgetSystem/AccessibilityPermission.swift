import AppKit
import ApplicationServices
import FidgetCore

/// 辅助功能权限。投递合成鼠标事件必须获得该权限。
@MainActor
public final class AccessibilityPermission: AccessibilityPermissionChecking {
    public init() {}

    public func isTrusted() -> Bool { AXIsProcessTrusted() }

    public func requestPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// 系统按授权时那个版本的签名认人。记录如果来自签名不同的版本（例如先装过本地构建），列表里的开关开着，
    /// 系统却不认当前版本，关掉再打开也没用；只有删掉记录、重新申请（列表里出现新的条目）才能恢复。
    public func resetPermission() async {
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            let arguments = ["reset", "Accessibility", bundleIdentifier]
            let status = await Task.detached { () -> Int32 in
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
                process.arguments = arguments
                do { try process.run() } catch { return -1 }
                process.waitUntilExit()
                return process.terminationStatus
            }.value
            if status == 0 {
                Log.shared.info("已删除辅助功能授权记录，重新申请", category: .system)
            } else {
                Log.shared.error("删除辅助功能授权记录失败（tccutil 退出码 \(status)）", category: .system)
            }
        }
        requestPermission()
    }

    public func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
