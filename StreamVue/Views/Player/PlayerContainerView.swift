import SwiftUI

struct PlayerContainerView: View {
    let channel: Channel
    let channels: [Channel]
    @Binding var selectedChannel: Channel?
    var providerManager: ProviderManager

    @State private var playerState = PlayerState()

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            PlayerView(
                player: playerState.player,
                onDoubleClick: toggleFullscreen
            )
            .ignoresSafeArea()

            if playerState.isBuffering && playerState.errorMessage == nil {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
            }

            if let error = playerState.errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.yellow)
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    HStack(spacing: 12) {
                        Button("Retry") {
                            playerState.play(urlString: channel.streamURL)
                        }
                        .buttonStyle(.bordered)
                        Button("Try Alternate Format") {
                            playerState.retryWithAlternateFormat()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }

            PlayerOverlayView(
                channel: channel,
                currentProgram: providerManager.currentProgram(for: channel),
                nextProgram: providerManager.nextProgram(for: channel),
                playerState: playerState,
                onPreviousChannel: previousChannel,
                onNextChannel: nextChannel,
                onToggleFullscreen: toggleFullscreen
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KeyboardShortcutHandler(
            onPlayPause: { playerState.togglePlayPause() },
            onNextChannel: nextChannel,
            onPreviousChannel: previousChannel,
            onToggleFullscreen: toggleFullscreen,
            onVolumeUp: { playerState.setVolume(min(playerState.volume + 0.1, 1.0)) },
            onVolumeDown: { playerState.setVolume(max(playerState.volume - 0.1, 0.0)) }
        ))
        .onAppear {
            playerState.play(urlString: channel.streamURL)
        }
        .onChange(of: channel.id) { _, _ in
            playerState.play(urlString: channel.streamURL)
        }
        .onDisappear {
            playerState.stop()
        }
    }

    private func nextChannel() {
        guard let currentIndex = channels.firstIndex(where: { $0.id == channel.id }) else { return }
        let nextIndex = (currentIndex + 1) % channels.count
        selectedChannel = channels[nextIndex]
    }

    private func previousChannel() {
        guard let currentIndex = channels.firstIndex(where: { $0.id == channel.id }) else { return }
        let prevIndex = (currentIndex - 1 + channels.count) % channels.count
        selectedChannel = channels[prevIndex]
    }

    private func toggleFullscreen() {
        if let window = NSApplication.shared.keyWindow {
            window.toggleFullScreen(nil)
        }
    }
}
