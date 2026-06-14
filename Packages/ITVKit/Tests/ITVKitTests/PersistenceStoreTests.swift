import XCTest
@testable import ITVKit

final class PersistenceStoreTests: XCTestCase {
    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("itvkit-tests-\(UUID().uuidString)")
        return dir
    }

    func testFavoritesRoundTrip() async throws {
        let dir = tempDir()
        let store = try PersistenceStore(directory: dir)
        await store.saveFavorites(["ch057", "ch003"])

        let reopened = try PersistenceStore(directory: dir)
        let loaded = await reopened.loadFavorites()
        XCTAssertEqual(loaded, ["ch057", "ch003"]) // order preserved
    }

    func testResumeSetClear() async throws {
        let store = try PersistenceStore(directory: tempDir())
        await store.setResume(key: "ch057@123", seconds: 42.5)
        let v = await store.resume(forKey: "ch057@123")
        XCTAssertEqual(v, 42.5)
        await store.clearResume(key: "ch057@123")
        let cleared = await store.resume(forKey: "ch057@123")
        XCTAssertNil(cleared)
    }

    func testRecentsDedupeAndOrder() async throws {
        let store = try PersistenceStore(directory: tempDir())
        let base = Date(timeIntervalSince1970: 1000)
        await store.addRecent(RecentItem(channelID: "a", programmeStart: nil, title: "A1", lastPlayed: base))
        await store.addRecent(RecentItem(channelID: "b", programmeStart: nil, title: "B1", lastPlayed: base.addingTimeInterval(10)))
        // Re-watch A (same id) → should move to front, not duplicate.
        await store.addRecent(RecentItem(channelID: "a", programmeStart: nil, title: "A2", lastPlayed: base.addingTimeInterval(20)))

        let recents = await store.loadRecents()
        XCTAssertEqual(recents.count, 2)
        XCTAssertEqual(recents.first?.channelID, "a")
        XCTAssertEqual(recents.first?.title, "A2")
    }

    func testRecentsCap() async throws {
        let store = try PersistenceStore(directory: tempDir(), recentsLimit: 3)
        for i in 0..<10 {
            await store.addRecent(RecentItem(channelID: "ch\(i)", programmeStart: nil, title: "T\(i)", lastPlayed: Date(timeIntervalSince1970: Double(i))))
        }
        let recents = await store.loadRecents()
        XCTAssertEqual(recents.count, 3)
        XCTAssertEqual(recents.first?.channelID, "ch9") // most recent kept
    }

    func testCorruptFileDegradesToDefault() async throws {
        let dir = tempDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{ this is not valid json".utf8).write(to: dir.appendingPathComponent("favorites.json"))
        let store = try PersistenceStore(directory: dir)
        let loaded = await store.loadFavorites()
        XCTAssertEqual(loaded, []) // no crash, empty default
    }

    func testResumeKeyFormat() {
        let key = ResumeKey.make(channelID: "ch057", programmeStart: Date(timeIntervalSince1970: 1781393772))
        XCTAssertEqual(key, "ch057@1781393772")
    }
}
