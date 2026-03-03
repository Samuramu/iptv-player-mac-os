import SwiftUI
import AVFoundation

struct PlayerOverlayView: View {
    let channel: Channel
    let currentProgram: EPGProgram?
    let nextProgram: EPGProgram?
    @Bindable var playerState: PlayerState
    let onPreviousChannel: () -> Void
    let onNextChannel: () -> Void
    let onToggleFullscreen: () -> Void

    @State private var isVisible = true
    @State private var hideTimer: Timer?
    @State private var showSubtitlePicker = false

    var body: some View {
        ZStack {
            // Click area to show/hide
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isVisible.toggle()
                    }
                    if isVisible { resetHideTimer() }
                }

            if isVisible {
                // Top gradient
                VStack {
                    LinearGradient(
                        colors: [.black.opacity(0.7), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 120)
                    Spacer()
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.8)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 160)
                }
                .allowsHitTesting(false)

                VStack(spacing: 0) {
                    // Top info bar
                    topInfoBar
                        .padding()

                    Spacer()

                    // Bottom controls
                    bottomControls
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                }
            }
        }
        .onHover { hovering in
            if hovering {
                isVisible = true
                resetHideTimer()
            }
        }
        .onAppear { resetHideTimer() }
    }

    private var topInfoBar: some View {
        HStack(spacing: 12) {
            // Channel icon
            CachedAsyncImage(urlString: channel.logoURL)
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(channel.name)
                    .font(.title3)
                    .fontWeight(.semibold)

                if let program = currentProgram {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.red)
                            .frame(width: 6, height: 6)
                        Text(program.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Stream quality badges
            if !playerState.streamInfo.isEmpty {
                streamInfoBadges
            }

            // Subtitles button
            if !playerState.subtitleOptions.isEmpty {
                Button(action: { showSubtitlePicker.toggle() }) {
                    Image(systemName: playerState.selectedSubtitle != nil ? "captions.bubble.fill" : "captions.bubble")
                        .font(.title3)
                        .padding(8)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showSubtitlePicker) {
                    subtitlePicker
                }
            }

            Button(action: onToggleFullscreen) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.title3)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var streamInfoBadges: some View {
        HStack(spacing: 6) {
            if !playerState.streamInfo.qualityLabel.isEmpty {
                infoBadge(playerState.streamInfo.qualityLabel)
            }
            if !playerState.streamInfo.videoCodec.isEmpty {
                infoBadge(playerState.streamInfo.videoCodec)
            }
            if !playerState.streamInfo.fps.isEmpty {
                infoBadge(playerState.streamInfo.fps)
            }
            if !playerState.streamInfo.bitrate.isEmpty {
                infoBadge(playerState.streamInfo.bitrate)
            }
            if !playerState.streamInfo.audioCodec.isEmpty {
                infoBadge(playerState.streamInfo.audioCodec)
            }
        }
    }

    private func infoBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.ultraThinMaterial, in: Capsule())
    }

    private var subtitlePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Subtitles")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 8)

            Divider()

            Button(action: {
                playerState.selectSubtitle(nil)
                showSubtitlePicker = false
            }) {
                HStack {
                    Text("Off")
                    Spacer()
                    if playerState.selectedSubtitle == nil {
                        Image(systemName: "checkmark")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)

            ForEach(playerState.subtitleOptions, id: \.self) { option in
                Button(action: {
                    playerState.selectSubtitle(option)
                    showSubtitlePicker = false
                }) {
                    HStack {
                        Text(option.displayName)
                        Spacer()
                        if playerState.selectedSubtitle == option {
                            Image(systemName: "checkmark")
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 200)
        .padding(.vertical, 8)
    }

    private var bottomControls: some View {
        HStack(spacing: 24) {
            Button(action: onPreviousChannel) {
                Image(systemName: "backward.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)

            Button(action: { playerState.togglePlayPause() }) {
                Image(systemName: playerState.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title)
            }
            .buttonStyle(.plain)

            Button(action: onNextChannel) {
                Image(systemName: "forward.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)

            Spacer()

            // Volume
            HStack(spacing: 8) {
                Image(systemName: volumeIcon)
                    .font(.callout)
                Slider(value: Binding(
                    get: { Double(playerState.volume) },
                    set: { playerState.setVolume(Float($0)) }
                ), in: 0...1)
                .frame(width: 100)
            }

            if let next = nextProgram {
                Divider()
                    .frame(height: 20)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Up Next")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(next.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var volumeIcon: String {
        if playerState.volume == 0 { return "speaker.slash.fill" }
        if playerState.volume < 0.33 { return "speaker.wave.1.fill" }
        if playerState.volume < 0.66 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    private func resetHideTimer() {
        hideTimer?.invalidate()
        isVisible = true
        hideTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { _ in
            Task { @MainActor in
                withAnimation(.easeInOut(duration: 0.3)) {
                    isVisible = false
                }
            }
        }
    }
}
