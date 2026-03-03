import Foundation
import SwiftData
import Observation

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
    private var loadTask: Task<Void, Never>?

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    func loadChannels(for provider: Provider) async {
        // Cancel any in-flight load to prevent concurrent ModelContext access
        loadTask?.cancel()
        guard let context = modelContext else { return }
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            let providerID = provider.id

            // Check if we already have channels for this provider
            let existingCount = try context.fetchCount(FetchDescriptor<Channel>(
                predicate: #Predicate { $0.providerID == providerID }
            ))

            if existingCount == 0 || provider.lastRefresh == nil {
                // Delete existing channels for this provider
                let existingChannels = try context.fetch(FetchDescriptor<Channel>(
                    predicate: #Predicate { $0.providerID == providerID }
                ))
                for channel in existingChannels {
                    context.delete(channel)
                }

                // Delete existing categories for this provider
                let existingCategories = try context.fetch(FetchDescriptor<ChannelCategory>(
                    predicate: #Predicate { $0.providerID == providerID }
                ))
                for category in existingCategories {
                    context.delete(category)
                }

                switch provider.type {
                case .m3u:
                    try await loadM3UChannels(provider: provider, context: context)
                case .xtream:
                    try await loadXtreamChannels(provider: provider, context: context)
                }

                try context.save()
                provider.lastRefresh = Date()
            }

            currentProviderID = providerID

            // Only load categories, not all channels
            await loadCategories(providerID: providerID, context: context)

            // Don't load channels until a category is selected
            channels = []

            // Load EPG if URL is available
            if !provider.epgURL.isEmpty, let epgURL = URL(string: provider.epgURL) {
                await loadEPG(url: epgURL, providerID: providerID, context: context)
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func loadCategories(providerID: UUID, context: ModelContext) async {
        do {
            // Get total count without loading all objects
            totalChannelCount = try context.fetchCount(FetchDescriptor<Channel>(
                predicate: #Predicate { $0.providerID == providerID }
            ))

            // Fetch categories from ChannelCategory table (lightweight)
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

            // Count channels per category
            for name in catNames {
                let catName = name
                let count = try context.fetchCount(FetchDescriptor<Channel>(
                    predicate: #Predicate {
                        $0.providerID == providerID && $0.groupTitle == catName
                    }
                ))
                counts[name] = count
            }

            categoryCounts = counts
            categories = catNames
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func fetchChannels(category: String?, searchText: String = "") async {
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
            } else if category == "All Channels" {
                descriptor = FetchDescriptor<Channel>(
                    predicate: #Predicate { $0.providerID == providerID },
                    sortBy: [SortDescriptor(\.channelNumber)]
                )
                descriptor.fetchLimit = 200
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

    func searchChannels(text: String) async {
        guard let context = modelContext, let providerID = currentProviderID else { return }
        guard !text.isEmpty else {
            channels = []
            return
        }

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
        isLoading = true

        // Force re-fetch by clearing lastRefresh
        provider.lastRefresh = nil

        let providerID = provider.id
        let existingChannels = (try? context.fetch(FetchDescriptor<Channel>(
            predicate: #Predicate { $0.providerID == providerID }
        ))) ?? []
        for channel in existingChannels {
            context.delete(channel)
        }

        isLoading = false
        await loadChannels(for: provider)
    }

    private func loadM3UChannels(provider: Provider, context: ModelContext) async throws {
        guard let url = URL(string: provider.url) else {
            throw M3UParserError.invalidURL
        }

        let parsed = try await M3UParser.parse(url: url)
        var count = 0
        var seenCategories = Set<String>()
        for (index, item) in parsed.enumerated() {
            let channel = Channel(
                name: item.name,
                streamURL: item.streamURL,
                logoURL: item.logoURL,
                groupTitle: item.groupTitle,
                tvgId: item.tvgId,
                tvgName: item.tvgName,
                providerID: provider.id,
                channelNumber: index + 1
            )
            context.insert(channel)

            if seenCategories.insert(item.groupTitle).inserted {
                let cat = ChannelCategory(name: item.groupTitle, providerID: provider.id)
                context.insert(cat)
            }
            count += 1
        }
        provider.channelCount = count
    }

    private func loadXtreamChannels(provider: Provider, context: ModelContext) async throws {
        guard let baseURL = provider.xtreamBaseURL else {
            throw XtreamError.invalidURL
        }

        let service = XtreamService(
            baseURL: baseURL,
            username: provider.username,
            password: provider.password
        )

        _ = try await service.authenticate()

        let xtreamCategories = try await service.getLiveCategories()
        var categoryMap: [String: String] = [:]
        for cat in xtreamCategories {
            if let id = cat.categoryId, let name = cat.categoryName {
                categoryMap[id] = name
                let category = ChannelCategory(name: name, providerID: provider.id)
                context.insert(category)
            }
        }

        let streams = try await service.getLiveStreams()
        var count = 0
        for (index, stream) in streams.enumerated() {
            guard let streamId = stream.streamId, let name = stream.name else { continue }

            let groupTitle = categoryMap[stream.categoryId ?? ""] ?? "Uncategorized"
            let streamURLString = service.streamURL(for: streamId)

            let channel = Channel(
                name: name,
                streamURL: streamURLString,
                logoURL: stream.streamIcon ?? "",
                groupTitle: groupTitle,
                tvgId: stream.epgChannelId ?? "",
                tvgName: name,
                providerID: provider.id,
                channelNumber: index + 1
            )
            context.insert(channel)
            count += 1
        }
        provider.channelCount = count
    }

    private func loadEPG(url: URL, providerID: UUID, context: ModelContext) async {
        do {
            let existing = try context.fetch(FetchDescriptor<EPGProgram>(
                predicate: #Predicate { $0.providerID == providerID }
            ))
            for program in existing {
                context.delete(program)
            }

            let parsed = try await EPGParser.parse(url: url)
            for item in parsed {
                let program = EPGProgram(
                    channelId: item.channelId,
                    title: item.title,
                    desc: item.description,
                    startTime: item.startTime,
                    stopTime: item.stopTime,
                    providerID: providerID
                )
                context.insert(program)
            }

            epgPrograms = try context.fetch(FetchDescriptor<EPGProgram>(
                predicate: #Predicate { $0.providerID == providerID }
            ))

            try context.save()
        } catch {
            print("EPG load error: \(error.localizedDescription)")
        }
    }

    func currentProgram(for channel: Channel) -> EPGProgram? {
        let now = Date()
        let channelId = channel.tvgId
        return epgPrograms.first { program in
            program.channelId == channelId && program.startTime <= now && program.stopTime > now
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
