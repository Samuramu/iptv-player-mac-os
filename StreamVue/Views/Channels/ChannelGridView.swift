import SwiftUI
import SwiftData

struct ChannelGridView: View {
    let channels: [Channel]
    @Binding var selectedChannel: Channel?
    var providerManager: ProviderManager
    let favorites: [Favorite]
    let modelContext: ModelContext

    private var favoriteIDs: Set<UUID> {
        Set(favorites.map(\.channelID))
    }

    var body: some View {
        VStack(spacing: 0) {
            if channels.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    if providerManager.isLoading {
                        ProgressView("Loading channels...")
                    } else {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.system(size: 48))
                            .foregroundStyle(.tertiary)
                        Text("Select a category")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Text("Choose a category from the sidebar to browse channels")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
            } else {
                HStack {
                    Text("\(channels.count) channels")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 6)

                List(selection: Binding(
                    get: { selectedChannel?.id },
                    set: { newID in
                        selectedChannel = channels.first { $0.id == newID }
                    }
                )) {
                    ForEach(channels) { channel in
                        ChannelListRow(
                            channel: channel,
                            isFavorite: favoriteIDs.contains(channel.id),
                            onToggleFavorite: { toggleFavorite(channel) }
                        )
                        .tag(channel.id)
                    }
                }
                .listStyle(.inset)
            }
        }
        .overlay(alignment: .bottom) {
            if providerManager.isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Loading...")
                        .font(.caption)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 12)
            }
        }
    }

    private func toggleFavorite(_ channel: Channel) {
        if let existing = favorites.first(where: { $0.channelID == channel.id }) {
            modelContext.delete(existing)
        } else {
            let favorite = Favorite(channelID: channel.id)
            modelContext.insert(favorite)
        }
    }
}

struct ChannelListRow: View {
    let channel: Channel
    let isFavorite: Bool
    let onToggleFavorite: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("\(channel.channelNumber)")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .frame(width: 36, alignment: .trailing)

            CachedAsyncImage(urlString: channel.logoURL)
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            Text(channel.name)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            Button(action: onToggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.caption)
                    .foregroundStyle(isFavorite ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 3)
    }
}
