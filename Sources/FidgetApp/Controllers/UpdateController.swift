import AppKit
import Combine
import Sparkle

/// 在线更新（Sparkle 2）：定期读取 GitHub Release 上的 appcast.xml，有新版本时下载，
/// 校验 EdDSA 签名与开发者签名后替换应用并重新启动。更新源与公钥写在 Info.plist（SUFeedURL / SUPublicEDKey）。
///
/// 只在打包好的发布构建里启用：调试构建与 `swift run` 不检查更新，免得开发中的版本被替换成正式版。
/// “自动检查”“自动安装”两个开关由 Sparkle 自己存进 UserDefaults；这里只把它们的当前值同步到 `UpdateState` 给界面显示。
@MainActor
final class UpdateController {
    private let controller: SPUStandardUpdaterController?

    init(state: UpdateState) {
        #if DEBUG
        controller = nil
        #else
        controller = AppInfo.isBundled ? SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil) : nil
        #endif
        guard let updater = controller?.updater else { return }
        state.isAvailable = true
        updater.publisher(for: \.automaticallyChecksForUpdates).removeDuplicates().assign(to: &state.$automaticallyChecks)
        updater.publisher(for: \.automaticallyDownloadsUpdates).removeDuplicates().assign(to: &state.$automaticallyInstalls)
        updater.publisher(for: \.lastUpdateCheckDate).assign(to: &state.$lastCheck)
    }

    /// 立即检查（显示 Sparkle 的检查与更新窗口）；不能在线更新时返回 false。
    func checkForUpdates() -> Bool {
        guard let controller else { return false }
        controller.checkForUpdates(nil)
        return true
    }

    func setAutomaticallyChecks(_ enabled: Bool) {
        controller?.updater.automaticallyChecksForUpdates = enabled
    }

    func setAutomaticallyInstalls(_ enabled: Bool) {
        controller?.updater.automaticallyDownloadsUpdates = enabled
    }
}
