import XCTest
@testable import ITVKit

/// Network-gated end-to-end checks against the live itv.live service.
/// Run with `ITV_LIVE_QA=1 ITV_PLAYLIST_URL=<playlist> swift test`.
/// Skipped otherwise, so the default suite stays hermetic.
final class RealServiceTests: XCTestCase {
    private func requireLiveURL() throws -> URL {
        let env = ProcessInfo.processInfo.environment
        guard env["ITV_LIVE_QA"] == "1", let s = env["ITV_PLAYLIST_URL"], let url = URL(string: s) else {
            throw XCTSkip("Set ITV_LIVE_QA=1 and ITV_PLAYLIST_URL to run live checks.")
        }
        return url
    }

    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("itvkit-live-\(UUID().uuidString)")
    }

    func testRealPlaylistParses() async throws {
        let url = try requireLiveURL()
        let playlist = try await PlaylistLoader().load(from: url)
        XCTAssertGreaterThan(playlist.channels.count, 100, "expected a substantial channel list")
        XCTAssertNotNil(playlist.epgURL, "EPG URL should be discovered from url-tvg header")
        XCTAssertTrue(playlist.channels.contains { $0.hasArchive }, "expected channels with archive")
        print("LIVE: parsed \(playlist.channels.count) channels, \(playlist.groupOrder.count) groups")
    }

    func testRealEPGBuildsSnapshot() async throws {
        let url = try requireLiveURL()
        let playlist = try await PlaylistLoader().load(from: url)
        let store = EPGStore(cacheDirectory: tempDir())

        let clock = Date()
        let snap = try await store.snapshot(for: playlist)
        print("LIVE: built EPG snapshot with \(snap.index.programmeCount) programmes in \(String(format: "%.2f", Date().timeIntervalSince(clock)))s")
        XCTAssertGreaterThan(snap.index.programmeCount, 1000)

        // now/next works for some channel.
        let now = Date()
        let hasNowNext = playlist.channels.contains { snap.index.nowNext(channelID: $0.id, at: now).now != nil }
        XCTAssertTrue(hasNowNext, "at least one channel should have a current programme")
    }

    func testRealArchiveURLIsReachableVOD() async throws {
        let url = try requireLiveURL()
        let playlist = try await PlaylistLoader().load(from: url)
        let store = EPGStore(cacheDirectory: tempDir())
        let snap = try await store.snapshot(for: playlist)
        let now = Date()

        // Find an archived channel with a programme that fully aired inside its window.
        var built: URL?
        var channelName = ""
        for ch in playlist.channels where ch.hasArchive {
            let windowStart = now.addingTimeInterval(-Double(ch.recDays) * 86_400)
            if let past = snap.index.programmes(for: ch.id).last(where: { $0.hasEnded(at: now) && $0.start > windowStart }),
               let u = ArchiveURLBuilder.catchUpURL(for: ch, programme: past, now: now) {
                built = u; channelName = ch.name; break
            }
        }
        let archiveURL = try XCTUnwrap(built, "could not build a catch-up URL from EPG")
        print("LIVE: catch-up URL for \(channelName): \(archiveURL.absoluteString)")

        let master = String(decoding: try await URLSessionFetcher().data(from: archiveURL), as: UTF8.self)
        XCTAssertTrue(master.contains("#EXTM3U"), "archive master should be a valid HLS playlist")
    }
}
