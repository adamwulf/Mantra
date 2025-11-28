import SwiftUI

struct ScheduledEntryRow: View {
    let entry: ScheduledEntry
    let phrases: [UUID: String]
    let onToggle: (Bool) -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: phraseIconName)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.phraseDisplayText(phrases: phrases))
                    .font(.body)
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    Image(systemName: timeIconName)
                        .font(.caption)
                    Text(entry.timeDisplayText())
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Toggle("", isOn: Binding(
                get: { entry.isEnabled },
                set: { onToggle($0) }
            ))
            .labelsHidden()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
    
    private var phraseIconName: String {
        switch entry.phraseMode {
        case .random: return "shuffle"
        case .specific: return "text.quote"
        }
    }
    
    private var timeIconName: String {
        switch entry.timeMode {
        case .random: return "sparkles"
        case .specific: return "clock"
        }
    }
}
