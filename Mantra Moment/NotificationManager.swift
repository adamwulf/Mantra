import Foundation
import UserNotifications
import Combine
#if canImport(UIKit)
import UIKit
#endif

class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined
    
    override private init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        checkAuthorization()
        
#if canImport(UIKit)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
#endif
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func appWillEnterForeground() {
        checkAuthorization()
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
    
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                self.checkAuthorization()
            }
        }
    }
    
    func checkAuthorization() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.authorizationStatus = settings.authorizationStatus
            }
        }
    }
    
    func schedule(phrases: [Phrase], schedule: Schedule) {
        cancelAll()
        
        guard schedule.isEnabled, !phrases.isEmpty else { return }
        
        let content = UNMutableNotificationContent()
        content.sound = .default
        
        // Simple logic: schedule 'frequency' notifications for the next day
        // In a real app, we'd probably schedule for the next week or so.
        // For this prototype, let's schedule for today (if time permits) and tomorrow.
        
        let calendar = Calendar.current
        let now = Date()
        
        // Normalize start/end times to today
        let startComponents = calendar.dateComponents([.hour, .minute], from: schedule.startTime)
        let endComponents = calendar.dateComponents([.hour, .minute], from: schedule.endTime)
        
        guard let startHour = startComponents.hour, let startMinute = startComponents.minute,
              let endHour = endComponents.hour, let endMinute = endComponents.minute else { return }
        
        let todayStart = calendar.date(bySettingHour: startHour, minute: startMinute, second: 0, of: now)!
        let todayEnd = calendar.date(bySettingHour: endHour, minute: endMinute, second: 0, of: now)!
        
        // Calculate duration in seconds
        let duration = todayEnd.timeIntervalSince(todayStart)
        guard duration > 0 else { return }
        
        for _ in 0..<schedule.frequency {
            let randomOffset = Double.random(in: 0...duration)
            let triggerDate = todayStart.addingTimeInterval(randomOffset)
            
            if triggerDate > now {
                scheduleNotification(at: triggerDate, with: phrases)
            }
            
            // Also schedule for tomorrow
            if let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart) {
                 let tomorrowTriggerDate = tomorrowStart.addingTimeInterval(randomOffset)
                 scheduleNotification(at: tomorrowTriggerDate, with: phrases)
            }
        }
    }
    
    private func scheduleNotification(at date: Date, with phrases: [Phrase]) {
        guard let phrase = phrases.randomElement() else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Mantra"
        content.body = phrase.text
        content.sound = .default
        
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request)
    }
    
    func scheduleTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Mantra Test"
        content.body = "This is a test notification. You got this!"
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request)
    }
    
    func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
