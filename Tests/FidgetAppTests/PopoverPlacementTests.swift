import AppKit
import FidgetCore
import Testing
@testable import FidgetApp

/// 真实地弹出菜单栏面板，检查它挂在菜单栏下方，内容变化后仍然如此。
/// 会在菜单栏放一个图标并短暂抢走焦点，所以默认跳过，用 `make ui-test` 运行。
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["FIDGET_UI_TESTS"] == "1", "需要 FIDGET_UI_TESTS=1（make ui-test）"))
struct PopoverPlacementTests {
    @Test func popoverStaysBelowMenuBar() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let model = AppModel(settings: .default)
        model.live.status = .blocked(.accessibilityPermission)
        let actions = PreviewActions()
        let controller = StatusItemController(model: model, actions: actions)
        defer { controller.closePopover() }
        try await Task.sleep(nanoseconds: 1_000_000_000) // 等菜单栏图标就位
        controller.showPopover()
        try await Task.sleep(nanoseconds: 1_000_000_000)

        let statusBarWindow = try #require(app.windows.first { String(describing: type(of: $0)).contains("StatusBar") })
        let popoverWindow = try #require(app.windows.first { String(describing: type(of: $0)).contains("Popover") })
        let screen = try #require(statusBarWindow.screen)
        func expectBelowMenuBar(_ frame: CGRect) {
            #expect(frame.maxY <= statusBarWindow.frame.maxY, "面板伸到了菜单栏上方：\(frame)，菜单栏 \(statusBarWindow.frame)")
            #expect(frame.minY >= screen.frame.minY, "面板超出了屏幕底部：\(frame)")
        }
        let withBanner = popoverWindow.frame
        expectBelowMenuBar(withBanner)

        // 授权后横幅消失：面板变矮，仍挂在菜单栏下方（图标宽度变化时会跟着平移几个点）。
        model.live.status = .watching(idleSeconds: 10, remainingSeconds: 50)
        try await Task.sleep(nanoseconds: 1_000_000_000)
        let withoutBanner = popoverWindow.frame
        #expect(withoutBanner.height < withBanner.height)
        expectBelowMenuBar(withoutBanner)
        withExtendedLifetime(actions) {}
    }
}
