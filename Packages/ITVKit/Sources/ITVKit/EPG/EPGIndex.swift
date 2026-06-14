import Foundation

/// Immutable, `Sendable` snapshot of the EPG, indexed per channel and sorted by
/// start time for O(log n) now/next and range queries. Built off-main and
/// published to the main actor without locks.
public struct EPGIndex: Sendable {
    public let channelNames: [String: String]
    private let byChannel: [String: [Programme]] // each sorted ascending by start

    public init(programmes: [Programme], channelNames: [String: String] = [:]) {
        var dict: [String: [Programme]] = [:]
        for p in programmes { dict[p.channelID, default: []].append(p) }
        for key in dict.keys { dict[key]!.sort { $0.start < $1.start } }
        self.byChannel = dict
        self.channelNames = channelNames
    }

    public var isEmpty: Bool { byChannel.isEmpty }
    public var programmeCount: Int { byChannel.values.reduce(0) { $0 + $1.count } }

    /// All programmes for a channel, ascending by start.
    public func programmes(for channelID: String) -> [Programme] { byChannel[channelID] ?? [] }

    /// The programme airing at `date`, if any (handles gaps with no coverage).
    public func programme(channelID: String, at date: Date) -> Programme? {
        let list = byChannel[channelID] ?? []
        guard !list.isEmpty else { return nil }
        // Largest index whose start <= date.
        var lo = 0, hi = list.count - 1, found = -1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if list[mid].start <= date { found = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        guard found >= 0 else { return nil }
        let candidate = list[found]
        return candidate.contains(date) ? candidate : nil
    }

    /// The currently-airing and immediately-following programmes.
    public func nowNext(channelID: String, at date: Date) -> (now: Programme?, next: Programme?) {
        let list = byChannel[channelID] ?? []
        guard !list.isEmpty else { return (nil, nil) }
        // First index whose start > date.
        var lo = 0, hi = list.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if list[mid].start <= date { lo = mid + 1 } else { hi = mid }
        }
        let now: Programme? = (lo > 0 && list[lo - 1].contains(date)) ? list[lo - 1] : nil
        let next: Programme? = lo < list.count ? list[lo] : nil
        return (now, next)
    }

    /// Programmes overlapping `range`, ascending by start.
    public func programmes(channelID: String, in range: ClosedRange<Date>) -> [Programme] {
        (byChannel[channelID] ?? []).filter { $0.stop > range.lowerBound && $0.start < range.upperBound }
    }

    /// Overall coverage `[min start, max stop]` across all channels.
    public var bounds: ClosedRange<Date>? {
        var minStart: Date?
        var maxStop: Date?
        for list in byChannel.values {
            if let first = list.first { minStart = min(minStart ?? first.start, first.start) }
            if let last = list.max(by: { $0.stop < $1.stop }) { maxStop = max(maxStop ?? last.stop, last.stop) }
        }
        guard let lo = minStart, let hi = maxStop, lo <= hi else { return nil }
        return lo...hi
    }
}
