import Foundation

/// 通过 `fidget://` URL 或快捷键触发的命令，便于脚本与自动化集成。
public enum AppCommand: Equatable, Sendable {
    case enable
    case disable
    case toggle
    /// `minutes` 为 nil 表示无限期暂停。
    case pause(minutes: Int?)
    case resume
    case moveNow
    /// `section` 为设置分区的原始值（general / movement / schedule / rules / keepAwake / advanced）。
    case openSettings(section: String?)
    case openOnboarding
}

public enum AppCommandParser {
    public static let scheme = "fidget"

    /// 支持：fidget://enable | disable | toggle | pause[?minutes=30] | resume | move | settings[?section=movement] | setup
    public static func parse(_ url: URL) -> AppCommand? {
        guard url.scheme?.lowercased() == scheme, let host = url.host?.lowercased() else { return nil }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        switch host {
        case "enable", "start", "on": return .enable
        case "disable", "stop", "off": return .disable
        case "toggle": return .toggle
        case "pause":
            if let raw = query.first(where: { $0.name == "minutes" })?.value, let minutes = Int(raw), minutes > 0 {
                return .pause(minutes: minutes)
            }
            return .pause(minutes: nil)
        case "resume": return .resume
        case "move", "jiggle", "now": return .moveNow
        case "settings", "preferences":
            return .openSettings(section: query.first(where: { $0.name == "section" })?.value)
        case "setup", "onboarding", "welcome": return .openOnboarding
        default: return nil
        }
    }
}
