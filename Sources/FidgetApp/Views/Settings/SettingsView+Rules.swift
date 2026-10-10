import FidgetCore
import FidgetSystem
import SwiftUI

struct RulesSettingsView: View {
    @ObservedObject var model: AppModel
    let actions: AppActions

    var body: some View {
        SettingsPage(.rules) {
            SettingsGroup(title: L.t("rules.system")) {
                ToggleRow(symbol: "lock.fill", title: L.t("rules.screenLocked"), isOn: $model.settings.rules.pauseWhenScreenLocked)
                RowDivider()
                ToggleRow(symbol: "battery.25", title: L.t("rules.battery"), isOn: $model.settings.rules.pauseOnBattery)
                RowDivider()
                ToggleRow(symbol: "play.rectangle", title: L.t("rules.media"), isOn: $model.settings.rules.pauseWhenOtherAppPreventsDisplaySleep)
                if model.settings.rules.pauseWhenOtherAppPreventsDisplaySleep {
                    DisplaySleepHoldersNote(live: model.live).padding(.leading, 40).padding(.bottom, 12)
                }
            }
            SettingsGroup(title: L.t("rules.apps")) {
                SettingsRow(symbol: "app.badge", title: L.t("rules.appMode")) {
                    PillPicker(options: AppRuleMode.allCases, selection: $model.settings.rules.appRuleMode, name: \.localizedName) { mode in
                        Text(mode.localizedName)
                    }
                }
                RowDivider()
                if model.settings.rules.appRules.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "square.dashed").font(.system(size: 20, weight: .light)).foregroundColor(Aurora.tertiaryText)
                        FootnoteText(L.t("rules.apps.empty"))
                    }
                    .padding(.vertical, 14)
                } else {
                    ForEach(model.settings.rules.appRules) { rule in
                        AppRuleRow(rule: rule) { actions.removeAppRule(rule) }
                        RowDivider()
                    }
                }
                ButtonRow {
                    Button(L.t("rules.chooseApp")) { actions.chooseAppForRule() }
                    GlassMenu(title: L.t("rules.addRunning")) {
                        ForEach(RunningApps.regularApps()) { app in
                            Button(app.name) { actions.addAppRule(app) }
                        }
                    }
                }
            }
        }
    }
}

private struct AppRuleRow: View {
    let rule: AppRule
    let remove: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            if let icon = RunningApps.icon(forBundleIdentifier: rule.bundleIdentifier) {
                Image(nsImage: icon).resizable().frame(width: 30, height: 30)
            } else {
                Image(systemName: Symbols.name("app.dashed")).font(.system(size: 20)).foregroundColor(Aurora.tertiaryText).frame(width: 30, height: 30)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.displayName).font(.system(size: 13.5)).foregroundColor(Aurora.text)
                Text(rule.bundleIdentifier).font(.system(size: 11)).foregroundColor(Aurora.tertiaryText)
            }
            Spacer()
            Button(action: remove) {
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(isHovering ? .white : Aurora.secondaryText)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(isHovering ? Aurora.negative.opacity(0.85) : Aurora.controlFill))
                    .contentShape(Circle())
            }
            .buttonStyle(PlainButtonStyle())
            .onHover { isHovering = $0 }
            .help(L.t("rules.remove"))
            .accessibilityLabel(L.t("rules.remove"))
        }
        .padding(.vertical, 10)
    }
}

/// 当前保持显示器唤醒的应用。单独成一个视图订阅运行数据，每秒变化时只刷新这一行，而不是整个规则页。
private struct DisplaySleepHoldersNote: View {
    @ObservedObject var live: LiveState

    var body: some View {
        let holders = live.diagnostics.environment.displaySleepHolders
        FootnoteText(L.f("rules.media.holders", holders.isEmpty ? L.t("common.none") : holders.joined(separator: ", ")))
    }
}

struct KeepAwakeSettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SettingsPage(.keepAwake) {
            VStack(alignment: .leading, spacing: 8) {
                GroupHeader(L.t("keepAwake.title"))
                HStack(alignment: .top, spacing: 12) {
                    FeatureTile(symbol: "display", title: L.t("keepAwake.display"), detail: L.t("keepAwake.display.detail"),
                                isOn: $model.settings.keepAwake.preventDisplaySleep)
                    FeatureTile(symbol: "moon.zzz.fill", title: L.t("keepAwake.system"), detail: L.t("keepAwake.system.detail"),
                                isOn: $model.settings.keepAwake.preventSystemSleep)
                }
                .fixedSize(horizontal: false, vertical: true)
                FootnoteText(L.t("keepAwake.hint")).padding(.horizontal, 4)
            }
            SettingsGroup {
                HeldAssertionsRow(live: model.live)
            }
        }
    }
}

/// 当前持有的电源断言。单独订阅运行数据，每秒变化时只刷新这一行。
private struct HeldAssertionsRow: View {
    @ObservedObject var live: LiveState

    var body: some View {
        ValueRow(symbol: "bolt.fill", title: L.t("keepAwake.state"), value: live.diagnostics.assertions.localizedSummary)
    }
}

