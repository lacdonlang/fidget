import AppKit
import FidgetCore
import SwiftUI

// 设置页的布局与组合控件，外观见 Aurora.swift。

enum SettingsMetrics {
    /// 设置页里滑杆的统一宽度：各行标题长短不一，固定宽度才能上下对齐。
    static let sliderWidth: CGFloat = 170
    /// 滑杆右侧数值（或预设菜单）的最小宽度，让上下几行的滑杆对齐。
    static let valueWidth: CGFloat = 88
}

/// 设置页：页头（主题色图标、大标题、一句说明，右侧可放一个操作）+ 若干分组，可滚动。
/// 页面里的普通按钮默认是玻璃胶囊样式，自绘控件取本分区的主题色。
struct SettingsPage<Accessory: View, Content: View>: View {
    let section: SettingsSection
    let accessory: Accessory
    let content: Content

    init(_ section: SettingsSection, @ViewBuilder accessory: () -> Accessory, @ViewBuilder content: () -> Content) {
        self.section = section
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                content
            }
            .padding(.horizontal, 28)
            .padding(.top, 16)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // 内容滚到标题栏下沿时渐隐，而不是被生硬地切掉。
        .mask(VStack(spacing: 0) {
            LinearGradient(gradient: Gradient(colors: [Color.black.opacity(0), Color.black]), startPoint: .top, endPoint: .bottom).frame(height: 12)
            Color.black
        })
        .buttonStyle(GlassButtonStyle())
        .environment(\.theme, section.theme)
    }

    private var header: some View {
        HStack(spacing: 16) {
            IconTile(symbol: section.symbolName, theme: section.theme, size: 54, glow: true)
            VStack(alignment: .leading, spacing: 4) {
                Text(section.title)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(Aurora.text)
                Text(section.subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(Aurora.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            accessory
        }
        .padding(.bottom, 4)
    }
}

extension SettingsPage where Accessory == EmptyView {
    init(_ section: SettingsSection, @ViewBuilder content: () -> Content) {
        self.init(section, accessory: { EmptyView() }, content: content)
    }
}

/// 分组标题，右侧可放一个小按钮。
struct GroupHeader<Accessory: View>: View {
    let title: String
    let accessory: Accessory

    init(_ title: String, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Aurora.secondaryText)
            Spacer(minLength: 8)
            accessory.controlSize(.small)
        }
        .padding(.horizontal, 4)
    }
}

extension GroupHeader where Accessory == EmptyView {
    init(_ title: String) {
        self.init(title, accessory: { EmptyView() })
    }
}

/// 一组设置：可选的标题（右侧可带小按钮）、玻璃卡片、可选的脚注。卡片里的行之间用 `RowDivider` 分隔。
struct SettingsGroup<Accessory: View, Content: View>: View {
    var title: String?
    var footer: String?
    let accessory: Accessory
    let content: Content

    init(title: String? = nil, footer: String? = nil, @ViewBuilder accessory: () -> Accessory, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                GroupHeader(title) { accessory }
            }
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()
            if let footer {
                FootnoteText(footer).padding(.horizontal, 4)
            }
        }
    }
}

extension SettingsGroup where Accessory == EmptyView {
    init(title: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, footer: footer, accessory: { EmptyView() }, content: content)
    }
}

/// 分组下方或行内的小号说明文字。
struct FootnoteText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundColor(Aurora.tertiaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// 分组卡片里两行之间的分隔线。
struct RowDivider: View {
    var body: some View {
        Rectangle().fill(Aurora.hairline).frame(height: 1)
    }
}

/// 一行设置：左侧可选的主题色小图标、标题（可带一行说明），右侧控件。禁用时文字变暗，控件各自变暗。
struct SettingsRow<Control: View>: View {
    var symbol: String?
    let title: String
    var subtitle: String?
    @ViewBuilder var control: Control
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(theme.accent)
                        .frame(width: 28, height: 28)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.accent.opacity(0.13)))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13.5))
                        .foregroundColor(Aurora.text)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11.5))
                            .foregroundColor(Aurora.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .opacity(isEnabled ? 1 : 0.45)
            Spacer(minLength: 12)
            // 控件先按理想宽度排好，窗口窄时让标题换行，而不是把按钮文字截断成“…”。
            control.layoutPriority(1)
        }
        .padding(.vertical, 10)
        .frame(minHeight: 50)
    }
}

