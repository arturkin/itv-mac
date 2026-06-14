import XCTest
@testable import ITVKit

final class XMLTVParserTests: XCTestCase {
    private func parse() throws -> EPGData {
        try XMLTVParser.parse(Fixture.data("epg_sample.xml"))
    }

    func testParsesChannelNames() throws {
        let epg = try parse()
        XCTAssertEqual(epg.channelNames["ch057"], "Матч! HD")
        XCTAssertEqual(epg.channelNames["ch003"], "Первый Канал HD")
    }

    func testParsesAllProgrammes() throws {
        let epg = try parse()
        XCTAssertEqual(epg.programmes.count, 3)
    }

    func testParsesTitleAndDuration() throws {
        let epg = try parse()
        let p = try XCTUnwrap(epg.programmes.first { $0.title == "Футбол. Чемпионат" })
        XCTAssertEqual(p.channelID, "ch057")
        XCTAssertEqual(p.duration, 90 * 60) // 12:00 → 13:30
    }

    func testHandlesCDATAWithEntities() throws {
        let epg = try parse()
        let p = try XCTUnwrap(epg.programmes.first { $0.title == "Новости спорта" })
        XCTAssertEqual(p.desc, "Обзор & итоги <дня>")
    }

    func testMixedTimezoneOffsets() throws {
        let epg = try parse()
        // ch003 programme uses +0000.
        let p = try XCTUnwrap(epg.programmes.first { $0.channelID == "ch003" })
        XCTAssertEqual(p.duration, 60 * 60)
        XCTAssertEqual(p.start, XMLTVDateParser.date(from: "20260614120000 +0000"))
    }
}
