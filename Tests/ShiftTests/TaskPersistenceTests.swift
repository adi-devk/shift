import XCTest
@testable import Shift

final class TaskPersistenceTests: XCTestCase {
    func testTaskCategoryClassification() {
        XCTAssertEqual(TaskCategory.determineCategory(from: "movie.mp4"), .video)
        XCTAssertEqual(TaskCategory.determineCategory(from: "stream.m3u8"), .video)
        XCTAssertEqual(TaskCategory.determineCategory(from: "song.flac"), .audio)
        XCTAssertEqual(TaskCategory.determineCategory(from: "report.pdf"), .documents)
        XCTAssertEqual(TaskCategory.determineCategory(from: "package.zip"), .compressed)
        XCTAssertEqual(TaskCategory.determineCategory(from: "app.ipa"), .compressed)
        XCTAssertEqual(TaskCategory.determineCategory(from: "linux.iso"), .compressed)
        XCTAssertEqual(TaskCategory.determineCategory(from: "file.torrent"), .torrent)
        XCTAssertEqual(TaskCategory.determineCategory(from: "picture.png"), .images)
    }

    func testTaskJSONEncodingDecoding() throws {
        let task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            fileName: "file.zip",
            fileSize: 1048576,
            downloadedBytes: 524288,
            status: .downloading,
            category: .compressed,
            protocolType: .http,
            maxConnections: 8
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(task)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DownloadTask.self, from: data)

        XCTAssertEqual(task.id, decoded.id)
        XCTAssertEqual(task.fileName, decoded.fileName)
        XCTAssertEqual(task.fileSize, decoded.fileSize)
        XCTAssertEqual(task.downloadedBytes, decoded.downloadedBytes)
        XCTAssertEqual(task.category, decoded.category)
        XCTAssertEqual(task.protocolType, decoded.protocolType)
        XCTAssertEqual(task.maxConnections, 8)
    }
}
