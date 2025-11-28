import SwiftUI

struct ScheduledEntryRow: View {
    let entry: ScheduledEntry
    let phrases: [UUID: String]
    let onToggle: (Bool) -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.phraseDisplayText(phrases: phrases))
                    .font(.body)
                Text(entry.timeDisplayText())
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Toggle("", isOn: Binding(
                get: { entry.isEnabled },
                set: { onToggle($0) }
            ))
            .labelsHidden()
        }
        .contentShape(Rectangle())
    }
}
