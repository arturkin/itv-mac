import XCTest
@testable import ITVKit

final class XMLTVDateParserTests: XCTestCase {
    private func utcDate(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s))!
    }

    func testParsesPositiveOffset() {
        // 12:00 +0300 == 09:00 UTC
        XCTAssertEqual(XMLTVDateParser.date(from: "20260614120000 +0300"), utcDate(2026, 6, 14, 9, 0, 0))
    }

    func testParsesZeroOffset() {
        XCTAssertEqual(XMLTVDateParser.date(from: "20260614120000 +0000"), utcDate(2026, 6, 14, 12, 0, 0))
    }

    func testParsesNegativeOffset() {
        // 12:00 -0500 == 17:00 UTC
        XCTAssertEqual(XMLTVDateParser.date(from: "20260614120000 -0500"), utcDate(2026, 6, 14, 17, 0, 0))
    }

    func testMissingOffsetTreatedAsUTC() {
        XCTAssertEqual(XMLTVDateParser.date(from: "20260614120000"), utcDate(2026, 6, 14, 12, 0, 0))
    }

    func testHalfHourOffset() {
        // 12:00 +0530 == 06:30 UTC
        XCTAssertEqual(XMLTVDateParser.date(from: "20260614120000 +0530"), utcDate(2026, 6, 14, 6, 30, 0))
    }

    func testRejectsGarbage() {
        XCTAssertNil(XMLTVDateParser.date(from: "not-a-date"))
        XCTAssertNil(XMLTVDateParser.date(from: "2026"))
        XCTAssertNil(XMLTVDateParser.date(from: "2026XX14120000 +0300"))
    }
}
