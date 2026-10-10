import FidgetCore
import SwiftUI

/// 首次启动引导：介绍 → 授权 → 偏好 → 完成。每一步换一种主题色。
struct OnboardingView: View {
    static let size = CGSize(width: 580, height: 620)
    private static let themes: [Theme] = [.violet, .sky, .emerald, .amber]

    @ObservedObject var model: AppModel
    let actions: AppActions
    @State private var step = 0
    private var stepCount: Int { Self.themes.count }
    private var theme: Theme { Self.themes[step] }

    var body: some View {
        ZStack {
            AuroraBackground(theme: theme)
                .id(step)
                .transition(.opacity)
            VStack(spacing: 22) {
                Image(nsImage: AppInfo.iconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 88, height: 88)
                    .shadow(color: theme.glow.opacity(0.8), radius: 24, y: 6)
                Group {
                    switch step {
                    case 0: welcome
                    case 1: permission
                    case 2: preferences
                    default: done
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                controls
            }
            .padding(.horizontal, 32)
            .padding(.top, 40)
            .padding(.bottom, 28)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .buttonStyle(GlassButtonStyle())
        .environment(\.theme, theme)
    }

    private func page(title: String, text: String, @ViewBuilder extra: () -> some View) -> some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(Aurora.text)
                .multilineTextAlignment(.center)
            Text(text)
                .font(.system(size: 13.5))
                .foregroundColor(Aurora.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            extra().padding(.top, 10)
        }
    }

    private var welcome: some View {
        page(title: L.t("onboarding.title"), text: L.t("onboarding.welcome.text")) {
            VStack(alignment: .leading, spacing: 0) {
                featureRow("cursorarrow.motionlines", .sky, L.t("onboarding.feature.idle"))
                RowDivider()
                featureRow("calendar.badge.clock", .rose, L.t("onboarding.feature.rules"))
                RowDivider()
                featureRow("lock.shield", .emerald, L.t("onboarding.feature.privacy"))
            }
            .padding(.horizontal, 16)
            .glassCard()
        }
    }

    private func featureRow(_ symbol: String, _ theme: Theme, _ text: String) -> some View {
        HStack(spacing: 14) {
            IconTile(symbol: symbol, theme: theme, size: 32)
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(Aurora.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
    }

    private var permission: some View {
        page(title: L.t("onboarding.permission.title"), text: L.t("onboarding.permission.text")) {
            VStack(spacing: 14) {
                if model.isAccessibilityTrusted {
                    StatusChip(symbol: "checkmark", title: L.t("onboarding.permission.granted"), color: Aurora.positive)
                } else {
                    StatusChip(symbol: "hourglass", title: L.t("onboarding.permission.missing"), color: Aurora.caution)
                    HStack(spacing: 10) {
                        Button(L.t("popover.grantAccess")) { actions.requestAccessibility() }.buttonStyle(GlassButtonStyle(kind: .primary))
                        Button(L.t("popover.openSystemSettings")) { actions.openAccessibilitySettings() }
                    }
                }
                FootnoteText(L.t("onboarding.permission.note")).multilineTextAlignment(.center)
                if !model.isAccessibilityTrusted {
                    FootnoteText(L.t("permission.reset.hint")).multilineTextAlignment(.center)
                    Button(L.t("permission.reset")) { actions.resetAccessibility() }.controlSize(.small)
                }
            }
        }
    }

    private var preferences: some View {
        page(title: L.t("onboarding.prefs.title"), text: L.t("onboarding.prefs.text")) {
            SettingsGroup {
                LaunchAtLoginToggle(model: model, actions: actions)
                RowDivider()
                DurationSlider(symbol: "hourglass", title: L.t("movement.idleThreshold"), seconds: $model.settings.idleThresholdSeconds, range: SettingsLimits.idleThresholdSeconds)
                RowDivider()
                ToggleRow(symbol: "eye.slash", title: L.t("movement.invisible"), isOn: $model.settings.movement.invisibleMode)
                RowDivider()
                ToggleRow(symbol: "lock.fill", title: L.t("rules.screenLocked"), isOn: $model.settings.rules.pauseWhenScreenLocked)
            }
        }
    }

    private var done: some View {
        page(title: L.t("onboarding.done.title"), text: L.t("onboarding.done.text")) {
            Button {
                actions.moveNow()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill").font(.system(size: 10, weight: .bold))
                    Text(L.t("movement.testNow"))
                }
            }
        }
    }

    private var controls: some View {
        HStack {
            if step > 0 {
                Button(L.t("onboarding.back")) { go(to: step - 1) }
            } else {
                Button(L.t("onboarding.skip")) { actions.finishOnboarding() }
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(0 ..< stepCount, id: \.self) { i in
                    ZStack {
                        Capsule().fill(Aurora.idle)
                        Capsule().fill(theme.gradient).opacity(i == step ? 1 : 0)
                    }
                    .frame(width: i == step ? 20 : 7, height: 7)
                }
            }
            Spacer()
            if step < stepCount - 1 {
                Button(L.t("onboarding.continue")) { go(to: step + 1) }
                    .buttonStyle(GlassButtonStyle(kind: .primary))
                    .keyboardShortcut(.defaultAction)
            } else {
                Button(L.t("onboarding.finish")) { actions.finishOnboarding() }
                    .buttonStyle(GlassButtonStyle(kind: .primary))
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func go(to newStep: Int) {
        withAnimation(.easeInOut(duration: 0.3)) { step = newStep }
    }
}

/// 关于窗口。
struct AboutView: View {
    static let size = CGSize(width: 380, height: 460)

    let actions: AppActions

    var body: some View {
        ZStack {
            AuroraBackground(theme: .violet)
            VStack(spacing: 14) {
                Image(nsImage: AppInfo.iconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 104, height: 104)
                    .shadow(color: Theme.violet.glow.opacity(0.8), radius: 26, y: 8)
                Text(AppInfo.name)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(Aurora.text)
                Text(L.f("about.version", AppInfo.version, AppInfo.build))
                    .font(Font.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundColor(Aurora.secondaryText)
                    .padding(.horizontal, 12)
                    .frame(height: 24)
                    .background(Capsule().fill(Aurora.fill))
                    .overlay(Capsule().strokeBorder(Aurora.glassStroke))
                Text(L.t("about.tagline"))
                    .font(.system(size: 13.5))
                    .foregroundColor(Aurora.text)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
                FootnoteText(L.t("about.credit")).multilineTextAlignment(.center)
                HStack(spacing: 10) {
                    Button(L.t("advanced.github")) { actions.openRepository() }
                    Button(L.t("advanced.checkUpdates")) { actions.checkForUpdates() }
                }
                .padding(.top, 6)
                Text(L.t("about.license")).font(.system(size: 11)).foregroundColor(Aurora.tertiaryText)
            }
            .padding(.horizontal, 32)
            .padding(.top, 24)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .buttonStyle(GlassButtonStyle())
        .environment(\.theme, .violet)
    }
}
