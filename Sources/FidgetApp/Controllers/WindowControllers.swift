import AppKit
import Combine
import SwiftUI

/// 用 NSWindow 承载 SwiftUI 的窗口控制器。
/// - 窗口标题由 `title` 提供，界面语言变化时自动更新（`navigationTitle` 到窗口标题的桥接要到 macOS 13 才有）；
/// - 关闭时释放 SwiftUI 内容（否则隐藏的视图仍会随模型每秒重算、动画仍在绘制），下次显示时再重建。
@MainActor
final class HostedWindowController: NSWindowController, NSWindowDelegate {
    enum Chrome {
        /// 普通标题栏，外观跟随系统。
        case standard
        /// 设置、引导与关于窗口：内容延伸到透明标题栏下方、不显示标题文字（界面见 Aurora.swift）。
        case immersive
    }

    private let size: CGSize
    private let title: () -> String
    private let makeContent: () -> NSViewController
    private var languageSubscription: AnyCancellable?

    init<Content: View>(
        title: @escaping () -> String,
        size: CGSize,
        minSize: CGSize? = nil,
        chrome: Chrome = .standard,
        content: @escaping () -> Content
    ) {
        self.size = size
        self.title = title
        makeContent = { NSHostingController(rootView: LocalizedRoot(content: content)) }
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if minSize != nil { style.insert(.resizable) }
        if chrome == .immersive { style.insert(.fullSizeContentView) }
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = title()
        if let minSize { window.contentMinSize = minSize }
        if chrome == .immersive {
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.backgroundColor = Aurora.windowBackground
        }
        super.init(window: window)
        window.delegate = self
        loadContentIfNeeded()
        window.center()
        languageSubscription = LanguageState.shared.$identifier.dropFirst().sink { [weak self] _ in
            // `@Published` 在赋值前发出通知；此时新的语言包已经生效，标题可以直接重取。
            guard let self else { return }
            self.window?.title = self.title()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持从 nib 创建") }

    func present() {
        loadContentIfNeeded()
        NSApp.bringToFront()
        if let window, !window.isVisible { window.center() }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private func loadContentIfNeeded() {
        guard let window, window.contentViewController == nil else { return }
        window.contentViewController = makeContent()
        window.setContentSize(size)
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentViewController = nil
    }
}

/// 界面语言变化时整体重建内容，保证所有经 `L.t` 取文案的子视图（包括 AppKit 包装的控件）都换成新语言，
/// 而不必让每个视图各自订阅语言变化；日期选择器等系统控件的格式也随之跟随界面语言。
struct LocalizedRoot<Content: View>: View {
    @ObservedObject private var language = LanguageState.shared
    let content: () -> Content

    var body: some View {
        content()
            .environment(\.locale, L.locale)
            .id(language.identifier)
    }
}

extension NSApplication {
    /// 把应用带到前台。macOS 14 起改用无参的 `activate()`，旧系统只有 `activate(ignoringOtherApps:)`。
    func bringToFront() {
        if #available(macOS 14, *) {
            activate()
        } else {
            activate(ignoringOtherApps: true)
        }
    }
}
