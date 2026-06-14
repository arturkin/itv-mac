import Foundation

/// Fetches and parses an M3U playlist URL into a `Playlist`.
public struct PlaylistLoader: Sendable {
    private let fetcher: Fetcher

    public init(fetcher: Fetcher = URLSessionFetcher()) {
        self.fetcher = fetcher
    }

    public func load(from url: URL) async throws -> Playlist {
        let data = try await fetcher.data(from: url)
        return try M3UPlaylistParser.parse(String(decoding: data, as: UTF8.self))
    }
}
