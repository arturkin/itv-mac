import AVFoundation
import AVKit
import CoreVideo
import QuartzCore
import Observation
import ITVKit

/// Wraps a single `AVPlayer` and exposes observable playback state to SwiftUI.
///
/// Playback modes mirror the Flussonic variants (see DISCOVERY.md):
/// - live  → `index.m3u8` (sliding, "LIVE")
/// - past programme → `archive-<start>-<dur>.m3u8` (finite VOD, scrub = programme time, stops at boundary)
/// - in-progress / time-shift → `index-<start>-now.m3u8` (EVENT, continuous from a past instant to live)
@MainActor
@Observable
final class PlayerController {
    let player = AVPlayer()

    private(set) var channel: Channel?
    /// The programme being caught up on, or `nil` when watching live / time-shifting.
    private(set) var programme: Programme?
    private(set) var isLive = true
    private(set) var statusMessage: String?

    /// Absolute wall-clock instant the current time-shift stream begins, or `nil`
    /// when watching live. Used to seek purely by time, with no EPG (see `stepBackward`).
    private(set) var timeShiftAnchor: Date?

    /// True while the stream is mirroring to an AirPlay device (e.g. the TV).
    private(set) var isExternalPlaybackActive = false

    /// True when the item is playing audio but its video can't be decoded by this
    /// Mac (unsupported codec) — surfaced so the UI can suggest AirPlay to the TV.
    private(set) var videoUnavailable = false

    /// Audio / subtitle options for the current item (populated when ready).
    private(set) var audioOptions: [TrackOption] = []
    private(set) var subtitleOptions: [TrackOption] = []

    var onPlaybackStarted: ((Channel, Programme?) -> Void)?
    var resumeLookup: ((Channel, Programme) -> Double?)?
    var onProgress: ((Channel, Programme, Double) -> Void)?
    var onPlaybackFailed: ((Channel, Programme?) -> Void)?
    private var currentLoadFailureHandled = false

    private var statusObservation: NSKeyValueObservation?
    private var externalPlaybackObservation: NSKeyValueObservation?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var pendingResume: Double?

    // Best-effort "is video actually decoding?" detection.
    private var videoOutput: AVPlayerItemVideoOutput?
    private var videoCheckTask: Task<Void, Never>?

    /// Default time-shift step (seek by time without relying on EPG data).
    static let defaultSeekInterval: TimeInterval = 30 * 60

    init() {
        // AirPlay: let AVKit mirror playback to an external device (the TV). The
        // route picker in the UI and the AVPlayerView controls both drive this.
        player.allowsExternalPlayback = true
        // Start rendering as soon as the first frames arrive rather than buffering
        // a large cushion first — high-bitrate live channels otherwise show audio
        // for 10+ seconds before any picture.
        player.automaticallyWaitsToMinimizeStalling = false
        addPeriodicObserver()
        observeExternalPlayback()
    }

    // MARK: - Public playback API

