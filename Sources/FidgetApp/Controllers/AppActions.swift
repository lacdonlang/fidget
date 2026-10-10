import FidgetCore
import FidgetSystem
import Foundation

/// 视图可触发的全部动作，由 AppDelegate 实现。
@MainActor
protocol AppActions: AnyObject {
    func setEnabled(_ enabled: Bool)
    func pause(_ preset: PausePreset)
    func resume()
    func moveNow()

    func openSettings(_ section: SettingsSection?)
    func openOnboarding()
    func finishOnboarding()
    func openAbout()
    func closePopover()
    func quit()

    func requestAccessibility()
    func openAccessibilitySettings()
    func resetAccessibility()
    func setLaunchAtLogin(_ enabled: Bool)
    func openLoginItemsSettings()

    func chooseAppForRule()
    func addAppRule(_ app: RunningApp)
    func removeAppRule(_ rule: AppRule)

    func resetStatistics()
    func exportSettings()
    func importSettings()
    func resetSettings()
    func revealSettingsFile()
    func revealLogFile()
    func copyDiagnostics()
    func checkForUpdates()
    func openRepository()
}
