import XCTest
@testable import ITVKit

final class ProgrammeSearchIndexTests: XCTestCase {
    private func channel(_ id: String, _ name: String) -> Channel {
        Channel(id: id, name: name, groupTitle: "G", logoURL: nil,
                liveURL: URL(string: "https://e/\(id)/index.m3u8?token=T")!,
                recDays: 5, cdnBaseURL: URL(string: "https://e/\(id)")!, streamName: id, token: "T")
    }
    private func prog(_ ch: String, _ title: String) -> Programme {
        Programme(channelID: ch, start: Date(timeIntervalSince1970: 0), stop: Date(timeIntervalSince1970: 1800), title: title, desc: "")
    }

    private func index() -> ProgrammeSearchIndex {
        ProgrammeSearchIndex(
            channels: [channel("ch057", "Матч! HD"), channel("ch003", "Первый Канал HD")],
            programmes: [prog("ch003", "Время покажет"), prog("ch057", "Футбол. Чемпионат")]
        )
    }

    func testFindsChannelByName() {
        let hits = index().search("матч")
        XCTAssertTrue(hits.contains { $0.kind == .channel && $0.channelID == "ch057" })
    }

    func testFindsProgrammeByTitle() {
        let hits = index().search("футбол")
        XCTAssertTrue(hits.contains { $0.kind == .programme && $0.title == "Футбол. Чемпионат" })
    }

    func testCaseInsensitive() {
        XCTAssertFalse(index().search("ВРЕМЯ").isEmpty)
        XCTAssertFalse(index().search("время").isEmpty)
    }

    func testEmptyQueryReturnsNothing() {
        XCTAssertTrue(index().search("   ").isEmpty)
        XCTAssertTrue(index().search("").isEmpty)
    }

    func testPrefixRanksAboveSubstring() {
        let idx = ProgrammeSearchIndex(channels: [], programmes: [
            prog("a", "Новости спорта"),   // "спорт" is a substring
            prog("b", "Спорт сегодня"),     // "спорт" is a prefix
        ])
        let hits = idx.search("спорт")
        XCTAssertEqual(hits.first?.title, "Спорт сегодня")
    }

    func testRespectsLimit() {
        let many = (0..<100).map { prog("a", "Show \($0)") }
        let hits = ProgrammeSearchIndex(channels: [], programmes: many).search("show", limit: 10)
        XCTAssertEqual(hits.count, 10)
    }

    func testDiacriticInsensitive() {
        let idx = ProgrammeSearchIndex(channels: [channel("c", "Cafe")], programmes: [prog("c", "Café Show")])
        XCTAssertFalse(idx.search("cafe").isEmpty)
    }
}