    func playLive(_ channel: Channel) {
        self.channel = channel
        self.programme = nil
        self.isLive = true
        self.timeShiftAnchor = nil
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
        self.timeShiftAnchor = nil
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

    // MARK: - Time-shift (seek by time, EPG-independent)

    /// Whether the current channel supports seeking back in time at all.
    var canTimeShift: Bool { channel?.hasArchive == true }

    /// The absolute instant currently being shown, or `nil` while live.
    var currentAbsoluteDate: Date? {
        guard let anchor = timeShiftAnchor else { return nil }
        let offset = player.currentTime().seconds
        guard offset.isFinite, offset >= 0 else { return anchor }
        return anchor.addingTimeInterval(offset)
    }

    /// How far behind the live edge we currently are, in seconds (0 while live).
    var secondsBehindLive: TimeInterval {
        guard let current = currentAbsoluteDate else { return 0 }
        return max(0, Date().timeIntervalSince(current))
    }

    /// Jump back by `interval` from the current position. Reloads the stream only
    /// when the target is earlier than what's already buffered; otherwise an
    /// instant seek. Works on any archive channel without EPG data.
    func stepBackward(by interval: TimeInterval = defaultSeekInterval) {
        guard let channel, channel.hasArchive else { return }
        let now = Date()
        let currentAbs = currentAbsoluteDate ?? now
        let target = currentAbs.addingTimeInterval(-interval)
        if let anchor = timeShiftAnchor, target >= anchor {
            seekWithinTimeShift(to: target)
        } else {
            timeShift(to: target, channel: channel, now: now)
        }
    }

    /// Jump forward by `interval`. Returns to live once it reaches the live edge.
    func stepForward(by interval: TimeInterval = defaultSeekInterval) {
        guard let channel, let _ = timeShiftAnchor else { return }
        let now = Date()
        let currentAbs = currentAbsoluteDate ?? now
        let target = currentAbs.addingTimeInterval(interval)
        // Within ~30s of live → just go live (the EVENT stream's tail is the live edge).
        if target >= now.addingTimeInterval(-30) {
            playLive(channel)
        } else {
            seekWithinTimeShift(to: target)
        }
    }

    /// Load a fresh time-shift stream beginning at `target` (clamped to the window).
    private func timeShift(to target: Date, channel: Channel, now: Date) {
        guard let start = ArchiveURLBuilder.clampToArchiveWindow(target, recDays: channel.recDays, now: now),
              let url = ArchiveURLBuilder.timeShiftURL(for: channel, to: target, now: now) else {
            playLive(channel)
            return
        }
        self.channel = channel
        self.programme = nil
        self.isLive = false
        self.timeShiftAnchor = start
        self.statusMessage = nil
        pendingResume = nil
        load(url: url)
        onPlaybackStarted?(channel, nil)
    }

    /// Seek inside the already-loaded time-shift stream (instant, no reload).
    private func seekWithinTimeShift(to target: Date) {
        guard let anchor = timeShiftAnchor else { return }
        let offset = max(0, target.timeIntervalSince(anchor))
        player.seek(to: CMTime(seconds: offset, preferredTimescale: 600),
                    toleranceBefore: .zero,
                    toleranceAfter: CMTime(seconds: 2, preferredTimescale: 600))
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
        resetVideoDetection()
        let item = AVPlayerItem(url: url)
        // Attach an offscreen video output so we can tell whether video actually
        // decodes on this Mac (some channels carry a codec VideoToolbox can't play).
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        item.add(output)
        videoOutput = output
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
            // Begin playback immediately rather than pre-buffering — cuts the
            // "audio only for 10s" startup gap on high-bitrate channels.
            player.playImmediately(atRate: 1.0)
            if let resume = pendingResume, resume > 1 {
                player.seek(to: CMTime(seconds: resume, preferredTimescale: 600))
                pendingResume = nil
            }
            startVideoDetection()
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

    // MARK: - Video-decode detection

    private func resetVideoDetection() {
        videoCheckTask?.cancel()
        videoCheckTask = nil
        if let output = videoOutput, let item = player.currentItem { item.remove(output) }
        videoOutput = nil
        videoUnavailable = false
    }

    /// Polls the offscreen output: if a real frame ever decodes, video works and
    /// the flag stays clear. If the item plays audio with no decoded frame for a
    /// generous window, flag it (so the UI can suggest AirPlay to the TV).
    private func startVideoDetection() {
        videoCheckTask?.cancel()
        videoCheckTask = Task { @MainActor [weak self] in
            let startedAt = CACurrentMediaTime()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard let self, let output = self.videoOutput, let item = self.player.currentItem else { return }
                let hostTime = CACurrentMediaTime()
                let elapsed = hostTime - startedAt
                let t = output.itemTime(forHostTime: hostTime)
                if output.hasNewPixelBuffer(forItemTime: t) {
                    self.videoUnavailable = false
                    if let out = self.videoOutput { item.remove(out); self.videoOutput = nil }
                    return // video decodes fine — done
                }
                let playing = self.player.timeControlStatus == .playing
                let hasVideoTrack = item.tracks.contains { $0.assetTrack?.mediaType == .video }
                if playing && !hasVideoTrack && elapsed > 4 {
                    self.videoUnavailable = true // audio-only feed: flag promptly
                } else if playing && elapsed > 20 {
                    self.videoUnavailable = true // track present but never decodes
                }
                if elapsed > 40 { // bound the work; keep whatever verdict we reached
                    if let out = self.videoOutput { item.remove(out); self.videoOutput = nil }
                    return
                }
            }
        }
    }

    // MARK: - Observers

    private func observeExternalPlayback() {
        externalPlaybackObservation = player.observe(\.isExternalPlaybackActive, options: [.new, .initial]) { [weak self] player, _ in
            Task { @MainActor in self?.isExternalPlaybackActive = player.isExternalPlaybackActive }
        }
    }

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
