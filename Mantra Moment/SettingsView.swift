import SwiftUI
import SwiftData
import UserNotifications

struct SettingsView: View {
    @State private var schedule = Schedule.load()
    @Query private var phrases: [Phrase]
    
    @State private var testNotificationCountdown = 0
    
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
#if canImport(UIKit)
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
#endif
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
                            
                            Stepper("Frequency: \(schedule.frequency) times/day", value: $schedule.frequency, in: 1...20)
                                .onChange(of: schedule.frequency) { _, _ in saveAndSchedule() }
                        }
                    }
                    
                    Section {
                        Button(testNotificationButtonTitle) {
                            sendTestNotification()
                        }
                        .disabled(testNotificationCountdown > 0)
                    }
                }
            }
            .navigationTitle("Settings")
        }
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
    
    private func saveAndSchedule() {
        schedule.save()
        NotificationManager.shared.schedule(phrases: phrases, schedule: schedule)
    }
}

#Preview {
    SettingsView()
}
