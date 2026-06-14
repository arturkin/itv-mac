import XCTest
import AVFoundation
import AppKit
@testable import ITVLive

@MainActor
final class PlayerViewTests: XCTestCase {
    /// Verifies the double-click → full-screen gesture is wired onto the player
    /// view. The full-screen transition itself needs a real window + display, so
    /// it's exercised manually / on an interactive login; this guards the wiring.
    func testPlayerHasDoubleClickFullScreenGesture() {
        let view = AVPlayerViewRepresentable.makePlayerView(
            player: AVPlayer(),
            doubleClickTarget: AVPlayerViewRepresentable.Coordinator()
        )
        let doubleClick = view.gestureRecognizers
            .compactMap { $0 as? NSClickGestureRecognizer }
            .first { $0.numberOfClicksRequired == 2 }

        XCTAssertNotNil(doubleClick, "Player view should carry a double-click recognizer for full screen")
        XCTAssertNotNil(doubleClick?.action, "Double-click recognizer should have an action wired")
        XCTAssertFalse(doubleClick?.delaysPrimaryMouseButtonEvents ?? true,
                       "Single clicks must still reach the transport controls")
    }
}
