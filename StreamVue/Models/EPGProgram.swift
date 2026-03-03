import Foundation
import SwiftData

@Model
final class EPGProgram {
    var id: UUID
    var channelId: String
    var title: String
    var desc: String
    var startTime: Date
    var stopTime: Date
    var providerID: UUID

    init(
        channelId: String,
        title: String,
        desc: String = "",
        startTime: Date,
        stopTime: Date,
        providerID: UUID
    ) {
        self.id = UUID()
        self.channelId = channelId
        self.title = title
        self.desc = desc
        self.startTime = startTime
        self.stopTime = stopTime
        self.providerID = providerID
    }

    var isCurrentlyAiring: Bool {
        let now = Date()
        return startTime <= now && stopTime > now
    }

    var progress: Double {
        let now = Date()
        let total = stopTime.timeIntervalSince(startTime)
        let elapsed = now.timeIntervalSince(startTime)
        guard total > 0 else { return 0 }
        return min(max(elapsed / total, 0), 1)
    }
}
