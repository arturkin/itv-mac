import XCTest
import AppKit
@testable import ITVLive

/// Verifies the SwiftUI app actually creates its main window. App-hosted unit
/// tests launch the real app in-process (no UI-automation entitlement needed),
/// so `NSApp.windows` reflects the real scene graph.
@MainActor
final class AppWindowTests: XCTestCase {
    func testMainWindowIsCreated() {
        let deadline = Date().addingTimeInterval(10)
        var titles: [String] = []
        while Date() < deadline {
            titles = NSApp.windows.map { $0.title }
            if NSApp.windows.contains(where: { $0.title.localizedCaseInsensitiveContains("itv") || $0.contentView != nil && $0.isVisible }) {
                // A real content window exists.
                if NSApp.windows.contains(where: { $0.frame.width > 200 && $0.frame.height > 200 }) {
                    return
                }
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        }
        XCTFail("No main window was created. Window titles: \(titles)")
    }
}
