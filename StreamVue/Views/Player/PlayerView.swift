import SwiftUI
import VLCKitSPM
import IOKit.pwr_mgt

struct PlayerView: NSViewRepresentable {
    let player: VLCMediaPlayer
    let onDoubleClick: () -> Void

    func makeNSView(context: Context) -> DoubleClickVideoView {
        let view = DoubleClickVideoView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        view.onDoubleClick = onDoubleClick
        player.drawable = view
        return view
    }

    func updateNSView(_ nsView: DoubleClickVideoView, context: Context) {
        nsView.onDoubleClick = onDoubleClick
        if player.drawable as? NSView !== nsView {
            player.drawable = nsView
        }
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
    private var sleepAssertionID: IOPMAssertionID = 0
    private var isSleepPrevented = false
    private var hasReceivedVideoFrame = false
    private var streamInfoExtracted = false

    override init() {
        super.init()
        player.delegate = self
        player.audio?.volume = 100
    }

    func play(url: URL) {
        // Stop current playback first
        if player.isPlaying {
            player.stop()
        }

        let media = VLCMedia(url: url)
        media.addOption(":network-caching=1500")
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
        hasReceivedVideoFrame = false
        streamInfoExtracted = false
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
        allowSleep()
    }

    func setVolume(_ vol: Float) {
        volume = vol
        player.audio?.volume = Int32(vol * 100)
    }

    func selectSubtitle(_ index: Int) {
        // -1 disables subtitles
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
                preventSleep()
                if !streamInfoExtracted {
                    extractStreamInfo()
                    extractSubtitles()
                    streamInfoExtracted = true
                }

            case .buffering:
                isBuffering = true
                statusMessage = "Buffering..."

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

            // Once we get time updates, stream is definitely playing
            if isBuffering {
                isBuffering = false
                statusMessage = nil
                cancelStallTimer()
            }

            // Extract stream info once we have video output
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

    private func extractStreamInfo() {
        var info = StreamInfo()

        let videoSize = player.videoSize
        if videoSize.width > 0 && videoSize.height > 0 {
            info.resolution = "\(Int(videoSize.width))x\(Int(videoSize.height))"
        }

        // VLC provides codec info through media tracksInformation
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

        // Get bitrate from media statistics
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
            if index == -1 { continue } // skip "Disable" entry
            options.append((index: index, name: name))
        }
        subtitleOptions = options
    }

    private func fourCCToString(_ code: UInt32) -> String {
        let knownCodecs: [UInt32: String] = [
            0x68323634: "H.264",     // h264
            0x48323634: "H.264",     // H264
            0x61766331: "H.264",     // avc1
            0x68657663: "HEVC",      // hevc
            0x48455643: "HEVC",      // HEVC
            0x68766331: "HEVC",      // hvc1
            0x76703039: "VP9",       // vp09
            0x56503039: "VP9",       // VP09
            0x61763031: "AV1",       // av01
            0x6D703461: "AAC",       // mp4a
            0x61632D33: "AC-3",      // ac-3
            0x65632D33: "E-AC-3",    // ec-3
            0x6F707573: "Opus",      // opus
            0x6D703361: "MP3",       // mp3a
        ]
        if let name = knownCodecs[code] { return name }

        // Try to interpret as FourCC characters
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
        player.stop()
        if isSleepPrevented {
            IOPMAssertionRelease(sleepAssertionID)
        }
    }
}
