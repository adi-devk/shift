import XCTest
@testable import Shift

final class SpeedLimiterTests: XCTestCase {
    func testSpeedLimiterConfiguration() {
        let limiter = SpeedLimiter(maxBytesPerSecond: 1024 * 1024) // 1 MB/s
        XCTAssertEqual(limiter.getLimit(), 1024 * 1024)

        limiter.setLimit(bytesPerSecond: 5 * 1024 * 1024) // 5 MB/s
        XCTAssertEqual(limiter.getLimit(), 5 * 1024 * 1024)
    }

    func testSpeedLimiterConsumption() async {
        let limiter = SpeedLimiter(maxBytesPerSecond: 0) // Unlimited
        let start = Date()
        await limiter.consume(bytes: 100_000)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 0.1)
    }
}
