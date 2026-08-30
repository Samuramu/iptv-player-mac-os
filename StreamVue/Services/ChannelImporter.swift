import Foundation
import SwiftData

/// Performs all heavy SwiftData work (import, delete, category counting) off the main thread.
@ModelActor
actor ChannelImporter {

    struct CategorySummary: Sendable {
        var counts: [String: Int]
        var total: Int
    }

    struct ImportedChannel: Sendable {
        var name: String
        var streamURL: String
        var logoURL: String
        var groupTitle: String
        var tvgId: String
        var tvgName: String
    }

    func hasChannels(providerID: UUID) throws -> Bool {
        var descriptor = FetchDescriptor<Channel>(predicate: #Predicate { $0.providerID == providerID })
        descriptor.fetchLimit = 1
        return try modelContext.fetchCount(descriptor) > 0
    }

    func categorySummary(providerID: UUID) throws -> CategorySummary {
        var descriptor = FetchDescriptor<Channel>(predicate: #Predicate { $0.providerID == providerID })
        descriptor.propertiesToFetch = [\.groupTitle]
        let all = try modelContext.fetch(descriptor)
        var counts: [String: Int] = [:]
        for ch in all { counts[ch.groupTitle, default: 0] += 1 }
        return CategorySummary(counts: counts, total: all.count)
    }

    /// Replaces the provider's channels with `items`. Existing channel IDs are preserved
    /// (matched by stream URL) so favorites and the current selection survive a refresh.
    /// The old data stays in place until the new set is written, then everything is saved once.
    func replaceChannels(providerID: UUID, with items: [ImportedChannel]) throws -> Int {
        let existing = try modelContext.fetch(FetchDescriptor<Channel>(
            predicate: #Predicate { $0.providerID == providerID }
        ))
        var idByURL: [String: UUID] = [:]
        for ch in existing where idByURL[ch.streamURL] == nil { idByURL[ch.streamURL] = ch.id }
        for ch in existing { modelContext.delete(ch) }

        let oldCategories = try modelContext.fetch(FetchDescriptor<ChannelCategory>(
            predicate: #Predicate { $0.providerID == providerID }
        ))
        for cat in oldCategories { modelContext.delete(cat) }

        var seenCategories = Set<String>()
        for (index, item) in items.enumerated() {
            let channel = Channel(
                name: item.name, streamURL: item.streamURL, logoURL: item.logoURL,
                groupTitle: item.groupTitle, tvgId: item.tvgId, tvgName: item.tvgName,
                providerID: providerID, channelNumber: index + 1
            )
            if let oldID = idByURL[item.streamURL] { channel.id = oldID }
            modelContext.insert(channel)
            if seenCategories.insert(item.groupTitle).inserted {
                modelContext.insert(ChannelCategory(name: item.groupTitle, providerID: providerID))
            }
        }
        try modelContext.save()
        return items.count
    }
}
