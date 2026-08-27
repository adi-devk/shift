import XCTest
@testable import Shift

final class UpdateTaskURLTests: XCTestCase {

    @MainActor
    func testUpdateTaskURLPreservesSegmentsAndResetsErrorState() async {
        let engine = ShiftDownloadEngine()
        let originalURL = URL(string: "https://example.com/expired_link_part1.zip?token=exp123")!
        let newURL = URL(string: "https://example.com/refreshed_link_part1.zip?token=fresh789")!

        // Create a task with existing segments
        let task = engine.addDownloadTask(url: originalURL, fileName: "archive_dataset.zip")
        
        // Manually simulate a failed / interrupted state
        if let idx = engine.tasks.firstIndex(where: { $0.id == task.id }) {
            var simulated = engine.tasks[idx]
            simulated.status = TaskStatus.failed
            simulated.errorDescription = "HTTP 403 Forbidden: Link Expired"
            simulated.downloadedBytes = 50 * 1024 * 1024
            simulated.fileSize = 100 * 1024 * 1024
            simulated.segments = [
                DownloadSegment(index: 0, startOffset: 0, currentOffset: 50 * 1024 * 1024, endOffset: 50 * 1024 * 1024 - 1, status: SegmentStatus.completed),
                DownloadSegment(index: 1, startOffset: 50 * 1024 * 1024, currentOffset: 50 * 1024 * 1024, endOffset: 100 * 1024 * 1024 - 1, status: SegmentStatus.failed, errorDescription: "403 Forbidden")
            ]
            engine.tasks[idx] = simulated
        }

        // Update URL
        engine.updateTaskURL(id: task.id, newURL: newURL, resumeImmediately: false)

        guard let updated = engine.tasks.first(where: { $0.id == task.id }) else {
            XCTFail("Task should exist")
            return
        }

        // Assertions
        XCTAssertEqual(updated.url, newURL, "Task URL should be updated to refreshed link")
        XCTAssertNil(updated.errorDescription, "Error description should be cleared")
        XCTAssertEqual(updated.status, TaskStatus.paused, "Failed status should be reset to paused")
        XCTAssertEqual(updated.downloadedBytes, 50 * 1024 * 1024, "Previous progress must be preserved")
        XCTAssertEqual(updated.segments.count, 2, "Segments must be preserved")
        XCTAssertEqual(updated.segments[0].status, SegmentStatus.completed, "Completed segment 0 remains completed")
        XCTAssertEqual(updated.segments[1].status, SegmentStatus.pending, "Failed segment 1 is reset to pending for resumption")

        // Cleanup
        engine.deleteTask(id: task.id, deleteFile: true)
    }
}
