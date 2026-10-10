import AppKit
import FidgetCore
import SwiftUI

// 设置、引导与关于窗口的视觉语言（参考 CleanMyMac）：随分区变色的淡淡光晕、半透明的“玻璃”卡片，
// 开关、滑杆、分段选择等控件自绘，用主题色渐变填充并带光晕。
// 有浅色和深色两套取值：下面的颜色都随外观变化（应用外观由设置里的“外观”决定，默认跟随系统）。
// 与 Components.swift 一样只用 macOS 11 就有的 SwiftUI API。

/// 窗口的基础配色。每个颜色都有浅色、深色两个取值，绘制时按视图所在的外观自动选用。
enum Aurora {
    static let base = Color.dynamic(light: NSColor(hex: 0xF7F7FA), dark: NSColor(hex: 0x17161D))
    static let baseDeep = Color.dynamic(light: NSColor(hex: 0xEDEDF2), dark: NSColor(hex: 0x0E0D12))
    /// 窗口自身的底色，与渐变上端一致：SwiftUI 内容铺满之前（打开、缩放窗口时）露出的就是它。
    static let windowBackground = NSColor.dynamic(light: NSColor(hex: 0xF7F7FA), dark: NSColor(hex: 0x17161D))

    static let text = Color.dynamic(light: NSColor(hex: 0x18171F).withAlphaComponent(0.92), dark: .white(0.94))
    static let secondaryText = Color.dynamic(light: .black(0.56), dark: .white(0.62))
    static let tertiaryText = Color.dynamic(light: .black(0.4), dark: .white(0.42))
    static let hairline = Color.dynamic(light: .black(0.08), dark: .white(0.08))
    static let glassStroke = Color.dynamic(light: .black(0.08), dark: .white(0.1))

    /// 卡片的填充与描边（上下两端）。浅色外观下是近乎不透明的白卡片加一点阴影，深色外观下是半透明的玻璃。
    static let cardTop = Color.dynamic(light: .white(0.9), dark: .white(0.075))
    static let cardBottom = Color.dynamic(light: .white(0.74), dark: .white(0.035))
    static let cardStrokeTop = Color.dynamic(light: .black(0.05), dark: .white(0.16))
    static let cardStrokeBottom = Color.dynamic(light: .black(0.09), dark: .white(0.05))
    static let cardShadow = Color.dynamic(light: .black(0.05), dark: .clear)

    /// 侧边栏压在窗口底色上的一层，以及其中选中项、悬停项的底色。
    static let sidebarTint = Color.dynamic(light: .black(0.035), dark: .black(0.24))
    static let selection = Color.dynamic(light: .white(0.95), dark: .white(0.1))
    static let hover = Color.dynamic(light: .black(0.04), dark: .white(0.05))

    /// 未选中的选项、分段选择的底槽等低对比度填充。
    static let fill = Color.dynamic(light: .black(0.045), dark: .white(0.07))
    /// 按钮、下拉菜单、时间输入框的底色及其悬停色。
    static let controlFill = Color.dynamic(light: .black(0.06), dark: .white(0.1))
    static let controlHover = Color.dynamic(light: .black(0.1), dark: .white(0.16))
    /// 关着的开关、滑杆未填充部分。
    static let track = Color.dynamic(light: .black(0.1), dark: .white(0.14))
    /// 轨迹预览画布与其中的点阵。
    static let inset = Color.dynamic(light: .black(0.035), dark: .black(0.28))
    static let dotGrid = Color.dynamic(light: .black(0.1), dark: .white(0.08))
    /// 引导页里未到达的步骤圆点。
    static let idle = Color.dynamic(light: .black(0.15), dark: .white(0.25))

    static let positive = Color.dynamic(light: NSColor(hex: 0x16A34A), dark: NSColor(hex: 0x4ADE80))
    static let negative = Color.dynamic(light: NSColor(hex: 0xE11D48), dark: NSColor(hex: 0xFB7185))
    static let caution = Color.dynamic(light: NSColor(hex: 0xD97706), dark: NSColor(hex: 0xFBBF24))
}

