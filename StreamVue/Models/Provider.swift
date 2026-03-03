import Foundation
import SwiftData

enum ProviderType: String, Codable, CaseIterable {
    case m3u = "M3U/M3U8 URL"
    case xtream = "Xtream Codes"
}

@Model
final class Provider {
    var id: UUID
    var name: String
    var type: ProviderType
    var url: String
    var username: String
    var password: String
    var epgURL: String
    var isEnabled: Bool
    var lastRefresh: Date?
    var channelCount: Int

    init(
        name: String,
        type: ProviderType,
        url: String,
        username: String = "",
        password: String = "",
        epgURL: String = "",
        isEnabled: Bool = true
    ) {
        self.id = UUID()
        self.name = name
        self.type = type
        self.url = url
        self.username = username
        self.password = password
        self.epgURL = epgURL
        self.isEnabled = isEnabled
        self.lastRefresh = nil
        self.channelCount = 0
    }

    var xtreamBaseURL: String? {
        guard type == .xtream else { return nil }
        var base = url
        if base.hasSuffix("/") { base.removeLast() }
        return base
    }
}
