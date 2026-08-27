import XCTest
@testable import Shift

final class GoogleDriveResolverTests: XCTestCase {

    func testGoogleDriveURLDetectionAndIDExtraction() {
        let testCases: [(urlStr: String, expectedID: String)] = [
            ("https://drive.google.com/file/d/1BziE_Z0H_z00xXYZ12345/view?usp=sharing", "1BziE_Z0H_z00xXYZ12345"),
            ("https://drive.google.com/file/d/1a2b3c4d5e6f7g8h/view", "1a2b3c4d5e6f7g8h"),
            ("https://drive.google.com/open?id=1234567890abcdef", "1234567890abcdef"),
            ("https://drive.google.com/uc?id=9876543210fedcba&export=download", "9876543210fedcba"),
            ("https://docs.google.com/file/d/DOC_FILE_ID_1122/edit", "DOC_FILE_ID_1122"),
            ("https://drive.usercontent.google.com/download?id=CDN_FILE_ID_55&export=download", "CDN_FILE_ID_55")
        ]

        for testCase in testCases {
            guard let url = URL(string: testCase.urlStr) else {
                XCTFail("Failed to create URL for \(testCase.urlStr)")
                continue
            }
            XCTAssertTrue(GoogleDriveURLResolver.isGoogleDriveURL(url), "URL should be detected as Google Drive: \(testCase.urlStr)")
            let extractedID = GoogleDriveURLResolver.extractFileID(from: url)
            XCTAssertEqual(extractedID, testCase.expectedID, "Extracted file ID should match expected for: \(testCase.urlStr)")
        }
    }

    func testContentDispositionParsing() {
        // Standard quoted
        let header1 = "attachment; filename=\"My Presentation 2026.pdf\""
        XCTAssertEqual(ContentDispositionParser.extractFileName(from: header1), "My Presentation 2026.pdf")

        // Unquoted
        let header2 = "attachment; filename=archive_data.zip; size=1024"
        XCTAssertEqual(ContentDispositionParser.extractFileName(from: header2), "archive_data.zip")

        // RFC 5987 / 6266 UTF-8 encoded
        let header3 = "attachment; filename=\"fallback.zip\"; filename*=UTF-8''%e6%96%87%e4%bb%b6%202026.zip"
        XCTAssertEqual(ContentDispositionParser.extractFileName(from: header3), "文件 2026.zip")

        // URL encoded space in filename*
        let header4 = "attachment; filename*=utf-8''Video%20Episode%201080p.mp4"
        XCTAssertEqual(ContentDispositionParser.extractFileName(from: header4), "Video Episode 1080p.mp4")

        // Sanitization of path traversal characters
        let header5 = "attachment; filename=\"../../../evil_path/file.iso\""
        let sanitized = ContentDispositionParser.extractFileName(from: header5)
        XCTAssertFalse(sanitized?.contains("/") ?? true, "Path traversal slash must be removed")
        XCTAssertEqual(sanitized, ".._.._.._evil_path_file.iso")
    }
}
