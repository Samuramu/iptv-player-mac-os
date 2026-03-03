import Foundation
import SwiftData

@Model
final class ChannelCategory {
    var id: UUID
    var name: String
    var providerID: UUID
    var channelCount: Int

    init(name: String, providerID: UUID, channelCount: Int = 0) {
        self.id = UUID()
        self.name = name
        self.providerID = providerID
        self.channelCount = channelCount
    }
}
