import Foundation

/// Stable key for a resumable catch-up playback position.
public enum ResumeKey {
    public static func make(channelID: String, programmeStart: Date) -> String {
        "\(channelID)@\(Int(programmeStart.timeIntervalSince1970))"
    }
}

/// On-disk persistence for favorites and resume positions, as atomic JSON files.
/// An `actor` so it's safe to call from anywhere; corrupt files degrade to empty
/// defaults rather than throwing.
public actor PersistenceStore {
    private let favoritesURL: URL
    private let resumeURL: URL

    public init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        favoritesURL = directory.appendingPathComponent("favorites.json")
        resumeURL = directory.appendingPathComponent("resume.json")
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
