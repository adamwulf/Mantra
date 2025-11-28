import Foundation

struct Schedule: Codable {
    var startTime: Date
    var endTime: Date
    var scheduledEntries: [ScheduledEntry]
    var isEnabled: Bool
    
    static let defaultSchedule = Schedule(
        startTime: Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date(),
        endTime: Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: Date()) ?? Date(),
        scheduledEntries: [],
        isEnabled: false
    )
}

extension Schedule {
    private static let key = "MantraSchedule"
    
    static func load() -> Schedule {
        if let data = UserDefaults.standard.data(forKey: key),
           let schedule = try? JSONDecoder().decode(Schedule.self, from: data) {
            return schedule
        }
        return .defaultSchedule
    }
    
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Schedule.key)
        }
    }
}
