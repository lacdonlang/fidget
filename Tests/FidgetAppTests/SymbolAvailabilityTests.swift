import Foundation
import Testing
@testable import FidgetApp
@testable import FidgetCore

/// 编译器查不出 SF Symbols 在旧系统上是否存在；菜单栏图标取到不存在的符号会直接变成空白。
/// 这里用系统自带的 SF Symbols 版本表，逐个检查源码里的符号在最低支持的 macOS 11 上是否可用。
@Suite("SF Symbols 在 macOS 11 上可用")
struct SymbolAvailabilityTests {
    static let table = URL(fileURLWithPath: "/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/name_availability.plist")
    static let hasTable = FileManager.default.fileExists(atPath: table.path)

    /// 符号名 → 首次出现的 macOS 版本。
    static func introductions() throws -> [String: String] {
        let plist = try #require(NSDictionary(contentsOf: table) as? [String: Any])
        let symbols = try #require(plist["symbols"] as? [String: String])
        let releases = try #require(plist["year_to_release"] as? [String: [String: String]])
        return symbols.compactMapValues { releases[$0]?["macOS"] }
    }

    static func availableOnMinimumOS(_ version: String) -> Bool {
        version.compare("11.0", options: .numeric) != .orderedDescending
    }

    /// 源码中的每处符号字面量：(符号名, 文件名, 是否直接包在 `Symbols.name(...)` 里)。
    static func symbolLiterals(known: [String: String]) throws -> [(name: String, file: String, wrapped: Bool)] {
        let root = PackagePaths.root.appendingPathComponent("Sources/FidgetApp")
        let enumerator = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        let regex = try NSRegularExpression(pattern: #"(Symbols\.name\()?"([a-z0-9]+(?:\.[a-z0-9]+)*)""#)
        var result: [(String, String, Bool)] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                let name = String(text[Range(match.range(at: 2), in: text)!])
                guard known[name] != nil else { continue }
                result.append((name, url.lastPathComponent, match.range(at: 1).location != NSNotFound))
            }
        }
        return result
    }

    @Test("每个符号要么 macOS 11 就有，要么登记了 macOS 11 就有的替代品", .enabled(if: hasTable))
    func everySymbolWorksOnMinimumOS() throws {
        let introduced = try Self.introductions()
        let literals = try Self.symbolLiterals(known: introduced)
        #expect(Set(literals.map(\.name)).count > 20)
        for name in Set(literals.map(\.name)).sorted() {
            let version = introduced[name]!
            guard !Self.availableOnMinimumOS(version) else { continue }
            let fallback = Symbols.fallbacks[name]
            #expect(fallback != nil, "\(name) 需要 macOS \(version)，请在 Symbols.fallbacks 登记 macOS 11 上的替代品")
            if let fallback {
                #expect(introduced[fallback].map(Self.availableOnMinimumOS) == true, "\(name) 的替代品 \(fallback) 在 macOS 11 上也不存在")
            }
        }
        for (name, fallback) in Symbols.fallbacks {
            #expect(introduced[name] != nil && introduced[fallback] != nil, "Symbols.fallbacks 里有拼错的符号: \(name) → \(fallback)")
        }
    }

    /// 菜单栏图标经 `StatusPresentation.symbol` 统一换名，其他地方用到新符号必须写成 `Symbols.name("…")`。
    @Test("新系统才有的符号都经过替代品转换", .enabled(if: hasTable))
    func newerSymbolsAreResolved() throws {
        let introduced = try Self.introductions()
        let exempt: Set<String> = ["Symbols.swift", "StatusPresentation.swift"]
        let offenders = try Self.symbolLiterals(known: introduced)
            .filter { !Self.availableOnMinimumOS(introduced[$0.name]!) && !$0.wrapped && !exempt.contains($0.file) }
            .map { "\($0.file): \($0.name)" }
        #expect(offenders.isEmpty, "这些地方直接使用了新系统才有的符号: \(offenders)")
    }

    @Test("缺少符号时换成替代品，有则原样使用")
    func fallbackResolution() {
        #expect(Symbols.name("computermouse", isAvailable: { _ in false }) == "cursorarrow")
        #expect(Symbols.name("cursorarrow.slash", isAvailable: { _ in false }) == "cursorarrow")
        #expect(Symbols.name("computermouse", isAvailable: { _ in true }) == "computermouse")
        #expect(Symbols.name("gearshape", isAvailable: { _ in false }) == "gearshape") // 没登记的原样返回
        #expect(Symbols.isAvailable("cursorarrow"))
        #expect(!Symbols.isAvailable("no.such.symbol"))
    }

    @Test("当前系统能显示的菜单栏图标样式")
    func availableIconStyles() {
        let available = MenuBarIconStyle.available
        #expect(available.contains(.cursor))
        #expect(available.allSatisfy { Symbols.isAvailable(StatusPresentation.preferredSymbol($0, .active)) })
    }
}