struct AdvancedSettingsView: View {
    @ObservedObject var model: AppModel
    let actions: AppActions

    var body: some View {
        SettingsPage(.advanced) {
            StatisticsGroup(live: model.live, actions: actions)
            DiagnosticsGroup(model: model, live: model.live, actions: actions)
            SettingsGroup(title: L.t("advanced.logging")) {
                ToggleRow(symbol: "doc.text", title: L.t("advanced.fileLogging"), isOn: $model.settings.advanced.fileLoggingEnabled)
                RowDivider()
                ButtonRow {
                    Button(L.t("advanced.revealLog")) { actions.revealLogFile() }
                }
            }
            SettingsGroup(title: L.t("advanced.settingsFile")) {
                ToggleRow(symbol: "checkmark.shield", title: L.t("advanced.verifyMovement"), isOn: $model.settings.advanced.verifyPointerMovement)
                RowDivider()
                ButtonRow {
                    Button(L.t("advanced.export")) { actions.exportSettings() }
                    Button(L.t("advanced.import")) { actions.importSettings() }
                    Button(L.t("advanced.revealSettings")) { actions.revealSettingsFile() }
                    Spacer(minLength: 8)
                    Button(L.t("advanced.resetSettings")) { actions.resetSettings() }.buttonStyle(GlassButtonStyle(kind: .destructive))
                }
            }
            SettingsGroup(title: L.t("advanced.about")) {
                ValueRow(symbol: "info.circle", title: L.t("advanced.version"), value: "\(AppInfo.version) (\(AppInfo.build))")
                RowDivider()
                ButtonRow {
                    Button(L.t("advanced.checkUpdates")) { actions.checkForUpdates() }
                    Button(L.t("advanced.github")) { actions.openRepository() }
                }
            }
        }
    }
}

/// 统计：随每次移动与工作时长变化。
private struct StatisticsGroup: View {
    @ObservedObject var live: LiveState
    let actions: AppActions

    var body: some View {
        let statistics = live.statistics
        VStack(alignment: .leading, spacing: 8) {
            GroupHeader(L.t("advanced.statistics")) {
                Button(L.t("advanced.resetStats")) { actions.resetStatistics() }
            }
            HStack(spacing: 12) {
                MetricTile(symbol: "sun.max.fill", title: L.t("advanced.stats.today"), value: "\(statistics.todayJiggles)")
                MetricTile(symbol: "sum", title: L.t("advanced.stats.total"), value: "\(statistics.totalJiggles)")
            }
            HStack(spacing: 12) {
                MetricTile(symbol: "clock.fill", title: L.t("advanced.stats.last"),
                           value: statistics.lastJiggleAt.map { StatusPresentation.relativeTime($0) } ?? L.t("advanced.stats.never"))
                MetricTile(symbol: "hourglass", title: L.t("advanced.stats.running"), value: StatusPresentation.humanDuration(statistics.totalRunningSeconds))
            }
        }
    }
}

/// 诊断：每秒刷新。
private struct DiagnosticsGroup: View {
    @ObservedObject var model: AppModel
    @ObservedObject var live: LiveState
    let actions: AppActions

    var body: some View {
        let diagnostics = live.diagnostics
        SettingsGroup(title: L.t("advanced.diagnostics")) {
            Button(L.t("advanced.copyDiagnostics")) { actions.copyDiagnostics() }
        } content: {
            ValueRow(title: L.t("advanced.diag.permission"), value: yesNo(model.isAccessibilityTrusted))
            RowDivider()
            ValueRow(title: L.t("advanced.diag.systemIdle"), value: DurationFormatting.clock(diagnostics.systemIdleSeconds))
            RowDivider()
            ValueRow(title: L.t("advanced.diag.realIdle"), value: DurationFormatting.clock(diagnostics.realIdleSeconds))
            RowDivider()
            ValueRow(title: L.t("advanced.diag.status"), value: "\(live.status.kind)")
            RowDivider()
            ValueRow(title: L.t("advanced.diag.locked"), value: yesNo(diagnostics.environment.isScreenLocked))
            RowDivider()
            ValueRow(title: L.t("advanced.diag.battery"), value: yesNo(diagnostics.environment.isOnBattery))
            RowDivider()
            ValueRow(title: L.t("advanced.diag.assertions"), value: diagnostics.assertions.localizedSummary)
            if !diagnostics.environment.displaySleepHolders.isEmpty {
                RowDivider()
                ValueRow(title: L.t("advanced.diag.holders"), value: diagnostics.environment.displaySleepHolders.joined(separator: ", "))
            }
            if let last = model.lastJiggle {
                RowDivider()
                ValueRow(title: L.t("advanced.diag.lastJiggle"), value: "\(StatusPresentation.clockTime(last.endedAt)) · \(yesNo(last.pointerMoved))")
            }
        }
    }

    private func yesNo(_ value: Bool) -> String { value ? L.t("common.yes") : L.t("common.no") }
}
