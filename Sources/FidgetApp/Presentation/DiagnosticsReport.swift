import FidgetCore
import Foundation

/// 诊断信息文本，供“拷贝诊断信息”与问题反馈使用。
enum DiagnosticsReport {
    @MainActor
    static func text(model: AppModel) -> String {
        let d = model.live.diagnostics
        let s = model.settings
        var lines = [
            "Fidget \(AppInfo.version) (\(AppInfo.build)) bundled=\(AppInfo.isBundled)",
            "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "status: \(model.live.status)",
            "warnings: \(model.warnings)",
            "accessibility: \(model.isAccessibilityTrusted)",
            "loginItem: \(model.loginItemStatus)",
            "systemIdle: \(String(format: "%.1f", d.systemIdleSeconds)) realIdle: \(String(format: "%.1f", d.realIdleSeconds))",
            "environment: locked=\(d.environment.isScreenLocked) battery=\(d.environment.isOnBattery) front=\(d.environment.frontmostBundleIdentifier ?? "-")",
            "displaySleepHolders: \(d.environment.displaySleepHolders.joined(separator: ", "))",
            "assertions: \(d.assertions)",
            "engine: \(d.engineMemory)",
        ]
        if let last = model.lastJiggle {
            lines.append("lastJiggle: moved=\(last.pointerMoved) at=\(last.endedAt) steps=\(last.path.points.count)")
        }
        lines.append("settings: idle=\(s.idleThresholdSeconds)s interval=\(s.jiggleIntervalSeconds)s pattern=\(s.movement.pattern.rawValue) amplitude=\(s.movement.amplitude) invisible=\(s.movement.invisibleMode)")
        lines.append("rules: locked=\(s.rules.pauseWhenScreenLocked) battery=\(s.rules.pauseOnBattery) media=\(s.rules.pauseWhenOtherAppPreventsDisplaySleep) apps=\(s.rules.appRules.map(\.bundleIdentifier))")
        lines.append("schedule: enabled=\(s.schedule.isEnabled) days=\(s.schedule.activeDays.map(\.rawValue).sorted()) \(s.schedule.startMinute)-\(s.schedule.endMinute)")
        return lines.joined(separator: "\n")
    }
}
