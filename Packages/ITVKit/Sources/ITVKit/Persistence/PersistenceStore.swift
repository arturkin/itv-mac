import Foundation

/// A recently-watched entry. `programmeStart == nil` means it was watched live.
public struct RecentItem: Codable, Sendable, Hashable, Identifiable {
    public let channelID: String
    public let programmeStart: Date?
    public let title: String
    public let lastPlayed: Date

    public init(channelID: String, programmeStart: Date?, title: String, lastPlayed: Date) {
        self.channelID = channelID
        self.programmeStart = programmeStart
        self.title = title
        self.lastPlayed = lastPlayed
    }

    public var id: String {
        "\(channelID)@\(programmeStart.map { Int($0.timeIntervalSince1970) } ?? -1)"
    }
}

/// Stable key for a resumable catch-up playback position.
public enum ResumeKey {
    public static func make(channelID: String, programmeStart: Date) -> String {
        "\(channelID)@\(Int(programmeStart.timeIntervalSince1970))"
    }
}

/// On-disk persistence for favorites, resume positions and recently-watched,
/// as atomic JSON files. An `actor` so it's safe to call from anywhere; corrupt
/// files degrade to empty defaults rather than throwing.
public actor PersistenceStore {
    private let favoritesURL: URL
    private let resumeURL: URL
    private let recentsURL: URL
    private let recentsLimit: Int

    public init(directory: URL, recentsLimit: Int = 50) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        favoritesURL = directory.appendingPathComponent("favorites.json")
        resumeURL = directory.appendingPathComponent("resume.json")
        recentsURL = directory.appendingPathComponent("recents.json")
        self.recentsLimit = recentsLimit
    }

    // MARK: Favorites (ordered channel IDs)

    public func loadFavorites() -> [String] { decode([String].self, favoritesURL) ?? [] }
    public func saveFavorites(_ ids: [String]) { encode(ids, favoritesURL) }

    // MARK: Resume positions (key -> seconds)

    public func loadResume() -> [String: Double] { decode([String: Double].self, resumeURL) ?? [:] }

    public func setResume(key: String, seconds: Double) {
        var map = loadResume()
        map[key] = seconds
        encode(map, resumeURL)
    }

    public func resume(forKey key: String) -> Double? { loadResume()[key] }

    public func clearResume(key: String) {
        var map = loadResume()
        map[key] = nil
        encode(map, resumeURL)
    }

    // MARK: Recently watched (most-recent first, deduped, capped)

    public func loadRecents() -> [RecentItem] { decode([RecentItem].self, recentsURL) ?? [] }

    public func addRecent(_ item: RecentItem) {
        var items = loadRecents().filter { $0.id != item.id }
        items.insert(item, at: 0)
        if items.count > recentsLimit { items = Array(items.prefix(recentsLimit)) }
        encode(items, recentsURL)
    }

    // MARK: - JSON helpers

    private func decode<T: Decodable>(_ type: T.Type, _ url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data) // corrupt → nil (graceful default)
    }

    private func encode<T: Encodable>(_ value: T, _ url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
