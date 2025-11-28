import Foundation
import SwiftData

@Model
final class Phrase {
    var id: UUID
    var text: String
    var isEnabled: Bool
    var createdAt: Date
    
    init(id: UUID = UUID(), text: String, isEnabled: Bool = true, createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }
}
