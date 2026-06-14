import SwiftUI
import AVKit

/// Bridges AppKit's `AVPlayerView` into SwiftUI. Using `AVPlayerView` (not the
/// SwiftUI `VideoPlayer`) gives the native transport bar, the Picture-in-Picture
/// button, full-screen toggle, and the audio/subtitle menu for free.
///
/// Adds **double-click anywhere on the video to toggle full screen** (the
/// standard media-player gesture), alongside the built-in full-screen button.
struct AVPlayerViewRepresentable: NSViewRepresentable {
    let player: AVPlayer

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> AVPlayerView {
        Self.makePlayerView(player: player, doubleClickTarget: context.coordinator)
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }

    /// Shared so an app-hosted test can verify the double-click wiring without
    /// a SwiftUI `Context`.
    static func makePlayerView(player: AVPlayer, doubleClickTarget: Coordinator) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .floating
        view.allowsPictureInPicturePlayback = true   // the entire macOS PiP integration
        view.showsFullScreenToggleButton = true
        view.videoGravity = .resizeAspect
        view.updatesNowPlayingInfoCenter = true
        // Set the identifier on the AppKit view directly — SwiftUI's
        // `.accessibilityIdentifier` doesn't propagate into an NSViewRepresentable,
        // so XCUI (and VoiceOver) can't otherwise find the player surface.
        view.setAccessibilityIdentifier("player.view")

        // Double-click the video to toggle full screen. `numberOfClicksRequired = 2`
        // means single clicks still pass through to the floating transport controls.
        let doubleClick = NSClickGestureRecognizer(
            target: doubleClickTarget,
            action: #selector(Coordinator.toggleFullScreen(_:))
        )
        doubleClick.numberOfClicksRequired = 2
        doubleClick.delaysPrimaryMouseButtonEvents = false
        view.addGestureRecognizer(doubleClick)
        return view
    }

    final class Coordinator: NSObject {
        @MainActor @objc func toggleFullScreen(_ gesture: NSGestureRecognizer) {
            gesture.view?.window?.toggleFullScreen(nil)
        }
    }
}
