import Foundation
import SwiftData

@Model
final class Channel {
    var id: UUID
    var name: String
    var streamURL: String
    var logoURL: String
    var groupTitle: String
    var tvgId: String
    var tvgName: String
    var providerID: UUID
    var channelNumber: Int

    init(
        name: String,
        streamURL: String,
        logoURL: String = "",
        groupTitle: String = "Uncategorized",
        tvgId: String = "",
        tvgName: String = "",
        providerID: UUID,
        channelNumber: Int = 0
    ) {
        self.id = UUID()
        self.name = name
        self.streamURL = streamURL
        self.logoURL = logoURL
        self.groupTitle = groupTitle
        self.tvgId = tvgId
        self.tvgName = tvgName
        self.providerID = providerID
        self.channelNumber = channelNumber
    }
}
