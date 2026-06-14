import XCTest
@testable import ITVKit

final class DataLayerTests: XCTestCase {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("itvkit-epg-\(UUID().uuidString)")
    }

    // MARK: PlaylistLoader

    func testPlaylistLoaderFetchesAndParses() async throws {
        let url = URL(string: "https://itv.example/p/abc/hls.ssl.m3u8")!
        let fetcher = FakeFetcher()
        fetcher.stub(url, data: Fixture.data("sample.m3u8"))
        let playlist = try await PlaylistLoader(fetcher: fetcher).load(from: url)
        XCTAssertEqual(playlist.channels.count, 4)
        XCTAssertEqual(playlist.epgURL?.absoluteString, "https://epg.example/epg.xml.gz")
    }

    // MARK: EPGStore

    private func samplePlaylist() throws -> Playlist {
        try M3UPlaylistParser.parse(Fixture.string("sample.m3u8"))
    }

    func testEPGStoreBuildsFilteredSnapshot() async throws {
        let playlist = try samplePlaylist() // epgURL = https://epg.example/epg.xml.gz
        let fetcher = FakeFetcher()
        fetcher.stub(playlist.epgURL!, data: Fixture.data("epg_sample.xml.gz"))
        let store = EPGStore(fetcher: fetcher, cacheDirectory: tempDir())

        let snap = try await store.snapshot(for: playlist)
        // ch057 is in the playlist; its two programmes survive the channel filter.
        XCTAssertEqual(snap.index.programmes(for: "ch057").count, 2)
        XCTAssertFalse(snap.search.search("футбол").isEmpty)
    }

    func testEPGStoreUsesFreshCacheWithoutRefetching() async throws {
        let playlist = try samplePlaylist()
        let fetcher = FakeFetcher()
        fetcher.stub(playlist.epgURL!, data: Fixture.data("epg_sample.xml.gz"))
        let store = EPGStore(fetcher: fetcher, cacheDirectory: tempDir(), maxAge: 3600)

        _ = try await store.snapshot(for: playlist)
        _ = try await store.snapshot(for: playlist) // should hit cache
        XCTAssertEqual(fetcher.callCount, 1)
    }

    func testEPGStoreForceRefreshRefetches() async throws {
        let playlist = try samplePlaylist()
        let fetcher = FakeFetcher()
        fetcher.stub(playlist.epgURL!, data: Fixture.data("epg_sample.xml.gz"))
        let store = EPGStore(fetcher: fetcher, cacheDirectory: tempDir())

        _ = try await store.snapshot(for: playlist)
        _ = try await store.snapshot(for: playlist, forceRefresh: true)
        XCTAssertEqual(fetcher.callCount, 2)
    }

    func testEPGStoreFallsBackToStaleCacheOnFetchFailure() async throws {
        let playlist = try samplePlaylist()
        let dir = tempDir()
        let fetcher = FakeFetcher()
        fetcher.stub(playlist.epgURL!, data: Fixture.data("epg_sample.xml.gz"))

        // First a successful fetch populates the cache (maxAge 0 so it's instantly stale).
        let store = EPGStore(fetcher: fetcher, cacheDirectory: dir, maxAge: 0)
        _ = try await store.snapshot(for: playlist)

        // Now the network is down; stale cache must still produce a snapshot.
        fetcher.stub(playlist.epgURL!, error: FetcherError.http(500))
        let snap = try await store.snapshot(for: playlist)
        XCTAssertEqual(snap.index.programmes(for: "ch057").count, 2)
    }

    func testEPGStoreThrowsWhenNoEPGURL() async {
        let playlist = Playlist(epgURL: nil, channels: [], groupOrder: [])
        let store = EPGStore(fetcher: FakeFetcher(), cacheDirectory: tempDir())
        do {
            _ = try await store.snapshot(for: playlist)
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? EPGStoreError, .noEPGURL)
        }
    }
}
