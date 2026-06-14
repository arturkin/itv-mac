import Foundation

public enum M3UParseError: Error, Equatable {
    case notAPlaylist
}

/// Parses an itv.live M3U playlist into a `Playlist`.
///
/// Tolerant of the quirks observed on the live service: CRLF line endings,
/// extra spaces before attributes, optional `#EXTGRP`, and missing `tvg-rec`.
public enum M3UPlaylistParser {
    public static func parse(_ text: String) throws -> Playlist {
        // Normalise CRLF and split.
        let lines = text.replacingOccurrences(of: "\r", with: "").split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var idx = 0
        // Header — must be #EXTM3U.
        while idx < lines.count, lines[idx].trimmingCharacters(in: .whitespaces).isEmpty { idx += 1 }
        guard idx < lines.count, lines[idx].hasPrefix("#EXTM3U") else { throw M3UParseError.notAPlaylist }
        let epgURL = attribute("url-tvg", in: lines[idx]).flatMap(URL.init(string:))
            ?? attribute("x-tvg-url", in: lines[idx]).flatMap(URL.init(string:))
        idx += 1

        var channels: [Channel] = []
        var groupOrder: [String] = []
        var seenGroups = Set<String>()

        var pendingExtinf: String?
        while idx < lines.count {
            let line = lines[idx]
            idx += 1
            if line.hasPrefix("#EXTINF") {
                pendingExtinf = line
            } else if line.hasPrefix("#") {
                continue // #EXTGRP and other directives — group-title attr is authoritative
            } else {
                let urlString = line.trimmingCharacters(in: .whitespaces)
                guard !urlString.isEmpty, let extinf = pendingExtinf else { continue }
                pendingExtinf = nil
                if let channel = makeChannel(extinf: extinf, urlString: urlString) {
                    channels.append(channel)
                    if seenGroups.insert(channel.groupTitle).inserted {
                        groupOrder.append(channel.groupTitle)
                    }
                }
            }
        }
        return Playlist(epgURL: epgURL, channels: channels, groupOrder: groupOrder)
    }

    // MARK: - Per-channel

    private static func makeChannel(extinf: String, urlString: String) -> Channel? {
        guard let liveURL = URL(string: urlString) else { return nil }
        let id = attribute("tvg-id", in: extinf) ?? ""
        let recDays = attribute("tvg-rec", in: extinf).flatMap { Int($0) } ?? 0
        let logoURL = attribute("tvg-logo", in: extinf).flatMap(URL.init(string:))
        let group = attribute("group-title", in: extinf) ?? ""
        let name = displayName(from: extinf)

        guard let (base, stream, token) = decompose(liveURL) else { return nil }

        return Channel(
            id: id.isEmpty ? stream : id,
            name: name.isEmpty ? (id.isEmpty ? stream : id) : name,
            groupTitle: group,
            logoURL: logoURL,
            liveURL: liveURL,
            recDays: recDays,
            cdnBaseURL: base,
            streamName: stream,
            token: token
        )
    }

    /// Splits a live URL like `https://cloud02.03cdn.wf/ch057/index.m3u8?token=…`
    /// into (`https://cloud02.03cdn.wf/ch057`, `ch057`, `token`).
    static func decompose(_ url: URL) -> (base: URL, stream: String, token: String)? {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let token = comps.queryItems?.first(where: { $0.name == "token" })?.value ?? ""
        comps.query = nil
        // path = /ch057/index.m3u8  → drop last component
        let full = comps.path
        guard let lastSlash = full.lastIndex(of: "/") else { return nil }
        let dirPath = String(full[full.startIndex..<lastSlash]) // /ch057
        let stream = dirPath.split(separator: "/").last.map(String.init) ?? ""
        comps.path = dirPath
        guard let base = comps.url else { return nil }
        return (base, stream, token)
    }

    // MARK: - EXTINF helpers

    /// Extracts `key="value"` from an `#EXTINF` (or `#EXTM3U`) line.
    static func attribute(_ key: String, in line: String) -> String? {
        guard let keyRange = line.range(of: "\(key)=\"") else { return nil }
        let afterKey = keyRange.upperBound
        guard let closing = line[afterKey...].firstIndex(of: "\"") else { return nil }
        return String(line[afterKey..<closing])
    }

    /// The display name = text after the first unquoted comma on the `#EXTINF` line.
    static func displayName(from extinf: String) -> String {
        var inQuotes = false
        for i in extinf.indices {
            let ch = extinf[i]
            if ch == "\"" { inQuotes.toggle() }
            else if ch == "," && !inQuotes {
                let name = extinf[extinf.index(after: i)...]
                return name.trimmingCharacters(in: .whitespaces)
            }
        }
        return ""
    }
}
