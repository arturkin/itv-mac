import Foundation
import CryptoKit

/// An immutable EPG snapshot ready for the UI: a time index plus a search index.
public struct EPGSnapshot: Sendable {
    public let index: EPGIndex
    public let search: ProgrammeSearchIndex
    public let builtAt: Date

    public init(index: EPGIndex, search: ProgrammeSearchIndex, builtAt: Date) {
        self.index = index
        self.search = search
        self.builtAt = builtAt
    }
}

public enum EPGStoreError: Error, Equatable { case noEPGURL }

/// Loads the EPG for a playlist: fetch gzipped XMLTV → gunzip → parse (filtered
/// to the playlist's channels) → build indexes. Caches the raw `.gz` on disk and
/// reuses it while fresh; on a fetch failure it falls back to stale cache.
public actor EPGStore {
    private let fetcher: Fetcher
    private let cacheDirectory: URL
    private let maxAge: TimeInterval

    public init(fetcher: Fetcher = URLSessionFetcher(),
                cacheDirectory: URL,
                maxAge: TimeInterval = 6 * 3600) {
        self.fetcher = fetcher
        self.cacheDirectory = cacheDirectory
        self.maxAge = maxAge
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    public func snapshot(for playlist: Playlist, now: Date = Date(), forceRefresh: Bool = false) async throws -> EPGSnapshot {
        guard let epgURL = playlist.epgURL else { throw EPGStoreError.noEPGURL }
        let cacheFile = cacheURL(for: epgURL)

        let gz: Data
        if !forceRefresh, let cached = freshCache(cacheFile, now: now) {
            gz = cached
        } else {
            do {
                let fetched = try await fetcher.data(from: epgURL)
                writeCache(fetched, to: cacheFile)
                gz = fetched
            } catch {
                if let stale = try? Data(contentsOf: cacheFile) {
                    gz = stale // degrade to stale cache rather than failing
                } else {
                    throw error
                }
            }
        }

        let xml = try Gunzip.inflate(gz)
        let ids = Set(playlist.channels.map(\.id))
        let epg = try XMLTVParser.parse(xml, channelIDs: ids)
        let index = EPGIndex(programmes: epg.programmes, channelNames: epg.channelNames)
        let search = ProgrammeSearchIndex(channels: playlist.channels, programmes: epg.programmes)
        return EPGSnapshot(index: index, search: search, builtAt: now)
    }

    // MARK: - Cache

    private func cacheURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        return cacheDirectory.appendingPathComponent("epg-\(name).xml.gz")
    }

    private func freshCache(_ file: URL, now: Date) -> Data? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
              let modified = attrs[.modificationDate] as? Date,
              now.timeIntervalSince(modified) <= maxAge,
              let data = try? Data(contentsOf: file) else { return nil }
        return data
    }

    private func writeCache(_ data: Data, to file: URL) {
        try? data.write(to: file, options: .atomic)
    }
}
