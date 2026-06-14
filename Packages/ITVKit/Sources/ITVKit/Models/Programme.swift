import Foundation

/// A single EPG programme (one `<programme>` element from the XMLTV feed).
public struct Programme: Identifiable, Hashable, Sendable, Codable {
    /// Matches `Channel.id` / XMLTV `channel` attribute.
    public let channelID: String
    public let start: Date
    public let stop: Date
    public let title: String
    public let desc: String

    public init(channelID: String, start: Date, stop: Date, title: String, desc: String) {
        self.channelID = channelID
        self.start = start
        self.stop = stop
        self.title = title
        self.desc = desc
    }

    /// Stable identity: a programme is uniquely keyed by its channel + start second.
    public var id: String { "\(channelID)@\(Int(start.timeIntervalSince1970))" }

    public var duration: TimeInterval { stop.timeIntervalSince(start) }

    /// Whether `date` falls within `[start, stop)`.
    public func contains(_ date: Date) -> Bool {
        date >= start && date < stop
    }

    /// True once the programme has fully aired (eligible for bounded `archive-` playback).
    public func hasEnded(at now: Date = Date()) -> Bool { stop <= now }

    /// True while the programme is currently airing (eligible for `index-…-now` playback).
    public func isAiring(at now: Date = Date()) -> Bool { start <= now && now < stop }
}
