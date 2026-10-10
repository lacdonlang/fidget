import FidgetCore
import SwiftUI

/// 设置窗口的分区。每个分区有自己的主题色：侧边栏图标、页头、窗口光晕与页面里的控件都用它。
enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case general, movement, schedule, rules, keepAwake, advanced

    var id: String { rawValue }
    var title: String { L.t("section.\(rawValue)") }
    var subtitle: String { L.t("section.\(rawValue).subtitle") }

    var symbolName: String {
        switch self {
        case .general: "gearshape.fill"
        case .movement: "cursorarrow.motionlines"
        case .schedule: "calendar"
        case .rules: "pause.fill"
        case .keepAwake: "sun.max.fill"
        case .advanced: "wrench.and.screwdriver.fill"
        }
    }

    var theme: Theme {
        switch self {
        case .general: .violet
        case .movement: .sky
        case .schedule: .rose
        case .rules: .emerald
        case .keepAwake: .amber
        case .advanced: .indigo
        }
    }
}

/// 设置窗口当前分区。放在窗口之外，URL 与菜单也能直达某个分区。
@MainActor
final class SettingsNavigation: ObservableObject {
    @Published var section: SettingsSection = .general
}

/// 设置窗口：深色底随分区变换光晕颜色；左侧分区列表延伸到透明标题栏下方，右侧是当前分区的设置页。
/// 设置页停在标题栏下沿：标题栏那一条只有背景，按住它就能拖动窗口。
/// 不用 macOS 13 才有的 NavigationSplitView，各版本系统外观一致。
struct SettingsView: View {
    static let defaultSize = CGSize(width: 860, height: 640)
    static let minimumSize = CGSize(width: 780, height: 520)

    let model: AppModel
    @ObservedObject var navigation: SettingsNavigation
    let actions: AppActions

    var body: some View {
        ZStack {
            AuroraBackground(theme: navigation.section.theme)
                .id(navigation.section)
                .transition(.opacity)
            HStack(spacing: 0) {
                SettingsSidebar(model: model, navigation: navigation, actions: actions)
                    .edgesIgnoringSafeArea(.top)
                detail.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(minWidth: Self.minimumSize.width, minHeight: Self.minimumSize.height)
    }

    @ViewBuilder
    private var detail: some View {
        switch navigation.section {
        case .general: GeneralSettingsView(model: model, actions: actions)
        case .movement: MovementSettingsView(model: model, actions: actions)
        case .schedule: ScheduleSettingsView(model: model)
        case .rules: RulesSettingsView(model: model, actions: actions)
        case .keepAwake: KeepAwakeSettingsView(model: model)
        case .advanced: AdvancedSettingsView(model: model, actions: actions)
        }
    }
}

private struct SettingsSidebar: View {
    let model: AppModel
    @ObservedObject var navigation: SettingsNavigation
    let actions: AppActions
    @State private var hovered: SettingsSection?
    @Namespace private var namespace

    private static let outerPadding: CGFloat = 12
    private static let itemPadding: CGFloat = 8
    private static let iconSize: CGFloat = 26
    private static let itemSpacing: CGFloat = 11

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
                .padding(.horizontal, Self.outerPadding + Self.itemPadding)
                .padding(.top, 54)
                .padding(.bottom, 22)
            VStack(spacing: 4) {
                ForEach(SettingsSection.allCases) { section in
                    item(section)
                }
            }
            .padding(.horizontal, Self.outerPadding)
            Spacer(minLength: 16)
            SidebarStatus(model: model, live: model.live, actions: actions)
                .padding(12)
                .environment(\.theme, navigation.section.theme)
        }
        .frame(width: 220)
        .frame(maxHeight: .infinity)
        .background(Aurora.sidebarTint)
        .overlay(Rectangle().fill(Aurora.hairline).frame(width: 1), alignment: .trailing)
    }

