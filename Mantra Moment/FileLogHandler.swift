import Foundation
import Logging
import Logfmt

/// A log handler that writes log messages to a file with daily rotation
struct FileLogHandler: LogHandler {
    // Thread-safe global log level override
    private static let overrideLock = NSLock()
    private static var overrideLogLevel: Logger.Level?

    private let label: String
    private let logsDirectory: URL
    private let dateFormatter: DateFormatter

    // Current file URL is computed based on rotation strategy
    private var currentFileURL: URL {
        getLogFileURL()
    }

    private var _logLevel: Logger.Level
    var logLevel: Logger.Level {
        get {
            FileLogHandler.overrideLock.lock()
            defer { FileLogHandler.overrideLock.unlock() }
            return FileLogHandler.overrideLogLevel ?? _logLevel
        }
        set { _logLevel = newValue }
    }

    var metadata = Logger.Metadata()
    subscript(metadataKey metadataKey: String) -> Logger.Metadata.Value? {
        get { metadata[metadataKey] }
        set { metadata[metadataKey] = newValue }
    }

    init(label: String, logLevel: Logger.Level = .info) {
        self._logLevel = logLevel
        self.label = label

        // Create a date formatter for timestamping log entries
        self.dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        dateFormatter.timeZone = .gmt

        // Get the logs directory from LogManager's static property
        self.logsDirectory = LogManager.logsDirectory

        do {
            try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        } catch {
            print("Error creating logs directory: \(error.localizedDescription)")
        }
    }

    /// Returns the appropriate log file URL based on daily rotation
    private func getLogFileURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        let dateString = formatter.string(from: Date())
        let filename = "\(label)-\(dateString).log"

        return logsDirectory.appendingPathComponent(filename)
    }

    func log(level: Logger.Level, message: Logger.Message, metadata: Logger.Metadata?, source: String, file: String, function: String, line: UInt) {
        // Only log if the level is at or above the configured level
        guard level >= self.logLevel else { return }

        // Format the log message with timestamp, level, source, and message
        let timestamp = dateFormatter.string(from: Date())
        let metadataString = String.logfmt(self.metadata.merging(metadata ?? [:]) { _, new in new })
        let filename = (file as NSString).lastPathComponent
        let logMessage = "\(timestamp) \(level.rawValue.uppercased()) [\(source)] \(filename):\(line) \(function) \(message)\(metadataString.isEmpty ? "" : " \(metadataString)")"

        // Write to file
        appendToFile(message: logMessage)
    }

    private func appendToFile(message: String) {
        let logMessage = message + "\n"
        let fileURL = currentFileURL // This will compute the current log file based on rotation strategy

        if let data = logMessage.data(using: .utf8) {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: fileURL.path) {
                // Append to existing file
                if let fileHandle = try? FileHandle(forWritingTo: fileURL) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                // Create new file
                try? data.write(to: fileURL, options: .atomic)
            }
        }
    }

    /// Returns the current global log level override
    public static func currentGlobalOverride() -> Logger.Level? {
        overrideLock.lock()
        defer { overrideLock.unlock() }
        return overrideLogLevel
    }

    /// Set global log level override for all FileLogHandlers
    public static func overrideGlobalLogLevel(_ logLevel: Logger.Level?) {
        overrideLock.lock()
        defer { overrideLock.unlock() }
        overrideLogLevel = logLevel
    }
}
