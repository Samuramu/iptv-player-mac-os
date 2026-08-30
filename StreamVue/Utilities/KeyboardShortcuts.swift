import SwiftUI
import AppKit

/// Menu → player bridge (the Playback menu posts these, the player handles them).
enum PlaybackCommands {
    enum Command: String {
        case playPause, nextChannel, previousChannel, toggleFullscreen
    }

    static let notification = Notification.Name("StreamVue.PlaybackCommand")

    static func post(_ command: Command) {
        NotificationCenter.default.post(name: notification, object: nil, userInfo: ["command": command.rawValue])
    }
}

/// Installs an app-wide local key monitor while the player is on screen. A local monitor
/// sees key presses before menu key-equivalents and regardless of which window is key,
/// so shortcuts (including Esc) keep working inside the detached fullscreen panel.
struct KeyboardShortcutHandler: NSViewRepresentable {
    let onPlayPause: () -> Void
    let onNextChannel: () -> Void
    let onPreviousChannel: () -> Void
    let onToggleFullscreen: () -> Void
    let onExitFullscreen: () -> Void
    let onVolumeUp: () -> Void
    let onVolumeDown: () -> Void

    func makeNSView(context: Context) -> NSView {
        context.coordinator.install()
        return NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let c = context.coordinator
        c.onPlayPause = onPlayPause
        c.onNextChannel = onNextChannel
        c.onPreviousChannel = onPreviousChannel
        c.onToggleFullscreen = onToggleFullscreen
        c.onExitFullscreen = onExitFullscreen
        c.onVolumeUp = onVolumeUp
        c.onVolumeDown = onVolumeDown
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onPlayPause: onPlayPause,
            onNextChannel: onNextChannel,
            onPreviousChannel: onPreviousChannel,
            onToggleFullscreen: onToggleFullscreen,
            onExitFullscreen: onExitFullscreen,
            onVolumeUp: onVolumeUp,
            onVolumeDown: onVolumeDown
        )
    }

    final class Coordinator {
        var onPlayPause: () -> Void
        var onNextChannel: () -> Void
        var onPreviousChannel: () -> Void
        var onToggleFullscreen: () -> Void
        var onExitFullscreen: () -> Void
        var onVolumeUp: () -> Void
        var onVolumeDown: () -> Void

        private var monitor: Any?
        private var menuObserver: NSObjectProtocol?

        init(
            onPlayPause: @escaping () -> Void,
            onNextChannel: @escaping () -> Void,
            onPreviousChannel: @escaping () -> Void,
            onToggleFullscreen: @escaping () -> Void,
            onExitFullscreen: @escaping () -> Void,
            onVolumeUp: @escaping () -> Void,
            onVolumeDown: @escaping () -> Void
        ) {
            self.onPlayPause = onPlayPause
            self.onNextChannel = onNextChannel
            self.onPreviousChannel = onPreviousChannel
            self.onToggleFullscreen = onToggleFullscreen
            self.onExitFullscreen = onExitFullscreen
            self.onVolumeUp = onVolumeUp
            self.onVolumeDown = onVolumeDown
        }

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.handleKeyDown(event) else { return event }
                return nil
            }
            menuObserver = NotificationCenter.default.addObserver(
                forName: PlaybackCommands.notification, object: nil, queue: .main
            ) { [weak self] note in
                guard let self,
                      let raw = note.userInfo?["command"] as? String,
                      let command = PlaybackCommands.Command(rawValue: raw) else { return }
                switch command {
                case .playPause: self.onPlayPause()
                case .nextChannel: self.onNextChannel()
                case .previousChannel: self.onPreviousChannel()
                case .toggleFullscreen: self.onToggleFullscreen()
                }
            }
        }

        func uninstall() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            if let menuObserver { NotificationCenter.default.removeObserver(menuObserver) }
            menuObserver = nil
        }

        deinit { uninstall() }

        private func isTypingInTextField(_ event: NSEvent) -> Bool {
            guard let responder = event.window?.firstResponder else { return false }
            return responder is NSTextView || responder is NSTextField
        }

        func handleKeyDown(_ event: NSEvent) -> Bool {
            // Don't hijack typing in the search field / sheets; do let Esc through to
            // exit fullscreen though.
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard modifiers.isEmpty else { return false }
            if event.keyCode != 53 && isTypingInTextField(event) { return false }
            if event.window is FullscreenPanel == false,
               let sheet = event.window?.attachedSheet, sheet.isVisible { return false }

            switch event.keyCode {
            case 49: // Space
                onPlayPause()
                return true
            case 126: // Up arrow
                onPreviousChannel()
                return true
            case 125: // Down arrow
                onNextChannel()
                return true
            case 124: // Right arrow
                onVolumeUp()
                return true
            case 123: // Left arrow
                onVolumeDown()
                return true
            case 53: // Escape — only exits fullscreen, never enters
                onExitFullscreen()
                return true
            case 3: // F key — toggles
                onToggleFullscreen()
                return true
            default:
                return false
            }
        }
    }
}