/// 一组主题色。图标底色、开关与滑杆的填充、选中态都用由浅到深的渐变，窗口光晕也取这两种颜色。
struct Theme: Hashable, Sendable {
    let lightHex: UInt32
    let deepHex: UInt32

    var light: Color { Color(hex: lightHex) }
    var deep: Color { Color(hex: deepHex) }
    var gradient: LinearGradient {
        LinearGradient(gradient: Gradient(colors: [light, deep]), startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// 小图标与强调色：深色外观取浅的一端，浅色外观取深的一端，两种底色上都看得清。
    var accent: Color { Color(nsAccent) }
    var nsAccent: NSColor { .dynamic(light: NSColor(hex: deepHex), dark: NSColor(hex: lightHex)) }
    /// 光晕（彩色阴影）的颜色。浅色外观下减半，否则白底上一片片彩色阴影显得脏。
    var glow: Color { .dynamic(light: NSColor(hex: deepHex).withAlphaComponent(0.5), dark: NSColor(hex: deepHex)) }
    /// 轨迹预览里移动的光点：深色底上用白色，浅色底上用主题色。
    var dot: Color { .dynamic(light: NSColor(hex: deepHex), dark: .white) }

    static let violet = Theme(lightHex: 0xC084FC, deepHex: 0x7C3AED)
    static let sky = Theme(lightHex: 0x38BDF8, deepHex: 0x2563EB)
    static let rose = Theme(lightHex: 0xF472B6, deepHex: 0xE11D48)
    static let emerald = Theme(lightHex: 0x34D399, deepHex: 0x059669)
    static let amber = Theme(lightHex: 0xFBBF24, deepHex: 0xEA580C)
    static let indigo = Theme(lightHex: 0x818CF8, deepHex: 0x4F46E5)
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme.violet
}

extension EnvironmentValues {
    /// 当前页面的主题色，自绘控件据此着色。
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: 1)
    }

    /// 随外观变化的颜色：深色外观用 `dark`，其余用 `light`。
    static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(NSColor.dynamic(light: light, dark: dark))
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    static func white(_ alpha: CGFloat) -> NSColor { NSColor(white: 1, alpha: alpha) }
    static func black(_ alpha: CGFloat) -> NSColor { NSColor(white: 0, alpha: alpha) }

    /// 随外观变化的颜色：深色外观用 `dark`，其余用 `light`。
    static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }
}

// MARK: - 背景与容器

/// 窗口背景：接近中性的底色，右上角一团淡淡的主题色光晕，左下角更淡的一团。
/// 光晕只是点缀，颜色交给图标与控件；调浓了整个窗口会显得艳俗，还会盖过卡片和文字。
struct AuroraBackground: View {
    var theme: Theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // 深色底上用深的一端才不刺眼；浅色底上用浅的一端，是一层淡淡的粉彩。
        let dark = colorScheme == .dark
        let main = dark ? theme.deep.opacity(0.26) : theme.light.opacity(0.18)
        let second = theme.light.opacity(dark ? 0.07 : 0.08)
        GeometryReader { geo in
            let radius = max(geo.size.width, geo.size.height)
            ZStack {
                LinearGradient(gradient: Gradient(colors: [Aurora.base, Aurora.baseDeep]), startPoint: .top, endPoint: .bottom)
                RadialGradient(gradient: Gradient(colors: [main, main.opacity(0)]),
                               center: UnitPoint(x: 0.88, y: -0.08), startRadius: 0, endRadius: radius * 0.7)
                RadialGradient(gradient: Gradient(colors: [second, second.opacity(0)]),
                               center: UnitPoint(x: 0.02, y: 1.04), startRadius: 0, endRadius: radius * 0.55)
            }
        }
        .edgesIgnoringSafeArea(.all)
    }
}

