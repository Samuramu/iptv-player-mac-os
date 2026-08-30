import Foundation
import SwiftData
import AppKit
import UniformTypeIdentifiers

/// Exports/imports providers (and favorites, keyed by stream URL) as a JSON file so a
/// setup can be saved locally and restored after a reinstall.
struct StreamVueBackup: Codable {
    struct ProviderRecord: Codable {
        var name: String
        var type: String
        var url: String
        var username: String
        var password: String
        var epgURL: String
        var isEnabled: Bool
        /// Stream URLs of favorited channels belonging to this provider.
        var favoriteStreamURLs: [String]
    }

    var version = 1
    var exportedAt = Date()
    var providers: [ProviderRecord]
}

@MainActor
enum BackupService {
    static let fileType = UTType.json

    static func makeBackup(context: ModelContext) throws -> StreamVueBackup {
        let providers = try context.fetch(FetchDescriptor<Provider>())
        let favoriteIDs = Set(try context.fetch(FetchDescriptor<Favorite>()).map(\.channelID))

        var records: [StreamVueBackup.ProviderRecord] = []
        for provider in providers {
            let providerID = provider.id
            var favoriteURLs: [String] = []
            if !favoriteIDs.isEmpty {
                var descriptor = FetchDescriptor<Channel>(predicate: #Predicate { $0.providerID == providerID })
                descriptor.propertiesToFetch = [\.id, \.streamURL]
                favoriteURLs = try context.fetch(descriptor)
                    .filter { favoriteIDs.contains($0.id) }
                    .map(\.streamURL)
            }
            records.append(.init(
                name: provider.name, type: provider.type.rawValue, url: provider.url,
                username: provider.username, password: provider.password, epgURL: provider.epgURL,
                isEnabled: provider.isEnabled, favoriteStreamURLs: favoriteURLs
            ))
        }
        return StreamVueBackup(providers: records)
    }

    /// Shows a save panel and writes the backup. Returns the written URL, or nil if cancelled.
    static func export(context: ModelContext) throws -> URL? {
        let backup = try makeBackup(context: context)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(backup)

        let panel = NSSavePanel()
        panel.allowedContentTypes = [fileType]
        panel.nameFieldStringValue = "StreamVue-providers.json"
        panel.title = "Export Providers"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        try data.write(to: url, options: .atomic)
        return url
    }

    struct ImportResult {
        var added: [Provider]
        var skipped: Int
        var pendingFavorites: [UUID: [String]]   // providerID -> stream URLs
    }

    /// Shows an open panel and merges providers from the file. Existing providers
    /// (same type + URL + username) are skipped. Favorites are returned so the caller can
    /// re-link them once the provider's channels have been loaded.
    static func importFromPanel(context: ModelContext) throws -> ImportResult? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [fileType]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Import Providers"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(StreamVueBackup.self, from: data)

        let existing = try context.fetch(FetchDescriptor<Provider>())
        var added: [Provider] = []
        var skipped = 0
        var pending: [UUID: [String]] = [:]

        for record in backup.providers {
            guard let type = ProviderType(rawValue: record.type) else { skipped += 1; continue }
            let match = existing.first { $0.type == type && $0.url == record.url && $0.username == record.username }
            let provider: Provider
            if let match {
                provider = match
                skipped += 1
            } else {
                provider = Provider(
                    name: record.name, type: type, url: record.url,
                    username: record.username, password: record.password,
                    epgURL: record.epgURL, isEnabled: record.isEnabled
                )
                context.insert(provider)
                added.append(provider)
            }
            if !record.favoriteStreamURLs.isEmpty {
                pending[provider.id] = record.favoriteStreamURLs
            }
        }
        try context.save()
        return ImportResult(added: added, skipped: skipped, pendingFavorites: pending)
    }

    /// Creates Favorite rows for channels of `providerID` whose stream URL is in `urls`.
    static func relinkFavorites(providerID: UUID, urls: [String], context: ModelContext) {
        guard !urls.isEmpty else { return }
        let wanted = Set(urls)
        let existingFavs = Set((try? context.fetch(FetchDescriptor<Favorite>()))?.map(\.channelID) ?? [])
        var descriptor = FetchDescriptor<Channel>(predicate: #Predicate { $0.providerID == providerID })
        descriptor.propertiesToFetch = [\.id, \.streamURL]
        guard let channels = try? context.fetch(descriptor) else { return }
        for ch in channels where wanted.contains(ch.streamURL) && !existingFavs.contains(ch.id) {
            context.insert(Favorite(channelID: ch.id))
        }
        try? context.save()
    }
}
