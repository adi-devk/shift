import XCTest
@testable import Shift

final class ChunkedDownloaderTests: XCTestCase {
    func testSegmentCalculations() {
        let segment = DownloadSegment(
            index: 0,
            startOffset: 0,
            currentOffset: 250,
            endOffset: 999,
            status: .downloading
        )

        XCTAssertEqual(segment.totalBytes, 1000)
        XCTAssertEqual(segment.downloadedBytes, 250)
        XCTAssertEqual(segment.remainingBytes, 750)
        XCTAssertEqual(segment.progress, 0.25, accuracy: 0.001)
        XCTAssertFalse(segment.isFinished)
    }

    func testSegmentCompletion() {
        let segment = DownloadSegment(
            index: 1,
            startOffset: 1000,
            currentOffset: 2000,
            endOffset: 1999,
            status: .completed
        )

        XCTAssertTrue(segment.isFinished)
        XCTAssertEqual(segment.progress, 1.0)
    }

    func testMultiSegmentPartitioning() {
        let totalSize: Int64 = 100_000_000 // 100 MB
        let numParts = 8
        let chunkSize = totalSize / Int64(numParts)

        var segments: [DownloadSegment] = []
        for i in 0..<numParts {
            let start = Int64(i) * chunkSize
            let end = (i == numParts - 1) ? (totalSize - 1) : (start + chunkSize - 1)
            segments.append(
                DownloadSegment(
                    index: i,
                    startOffset: start,
                    currentOffset: start,
                    endOffset: end
                )
            )
        }

        XCTAssertEqual(segments.count, 8)
        XCTAssertEqual(segments.first?.startOffset, 0)
        XCTAssertEqual(segments.last?.endOffset, 99_999_999)
        let totalSpan = segments.reduce(0) { $0 + $1.totalBytes }
        XCTAssertEqual(totalSpan, 100_000_000)
    }
}
