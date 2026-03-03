import Foundation
import SwiftData

@Model
final class Favorite {
    var id: UUID
    var channelID: UUID
    var dateAdded: Date

    init(channelID: UUID) {
        self.id = UUID()
        self.channelID = channelID
        self.dateAdded = Date()
    }
}
