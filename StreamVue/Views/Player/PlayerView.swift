import SwiftUI
import VLCKitSPM
import IOKit.pwr_mgt

struct PlayerView: NSViewRepresentable {
    let playerState: PlayerState
    let onDoubleClick: () -> Void

    func makeNSView(context: Context) -> PlayerHostView {
        let host = PlayerHostView()
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.black.cgColor
        host.playerState = playerState
        playerState.videoView.onDoubleClick = onDoubleClick
        playerState.hostView = host
        host.attachVideoView()
        return host
    }

    func updateNSView(_ nsView: PlayerHostView, context: Context) {
        playerState.videoView.onDoubleClick = onDoubleClick
    }
}

class PlayerHostView: NSView {
    weak var playerState: PlayerState?

    func attachVideoView() {
        guard let playerState, playerState.videoView.superview !== self else { return }
        let vv = playerState.videoView
        vv.removeFromSuperview()
        vv.translatesAutoresizingMaskIntoConstraints = false
        addSubview(vv)
        NSLayoutConstraint.activate([
            vv.leadingAnchor.constraint(equalTo: leadingAnchor),
            vv.trailingAnchor.constraint(equalTo: trailingAnchor),
            vv.topAnchor.constraint(equalTo: topAnchor),
            vv.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
}

class DoubleClickVideoView: NSView {
    var onDoubleClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?()
        } else {
            super.mouseDown(with: event)
        }
    }

    override var acceptsFirstResponder: Bool { true }
}

// MARK: - Fullscreen Window

class FullscreenPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

struct StreamInfo {
    var videoCodec: String = ""
    var audioCodec: String = ""
    var resolution: String = ""
    var fps: String = ""
    var bitrate: String = ""

    var isEmpty: Bool {
        videoCodec.isEmpty && resolution.isEmpty
    }

    var qualityLabel: String {
        if resolution.contains("3840") || resolution.contains("2160") { return "4K" }
        if resolution.contains("1920") || resolution.contains("1080") { return "HD 1080p" }
        if resolution.contains("1280") || resolution.contains("720") { return "HD 720p" }
        if resolution.contains("854") || resolution.contains("480") { return "SD 480p" }
        if !resolution.isEmpty { return resolution }
        return ""
    }
}

@Observable
final class PlayerState: NSObject, VLCMediaPlayerDelegate {
    var player = VLCMediaPlayer()
    let videoView: DoubleClickVideoView = {
        let v = DoubleClickVideoView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.black.cgColor
        return v
    }()
    weak var hostView: PlayerHostView?
    var isPlaying = false
    var volume: Float = 1.0
    var isBuffering = false
    var currentTime: Double = 0
    var duration: Double = 0
    var errorMessage: String?
    var statusMessage: String?
    var debugInfo: String?
    var streamInfo = StreamInfo()
    var subtitleOptions: [(index: Int, name: String)] = []
    var selectedSubtitleIndex: Int = -1

    private var currentURLString: String?
    private var activeURLString: String?
    private var triedAlternate = false
    private var stallTimer: Timer?
    private var bufferRetryTimer: Timer?
    private var bufferRetryCount = 0
    private var sleepAssertionID: IOPMAssertionID = 0
    private var isSleepPrevented = false
    private var streamInfoExtracted = false
    private var fullscreenPanel: FullscreenPanel?

    override init() {
        super.init()
        player.delegate = self
        player.drawable = videoView
        player.audio?.volume = 100
    }

    // MARK: - Fullscreen

    func enterFullscreen() {
        guard fullscreenPanel == nil,
              let screen = NSScreen.main ?? videoView.window?.screen else { return }

        let panel = FullscreenPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.isOpaque = true
        panel.backgroundColor = .black
        panel.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces]
        panel.hasShadow = false

        // Reparent the video view into the fullscreen panel
        videoView.removeFromSuperview()
        videoView.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView?.addSubview(videoView)
        if let contentView = panel.contentView {
            NSLayoutConstraint.activate([
                videoView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                videoView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                videoView.topAnchor.constraint(equalTo: contentView.topAnchor),
                videoView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            ])
        }

        panel.orderFrontRegardless()
        panel.makeKey()
        fullscreenPanel = panel

        // Hide cursor after delay
        NSCursor.setHiddenUntilMouseMoves(true)
    }

    func exitFullscreen() {
        guard let panel = fullscreenPanel else { return }

        // Reparent the video view back to the SwiftUI host
        videoView.removeFromSuperview()
        hostView?.attachVideoView()

        panel.orderOut(nil)
        fullscreenPanel = nil

        // Restore focus to main window
        NSApplication.shared.mainWindow?.makeKey()
    }

    var isInFullscreen: Bool {
        fullscreenPanel != nil
    }

    // MARK: - Playback

