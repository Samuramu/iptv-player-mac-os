import SwiftUI

struct ChannelCard: View {
    let channel: Channel
    let isSelected: Bool
    let isFavorite: Bool
    let currentProgram: EPGProgram?
    let onToggleFavorite: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Logo area
            ZStack(alignment: .topTrailing) {
                CachedAsyncImage(urlString: channel.logoURL)
                    .frame(height: 100)
                    .frame(maxWidth: .infinity)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Button(action: onToggleFavorite) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.caption)
                        .foregroundStyle(isFavorite ? .yellow : .white.opacity(0.6))
                        .padding(6)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(6)
                .opacity(isHovered || isFavorite ? 1 : 0)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(channel.name)
                        .font(.callout)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    Spacer()

                    if channel.channelNumber > 0 {
                        Text("\(channel.channelNumber)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }
                }

                if let program = currentProgram {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.red)
                            .frame(width: 6, height: 6)
                        Text(program.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(.white.opacity(0.1))
                                .frame(height: 3)
                            Capsule()
                                .fill(.accent)
                                .frame(width: geo.size.width * program.progress, height: 3)
                        }
                    }
                    .frame(height: 3)
                }
            }
            .padding(10)
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.white.opacity(0.05))
                .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .shadow(color: isHovered ? .black.opacity(0.3) : .clear, radius: 8)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
    }
}
