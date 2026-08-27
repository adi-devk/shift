import Foundation

public enum SegmentStatus: String, Codable, Sendable {
    case pending
    case connecting
    case downloading
    case completed
    case paused
    case failed
}

public struct DownloadSegment: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let index: Int
    public var startOffset: Int64
    public var currentOffset: Int64
    public var endOffset: Int64
    public var totalBytes: Int64 {
        max(0, endOffset - startOffset + 1)
    }
    public var downloadedBytes: Int64 {
        max(0, currentOffset - startOffset)
    }
    public var progress: Double {
        guard totalBytes > 0 else { return 0.0 }
        return min(1.0, max(0.0, Double(downloadedBytes) / Double(totalBytes)))
    }
    public var speedBytesPerSec: Int64
    public var status: SegmentStatus
    public var errorDescription: String?

    public init(
        id: UUID = UUID(),
        index: Int,
        startOffset: Int64,
        currentOffset: Int64? = nil,
        endOffset: Int64,
        speedBytesPerSec: Int64 = 0,
        status: SegmentStatus = .pending,
        errorDescription: String? = nil
    ) {
        self.id = id
        self.index = index
        self.startOffset = startOffset
        self.currentOffset = currentOffset ?? startOffset
        self.endOffset = endOffset
        self.speedBytesPerSec = speedBytesPerSec
        self.status = status
        self.errorDescription = errorDescription
    }

    public var isFinished: Bool {
        return currentOffset > endOffset || status == .completed
    }

    public var remainingBytes: Int64 {
        max(0, endOffset - currentOffset + 1)
    }
}
