import SwiftUI
import SwiftData

struct PhraseListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Phrase.createdAt, order: .reverse) private var phrases: [Phrase]
    
    @State private var showingAddPhrase = false
    @State private var newPhraseText = ""
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(phrases) { phrase in
                    Text(phrase.text)
                }
                .onDelete(perform: deletePhrases)
            }
            .navigationTitle("Phrases")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingAddPhrase = true }) {
                        Label("Add Phrase", systemImage: "plus")
                    }
                }
            }
            .alert("New Phrase", isPresented: $showingAddPhrase) {
                TextField("Enter phrase", text: $newPhraseText)
                Button("Cancel", role: .cancel) { newPhraseText = "" }
                Button("Add") {
                    addPhrase()
                }
            }
        }
    }
    
    private func addPhrase() {
        guard !newPhraseText.isEmpty else { return }
        let phrase = Phrase(text: newPhraseText)
        modelContext.insert(phrase)
        newPhraseText = ""
    }
    
    private func deletePhrases(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(phrases[index])
            }
        }
    }
}

#Preview {
    PhraseListView()
        .modelContainer(for: Phrase.self, inMemory: true)
}
