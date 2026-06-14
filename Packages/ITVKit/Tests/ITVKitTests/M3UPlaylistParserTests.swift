import XCTest
@testable import ITVKit

final class M3UPlaylistParserTests: XCTestCase {
    private func parseSample() throws -> Playlist {
        try M3UPlaylistParser.parse(Fixture.string("sample.m3u8"))
    }

    func testParsesAllChannels() throws {
        let pl = try parseSample()
        XCTAssertEqual(pl.channels.count, 4)
    }

    func testDiscoversEPGURL() throws {
        let pl = try parseSample()
        XCTAssertEqual(pl.epgURL?.absoluteString, "https://epg.example/epg.xml.gz")
    }

    func testGroupOrderIsFirstSeen() throws {
        let pl = try parseSample()
        XCTAssertEqual(pl.groupOrder, ["Спорт", "Новости", "Кино"])
    }

    func testParsesAttributesAndStreamAddressing() throws {
        let pl = try parseSample()
        let ch = try XCTUnwrap(pl.channels.first { $0.id == "ch057" })
        XCTAssertEqual(ch.name, "Матч! HD")
        XCTAssertEqual(ch.groupTitle, "Спорт")
        XCTAssertEqual(ch.recDays, 10)
        XCTAssertTrue(ch.hasArchive)
        XCTAssertEqual(ch.token, "TESTTOKEN57")
        XCTAssertEqual(ch.streamName, "ch057")
        XCTAssertEqual(ch.cdnBaseURL.absoluteString, "https://cloud02.cdn.example/ch057")
        XCTAssertEqual(ch.logoURL?.absoluteString, "https://logo.example/ch057.png")
        XCTAssertEqual(ch.liveURL.absoluteString, "https://cloud02.cdn.example/ch057/index.m3u8?token=TESTTOKEN57")
    }

    func testMissingTVGRecMeansNoArchive() throws {
        let pl = try parseSample()
        let ch = try XCTUnwrap(pl.channels.first { $0.id == "ch003" }) // no tvg-rec attribute
        XCTAssertEqual(ch.recDays, 0)
        XCTAssertFalse(ch.hasArchive)
    }

    func testExplicitZeroTVGRecMeansNoArchive() throws {
        let pl = try parseSample()
        let ch = try XCTUnwrap(pl.channels.first { $0.id == "ch500" })
        XCTAssertEqual(ch.recDays, 0)
        XCTAssertFalse(ch.hasArchive)
    }

    func testHandlesCRLFLineEndings() throws {
        let crlf = "#EXTM3U url-tvg=\"https://epg.example/e.xml.gz\"\r\n" +
            "#EXTINF:-1 tvg-id=\"ch001\" tvg-rec=\"5\" group-title=\"News\", Test One\r\n" +
            "#EXTGRP:News\r\n" +
            "https://cloud01.cdn.example/ch001/index.m3u8?token=ABC\r\n"
        let pl = try M3UPlaylistParser.parse(crlf)
        XCTAssertEqual(pl.channels.count, 1)
        let ch = try XCTUnwrap(pl.channels.first)
        XCTAssertEqual(ch.id, "ch001")
        XCTAssertEqual(ch.token, "ABC") // no trailing \r leaked into token
        XCTAssertEqual(ch.recDays, 5)
    }

    func testThrowsWhenNotAPlaylist() {
        XCTAssertThrowsError(try M3UPlaylistParser.parse("just some text\nnot m3u")) { error in
            XCTAssertEqual(error as? M3UParseError, .notAPlaylist)
        }
    }
}
