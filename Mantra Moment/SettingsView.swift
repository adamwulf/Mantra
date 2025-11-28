import SwiftUI
import SwiftData
import UserNotifications
#if os(macOS)
import AppKit
#endif

struct SettingsView: View {
    @State private var schedule = Schedule.load()
    @Query private var phrases: [Phrase]
    
    @State private var testNotificationCountdown = 0
    @State private var showingAddEntry = false
    @State private var editingEntry: ScheduledEntry?
    
    @ObservedObject var notificationManager = NotificationManager.shared
    
    var body: some View {
        NavigationStack {
            Form {
                if notificationManager.authorizationStatus == .denied {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Notifications are disabled")
                                .font(.headline)
                                .foregroundColor(.red)
                            Text("Please enable notifications in Settings to receive your mantras.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Button("Open Settings") {
                                openSettings()
                            }
                        }
                    }
                } else {
                    Section(header: Text("Notifications")) {
                        Toggle("Enable Notifications", isOn: $schedule.isEnabled)
                            .onChange(of: schedule.isEnabled) { oldValue, newValue in
                                if newValue {
                                    NotificationManager.shared.requestAuthorization()
                                }
                                saveAndSchedule()
                            }
                        
                        if schedule.isEnabled {
                            DatePicker("Start Time", selection: $schedule.startTime, displayedComponents: .hourAndMinute)
                                .onChange(of: schedule.startTime) { _, _ in saveAndSchedule() }
                            
                            DatePicker("End Time", selection: $schedule.endTime, displayedComponents: .hourAndMinute)
                                .onChange(of: schedule.endTime) { _, _ in saveAndSchedule() }
                        }
                    }
                    
                    if schedule.isEnabled {
                        Section(header: Text("Scheduled Entries")) {
                            if schedule.scheduledEntries.isEmpty {
                                Text("No scheduled entries")
                                    .foregroundColor(.secondary)
                                    .italic()
                            } else {
                                ForEach(schedule.scheduledEntries) { entry in
                                    ScheduledEntryRow(
                                        entry: entry,
                                        phrases: phraseDictionary,
                                        onToggle: { isEnabled in
                                            toggleEntry(entry, isEnabled: isEnabled)
                                        }
                                    )
                                    .onTapGesture {
                                        editingEntry = entry
                                    }
                                }
                                .onDelete(perform: deleteEntries)
                            }
                            
                            Button(action: { showingAddEntry = true }) {
                                Label("Add Entry", systemImage: "plus")
                            }
                        }
                    }
                    
                    Section {
                        Button(testNotificationButtonTitle) {
                            sendTestNotification()
                        }
                        .disabled(testNotificationCountdown > 0)
                    }
                    
                    if schedule.isEnabled {
                        Section(header: Text("Next Notification")) {
                            if let nextDate = notificationManager.nextNotificationDate {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(nextDate, style: .date)
                                    Text(nextDate, style: .time)
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                Text("No notification scheduled")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingAddEntry) {
                ScheduledEntryEditView(entry: nil) { newEntry in
                    addEntry(newEntry)
                }
            }
            .sheet(item: $editingEntry) { entry in
                ScheduledEntryEditView(entry: entry) { updatedEntry in
                    updateEntry(updatedEntry)
                }
            }
        }
    }
    
    private var phraseDictionary: [UUID: String] {
        Dictionary(uniqueKeysWithValues: phrases.map { ($0.id, $0.text) })
    }
    
    private var testNotificationButtonTitle: String {
        if testNotificationCountdown > 0 {
            return "Send Test Notification (\(testNotificationCountdown))"
        } else {
            return "Send Test Notification"
        }
    }
    
    private func sendTestNotification() {
        NotificationManager.shared.scheduleTestNotification()
        testNotificationCountdown = 5
        
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if testNotificationCountdown > 0 {
                testNotificationCountdown -= 1
            } else {
                timer.invalidate()
            }
        }
    }
    
    private func addEntry(_ entry: ScheduledEntry) {
        schedule.scheduledEntries.append(entry)
        saveAndSchedule()
    }
    
    private func updateEntry(_ entry: ScheduledEntry) {
        if let index = schedule.scheduledEntries.firstIndex(where: { $0.id == entry.id }) {
            schedule.scheduledEntries[index] = entry
            saveAndSchedule()
        }
    }
    
    private func toggleEntry(_ entry: ScheduledEntry, isEnabled: Bool) {
        if let index = schedule.scheduledEntries.firstIndex(where: { $0.id == entry.id }) {
            schedule.scheduledEntries[index].isEnabled = isEnabled
            saveAndSchedule()
        }
    }
    
    private func deleteEntries(offsets: IndexSet) {
        schedule.scheduledEntries.remove(atOffsets: offsets)
        saveAndSchedule()
    }
    
    private func saveAndSchedule() {
        schedule.save()
        NotificationManager.shared.cachePhrasesForBackground(phrases)
        NotificationManager.shared.scheduleNextNotification()
    }
    
    private func openSettings() {
#if canImport(UIKit)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
#elseif os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
#endif
    }
}

#Preview {
    SettingsView()
}
