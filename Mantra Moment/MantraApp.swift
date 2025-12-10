import SwiftUI
import SwiftData
import BackgroundTasks
import Logging

@main
struct MantraApp: App {
    let container: ModelContainer
    static let logger = Logger(label: "MantraApp")

    init() {
        // Configure logging first, before anything else
        LogManager.configure()

        do {
            container = try ModelContainer(for: Phrase.self)
            seedDefaultPhrasesIfNeeded()
            Self.logger.info("app_initialized")

            // Register background task handler before scheduling
            #if os(iOS)
            BGTaskScheduler.shared.register(
                forTaskWithIdentifier: NotificationManager.backgroundTaskIdentifier,
                using: nil
            ) { task in
                NotificationManager.shared.handleBackgroundRefresh(task: task as! BGAppRefreshTask)
            }
            #endif

            // Verify notification is scheduled on startup
            NotificationManager.shared.verifyNotificationScheduled()

            // Schedule background refresh for notification rescheduling
            NotificationManager.shared.scheduleBackgroundRefresh()
        } catch {
            Self.logger.critical("model_container_failed", metadata: ["error": "\(error)"])
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
    
    var body: some Scene {
#if os(macOS)
        MenuBarExtra("Mantra", systemImage: "figure.mind.and.body") {
            Button("Settings") {
                NSApplication.shared.activate(ignoringOtherApps: true)
                if let window = NSApplication.shared.windows.first(where: { $0.identifier?.rawValue == "main" }) {
                    window.makeKeyAndOrderFront(nil)
                } else {
                    // Open new window
                    let contentView = ContentView()
                        .modelContainer(container)
                    let hostingController = NSHostingController(rootView: contentView)
                    let window = NSWindow(contentViewController: hostingController)
                    window.identifier = NSUserInterfaceItemIdentifier("main")
                    window.title = "Mantra"
                    window.setContentSize(NSSize(width: 600, height: 500))
                    window.center()
                    window.makeKeyAndOrderFront(nil)
                }
            }
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .menuBarExtraStyle(.menu)
#else
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
#endif
    }
    
    private func seedDefaultPhrasesIfNeeded() {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Phrase>()
        
        do {
            let count = try context.fetchCount(descriptor)
            if count == 0 {
                let defaultPhrases = [
                    "It's ok to slow down.",
                    "Slow and steady.",
                    "One step at a time.",
                    "Take time to breathe.",
                    "It's a marathon not a sprint.",
                    "I can slow down. That's ok.",
                    "Slow is steady and steady is fast.",
                    "Treat every blunder as a gambit.",
                    "Work the problem.",
                    "Obstacles are on the way not in the way.",
                    "Inspiration only shows up when you do.",
                    "You only see the doors you're facing.",
                    "Slow down. Be methodical.",
                    "It's ok to reschedule or say no."
                ]
                
                for text in defaultPhrases {
                    context.insert(Phrase(text: text))
                }
                try context.save()
            }
        } catch {
            print("Failed to seed data: \(error)")
        }
    }
}