    /// 与下面的分区行对齐：图标与分区图标同列同宽，文字与分区名称左对齐。
    private var brand: some View {
        HStack(spacing: Self.itemSpacing) {
            // 应用图标四周有透明边（macOS 图标网格里图形只占 824/1024），放大画进图标位，可见部分与分区图标一样大。
            Image(nsImage: AppInfo.iconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: Self.iconSize * 1024 / 824, height: Self.iconSize * 1024 / 824)
                .frame(width: Self.iconSize, height: Self.iconSize)
            VStack(alignment: .leading, spacing: 1) {
                Text(AppInfo.name)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(Aurora.text)
                Text(L.f("about.version", AppInfo.version, AppInfo.build))
                    .font(.system(size: 11))
                    .foregroundColor(Aurora.tertiaryText)
            }
        }
    }

    private func item(_ section: SettingsSection) -> some View {
        let selected = navigation.section == section
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { navigation.section = section }
        } label: {
            HStack(spacing: Self.itemSpacing) {
                IconTile(symbol: section.symbolName, theme: section.theme, size: Self.iconSize, glow: selected)
                Text(section.title)
                    .font(.system(size: 13.5, weight: selected ? .semibold : .medium))
                    .foregroundColor(selected ? Aurora.text : Aurora.text.opacity(0.75))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Self.itemPadding)
            .frame(height: 40)
            .background(ZStack {
                if selected {
                    shape.fill(Aurora.selection)
                        .shadow(color: Aurora.cardShadow, radius: 4, y: 1)
                        .overlay(shape.strokeBorder(Aurora.glassStroke))
                        .matchedGeometryEffect(id: "selection", in: namespace)
                } else if hovered == section {
                    shape.fill(Aurora.hover)
                }
            })
            .contentShape(shape)
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { inside in
            if inside { hovered = section } else if hovered == section { hovered = nil }
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 侧边栏底部：当前运行状态与总开关。单独订阅运行数据，每秒变化时只刷新这一块。
private struct SidebarStatus: View {
    @ObservedObject var model: AppModel
    @ObservedObject var live: LiveState
    let actions: AppActions

    var body: some View {
        let presentation = StatusPresentation.make(status: live.status, settings: model.settings, now: Date())
        HStack(spacing: 10) {
            Circle()
                .fill(presentation.kind.color)
                .frame(width: 8, height: 8)
                .shadow(color: presentation.kind.color.opacity(0.9), radius: 4)
            Text(presentation.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Aurora.text)
                .lineLimit(1)
            Spacer(minLength: 4)
            GlowSwitch(title: L.t("popover.enable"), isOn: Binding(get: { model.settings.isEnabled }, set: { actions.setEnabled($0) }))
        }
        .padding(.horizontal, 12)
        .frame(height: 46)
        .glassCard(cornerRadius: 12)
        .help(presentation.detail)
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var model: AppModel
    let actions: AppActions

    var body: some View {
        SettingsPage(.general) {
            SettingsGroup(title: L.t("general.startup"), footer: model.loginItemStatus == .unavailable ? L.t("general.launchAtLogin.unavailable") : nil) {
                LaunchAtLoginToggle(model: model, actions: actions)
                if model.loginItemStatus == .requiresApproval {
                    RowDivider()
                    SettingsRow(title: L.t("general.launchAtLogin.approval")) {
                        Button(L.t("general.openLoginItems")) { actions.openLoginItemsSettings() }
                    }
                }
            }
            SettingsGroup(title: L.t("general.menuBar")) {
                SettingsRow(symbol: "menubar.rectangle", title: L.t("general.iconStyle")) {
                    PillPicker(options: MenuBarIconStyle.available, selection: $model.settings.general.menuBarIconStyle, name: \.localizedName) { style in
                        Image(systemName: StatusPresentation.previewSymbol(for: style)).font(.system(size: 13, weight: .semibold))
                    }
                }
                RowDivider()
                ToggleRow(symbol: "timer", title: L.t("general.showCountdown"), isOn: $model.settings.general.showCountdownInMenuBar)
            }
            SettingsGroup(title: L.t("general.shortcut"), footer: L.t("general.shortcut.hint")) {
                SettingsRow(symbol: "command", title: L.t("general.toggleShortcut")) {
                    HStack(spacing: 8) {
                        KeyRecorderView(hotKey: $model.settings.general.hotKey)
                            .frame(width: 150, height: 28)
                        if model.settings.general.hotKey != nil {
                            Button(L.t("general.clear")) { model.settings.general.hotKey = nil }.controlSize(.small)
                        }
                    }
                }
            }
            SettingsGroup(title: L.t("general.appearanceAndLanguage")) {
                SettingsRow(symbol: "circle.lefthalf.fill", title: L.t("general.appearance")) {
                    PillPicker(options: AppearancePreference.allCases, selection: $model.settings.general.appearance, name: \.localizedName) { appearance in
                        Text(appearance.localizedName)
                    }
                }
                RowDivider()
                SettingsRow(symbol: "globe", title: L.t("general.language")) {
                    GlassMenu(title: languageName(languageSelection.wrappedValue)) {
                        ForEach([LanguageState.system] + L.supportedLanguages, id: \.self) { language in
                            Toggle(languageName(language), isOn: Binding(get: { languageSelection.wrappedValue == language }, set: { if $0 { languageSelection.wrappedValue = language } }))
                        }
                    }
                }
            }
            SettingsGroup(title: L.t("general.permissions")) {
                SettingsRow(symbol: "hand.raised.fill", title: L.t("general.accessibility")) {
                    if model.isAccessibilityTrusted {
                        StatusChip(symbol: "checkmark", title: L.t("general.accessibility.granted"), color: Aurora.positive)
                    } else {
                        StatusChip(symbol: "xmark", title: L.t("general.accessibility.missing"), color: Aurora.negative)
                    }
                }
                if !model.isAccessibilityTrusted {
                    ButtonRow {
                        Button(L.t("popover.grantAccess")) { actions.requestAccessibility() }.buttonStyle(GlassButtonStyle(kind: .primary))
                        Button(L.t("popover.openSystemSettings")) { actions.openAccessibilitySettings() }
                    }
                    RowDivider()
                    SettingsRow(symbol: "arrow.counterclockwise", title: L.t("permission.reset.title"), subtitle: L.t("permission.reset.hint")) {
                        Button(L.t("permission.reset")) { actions.resetAccessibility() }
                    }
                }
                RowDivider()
                ButtonRow {
                    Button(L.t("general.showOnboarding")) { actions.openOnboarding() }
                }
            }
        }
    }

    private var languageSelection: Binding<String> {
        Binding(
            get: { model.settings.general.languageOverride ?? LanguageState.system },
            set: { model.settings.general.languageOverride = $0 == LanguageState.system ? nil : $0 }
        )
    }

    /// 每种语言用它自己的语言显示名称，例如 English、简体中文。
    private func languageName(_ language: String) -> String {
        guard language != LanguageState.system else { return L.t("general.language.system") }
        return Locale(identifier: language).localizedString(forIdentifier: language) ?? language
    }
}

struct MovementSettingsView: View {
    @ObservedObject var model: AppModel
    let actions: AppActions

    private var invisible: Bool { model.settings.movement.invisibleMode }

    var body: some View {
        SettingsPage(.movement) {
            moveNow
        } content: {
            SettingsGroup(title: L.t("movement.timing"), footer: L.t("movement.timing.hint")) {
                DurationSlider(symbol: "hourglass", title: L.t("movement.idleThreshold"), seconds: $model.settings.idleThresholdSeconds, range: SettingsLimits.idleThresholdSeconds)
                RowDivider()
                DurationSlider(symbol: "repeat", title: L.t("movement.interval"), seconds: $model.settings.jiggleIntervalSeconds, range: SettingsLimits.jiggleIntervalSeconds)
            }
            SettingsGroup(title: L.t("movement.pattern")) {
                VStack(spacing: 12) {
                    PatternPreview(settings: model.settings.movement)
                    PatternPicker(selection: $model.settings.movement.pattern).disabled(invisible)
                }
                .padding(.vertical, 16)
                RowDivider()
                ToggleRow(symbol: "arrow.uturn.backward", title: L.t("movement.returnToOrigin"), isOn: $model.settings.movement.returnToOrigin)
                    .disabled(invisible)
                RowDivider()
                ToggleRow(symbol: "eye.slash", title: L.t("movement.invisible"), isOn: $model.settings.movement.invisibleMode)
                RowDivider()
                ValueSlider(symbol: "arrow.up.left.and.arrow.down.right", title: L.t("movement.amplitude"),
                            value: Binding(get: { model.settings.movement.amplitude }, set: { model.settings.movement.amplitude = $0.rounded() }),
                            range: SettingsLimits.amplitude, valueText: "\(Int(model.settings.movement.amplitude)) px")
                    .disabled(invisible)
                RowDivider()
                ValueSlider(symbol: "stopwatch", title: L.t("movement.duration"),
                            value: Binding(get: { Double(model.settings.movement.durationMilliseconds) }, set: { model.settings.movement.durationMilliseconds = Int(($0 / 10).rounded() * 10) }),
                            range: Double(SettingsLimits.durationMilliseconds.lowerBound) ... Double(SettingsLimits.durationMilliseconds.upperBound),
                            valueText: "\(model.settings.movement.durationMilliseconds) ms")
                    .disabled(invisible)
            }
        }
    }

    /// 页头右侧：立即移动，下方是上次移动的结果。
    private var moveNow: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Button {
                actions.moveNow()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill").font(.system(size: 10, weight: .bold))
                    Text(L.t("movement.testNow"))
                }
            }
            .buttonStyle(GlassButtonStyle(kind: .primary))
            if let last = model.lastJiggle {
                let time = StatusPresentation.clockTime(last.endedAt)
                Text(last.pointerMoved ? L.f("movement.lastResult.ok", time) : L.f("movement.lastResult.failed", time))
                    .font(.system(size: 11))
                    .foregroundColor(last.pointerMoved ? Aurora.tertiaryText : Aurora.negative)
            }
        }
    }
}

struct ScheduleSettingsView: View {
    @ObservedObject var model: AppModel
    private let calendar = Calendar.current

