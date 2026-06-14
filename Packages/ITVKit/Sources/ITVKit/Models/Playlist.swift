import Foundation

/// The parsed result of an M3U playlist: the EPG source plus channels and the
/// order their groups first appeared (used to order sidebar sections).
public struct Playlist: Sendable, Equatable {
    /// EPG XMLTV URL discovered from the `#EXTM3U url-tvg="…"` header, if present.
    public let epgURL: URL?
    public let channels: [Channel]
    /// Group titles in first-seen order.
    public let groupOrder: [String]

    public init(epgURL: URL?, channels: [Channel], groupOrder: [String]) {
        self.epgURL = epgURL
        self.channels = channels
        self.groupOrder = groupOrder
    }

    /// Channels for a given group, preserving playlist order.
    public func channels(in group: String) -> [Channel] {
        channels.filter { $0.groupTitle == group }
    }
}
