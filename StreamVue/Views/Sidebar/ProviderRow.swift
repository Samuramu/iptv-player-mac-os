import SwiftUI

struct ProviderRow: View {
    let provider: Provider
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: provider.type == .m3u ? "list.bullet" : "server.rack")
                .font(.caption)
                .foregroundStyle(isSelected ? .accent : .secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(provider.name)
                    .font(.callout)
                    .fontWeight(isSelected ? .semibold : .regular)

                Text("\(provider.channelCount) channels")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !provider.isEnabled {
                Image(systemName: "pause.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}
