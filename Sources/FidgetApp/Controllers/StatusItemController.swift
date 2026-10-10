import AppKit
import Combine
import FidgetCore
import SwiftUI

/// 菜单栏图标：左键弹出面板，右键弹出快捷菜单。图标与倒计时跟随模型自动刷新。
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let model: AppModel
    private unowned let actions: AppActions
    private var lastSymbol: String?
    private var modelSubscription: AnyCancellable?
    private var renderScheduled = false

    init(model: AppModel, actions: AppActions) {
        self.model = model
        self.actions = actions
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(buttonClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
            button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize(for: .small), weight: .regular)
        }

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        // 设置（含图标样式、界面语言）与运行状态任一变化都重绘。
        modelSubscription = model.objectWillChange.merge(with: model.live.objectWillChange)
            .sink { [weak self] _ in self?.setNeedsRender() }
        render()
    }

    /// `objectWillChange` 在值改变之前发出，所以渲染推迟到下一轮 run loop；同一轮里的多次变化只渲染一次。
    private func setNeedsRender() {
        guard !renderScheduled else { return }
        renderScheduled = true
        Task { [weak self] in
            guard let self else { return }
            renderScheduled = false
            render()
        }
    }

    private func render() {
        guard let button = statusItem.button else { return }
        let presentation = StatusPresentation.make(status: model.live.status, settings: model.settings, now: Date())
        if presentation.symbolName != lastSymbol {
            let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
            let image = NSImage(systemSymbolName: presentation.symbolName, accessibilityDescription: presentation.title)
                ?? NSImage(systemSymbolName: "cursorarrow", accessibilityDescription: presentation.title)
            button.image = image?.withSymbolConfiguration(configuration)
            button.image?.isTemplate = true
            lastSymbol = presentation.symbolName
        }
        // 每次赋值（哪怕值相同）都会让菜单栏重新布局，代价约数毫秒，所以只在变化时写入。
        let appearsDisabled = presentation.kind == .off
        if button.appearsDisabled != appearsDisabled { button.appearsDisabled = appearsDisabled }
        let countdown = model.settings.general.showCountdownInMenuBar ? presentation.countdown.map { " " + $0 } : nil
        if button.title != countdown ?? "" { button.title = countdown ?? "" }
        let toolTip = "\(AppInfo.name) · \(presentation.title)\n\(presentation.detail)"
        if button.toolTip != toolTip { button.toolTip = toolTip }
    }

    // MARK: - 点击

    @objc private func buttonClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    /// 面板内容只在显示期间存在：关闭后释放，避免看不见的视图仍随每秒的状态变化重算、播放进度动画。
    /// 显示前按内容的理想尺寸设定面板大小；显示后内容变高变矮（出现横幅时）由 NSHostingController 的尺寸约束带动面板。
    /// 不要把 SwiftUI 里测得的尺寸写回 contentSize：macOS 27 上首次测得的是 0，面板会先按 0 高度定位，
    /// 再被内容向上撑开，伸出屏幕顶端（1.1.0 的问题）。
    func showPopover() {
        guard let button = statusItem.button else { return }
        let content = PopoverView(model: model, live: model.live, actions: actions)
        let hosting = NSHostingController(rootView: LocalizedRoot { content })
        popover.contentViewController = hosting
        popover.contentSize = hosting.view.fittingSize
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.bringToFront()
        popover.contentViewController?.view.window?.makeKey()
    }

    func closePopover() {
        popover.performClose(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        popover.contentViewController = nil
    }

    // MARK: - 右键菜单

    private func showContextMenu() {
        let menu = NSMenu()
        let presentation = StatusPresentation.make(status: model.live.status, settings: model.settings, now: Date())
        let header = NSMenuItem(title: "\(presentation.title) · \(presentation.detail)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        addItem(to: menu, model.settings.isEnabled ? L.t("menu.disable") : L.t("menu.enable"), #selector(toggleEnabled))
        if model.manualPause != nil {
            addItem(to: menu, L.t("popover.resume"), #selector(resume))
        } else {
            let pauseMenu = NSMenu()
            for preset in PausePreset.allCases {
                addItem(to: pauseMenu, preset.localizedName, #selector(pause(_:))).representedObject = preset.rawValue
            }
            menu.addItem(withTitle: L.t("menu.pauseFor"), action: nil, keyEquivalent: "").submenu = pauseMenu
        }
        addItem(to: menu, L.t("popover.moveNow"), #selector(moveNow))
        menu.addItem(.separator())
        addItem(to: menu, L.t("popover.settings"), #selector(openSettings), key: ",")
        addItem(to: menu, L.t("popover.about"), #selector(openAbout))
        menu.addItem(.separator())
        addItem(to: menu, L.t("popover.quit"), #selector(quit), key: "q")

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @discardableResult
    private func addItem(to menu: NSMenu, _ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func toggleEnabled() { actions.setEnabled(!model.settings.isEnabled) }
    @objc private func resume() { actions.resume() }
    @objc private func pause(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let preset = PausePreset(rawValue: raw) { actions.pause(preset) }
    }
    @objc private func moveNow() { actions.moveNow() }
    @objc private func openSettings() { actions.openSettings(nil) }
    @objc private func openAbout() { actions.openAbout() }
    @objc private func quit() { actions.quit() }
}
