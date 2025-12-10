import Foundation
import Logging
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

/// Manages logging configuration for the application
enum LogManager {
    
    static let logger = Logger(label: "LogManager")
    
    /// The directory where log files are stored
    static let logsDirectory: URL = {
        let fileManager = FileManager.default
        // Use Application Support for persistence across app restarts
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Cannot generate log file destination")
        }
        let bundleId = Bundle.main.bundleIdentifier ?? "com.milestonemade.Mantra"
        return appSupport.appendingPathComponent(bundleId, isDirectory: true).appendingPathComponent("Logs", isDirectory: true)
    }()

    /// Maximum age for log files (7 days)
    private static let maxLogAge: TimeInterval = 7 * 24 * 60 * 60

    /// Configure the logging system to use our FileLogHandler
    static func configure() {
        // Create logs directory if needed
        do {
            try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        } catch {
            print("Error creating logs directory: \(error.localizedDescription)")
        }

        // Bootstrap the logging system with our FileLogHandler
        // Each logger gets its own FileLogHandler with its label, but they all write
        // to the same file safely via the static dispatch queue in FileLogHandler
        LoggingSystem.bootstrap { label in
            let fileHandler = FileLogHandler(label: label, logLevel: .debug)
            #if DEBUG
            // In debug, multiplex to both console and file
            return MultiplexLogHandler([
                StreamLogHandler.standardOutput(label: label),
                fileHandler
            ])
            #else
            // In release, just use the file handler
            return fileHandler
            #endif
        }
        
        logger.info("logging_configured", metadata: ["location": .string(logsDirectory.absoluteString)])

        // Clean up old log files
        cleanupOldLogs()
    }

    /// Clean up log files older than 7 days
    static func cleanupOldLogs() {
        let fileManager = FileManager.default
        let cutoffDate = Date().addingTimeInterval(-maxLogAge)

        do {
            let logFiles = try fileManager.contentsOfDirectory(at: logsDirectory, includingPropertiesForKeys: [.creationDateKey])

            for fileURL in logFiles {
                guard fileURL.pathExtension == "log" else { continue }

                if let resourceValues = try? fileURL.resourceValues(forKeys: [.creationDateKey]),
                   let creationDate = resourceValues.creationDate,
                   creationDate < cutoffDate {
                    try? fileManager.removeItem(at: fileURL)
                }
            }
        } catch {
            // Directory might not exist yet, that's fine
        }
    }

    /// Get all log files sorted by date (newest first)
    static func getLogFiles() -> [URL] {
        let fileManager = FileManager.default

        do {
            let files = try fileManager.contentsOfDirectory(at: logsDirectory, includingPropertiesForKeys: [.creationDateKey])
            return files
                .filter { $0.pathExtension == "log" }
                .sorted { url1, url2 in
                    let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                    let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                    return date1 > date2
                }
        } catch {
            return []
        }
    }

    /// Create a zip archive of all log files and return the URL
    static func createLogArchive() -> URL? {
        let fileManager = FileManager.default
        let logFiles = getLogFiles()

        guard !logFiles.isEmpty else { return nil }

        // Create temp directory for the archive
        let tempDir = fileManager.temporaryDirectory
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let archiveName = "MantraLogs_\(dateFormatter.string(from: Date())).zip"
        let archiveURL = tempDir.appendingPathComponent(archiveName)

        // Remove existing archive if present
        try? fileManager.removeItem(at: archiveURL)

        // Create a temporary directory with all the log files to zip
        let stagingDir = tempDir.appendingPathComponent("MantraLogStaging")
        try? fileManager.removeItem(at: stagingDir)
        try? fileManager.createDirectory(at: stagingDir, withIntermediateDirectories: true)

        // Copy log files to staging directory
        for logFile in logFiles {
            let destURL = stagingDir.appendingPathComponent(logFile.lastPathComponent)
            try? fileManager.copyItem(at: logFile, to: destURL)
        }

        // Create zip archive using FileManager's built-in compression
        do {
            let coordinator = NSFileCoordinator()
            var error: NSError?

            coordinator.coordinate(readingItemAt: stagingDir, options: .forUploading, error: &error) { zipURL in
                try? fileManager.moveItem(at: zipURL, to: archiveURL)
            }

            if error != nil {
                return nil
            }

            // Clean up staging directory
            try? fileManager.removeItem(at: stagingDir)

            return fileManager.fileExists(atPath: archiveURL.path) ? archiveURL : nil
        }
    }

    #if canImport(UIKit)
    /// Share log archive on iOS
    @MainActor
    static func shareLogArchive(from viewController: UIViewController? = nil) {
        guard let archiveURL = createLogArchive() else { return }

        let activityVC = UIActivityViewController(activityItems: [archiveURL], applicationActivities: nil)

        if let vc = viewController ?? UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows.first?.rootViewController {
            // For iPad, set the source view
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = vc.view
                popover.sourceRect = CGRect(x: vc.view.bounds.midX, y: vc.view.bounds.midY, width: 0, height: 0)
            }
            vc.present(activityVC, animated: true)
        }
    }
    #endif

    #if os(macOS)
    /// Show save panel for log archive on macOS
    @MainActor
    static func saveLogArchive() {
        guard let archiveURL = createLogArchive() else { return }

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.zip]
        savePanel.nameFieldStringValue = archiveURL.lastPathComponent
        savePanel.canCreateDirectories = true

        savePanel.begin { response in
            if response == .OK, let destURL = savePanel.url {
                try? FileManager.default.copyItem(at: archiveURL, to: destURL)
            }
            // Clean up temp file
            try? FileManager.default.removeItem(at: archiveURL)
        }
    }
    #endif
}
