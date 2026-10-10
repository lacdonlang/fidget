import FidgetCore
import Foundation

/// 本地化入口。
/// - 打包后的 .app 把 .lproj 直接放在 Contents/Resources 下，主包可识别语言；
/// - `swift run` 开发模式下回退到 SwiftPM 资源包；
/// - 用户可在设置里覆盖界面语言。切换后 `LanguageState` 发出通知：窗口与弹出面板的根视图整体重建（见 `LocalizedRoot`），
///   窗口标题随之更新；菜单栏图标随设置变化重绘。日期与时长的格式化也跟随界面语言而不是系统语言。
enum L {
    static let supportedLanguages = ["en", "zh-Hans"]

    private static let baseBundle: Bundle = {
        if Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: "en") != nil {
            return Bundle.main
        }
        return Bundle.module
    }()

    private static let current = Locked<(bundle: Bundle, locale: Locale)>((baseBundle, .autoupdatingCurrent))

    /// 指定语言的资源包；nil 或不支持的语言返回跟随系统的基础包。
    /// 通过“该语言的 Localizable.strings 在哪”来定位 .lproj，不依赖资源包的目录布局
    /// （不同版本的 SwiftPM 生成的资源包结构不同，直接按名字找 .lproj 目录在旧版上会失败）。
    static func bundle(forLanguage language: String?) -> Bundle {
        guard let language,
              let strings = baseBundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: language)
        else { return baseBundle }
        let directory = (strings as NSString).deletingLastPathComponent
        guard (directory as NSString).lastPathComponent.lowercased() == "\(language).lproj".lowercased(),
              let languageBundle = Bundle(path: directory)
        else { return baseBundle }
        return languageBundle
    }

    /// 界面语言对应的区域设置：语言取覆盖值，地区沿用系统设置；nil 表示完全跟随系统。
    static func locale(forLanguage language: String?) -> Locale {
        guard let language else { return .autoupdatingCurrent }
        guard let region = Locale.current.regionCode else { return Locale(identifier: language) }
        return Locale(identifier: "\(language)_\(region)")
    }

    /// 覆盖界面语言；传 nil 恢复跟随系统。
    @MainActor
    static func setLanguageOverride(_ language: String?) {
        let value = (bundle(forLanguage: language), locale(forLanguage: language))
        current.withLock { $0 = value }
        LanguageState.shared.identifier = language ?? LanguageState.system
    }

    /// 当前界面语言的区域设置，供日期、时长等格式化使用。
    static var locale: Locale { current.withLock { $0.locale } }

    /// 系统日历换上界面语言（星期名称等随之变化），保留用户设定的每周第一天。
    static var calendar: Calendar {
        var calendar = Calendar.current
        let firstWeekday = calendar.firstWeekday
        calendar.locale = locale
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    static func t(_ key: String, bundle: Bundle? = nil) -> String {
        (bundle ?? current.withLock { $0.bundle }).localizedString(forKey: key, value: key, table: nil)
    }

    static func f(_ key: String, _ args: CVarArg...) -> String {
        String(format: t(key), locale: locale, arguments: args)
    }
}

/// 当前界面语言的可观察标识。只在主线程修改。
@MainActor
final class LanguageState: ObservableObject {
    static let system = "system"
    static let shared = LanguageState()

    @Published fileprivate(set) var identifier = LanguageState.system
}
