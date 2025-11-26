import SwiftUI
import SwiftData

@main
struct MantraApp: App {
    let container: ModelContainer
    
    init() {
        do {
            container = try ModelContainer(for: Phrase.self)
            seedDefaultPhrasesIfNeeded()
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
    
    var body: some Scene {
#if os(macOS)
        MenuBarExtra("Mantra", systemImage: "figure.mind.and.body") {
            ContentView()
        }
        .menuBarExtraStyle(.window)
        .modelContainer(container)
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
                    "You only see the doors you're facing."
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
