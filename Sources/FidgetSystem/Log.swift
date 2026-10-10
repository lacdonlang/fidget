import FidgetCore
import Foundation
import os

/// 统一日志：始终写入 os.log；用户开启文件日志后同时写入 ~/Library/Logs/Fidget/fidget.log。
public final class Log: Sendable {
    public enum Category: String, CaseIterable, Sendable { case app, engine, system }

    public static let subsystem = "com.lacdon.fidget"
    public static let shared = Log()

    private let loggers: [Category: Logger]
    private let sink = Locked<FileLogSink?>(nil)

    private init() {
        loggers = Dictionary(uniqueKeysWithValues: Category.allCases.map { ($0, Logger(subsystem: Log.subsystem, category: $0.rawValue)) })
    }

    public var fileURL: URL? { sink.withLock { $0?.url } }

    public func enableFileLogging(directory: URL = AppDirectories.logsDirectory) {
        sink.withLock { current in
            guard current == nil else { return }
            current = FileLogSink(directory: directory)
        }
        info("文件日志已开启", category: .app)
    }

    public func disableFileLogging() {
        sink.withLock { $0 = nil }
    }

    public func info(_ message: String, category: Category = .app) { log(.info, "INFO", message, category) }
    public func error(_ message: String, category: Category = .app) { log(.error, "ERROR", message, category) }
    public func debug(_ message: String, category: Category = .app) { log(.debug, "DEBUG", message, category) }

    private func log(_ type: OSLogType, _ label: String, _ message: String, _ category: Category) {
        loggers[category]?.log(level: type, "\(message, privacy: .public)")
        sink.withLock { $0?.write("\(label) [\(category.rawValue)] \(message)") }
    }
}

/// 简单的文件日志：保持文件句柄打开并在内存里记录大小，超过 1 MB 轮转一次。所有访问都经由 Log 的锁串行化。
final class FileLogSink: @unchecked Sendable {
    let url: URL
    private let maxBytes: UInt64 = 1_000_000
    private var handle: FileHandle?
    private var size: UInt64 = 0
    private let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    init(directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("fidget.log")
        open()
    }

    deinit { try? handle?.close() }

    func write(_ line: String) {
        let data = Data("\(formatter.string(from: Date())) \(line)\n".utf8)
        if size > maxBytes { rotate() }
        guard let handle else { return }
        try? handle.write(contentsOf: data)
        size += UInt64(data.count)
    }

    private func open() {
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        handle = try? FileHandle(forWritingTo: url)
        size = (try? handle?.seekToEnd()) ?? 0
    }

    private func rotate() {
        try? handle?.close()
        let rotated = url.deletingPathExtension().appendingPathExtension("1.log")
        try? FileManager.default.removeItem(at: rotated)
        try? FileManager.default.moveItem(at: url, to: rotated)
        open()
    }
}
