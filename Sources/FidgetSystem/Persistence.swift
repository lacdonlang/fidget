import FidgetCore
import Foundation

/// 应用目录。可用环境变量 FIDGET_CONFIG_DIR 覆盖（测试与脚本使用），此时日志也写到其下的 Logs/。
public enum AppDirectories {
    public static let appName = "Fidget"

    private static var overrideDirectory: URL? {
        guard let path = ProcessInfo.processInfo.environment["FIDGET_CONFIG_DIR"], !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    public static var configDirectory: URL {
        if let overrideDirectory { return overrideDirectory }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent(appName, isDirectory: true)
    }

    public static var logsDirectory: URL {
        if let overrideDirectory { return overrideDirectory.appendingPathComponent("Logs", isDirectory: true) }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/\(appName)", isDirectory: true)
    }

    public static var settingsFile: URL { configDirectory.appendingPathComponent("settings.json") }
    public static var statisticsFile: URL { configDirectory.appendingPathComponent("statistics.json") }
}

extension Bundle {
    /// 是否以 .app 形式运行（`swift run` / `swift test` 时为 false）。
    public var isAppBundle: Bool { bundleURL.pathExtension == "app" }
}

/// JSON 文件存储：原子写入；文件不存在时返回默认值；文件损坏时备份为 `*.corrupt-<时间戳>.json` 后返回默认值。
/// 读写都经过 `normalize`（设置用它做范围校验）。
public struct JSONFileStore<Value: Codable & Sendable>: ValueStore {
    public let url: URL
    private let defaultValue: Value
    private let normalize: @Sendable (Value) -> Value

    public init(url: URL, default defaultValue: Value, normalize: @escaping @Sendable (Value) -> Value = { $0 }) {
        self.url = url
        self.defaultValue = defaultValue
        self.normalize = normalize
    }

    public func load() throws -> Value {
        guard FileManager.default.fileExists(atPath: url.path) else { return defaultValue }
        let data = try Data(contentsOf: url)
        do {
            return normalize(try Self.decode(data))
        } catch {
            let backup = url.deletingPathExtension().appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: url, to: backup)
            Log.shared.error("配置文件损坏，已备份到 \(backup.lastPathComponent): \(error)", category: .system)
            return defaultValue
        }
    }

    public func save(_ value: Value) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encode(normalize(value)).write(to: url, options: .atomic)
    }

    /// 文件格式的唯一定义：导入导出与读写共用。
    public static func encode(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    public static func decode(_ data: Data) throws -> Value {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Value.self, from: data)
    }
}

extension JSONFileStore where Value == Settings {
    public static func settings(at url: URL = AppDirectories.settingsFile) -> Self {
        Self(url: url, default: .default, normalize: { $0.validated() })
    }
}

extension JSONFileStore where Value == Statistics {
    public static func statistics(at url: URL = AppDirectories.statisticsFile) -> Self {
        Self(url: url, default: Statistics())
    }
}
