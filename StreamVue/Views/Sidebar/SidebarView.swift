import SwiftUI
import SwiftData

struct SidebarView: View {
    @Binding var selectedProvider: Provider?
    @Binding var selectedCategory: String?
    @Binding var showingAddProvider: Bool
    var providerManager: ProviderManager

    @Environment(\.modelContext) private var modelContext
    @Query private var providers: [Provider]

    var body: some View {
        List(selection: $selectedCategory) {
            Section("Providers") {
                ForEach(providers) { provider in
                    ProviderRow(provider: provider, isSelected: selectedProvider?.id == provider.id)
                        .onTapGesture {
                            selectedProvider = provider
                        }
                        .contextMenu {
                            Button("Refresh") {
                                Task {
                                    await providerManager.refreshProvider(provider)
                                }
                            }
                            Button("Delete", role: .destructive) {
                                modelContext.delete(provider)
                                if selectedProvider?.id == provider.id {
                                    selectedProvider = providers.first { $0.id != provider.id }
                                }
                            }
                        }
                }

                Button(action: { showingAddProvider = true }) {
                    Label("Add Provider", systemImage: "plus.circle")
                        .foregroundStyle(.accent)
                }
                .buttonStyle(.plain)
            }

            if !providerManager.categories.isEmpty {
                Section("Categories (\(providerManager.categories.count))") {
                    CategoryRow(
                        name: "All Channels",
                        icon: "tv",
                        count: providerManager.totalChannelCount
                    )
                    .tag("All Channels" as String?)

                    CategoryRow(name: "Favorites", icon: "star.fill", count: 0)
                        .tag("Favorites" as String?)

                    ForEach(providerManager.categories, id: \.self) { category in
                        CategoryRow(
                            name: category,
                            icon: "folder",
                            count: providerManager.categoryCounts[category] ?? 0
                        )
                        .tag(category as String?)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("StreamVue")
    }
}