/// 带开关的一行。
struct ToggleRow: View {
    var symbol: String?
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(symbol: symbol, title: title, subtitle: subtitle) {
            GlowSwitch(title: title, isOn: $isOn)
        }
    }
}

/// 只显示文字的一行，例如统计与诊断。
struct ValueRow: View {
    var symbol: String?
    let title: String
    let value: String

    var body: some View {
        SettingsRow(symbol: symbol, title: title) {
            Text(value)
                .font(Font.system(size: 13).monospacedDigit())
                .foregroundColor(Aurora.secondaryText)
                .multilineTextAlignment(.trailing)
        }
    }
}

/// 一排按钮（左对齐），放在分组卡片里。
struct ButtonRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 8) { content }
            .padding(.vertical, 12)
            .frame(minHeight: 50)
    }
}

/// 对数刻度的时长滑杆，范围覆盖几秒到几小时仍能精细调整；右侧的数值是常用预设菜单。
struct DurationSlider: View {
    var symbol: String?
    let title: String
    @Binding var seconds: Double
    let range: ClosedRange<Double>

    private static let presets: [Double] = [15, 30, 60, 120, 300, 600, 900, 1800, 3600]

    var body: some View {
        let text = StatusPresentation.humanDuration(seconds)
        SettingsRow(symbol: symbol, title: title) {
            HStack(spacing: 12) {
                GlowSlider(value: Binding(get: { position(for: seconds) }, set: { seconds = DurationFormatting.snapToNiceSeconds(value(at: $0)) }),
                           title: title, valueText: text)
                    .frame(width: SettingsMetrics.sliderWidth)
                GlassMenu(title: text) {
                    ForEach(Self.presets.filter { range.contains($0) }, id: \.self) { preset in
                        Button(StatusPresentation.humanDuration(preset)) { seconds = preset }
                    }
                }
                .frame(minWidth: SettingsMetrics.valueWidth, alignment: .trailing)
            }
        }
    }

    private func position(for value: Double) -> Double {
        let lo = log(range.lowerBound), hi = log(range.upperBound)
        return (log(range.clamping(value)) - lo) / (hi - lo)
    }

    private func value(at position: Double) -> Double {
        let lo = log(range.lowerBound), hi = log(range.upperBound)
        return range.clamping(exp(lo + (hi - lo) * (0 ... 1).clamping(position)))
    }
}

/// 线性滑杆加右侧的数值，例如“8 px”。
struct ValueSlider: View {
    var symbol: String?
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let valueText: String

    var body: some View {
        SettingsRow(symbol: symbol, title: title) {
            HStack(spacing: 12) {
                GlowSlider(value: $value, range: range, title: title, valueText: valueText)
                    .frame(width: SettingsMetrics.sliderWidth)
                Text(valueText)
                    .font(Font.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundColor(Aurora.text)
                    .frame(minWidth: SettingsMetrics.valueWidth, alignment: .trailing)
            }
        }
    }
}

/// 星期选择：七个圆形开关，选中的填充主题渐变；顺序遵循系统日历，名称跟随界面语言。
struct WeekdayPicker: View {
    @Binding var selection: Set<Weekday>
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    private let calendar = L.calendar

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Weekday.ordered(firstWeekday: calendar.firstWeekday), id: \.self) { day in
                let selected = selection.contains(day)
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        if selected { selection.remove(day) } else { selection.insert(day) }
                    }
                } label: {
                    Text(day.shortName(calendar: calendar))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(selected ? .white : Aurora.secondaryText)
                        .frame(width: 38, height: 38)
                        .background(ZStack {
                            Circle().fill(Aurora.fill)
                            Circle().fill(theme.gradient).opacity(selected ? 1 : 0)
                        })
                        .overlay(Circle().strokeBorder(selected ? Color.white.opacity(0.25) : Aurora.glassStroke))
                        .shadow(color: theme.glow.opacity(selected ? 0.55 : 0), radius: 6)
                        .contentShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
                .help(day.fullName(calendar: calendar))
                .accessibilityLabel(day.fullName(calendar: calendar))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .opacity(isEnabled ? 1 : 0.4)
    }
}

