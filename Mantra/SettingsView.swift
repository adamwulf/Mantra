import SwiftUI
import SwiftData

struct SettingsView: View {
    @State private var schedule = Schedule.load()
    @Query private var phrases: [Phrase]
    
    var body: some View {
        NavigationStack {
            Form {
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
                        
                        Stepper("Frequency: \(schedule.frequency) times/day", value: $schedule.frequency, in: 1...20)
                            .onChange(of: schedule.frequency) { _, _ in saveAndSchedule() }
                    }
                }
                
                Section {
                    Button("Send Test Notification") {
                        NotificationManager.shared.scheduleTestNotification()
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
    
    private func saveAndSchedule() {
        schedule.save()
        NotificationManager.shared.schedule(phrases: phrases, schedule: schedule)
    }
}

#Preview {
    SettingsView()
}
