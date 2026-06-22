import XCTest
import AVFoundation
import ITVKit
@testable import ITVLive

/// Offline state-machine checks for time-shift seeking. These never hit the
/// network (the bogus stream URL just fails asynchronously, after the synchronous
/// state has been set) and need no UI-automation permission.
@MainActor
final class PlayerControllerTests: XCTestCase {
    private func channel(recDays: Int) -> Channel {
        Channel(
            id: "ch057", name: "Матч! HD", groupTitle: "Спорт", logoURL: nil,
            liveURL: URL(string: "https://cloud02.cdn.example/ch057/index.m3u8?token=TOK")!,
            recDays: recDays,
            cdnBaseURL: URL(string: "https://cloud02.cdn.example/ch057")!,
            streamName: "ch057", token: "TOK"
        )
    }

    func testLiveResetsTimeShiftState() {
        let pc = PlayerController()
        pc.playLive(channel(recDays: 10))
        XCTAssertTrue(pc.isLive)
        XCTAssertNil(pc.timeShiftAnchor)
        XCTAssertNil(pc.currentAbsoluteDate)
        XCTAssertTrue(pc.canTimeShift)
    }

    func testStepBackwardEntersTimeShiftAnchoredHalfHourAgo() throws {
        let pc = PlayerController()
        pc.playLive(channel(recDays: 10))
        let before = Date()
        pc.stepBackward() // default 30 min
        XCTAssertFalse(pc.isLive)
        let anchor = try XCTUnwrap(pc.timeShiftAnchor)
        let expected = before.addingTimeInterval(-PlayerController.defaultSeekInterval)
        XCTAssertEqual(anchor.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 5,
                       "anchor should be ~30 min before now")
    }

    func testStepForwardFromHalfHourBackReturnsToLive() {
        let pc = PlayerController()
        pc.playLive(channel(recDays: 10))
        pc.stepBackward()            // 30 min behind
        XCTAssertFalse(pc.isLive)
        pc.stepForward()             // +30 min == live edge
        XCTAssertTrue(pc.isLive, "stepping forward back to the live edge should resume live")
        XCTAssertNil(pc.timeShiftAnchor)
    }

    func testChannelWithoutArchiveCannotTimeShift() {
        let pc = PlayerController()
        pc.playLive(channel(recDays: 0))
        XCTAssertFalse(pc.canTimeShift)
        pc.stepBackward()
        XCTAssertTrue(pc.isLive, "a channel without archive must stay live")
        XCTAssertNil(pc.timeShiftAnchor)
    }

    func testJumpToLiveClearsAnchor() {
        let pc = PlayerController()
        pc.playLive(channel(recDays: 10))
        pc.stepBackward()
        XCTAssertNotNil(pc.timeShiftAnchor)
        pc.jumpToLive()
        XCTAssertTrue(pc.isLive)
        XCTAssertNil(pc.timeShiftAnchor)
    }
}