/// 轨迹选择：一排带图标的卡片，选中的填充主题渐变。
struct PatternPicker: View {
    @Binding var selection: MovementPattern
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 8) {
            ForEach(MovementPattern.allCases) { pattern in
                let selected = pattern == selection
                let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { selection = pattern }
                } label: {
                    VStack(spacing: 6) {
                        // 各符号高矮不一，固定高度让下面的文字对齐。
                        Image(systemName: pattern.symbolName).font(.system(size: 16, weight: .semibold)).frame(height: 20)
                        Text(pattern.localizedName)
                            .font(.system(size: 11.5, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .foregroundColor(selected ? .white : Aurora.secondaryText)
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(ZStack {
                        shape.fill(Aurora.fill)
                        shape.fill(theme.gradient).opacity(selected ? 1 : 0)
                    })
                    .overlay(shape.strokeBorder(selected ? Color.white.opacity(0.25) : Aurora.glassStroke))
                    .shadow(color: theme.glow.opacity(selected ? 0.55 : 0), radius: 8)
                    .contentShape(shape)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel(pattern.localizedName)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .opacity(isEnabled ? 1 : 0.4)
    }
}

/// 轨迹预览：在点阵画布上画出发光的轨迹，一个光点沿轨迹循环运动。
struct PatternPreview: View {
    let settings: MovementSettings
    var height: CGFloat = 150
    @Environment(\.theme) private var theme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        GeometryReader { geo in
            // 轨迹只在设置或尺寸变化、body 重新求值时计算；静态部分在动画之外，动画每帧只重绘移动的光点。
            if geo.size.width > 20, geo.size.height > 20 {
                let path = Self.previewPath(settings, in: geo.size)
                ZStack(alignment: .topLeading) {
                    DotGrid(size: geo.size)
                    Path { $0.move(to: path.origin); $0.addLines(path.points) }
                        .stroke(theme.gradient, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        .shadow(color: theme.glow, radius: 6)
                    Circle().fill(Aurora.tertiaryText).frame(width: 7, height: 7).position(path.origin)
                    MovingDot(path: path, theme: theme)
                }
            }
        }
        .frame(height: height)
        .background(shape.fill(Aurora.inset))
        .overlay(shape.strokeBorder(Aurora.hairline))
        .clipShape(shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(settings.pattern.localizedName)
    }

    /// 预览里把振幅固定缩放到画布短边的 1/3，形状与节奏保持真实。
    private static func previewPath(_ settings: MovementSettings, in size: CGSize) -> MovementPath {
        var preview = settings.effective
        preview.amplitude = settings.invisibleMode ? 6 : Double(min(size.width, size.height)) / 3
        var rng = SeededRandomNumberGenerator(seed: 42)
        let bounds = CGRect(origin: .zero, size: size)
        return MovementPathGenerator.makePath(settings: preview, origin: CGPoint(x: size.width / 2, y: size.height / 2), bounds: bounds, sequence: 0, rng: &rng)
    }
}

/// 预览画布的点阵底纹。
private struct DotGrid: View {
    let size: CGSize
    private let spacing: CGFloat = 14

    var body: some View {
        Path { path in
            var y = spacing / 2
            while y < size.height {
                var x = spacing / 2
                while x < size.width {
                    path.addEllipse(in: CGRect(x: x - 0.75, y: y - 0.75, width: 1.5, height: 1.5))
                    x += spacing
                }
                y += spacing
            }
        }
        .fill(Aurora.dotGrid)
    }
}

/// 沿轨迹循环运动的光点：每圈走完停顿 0.8 秒。30 帧足够看清节奏；窗口不在前台或视图消失时停表。
private struct MovingDot: View {
    let path: MovementPath
    let theme: Theme
    @StateObject private var clock = FrameClock(framesPerSecond: 30)
    @Environment(\.controlActiveState) private var controlActiveState

    var body: some View {
        ZStack {
            Circle().fill(theme.light.opacity(0.45)).frame(width: 24, height: 24).blur(radius: 6)
            Circle().fill(theme.dot).frame(width: 10, height: 10).shadow(color: theme.glow, radius: 4)
        }
        .position(position(at: clock.now))
        .onAppear { clock.isRunning = controlActiveState != .inactive }
        .onDisappear { clock.isRunning = false }
        .onChange(of: controlActiveState) { clock.isRunning = $0 != .inactive }
    }

    private func position(at date: Date) -> CGPoint {
        guard !path.points.isEmpty else { return path.origin }
        let step = max(0.005, path.stepInterval)
        let total = path.totalDuration
        let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: total + 0.8)
        return t >= total ? path.origin : path.points[min(path.points.count - 1, Int(t / step))]
    }
}

/// 简单的帧时钟（替代 macOS 12 才有的 TimelineView）。
@MainActor
private final class FrameClock: ObservableObject {
    @Published private(set) var now = Date()
    private let interval: TimeInterval
    private var timer: Timer?

    init(framesPerSecond: Double) {
        interval = 1 / framesPerSecond
    }

    var isRunning: Bool {
        get { timer != nil }
        set {
            guard newValue != isRunning else { return }
            timer?.invalidate()
            timer = nil
            guard newValue else { return }
            let timer = Timer(timeInterval: interval, repeats: true) { [weak self] timer in
                guard let self else { return timer.invalidate() }
                MainActor.assumeIsolated { self.now = Date() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }
}

/// 时刻：玻璃胶囊里一个无边框的时间输入框（点选时、分后直接输入或用方向键调整）。
struct TimeChip: View {
    @Binding var date: Date
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock").font(.system(size: 12, weight: .semibold)).foregroundColor(theme.accent)
            TimeField(date: $date).fixedSize()
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(height: 30)
        .background(Capsule().fill(Aurora.controlFill))
        .overlay(Capsule().strokeBorder(Aurora.glassStroke))
        .opacity(isEnabled ? 1 : 0.4)
    }
}

/// 无边框、透明底的 NSDatePicker（文本 + 步进器），只编辑时和分。格式跟随界面语言。
private struct TimeField: NSViewRepresentable {
    @Binding var date: Date

    func makeNSView(context: Context) -> NSDatePicker {
        let picker = NSDatePicker()
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = .hourMinute
        picker.isBezeled = false
        picker.isBordered = false
        picker.drawsBackground = false
        picker.font = .monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        picker.textColor = .labelColor
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.changed(_:))
        return picker
    }

    func updateNSView(_ picker: NSDatePicker, context: Context) {
        context.coordinator.date = $date
        picker.locale = L.locale
        picker.calendar = L.calendar
        picker.isEnabled = context.environment.isEnabled
        if picker.dateValue != date { picker.dateValue = date }
    }

    func makeCoordinator() -> Coordinator { Coordinator(date: $date) }

    @MainActor
    final class Coordinator: NSObject {
        var date: Binding<Date>

        init(date: Binding<Date>) {
            self.date = date
        }

        @objc func changed(_ sender: NSDatePicker) {
            date.wrappedValue = sender.dateValue
        }
    }
}

/// 统计数字卡片：小标题 + 大号数字。
struct MetricTile: View {
    let symbol: String
    let title: String
    let value: String
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundColor(theme.accent)
                Text(title).font(.system(size: 12)).foregroundColor(Aurora.secondaryText).lineLimit(1)
            }
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundColor(Aurora.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

/// 功能卡片：大图标、标题、一句说明、开关；开启时卡片泛起主题色。
struct FeatureTile: View {
    let symbol: String
    let title: String
    let detail: String
    @Binding var isOn: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                IconTile(symbol: symbol, theme: theme, size: 38, glow: isOn)
                Spacer()
                GlowSwitch(title: title, isOn: $isOn)
            }
            .padding(.bottom, 14)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Aurora.text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 4)
            Text(detail)
                .font(.system(size: 11.5))
                .foregroundColor(Aurora.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassCard(tint: isOn ? theme.light : nil)
    }
}

/// “登录时启动”开关：显示系统登录项的真实状态，切换时直接注册或注销。
struct LaunchAtLoginToggle: View {
    @ObservedObject var model: AppModel
    let actions: AppActions

    var body: some View {
        ToggleRow(symbol: "power", title: L.t("general.launchAtLogin"), isOn: Binding(get: { model.launchAtLogin }, set: { actions.setLaunchAtLogin($0) }))
            .disabled(model.loginItemStatus == .unavailable)
    }
}
