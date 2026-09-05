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
                #if os(iOS)
                Section {
                    NavigationLink {
                        PhraseListView()
                    } label: {
                        HStack {
                            Label("Phrases", systemImage: "quote.bubble")
                            Spacer()
                            Text(phrases.count, format: .number)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel(phrases.count == 1 ? "1 phrase" : "\(phrases.count) phrases")
                        }
                    }
                }
                #endif

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
                    Section {
                        Toggle("Enable Notifications", isOn: $schedule.isEnabled)
                            .onChange(of: schedule.isEnabled) { oldValue, newValue in
                                if newValue {
                                    NotificationManager.shared.requestAuthorization()
                                }
                                saveAndSchedule()
                            }

                        #if os(macOS)
                        LaunchAtLoginView()
                        #endif

                        if schedule.isEnabled {
                            HStack {
                                DatePicker("Start", selection: $schedule.startTime, displayedComponents: .hourAndMinute)
                                    .labelsHidden()
                                Text("to")
                                    .foregroundColor(.secondary)
                                DatePicker("End", selection: $schedule.endTime, displayedComponents: .hourAndMinute)
                                    .labelsHidden()
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .onChange(of: schedule.startTime) { _, _ in saveAndSchedule() }
                            .onChange(of: schedule.endTime) { _, _ in saveAndSchedule() }
                        }
                    } header: {
                        Text("Reminders")
                            .font(.headline)
                    } footer: {
                        if schedule.isEnabled {
                            Text("Notifications will be scheduled between these times.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if schedule.isEnabled {
#if os(macOS)
                        Divider()
                            .padding(.vertical, 8)
#endif
                        
                        Section {
                            if schedule.scheduledEntries.isEmpty {
                                Text("No reminders scheduled")
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
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        editingEntry = entry
                                    }
                                }
                                .onDelete(perform: deleteEntries)
                            }
                            
                            Button(action: { showingAddEntry = true }) {
                                Label("Add Reminder", systemImage: "plus.circle.fill")
                            }
                        } header: {
                            Text("Schedule")
                                .font(.headline)
                        }
                    }
                    
                    if schedule.isEnabled {
#if os(macOS)
                        Divider()
                            .padding(.vertical, 8)
#endif
                        
                        Section(header: Text("Status").font(.headline)) {
                            if let nextDate = notificationManager.nextNotificationDate {
                                HStack {
                                    Text("Next Reminder")
                                    Spacer()
                                    Text(nextDate, style: .relative)
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                Text("No reminder scheduled")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                #if os(macOS)
                Divider()
                    .padding(.vertical, 8)
                #endif

                Section {
                    DisclosureGroup("Support") {
                        HStack {
                            Text("Background Refresh")
                            Spacer()
                            Text(notificationManager.backgroundRefreshStatus.rawValue)
                                .foregroundColor(backgroundRefreshStatusColor)
                                .font(.caption)
                        }

                        if schedule.isEnabled && notificationManager.authorizationStatus != .denied {
                            Button(testNotificationButtonTitle) {
                                sendTestNotification()
                            }
                            .disabled(testNotificationCountdown > 0)
                        }

                        Button("Export Debug Logs") {
                            exportDebugLogs()
                        }
                    }
                }
            }
            #if os(iOS)
            .formStyle(.grouped)
            .navigationTitle("Mantra")
            #else
            .padding()
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .navigationTitle("Settings")
            #endif
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

    private var backgroundRefreshStatusColor: Color {
        switch notificationManager.backgroundRefreshStatus {
        case .scheduled:
            return .green
        case .unavailable:
            return .orange
        case .notPermitted, .unknown:
            return .red
        case .tooManyRequests:
            return .yellow
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

    private func exportDebugLogs() {
#if canImport(UIKit)
        LogManager.shareLogArchive()
#elseif os(macOS)
        LogManager.saveLogArchive()
#endif
    }
}

#Preview {
    SettingsView()
}
