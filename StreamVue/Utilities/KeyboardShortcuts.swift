import SwiftUI
import AppKit

struct KeyboardShortcutHandler: NSViewRepresentable {
    let onPlayPause: () -> Void
    let onNextChannel: () -> Void
    let onPreviousChannel: () -> Void
    let onToggleFullscreen: () -> Void
    let onExitFullscreen: () -> Void
    let onVolumeUp: () -> Void
    let onVolumeDown: () -> Void

    func makeNSView(context: Context) -> KeyEventView {
        let view = KeyEventView()
        view.handler = context.coordinator
        return view
    }

    func updateNSView(_ nsView: KeyEventView, context: Context) {
        context.coordinator.onPlayPause = onPlayPause
        context.coordinator.onNextChannel = onNextChannel
        context.coordinator.onPreviousChannel = onPreviousChannel
        context.coordinator.onToggleFullscreen = onToggleFullscreen
        context.coordinator.onExitFullscreen = onExitFullscreen
        context.coordinator.onVolumeUp = onVolumeUp
        context.coordinator.onVolumeDown = onVolumeDown
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

    class Coordinator {
        var onPlayPause: () -> Void
        var onNextChannel: () -> Void
        var onPreviousChannel: () -> Void
        var onToggleFullscreen: () -> Void
        var onExitFullscreen: () -> Void
        var onVolumeUp: () -> Void
        var onVolumeDown: () -> Void

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

        func handleKeyDown(_ event: NSEvent) -> Bool {
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
                break
            }
            return false
        }
    }
}

class KeyEventView: NSView {
    var handler: KeyboardShortcutHandler.Coordinator?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if handler?.handleKeyDown(event) != true {
            super.keyDown(with: event)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }
}
