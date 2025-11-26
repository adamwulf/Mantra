import SwiftUI
import SwiftData

struct PhraseListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Phrase.createdAt, order: .reverse) private var phrases: [Phrase]
    
    @State private var showingAddPhrase = false
    @State private var newPhraseText = ""
    
    @State private var editingPhrase: Phrase?
    @State private var editingPhraseText = ""
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(phrases) { phrase in
                    Text(phrase.text)
                        .onTapGesture {
                            editingPhrase = phrase
                            editingPhraseText = phrase.text
                        }
                }
                .onDelete(perform: deletePhrases)
            }
            .navigationTitle("Phrases")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
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
            .alert("Edit Phrase", isPresented: Binding(
                get: { editingPhrase != nil },
                set: { if !$0 { editingPhrase = nil } }
            )) {
                TextField("Enter phrase", text: $editingPhraseText)
                Button("Cancel", role: .cancel) {
                    editingPhrase = nil
                    editingPhraseText = ""
                }
                Button("Save") {
                    saveEditedPhrase()
                }
            }
        }
    }
    
    private func addPhrase() {
        guard !newPhraseText.isEmpty else { return }
        let phrase = Phrase(text: newPhraseText)
        modelContext.insert(phrase)
        newPhraseText = ""
        cachePhrases()
    }
    
    private func saveEditedPhrase() {
        guard let phrase = editingPhrase, !editingPhraseText.isEmpty else { return }
        phrase.text = editingPhraseText
        editingPhrase = nil
        editingPhraseText = ""
        cachePhrases()
    }
    
    private func deletePhrases(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(phrases[index])
            }
        }
        cachePhrases()
    }
    
    private func cachePhrases() {
        NotificationManager.shared.cachePhrasesForBackground(phrases)
    }
}

#Preview {
    PhraseListView()
        .modelContainer(for: Phrase.self, inMemory: true)
}
