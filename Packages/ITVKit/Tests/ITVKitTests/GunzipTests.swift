import XCTest
@testable import ITVKit

final class GunzipTests: XCTestCase {
    func testInflatesSmallFixtureByteEqual() throws {
        let inflated = try Gunzip.inflate(Fixture.data("hello.txt.gz"))
        XCTAssertEqual(inflated, Fixture.data("hello.txt"))
    }

    func testInflatesXMLFixtureByteEqual() throws {
        let inflated = try Gunzip.inflate(Fixture.data("epg_sample.xml.gz"))
        XCTAssertEqual(inflated, Fixture.data("epg_sample.xml"))
    }

    func testInflatedXMLParsesEndToEnd() throws {
        let inflated = try Gunzip.inflate(Fixture.data("epg_sample.xml.gz"))
        let epg = try XMLTVParser.parse(inflated)
        XCTAssertEqual(epg.programmes.count, 3)
    }

    func testRejectsNonGzip() {
        XCTAssertThrowsError(try Gunzip.inflate(Data("not gzip at all, just text bytes here".utf8))) { error in
            XCTAssertEqual(error as? Gunzip.GunzipError, .notGzip)
        }
    }

    func testRejectsTruncated() {
        let full = [UInt8](Fixture.data("hello.txt.gz"))
        let truncated = Data(full.prefix(12)) // valid header, cut payload+trailer
        XCTAssertThrowsError(try Gunzip.inflate(truncated))
    }
}
