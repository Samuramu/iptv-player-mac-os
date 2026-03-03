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

    func loadChannels(for provider: Provider) async {
        guard let context = modelContext, !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            let providerID = provider.id

            let existingCount = try context.fetchCount(FetchDescriptor<Channel>(
                predicate: #Predicate { $0.providerID == providerID }
            ))

            if existingCount == 0 || provider.lastRefresh == nil {
                // Delete existing data
                let existingChannels = try context.fetch(FetchDescriptor<Channel>(
                    predicate: #Predicate { $0.providerID == providerID }
                ))
                for channel in existingChannels { context.delete(channel) }

                let existingCategories = try context.fetch(FetchDescriptor<ChannelCategory>(
                    predicate: #Predicate { $0.providerID == providerID }
                ))
                for category in existingCategories { context.delete(category) }

                // Fetch data from network (off main thread)
                switch provider.type {
                case .m3u:
                    let parsed = try await fetchM3UData(url: provider.url)
                    insertM3UChannels(parsed, provider: provider, context: context)
                case .xtream:
                    let data = try await fetchXtreamData(provider: provider)
                    insertXtreamChannels(data, provider: provider, context: context)
                }

                try context.save()
                provider.lastRefresh = Date()
            }

            currentProviderID = providerID
            loadCategoriesSync(providerID: providerID, context: context)
            channels = []

        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // Network fetching — runs off main thread
    private nonisolated func fetchM3UData(url: String) async throws -> [M3UParser.ParsedChannel] {
        guard let m3uURL = URL(string: url) else { throw M3UParserError.invalidURL }
        return try await M3UParser.parse(url: m3uURL)
    }

    private nonisolated func fetchXtreamData(provider: Provider) async throws -> (categories: [XtreamService.XtreamCategory], streams: [XtreamService.XtreamStream]) {
        guard let baseURL = provider.xtreamBaseURL else { throw XtreamError.invalidURL }
        let service = XtreamService(baseURL: baseURL, username: provider.username, password: provider.password)
        _ = try await service.authenticate()
        let cats = try await service.getLiveCategories()
        let streams = try await service.getLiveStreams()
        return (cats, streams)
    }

    // Insert into context — main thread only
    private func insertM3UChannels(_ parsed: [M3UParser.ParsedChannel], provider: Provider, context: ModelContext) {
        var seenCategories = Set<String>()
        for (index, item) in parsed.enumerated() {
            let channel = Channel(
                name: item.name, streamURL: item.streamURL, logoURL: item.logoURL,
                groupTitle: item.groupTitle, tvgId: item.tvgId, tvgName: item.tvgName,
                providerID: provider.id, channelNumber: index + 1
            )
            context.insert(channel)
            if seenCategories.insert(item.groupTitle).inserted {
                context.insert(ChannelCategory(name: item.groupTitle, providerID: provider.id))
            }
        }
        provider.channelCount = parsed.count
    }

    private func insertXtreamChannels(_ data: (categories: [XtreamService.XtreamCategory], streams: [XtreamService.XtreamStream]), provider: Provider, context: ModelContext) {
        guard let baseURL = provider.xtreamBaseURL else { return }
        let service = XtreamService(baseURL: baseURL, username: provider.username, password: provider.password)

        var categoryMap: [String: String] = [:]
        for cat in data.categories {
            if let id = cat.categoryId, let name = cat.categoryName {
                categoryMap[id] = name
                context.insert(ChannelCategory(name: name, providerID: provider.id))
            }
        }

        var count = 0
        for (index, stream) in data.streams.enumerated() {
            guard let streamId = stream.streamId, let name = stream.name else { continue }
            let groupTitle = categoryMap[stream.categoryId ?? ""] ?? "Uncategorized"
            let channel = Channel(
                name: name, streamURL: service.streamURL(for: streamId),
                logoURL: stream.streamIcon ?? "", groupTitle: groupTitle,
                tvgId: stream.epgChannelId ?? "", tvgName: name,
                providerID: provider.id, channelNumber: index + 1
            )
            context.insert(channel)
            count += 1
        }
        provider.channelCount = count
    }

    // Synchronous category loading (main thread)
    private func loadCategoriesSync(providerID: UUID, context: ModelContext) {
        do {
            totalChannelCount = try context.fetchCount(FetchDescriptor<Channel>(
                predicate: #Predicate { $0.providerID == providerID }
            ))

            let cats = try context.fetch(FetchDescriptor<ChannelCategory>(
                predicate: #Predicate { $0.providerID == providerID }
            ))

            var seen = Set<String>()
            var catNames: [String] = []
            var counts: [String: Int] = [:]

            for cat in cats {
                if seen.insert(cat.name).inserted {
                    catNames.append(cat.name)
                }
            }
            catNames.sort()

            for name in catNames {
                let catName = name
                counts[name] = try context.fetchCount(FetchDescriptor<Channel>(
                    predicate: #Predicate {
                        $0.providerID == providerID && $0.groupTitle == catName
                    }
                ))
            }

            categoryCounts = counts
            categories = catNames
        } catch {
            errorMessage = error.localizedDescription
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
        guard let context = modelContext else { return }
        provider.lastRefresh = nil
        let providerID = provider.id
        let existing = (try? context.fetch(FetchDescriptor<Channel>(
            predicate: #Predicate { $0.providerID == providerID }
        ))) ?? []
        for ch in existing { context.delete(ch) }
        await loadChannels(for: provider)
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
