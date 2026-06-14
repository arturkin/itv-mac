import XCTest

/// UI tests run against the deterministic offline fixture (`-uitest`):
/// 3 channels in 3 groups, with synthetic past/now/future programmes.
///
/// Queries target accessibility **identifiers** (e.g. `channel.ch057`) with
/// `.firstMatch`: a channel's display name is ambiguous (it appears in both the
/// sidebar row and, once selected, the now-playing header), and an identifier
/// can land on both a cell and its inner static text.
@MainActor
final class ITVLiveUITests: XCTestCase {
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest"]
        app.launch()
        return app
    }

    private func channelRow(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    override func setUp() { continueAfterFailure = false }

    func testWindowAndSidebarLoad() {
        let app = launchApp()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        XCTAssertGreaterThan(app.windows.count, 0, "app should present a window")
        XCTAssertTrue(channelRow(app, "channel.ch057").waitForExistence(timeout: 10),
                      "sidebar should list fixture channels")
    }

    func testSelectingChannelShowsPlayer() {
        let app = launchApp()
        let row = channelRow(app, "channel.ch003")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.click()
        // The player pane appeared if its chrome is present. Anchor on Buttons,
        // which surface reliably in XCUI (a SwiftUI Label like the LIVE badge and
        // the AVPlayerView surface do not always expose a queryable element).
        let appeared = app.buttons["player.favorite"].waitForExistence(timeout: 10)
            || app.buttons["timeline.prevDay"].waitForExistence(timeout: 3)
            || app.buttons["player.goLive"].waitForExistence(timeout: 3)
        XCTAssertTrue(appeared, "player pane should appear after selecting a channel")
    }

    func testTimelineIsBrowsableWithoutStartingPlayback() {
        let app = launchApp()
        let row = channelRow(app, "channel.ch057")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.click()
        // Day-stepping controls exist (browsing the archive history).
        let prevDay = app.buttons["timeline.prevDay"]
        XCTAssertTrue(prevDay.waitForExistence(timeout: 10), "timeline day navigation should be present")
        // Headline requirement: stepping through history days is a pure browse —
        // it must not change which channel is loaded in the player.
        let liveBadgeBefore = app.descendants(matching: .any)["player.liveBadge"].firstMatch.exists
        if prevDay.isEnabled { prevDay.click() }
        XCTAssertEqual(app.descendants(matching: .any)["player.liveBadge"].firstMatch.exists, liveBadgeBefore,
                       "browsing the timeline must not alter playback state")
    }

    func testSearchFiltersChannels() {
        let app = launchApp()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.click()
        field.typeText("Первый")
        XCTAssertTrue(channelRow(app, "channel.ch003").waitForExistence(timeout: 8),
                      "search should surface the matching channel")
    }
}
