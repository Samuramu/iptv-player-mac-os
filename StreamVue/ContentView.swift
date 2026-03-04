import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var providerManager = ProviderManager()
    @State private var playerState = PlayerState()
    @State private var selectedProvider: Provider?
    @State private var selectedCategory: String?
    @State private var selectedChannel: Channel?
    @State private var searchText = ""
    @State private var showingSettings = false
    @State private var showingAddProvider = false
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var hasInitialized = false
    @State private var isFullscreen = false

    @Query private var providers: [Provider]
    @Query private var favorites: [Favorite]

    var body: some View {
        Group {
            if isFullscreen, let channel = selectedChannel {
                // Fullscreen: video only, no sidebars — same playerState, no reload
                PlayerContainerView(
                    channel: channel,
                    channels: providerManager.channels,
                    selectedChannel: $selectedChannel,
                    isFullscreen: $isFullscreen,
                    playerState: playerState,
                    providerManager: providerManager
                )
            } else {
                // Normal: 3-column layout
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    SidebarView(
                        selectedProvider: $selectedProvider,
                        selectedCategory: $selectedCategory,
                        showingAddProvider: $showingAddProvider,
                        providerManager: providerManager
                    )
                    .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
                } content: {
                    ChannelGridView(
                        channels: providerManager.channels,
                        selectedChannel: $selectedChannel,
                        providerManager: providerManager,
                        favorites: favorites,
                        modelContext: modelContext
                    )
                    .navigationSplitViewColumnWidth(min: 300, ideal: 400, max: 600)
                    .searchable(text: $searchText, prompt: "Search channels")
                } detail: {
                    if let channel = selectedChannel {
                        PlayerContainerView(
                            channel: channel,
                            channels: providerManager.channels,
                            selectedChannel: $selectedChannel,
                            isFullscreen: $isFullscreen,
                            playerState: playerState,
                            providerManager: providerManager
                        )
                    } else {
                        VStack(spacing: 16) {
                            Image(systemName: "tv")
                                .font(.system(size: 64))
                                .foregroundStyle(.tertiary)
                            Text("Select a category, then a channel")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        Button(action: { showingSettings = true }) {
                            Image(systemName: "gear")
                        }
                    }
                }
                .sheet(isPresented: $showingAddProvider) {
                    AddProviderView(providerManager: providerManager)
                }
                .sheet(isPresented: $showingSettings) {
                    SettingsView(providerManager: providerManager)
                }
            }
        }
        .task {
            providerManager.setModelContext(modelContext)
            if let first = providers.first {
                selectedProvider = first
                hasInitialized = true
                await providerManager.loadChannels(for: first)
            } else {
                hasInitialized = true
            }
        }
        .onChange(of: selectedProvider) { _, newProvider in
            guard hasInitialized, let provider = newProvider else { return }
            selectedCategory = nil
            Task {
                await providerManager.loadChannels(for: provider)
            }
        }
        .onChange(of: selectedCategory) { _, newCategory in
            if let newCategory {
                if newCategory == "Favorites" {
                    let favoriteIDs = Set(favorites.map(\.channelID))
                    providerManager.fetchChannels(category: nil)
                    providerManager.channels = providerManager.channels.filter {
                        favoriteIDs.contains($0.id)
                    }
                } else {
                    providerManager.fetchChannels(category: newCategory)
                }
            } else {
                providerManager.channels = []
            }
        }
        .onChange(of: searchText) { _, newText in
            if newText.isEmpty {
                if let selectedCategory {
                    if selectedCategory == "Favorites" {
                        let favoriteIDs = Set(favorites.map(\.channelID))
                        providerManager.fetchChannels(category: nil)
                        providerManager.channels = providerManager.channels.filter {
                            favoriteIDs.contains($0.id)
                        }
                    } else {
                        providerManager.fetchChannels(category: selectedCategory)
                    }
                } else {
                    providerManager.channels = []
                }
            } else {
                providerManager.searchChannels(text: newText)
            }
        }
        .onChange(of: selectedChannel) { oldChannel, newChannel in
            if let channel = newChannel {
                // Only start playback if it's a different channel
                if oldChannel?.id != channel.id {
                    playerState.play(urlString: channel.streamURL)
                }
            } else {
                playerState.stop()
            }
        }
        .onChange(of: isFullscreen) { _, fullscreen in
            if !fullscreen {
                if let window = NSApplication.shared.keyWindow,
                   window.styleMask.contains(.fullScreen) {
                    window.toggleFullScreen(nil)
                }
            }
        }
        .onChange(of: favorites.count) { _, _ in
            if selectedCategory == "Favorites" {
                let favoriteIDs = Set(favorites.map(\.channelID))
                providerManager.fetchChannels(category: nil)
                providerManager.channels = providerManager.channels.filter {
                    favoriteIDs.contains($0.id)
                }
            }
        }
    }
}
