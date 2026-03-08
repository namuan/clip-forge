import Foundation

enum LogLevel: String, Sendable {
    case debug = "DEBUG"
    case info  = "INFO"
    case warn  = "WARN"
    case error = "ERROR"
}

final class Logger: @unchecked Sendable {
    static let shared = Logger()

    private let appName = "ClipForge"
    private let logDirectory: URL
    private let dateFormatter: DateFormatter
    private let fileManager = FileManager.default
    private var currentLogFile: URL?
    private var currentLogDate: String?
    private let queue = DispatchQueue(label: "com.clipforge.logger", qos: .utility)
    private let lock = NSLock()

    private init() {
        let homeDir = fileManager.homeDirectoryForCurrentUser
        logDirectory = homeDir.appendingPathComponent("Library/Logs/\(appName)")

        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        try? fileManager.createDirectory(at: logDirectory, withIntermediateDirectories: true)
    }

    private func logFileURL(for date: String) -> URL {
        logDirectory.appendingPathComponent("\(appName)-\(date).log")
    }

    private func rotateLogFileIfNeeded() {
        let today = dateFormatter.string(from: Date())
        lock.lock()
        defer { lock.unlock() }
        if currentLogDate != today {
            currentLogDate = today
            currentLogFile = logFileURL(for: today)
        }
    }

    private func formatMessage(_ level: LogLevel, _ message: String, file: String, function: String, line: Int) -> String {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let filename = (file as NSString).lastPathComponent
        return "[\(timestamp)] [\(level.rawValue)] [\(filename):\(line)] \(function) - \(message)"
    }

    func log(_ level: LogLevel, _ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.rotateLogFileIfNeeded()

            self.lock.lock()
            let logFile = self.currentLogFile
            self.lock.unlock()

            guard let fileURL = logFile else { return }

            let formattedMessage = self.formatMessage(level, message, file: file, function: function, line: line)
            let logLine = formattedMessage + "\n"

            if let data = logLine.data(using: .utf8) {
                if self.fileManager.fileExists(atPath: fileURL.path) {
                    if let fileHandle = try? FileHandle(forWritingTo: fileURL) {
                        fileHandle.seekToEndOfFile()
                        fileHandle.write(data)
                        fileHandle.closeFile()
                    }
                } else {
                    try? data.write(to: fileURL)
                }
            }
        }
    }

    func cleanupOldLogs(keepDays: Int = 7) {
        queue.async { [weak self] in
            guard let self = self else { return }

            let cutoffDate = Calendar.current.date(byAdding: .day, value: -keepDays, to: Date())!
            let cutoffString = self.dateFormatter.string(from: cutoffDate)

            guard let files = try? self.fileManager.contentsOfDirectory(at: self.logDirectory, includingPropertiesForKeys: nil) else { return }

            for file in files where file.lastPathComponent.hasSuffix(".log") {
                let name = file.deletingPathExtension().lastPathComponent
                if let datePart = name.split(separator: "-").last,
                   String(datePart) < cutoffString {
                    try? self.fileManager.removeItem(at: file)
                }
            }
        }
    }

    var logsDirectory: URL {
        logDirectory
    }
}

func CFLog(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
    Task {
        await MainActor.run {
            Logger.shared.log(level, message, file: file, function: function, line: line)
        }
    }
}

func CFLogDebug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    CFLog(message, level: .debug, file: file, function: function, line: line)
}

func CFLogInfo(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    CFLog(message, level: .info, file: file, function: function, line: line)
}

func CFLogWarn(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    CFLog(message, level: .warn, file: file, function: function, line: line)
}

func CFLogError(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    CFLog(message, level: .error, file: file, function: function, line: line)
}
