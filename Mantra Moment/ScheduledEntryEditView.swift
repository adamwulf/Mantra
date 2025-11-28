import SwiftUI
import SwiftData

struct ScheduledEntryEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Phrase> { $0.isEnabled }) private var enabledPhrases: [Phrase]
    
    let entry: ScheduledEntry?
    let onSave: (ScheduledEntry) -> Void
    
    @State private var phraseMode: PhraseModeSelection = .random
    @State private var selectedPhraseId: UUID?
    @State private var timeMode: TimeModeSelection = .random
    @State private var selectedTime: Date = Date()
    
    enum PhraseModeSelection: String, CaseIterable {
        case specific = "Specific Phrase"
        case random = "Random Phrase"
    }
    
    enum TimeModeSelection: String, CaseIterable {
        case specific = "Specific Time"
        case random = "Random Time"
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Phrase")) {
                    Picker("Phrase Mode", selection: $phraseMode) {
                        ForEach(PhraseModeSelection.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    if phraseMode == .specific {
                        if enabledPhrases.isEmpty {
                            Text("No enabled phrases available")
                                .foregroundColor(.secondary)
                                .italic()
                        } else {
                            Picker("Select Phrase", selection: $selectedPhraseId) {
                                Text("Select a phrase").tag(nil as UUID?)
                                ForEach(enabledPhrases) { phrase in
                                    Text(phrase.text).tag(phrase.id as UUID?)
                                }
                            }
                        }
                    }
                }
                
                Section(header: Text("Time")) {
                    Picker("Time Mode", selection: $timeMode) {
                        ForEach(TimeModeSelection.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    if timeMode == .specific {
                        DatePicker("Time", selection: $selectedTime, displayedComponents: .hourAndMinute)
                    }
                }
            }
            .navigationTitle(entry == nil ? "Add Entry" : "Edit Entry")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveEntry()
                    }
                    .disabled(!canSave)
                }
            }
        }
        .onAppear {
            loadEntry()
        }
    }
    
    private var canSave: Bool {
        if phraseMode == .specific && selectedPhraseId == nil {
            return false
        }
        return true
    }
    
    private func loadEntry() {
        guard let entry = entry else { return }
        
        // Load phrase mode
        switch entry.phraseMode {
        case .specific(let phraseId):
            phraseMode = .specific
            selectedPhraseId = phraseId
        case .random:
            phraseMode = .random
        }
        
        // Load time mode
        switch entry.timeMode {
        case .specific(let hour, let minute):
            timeMode = .specific
            let calendar = Calendar.current
            if let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) {
                selectedTime = date
            }
        case .random:
            timeMode = .random
        }
    }
    
    private func saveEntry() {
        let calendar = Calendar.current
        
        // Build phrase mode
        let finalPhraseMode: PhraseMode
        switch phraseMode {
        case .specific:
            guard let phraseId = selectedPhraseId else { return }
            finalPhraseMode = .specific(phraseId: phraseId)
        case .random:
            finalPhraseMode = .random
        }
        
        // Build time mode
        let finalTimeMode: TimeMode
        switch timeMode {
        case .specific:
            let components = calendar.dateComponents([.hour, .minute], from: selectedTime)
            guard let hour = components.hour, let minute = components.minute else { return }
            finalTimeMode = .specific(hour: hour, minute: minute)
        case .random:
            finalTimeMode = .random
        }
        
        let newEntry = ScheduledEntry(
            id: entry?.id ?? UUID(),
            phraseMode: finalPhraseMode,
            timeMode: finalTimeMode,
            isEnabled: entry?.isEnabled ?? true
        )
        
        onSave(newEntry)
        dismiss()
    }
}
