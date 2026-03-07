import SwiftUI

struct PlayerContainerView: View {
    let channel: Channel
    let channels: [Channel]
    @Binding var selectedChannel: Channel?
    @Binding var isFullscreen: Bool
    @Bindable var playerState: PlayerState
    var providerManager: ProviderManager

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            PlayerView(
                player: playerState.player,
                onDoubleClick: toggleFullscreen
            )
            .ignoresSafeArea()

            if playerState.errorMessage != nil {
                // Error state
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.yellow)

                    Text("Unable to Play Stream")
                        .font(.title3)
                        .fontWeight(.semibold)

                    if let error = playerState.errorMessage {
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }

                    Text(channel.name)
                        .font(.caption)
                        .foregroundStyle(.tertiary)

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
                    .padding(.top, 4)
                }
                .padding(32)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            } else if playerState.isBuffering {
                // Buffering / connecting state
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)

                    if let status = playerState.statusMessage {
                        Text(status)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .transition(.opacity)
                    }

                    Text(channel.name)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(24)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
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

            // Debug overlay — shown when debug info is available
            if let debug = playerState.debugInfo {
                VStack(alignment: .leading) {
                    Spacer()
                    Text(debug)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.green)
                        .padding(10)
                        .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 8))
                        .padding(12)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KeyboardShortcutHandler(
            onPlayPause: { playerState.togglePlayPause() },
            onNextChannel: nextChannel,
            onPreviousChannel: previousChannel,
            onToggleFullscreen: toggleFullscreen,
            onExitFullscreen: exitFullscreen,
            onVolumeUp: { playerState.setVolume(min(playerState.volume + 0.1, 1.0)) },
            onVolumeDown: { playerState.setVolume(max(playerState.volume - 0.1, 0.0)) }
        ))
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
        isFullscreen.toggle()

        if let window = NSApplication.shared.keyWindow {
            if isFullscreen && !window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
            } else if !isFullscreen && window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
            }
        }
    }

    private func exitFullscreen() {
        guard isFullscreen else { return }
        isFullscreen = false
        if let window = NSApplication.shared.keyWindow,
           window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
    }
}
