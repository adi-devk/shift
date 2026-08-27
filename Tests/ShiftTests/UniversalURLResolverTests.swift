import XCTest
@testable import Shift

final class UniversalURLResolverTests: XCTestCase {

    func testProtocolDetection() {
        XCTAssertEqual(
            UniversalURLResolver.detectProtocolType(for: URL(string: "magnet:?xt=urn:btih:1234567890abcdef")!),
            .magnet
        )
        XCTAssertEqual(
            UniversalURLResolver.detectProtocolType(for: URL(string: "https://example.com/archlinux.iso.torrent")!),
            .bittorrent
        )
        XCTAssertEqual(
            UniversalURLResolver.detectProtocolType(for: URL(string: "https://live.example.com/stream/master.m3u8")!),
            .hls
        )
        XCTAssertEqual(
            UniversalURLResolver.detectProtocolType(for: URL(string: "https://drive.google.com/file/d/1BziE_Z0H_z00xXYZ12345/view")!),
            .googleDrive
        )
        XCTAssertEqual(
            UniversalURLResolver.detectProtocolType(for: URL(string: "https://www.dropbox.com/s/12345/my_document.pdf?dl=0")!),
            .dropbox
        )
        XCTAssertEqual(
            UniversalURLResolver.detectProtocolType(for: URL(string: "https://github.com/user/repo/releases/download/v1.0.0/app.zip")!),
            .githubRelease
        )
        XCTAssertEqual(
            UniversalURLResolver.detectProtocolType(for: URL(string: "https://archive.org/download/item/file.mp3")!),
            .internetArchive
        )
        XCTAssertEqual(
            UniversalURLResolver.detectProtocolType(for: URL(string: "https://1drv.ms/u/s!Am12345")!),
            .onedrive
        )
    }

    func testDirectURLTransformation() {
        // Dropbox
        let dbURL = URL(string: "https://www.dropbox.com/s/12345/myfile.pdf?dl=0")!
        let transformedDB = UniversalURLResolver.transformToDirectURL(dbURL)
        XCTAssertEqual(transformedDB.absoluteString, "https://www.dropbox.com/s/12345/myfile.pdf?dl=1")

        // GitHub Raw
        let ghURL = URL(string: "https://github.com/user/repo/raw/main/file.txt")!
        let transformedGH = UniversalURLResolver.transformToDirectURL(ghURL)
        XCTAssertEqual(transformedGH.absoluteString, "https://raw.githubusercontent.com/user/repo/main/file.txt")
    }

    func testAdvancedContentDispositionParsing() {
        // Gopeed #1215: HTML entity unescaping in filename
        let htmlHeader = "attachment; filename=\"Rock &amp; Roll - Track &quot;01&quot;.mp3\""
        XCTAssertEqual(
            AdvancedContentDispositionParser.extractFileName(from: htmlHeader),
            "Rock & Roll - Track \"01\".mp3"
        )

        // RFC 5987 / RFC 6266 filename* with charset
        let rfcHeader = "attachment; filename=\"fallback.zip\"; filename*=UTF-8''Gopeed%20Pro%20%2B%20Tools.tar.gz"
        XCTAssertEqual(
            AdvancedContentDispositionParser.extractFileName(from: rfcHeader),
            "Gopeed Pro + Tools.tar.gz"
        )

        // ISO / GBK / Mixed charset
        let mixedHeader = "attachment; filename*=GBK''%B2%E2%CA%D4%CE%C4%BC%FE.zip"
        let res = AdvancedContentDispositionParser.extractFileName(from: mixedHeader)
        XCTAssertNotNil(res)
    }

    func testMIMETypeRegistry() {
        XCTAssertEqual(MIMETypeRegistry.extensionForMIMEType("application/zip"), "zip")
        XCTAssertEqual(MIMETypeRegistry.extensionForMIMEType("application/x-7z-compressed"), "7z")
        XCTAssertEqual(MIMETypeRegistry.extensionForMIMEType("video/mp4; charset=binary"), "mp4")
        XCTAssertEqual(MIMETypeRegistry.extensionForMIMEType("application/pdf"), "pdf")
        XCTAssertEqual(MIMETypeRegistry.extensionForMIMEType("application/vnd.android.package-archive"), "apk")
        XCTAssertEqual(MIMETypeRegistry.extensionForMIMEType("application/x-bittorrent"), "torrent")
    }
}
