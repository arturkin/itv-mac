import XCTest
@testable import ITVKit

final class EPGIndexTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func p(_ ch: String, _ startMin: Int, _ stopMin: Int, _ title: String = "T") -> Programme {
        Programme(channelID: ch,
                  start: t0.addingTimeInterval(Double(startMin) * 60),
                  stop: t0.addingTimeInterval(Double(stopMin) * 60),
                  title: title, desc: "")
    }

    func testProgrammesAreSortedByStart() {
        let idx = EPGIndex(programmes: [p("a", 60, 90), p("a", 0, 30), p("a", 30, 60)])
        let starts = idx.programmes(for: "a").map { $0.start }
        XCTAssertEqual(starts, starts.sorted())
    }

    func testProgrammeAtFindsAiring() {
        let idx = EPGIndex(programmes: [p("a", 0, 30, "first"), p("a", 30, 60, "second")])
        XCTAssertEqual(idx.programme(channelID: "a", at: t0.addingTimeInterval(45 * 60))?.title, "second")
    }

    func testProgrammeAtReturnsNilInGap() {
        // gap between 30 and 60
        let idx = EPGIndex(programmes: [p("a", 0, 30), p("a", 60, 90)])
        XCTAssertNil(idx.programme(channelID: "a", at: t0.addingTimeInterval(45 * 60)))
    }

    func testNowNext() {
        let idx = EPGIndex(programmes: [p("a", 0, 30, "now"), p("a", 30, 60, "next")])
        let nn = idx.nowNext(channelID: "a", at: t0.addingTimeInterval(15 * 60))
        XCTAssertEqual(nn.now?.title, "now")
        XCTAssertEqual(nn.next?.title, "next")
    }

    func testNowNextBeforeFirstProgramme() {
        let idx = EPGIndex(programmes: [p("a", 60, 90, "future")])
        let nn = idx.nowNext(channelID: "a", at: t0)
        XCTAssertNil(nn.now)
        XCTAssertEqual(nn.next?.title, "future")
    }

    func testRangeQueryOverlap() {
        let idx = EPGIndex(programmes: [p("a", 0, 30), p("a", 30, 60), p("a", 60, 90), p("a", 90, 120)])
        let range = t0.addingTimeInterval(45 * 60)...t0.addingTimeInterval(75 * 60)
        XCTAssertEqual(idx.programmes(channelID: "a", in: range).count, 2) // 30-60 and 60-90
    }

    func testBinarySearchMatchesLinearOracle() {
        // Build 500 contiguous programmes and probe random instants.
        var progs: [Programme] = []
        for i in 0..<500 { progs.append(p("a", i * 30, (i + 1) * 30, "p\(i)")) }
        let idx = EPGIndex(programmes: progs)
        for _ in 0..<200 {
            let offset = Double(Int.random(in: 0..<(500 * 30 * 60)))
            let date = t0.addingTimeInterval(offset)
            let oracle = progs.first { $0.contains(date) }
            XCTAssertEqual(idx.programme(channelID: "a", at: date)?.id, oracle?.id)
        }
    }

    func testBounds() {
        let idx = EPGIndex(programmes: [p("a", 0, 30), p("b", 10, 120)])
        XCTAssertEqual(idx.bounds?.lowerBound, t0)
        XCTAssertEqual(idx.bounds?.upperBound, t0.addingTimeInterval(120 * 60))
    }
}
