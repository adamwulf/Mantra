import SwiftUI
import SwiftData

struct PhraseListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Phrase.createdAt, order: .reverse) private var phrases: [Phrase]
    
    @State private var showingAddPhrase = false
    @State private var newPhraseText = ""
    
    @State private var editingPhrase: Phrase?
    @State private var editingPhraseText = ""
    
    @FocusState private var focusedPhraseID: UUID?
    
    var body: some View {
        List {
            ForEach(phrases) { phrase in
                if editingPhrase?.id == phrase.id {
                    TextField("Enter phrase", text: $editingPhraseText)
                        .focused($focusedPhraseID, equals: phrase.id)
                        .onSubmit {
                            saveEditedPhrase()
                        }
                    #if os(macOS)
                        .onExitCommand {
                            cancelEditing()
                        }
                    #endif
                } else {
                    Text(phrase.text)
                        .onTapGesture {
                            startEditing(phrase)
                        }
                }
            }
            .onDelete(perform: deletePhrases)
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .scrollContentBackground(.hidden)
        #endif
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
    }
    
    private func addPhrase() {
        guard !newPhraseText.isEmpty else { return }
        let phrase = Phrase(text: newPhraseText)
        modelContext.insert(phrase)
        newPhraseText = ""
        cachePhrases()
    }
    
    private func startEditing(_ phrase: Phrase) {
        editingPhrase = phrase
        editingPhraseText = phrase.text
        focusedPhraseID = phrase.id
    }
    
    private func cancelEditing() {
        editingPhrase = nil
        editingPhraseText = ""
        focusedPhraseID = nil
    }
    
    private func saveEditedPhrase() {
        guard let phrase = editingPhrase, !editingPhraseText.isEmpty else {
            cancelEditing()
            return
        }
        phrase.text = editingPhraseText
        editingPhrase = nil
        editingPhraseText = ""
        focusedPhraseID = nil
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
        // Pending notifications carry frozen phrase text, so reschedule to
        // pick up edits and drop deleted phrases
        NotificationManager.shared.scheduleNextNotification()
    }
}

#Preview {
    NavigationStack {
        PhraseListView()
    }
    .modelContainer(for: Phrase.self, inMemory: true)
}