/// 玻璃卡片：深色外观下是半透明的白色填充、上沿稍亮的细描边；浅色外观下是白卡片加一点阴影。
private struct GlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color?

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return content
            .background(ZStack {
                shape
                    .fill(LinearGradient(gradient: Gradient(colors: [Aurora.cardTop, Aurora.cardBottom]), startPoint: .top, endPoint: .bottom))
                    .shadow(color: Aurora.cardShadow, radius: 10, y: 2)
                if let tint { shape.fill(tint.opacity(0.12)) }
            })
            .overlay(shape.strokeBorder(LinearGradient(gradient: Gradient(colors: [Aurora.cardStrokeTop, Aurora.cardStrokeBottom]), startPoint: .top, endPoint: .bottom), lineWidth: 1))
    }
}

extension View {
    /// 玻璃卡片背景；`tint` 给卡片叠一层淡淡的颜色（例如已开启的功能）。
    func glassCard(cornerRadius: CGFloat = 14, tint: Color? = nil) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius, tint: tint))
    }
}

/// 主题渐变底色的圆角方块图标（侧边栏、页头、引导页）。`glow` 时带同色光晕。
struct IconTile: View {
    let symbol: String
    let theme: Theme
    var size: CGFloat = 26
    var glow = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
        Image(systemName: symbol)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .background(ZStack {
                shape.fill(theme.gradient)
                // 上半部分的高光，让方块有一点立体感。
                shape.fill(LinearGradient(gradient: Gradient(colors: [Color.white.opacity(0.28), Color.white.opacity(0)]), startPoint: .top, endPoint: .center))
            })
            .overlay(shape.strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5))
            .shadow(color: theme.glow.opacity(glow ? 0.75 : 0.3), radius: glow ? size * 0.32 : 2, y: glow ? size * 0.08 : 1)
    }
}

/// 带图标的彩色小胶囊，表示“已授权 / 未授权”之类的状态。
struct StatusChip: View {
    let symbol: String
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 11, weight: .bold))
            Text(title).font(.system(size: 12, weight: .semibold))
        }
        .foregroundColor(color)
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(Capsule().fill(color.opacity(0.15)))
        .overlay(Capsule().strokeBorder(color.opacity(0.3)))
    }
}

// MARK: - 控件

/// 自绘开关：关时为半透明胶囊，开时填充主题渐变并发光。`title` 只用于无障碍描述。
struct GlowSwitch: View {
    let title: String
    @Binding var isOn: Bool
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: toggle) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(Aurora.track)
                Capsule().fill(theme.gradient).opacity(isOn ? 1 : 0)
                Capsule().strokeBorder(isOn ? Color.white.opacity(0.25) : Aurora.glassStroke, lineWidth: 1)
                Circle()
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.3), radius: 1.5, y: 1)
                    .padding(2.5)
            }
            .frame(width: 40, height: 23)
            .shadow(color: theme.glow.opacity(isOn ? 0.65 : 0), radius: 8)
            .contentShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(isOn ? L.t("common.on") : L.t("common.off")))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { toggle() }
    }

    private func toggle() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { isOn.toggle() }
    }
}

/// 自绘滑杆：主题渐变的轨道和发光的圆钮。`title`、`valueText` 用于无障碍描述。
struct GlowSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0 ... 1
    let title: String
    let valueText: String
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @State private var isDragging = false
    private let knob: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            let travel = max(1, geo.size.width - knob)
            let offset = travel * CGFloat(fraction)
            ZStack(alignment: .leading) {
                Capsule().fill(Aurora.track).frame(height: 4)
                Capsule()
                    .fill(theme.gradient)
                    .frame(width: offset + knob / 2, height: 4)
                    .shadow(color: theme.glow.opacity(0.8), radius: 4)
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().strokeBorder(Aurora.glassStroke))
                    .frame(width: knob, height: knob)
                    .shadow(color: theme.glow.opacity(isDragging ? 0.95 : 0.6), radius: isDragging ? 8 : 5)
                    .scaleEffect(isDragging ? 1.15 : 1)
                    .offset(x: offset)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard isEnabled else { return }
                        if !isDragging { withAnimation(.easeOut(duration: 0.15)) { isDragging = true } }
                        set(fraction: Double((drag.location.x - knob / 2) / travel))
                    }
                    .onEnded { _ in withAnimation(.easeOut(duration: 0.2)) { isDragging = false } }
            )
        }
        .frame(height: 22)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(valueText))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: set(fraction: fraction + 0.05)
            case .decrement: set(fraction: fraction - 0.05)
            @unknown default: break
            }
        }
    }

    private var fraction: Double {
        guard range.upperBound > range.lowerBound else { return 0 }
        return (0 ... 1).clamping((value - range.lowerBound) / (range.upperBound - range.lowerBound))
    }

    private func set(fraction: Double) {
        value = range.lowerBound + (0 ... 1).clamping(fraction) * (range.upperBound - range.lowerBound)
    }
}

