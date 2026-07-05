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
        logger.info("notification_manager_init", metadata: ["status": "starting"])
        UNUserNotificationCenter.current().delegate = self
        checkAuthorization()

#if canImport(UIKit)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
#endif
        logger.info("notification_manager_init", metadata: ["status": "complete"])
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        #if os(macOS)
        backgroundActivityScheduler?.invalidate()
        #endif
    }
    
    @objc private func appWillEnterForeground() {
        logger.info("app_foreground", metadata: ["action": "verify_notifications"])
        checkAuthorization()
        verifyNotificationScheduled()
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        logger.info("notification_present", metadata: ["identifier": "\(notification.request.identifier)", "body": "\(notification.request.content.body)"])
        completionHandler([.banner, .list, .sound])
    }

    // Called when the user interacts with (taps) a notification
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        logger.info("notification_interaction", metadata: ["identifier": "\(response.notification.request.identifier)", "action": "\(response.actionIdentifier)"])
        // Re-resolve random phrases and times when the user engages
        scheduleNextNotification()
        completionHandler()
    }
    
    func requestAuthorization() {
        logger.info("authorization_request")
        // .criticalAlert requires an Apple-granted entitlement this app doesn't
        // have, and requesting it without one fails the entire authorization
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            self.logger.info("authorization_response", metadata: ["granted": "\(granted)", "error": "\(error?.localizedDescription ?? "none")"])
            DispatchQueue.main.async {
                self.checkAuthorization()
            }
        }
    }

    func checkAuthorization() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            self.logger.debug("authorization_status", metadata: ["status": "\(settings.authorizationStatus.rawValue)"])
            DispatchQueue.main.async {
                self.authorizationStatus = settings.authorizationStatus
            }
        }
    }
    

    func scheduleTestNotification() {
        logger.info("test_notification", metadata: ["status": "scheduling"])
        let content = UNMutableNotificationContent()
        content.title = "Mantra Test"
        content.body = "This is a test notification. You got this!"
        content.sound = .default
        // .critical is silently downgraded without the critical-alerts entitlement
        content.interruptionLevel = .timeSensitive

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                self.logger.error("test_notification", metadata: ["status": "failed", "error": "\(error.localizedDescription)"])
            } else {
                self.logger.info("test_notification", metadata: ["status": "scheduled"])
            }
        }
    }

    func cancelAll() {
        logger.info("notifications_cancel_all")
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
    
    // MARK: - Scheduled Entry Support
    
    /// Cache phrases to UserDefaults for background access
    func cachePhrasesForBackground(_ phrases: [Phrase]) {
        let phraseDict = Dictionary(uniqueKeysWithValues: phrases.filter { $0.isEnabled }.map { ($0.id, $0.text) })
        if let data = try? JSONEncoder().encode(phraseDict) {
            UserDefaults.standard.set(data, forKey: "CachedPhrases")
            logger.debug("phrases_cached", metadata: ["count": "\(phraseDict.count)"])
        }
    }

    /// Load cached phrases from UserDefaults
    private func loadCachedPhrases() -> [UUID: String] {
        guard let data = UserDefaults.standard.data(forKey: "CachedPhrases"),
              let phrases = try? JSONDecoder().decode([UUID: String].self, from: data) else {
            logger.warning("phrases_cache_empty")
            return [:]
        }
        logger.debug("phrases_loaded", metadata: ["count": "\(phrases.count)"])
        return phrases
    }
    
    /// Schedule repeating notifications for all enabled scheduled entries.
    ///
    /// Every request uses a repeating `UNCalendarNotificationTrigger`, so once
    /// scheduled, notifications keep firing indefinitely without the app ever
    /// being launched again — delivery does not depend on background refresh.
    ///
    /// Entries with a specific phrase and specific time use one daily repeating
    /// trigger. Entries with a random phrase and/or random time use one weekly
    /// repeating trigger per weekday, each with an independently resolved phrase
    /// and time, so content still varies day to day while the app stays closed.
    /// Whenever the app does run (foreground, notification tap, or background
    /// refresh), everything is re-resolved so the randomness stays fresh.
    func scheduleNextNotification(completion: (() -> Void)? = nil) {
        logger.info("schedule_notifications", metadata: ["status": "starting"])
        cancelAll()
        let schedule = Schedule.load()
        guard schedule.isEnabled else {
            logger.info("schedule_notifications", metadata: ["status": "skipped", "reason": "schedule_disabled"])
            DispatchQueue.main.async {
                self.nextNotificationDate = nil
            }
            completion?()
            return
        }

        let phrases = loadCachedPhrases()
        guard !phrases.isEmpty else {
            logger.warning("schedule_notifications", metadata: ["status": "skipped", "reason": "no_phrases"])
            DispatchQueue.main.async {
                self.nextNotificationDate = nil
            }
            completion?()
            return
        }

        let enabledEntries = schedule.scheduledEntries.filter { $0.isEnabled }
        guard !enabledEntries.isEmpty else {
            logger.info("schedule_notifications", metadata: ["status": "skipped", "reason": "no_enabled_entries"])
            DispatchQueue.main.async {
                self.nextNotificationDate = nil
            }
            completion?()
            return
        }

        logger.info("schedule_notifications", metadata: [
            "status": "processing",
            "enabled_entries": "\(enabledEntries.count)",
            "phrases": "\(phrases.count)",
            "start_time": "\(schedule.startTime)",
            "end_time": "\(schedule.endTime)"
        ])

        let requests = buildNotificationRequests(for: enabledEntries, schedule: schedule, phrases: phrases)

        let group = DispatchGroup()
        for request in requests {
            group.enter()
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    self.logger.error("schedule_notification", metadata: [
                        "status": "failed",
                        "id": "\(request.identifier)",
                        "error": "\(error.localizedDescription)"
                    ])
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            self.logger.info("schedule_notifications", metadata: [
                "status": "complete",
                "requests": "\(requests.count)"
            ])
            // Update the next-notification display from the actual pending requests
            self.getNextScheduledNotification { _ in }
            completion?()
        }

        // Background refresh only re-resolves random phrases/times when the
        // system allows, and delivery does not depend on it
        scheduleBackgroundRefresh()
    }

    /// Maximum pending local notification requests the system keeps per app
    private static let maxPendingNotifications = 64

    /// Build repeating notification requests for the enabled entries.
    ///
    /// Fully-specific entries cost one request. Entries with randomness cost
    /// seven (one per weekday). If the weekday fan-out would exceed the system's
    /// pending request budget, entries are degraded to a single daily repeating
    /// request with a frozen phrase and time until everything fits.
    private func buildNotificationRequests(for entries: [ScheduledEntry], schedule: Schedule, phrases: [UUID: String]) -> [UNNotificationRequest] {
        let calendar = Calendar.current
        let now = Date()

        let startComponents = calendar.dateComponents([.hour, .minute], from: schedule.startTime)
        let endComponents = calendar.dateComponents([.hour, .minute], from: schedule.endTime)

        guard let startHour = startComponents.hour, let startMinute = startComponents.minute,
              let endHour = endComponents.hour, let endMinute = endComponents.minute,
              let windowStart = calendar.date(bySettingHour: startHour, minute: startMinute, second: 0, of: now),
              let windowEnd = calendar.date(bySettingHour: endHour, minute: endMinute, second: 0, of: now) else {
            logger.error("build_requests", metadata: ["status": "failed", "reason": "invalid_window"])
            return []
        }

        // Specific-time entries anchor the spacing for random times
        let specificDates: [Date] = entries.compactMap { entry in
            if case .specific(let hour, let minute) = entry.timeMode {
                return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now)
            }
            return nil
        }

        // An entry with any randomness gets one weekly trigger per weekday so
        // its phrase/time still vary day to day, while fully-specific entries repeat daily
        func hasVariety(_ entry: ScheduledEntry) -> Bool {
            if case .specific = entry.phraseMode, case .specific = entry.timeMode {
                return false
            }
            return true
        }

        var varietyIds = Set(entries.filter(hasVariety).map(\.id))
        func slotCost() -> Int {
            (entries.count - varietyIds.count) + varietyIds.count * 7
        }
        while slotCost() > Self.maxPendingNotifications, let degraded = varietyIds.first {
            varietyIds.remove(degraded)
            logger.warning("build_requests", metadata: [
                "status": "degraded",
                "reason": "pending_budget",
                "entry_id": "\(degraded)"
            ])
        }

        func makeRequest(identifier: String, phrase: String, dateMatching components: DateComponents) -> UNNotificationRequest {
            let content = UNMutableNotificationContent()
            content.title = "Mantra"
            content.body = phrase
            content.sound = .default
            // .critical is silently downgraded without the critical-alerts entitlement
            content.interruptionLevel = .timeSensitive
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        }

        // Resolve hour/minute for an entry, consuming from randomTimes for random entries
        func resolveTime(for entry: ScheduledEntry, randomTimes: [Date], randomIndex: inout Int) -> (hour: Int, minute: Int)? {
            switch entry.timeMode {
            case .specific(let hour, let minute):
                return (hour, minute)
            case .random:
                guard randomIndex < randomTimes.count else { return nil }
                let components = calendar.dateComponents([.hour, .minute], from: randomTimes[randomIndex])
                randomIndex += 1
                guard let hour = components.hour, let minute = components.minute else { return nil }
                return (hour, minute)
            }
        }

        var requests: [UNNotificationRequest] = []

        // Daily repeating requests: fully-specific entries plus any degraded ones
        let dailyEntries = entries.filter { !varietyIds.contains($0.id) }
        let dailyRandomCount = dailyEntries.filter { $0.timeMode == .random }.count
        let dailyRandomTimes = calculateRandomTimes(count: dailyRandomCount, start: windowStart, end: windowEnd, avoid: specificDates)
        var dailyRandomIndex = 0
        for entry in dailyEntries {
            guard let phrase = resolvePhrase(for: entry, phrases: phrases) else {
                logger.warning("build_requests", metadata: ["status": "skipped", "reason": "phrase_not_found", "entry_id": "\(entry.id)"])
                continue
            }
            guard let time = resolveTime(for: entry, randomTimes: dailyRandomTimes, randomIndex: &dailyRandomIndex) else {
                continue
            }
            var components = DateComponents()
            components.hour = time.hour
            components.minute = time.minute
            requests.append(makeRequest(identifier: "mantra-\(entry.id.uuidString)-daily", phrase: phrase, dateMatching: components))
        }

        // Weekly repeating requests: one per weekday per variety entry, with
        // phrase and time resolved independently for each weekday
        let weeklyEntries = entries.filter { varietyIds.contains($0.id) }
        let weeklyRandomCount = weeklyEntries.filter { $0.timeMode == .random }.count
        for weekday in 1...7 {
            let randomTimes = calculateRandomTimes(count: weeklyRandomCount, start: windowStart, end: windowEnd, avoid: specificDates)
            var randomIndex = 0
            for entry in weeklyEntries {
                guard let phrase = resolvePhrase(for: entry, phrases: phrases) else {
                    logger.warning("build_requests", metadata: ["status": "skipped", "reason": "phrase_not_found", "entry_id": "\(entry.id)"])
                    continue
                }
                guard let time = resolveTime(for: entry, randomTimes: randomTimes, randomIndex: &randomIndex) else {
                    continue
                }
                var components = DateComponents()
                components.weekday = weekday
                components.hour = time.hour
                components.minute = time.minute
                requests.append(makeRequest(identifier: "mantra-\(entry.id.uuidString)-weekday\(weekday)", phrase: phrase, dateMatching: components))
            }
        }

        logger.info("build_requests", metadata: [
            "status": "complete",
            "daily_entries": "\(dailyEntries.count)",
            "weekly_entries": "\(weeklyEntries.count)",
            "requests": "\(requests.count)"
        ])

        return requests
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
        logger.debug("next_notification_query")
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            self.logger.debug("pending_notifications", metadata: ["count": "\(requests.count)"])

            // Find the earliest notification
            let nextDate = requests.compactMap { request -> Date? in
                if let trigger = request.trigger as? UNCalendarNotificationTrigger,
                   let nextTriggerDate = trigger.nextTriggerDate() {
                    return nextTriggerDate
                }
                return nil
            }.min()

            self.logger.info("next_notification", metadata: [
                "date": "\(nextDate?.description ?? "none")",
                "pending_count": "\(requests.count)"
            ])

            DispatchQueue.main.async {
                self.nextNotificationDate = nextDate
                completion(nextDate)
            }
        }
    }

    /// Verify that a notification is scheduled within the next 24 hours
    /// If not, clear all notifications and reschedule
    ///
    /// With repeating triggers every entry fires daily, so a healthy install
    /// always has something due within 24 hours. This is a safety net for
    /// cases where the pending requests were lost (e.g. device restore)
    func verifyNotificationScheduled() {
        logger.info("verify_notifications")
        getNextScheduledNotification { nextDate in
            let now = Date()
            let twentyFourHoursFromNow = now.addingTimeInterval(24 * 60 * 60)

            // Check if we have a notification scheduled within the next 24 hours
            if let nextDate = nextDate, nextDate <= twentyFourHoursFromNow {
                self.logger.info("verify_notifications", metadata: [
                    "status": "valid",
                    "next_date": "\(nextDate)",
                    "hours_from_now": "\(nextDate.timeIntervalSince(now) / 3600)"
                ])
                return
            }

            if let nextDate = nextDate {
                self.logger.warning("verify_notifications", metadata: [
                    "status": "stale",
                    "action": "rescheduling",
                    "next_date": "\(nextDate)",
                    "hours_from_now": "\(nextDate.timeIntervalSince(now) / 3600)"
                ])
            } else {
                self.logger.warning("verify_notifications", metadata: ["status": "empty", "action": "rescheduling"])
            }

            // No notification scheduled within 24 hours, reschedule
            self.scheduleNextNotification()
        }
    }

    // MARK: - Background App Refresh

    /// Schedule a background app refresh task to reschedule notifications
    /// This ensures notifications continue even if the user doesn't open the app
    func scheduleBackgroundRefresh() {
        logger.info("background_refresh", metadata: ["status": "scheduling"])
        #if os(iOS)
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskIdentifier)
        // Request to run no earlier than 12 hours from now
        // The system will decide the actual time based on user behavior and battery
        request.earliestBeginDate = Date(timeIntervalSinceNow: 12 * 60 * 60)

        do {
            try BGTaskScheduler.shared.submit(request)
            logger.info("background_refresh", metadata: [
                "status": "scheduled",
                "earliest_begin_date": "\(request.earliestBeginDate?.description ?? "none")"
            ])
            DispatchQueue.main.async {
                self.backgroundRefreshStatus = .scheduled
            }
        } catch let error as BGTaskScheduler.Error {
            logger.warning("background_refresh", metadata: [
                "status": "error",
                "code": "\(error.code.rawValue)",
                "error": "\(error.localizedDescription)"
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
            logger.error("background_refresh", metadata: ["status": "error", "error": "\(error.localizedDescription)"])
            DispatchQueue.main.async {
                self.backgroundRefreshStatus = .unknown
            }
        }
        #elseif os(macOS)
        // Use NSBackgroundActivityScheduler on macOS
        // The scheduler repeats indefinitely, so keep the existing one if
        // already configured. Recreating it here would invalidate it from
        // inside its own execution block when rescheduling
        if backgroundActivityScheduler != nil {
            logger.debug("background_activity", metadata: ["platform": "macos", "status": "already_configured"])
            return
        }

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

            self.logger.info("background_activity", metadata: ["platform": "macos", "status": "triggered"])

            // Check if we should defer (system conditions changed)
            if scheduler.shouldDefer {
                self.logger.info("background_activity", metadata: ["platform": "macos", "status": "deferred"])
                completion(.deferred)
                return
            }

            // Delivery doesn't depend on this activity ever running: all
            // requests use repeating triggers. Rescheduling here re-resolves
            // random phrases and times so variety stays fresh.
            self.scheduleNextNotification {
                completion(.finished)
            }
        }

        backgroundActivityScheduler = scheduler
        logger.info("background_activity", metadata: [
            "platform": "macos",
            "status": "configured",
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
        logger.info("background_task", metadata: ["platform": "ios", "status": "started", "task_id": "\(task.identifier)"])

        // Schedule the next background refresh first
        scheduleBackgroundRefresh()

        // Set up expiration handler
        task.expirationHandler = {
            self.logger.warning("background_task", metadata: ["platform": "ios", "status": "expired"])
            task.setTaskCompleted(success: false)
        }

        // Delivery doesn't depend on this task ever running: all requests use
        // repeating triggers. Rescheduling here re-resolves random phrases and
        // times so variety stays fresh on long-unopened installs.
        scheduleNextNotification {
            self.logger.info("background_task", metadata: ["platform": "ios", "status": "complete"])
            task.setTaskCompleted(success: true)
        }
    }
    #endif
}
