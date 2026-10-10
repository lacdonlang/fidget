import AppKit
import FidgetCore
import SwiftUI

// 菜单栏弹出面板用的小部件。面板跟随系统的浅色 / 深色外观，所以这里只用系统语义色；
// 设置、引导与关于窗口固定为深色，用的是 Aurora.swift 里的另一套组件。
// 只用 macOS 11 就有的 SwiftUI API。更新的 API（ShapeStyle 层级色、`background(_:in:)`、Canvas、TimelineView 等）
// 用等价的旧写法实现，所有系统版本走同一条代码路径、外观一致。

/// 面板配色。都取自系统的语义色，自动适配浅色 / 深色模式。
enum Palette {
    /// 卡片、进度条底色等低对比度填充。
    static let fill = Color(NSColor.quaternaryLabelColor)
    static let windowBackground = Color(NSColor.windowBackgroundColor)
}

extension EngineStatus.Kind {
    var color: Color {
        switch self {
        case .active: .green
        case .watching: .blue
        case .paused: .orange
        case .blocked: .red
        case .off: .secondary
        }
    }
}

extension View {
    /// 强调按钮：macOS 12 起用填充样式；macOS 11 没有该样式，保持普通按钮。
    @ViewBuilder
    func prominentButtonStyle() -> some View {
        if #available(macOS 12, *) {
            buttonStyle(.borderedProminent)
        } else {
            self
        }
    }
}

/// 带彩色圆点的状态胶囊。
struct StatusBadge: View {
    let kind: EngineStatus.Kind
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(kind.color).frame(width: 8, height: 8)
            Text(title).font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(kind.color.opacity(0.14)))
        .foregroundColor(kind.color)
    }
}

/// 圆角卡片容器。
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.fill.opacity(0.55)))
    }
}

/// 弹出面板里的小统计块。
struct StatTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(Font.title3.weight(.semibold).monospacedDigit())
            Text(title).font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 简单的进度条，表示闲置时间逼近阈值（或距离下一次移动）的进度。
struct IdleProgressBar: View {
    let progress: Double
    let kind: EngineStatus.Kind

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.fill)
                Capsule().fill(kind.color).frame(width: max(4, geo.size.width * (0 ... 1).clamping(progress)))
            }
        }
        .frame(height: 5)
        .animation(.linear(duration: 0.5), value: progress)
    }
}

/// 权限/警告横幅。
struct Banner: View {
    enum Kind { case warning, error }
    let kind: Kind
    let text: String
    var primary: (title: String, action: () -> Void)?
    var secondary: (title: String, action: () -> Void)?
    /// 按钮下方的小号链接，放不常用的补救操作。
    var footnote: (title: String, action: () -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: kind == .error ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill")
                    .foregroundColor(tint)
                Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
            }
            if primary != nil || secondary != nil {
                HStack {
                    if let primary { Button(primary.title, action: primary.action).prominentButtonStyle().controlSize(.small) }
                    if let secondary { Button(secondary.title, action: secondary.action).controlSize(.small) }
                }
            }
            if let footnote {
                Button(footnote.title, action: footnote.action).buttonStyle(LinkButtonStyle()).font(.caption)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.12)))
    }

    private var tint: Color { kind == .error ? .red : .orange }
}
