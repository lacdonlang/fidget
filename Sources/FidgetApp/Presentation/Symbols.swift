import AppKit
import FidgetCore

/// SF Symbols 的名字。界面里用到的符号原则上都要在 macOS 11 就存在（`SymbolAvailabilityTests` 逐个检查），
/// 少数更新的符号在这里登记 macOS 11 上就有的替代品，经 `Symbols.name(_:)` 取名字时在旧系统上自动换掉。
/// 菜单栏图标如果取到不存在的符号会变成空白，所以这件事不能只靠肉眼检查。
enum Symbols {
    static let fallbacks: [String: String] = [
        "cursorarrow.slash": "cursorarrow", // macOS 14
        "computermouse": "cursorarrow", // macOS 12
        "computermouse.fill": "cursorarrow.motionlines", // macOS 12
        "circle.dotted": "circle.dashed", // macOS 12
        "app.dashed": "app", // macOS 12
    ]

    private static let availability = Locked<[String: Bool]>([:])

    /// 当前系统里有没有这个符号（结果缓存）。
    static func isAvailable(_ name: String) -> Bool {
        if let known = availability.withLock({ $0[name] }) { return known }
        let available = NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
        availability.withLock { $0[name] = available }
        return available
    }

    /// 实际使用的符号名：当前系统缺少时换成登记的替代品。
    static func name(_ preferred: String, isAvailable: (String) -> Bool = Symbols.isAvailable) -> String {
        guard let fallback = fallbacks[preferred], !isAvailable(preferred) else { return preferred }
        return fallback
    }
}

extension MenuBarIconStyle {
    /// 当前系统能原样显示的图标样式（例如鼠标图标需要 macOS 12），设置界面只列出这些。
    static var available: [MenuBarIconStyle] { allCases.filter(\.isAvailable) }

    var isAvailable: Bool { Symbols.isAvailable(StatusPresentation.preferredSymbol(self, .active)) }
}
