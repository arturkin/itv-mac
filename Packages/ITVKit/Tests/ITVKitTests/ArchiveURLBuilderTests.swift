import XCTest
@testable import ITVKit

final class ArchiveURLBuilderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000) // fixed reference

    private func channel(recDays: Int) -> Channel {
        Channel(
            id: "ch057", name: "Матч! HD", groupTitle: "Спорт", logoURL: nil,
            liveURL: URL(string: "https://cloud02.cdn.example/ch057/index.m3u8?token=TOK")!,
            recDays: recDays,
            cdnBaseURL: URL(string: "https://cloud02.cdn.example/ch057")!,
            streamName: "ch057", token: "TOK"
        )
    }

    private func prog(start: TimeInterval, stop: TimeInterval) -> Programme {
        Programme(channelID: "ch057",
                  start: now.addingTimeInterval(start),
                  stop: now.addingTimeInterval(stop),
                  title: "X", desc: "")
    }

    func testLivePassthrough() {
        XCTAssertEqual(ArchiveURLBuilder.liveURL(for: channel(recDays: 10)).absoluteString,
                       "https://cloud02.cdn.example/ch057/index.m3u8?token=TOK")
    }

    func testEndedProgrammeBuildsBoundedArchiveURL() {
        let p = prog(start: -7200, stop: -5400) // 2h..1.5h ago, 30 min
        let url = ArchiveURLBuilder.catchUpURL(for: channel(recDays: 10), programme: p, now: now)
        let expectedStart = Int(now.timeIntervalSince1970) - 7200
        XCTAssertEqual(url?.absoluteString,
                       "https://cloud02.cdn.example/ch057/archive-\(expectedStart)-1800.m3u8?token=TOK")
    }

    func testInProgressProgrammeBuildsIndexNowURL() {
        let p = prog(start: -600, stop: 600) // started 10 min ago, ends in 10 min
        let url = ArchiveURLBuilder.catchUpURL(for: channel(recDays: 10), programme: p, now: now)
        let expectedStart = Int(now.timeIntervalSince1970) - 600
        XCTAssertEqual(url?.absoluteString,
                       "https://cloud02.cdn.example/ch057/index-\(expectedStart)-now.m3u8?token=TOK")
    }

    func testFutureProgrammeHasNoCatchUp() {
        let p = prog(start: 3600, stop: 7200)
        XCTAssertNil(ArchiveURLBuilder.catchUpURL(for: channel(recDays: 10), programme: p, now: now))
    }

    func testNoArchiveChannelHasNoCatchUp() {
        let p = prog(start: -7200, stop: -5400)
        XCTAssertNil(ArchiveURLBuilder.catchUpURL(for: channel(recDays: 0), programme: p, now: now))
        XCTAssertNil(ArchiveURLBuilder.mode(for: channel(recDays: 0), programme: p, now: now))
    }

    func testProgrammeFullyOutsideWindowHasNoCatchUp() {
        let p = prog(start: -20 * 86400, stop: -20 * 86400 + 1800) // 20 days ago, window is 10
        XCTAssertNil(ArchiveURLBuilder.catchUpURL(for: channel(recDays: 10), programme: p, now: now))
    }

    func testProgrammePartlyBeforeWindowIsClampedToWindowStart() {
        // starts 11 days ago, ends 9 days ago; window starts 10 days ago.
        let p = prog(start: -11 * 86400, stop: -9 * 86400)
        let mode = ArchiveURLBuilder.mode(for: channel(recDays: 10), programme: p, now: now)
        let windowStart = Int(now.timeIntervalSince1970) - 10 * 86400
        let clampedStop = Int(now.timeIntervalSince1970) - 9 * 86400
        XCTAssertEqual(mode, .archive(start: windowStart, duration: clampedStop - windowStart))
    }

    func testModeForEndedProgramme() {
        let p = prog(start: -7200, stop: -5400)
        let expectedStart = Int(now.timeIntervalSince1970) - 7200
        XCTAssertEqual(ArchiveURLBuilder.mode(for: channel(recDays: 10), programme: p, now: now),
                       .archive(start: expectedStart, duration: 1800))
    }

    func testTimestampMathIsTimezoneIndependent() {
        // The builder uses timeIntervalSince1970, so the process TZ must not matter.
        let p = prog(start: -3600, stop: -1800)
        let url = ArchiveURLBuilder.catchUpURL(for: channel(recDays: 10), programme: p, now: now)
        let expectedStart = Int(now.timeIntervalSince1970) - 3600
        XCTAssertTrue(url!.absoluteString.contains("archive-\(expectedStart)-1800.m3u8"))
    }
}
