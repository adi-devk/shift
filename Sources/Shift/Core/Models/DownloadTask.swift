import Foundation
import SwiftUI

public enum TaskStatus: String, Codable, CaseIterable, Sendable {
    case queued = "Queued"
    case connecting = "Connecting"
    case downloading = "Downloading"
    case paused = "Paused"
    case merging = "Merging"
    case completed = "Completed"
    case failed = "Failed"

    public var iconName: String {
        switch self {
        case .queued: return "clock.arrow.circlepath"
        case .connecting: return "network"
        case .downloading: return "arrow.down.circle.fill"
        case .paused: return "pause.circle.fill"
        case .merging: return "arrow.triangle.merge"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    public var color: Color {
        switch self {
        case .queued: return .secondary
        case .connecting: return .orange
        case .downloading: return .blue
        case .paused: return .orange
        case .merging: return .purple
        case .completed: return .green
        case .failed: return .red
        }
    }
}

public enum ProtocolType: String, Codable, Sendable {
    case http = "HTTP/S"
    case hls = "HLS (m3u8)"
    case torrent = "BitTorrent"
}

public struct DownloadSpeedSample: Codable, Sendable, Identifiable {
    public var id = UUID()
    public let timestamp: Date
    public let bytesPerSecond: Int64

    public init(timestamp: Date = Date(), bytesPerSecond: Int64) {
        self.id = UUID()
        self.timestamp = timestamp
        self.bytesPerSecond = bytesPerSecond
    }
}

public struct DownloadTask: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var url: URL
    public var fileName: String
    public var fileSize: Int64 // -1 if unknown / dynamic stream
    public var downloadedBytes: Int64
    public var status: TaskStatus
    public var category: TaskCategory
    public var protocolType: ProtocolType
    
    public var createdAt: Date
    public var startedAt: Date?
    public var completedAt: Date?
    
    public var speedBytesPerSec: Int64
    public var averageSpeedBytesPerSec: Int64
    public var etaSeconds: TimeInterval?
    public var speedHistory: [DownloadSpeedSample]
    
    public var segments: [DownloadSegment]
    public var maxConnections: Int
    public var isChunked: Bool
    public var supportsResume: Bool
    
    public var headers: [String: String]
    public var userAgent: String?
    public var destinationPath: String
    public var mimeType: String?
    public var etag: String?
    public var errorDescription: String?

    public init(
        id: UUID = UUID(),
        url: URL,
        fileName: String? = nil,
        fileSize: Int64 = -1,
        downloadedBytes: Int64 = 0,
        status: TaskStatus = .queued,
        category: TaskCategory? = nil,
        protocolType: ProtocolType = .http,
        createdAt: Date = Date(),
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        speedBytesPerSec: Int64 = 0,
        averageSpeedBytesPerSec: Int64 = 0,
        etaSeconds: TimeInterval? = nil,
        speedHistory: [DownloadSpeedSample] = [],
        segments: [DownloadSegment] = [],
        maxConnections: Int = 8,
        isChunked: Bool = true,
        supportsResume: Bool = true,
        headers: [String: String] = [:],
        userAgent: String? = nil,
        destinationPath: String = "",
        mimeType: String? = nil,
        etag: String? = nil,
        errorDescription: String? = nil
    ) {
        self.id = id
        self.url = url
        
        let resolvedFileName = fileName ?? (url.lastPathComponent.isEmpty ? "download_\(Int(createdAt.timeIntervalSince1970))" : url.lastPathComponent)
        self.fileName = resolvedFileName
        self.fileSize = fileSize
        self.downloadedBytes = downloadedBytes
        self.status = status
        self.category = category ?? TaskCategory.determineCategory(from: resolvedFileName, mimeType: mimeType)
        self.protocolType = protocolType
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.speedBytesPerSec = speedBytesPerSec
        self.averageSpeedBytesPerSec = averageSpeedBytesPerSec
        self.etaSeconds = etaSeconds
        self.speedHistory = speedHistory
        self.segments = segments
        self.maxConnections = maxConnections
        self.isChunked = isChunked
        self.supportsResume = supportsResume
        self.headers = headers
        self.userAgent = userAgent
        self.destinationPath = destinationPath
        self.mimeType = mimeType
        self.etag = etag
        self.errorDescription = errorDescription
    }

    public var progress: Double {
        if fileSize > 0 {
            return min(1.0, max(0.0, Double(downloadedBytes) / Double(fileSize)))
        } else if !segments.isEmpty {
            let total = segments.reduce(0) { $0 + $1.totalBytes }
            let done = segments.reduce(0) { $0 + $1.downloadedBytes }
            guard total > 0 else { return 0.0 }
            return min(1.0, max(0.0, Double(done) / Double(total)))
        }
        return 0.0
    }

    public var formattedSpeed: String {
        ByteCountFormatter.formatSpeed(bytesPerSecond: speedBytesPerSec)
    }

    public var formattedAverageSpeed: String {
        ByteCountFormatter.formatSpeed(bytesPerSecond: averageSpeedBytesPerSec)
    }

    public var formattedDownloadedSize: String {
        ByteCountFormatter.formatBytes(downloadedBytes)
    }

    public var formattedTotalSize: String {
        if fileSize > 0 {
            return ByteCountFormatter.formatBytes(fileSize)
        } else {
            return "Unknown"
        }
    }

    public var formattedETA: String {
        guard let eta = etaSeconds, eta > 0, status == .downloading else {
            return status == .completed ? "Finished" : "--"
        }
        let totalSeconds = Int(eta)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%dh %02dm %02ds", hours, minutes, seconds)
        } else if minutes > 0 {
            return String(format: "%dm %02ds", minutes, seconds)
        } else {
            return String(format: "%ds", seconds)
        }
    }

    public static func == (lhs: DownloadTask, rhs: DownloadTask) -> Bool {
        return lhs.id == rhs.id &&
               lhs.status == rhs.status &&
               lhs.downloadedBytes == rhs.downloadedBytes &&
               lhs.speedBytesPerSec == rhs.speedBytesPerSec &&
               lhs.segments.count == rhs.segments.count &&
               lhs.errorDescription == rhs.errorDescription
    }
}

public extension ByteCountFormatter {
    static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    static func formatSpeed(bytesPerSecond: Int64) -> String {
        guard bytesPerSecond > 0 else { return "0 B/s" }
        return "\(formatBytes(bytesPerSecond))/s"
    }
}
