import SwiftUI
import AVFoundation
import AVKit
import IOKit.pwr_mgt

struct PlayerView: NSViewRepresentable {
    let player: AVPlayer
    let onDoubleClick: () -> Void

    func makeNSView(context: Context) -> DoubleClickAVPlayerView {
        let view = DoubleClickAVPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.showsFullScreenToggleButton = false
        view.allowsPictureInPicturePlayback = false
        view.videoGravity = .resizeAspect
        view.onDoubleClick = onDoubleClick
        return view
    }

    func updateNSView(_ nsView: DoubleClickAVPlayerView, context: Context) {
        nsView.player = player
        nsView.onDoubleClick = onDoubleClick
    }
}

class DoubleClickAVPlayerView: AVPlayerView {
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
final class PlayerState {
    var player = AVPlayer()
    var isPlaying = false
    var volume: Float = 1.0
    var isBuffering = false
    var currentTime: Double = 0
    var duration: Double = 0
    var errorMessage: String?
    var statusMessage: String?
    var streamInfo = StreamInfo()
    var subtitleOptions: [AVMediaSelectionOption] = []
    var selectedSubtitle: AVMediaSelectionOption?

    private var currentURLString: String?
    private var triedAlternate = false
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var bufferingObservation: NSKeyValueObservation?
    private var bufferFullObservation: NSKeyValueObservation?
    private var rateObservation: NSKeyValueObservation?
    private var stallTimer: Timer?
    private var sleepAssertionID: IOPMAssertionID = 0
    private var isSleepPrevented = false

    init() {
        player.automaticallyWaitsToMinimizeStalling = true
        setupObservers()
    }

    func play(url: URL) {
        let asset = AVURLAsset(url: url, options: [
            "AVURLAssetHTTPHeaderFieldsKey": [
                "User-Agent": "Mozilla/5.0"
            ]
        ])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 10

        player.replaceCurrentItem(with: item)
        player.volume = volume
        player.play()
        isPlaying = true
        isBuffering = true
        errorMessage = nil
        statusMessage = "Connecting..."
        streamInfo = StreamInfo()
        subtitleOptions = []
        selectedSubtitle = nil
        startStallTimer()

        observeItem(item)
    }

    func play(urlString: String) {
        currentURLString = urlString
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
        player.pause()
        player.replaceCurrentItem(with: nil)
        isPlaying = false
        statusMessage = nil
        isBuffering = false
        cancelStallTimer()
        allowSleep()
    }

    func setVolume(_ vol: Float) {
        volume = vol
        player.volume = vol
    }

    func selectSubtitle(_ option: AVMediaSelectionOption?) {
        guard let item = player.currentItem,
              let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) else { return }
        item.select(option, in: group)
        selectedSubtitle = option
    }

    private func setupObservers() {
        rateObservation = player.observe(\.rate) { [weak self] player, _ in
            Task { @MainActor in
                let playing = player.rate > 0
                self?.isPlaying = playing
                if playing {
                    self?.preventSleep()
                } else {
                    self?.allowSleep()
                }
            }
        }
    }

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

    private func observeItem(_ item: AVPlayerItem) {
        statusObservation?.invalidate()
        bufferingObservation?.invalidate()
        bufferFullObservation?.invalidate()

        statusObservation = item.observe(\.status) { [weak self] item, _ in
            Task { @MainActor in
                switch item.status {
                case .readyToPlay:
                    self?.statusMessage = "Preparing stream..."
                    self?.extractStreamInfo(from: item)
                    self?.extractSubtitles(from: item)
                    // Clear status once actually playing
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if self?.isPlaying == true {
                            self?.statusMessage = nil
                            self?.isBuffering = false
                            self?.cancelStallTimer()
                        }
                    }
                case .failed:
                    self?.cancelStallTimer()
                    self?.isBuffering = false
                    self?.statusMessage = nil
                    let underlying = item.error?.localizedDescription ?? "Playback failed"
                    self?.errorMessage = underlying
                    self?.isPlaying = false
                default:
                    break
                }
            }
        }

        bufferingObservation = item.observe(\.isPlaybackBufferEmpty) { [weak self] item, _ in
            Task { @MainActor in
                if item.isPlaybackBufferEmpty {
                    self?.isBuffering = true
                    self?.statusMessage = "Buffering..."
                }
            }
        }

        bufferFullObservation = item.observe(\.isPlaybackLikelyToKeepUp) { [weak self] item, _ in
            Task { @MainActor in
                if item.isPlaybackLikelyToKeepUp {
                    self?.isBuffering = false
                    self?.statusMessage = nil
                    self?.cancelStallTimer()
                }
            }
        }
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

    private func extractStreamInfo(from item: AVPlayerItem) {
        var info = StreamInfo()

        for track in item.tracks {
            guard let assetTrack = track.assetTrack else { continue }

            if assetTrack.mediaType == .video {
                let size = assetTrack.naturalSize
                info.resolution = "\(Int(size.width))x\(Int(size.height))"

                let rate = assetTrack.nominalFrameRate
                if rate > 0 {
                    info.fps = String(format: "%.0f fps", rate)
                }

                let bitrate = assetTrack.estimatedDataRate
                if bitrate > 0 {
                    if bitrate > 1_000_000 {
                        info.bitrate = String(format: "%.1f Mbps", bitrate / 1_000_000)
                    } else {
                        info.bitrate = String(format: "%.0f Kbps", bitrate / 1_000)
                    }
                }

                for desc in assetTrack.formatDescriptions {
                    let formatDesc = desc as! CMFormatDescription
                    let codec = CMFormatDescriptionGetMediaSubType(formatDesc)
                    info.videoCodec = fourCCToString(codec)
                }
            }

            if assetTrack.mediaType == .audio {
                for desc in assetTrack.formatDescriptions {
                    let formatDesc = desc as! CMFormatDescription
                    let codec = CMFormatDescriptionGetMediaSubType(formatDesc)
                    info.audioCodec = fourCCToString(codec)
                }
            }
        }

        streamInfo = info
    }

    private func extractSubtitles(from item: AVPlayerItem) {
        if let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) {
            subtitleOptions = group.options
        }
    }

    private func fourCCToString(_ code: FourCharCode) -> String {
        let mapping: [FourCharCode: String] = [
            kCMVideoCodecType_H264: "H.264",
            kCMVideoCodecType_HEVC: "HEVC",
            kCMVideoCodecType_VP9: "VP9",
            kCMVideoCodecType_AV1: "AV1",
        ]
        if let name = mapping[code] { return name }

        let chars: [Character] = [
            Character(UnicodeScalar((code >> 24) & 0xFF)!),
            Character(UnicodeScalar((code >> 16) & 0xFF)!),
            Character(UnicodeScalar((code >> 8) & 0xFF)!),
            Character(UnicodeScalar(code & 0xFF)!),
        ]
        return String(chars).trimmingCharacters(in: .whitespaces)
    }

    deinit {
        stallTimer?.invalidate()
        statusObservation?.invalidate()
        bufferingObservation?.invalidate()
        bufferFullObservation?.invalidate()
        rateObservation?.invalidate()
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        if isSleepPrevented {
            IOPMAssertionRelease(sleepAssertionID)
        }
    }
}
