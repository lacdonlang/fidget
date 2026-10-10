import FidgetCore
import SwiftUI

/// 菜单栏弹出面板。显示运行状态，所以同时订阅设置与每秒变化的运行数据。
struct PopoverView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var live: LiveState
    let actions: AppActions

    var body: some View {
        let presentation = StatusPresentation.make(status: live.status, settings: model.settings, now: Date())
        VStack(alignment: .leading, spacing: 12) {
            header(presentation)
            mainCard(presentation)
            banners
            quickActions
            statsRow
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 330)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func header(_ presentation: StatusPresentation) -> some View {
        HStack(spacing: 8) {
            Image(systemName: presentation.symbolName)
                .font(.title3)
                .foregroundColor(presentation.kind.color)
                .frame(width: 24)
            Text(AppInfo.name).font(.headline)
            Spacer()
            StatusBadge(kind: presentation.kind, title: presentation.title)
        }
    }

    private func mainCard(_ presentation: StatusPresentation) -> some View {
        Card {
            Toggle(isOn: Binding(get: { model.settings.isEnabled }, set: { actions.setEnabled($0) })) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L.t("popover.enable")).font(.body.weight(.medium))
                    Text(presentation.detail).font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            if let progress {
                IdleProgressBar(progress: progress, kind: presentation.kind)
            }
        }
    }

    /// watching：闲置进度；active：距下一次移动的进度。
    private var progress: Double? {
        switch live.status {
        case let .watching(idle, _):
            return model.settings.idleThresholdSeconds > 0 ? idle / model.settings.idleThresholdSeconds : 0
        case let .active(_, _, next):
            return model.settings.jiggleIntervalSeconds > 0 ? 1 - next / model.settings.jiggleIntervalSeconds : 1
        default:
            return nil
        }
    }

    @ViewBuilder
    private var banners: some View {
        if case .blocked = live.status {
            Banner(kind: .error, text: L.t("status.blocked.detail"),
                   primary: (L.t("popover.grantAccess"), { actions.requestAccessibility() }),
                   secondary: (L.t("popover.openSystemSettings"), { actions.openAccessibilitySettings() }),
                   footnote: (L.t("permission.reset.link"), { actions.resetAccessibility() }))
        } else if let warning = model.warnings.first, case let .pointerDidNotMove(failures) = warning {
            Banner(kind: .warning, text: L.f("popover.warning.pointer", failures),
                   primary: (L.t("popover.openSystemSettings"), { actions.openAccessibilitySettings() }))
        } else if let error = model.lastError {
            Banner(kind: .warning, text: error, primary: (L.t("common.dismiss"), { model.lastError = nil }))
        }
    }

    private var quickActions: some View {
        HStack(spacing: 8) {
            if model.manualPause != nil {
                Button {
                    actions.resume()
                } label: {
                    Label(L.t("popover.resume"), systemImage: "play.fill")
                }
                .prominentButtonStyle()
            } else {
                Menu {
                    ForEach(PausePreset.allCases) { preset in
                        Button(preset.localizedName) { actions.pause(preset) }
                    }
                } label: {
                    Label(L.t("popover.pause"), systemImage: "pause.fill")
                }
                .fixedSize()
                .disabled(!model.settings.isEnabled)
            }
            Button {
                actions.moveNow()
            } label: {
                Label(L.t("popover.moveNow"), systemImage: "cursorarrow.motionlines")
            }
            Spacer()
        }
        .controlSize(.regular)
    }

    private var statsRow: some View {
        HStack {
            StatTile(title: L.t("stats.today"), value: "\(live.statistics.todayJiggles)")
            StatTile(title: L.t("stats.total"), value: "\(live.statistics.totalJiggles)")
            StatTile(title: L.t("stats.running"), value: StatusPresentation.humanDuration(live.statistics.totalRunningSeconds))
        }
    }

    private var footer: some View {
        HStack {
            Button(L.t("popover.settings")) { actions.openSettings(nil) }
                .keyboardShortcut(",", modifiers: .command)
            Spacer()
            Button(L.t("popover.about")) { actions.openAbout() }
            Button(L.t("popover.quit")) { actions.quit() }
                .keyboardShortcut("q", modifiers: .command)
        }
        .buttonStyle(.link)
        .font(.callout)
    }
}
