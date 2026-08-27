import Foundation

public final class SpeedLimiter: @unchecked Sendable {
    private let lock = NSLock()
    private var maxBytesPerSecond: Int64
    private var availableTokens: Double
    private var lastRefillTime: TimeInterval

    public init(maxBytesPerSecond: Int64 = 0) {
        self.maxBytesPerSecond = maxBytesPerSecond
        self.availableTokens = Double(maxBytesPerSecond)
        self.lastRefillTime = ProcessInfo.processInfo.systemUptime
    }

    public func setLimit(bytesPerSecond: Int64) {
        lock.lock()
        defer { lock.unlock() }
        self.maxBytesPerSecond = bytesPerSecond
        self.availableTokens = Double(bytesPerSecond)
        self.lastRefillTime = ProcessInfo.processInfo.systemUptime
    }

    public func getLimit() -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        return maxBytesPerSecond
    }

    /// Requests permission to transfer `bytes` count. Suspends if throttling is active.
    public func consume(bytes: Int) async {
        guard maxBytesPerSecond > 0 else { return }

        while true {
            let delay: TimeInterval = {
                lock.lock()
                defer { lock.unlock() }

                let now = ProcessInfo.processInfo.systemUptime
                let elapsed = now - lastRefillTime
                lastRefillTime = now

                // Replenish tokens based on elapsed time
                let refill = elapsed * Double(maxBytesPerSecond)
                availableTokens = min(Double(maxBytesPerSecond), availableTokens + refill)

                let requested = Double(bytes)
                if availableTokens >= requested {
                    availableTokens -= requested
                    return 0.0
                } else {
                    let needed = requested - availableTokens
                    let waitTime = needed / Double(maxBytesPerSecond)
                    return min(waitTime, 1.0)
                }
            }()

            if delay <= 0 {
                break
            } else {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }
}