/// 胶囊分段选择：选中项填充主题渐变，切换时滑动过去。`name` 用于悬停提示与无障碍描述。
struct PillPicker<Value: Hashable, Label: View>: View {
    let options: [Value]
    @Binding var selection: Value
    let name: (Value) -> String
    @ViewBuilder let label: (Value) -> Label
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selection = option }
                } label: {
                    label(option)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(selected ? .white : Aurora.secondaryText)
                        .padding(.horizontal, 12)
                        .frame(minWidth: 36, minHeight: 26)
                        .background(ZStack {
                            if selected {
                                Capsule()
                                    .fill(theme.gradient)
                                    .shadow(color: theme.glow.opacity(0.6), radius: 6)
                                    .matchedGeometryEffect(id: "selection", in: namespace)
                            }
                        })
                        .contentShape(Capsule())
                }
                .buttonStyle(PlainButtonStyle())
                .help(name(option))
                .accessibilityLabel(Text(name(option)))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(Aurora.fill))
        .overlay(Capsule().strokeBorder(Aurora.glassStroke))
        .opacity(isEnabled ? 1 : 0.4)
    }
}

/// 胶囊按钮。`primary` 填充主题渐变并发光，`secondary` 是半透明玻璃，`destructive` 用于恢复默认之类的操作。
/// `controlSize(.small)` 时变成小号。
struct GlassButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, destructive }
    var kind: Kind = .secondary

    func makeBody(configuration: Configuration) -> some View {
        GlassButton(configuration: configuration, kind: kind)
    }
}

private struct GlassButton: View {
    let configuration: ButtonStyleConfiguration
    let kind: GlassButtonStyle.Kind
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize
    @State private var isHovering = false

    var body: some View {
        let small = controlSize == .small || controlSize == .mini
        configuration.label
            .font(.system(size: small ? 11.5 : 13, weight: .semibold))
            .lineLimit(1)
            .foregroundColor(foreground)
            .padding(.horizontal, small ? 11 : 16)
            .frame(height: small ? 24 : 30)
            .background(background)
            .overlay(Capsule().strokeBorder(kind == .primary ? Color.white.opacity(0.25) : Aurora.glassStroke))
            .shadow(color: kind == .primary ? theme.glow.opacity(0.6) : .clear, radius: 10, y: 3)
            .brightness(configuration.isPressed ? -0.08 : 0)
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Capsule())
            .onHover { isHovering = $0 }
    }

    private var foreground: Color {
        switch kind {
        case .primary: .white
        case .secondary: Aurora.text
        case .destructive: Aurora.negative
        }
    }

    @ViewBuilder
    private var background: some View {
        switch kind {
        case .primary:
            Capsule().fill(theme.gradient).brightness(isHovering ? 0.06 : 0)
        case .secondary:
            Capsule().fill(isHovering ? Aurora.controlHover : Aurora.controlFill)
        case .destructive:
            Capsule().fill(Aurora.negative.opacity(isHovering ? 0.22 : 0.14))
        }
    }
}

/// 玻璃胶囊外观的下拉菜单。macOS 上菜单的标签由 AppKit 绘制，样式只能加在整个控件外面。
struct GlassMenu<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        Menu {
            content
        } label: {
            Text(title)
        }
        .menuStyle(BorderlessButtonMenuStyle())
        .fixedSize()
        .padding(.leading, 12)
        .padding(.trailing, 9)
        .frame(height: 28)
        .background(Capsule().fill(Aurora.controlFill))
        .overlay(Capsule().strokeBorder(Aurora.glassStroke))
    }
}