    func play(url: URL) {
        if player.isPlaying {
            player.stop()
        }

        let media = VLCMedia(url: url)
        media.addOption(":network-caching=3000")
        media.addOption(":live-caching=3000")
        media.addOption(":http-reconnect")
        media.addOption(":http-continuous")
        media.addOption(":http-user-agent=VLC/3.0.20 LibVLC/3.0.20")

        player.media = media
        player.audio?.volume = Int32(volume * 100)
        player.play()

        isPlaying = true
        isBuffering = true
        errorMessage = nil
        statusMessage = "Connecting..."
        debugInfo = nil
        streamInfo = StreamInfo()
        subtitleOptions = []
        selectedSubtitleIndex = -1
        streamInfoExtracted = false
        bufferRetryCount = 0
        cancelBufferRetryTimer()
        startStallTimer()
    }

    func play(urlString: String) {
        currentURLString = urlString
        activeURLString = urlString
        triedAlternate = false

        guard let url = URL(string: urlString) else {
            errorMessage = "Invalid stream URL"
            statusMessage = nil
            return
        }
        play(url: url)
    }

    func retryWithAlternateFormat() {
        guard let original = currentURLString else { return }
        errorMessage = nil

        let alternate: String
        if !triedAlternate {
            if original.hasSuffix(".ts") {
                alternate = String(original.dropLast(3)) + ".m3u8"
            } else if original.hasSuffix(".m3u8") {
                alternate = String(original.dropLast(5)) + ".ts"
            } else {
                alternate = original
            }
            triedAlternate = true
        } else {
            alternate = original
            triedAlternate = false
        }

        guard let url = URL(string: alternate) else { return }
        activeURLString = alternate
        play(url: url)
    }

    func togglePlayPause() {
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }

    func stop() {
        player.stop()
        isPlaying = false
        statusMessage = nil
        isBuffering = false
        cancelStallTimer()
        cancelBufferRetryTimer()
        allowSleep()
    }

    func setVolume(_ vol: Float) {
        volume = vol
        player.audio?.volume = Int32(vol * 100)
    }

    func selectSubtitle(_ index: Int) {
        player.currentVideoSubTitleIndex = Int32(index)
        selectedSubtitleIndex = index
    }

    // MARK: - VLCMediaPlayerDelegate

    @objc func mediaPlayerStateChanged(_ aNotification: Notification) {
        Task { @MainActor in
            guard let vlcPlayer = aNotification.object as? VLCMediaPlayer else { return }
            let state = vlcPlayer.state

            switch state {
            case .playing:
                isPlaying = true
                isBuffering = false
                statusMessage = nil
                cancelStallTimer()
                cancelBufferRetryTimer()
                bufferRetryCount = 0
                preventSleep()
                if !streamInfoExtracted {
                    extractStreamInfo()
                    extractSubtitles()
                    streamInfoExtracted = true
                }

            case .buffering:
                isBuffering = true
                statusMessage = "Buffering..."
                startBufferRetryTimer()

            case .paused:
                isPlaying = false
                allowSleep()

            case .stopped:
                isPlaying = false
                isBuffering = false
                allowSleep()

            case .ended:
                isPlaying = false
                isBuffering = false
                statusMessage = nil
                allowSleep()

            case .error:
                isPlaying = false
                isBuffering = false
                cancelStallTimer()
                statusMessage = nil
                errorMessage = "Playback failed"
                allowSleep()

            case .opening:
                isBuffering = true
                statusMessage = "Opening stream..."

            default:
                break
            }
        }
    }

    @objc func mediaPlayerTimeChanged(_ aNotification: Notification) {
        Task { @MainActor in
            guard let vlcPlayer = aNotification.object as? VLCMediaPlayer else { return }
            let time = vlcPlayer.time
            currentTime = Double(time.intValue) / 1000.0
            if let media = vlcPlayer.media {
                let len = media.length
                if len.intValue > 0 {
                    duration = Double(len.intValue) / 1000.0
                }
            }

            if isBuffering {
                isBuffering = false
                statusMessage = nil
                cancelStallTimer()
            }

            if !streamInfoExtracted && vlcPlayer.hasVideoOut {
                extractStreamInfo()
                extractSubtitles()
                streamInfoExtracted = true
            }
        }
    }

    // MARK: - Private