    private var isEnabled: Bool { model.settings.schedule.isEnabled }

    var body: some View {
        SettingsPage(.schedule) {
            SettingsGroup {
                ToggleRow(symbol: "calendar.badge.clock", title: L.t("schedule.enable"), subtitle: L.t("schedule.hint"), isOn: $model.settings.schedule.isEnabled)
            }
            SettingsGroup(title: L.t("schedule.days")) {
                WeekdayPicker(selection: $model.settings.schedule.activeDays)
                    .padding(.vertical, 14)
                RowDivider()
                ButtonRow {
                    Button(L.t("schedule.weekdays")) { model.settings.schedule.activeDays = Weekday.workdays }
                    Button(L.t("schedule.everyDay")) { model.settings.schedule.activeDays = Set(Weekday.allCases) }
                }
                .controlSize(.small)
            }
            .disabled(!isEnabled)
            SettingsGroup(title: L.t("schedule.hours")) {
                SettingsRow(symbol: "sunrise", title: L.t("schedule.start")) {
                    TimeChip(date: minuteBinding(\.startMinute))
                }
                RowDivider()
                SettingsRow(symbol: "sunset", title: L.t("schedule.end")) {
                    TimeChip(date: minuteBinding(\.endMinute))
                }
                if model.settings.schedule.isOvernight {
                    RowDivider()
                    HStack(spacing: 6) {
                        Image(systemName: "moon.stars").foregroundColor(SettingsSection.schedule.theme.accent)
                        FootnoteText(L.t("schedule.overnight"))
                    }
                    .padding(.vertical, 10)
                }
                RowDivider()
                ValueRow(symbol: "clock.arrow.circlepath", title: L.t("schedule.next"), value: nextActiveText)
            }
            .disabled(!isEnabled)
        }
    }

    private var nextActiveText: String {
        let now = Date()
        guard isEnabled else { return L.t("schedule.next.now") }
        guard let next = model.settings.schedule.nextActiveDate(after: now, calendar: calendar) else { return L.t("schedule.next.never") }
        if next <= now { return L.t("schedule.next.now") }
        return StatusPresentation.timeString(next, now: now, calendar: calendar)
    }

    private func minuteBinding(_ keyPath: WritableKeyPath<ScheduleSettings, Int>) -> Binding<Date> {
        let day = calendar.startOfDay(for: Date())
        return Binding(
            get: { calendar.date(atMinuteOfDay: model.settings.schedule[keyPath: keyPath], on: day) ?? day },
            set: { model.settings.schedule[keyPath: keyPath] = calendar.minuteOfDay(of: $0) }
        )
    }
}
