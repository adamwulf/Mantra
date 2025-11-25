import Foundation
import SwiftData

@Model
final class Phrase {
    var text: String
    var isEnabled: Bool
    var createdAt: Date
    
    init(text: String, isEnabled: Bool = true, createdAt: Date = Date()) {
        self.text = text
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }
}
