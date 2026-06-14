import Foundation

/// Parsed XMLTV payload: channel display-names plus all programmes.
public struct EPGData: Sendable, Equatable {
    public let channelNames: [String: String]
    public let programmes: [Programme]

    public init(channelNames: [String: String], programmes: [Programme]) {
        self.channelNames = channelNames
        self.programmes = programmes
    }
}

public enum XMLTVParseError: Error { case malformed }

/// Streaming (SAX) XMLTV parser. Never builds a DOM, so it copes with the
/// multi-hundred-megabyte decompressed feed.
public enum XMLTVParser {
    /// Parses XMLTV. When `channelIDs` is non-nil, only channels/programmes whose
    /// id is in the set are kept — used to discard the ~800 EPG channels not in
    /// the user's playlist, cutting the in-memory programme count by ~5×.
    public static func parse(_ data: Data, channelIDs: Set<String>? = nil) throws -> EPGData {
        let delegate = Delegate(channelIDs: channelIDs)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw XMLTVParseError.malformed }
        return EPGData(channelNames: delegate.channelNames, programmes: delegate.programmes)
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        let channelIDs: Set<String>?
        var channelNames: [String: String] = [:]
        var programmes: [Programme] = []

        init(channelIDs: Set<String>?) { self.channelIDs = channelIDs }

        private func wanted(_ id: String?) -> Bool {
            guard let filter = channelIDs else { return true }
            guard let id else { return false }
            return filter.contains(id)
        }

        // current channel element
        private var currentChannelID: String?
        private var displayName = ""
        private var capturingDisplayName = false

        // current programme element
        private var progChannel: String?
        private var progStart: Date?
        private var progStop: Date?
        private var title = ""
        private var desc = ""
        private enum Field { case none, title, desc, displayName }
        private var field: Field = .none

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes attributeDict: [String: String]) {
            switch elementName {
            case "channel":
                currentChannelID = attributeDict["id"]
                displayName = ""
            case "display-name":
                capturingDisplayName = true
                field = .displayName
            case "programme":
                progChannel = attributeDict["channel"]
                progStart = attributeDict["start"].flatMap(XMLTVDateParser.date(from:))
                progStop = attributeDict["stop"].flatMap(XMLTVDateParser.date(from:))
                title = ""; desc = ""
            case "title":
                field = .title
            case "desc":
                field = .desc
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            append(string)
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            if let s = String(data: CDATABlock, encoding: .utf8) { append(s) }
        }

        private func append(_ s: String) {
            switch field {
            case .title: title += s
            case .desc: desc += s
            case .displayName where capturingDisplayName: displayName += s
            default: break
            }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
            switch elementName {
            case "display-name":
                if let id = currentChannelID, wanted(id), channelNames[id] == nil {
                    channelNames[id] = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                capturingDisplayName = false
                field = .none
            case "channel":
                currentChannelID = nil
            case "title", "desc":
                field = .none
            case "programme":
                if let ch = progChannel, wanted(ch), let start = progStart, let stop = progStop {
                    programmes.append(Programme(
                        channelID: ch,
                        start: start,
                        stop: stop,
                        title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                        desc: desc.trimmingCharacters(in: .whitespacesAndNewlines)
                    ))
                }
                progChannel = nil; progStart = nil; progStop = nil
            default:
                break
            }
        }
    }
}
