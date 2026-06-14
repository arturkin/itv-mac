import AVFoundation
import AVKit
import Observation
import ITVKit

/// Wraps a single `AVPlayer` and exposes observable playback state to SwiftUI.
///
/// Playback modes mirror the Flussonic variants (see DISCOVERY.md):
/// - live  → `index.m3u8` (sliding, "LIVE")
/// - past programme → `archive-<start>-<dur>.m3u8` (finite VOD, scrub = programme time, stops at boundary)
/// - in-progress → `index-<start>-now.m3u8` (EVENT)
@MainActor
@Observable
final class PlayerController {
    let player = AVPlayer()

    private(set) var channel: Channel?
    /// The programme being caught up on, or `nil` when watching live.
    private(set) var programme: Programme?
    private(set) var isLive = true
    private(set) var statusMessage: String?

    /// Audio / subtitle options for the current item (populated when ready).
    private(set) var audioOptions: [TrackOption] = []
    private(set) var subtitleOptions: [TrackOption] = []

    var onPlaybackStarted: ((Channel, Programme?) -> Void)?
    var resumeLookup: ((Channel, Programme) -> Double?)?
    var onProgress: ((Channel, Programme, Double) -> Void)?
    var onPlaybackFailed: ((Channel, Programme?) -> Void)?
    private var currentLoadFailureHandled = false

    private var statusObservation: NSKeyValueObservation?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var pendingResume: Double?

    init() {
        player.allowsExternalPlayback = false
        addPeriodicObserver()
    }

    // MARK: - Public playback API

    func playLive(_ channel: Channel) {
        self.channel = channel
        self.programme = nil
        self.isLive = true
        self.statusMessage = nil
        pendingResume = nil
        load(url: ArchiveURLBuilder.liveURL(for: channel))
        onPlaybackStarted?(channel, nil)
    }

    /// Plays a programme as catch-up. Returns false if it isn't playable
    /// (no archive / outside window / future).
    @discardableResult
    func playCatchUp(_ channel: Channel, programme: Programme, now: Date = Date()) -> Bool {
        guard let mode = ArchiveURLBuilder.mode(for: channel, programme: programme, now: now),
              let url = ArchiveURLBuilder.catchUpURL(for: channel, programme: programme, now: now) else {
            return false
        }
        self.channel = channel
        self.programme = programme
        self.isLive = (mode == .live)
        self.statusMessage = nil
        pendingResume = resumeLookup?(channel, programme)
        load(url: url)
        onPlaybackStarted?(channel, programme)
        return true
    }

    func jumpToLive() {
        guard let channel else { return }
        playLive(channel)
    }

    func togglePlayPause() {
        player.timeControlStatus == .paused ? player.play() : player.pause()
    }

    func select(_ option: TrackOption) {
        guard let item = player.currentItem else { return }
        Task { @MainActor in
            guard let group = try? await item.asset.loadMediaSelectionGroup(for: option.characteristic) else { return }
            let match = group.options.first { $0.displayName == option.name }
            item.select(match, in: group)
        }
    }

    // MARK: - Item loading

    private func load(url: URL) {
        statusObservation?.invalidate()
        currentLoadFailureHandled = false
        let item = AVPlayerItem(url: url)
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in self?.handleStatusChange(item) }
        }
        installEndObserver(for: item)
        player.replaceCurrentItem(with: item)
        player.play()
    }

    private func handleStatusChange(_ item: AVPlayerItem) {
        switch item.status {
        case .readyToPlay:
            statusMessage = nil
            if let resume = pendingResume, resume > 1 {
                player.seek(to: CMTime(seconds: resume, preferredTimescale: 600))
                pendingResume = nil
            }
            Task { @MainActor in await self.loadTrackOptions(item) }
        case .failed:
            statusMessage = item.error?.localizedDescription ?? "Playback failed."
            if !currentLoadFailureHandled, let channel {
                currentLoadFailureHandled = true
                onPlaybackFailed?(channel, programme)
            }
        default:
            break
        }
    }

    private func loadTrackOptions(_ item: AVPlayerItem) async {
        audioOptions = await options(for: .audible, in: item)
        subtitleOptions = await options(for: .legible, in: item)
    }

    private func options(for characteristic: AVMediaCharacteristic, in item: AVPlayerItem) async -> [TrackOption] {
        guard let group = try? await item.asset.loadMediaSelectionGroup(for: characteristic) else { return [] }
        return group.options.map { TrackOption(name: $0.displayName, characteristic: characteristic) }
    }

    // MARK: - Observers

    private func addPeriodicObserver() {
        let interval = CMTime(seconds: 5, preferredTimescale: 1)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            // Hop to the main actor; AVKit calls back on the main queue but the
            // closure isn't statically isolated.
            MainActor.assumeIsolated {
                guard let self, let channel = self.channel, let programme = self.programme, !self.isLive else { return }
                let seconds = time.seconds
                if seconds.isFinite, seconds > 0 { self.onProgress?(channel, programme, seconds) }
            }
        }
    }

    private func installEndObserver(for item: AVPlayerItem) {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.statusMessage = nil // programme finished; UI may auto-advance later
            }
        }
    }

}

/// A selectable audio or subtitle track.
struct TrackOption: Identifiable, Hashable {
    let name: String
    let characteristic: AVMediaCharacteristic
    var id: String { "\(characteristic.rawValue):\(name)" }
}
