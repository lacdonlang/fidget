import AppKit
import FidgetCore
import FidgetSystem
import UniformTypeIdentifiers

/// 应用控制中枢：装配服务、驱动引擎、管理窗口，并实现所有界面动作。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, AppActions {
    private var services: AppServices!
    private var model: AppModel!
    private var driver: EngineDriver!
    private var statusItem: StatusItemController!
    private let settingsNavigation = SettingsNavigation()
    private var settingsWindow: HostedWindowController?
    private var onboardingWindow: HostedWindowController?
    private var aboutWindow: HostedWindowController?
    private var updater: UpdateController?
    private var saveTask: Task<Void, Never>?
    private var statisticsTimer: Timer?
    private var savedStatistics: Statistics?
    private var terminationSignal: DispatchSourceSignal?

    // MARK: - 生命周期

    func applicationDidFinishLaunching(_ notification: Notification) {
        let services = AppServices.live()
        self.services = services

        let settings = load(services.settingsStore, fallback: .default)
        var statistics = load(services.statisticsStore, fallback: Statistics())
        if statistics.firstLaunchAt == nil { statistics.firstLaunchAt = Date() }

        if settings.advanced.fileLoggingEnabled { Log.shared.enableFileLogging() }
        L.setLanguageOverride(settings.general.languageOverride)
        NSApp.appearance = settings.general.appearance.nsAppearance
        Log.shared.info("Fidget \(AppInfo.version) (\(AppInfo.build)) 启动，bundled=\(AppInfo.isBundled)", category: .app)

        let model = AppModel(settings: settings, statistics: statistics)
        self.model = model
        model.onSettingsChanged = { [weak self] old, new in self?.settingsDidChange(from: old, to: new) }

        driver = EngineDriver(model: model, services: services)
        statusItem = StatusItemController(model: model, actions: self)
        updater = UpdateController(state: model.updates)

        services.hotKeys?.onTrigger = { [weak self] in self?.driver.toggle() }
        services.hotKeys?.register(settings.general.hotKey)
        services.loginItems?.migrateLaunchAgentIfNeeded()
        refreshLoginItemStatus()

        driver.start()
        statisticsTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveStatistics() }
        }

        if !settings.general.hasCompletedOnboarding || !model.isAccessibilityTrusted {
            openOnboarding()
        }
        installTerminationHandler()
    }

    private func load<Store: ValueStore>(_ store: Store, fallback: Store.Value) -> Store.Value {
        do { return try store.load() } catch {
            Log.shared.error("读取 \(Store.Value.self) 失败，使用默认值: \(error)", category: .app)
            return fallback
        }
    }

    /// 让 `killall Fidget` / SIGTERM 也走正常退出流程（保存设置与统计、释放断言）。
    private func installTerminationHandler() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated { NSApp.terminate(nil) }
        }
        source.resume()
        terminationSignal = source
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let command = AppCommandParser.parse(url) else {
                Log.shared.error("无法识别的 URL: \(url)", category: .app)
                continue
            }
            handle(command)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusItem.showPopover()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        saveSettingsNow()
        saveStatistics()
        driver.stop()
        Log.shared.info("退出", category: .app)
    }

    // MARK: - 命令

    func handle(_ command: AppCommand) {
        switch command {
        case .enable: driver.setEnabled(true)
        case .disable: driver.setEnabled(false)
        case .toggle: driver.toggle()
        case let .pause(minutes): driver.pause(minutes: minutes)
        case .resume: driver.resume()
        case .moveNow: driver.moveNow()
        case let .openSettings(section): openSettings(section.flatMap(SettingsSection.init(rawValue:)))
        case .openOnboarding: openOnboarding()
        }
    }

    // MARK: - 设置变更的副作用（所有设置修改都经过这里）

    private func settingsDidChange(from old: Settings, to new: Settings) {
        scheduleSave()
        driver.setNeedsTick()
        if old.general.hotKey != new.general.hotKey {
            services.hotKeys?.register(new.general.hotKey)
        }
        if old.advanced.fileLoggingEnabled != new.advanced.fileLoggingEnabled {
            new.advanced.fileLoggingEnabled ? Log.shared.enableFileLogging() : Log.shared.disableFileLogging()
        }
        if old.general.languageOverride != new.general.languageOverride {
            L.setLanguageOverride(new.general.languageOverride)
        }
        if old.general.appearance != new.general.appearance {
            // 整个应用（设置等窗口、弹出面板、菜单）随之切换；菜单栏图标跟随菜单栏，不受影响。
            NSApp.appearance = new.general.appearance.nsAppearance
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self?.saveSettingsNow()
        }
    }

    private func saveSettingsNow() {
        saveTask?.cancel()
        do {
            try services.settingsStore.save(model.settings)
        } catch {
            model.lastError = L.f("errors.settingsSave", error.localizedDescription)
            Log.shared.error("保存设置失败: \(error)", category: .app)
        }
    }

    /// 统计没变就不重写文件（关闭、暂停、锁屏期间每分钟的定时保存都会落到这里）。
    private func saveStatistics() {
        let statistics = model.live.statistics
        guard statistics != savedStatistics else { return }
        do {
            try services.statisticsStore.save(statistics)
            savedStatistics = statistics
        } catch {
            Log.shared.error("保存统计失败: \(error)", category: .app)
        }
    }

    private func refreshLoginItemStatus() {
        model.loginItemStatus = services.loginItems?.status ?? .unavailable
    }

    // MARK: - AppActions：引擎

    func setEnabled(_ enabled: Bool) { driver.setEnabled(enabled) }
    func pause(_ preset: PausePreset) { driver.pause(preset) }
    func resume() { driver.resume() }
    func moveNow() { driver.moveNow() }

    // MARK: - AppActions：窗口

    func openSettings(_ section: SettingsSection?) {
        if let section { settingsNavigation.section = section }
        present(&settingsWindow) {
            HostedWindowController(title: { L.t("settings.title") }, size: SettingsView.defaultSize, minSize: SettingsView.minimumSize, chrome: .immersive) { [unowned self] in
                SettingsView(model: self.model, navigation: self.settingsNavigation, actions: self)
            }
        }
    }

    func openOnboarding() {
        present(&onboardingWindow) {
            HostedWindowController(title: { L.t("onboarding.title") }, size: OnboardingView.size, chrome: .immersive) { [unowned self] in
                OnboardingView(model: self.model, actions: self)
            }
        }
    }

    func finishOnboarding() {
        model.settings.general.hasCompletedOnboarding = true
        onboardingWindow?.close()
    }

    func openAbout() {
        present(&aboutWindow) {
            HostedWindowController(title: { L.t("about.title") }, size: AboutView.size, chrome: .immersive) { [unowned self] in
                AboutView(actions: self)
            }
        }
    }

    private func present(_ window: inout HostedWindowController?, make: () -> HostedWindowController) {
        closePopover()
        if window == nil { window = make() }
        window?.present()
    }

    func closePopover() { statusItem.closePopover() }

    func quit() { NSApp.terminate(nil) }

    // MARK: - AppActions：权限与登录项

    func requestAccessibility() { services.accessibility.requestPermission() }

    func openAccessibilitySettings() { services.accessibility.openSystemSettings() }

    func resetAccessibility() { Task { await services.accessibility.resetPermission() } }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try services.loginItems?.setEnabled(enabled)
        } catch {
            model.lastError = L.f("errors.loginItem", error.localizedDescription)
            Log.shared.error("设置登录项失败: \(error)", category: .system)
        }
        refreshLoginItemStatus()
    }

    func openLoginItemsSettings() { services.loginItems?.openSystemSettings() }

    // MARK: - AppActions：应用规则

    func chooseAppForRule() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = L.t("rules.chooseApp.prompt")
        NSApp.bringToFront()
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let app = RunningApps.app(at: url) { addAppRule(app) }
        }
    }

    func addAppRule(_ app: RunningApp) {
        guard !model.settings.rules.appRules.contains(where: { $0.bundleIdentifier == app.bundleIdentifier }) else { return }
        model.settings.rules.appRules.append(AppRule(bundleIdentifier: app.bundleIdentifier, displayName: app.name))
    }

    func removeAppRule(_ rule: AppRule) {
        model.settings.rules.appRules.removeAll { $0.bundleIdentifier == rule.bundleIdentifier }
    }

    // MARK: - AppActions：高级

    func resetStatistics() {
        model.live.statistics.reset()
        saveStatistics()
    }

    func exportSettings() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Fidget Settings.json"
        NSApp.bringToFront()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try JSONFileStore.settings(at: url).save(model.settings)
        } catch {
            model.lastError = L.f("errors.settingsSave", error.localizedDescription)
        }
    }

    func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        NSApp.bringToFront()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            // 不用 load()：它会把读不懂的文件改名备份，而这里是用户自己挑的文件。
            model.settings = try JSONFileStore<Settings>.decode(Data(contentsOf: url)).validated()
        } catch {
            model.lastError = L.f("errors.import", error.localizedDescription)
            Log.shared.error("导入设置失败: \(error)", category: .app)
        }
    }

    func resetSettings() {
        var defaults = Settings.default
        defaults.general.hasCompletedOnboarding = true
        model.settings = defaults
    }

    func revealSettingsFile() {
        saveSettingsNow()
        NSWorkspace.shared.activateFileViewerSelecting([AppDirectories.settingsFile])
    }

    func revealLogFile() {
        if let url = Log.shared.fileURL {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(AppDirectories.logsDirectory)
        }
    }

    func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(DiagnosticsReport.text(model: model), forType: .string)
    }

    /// 在线更新可用时由 Sparkle 检查；调试构建等不能在线更新时打开发布页。
    func checkForUpdates() {
        closePopover()
        if updater?.checkForUpdates() != true { NSWorkspace.shared.open(AppInfo.releasesURL) }
    }

    func setAutomaticUpdateChecks(_ enabled: Bool) { updater?.setAutomaticallyChecks(enabled) }

    func setAutomaticUpdateInstalls(_ enabled: Bool) { updater?.setAutomaticallyInstalls(enabled) }
    func openRepository() { NSWorkspace.shared.open(AppInfo.repositoryURL) }
}
