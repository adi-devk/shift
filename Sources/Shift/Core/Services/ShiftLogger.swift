import Foundation
import os.log
import Combine

public enum LogLevel: String, Codable, CaseIterable, Sendable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"

    public var icon: String {
        switch self {
        case .debug: return "ant.fill"
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }
}

public enum LogCategory: String, Codable, CaseIterable, Sendable {
    case engine = "Engine"
    case network = "Network"
    case storage = "Storage"
    case browser = "Browser"
    case sniffer = "Sniffer"
    case widget = "Widget"
    case background = "Background"
    case general = "General"
}

public struct LogEntry: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var timestamp: Date
    public var level: LogLevel
    public var category: LogCategory
    public var message: String
    public var file: String
    public var line: Int

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: LogLevel,
        category: LogCategory,
        message: String,
        file: String = #file,
        line: Int = #line
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.message = message
        self.file = (file as NSString).lastPathComponent
        self.line = line
    }

    public var formattedText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        let dateStr = formatter.string(from: timestamp)
        return "[\(dateStr)] [\(level.rawValue)] [\(category.rawValue)] [\(file):\(line)] \(message)"
    }
}

public final class ShiftLogger: ObservableObject, @unchecked Sendable {
    public static let shared = ShiftLogger()

    @Published public private(set) var entries: [LogEntry] = []
    private let lock = NSLock()
    private let maxEntries = 1000
    private let logFileURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let logsDir = appSupport.appendingPathComponent("Shift/Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        self.logFileURL = logsDir.appendingPathComponent("Shift_Diagnostics.log")

        // Clean up legacy log file from Documents if present
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let legacyLog = docs.appendingPathComponent("Shift_Diagnostics.log")
            try? FileManager.default.removeItem(at: legacyLog)
        }

        loadExistingLogs()
        log(level: .info, category: .general, message: "🚀 Shift Logger initialized. Private diagnostic log stream active.")
    }

    public func log(
        level: LogLevel,
        category: LogCategory,
        message: String,
        file: String = #file,
        line: Int = #line
    ) {
        let entry = LogEntry(level: level, category: category, message: message, file: file, line: line)

        // 1. Apple Unified OS Log
        let osLog = OSLog(subsystem: "com.shift.downloadmanager", category: category.rawValue)
        let osLogType: OSLogType
        switch level {
        case .debug: osLogType = .debug
        case .info: osLogType = .info
        case .warning: osLogType = .default
        case .error: osLogType = .error
        }
        os_log("%{public}@", log: osLog, type: osLogType, entry.formattedText)

        // 2. In-Memory Buffer for UI
        lock.lock()
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        lock.unlock()

        // 3. Append to persistent log file
        appendToLogFile(entry.formattedText + "\n")
    }

    public func debug(_ message: String, category: LogCategory = .general, file: String = #file, line: Int = #line) {
        log(level: .debug, category: category, message: message, file: file, line: line)
    }

    public func info(_ message: String, category: LogCategory = .general, file: String = #file, line: Int = #line) {
        log(level: .info, category: category, message: message, file: file, line: line)
    }

    public func warning(_ message: String, category: LogCategory = .general, file: String = #file, line: Int = #line) {
        log(level: .warning, category: category, message: message, file: file, line: line)
    }

    public func error(_ message: String, category: LogCategory = .general, file: String = #file, line: Int = #line) {
        log(level: .error, category: category, message: message, file: file, line: line)
    }

    public func clearLogs() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
        try? "".write(to: logFileURL, atomically: true, encoding: .utf8)
        log(level: .info, category: .general, message: "🧹 Diagnostic logs cleared by user.")
    }

    public func exportLogsText() -> String {
        lock.lock()
        defer { lock.unlock() }
        return entries.map { $0.formattedText }.joined(separator: "\n")
    }

    public func getLogFileURL() -> URL {
        // Ensure file is up to date
        let text = exportLogsText()
        try? text.write(to: logFileURL, atomically: true, encoding: .utf8)
        return logFileURL
    }

    private func appendToLogFile(_ string: String) {
        guard let data = string.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: logFileURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: logFileURL, options: .atomic)
        }
    }

    private func loadExistingLogs() {
        if let existing = try? String(contentsOf: logFileURL, encoding: .utf8) {
            let lines = existing.components(separatedBy: .newlines).filter { !$0.isEmpty }
            for line in lines.suffix(200) {
                let entry = LogEntry(level: .info, category: .general, message: line)
                entries.append(entry)
            }
        }
    }
}
