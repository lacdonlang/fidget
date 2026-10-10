import Foundation
import Testing
@testable import FidgetApp

/// 在线更新的配置：Info.plist 里的更新源与公钥，发布流程生成的 appcast.xml。
@Suite("在线更新")
struct UpdateFeedTests {
    static let root = PackagePaths.root

    static func infoPlist() throws -> [String: Any] {
        let data = try Data(contentsOf: root.appendingPathComponent("Resources/Info.plist"))
        return try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    static var version: String {
        get throws { try String(contentsOf: root.appendingPathComponent("VERSION"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    @Test("更新源指向最新 Release 的 appcast.xml，公钥是 32 字节的 Ed25519 公钥")
    func infoPlistKeys() throws {
        let plist = try Self.infoPlist()
        #expect(plist["SUFeedURL"] as? String == "https://github.com/lacdonlang/fidget/releases/latest/download/appcast.xml")
        let key = try #require(plist["SUPublicEDKey"] as? String)
        #expect(Data(base64Encoded: key)?.count == 32)
        #expect(plist["SUEnableAutomaticChecks"] as? Bool == true)
    }

    @Test("appcast.xml：版本、构建号、最低系统、下载地址、签名与更新说明")
    func appcast() throws {
        let version = try Self.version
        let parts = version.split(separator: ".").compactMap { Int($0) }
        let build = parts[0] * 10000 + parts[1] * 100 + parts[2]
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("appcast-\(UUID().uuidString).xml")
        defer { try? FileManager.default.removeItem(at: output) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [Self.root.appendingPathComponent("scripts/make-appcast.sh").path, "Fidget-\(version).zip", output.path]
        process.environment = ["SPARKLE_SIGNATURE": #"sparkle:edSignature="c2lnbmF0dXJl" length="1234""#, "PATH": "/usr/bin:/bin"]
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "make-appcast.sh 失败（CHANGELOG.md 里要有 ## \(version) 一节）")

        let document = try XMLDocument(contentsOf: output)
        func text(_ path: String) throws -> String? { try document.nodes(forXPath: path).first?.stringValue }
        #expect(try text("/rss/channel/item/sparkle:version") == "\(build)")
        #expect(try text("/rss/channel/item/sparkle:shortVersionString") == version)
        #expect(try text("/rss/channel/item/sparkle:minimumSystemVersion") == "11.0")
        #expect(try text("/rss/channel/item/enclosure/@url") == "https://github.com/lacdonlang/fidget/releases/download/v\(version)/Fidget-\(version).zip")
        #expect(try text("/rss/channel/item/enclosure/@sparkle:edSignature") == "c2lnbmF0dXJl")
        #expect(try text("/rss/channel/item/enclosure/@length") == "1234")
        #expect(try text("/rss/channel/item/description")?.contains("<li>") == true)
    }
}
