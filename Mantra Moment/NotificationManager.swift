import Foundation
import UserNotifications
import Combine
#if canImport(UIKit)
import UIKit
#endif

class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published var nextNotificationDate: Date?
    
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
        completionHandler([.banner, .list, .sound])
    }
    
    // Called when notification is delivered (even in background)
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        // Schedule the next notification to maintain continuous flow
        scheduleNextNotification()
        completionHandler()
    }
    
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge, .criticalAlert]) { granted, error in
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
    

    func scheduleTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Mantra Test"
        content.body = "This is a test notification. You got this!"
        content.sound = .default
        content.interruptionLevel = .critical
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request)
    }
    
    func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
    
    // MARK: - Continuous Rescheduling
    
    /// Cache phrases to UserDefaults for background access
    func cachePhrasesForBackground(_ phrases: [Phrase]) {
        let phraseTexts = phrases.filter { $0.isEnabled }.map { $0.text }
        UserDefaults.standard.set(phraseTexts, forKey: "CachedPhrases")
    }
    
    /// Load cached phrases from UserDefaults
    private func loadCachedPhrases() -> [String] {
        return UserDefaults.standard.stringArray(forKey: "CachedPhrases") ?? []
    }
    
    /// Schedule the next notification based on current schedule settings
    func scheduleNextNotification() {
        cancelAll()
        let schedule = Schedule.load()
        guard schedule.isEnabled else {
            DispatchQueue.main.async {
                self.nextNotificationDate = nil
            }
            return
        }
        
        let phrases = loadCachedPhrases()
        guard !phrases.isEmpty else {
            DispatchQueue.main.async {
                self.nextNotificationDate = nil
            }
            return
        }
        
        guard let nextTime = calculateNextNotificationTime(for: schedule) else {
            DispatchQueue.main.async {
                self.nextNotificationDate = nil
            }
            return
        }
        
        // Pick a random phrase
        guard let phraseText = phrases.randomElement() else {
            DispatchQueue.main.async {
                self.nextNotificationDate = nil
            }
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = "Mantra"
        content.body = phraseText
        content.sound = .default
        content.interruptionLevel = .critical
        
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: nextTime)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if error == nil {
                DispatchQueue.main.async {
                    self.nextNotificationDate = nextTime
                }
            }
        }
    }
    
    /// Calculate when the next notification should fire based on schedule settings
    private func calculateNextNotificationTime(for schedule: Schedule) -> Date? {
        let calendar = Calendar.current
        let now = Date()
        
        // Get start/end times for today
        let startComponents = calendar.dateComponents([.hour, .minute], from: schedule.startTime)
        let endComponents = calendar.dateComponents([.hour, .minute], from: schedule.endTime)
        
        guard let startHour = startComponents.hour, let startMinute = startComponents.minute,
              let endHour = endComponents.hour, let endMinute = endComponents.minute else { return nil }
        
        let todayStart = calendar.date(bySettingHour: startHour, minute: startMinute, second: 0, of: now)!
        let todayEnd = calendar.date(bySettingHour: endHour, minute: endMinute, second: 0, of: now)!
        
        // Calculate the duration of the notification window
        let duration = todayEnd.timeIntervalSince(todayStart)
        guard duration > 0 else { return nil }
        
        // Calculate average interval between notifications based on frequency
        let averageInterval = duration / Double(schedule.frequency)
        
        // If we're currently within today's window, schedule for later today
        if now >= todayStart && now < todayEnd {
            // Schedule the next notification at least averageInterval from now
            let nextTime = now.addingTimeInterval(averageInterval)
            
            // If that would be past today's end time, schedule for tomorrow
            if nextTime > todayEnd {
                guard let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart) else { return nil }
                let randomOffset = Double.random(in: 0...duration)
                return tomorrowStart.addingTimeInterval(randomOffset)
            }
            
            return nextTime
        }
        
        // If we're past today's window, schedule for tomorrow
        if now >= todayEnd {
            guard let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart) else { return nil }
            let randomOffset = Double.random(in: 0...duration)
            return tomorrowStart.addingTimeInterval(randomOffset)
        }
        
        // If we're before today's window, schedule for later today
        let randomOffset = Double.random(in: 0...duration)
        return todayStart.addingTimeInterval(randomOffset)
    }
    
    // MARK: - Notification Verification
    
    /// Get the next scheduled notification date
    func getNextScheduledNotification(completion: @escaping (Date?) -> Void) {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            // Find the earliest notification
            let nextDate = requests.compactMap { request -> Date? in
                if let trigger = request.trigger as? UNCalendarNotificationTrigger,
                   let nextTriggerDate = trigger.nextTriggerDate() {
                    return nextTriggerDate
                }
                return nil
            }.min()
            
            DispatchQueue.main.async {
                self.nextNotificationDate = nextDate
                completion(nextDate)
            }
        }
    }
    
    /// Verify that a notification is scheduled within the next 24 hours
    /// If not, clear all notifications and reschedule
    func verifyNotificationScheduled() {
        getNextScheduledNotification { nextDate in
            let now = Date()
            let twentyFourHoursFromNow = now.addingTimeInterval(24 * 60 * 60)
            
            // Check if we have a notification scheduled within the next 24 hours
            if let nextDate = nextDate, nextDate <= twentyFourHoursFromNow {
                // We're good, notification is scheduled
                return
            }
            
            // No notification scheduled within 24 hours, reschedule
            self.scheduleNextNotification()
        }
    }
}
