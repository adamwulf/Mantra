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
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
    
    private func seedDefaultPhrasesIfNeeded() {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Phrase>()
        
        do {
            let count = try context.fetchCount(descriptor)
            if count == 0 {
                let defaultPhrases = [
                    "Breathe in, breathe out.",
                    "You are enough.",
                    "This too shall pass.",
                    "Stay present.",
                    "Focus on the good."
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
