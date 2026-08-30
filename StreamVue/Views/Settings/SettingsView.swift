import SwiftUI
import SwiftData

struct SettingsView: View {
    var providerManager: ProviderManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var providers: [Provider]
    @State private var showingAddProvider = false
    @State private var backupMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Providers section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Providers", systemImage: "antenna.radiowaves.left.and.right")
                                .font(.headline)
                            Spacer()
                            Button(action: { showingAddProvider = true }) {
                                Label("Add", systemImage: "plus")
                                    .font(.callout)
                            }
                            .buttonStyle(.bordered)
                        }

                        if providers.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "tv.slash")
                                    .font(.largeTitle)
                                    .foregroundStyle(.tertiary)
                                Text("No providers configured")
                                    .foregroundStyle(.secondary)
                                Text("Add an M3U URL or Xtream Codes provider to get started")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                        } else {
                            ForEach(providers) { provider in
                                ProviderSettingsRow(
                                    provider: provider,
                                    onRefresh: {
                                        Task { await providerManager.loadChannels(for: provider) }
                                    },
                                    onDelete: { modelContext.delete(provider) }
                                )
                            }
                        }
                    }

                    Divider()

                    // Backup section
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Backup", systemImage: "externaldrive")
                            .font(.headline)
                        Text("Save your providers (and favorites) to a file so you can restore them after a reinstall.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            Button(action: exportProviders) {
                                Label("Export…", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.bordered)
                            .disabled(providers.isEmpty)

                            Button(action: importProviders) {
                                Label("Import…", systemImage: "square.and.arrow.down")
                            }
                            .buttonStyle(.bordered)

                            if let backupMessage {
                                Text(backupMessage)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }

                    Divider()

                    // About section
                    VStack(alignment: .leading, spacing: 8) {
                        Label("About", systemImage: "info.circle")
                            .font(.headline)

                        HStack {
                            Text("StreamVue")
                                .fontWeight(.medium)
                            Text("v1.0")
                                .foregroundStyle(.secondary)
                        }
                        Text("A native macOS IPTV player")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding()
            }
        }
        .frame(width: 500, height: 500)
        .sheet(isPresented: $showingAddProvider) {
            AddProviderView(providerManager: providerManager)
        }
    }

    private func exportProviders() {
        do {
            if let url = try BackupService.export(context: modelContext) {
                backupMessage = "Saved to \(url.lastPathComponent)"
            }
        } catch {
            backupMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    private func importProviders() {
        do {
            guard let result = try BackupService.importFromPanel(context: modelContext) else { return }
            backupMessage = "Imported \(result.added.count) provider\(result.added.count == 1 ? "" : "s")"
                + (result.skipped > 0 ? ", \(result.skipped) already present" : "")
            // Load new providers in the background and re-link favorites once channels exist.
            Task {
                for provider in result.added {
                    await providerManager.loadChannels(for: provider)
                }
                for (providerID, urls) in result.pendingFavorites {
                    BackupService.relinkFavorites(providerID: providerID, urls: urls, context: modelContext)
                }
            }
        } catch {
            backupMessage = "Import failed: \(error.localizedDescription)"
        }
    }
}

private struct ProviderSettingsRow: View {
    let provider: Provider
    let onRefresh: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: provider.type == .m3u ? "list.bullet" : "server.rack")
                .font(.title3)
                .foregroundStyle(.accent)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(provider.name)
                    .fontWeight(.medium)

                Text(provider.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text("\(provider.channelCount) channels")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    if let lastRefresh = provider.lastRefresh {
                        Text("Updated \(lastRefresh.formatted(.relative(presentation: .named)))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { provider.isEnabled },
                set: { provider.isEnabled = $0 }
            ))
            .toggleStyle(.switch)
            .labelsHidden()

            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .background(.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
    }
}
