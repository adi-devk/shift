import XCTest
@testable import Shift

final class HLSParserTests: XCTestCase {
    func testMasterPlaylistParsing() {
        let m3u8 = """
        #EXTM3U
        #EXT-X-VERSION:3
        #EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360,CODECS="avc1.4d401e,mp4a.40.2"
        360p/playlist.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=2500000,RESOLUTION=1280x720,CODECS="avc1.4d401f,mp4a.40.2"
        720p/playlist.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080,CODECS="avc1.4d4028,mp4a.40.2"
        1080p/playlist.m3u8
        """

        let baseURL = URL(string: "https://cdn.example.com/live/master.m3u8")!
        let (variants, segments) = HLSPlaylistParser.parse(content: m3u8, baseURL: baseURL)

        XCTAssertEqual(variants.count, 3)
        XCTAssertEqual(segments.count, 0)

        let highest = variants.sorted { $0.bandwidth > $1.bandwidth }.first
        XCTAssertEqual(highest?.bandwidth, 5000000)
        XCTAssertEqual(highest?.resolution, "1920x1080")
        XCTAssertEqual(highest?.url.absoluteString, "https://cdn.example.com/live/1080p/playlist.m3u8")
    }

    func testMediaPlaylistParsing() {
        let m3u8 = """
        #EXTM3U
        #EXT-X-TARGETDURATION:10
        #EXT-X-VERSION:3
        #EXT-X-MEDIA-SEQUENCE:0
        #EXTINF:9.009,
        segment_0.ts
        #EXTINF:9.009,
        segment_1.ts
        #EXTINF:8.500,
        segment_2.ts
        #EXT-X-ENDLIST
        """

        let baseURL = URL(string: "https://cdn.example.com/media/playlist.m3u8")!
        let (variants, segments) = HLSPlaylistParser.parse(content: m3u8, baseURL: baseURL)

        XCTAssertEqual(variants.count, 0)
        XCTAssertEqual(segments.count, 3)
        XCTAssertEqual(segments[0].duration, 9.009)
        XCTAssertEqual(segments[0].url.absoluteString, "https://cdn.example.com/media/segment_0.ts")
        XCTAssertEqual(segments[2].duration, 8.5)
        XCTAssertEqual(segments[2].url.absoluteString, "https://cdn.example.com/media/segment_2.ts")
    }
}
