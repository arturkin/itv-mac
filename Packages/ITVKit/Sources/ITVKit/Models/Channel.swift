import Foundation

/// A single TV channel parsed from the M3U playlist.
///
/// Stream addressing is split out so `ArchiveURLBuilder` can construct live,
/// catch-up and in-progress URLs from `cdnBaseURL` + `token` without re-parsing.
public struct Channel: Identifiable, Hashable, Sendable, Codable {
    /// `tvg-id`, e.g. `"ch057"`. Matches the XMLTV `<channel id>`.
    public let id: String
    /// Display name (the text after the comma on the `#EXTINF` line).
    public let name: String
    /// `group-title`, e.g. `"Спорт"`.
    public let groupTitle: String
    /// `tvg-logo`.
    public let logoURL: URL?
    /// Full live master playlist URL including `?token=`, verbatim from the playlist.
    public let liveURL: URL
    /// `tvg-rec` — days of archive available. `0` means no catch-up.
    public let recDays: Int
    /// Directory URL that holds the stream's playlist files, e.g.
    /// `https://cloud02.03cdn.wf/ch057` (no trailing slash, no filename, no query).
    public let cdnBaseURL: URL
    /// Stream name segment, e.g. `"ch057"`.
    public let streamName: String
    /// The `token` query-parameter value, reused verbatim for archive requests.
    public let token: String

    public init(
        id: String,
        name: String,
        groupTitle: String,
        logoURL: URL?,
        liveURL: URL,
        recDays: Int,
        cdnBaseURL: URL,
        streamName: String,
        token: String
    ) {
        self.id = id
        self.name = name
        self.groupTitle = groupTitle
        self.logoURL = logoURL
        self.liveURL = liveURL
        self.recDays = recDays
        self.cdnBaseURL = cdnBaseURL
        self.streamName = streamName
        self.token = token
    }

    /// Whether this channel offers catch-up / archive playback.
    public var hasArchive: Bool { recDays > 0 }

    /// The valid catch-up window ending at `now`, or `nil` when there is no archive.
    public func archiveWindow(now: Date = Date()) -> ClosedRange<Date>? {
        guard recDays > 0 else { return nil }
        let start = now.addingTimeInterval(-Double(recDays) * 86_400)
        return start...now
    }
}
