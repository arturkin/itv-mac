import Foundation

/// Parses XMLTV timestamps of the form `YYYYMMDDHHmmss ±HHMM`
/// (e.g. `20260614120000 +0300`) into absolute `Date`s.
///
/// Hand-rolled (no `DateFormatter`) for speed and thread-safety — the EPG can
/// contain hundreds of thousands of timestamps. A missing offset is treated as UTC.
public enum XMLTVDateParser {
    private static let utcCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    public static func date(from string: String) -> Date? {
        let bytes = Array(string.utf8)
        guard bytes.count >= 14 else { return nil }

        func digits(_ start: Int, _ count: Int) -> Int? {
            var value = 0
            for i in start..<(start + count) {
                let b = bytes[i]
                guard b >= 0x30, b <= 0x39 else { return nil }
                value = value * 10 + Int(b - 0x30)
            }
            return value
        }

        guard let year = digits(0, 4),
              let month = digits(4, 2),
              let day = digits(6, 2),
              let hour = digits(8, 2),
              let minute = digits(10, 2),
              let second = digits(12, 2) else { return nil }

        // Optional offset after position 14 (skip a leading space).
        var offsetSeconds = 0
        var i = 14
        while i < bytes.count, bytes[i] == 0x20 { i += 1 }
        if i < bytes.count, bytes[i] == 0x2B || bytes[i] == 0x2D { // + or -
            let sign = bytes[i] == 0x2D ? -1 : 1
            i += 1
            if let oh = digits(i, 2), let om = digits(i + 2, 2) {
                offsetSeconds = sign * (oh * 3600 + om * 60)
            }
        }

        var dc = DateComponents()
        dc.year = year; dc.month = month; dc.day = day
        dc.hour = hour; dc.minute = minute; dc.second = second
        dc.timeZone = TimeZone(secondsFromGMT: offsetSeconds)
        return utcCalendar.date(from: dc)
    }
}
