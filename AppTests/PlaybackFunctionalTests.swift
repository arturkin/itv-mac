import XCTest
import AVFoundation
import ITVKit
@testable import ITVLive

/// Network-gated playback verification using a real `AVPlayer`. These do NOT
/// need UI-automation TCC (unlike XCUITests), so they run headlessly.
/// Enable with `ITV_LIVE_QA=1 ITV_PLAYLIST_URL=<playlist>`.
@MainActor
final class PlaybackFunctionalTests: XCTestCase {
    private func liveURL() throws -> URL {
        let env = ProcessInfo.processInfo.environment
        // xcodebuild forwards TEST_RUNNER_-prefixed vars to the test host; accept either form.
        func value(_ key: String) -> String? { env[key] ?? env["TEST_RUNNER_\(key)"] }
        guard value("ITV_LIVE_QA") == "1", let s = value("ITV_PLAYLIST_URL"), let url = URL(string: s) else {
            throw XCTSkip("Set ITV_LIVE_QA=1 and ITV_PLAYLIST_URL to run playback checks.")
        }
        return url
    }

    private func tmp() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("itv-pb-\(UUID().uuidString)")
    }

    @discardableResult
    private func waitUntilReady(_ item: AVPlayerItem, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if item.status == .readyToPlay { return true }
            if item.status == .failed { return false }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return item.status == .readyToPlay
    }

    func testLivePlaybackReachesReadyAndAdvances() async throws {
        let url = try liveURL()
        let playlist = try await PlaylistLoader().load(from: url)
        let channel = try XCTUnwrap(playlist.channels.first)

        let item = AVPlayerItem(url: ArchiveURLBuilder.liveURL(for: channel))
        let player = AVPlayer(playerItem: item)
        player.play()

        let ready = await waitUntilReady(item, timeout: 25)
        XCTAssertTrue(ready,
                      "live stream should reach readyToPlay (status=\(item.status.rawValue), err=\(String(describing: item.error)))")

        // Playback should make progress within a few seconds.
        let t0 = player.currentTime().seconds
        let deadline = Date().addingTimeInterval(8)
        var advanced = false
        while Date() < deadline {
            if player.currentTime().seconds > t0 + 0.5 { advanced = true; break }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        XCTAssertTrue(advanced, "live playback time should advance")
        player.pause()
    }

    func testArchivePlaybackIsFiniteSeekableVOD() async throws {
        let url = try liveURL()
        let playlist = try await PlaylistLoader().load(from: url)
        let snapshot = try await EPGStore(cacheDirectory: tmp()).snapshot(for: playlist)
        let now = Date()

        var archiveURL: URL?
        var expectedDuration: TimeInterval = 0
        var channelName = ""
        for ch in playlist.channels where ch.hasArchive {
            let windowStart = now.addingTimeInterval(-Double(ch.recDays) * 86_400)
            if let past = snapshot.index.programmes(for: ch.id).last(where: { $0.hasEnded(at: now) && $0.start > windowStart }),
               let built = ArchiveURLBuilder.catchUpURL(for: ch, programme: past, now: now) {
                archiveURL = built
                expectedDuration = past.duration
                channelName = ch.name
                break
            }
        }
        let resolved = try XCTUnwrap(archiveURL, "should build a catch-up URL")
        print("PLAYBACK: archive \(channelName) expected≈\(Int(expectedDuration))s \(resolved.lastPathComponent)")

        let item = AVPlayerItem(url: resolved)
        let player = AVPlayer(playerItem: item) // must be retained to drive the item to readyToPlay
        let ready = await waitUntilReady(item, timeout: 25)
        XCTAssertTrue(ready,
                      "archive clip should reach readyToPlay (err=\(String(describing: item.error)))")

        let duration = try await item.asset.load(.duration).seconds
        XCTAssertTrue(duration.isFinite && duration > 0, "archive VOD must have finite duration, got \(duration)")
        // The server rounds the start to a GOP boundary, so allow generous tolerance.
        XCTAssertEqual(duration, expectedDuration, accuracy: 180,
                       "archive duration should approximate the programme length")
        // A finite, fully-seekable range proves it's VOD (catch-up scrubs to programme length).
        let seekable = item.seekableTimeRanges.last?.timeRangeValue
        XCTAssertNotNil(seekable, "archive should expose a seekable range")
        withExtendedLifetime(player) {}
    }
}