    private func preventSleep() {
        guard !isSleepPrevented else { return }
        let reason = "StreamVue video playback" as CFString
        let success = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &sleepAssertionID
        )
        isSleepPrevented = (success == kIOReturnSuccess)
    }

    private func allowSleep() {
        guard isSleepPrevented else { return }
        IOPMAssertionRelease(sleepAssertionID)
        isSleepPrevented = false
    }

    private func startStallTimer() {
        cancelStallTimer()
        stallTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isBuffering, self.errorMessage == nil else { return }
                self.statusMessage = "Stream is taking too long to respond"
            }
        }
    }

    private func cancelStallTimer() {
        stallTimer?.invalidate()
        stallTimer = nil
    }

    private func startBufferRetryTimer() {
        cancelBufferRetryTimer()
        bufferRetryTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isBuffering, self.errorMessage == nil else { return }
                self.bufferRetryCount += 1
                if self.bufferRetryCount <= 3 {
                    self.statusMessage = "Reconnecting... (attempt \(self.bufferRetryCount)/3)"
                    // Restart playback with the same URL
                    if let urlString = self.activeURLString, let url = URL(string: urlString) {
                        self.player.stop()
                        let media = VLCMedia(url: url)
                        media.addOption(":network-caching=3000")
                        media.addOption(":live-caching=3000")
                        media.addOption(":http-reconnect")
                        media.addOption(":http-continuous")
                        media.addOption(":http-user-agent=VLC/3.0.20 LibVLC/3.0.20")
                        self.player.media = media
                        self.player.play()
                    }
                } else {
                    self.statusMessage = "Stream stalled — tap Retry"
                    self.cancelBufferRetryTimer()
                }
            }
        }
    }

    private func cancelBufferRetryTimer() {
        bufferRetryTimer?.invalidate()
        bufferRetryTimer = nil
    }

    private func extractStreamInfo() {
        var info = StreamInfo()

        let videoSize = player.videoSize
        if videoSize.width > 0 && videoSize.height > 0 {
            info.resolution = "\(Int(videoSize.width))x\(Int(videoSize.height))"
        }

        if let media = player.media {
            let tracks = media.tracksInformation
            if let tracks = tracks as? [[String: Any]] {
                for track in tracks {
                    let type = track[VLCMediaTracksInformationType] as? String ?? ""
                    let codec = track[VLCMediaTracksInformationCodec] as? Int ?? 0
                    let codecStr = fourCCToString(UInt32(bitPattern: Int32(codec)))

                    if type == VLCMediaTracksInformationTypeVideo {
                        info.videoCodec = codecStr
                        if let w = track[VLCMediaTracksInformationVideoWidth] as? Int,
                           let h = track[VLCMediaTracksInformationVideoHeight] as? Int, w > 0, h > 0 {
                            info.resolution = "\(w)x\(h)"
                        }
                        if let rate = track[VLCMediaTracksInformationFrameRate] as? Int,
                           let rateDen = track[VLCMediaTracksInformationFrameRateDenominator] as? Int, rateDen > 0 {
                            let fps = Double(rate) / Double(rateDen)
                            info.fps = String(format: "%.0f fps", fps)
                        }
                    } else if type == VLCMediaTracksInformationTypeAudio {
                        info.audioCodec = codecStr
                    }
                }
            }
        }

        if let media = player.media {
            let stats = media.statistics
            let bitrate = stats.demuxBitrate
            if bitrate > 0 {
                let bps = bitrate * 8
                if bps > 1_000_000 {
                    info.bitrate = String(format: "%.1f Mbps", bps / 1_000_000)
                } else if bps > 1_000 {
                    info.bitrate = String(format: "%.0f Kbps", bps / 1_000)
                }
            }
        }

        streamInfo = info
    }

    private func extractSubtitles() {
        guard let subtitleNames = player.videoSubTitlesNames as? [String],
              let subtitleIndexes = player.videoSubTitlesIndexes as? [NSNumber] else { return }

        var options: [(index: Int, name: String)] = []
        for (name, idx) in zip(subtitleNames, subtitleIndexes) {
            let index = idx.intValue
            if index == -1 { continue }
            options.append((index: index, name: name))
        }
        subtitleOptions = options
    }

    private func fourCCToString(_ code: UInt32) -> String {
        let knownCodecs: [UInt32: String] = [
            0x68323634: "H.264",
            0x48323634: "H.264",
            0x61766331: "H.264",
            0x68657663: "HEVC",
            0x48455643: "HEVC",
            0x68766331: "HEVC",
            0x76703039: "VP9",
            0x56503039: "VP9",
            0x61763031: "AV1",
            0x6D703461: "AAC",
            0x61632D33: "AC-3",
            0x65632D33: "E-AC-3",
            0x6F707573: "Opus",
            0x6D703361: "MP3",
        ]
        if let name = knownCodecs[code] { return name }

        let chars: [Character] = [
            Character(UnicodeScalar((code >> 24) & 0xFF)!),
            Character(UnicodeScalar((code >> 16) & 0xFF)!),
            Character(UnicodeScalar((code >> 8) & 0xFF)!),
            Character(UnicodeScalar(code & 0xFF)!),
        ]
        let str = String(chars).trimmingCharacters(in: .whitespaces)
        return str.isEmpty ? "Unknown" : str
    }

    deinit {
        stallTimer?.invalidate()
        bufferRetryTimer?.invalidate()
        player.stop()
        if isSleepPrevented {
            IOPMAssertionRelease(sleepAssertionID)
        }
    }
}
