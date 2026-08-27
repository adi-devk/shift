import XCTest
@testable import Shift

final class TorrentParserTests: XCTestCase {
    func testBencodeParser() throws {
        // String
        let strData = "4:spam".data(using: .utf8)!
        let parsedStr = try BencodeParser.parse(data: strData)
        XCTAssertEqual(parsedStr.stringValue, "spam")

        // Integer
        let intData = "i42e".data(using: .utf8)!
        let parsedInt = try BencodeParser.parse(data: intData)
        XCTAssertEqual(parsedInt.intValue, 42)

        // List
        let listData = "l4:spami42ee".data(using: .utf8)!
        let parsedList = try BencodeParser.parse(data: listData)
        XCTAssertEqual(parsedList.listValue?.count, 2)
        XCTAssertEqual(parsedList.listValue?[0].stringValue, "spam")
        XCTAssertEqual(parsedList.listValue?[1].intValue, 42)

        // Dictionary
        let dictData = "d3:bar4:spam3:fooi42ee".data(using: .utf8)!
        let parsedDict = try BencodeParser.parse(data: dictData)
        XCTAssertEqual(parsedDict.dictValue?["bar"]?.stringValue, "spam")
        XCTAssertEqual(parsedDict.dictValue?["foo"]?.intValue, 42)
    }

    func testMagnetLinkParser() {
        let magnet = "magnet:?xt=urn:btih:4a7e946a061b476e3c0f20d0f5ff27d2bf6d13ab&dn=Ubuntu+Desktop&tr=udp%3A%2F%2Ftracker.opentrackr.org%3A1337%2Fannounce"
        let meta = TorrentMeta.parseMagnetLink(magnet)

        XCTAssertNotNil(meta)
        XCTAssertEqual(meta?.infoHash, "4A7E946A061B476E3C0F20D0F5FF27D2BF6D13AB")
        XCTAssertEqual(meta?.displayName, "Ubuntu Desktop")
        XCTAssertEqual(meta?.trackers.count, 1)
        XCTAssertEqual(meta?.trackers.first, "udp://tracker.opentrackr.org:1337/announce")
    }
}
