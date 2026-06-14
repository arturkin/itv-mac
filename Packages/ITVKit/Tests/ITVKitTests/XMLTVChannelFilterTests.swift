import XCTest
@testable import ITVKit

final class XMLTVChannelFilterTests: XCTestCase {
    func testChannelFilterKeepsOnlyRequested() throws {
        let epg = try XMLTVParser.parse(Fixture.data("epg_sample.xml"), channelIDs: ["ch057"])
        XCTAssertTrue(epg.programmes.allSatisfy { $0.channelID == "ch057" })
        XCTAssertEqual(epg.channelNames["ch057"], "Матч! HD")
        XCTAssertNil(epg.channelNames["ch003"])
        XCTAssertEqual(epg.programmes.count, 2) // only ch057's two programmes
    }

    func testNilFilterKeepsEverything() throws {
        let epg = try XMLTVParser.parse(Fixture.data("epg_sample.xml"), channelIDs: nil)
        XCTAssertEqual(epg.programmes.count, 3)
    }
}
