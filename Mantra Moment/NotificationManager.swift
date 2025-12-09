import Foundation
import UserNotifications
import Combine
import BackgroundTasks
import Logging
#if canImport(UIKit)
import UIKit
#endif

class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    private let logger = Logger(label: "NotificationManager")

    /// Background task identifier for rescheduling notifications
    static let backgroundTaskIdentifier = "com.milestonemade.Mantra.refresh"

    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published var nextNotificationDate: Date?
    @Published var backgroundRefreshStatus: BackgroundRefreshStatus = .unknown

    #if os(macOS)
    /// Background activity scheduler for macOS
    private var backgroundActivityScheduler: NSBackgroundActivityScheduler?
    #endif

    enum BackgroundRefreshStatus: String {
        case unknown = "Unknown"
        case scheduled = "Scheduled"
        case unavailable = "Unavailable"
        case notPermitted = "Not Permitted"
        case tooManyRequests = "Too Many Requests"
    }
    
    override private init() {
        super.init()
        logger.info("NotificationManager initializing")
        UNUserNotificationCenter.current().delegate = self
        checkAuthorization()

#if canImport(UIKit)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
#endif
        logger.info("NotificationManager initialized")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        #if os(macOS)
        backgroundActivityScheduler?.invalidate()
        #endif
    }
    
    @objc private func appWillEnterForeground() {
        logger.info("App will enter foreground - checking authorization and verifying notifications")
        checkAuthorization()
        verifyNotificationScheduled()
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        logger.info("Will present notification", metadata: ["identifier": "\(notification.request.identifier)", "body": "\(notification.request.content.body)"])
        completionHandler([.banner, .list, .sound])
    }

    // Called when the user interacts with (taps) a notification
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        logger.info("User interacted with notification", metadata: ["identifier": "\(response.notification.request.identifier)", "action": "\(response.actionIdentifier)"])
        // Schedule the next batch of notifications when user engages
        scheduleNextNotification()
        completionHandler()
    }
    
    func requestAuthorization() {
        logger.info("Requesting notification authorization")
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge, .criticalAlert]) { granted, error in
            self.logger.info("Authorization response", metadata: ["granted": "\(granted)", "error": "\(error?.localizedDescription ?? "none")"])
            DispatchQueue.main.async {
                self.checkAuthorization()
            }
        }
    }

    func checkAuthorization() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            self.logger.debug("Authorization status checked", metadata: ["status": "\(settings.authorizationStatus.rawValue)"])
            DispatchQueue.main.async {
                self.authorizationStatus = settings.authorizationStatus
            }
        }
    }
    

    func scheduleTestNotification() {
        logger.info("Scheduling test notification")
        let content = UNMutableNotificationContent()
        content.title = "Mantra Test"
        content.body = "This is a test notification. You got this!"
        content.sound = .default
        content.interruptionLevel = .critical

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                self.logger.error("Failed to schedule test notification", metadata: ["error": "\(error.localizedDescription)"])
            } else {
                self.logger.info("Test notification scheduled successfully")
            }
        }
    }

    func cancelAll() {
        logger.info("Cancelling all pending notifications")
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
    
    // MARK: - Scheduled Entry Support
    
    /// Cache phrases to UserDefaults for background access
    func cachePhrasesForBackground(_ phrases: [Phrase]) {
        let phraseDict = Dictionary(uniqueKeysWithValues: phrases.filter { $0.isEnabled }.map { ($0.id, $0.text) })
        if let data = try? JSONEncoder().encode(phraseDict) {
            UserDefaults.standard.set(data, forKey: "CachedPhrases")
            logger.debug("Cached phrases for background access", metadata: ["count": "\(phraseDict.count)"])
        }
    }

    /// Load cached phrases from UserDefaults
    private func loadCachedPhrases() -> [UUID: String] {
        guard let data = UserDefaults.standard.data(forKey: "CachedPhrases"),
              let phrases = try? JSONDecoder().decode([UUID: String].self, from: data) else {
            logger.warning("No cached phrases found")
            return [:]
        }
        logger.debug("Loaded cached phrases", metadata: ["count": "\(phrases.count)"])
        return phrases
    }
    
    /// Schedule notifications for all enabled scheduled entries
    func scheduleNextNotification() {
        logger.info("scheduleNextNotification called")
        cancelAll()
        let schedule = Schedule.load()
        guard schedule.isEnabled else {
            logger.info("Schedule is disabled, not scheduling notifications")
            DispatchQueue.main.async {
                self.nextNotificationDate = nil
            }
            return
        }

        let phrases = loadCachedPhrases()
        guard !phrases.isEmpty else {
            logger.warning("No phrases available, cannot schedule notifications")
            DispatchQueue.main.async {
                self.nextNotificationDate = nil
            }
            return
        }

        let enabledEntries = schedule.scheduledEntries.filter { $0.isEnabled }
        guard !enabledEntries.isEmpty else {
            logger.info("No enabled schedule entries, not scheduling notifications")
            DispatchQueue.main.async {
                self.nextNotificationDate = nil
            }
            return
        }

        logger.info("Scheduling notifications", metadata: [
            "enabledEntries": "\(enabledEntries.count)",
            "phrases": "\(phrases.count)",
            "startTime": "\(schedule.startTime)",
            "endTime": "\(schedule.endTime)"
        ])

        // Calculate times for all entries
        let times = calculateNotificationTimes(for: enabledEntries, schedule: schedule)

        let now = Date()
        var earliestFutureTime: Date?
        var scheduledCount = 0
        var errorCount = 0

        // Schedule each entry
        for (entry, time) in zip(enabledEntries, times) {
            guard let phraseText = resolvePhrase(for: entry, phrases: phrases) else {
                logger.warning("Could not resolve phrase for entry", metadata: ["entryId": "\(entry.id)"])
                continue
            }

            let content = UNMutableNotificationContent()
            content.title = "Mantra"
            content.body = phraseText
            content.sound = .default
            content.interruptionLevel = .critical

            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: time)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

            let requestId = UUID().uuidString
            let request = UNNotificationRequest(identifier: requestId, content: content, trigger: trigger)

            logger.debug("Scheduling notification", metadata: [
                "id": "\(requestId)",
                "time": "\(time)",
                "phrase": "\(phraseText.prefix(30))"
            ])

            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    errorCount += 1
                    self.logger.error("Failed to schedule notification", metadata: [
                        "id": "\(requestId)",
                        "error": "\(error.localizedDescription)"
                    ])
                } else {
                    scheduledCount += 1
                    DispatchQueue.main.async {
                        // Only consider future times for "next notification" display
                        if time > now && (earliestFutureTime == nil || time < earliestFutureTime!) {
                            earliestFutureTime = time
                            self.nextNotificationDate = time
                        }
                    }
                }
            }
        }

        logger.info("Notification scheduling complete", metadata: [
            "scheduled": "\(scheduledCount)",
            "errors": "\(errorCount)",
            "nextTime": "\(earliestFutureTime?.description ?? "none")"
        ])

        // Update nextNotificationDate on main thread after all scheduling
        DispatchQueue.main.async {
            if earliestFutureTime == nil {
                self.logger.info("All scheduled times are in the past, clearing nextNotificationDate")
                // All times were in the past, clear the display
                self.nextNotificationDate = nil
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
        logger.debug("Getting next scheduled notification")
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            self.logger.debug("Pending notification requests", metadata: ["count": "\(requests.count)"])

            // Find the earliest notification
            let nextDate = requests.compactMap { request -> Date? in
                if let trigger = request.trigger as? UNCalendarNotificationTrigger,
                   let nextTriggerDate = trigger.nextTriggerDate() {
                    return nextTriggerDate
                }
                return nil
            }.min()

            self.logger.info("Next scheduled notification", metadata: [
                "date": "\(nextDate?.description ?? "none")",
                "pendingCount": "\(requests.count)"
            ])

            DispatchQueue.main.async {
                self.nextNotificationDate = nextDate
                completion(nextDate)
            }
        }
    }

    /// Verify that a notification is scheduled within the next 24 hours
    /// If not, clear all notifications and reschedule
    func verifyNotificationScheduled() {
        logger.info("Verifying notifications are scheduled")
        getNextScheduledNotification { nextDate in
            let now = Date()
            let twentyFourHoursFromNow = now.addingTimeInterval(24 * 60 * 60)

            // Check if we have a notification scheduled within the next 24 hours
            if let nextDate = nextDate, nextDate <= twentyFourHoursFromNow {
                self.logger.info("Notifications verified - next notification is within 24 hours", metadata: [
                    "nextDate": "\(nextDate)",
                    "hoursFromNow": "\(nextDate.timeIntervalSince(now) / 3600)"
                ])
                return
            }

            if let nextDate = nextDate {
                self.logger.warning("Next notification is more than 24 hours away, rescheduling", metadata: [
                    "nextDate": "\(nextDate)",
                    "hoursFromNow": "\(nextDate.timeIntervalSince(now) / 3600)"
                ])
            } else {
                self.logger.warning("No notifications scheduled, rescheduling")
            }

            // No notification scheduled within 24 hours, reschedule
            self.scheduleNextNotification()
        }
    }

    // MARK: - Background App Refresh

    /// Schedule a background app refresh task to reschedule notifications
    /// This ensures notifications continue even if the user doesn't open the app
    func scheduleBackgroundRefresh() {
        logger.info("Scheduling background refresh")
        #if os(iOS)
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskIdentifier)
        // Request to run no earlier than 12 hours from now
        // The system will decide the actual time based on user behavior and battery
        request.earliestBeginDate = Date(timeIntervalSinceNow: 12 * 60 * 60)

        do {
            try BGTaskScheduler.shared.submit(request)
            logger.info("Background refresh task submitted successfully", metadata: [
                "earliestBeginDate": "\(request.earliestBeginDate?.description ?? "none")"
            ])
            DispatchQueue.main.async {
                self.backgroundRefreshStatus = .scheduled
            }
        } catch let error as BGTaskScheduler.Error {
            logger.warning("Background task scheduler error", metadata: [
                "code": "\(error.code.rawValue)",
                "description": "\(error.localizedDescription)"
            ])
            DispatchQueue.main.async {
                switch error.code {
                case .unavailable:
                    self.backgroundRefreshStatus = .unavailable
                case .notPermitted:
                    self.backgroundRefreshStatus = .notPermitted
                case .tooManyPendingTaskRequests:
                    // Already have a pending request, which is fine
                    self.backgroundRefreshStatus = .scheduled
                case .immediateRunIneligible:
                    // Only applies to BGContinuedProcessingTaskRequest, not BGAppRefreshTaskRequest
                    self.backgroundRefreshStatus = .scheduled
                @unknown default:
                    self.backgroundRefreshStatus = .unknown
                }
            }
        } catch {
            logger.error("Unknown error scheduling background refresh", metadata: ["error": "\(error.localizedDescription)"])
            DispatchQueue.main.async {
                self.backgroundRefreshStatus = .unknown
            }
        }
        #elseif os(macOS)
        // Use NSBackgroundActivityScheduler on macOS
        // Invalidate any existing scheduler before creating a new one
        backgroundActivityScheduler?.invalidate()

        let scheduler = NSBackgroundActivityScheduler(identifier: Self.backgroundTaskIdentifier)
        scheduler.repeats = true
        // Run approximately every 12 hours
        scheduler.interval = 12 * 60 * 60
        // Allow flexibility of ±2 hours for optimal scheduling
        scheduler.tolerance = 2 * 60 * 60
        scheduler.qualityOfService = .background

        scheduler.schedule { [weak self] completion in
            guard let self = self else {
                completion(.finished)
                return
            }

            self.logger.info("macOS background activity triggered")

            // Check if we should defer (system conditions changed)
            if scheduler.shouldDefer {
                self.logger.info("macOS background activity deferred by system")
                completion(.deferred)
                return
            }

            // Verify and reschedule notifications if needed
            self.getNextScheduledNotification { nextDate in
                let now = Date()
                let twentyFourHoursFromNow = now.addingTimeInterval(24 * 60 * 60)

                if let nextDate = nextDate, nextDate <= twentyFourHoursFromNow {
                    self.logger.info("macOS background: notifications already scheduled", metadata: [
                        "nextDate": "\(nextDate)"
                    ])
                    completion(.finished)
                    return
                }

                self.logger.info("macOS background: rescheduling notifications")
                // Need to reschedule notifications
                self.scheduleNextNotification()
                completion(.finished)
            }
        }

        backgroundActivityScheduler = scheduler
        logger.info("macOS background activity scheduler configured", metadata: [
            "interval": "\(scheduler.interval)",
            "tolerance": "\(scheduler.tolerance)"
        ])
        DispatchQueue.main.async {
            self.backgroundRefreshStatus = .scheduled
        }
        #endif
    }

    /// Handle the background refresh task
    /// Called by the system when it grants background execution time
    #if os(iOS)
    func handleBackgroundRefresh(task: BGAppRefreshTask) {
        logger.info("iOS background refresh task started", metadata: ["taskIdentifier": "\(task.identifier)"])

        // Schedule the next background refresh first
        scheduleBackgroundRefresh()

        // Set up expiration handler
        task.expirationHandler = {
            self.logger.warning("iOS background refresh task expired")
            task.setTaskCompleted(success: false)
        }

        // Verify and reschedule notifications if needed
        getNextScheduledNotification { nextDate in
            let now = Date()
            let twentyFourHoursFromNow = now.addingTimeInterval(24 * 60 * 60)

            if let nextDate = nextDate, nextDate <= twentyFourHoursFromNow {
                self.logger.info("iOS background: notifications already scheduled", metadata: [
                    "nextDate": "\(nextDate)",
                    "hoursFromNow": "\(nextDate.timeIntervalSince(now) / 3600)"
                ])
                task.setTaskCompleted(success: true)
                return
            }

            if let nextDate = nextDate {
                self.logger.info("iOS background: next notification > 24h away, rescheduling", metadata: [
                    "nextDate": "\(nextDate)",
                    "hoursFromNow": "\(nextDate.timeIntervalSince(now) / 3600)"
                ])
            } else {
                self.logger.info("iOS background: no notifications scheduled, scheduling now")
            }

            // Need to reschedule notifications
            self.scheduleNextNotification()
            self.logger.info("iOS background refresh task completed successfully")
            task.setTaskCompleted(success: true)
        }
    }
    #endif
}
