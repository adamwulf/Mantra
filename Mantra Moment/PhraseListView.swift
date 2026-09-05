import SwiftUI
import SwiftData

struct PhraseListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Phrase.createdAt, order: .reverse) private var phrases: [Phrase]
    
    @State private var showingAddPhrase = false
    @State private var newPhraseText = ""
    
    @State private var editingPhrase: Phrase?
    @State private var editingPhraseText = ""
    
    @FocusState private var focusedPhraseID: UUID?
    
    var body: some View {
        Group {
            #if os(macOS)
            Form {
                Section {
                    phraseRows
                } footer: {
                    Text("Click a phrase to edit it. Control-click for more options.")
                }
            }
            .formStyle(.grouped)
            #else
            List {
                phraseRows
            }
            .listStyle(.insetGrouped)
            #endif
        }
        .navigationTitle("Phrases")
        .toolbar {
            #if os(macOS)
            ToolbarItem(placement: .navigation) {
                Button {
                    dismiss()
                } label: {
                    Label("Back to Settings", systemImage: "chevron.left")
                        .labelStyle(.iconOnly)
                }
                .help("Back to Settings")
                .keyboardShortcut("[", modifiers: .command)
            }
            #endif
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingAddPhrase = true }) {
                    Label("Add Phrase", systemImage: "plus")
                }
                .help("Add Phrase")
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

    @ViewBuilder
    private var phraseRows: some View {
        #if os(macOS)
        if phrases.isEmpty {
            ContentUnavailableView("No Phrases", systemImage: "quote.bubble", description: Text("Add a phrase to use in your reminders."))
        }
        #endif
        ForEach(phrases) { phrase in
            Group {
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
                    #if os(macOS)
                    Button {
                        startEditing(phrase)
                    } label: {
                        Text(phrase.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Edit Phrase")
                    #else
                    Text(phrase.text)
                        .onTapGesture {
                            startEditing(phrase)
                        }
                    #endif
                }
            }
            #if os(macOS)
            .padding(.vertical, 6)
            .contextMenu {
                Button("Edit Phrase") { startEditing(phrase) }
                Button("Delete Phrase", role: .destructive) {
                    if let index = phrases.firstIndex(where: { $0.id == phrase.id }) {
                        deletePhrases(offsets: IndexSet(integer: index))
                    }
                }
            }
            #endif
        }
        .onDelete(perform: deletePhrases)
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
