import Foundation

/// Builds Flussonic playback URLs from a `Channel`'s stream addressing.
///
/// All URLs share the live URL's host/path/`token`; only the filename changes.
/// Timestamps are integer UTC seconds (`timeIntervalSince1970`), so they are
/// independent of how the EPG prints its timezone offset.
public enum ArchiveURLBuilder {

    /// The playback mode chosen for a programme.
    public enum Mode: Equatable, Sendable {
        case live
        /// Bounded VOD clip: `archive-<start>-<duration>.m3u8` (finite, seekable, stops at boundary).
        case archive(start: Int, duration: Int)
        /// Append-only EVENT for a currently-airing programme: `index-<start>-now.m3u8`.
        case inProgress(start: Int)
    }

    public static func liveURL(for channel: Channel) -> URL { channel.liveURL }

    public static func archiveClipURL(for channel: Channel, start: Date, durationSeconds: Int) -> URL {
        url(for: channel, filename: "archive-\(unix(start))-\(max(1, durationSeconds)).m3u8")
    }

    public static func inProgressURL(for channel: Channel, start: Date) -> URL {
        url(for: channel, filename: "index-\(unix(start))-now.m3u8")
    }

    /// Fallback path (kept for robustness; not used as primary — see DISCOVERY.md).
    public static func timeshiftAbsURL(for channel: Channel, at date: Date) -> URL {
        url(for: channel, filename: "timeshift_abs-\(unix(date)).m3u8")
    }

    // MARK: - Time-shift (EPG-independent)

    /// Clamps an absolute instant into the channel's archive window
    /// `[now - recDays·86400, now)`. Returns `nil` when the channel has no
    /// archive, or when `date` is at/after `now` (the caller should go live).
    /// This is the core of seeking purely by time, with no EPG data.
    public static func clampToArchiveWindow(_ date: Date, recDays: Int, now: Date = Date()) -> Date? {
        guard recDays > 0 else { return nil }
        guard date < now else { return nil }
        let windowStart = now.addingTimeInterval(-Double(recDays) * 86_400)
        return max(date, windowStart)
    }

    /// A continuous "play from this past instant up to the live edge" URL,
    /// built without any EPG. Uses the growing EVENT playlist
    /// (`index-<startUnix>-now.m3u8`) so the native scrubber covers `[date, now]`.
    /// Returns `nil` if the channel has no archive or `date` is not in the past.
    public static func timeShiftURL(for channel: Channel, to date: Date, now: Date = Date()) -> URL? {
        guard let start = clampToArchiveWindow(date, recDays: channel.recDays, now: now) else { return nil }
        return inProgressURL(for: channel, start: start)
    }

    /// Picks the right mode + URL to catch up on `programme`, clamped to the
    /// channel's archive window. Returns `nil` when the programme isn't playable
    /// as catch-up (no archive, fully outside the window, or entirely in the future).
    public static func catchUpURL(for channel: Channel, programme: Programme, now: Date = Date()) -> URL? {
        guard let mode = mode(for: channel, programme: programme, now: now) else { return nil }
        switch mode {
        case .live:
            return liveURL(for: channel)
        case let .archive(start, duration):
            return url(for: channel, filename: "archive-\(start)-\(duration).m3u8")
        case let .inProgress(start):
            return url(for: channel, filename: "index-\(start)-now.m3u8")
        }
    }

    /// The playback mode for a programme without building the URL (handy for the UI
    /// to decide live-vs-catch-up affordances and for tests).
    public static func mode(for channel: Channel, programme: Programme, now: Date = Date()) -> Mode? {
        guard let (start, stop) = clamp(start: programme.start, stop: programme.stop, recDays: channel.recDays, now: now) else {
            return nil
        }
        if programme.stop <= now {
            return .archive(start: unix(start), duration: max(1, unix(stop) - unix(start)))
        } else if programme.start <= now {
            return .inProgress(start: unix(start))
        } else {
            return nil // future programme
        }
    }

    /// Clamps `[start, stop]` into the archive window `[now - recDays·86400, now]`.
    /// Returns `nil` if the channel has no archive or the interval lies fully outside it.
    public static func clamp(start: Date, stop: Date, recDays: Int, now: Date) -> (start: Date, stop: Date)? {
        guard recDays > 0 else { return nil }
        let windowStart = now.addingTimeInterval(-Double(recDays) * 86_400)
        let clampedStart = max(start, windowStart)
        let clampedStop = min(stop, now)
        guard clampedStart < clampedStop else { return nil }
        return (clampedStart, clampedStop)
    }

    // MARK: - Private

    private static func unix(_ date: Date) -> Int { Int(date.timeIntervalSince1970.rounded(.down)) }

    private static func url(for channel: Channel, filename: String) -> URL {
        var comps = URLComponents(url: channel.cdnBaseURL.appendingPathComponent(filename), resolvingAgainstBaseURL: false)!
        if !channel.token.isEmpty {
            comps.queryItems = [URLQueryItem(name: "token", value: channel.token)]
        }
        return comps.url!
    }
}
