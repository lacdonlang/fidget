import AppKit
import FidgetSystem
import Foundation

/// 应用元信息。
enum AppInfo {
    static let name = "Fidget"
    static let repositoryURL = URL(string: "https://github.com/lacdonlang/fidget")!
    static let releasesURL = URL(string: "https://github.com/lacdonlang/fidget/releases/latest")!

    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    static var isBundled: Bool { Bundle.main.isAppBundle }

    @MainActor
    static var iconImage: NSImage {
        if let icon = NSApp?.applicationIconImage, isBundled { return icon }
        return NSImage(systemSymbolName: "cursorarrow.motionlines", accessibilityDescription: name) ?? NSImage()
    }
}
