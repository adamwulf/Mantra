import Foundation
import Logging
import Logfmt

/// A log handler that writes log messages to a file with daily rotation
struct FileLogHandler: LogHandler {
    // Static dispatch queue for thread-safe file writing across all instances
    private static let fileWriteQueue = DispatchQueue(label: "com.milestonemade.Mantra.FileLogHandler", autoreleaseFrequency: .workItem)
 
    // Thread-safe global log level override
    private static let overrideLock = NSLock()
    private static var overrideLogLevel: Logger.Level?

    private let label: String
    private let dateFormatter: DateFormatter

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

        do {
            try FileManager.default.createDirectory(at: LogManager.logsDirectory, withIntermediateDirectories: true)
        } catch {
            print("Error creating logs directory: \(error.localizedDescription)")
        }
    }

    func log(level: Logger.Level, message: Logger.Message, metadata: Logger.Metadata?, source: String, file: String, function: String, line: UInt) {
        // Only log if the level is at or above the configured level
        guard level >= self.logLevel else { return }

        // Format the log message with timestamp, level, source, and message
        let timestamp = dateFormatter.string(from: Date())
        let metadataString = String.logfmt(self.metadata.merging(metadata ?? [:]) { _, new in new })
        let filename = ((file as NSString).lastPathComponent as NSString).deletingPathExtension
        let levelStr = level.rawValue.uppercased().padding(toLength: 8, withPad: " ", startingAt: 0)
        let logMessage = "\(timestamp) \(levelStr) [\(label)] \(filename).\(function):\(line) \(message)\(metadataString.isEmpty ? "" : " \(metadataString)")"

        // Write to file
        FileLogHandler.appendToFile(message: logMessage, to: Self.getLogFileURL(for: source))
    }

    /// Returns the appropriate log file URL based on daily rotation
    private static func getLogFileURL(for source: String) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        let dateString = formatter.string(from: Date())
        let filename = "\(source)-\(dateString).log"

        return LogManager.logsDirectory.appendingPathComponent(filename)
    }

    private static func appendToFile(message: String, to fileURL: URL) {
        let logMessage = message + "\n"

        fileWriteQueue.async {
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
