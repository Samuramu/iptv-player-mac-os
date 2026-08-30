import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class ProviderManager {
    var isLoading = false
    var errorMessage: String?
    var channels: [Channel] = []
    var categories: [String] = []
    var categoryCounts: [String: Int] = [:]
    var epgPrograms: [EPGProgram] = []
    var totalChannelCount = 0

    private(set) var currentProviderID: UUID?
    private var modelContext: ModelContext?

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    /// Bumped whenever the channel table for the current provider changes on disk,
    /// so views can re-run their current query.
    var reloadToken = 0

    private var importer: ChannelImporter?

    /// Loads a provider. Cached channels/categories appear immediately; if a refresh is
    /// needed it runs in the background and the UI is swapped over once the new data is saved.
    func loadChannels(for provider: Provider, forceRefresh: Bool = false) async {
        guard let context = modelContext else { return }
        if importer == nil { importer = ChannelImporter(modelContainer: context.container) }
        guard let importer else { return }

        let providerID = provider.id
        currentProviderID = providerID
        errorMessage = nil

        // 1. Show whatever is already cached, without blocking the UI.
        let hasCached = (try? await importer.hasChannels(providerID: providerID)) ?? false
        if hasCached {
            await reloadCategories(providerID: providerID)
        } else {
            categories = []
            categoryCounts = [:]
            totalChannelCount = 0
            channels = []
        }

        // 2. Refresh in the background if needed.
        guard forceRefresh || !hasCached || provider.lastRefresh == nil else { return }
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let items: [ChannelImporter.ImportedChannel]
            switch provider.type {
            case .m3u:
                items = try await fetchM3UData(url: provider.url)
            case .xtream:
                items = try await fetchXtreamData(
                    baseURL: provider.xtreamBaseURL ?? "",
                    username: provider.username,
                    password: provider.password
                )
            }

            let count = try await importer.replaceChannels(providerID: providerID, with: items)

            // Bail if the user switched provider while we were fetching.
            guard currentProviderID == providerID else { return }
            provider.channelCount = count
            provider.lastRefresh = Date()
            try? context.save()

            await reloadCategories(providerID: providerID)
            reloadToken += 1
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reloadCategories(providerID: UUID) async {
        guard let importer else { return }
        do {
            let summary = try await importer.categorySummary(providerID: providerID)
            guard currentProviderID == providerID else { return }
            categoryCounts = summary.counts
            categories = summary.counts.keys.sorted()
            totalChannelCount = summary.total
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // Network fetching — runs off main thread
    private nonisolated func fetchM3UData(url: String) async throws -> [ChannelImporter.ImportedChannel] {
        guard let m3uURL = URL(string: url) else { throw M3UParserError.invalidURL }
        let parsed = try await M3UParser.parse(url: m3uURL)
        return parsed.map {
            ChannelImporter.ImportedChannel(
                name: $0.name, streamURL: $0.streamURL, logoURL: $0.logoURL,
                groupTitle: $0.groupTitle, tvgId: $0.tvgId, tvgName: $0.tvgName
            )
        }
    }

    private nonisolated func fetchXtreamData(baseURL: String, username: String, password: String) async throws -> [ChannelImporter.ImportedChannel] {
        guard !baseURL.isEmpty else { throw XtreamError.invalidURL }
        let service = XtreamService(baseURL: baseURL, username: username, password: password)
        _ = try await service.authenticate()
        let cats = try await service.getLiveCategories()
        let streams = try await service.getLiveStreams()

        var categoryMap: [String: String] = [:]
        for cat in cats {
            if let id = cat.categoryId, let name = cat.categoryName { categoryMap[id] = name }
        }
        return streams.compactMap { stream in
            guard let streamId = stream.streamId, let name = stream.name else { return nil }
            return ChannelImporter.ImportedChannel(
                name: name, streamURL: service.streamURL(for: streamId),
                logoURL: stream.streamIcon ?? "",
                groupTitle: categoryMap[stream.categoryId ?? ""] ?? "Uncategorized",
                tvgId: stream.epgChannelId ?? "", tvgName: name
            )
        }
    }

    func fetchChannels(category: String?, searchText: String = "") {
        guard let context = modelContext, let providerID = currentProviderID else { return }

        do {
            var descriptor: FetchDescriptor<Channel>

            if let category, category != "All Channels", category != "Favorites" {
                let group = category
                descriptor = FetchDescriptor<Channel>(
                    predicate: #Predicate {
                        $0.providerID == providerID && $0.groupTitle == group
                    },
                    sortBy: [SortDescriptor(\.channelNumber)]
                )
            } else {
                descriptor = FetchDescriptor<Channel>(
                    predicate: #Predicate { $0.providerID == providerID },
                    sortBy: [SortDescriptor(\.channelNumber)]
                )
                descriptor.fetchLimit = 200
            }

            var result = try context.fetch(descriptor)

            if !searchText.isEmpty {
                result = result.filter {
                    $0.name.localizedCaseInsensitiveContains(searchText)
                }
            }

            channels = result
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func searchChannels(text: String) {
        guard let context = modelContext, let providerID = currentProviderID else { return }
        guard !text.isEmpty else { channels = []; return }

        do {
            let searchText = text
            var descriptor = FetchDescriptor<Channel>(
                predicate: #Predicate {
                    $0.providerID == providerID &&
                    $0.name.localizedStandardContains(searchText)
                },
                sortBy: [SortDescriptor(\.channelNumber)]
            )
            descriptor.fetchLimit = 200
            channels = try context.fetch(descriptor)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshProvider(_ provider: Provider) async {
        await loadChannels(for: provider, forceRefresh: true)
    }

    func currentProgram(for channel: Channel) -> EPGProgram? {
        let now = Date()
        let channelId = channel.tvgId
        return epgPrograms.first {
            $0.channelId == channelId && $0.startTime <= now && $0.stopTime > now
        }
    }

    func nextProgram(for channel: Channel) -> EPGProgram? {
        let now = Date()
        let channelId = channel.tvgId
        return epgPrograms
            .filter { $0.channelId == channelId && $0.startTime > now }
            .sorted { $0.startTime < $1.startTime }
            .first
    }

    func programs(for channel: Channel) -> [EPGProgram] {
        let channelId = channel.tvgId
        return epgPrograms
            .filter { $0.channelId == channelId }
            .sorted { $0.startTime < $1.startTime }
    }
}
