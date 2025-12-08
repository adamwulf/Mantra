import Foundation
import UserNotifications
import Combine
import BackgroundTasks
#if canImport(UIKit)
import UIKit
#endif

class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    /// Background task identifier for rescheduling notifications
    static let backgroundTaskIdentifier = "com.milestonemade.Mantra.refresh"

    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published var nextNotificationDate: Date?
    @Published var backgroundRefreshStatus: BackgroundRefreshStatus = .unknown

    enum BackgroundRefreshStatus: String {
        case unknown = "Unknown"
        case scheduled = "Scheduled"
        case unavailable = "Unavailable"
        case notPermitted = "Not Permitted"
        case tooManyRequests = "Too Many Requests"
    }
    
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
        verifyNotificationScheduled()
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
    
    // Called when the user interacts with (taps) a notification
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        // Schedule the next batch of notifications when user engages
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
    
    // MARK: - Scheduled Entry Support
    
    /// Cache phrases to UserDefaults for background access
    func cachePhrasesForBackground(_ phrases: [Phrase]) {
        let phraseDict = Dictionary(uniqueKeysWithValues: phrases.filter { $0.isEnabled }.map { ($0.id, $0.text) })
        if let data = try? JSONEncoder().encode(phraseDict) {
            UserDefaults.standard.set(data, forKey: "CachedPhrases")
        }
    }
    
    /// Load cached phrases from UserDefaults
    private func loadCachedPhrases() -> [UUID: String] {
        guard let data = UserDefaults.standard.data(forKey: "CachedPhrases"),
              let phrases = try? JSONDecoder().decode([UUID: String].self, from: data) else {
            return [:]
        }
        return phrases
    }
    
    /// Schedule notifications for all enabled scheduled entries
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
        
        let enabledEntries = schedule.scheduledEntries.filter { $0.isEnabled }
        guard !enabledEntries.isEmpty else {
            DispatchQueue.main.async {
                self.nextNotificationDate = nil
            }
            return
        }
        
        // Calculate times for all entries
        let times = calculateNotificationTimes(for: enabledEntries, schedule: schedule)
        
        var earliestTime: Date?
        
        // Schedule each entry
        for (entry, time) in zip(enabledEntries, times) {
            guard let phraseText = resolvePhrase(for: entry, phrases: phrases) else {
                continue
            }
            
            let content = UNMutableNotificationContent()
            content.title = "Mantra"
            content.body = phraseText
            content.sound = .default
            content.interruptionLevel = .critical
            
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: time)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
            
            UNUserNotificationCenter.current().add(request) { error in
                if error == nil {
                    DispatchQueue.main.async {
                        if earliestTime == nil || time < earliestTime! {
                            earliestTime = time
                            self.nextNotificationDate = time
                        }
                    }
                }
            }
        }
        
        if let earliest = earliestTime {
            DispatchQueue.main.async {
                self.nextNotificationDate = earliest
            }
        }

        // Schedule background refresh to ensure notifications continue
        scheduleBackgroundRefresh()
    }

    /// Resolve the phrase text for a scheduled entry
    private func resolvePhrase(for entry: ScheduledEntry, phrases: [UUID: String]) -> String? {
        switch entry.phraseMode {
        case .specific(let phraseId):
            return phrases[phraseId]
        case .random:
            return phrases.values.randomElement()
        }
    }
    
    // MARK: - Caching
    
    struct CachedSchedule: Codable {
        let date: Date
        let scheduleData: Data
        let times: [Date]
    }
    
    private func getCachedSchedule(for date: Date, schedule: Schedule) -> [Date]? {
        guard let data = UserDefaults.standard.data(forKey: "CachedSchedule"),
              let cache = try? JSONDecoder().decode(CachedSchedule.self, from: data) else {
            return nil
        }
        
        // Check if cache is for the same date
        if !Calendar.current.isDate(cache.date, inSameDayAs: date) {
            return nil
        }
        
        // Check if schedule settings match
        let encoder = JSONEncoder()
        if #available(iOS 11.0, macOS 10.13, *) {
            encoder.outputFormatting = .sortedKeys
        }
        
        guard let currentScheduleData = try? encoder.encode(schedule),
              cache.scheduleData == currentScheduleData else {
            return nil
        }
        
        return cache.times
    }
    
    private func saveCachedSchedule(_ times: [Date], for date: Date, schedule: Schedule) {
        let encoder = JSONEncoder()
        if #available(iOS 11.0, macOS 10.13, *) {
            encoder.outputFormatting = .sortedKeys
        }
        
        guard let scheduleData = try? encoder.encode(schedule) else { return }
        let cache = CachedSchedule(date: date, scheduleData: scheduleData, times: times)
        if let data = try? encoder.encode(cache) {
            UserDefaults.standard.set(data, forKey: "CachedSchedule")
        }
    }

    /// Calculate notification times for all entries
    private func calculateNotificationTimes(for entries: [ScheduledEntry], schedule: Schedule) -> [Date] {
        let calendar = Calendar.current
        let now = Date()
        
        // Get start/end times for today
        let startComponents = calendar.dateComponents([.hour, .minute], from: schedule.startTime)
        let endComponents = calendar.dateComponents([.hour, .minute], from: schedule.endTime)
        
        guard let startHour = startComponents.hour, let startMinute = startComponents.minute,
              let endHour = endComponents.hour, let endMinute = endComponents.minute else {
            return []
        }
        
        let todayStart = calendar.date(bySettingHour: startHour, minute: startMinute, second: 0, of: now)!
        let todayEnd = calendar.date(bySettingHour: endHour, minute: endMinute, second: 0, of: now)!
        
        // Determine if we should schedule for today or tomorrow
        let useToday = now < todayEnd
        let targetStart = useToday ? todayStart : calendar.date(byAdding: .day, value: 1, to: todayStart)!
        let targetEnd = useToday ? todayEnd : calendar.date(byAdding: .day, value: 1, to: todayEnd)!
        
        // Check cache first
        if let cachedTimes = getCachedSchedule(for: targetStart, schedule: schedule) {
            return cachedTimes
        }

        // Separate entries by time mode
        var specificTimes: [Date] = []
        var randomCount = 0
        
        for entry in entries {
            switch entry.timeMode {
            case .specific(let hour, let minute):
                // For specific times, we always try to schedule for today first
                if let specificTimeToday = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) {
                    if specificTimeToday > now {
                        // It's in the future today, so use it
                        specificTimes.append(specificTimeToday)
                    } else {
                        // It's in the past today, so schedule for tomorrow
                        if let tomorrowTime = calendar.date(byAdding: .day, value: 1, to: specificTimeToday) {
                            specificTimes.append(tomorrowTime)
                        }
                    }
                }
            case .random:
                randomCount += 1
            }
        }
        
        // Calculate random times with intelligent spacing
        let randomTimes = calculateRandomTimes(count: randomCount, start: targetStart, end: targetEnd, avoid: specificTimes)
        
        // Combine and sort all times, then return in original entry order
        var allTimes: [Date] = []
        var randomIndex = 0
        
        for entry in entries {
            switch entry.timeMode {
            case .specific:
                if let time = specificTimes.first {
                    allTimes.append(time)
                    specificTimes.removeFirst()
                }
            case .random:
                if randomIndex < randomTimes.count {
                    allTimes.append(randomTimes[randomIndex])
                    randomIndex += 1
                }
            }
        }
        
        // Save to cache
        saveCachedSchedule(allTimes, for: targetStart, schedule: schedule)
        
        return allTimes
    }
    
    /// Calculate random times with intelligent spacing
    private func calculateRandomTimes(count: Int, start: Date, end: Date, avoid: [Date]) -> [Date] {
        guard count > 0 else { return [] }
        
        let duration = end.timeIntervalSince(start)
        guard duration > 0 else { return [] }
        
        // Divide the window into segments
        let segmentDuration = duration / Double(count)
        var times: [Date] = []
        
        for i in 0..<count {
            let segmentStart = start.addingTimeInterval(Double(i) * segmentDuration)
            let segmentEnd = start.addingTimeInterval(Double(i + 1) * segmentDuration)
            
            // Add randomization within the segment (±15 minutes or segment size, whichever is smaller)
            let maxRandomization = min(900.0, segmentDuration / 2) // 15 minutes = 900 seconds
            let randomOffset = Double.random(in: -maxRandomization...maxRandomization)
            let segmentMid = segmentStart.addingTimeInterval(segmentDuration / 2)
            var proposedTime = segmentMid.addingTimeInterval(randomOffset)
            
            // Ensure it's within the segment bounds
            proposedTime = max(segmentStart, min(segmentEnd, proposedTime))
            
            // Ensure minimum 30-minute spacing from specific times
            let minSpacing: TimeInterval = 1800 // 30 minutes
            var isTooClose = false
            for avoidTime in avoid {
                if abs(proposedTime.timeIntervalSince(avoidTime)) < minSpacing {
                    isTooClose = true
                    break
                }
            }
            
            // If too close to a specific time, shift it
            if isTooClose {
                // Try shifting forward first
                var shiftedTime = proposedTime.addingTimeInterval(minSpacing)
                if shiftedTime <= segmentEnd {
                    proposedTime = shiftedTime
                } else {
                    // Try shifting backward
                    shiftedTime = proposedTime.addingTimeInterval(-minSpacing)
                    if shiftedTime >= segmentStart {
                        proposedTime = shiftedTime
                    }
                }
            }
            
            times.append(proposedTime)
        }
        
        return times.sorted()
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

    // MARK: - Background App Refresh

    /// Schedule a background app refresh task to reschedule notifications
    /// This ensures notifications continue even if the user doesn't open the app
    func scheduleBackgroundRefresh() {
        #if os(iOS)
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskIdentifier)
        // Request to run no earlier than 12 hours from now
        // The system will decide the actual time based on user behavior and battery
        request.earliestBeginDate = Date(timeIntervalSinceNow: 12 * 60 * 60)

        do {
            try BGTaskScheduler.shared.submit(request)
            DispatchQueue.main.async {
                self.backgroundRefreshStatus = .scheduled
            }
        } catch let error as BGTaskScheduler.Error {
            DispatchQueue.main.async {
                switch error.code {
                case .unavailable:
                    self.backgroundRefreshStatus = .unavailable
                case .notPermitted:
                    self.backgroundRefreshStatus = .notPermitted
                case .tooManyPendingTaskRequests:
                    // Already have a pending request, which is fine
                    self.backgroundRefreshStatus = .scheduled
                @unknown default:
                    self.backgroundRefreshStatus = .unknown
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.backgroundRefreshStatus = .unknown
            }
        }
        #else
        DispatchQueue.main.async {
            self.backgroundRefreshStatus = .unavailable
        }
        #endif
    }

    /// Handle the background refresh task
    /// Called by the system when it grants background execution time
    #if os(iOS)
    func handleBackgroundRefresh(task: BGAppRefreshTask) {
        // Schedule the next background refresh first
        scheduleBackgroundRefresh()

        // Set up expiration handler
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        // Verify and reschedule notifications if needed
        getNextScheduledNotification { nextDate in
            let now = Date()
            let twentyFourHoursFromNow = now.addingTimeInterval(24 * 60 * 60)

            if let nextDate = nextDate, nextDate <= twentyFourHoursFromNow {
                // Notifications are already scheduled, we're done
                task.setTaskCompleted(success: true)
                return
            }

            // Need to reschedule notifications
            self.scheduleNextNotification()
            task.setTaskCompleted(success: true)
        }
    }
    #endif
}
