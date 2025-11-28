import Foundation

enum PhraseMode: Codable, Equatable {
    case specific(phraseId: UUID)
    case random
    
    enum CodingKeys: String, CodingKey {
        case type
        case phraseId
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "specific":
            let id = try container.decode(UUID.self, forKey: .phraseId)
            self = .specific(phraseId: id)
        case "random":
            self = .random
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Invalid phrase mode type")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .specific(let phraseId):
            try container.encode("specific", forKey: .type)
            try container.encode(phraseId, forKey: .phraseId)
        case .random:
            try container.encode("random", forKey: .type)
        }
    }
}

enum TimeMode: Codable, Equatable {
    case specific(hour: Int, minute: Int)
    case random
    
    enum CodingKeys: String, CodingKey {
        case type
        case hour
        case minute
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "specific":
            let hour = try container.decode(Int.self, forKey: .hour)
            let minute = try container.decode(Int.self, forKey: .minute)
            self = .specific(hour: hour, minute: minute)
        case "random":
            self = .random
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Invalid time mode type")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .specific(let hour, let minute):
            try container.encode("specific", forKey: .type)
            try container.encode(hour, forKey: .hour)
            try container.encode(minute, forKey: .minute)
        case .random:
            try container.encode("random", forKey: .type)
        }
    }
}

struct ScheduledEntry: Codable, Identifiable, Equatable {
    var id: UUID
    var phraseMode: PhraseMode
    var timeMode: TimeMode
    var isEnabled: Bool
    
    init(id: UUID = UUID(), phraseMode: PhraseMode, timeMode: TimeMode, isEnabled: Bool = true) {
        self.id = id
        self.phraseMode = phraseMode
        self.timeMode = timeMode
        self.isEnabled = isEnabled
    }
    
    /// Get a display string for the phrase mode
    func phraseDisplayText(phrases: [UUID: String]) -> String {
        switch phraseMode {
        case .specific(let phraseId):
            return phrases[phraseId] ?? "Unknown Phrase"
        case .random:
            return "Random Phrase"
        }
    }
    
    /// Get a display string for the time mode
    func timeDisplayText() -> String {
        switch timeMode {
        case .specific(let hour, let minute):
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            let calendar = Calendar.current
            if let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) {
                return formatter.string(from: date)
            }
            return "\(hour):\(String(format: "%02d", minute))"
        case .random:
            return "Random Time"
        }
    }
}
