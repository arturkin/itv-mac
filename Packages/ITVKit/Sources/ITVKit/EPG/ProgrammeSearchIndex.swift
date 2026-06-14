import Foundation

/// Case- and diacritic-insensitive (Cyrillic-aware) search across channel names
/// and programme titles. Folded keys are computed once at build; search folds
/// the query and scans, ranking prefix matches above substring matches.
public struct ProgrammeSearchIndex: Sendable {
    public struct Hit: Sendable, Hashable, Identifiable {
        public enum Kind: Sendable, Hashable { case channel, programme }
        public let kind: Kind
        public let channelID: String
        public let title: String
        public let programme: Programme?

        public var id: String {
            switch kind {
            case .channel: return "ch:\(channelID)"
            case .programme: return "pg:\(programme?.id ?? channelID)"
            }
        }
    }

    private struct Entry: Sendable { let folded: String; let hit: Hit }
    private let entries: [Entry]

    public init(channels: [Channel], programmes: [Programme]) {
        var built: [Entry] = []
        built.reserveCapacity(channels.count + programmes.count)
        for c in channels {
            built.append(Entry(folded: Self.fold(c.name),
                               hit: Hit(kind: .channel, channelID: c.id, title: c.name, programme: nil)))
        }
        for p in programmes where !p.title.isEmpty {
            built.append(Entry(folded: Self.fold(p.title),
                               hit: Hit(kind: .programme, channelID: p.channelID, title: p.title, programme: p)))
        }
        self.entries = built
    }

    public func search(_ query: String, limit: Int = 50) -> [Hit] {
        let q = Self.fold(query)
        guard !q.isEmpty else { return [] }
        var prefix: [Hit] = []
        var substring: [Hit] = []
        for e in entries {
            if e.folded.hasPrefix(q) {
                prefix.append(e.hit)
                if prefix.count >= limit { break }
            } else if e.folded.contains(q) {
                substring.append(e.hit)
            }
        }
        return Array((prefix + substring).prefix(limit))
    }

    static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
                  locale: Locale(identifier: "ru_RU"))
    }
}
