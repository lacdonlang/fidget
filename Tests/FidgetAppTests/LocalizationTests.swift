import Foundation
import Testing
@testable import FidgetApp
@testable import FidgetCore

@Suite("本地化")
struct LocalizationTests {
    static var resources: URL { PackagePaths.root.appendingPathComponent("Sources/FidgetApp/Resources") }

    /// 用系统的属性列表解析器读取 .strings，与运行时加载字符串表的方式一致（格式错误会直接失败）。
    static func strings(_ language: String) throws -> [String: String] {
        let url = resources.appendingPathComponent("\(language).lproj/Localizable.strings")
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
        return try #require(plist as? [String: String])
    }

    static func placeholderCount(_ value: String) -> Int { value.components(separatedBy: "%").count - 1 }

    @Test("各语言键集合一致，占位符数量一致")
    func parity() throws {
        let english = try Self.strings("en")
        #expect(english.count > 100)
        for language in L.supportedLanguages where language != "en" {
            let other = try Self.strings(language)
            #expect(Set(english.keys).subtracting(other.keys).isEmpty, "\(language) 缺少: \(Set(english.keys).subtracting(other.keys).sorted())")
            #expect(Set(other.keys).subtracting(english.keys).isEmpty, "en 缺少: \(Set(other.keys).subtracting(english.keys).sorted())")
            for (key, value) in english {
                guard let translated = other[key] else { continue }
                #expect(Self.placeholderCount(value) == Self.placeholderCount(translated), "占位符数量不一致: \(language) \(key)")
            }
        }
    }

    @Test("源码里用到的每个键都存在")
    func keysUsedInCodeExist() throws {
        let english = try Self.strings("en")
        let sourcesRoot = PackagePaths.root.appendingPathComponent("Sources/FidgetApp")
        let enumerator = try #require(FileManager.default.enumerator(at: sourcesRoot, includingPropertiesForKeys: nil))
        let regex = try NSRegularExpression(pattern: #"L\.[tf]\("([^"\\]+)"#)
        var used = Set<String>()
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                used.insert(String(text[Range(match.range(at: 1), in: text)!]))
            }
        }
        #expect(used.count > 80)
        // 以 "." 结尾的是 "pattern.\(rawValue)" 之类的动态前缀，下面单独校验。
        let missing = used.filter { !$0.hasSuffix(".") && english[$0] == nil }.sorted()
        #expect(missing.isEmpty, "strings 缺少: \(missing)")
        for pattern in MovementPattern.allCases { #expect(english["pattern.\(pattern.rawValue)"] != nil) }
        for preset in PausePreset.allCases { #expect(english["pause.\(preset.rawValue)"] != nil) }
        for section in SettingsSection.allCases {
            #expect(english["section.\(section.rawValue)"] != nil)
            #expect(english["section.\(section.rawValue).subtitle"] != nil)
        }
        for style in MenuBarIconStyle.allCases { #expect(english["iconStyle.\(style.rawValue)"] != nil) }
        for mode in AppRuleMode.allCases { #expect(english["rules.appMode.\(mode.rawValue)"] != nil) }
        for appearance in AppearancePreference.allCases { #expect(english["appearance.\(appearance.rawValue)"] != nil) }
    }

    @Test("界面语言对应的区域设置：语言取覆盖值，地区沿用系统")
    func localeForLanguage() {
        #expect(L.locale(forLanguage: nil) == Locale.autoupdatingCurrent)
        let chinese = L.locale(forLanguage: "zh-Hans") // 地区为 CN 时会规范化成等价的 zh_CN
        #expect(chinese.languageCode == "zh")
        #expect(chinese.regionCode == Locale.current.regionCode)
        #expect(L.locale(forLanguage: "en").languageCode == "en")
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = chinese
        #expect(calendar.weekdaySymbols.first == "星期日")
    }

    @Test("按语言取资源包，不触碰全局状态")
    func languageBundles() {
        #expect(L.t("popover.quit", bundle: L.bundle(forLanguage: "zh-Hans")) == "退出")
        #expect(L.t("popover.quit", bundle: L.bundle(forLanguage: "en")) == "Quit")
        #expect(L.bundle(forLanguage: "xx-YY") == L.bundle(forLanguage: nil))
        #expect(L.t("no.such.key", bundle: L.bundle(forLanguage: "en")) == "no.such.key")
        #expect(L.f("about.version", "1.0", "7") == L.t("about.version").replacingOccurrences(of: "%@ (%@)", with: "1.0 (7)"))
    }
}
