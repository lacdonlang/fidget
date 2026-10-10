#if DEBUG
import AppKit
import FidgetCore
import FidgetSystem
import SwiftUI

/// 调试构建专用：在进程内用固定的示例数据渲染各个界面，生成 README 截图。
/// 不读写配置、不需要任何系统权限，结果与运行时的真实状态（星期几、是否闲置）无关。
///
///     Fidget.app/Contents/MacOS/Fidget --render-screenshots <输出目录> [--language zh-Hans] [--appearance dark]
///
/// 外观由 `--appearance light|dark` 指定（默认浅色），与系统当前的外观设置无关；
/// `make screenshots` 每种界面语言、每种外观各渲染一套（docs/images/<语言>/<外观>/）。
@MainActor
final class ScreenshotRenderer: NSObject, NSApplicationDelegate {
    private let outputDirectory: URL
    private let language: String?
    private let appearance: NSAppearance.Name

    init?(arguments: [String]) {
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        guard let output = value(after: "--render-screenshots") else { return nil }
        outputDirectory = URL(fileURLWithPath: output, isDirectory: true)
        language = value(after: "--language")
        appearance = value(after: "--appearance") == "dark" ? .darkAqua : .aqua
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        L.setLanguageOverride(language)
        NSApp.appearance = NSAppearance(named: appearance)
        do {
            try renderAll()
            print("截图已写入 \(outputDirectory.path)")
        } catch {
            FileHandle.standardError.write(Data("截图失败: \(error)\n".utf8))
            exit(1)
        }
        NSApp.terminate(nil)
    }

    private func renderAll() throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let actions = PreviewActions()
        let model = Self.sampleModel()

        let onboarding = HostedWindowController(title: { L.t("onboarding.title") }, size: OnboardingView.size, chrome: .immersive) {
            Self.active(OnboardingView(model: model, actions: actions))
        }
        try capture("onboarding", onboarding.window)
        onboarding.close()

        let about = HostedWindowController(title: { L.t("about.title") }, size: AboutView.size, chrome: .immersive) {
            Self.active(AboutView(actions: actions))
        }
        try capture("about", about.window)
        about.close()

        let navigation = SettingsNavigation()
        let settings = HostedWindowController(title: { L.t("settings.title") }, size: SettingsView.defaultSize, minSize: SettingsView.minimumSize, chrome: .immersive) {
            Self.active(SettingsView(model: model, navigation: navigation, actions: actions))
        }
        for section in SettingsSection.allCases {
            navigation.section = section
            try capture("settings-\(section.rawValue)", settings.window)
        }
        settings.close()

        // 弹出面板的内容放进普通窗口渲染，只截取内容区域。
        let popover = HostedWindowController(title: { AppInfo.name }, size: CGSize(width: 330, height: 300)) {
            // 真实的弹出面板自带背景材质；放进普通窗口截取内容区域时补上窗口底色。
            Self.active(PopoverView(model: model, live: model.live, actions: actions).background(Palette.windowBackground))
        }
        if let window = popover.window, let hosting = window.contentViewController { window.setContentSize(hosting.view.fittingSize) }
        try capture("popover", popover.window, includeTitleBar: false, format: .png)
        let until = Date().addingTimeInterval(30 * 60)
        model.manualPause = ManualPause(until: until)
        model.live.status = .paused(.manual(until: until))
        try capture("popover-paused", popover.window, includeTitleBar: false, format: .png)
    }

    enum ImageFormat: String {
        case png, jpeg = "jpg"
    }

    /// 让窗口完成布局与渲染后画成图片。深色窗口的渐变与光晕存成 PNG 每张两三 MB，
    /// 存成 JPEG（质量 0.88）只有约十分之一，肉眼看不出差别；跟随系统外观的弹出面板仍用 PNG。
    private func capture(_ name: String, _ window: NSWindow?, includeTitleBar: Bool = true, format: ImageFormat = .jpeg) throws {
        guard let window, let content = window.contentView else { throw RenderError(name: name) }
        let view = includeTitleBar ? content.superview ?? content : content
        window.makeKeyAndOrderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw RenderError(name: name) }
        view.cacheDisplay(in: view.bounds, to: rep)
        let data = switch format {
        case .png: rep.representation(using: .png, properties: [:])
        case .jpeg: rep.representation(using: .jpeg, properties: [.compressionFactor: 0.88])
        }
        guard let data else { throw RenderError(name: name) }
        try data.write(to: outputDirectory.appendingPathComponent("\(name).\(format.rawValue)"))
    }

    /// 截图进程不抢用户的焦点，因此窗口不在前台。这里让 SwiftUI 绘制的部分按前台外观渲染；
    /// 开关、标题栏等 AppKit 绘制的部分仍跟随窗口的实际状态。
    private static func active(_ view: some View) -> some View {
        view.environment(\.controlActiveState, .key)
    }

    private static func sampleModel() -> AppModel {
        var settings = Settings.default
        settings.general.hasCompletedOnboarding = true
        settings.general.showCountdownInMenuBar = true
        settings.general.hotKey = HotKey(keyCode: 38, modifiers: [.option, .command])
        settings.rules.appRules = [AppRule(bundleIdentifier: "us.zoom.xos", displayName: "zoom.us")]
        settings.schedule.isEnabled = true
        settings.keepAwake.preventDisplaySleep = true

        let now = Date()
        let statistics = Statistics(totalJiggles: 348, todayJiggles: 12, lastJiggleAt: now.addingTimeInterval(-35), totalRunningSeconds: 5 * 3600 + 42 * 60)
        let model = AppModel(settings: settings, statistics: statistics)
        model.live.status = .active(idleSeconds: 215, jiggleCount: 3, nextJiggleInSeconds: 25)
        model.isAccessibilityTrusted = true
        model.loginItemStatus = .enabled
        model.live.diagnostics = LiveState.Diagnostics(systemIdleSeconds: 35, realIdleSeconds: 215, assertions: settings.keepAwake)
        return model
    }

    private struct RenderError: Error, CustomStringConvertible {
        var name: String
        var description: String { "无法渲染 \(name)" }
    }
}

/// 截图与界面测试时视图需要一个动作对象，但不会被调用。
@MainActor
final class PreviewActions: AppActions {
    func setEnabled(_ enabled: Bool) {}
    func pause(_ preset: PausePreset) {}
    func resume() {}
    func moveNow() {}
    func openSettings(_ section: SettingsSection?) {}
    func openOnboarding() {}
    func finishOnboarding() {}
    func openAbout() {}
    func closePopover() {}
    func quit() {}
    func requestAccessibility() {}
    func openAccessibilitySettings() {}
    func resetAccessibility() {}
    func setLaunchAtLogin(_ enabled: Bool) {}
    func openLoginItemsSettings() {}
    func chooseAppForRule() {}
    func addAppRule(_ app: RunningApp) {}
    func removeAppRule(_ rule: AppRule) {}
    func resetStatistics() {}
    func exportSettings() {}
    func importSettings() {}
    func resetSettings() {}
    func revealSettingsFile() {}
    func revealLogFile() {}
    func copyDiagnostics() {}
    func checkForUpdates() {}
    func openRepository() {}
}
#endif
