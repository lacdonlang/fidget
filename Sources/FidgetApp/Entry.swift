import AppKit

/// 可执行目标的入口。
public enum FidgetAppEntry {
    @MainActor
    public static func run() {
        let app = NSApplication.shared
        let delegate = makeDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }

    @MainActor
    private static func makeDelegate() -> NSApplicationDelegate {
        #if DEBUG
        if let renderer = ScreenshotRenderer(arguments: CommandLine.arguments) { return renderer }
        #endif
        return AppDelegate()
    }
}
