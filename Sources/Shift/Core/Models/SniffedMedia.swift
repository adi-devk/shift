import Foundation
import SwiftUI

public enum SniffedMediaType: String, Codable, Sendable, CaseIterable {
    case video = "Video"
    case audio = "Audio"
    case hlsStream = "HLS Stream"
    case document = "Document"
    case directFile = "File"

    public var iconName: String {
        switch self {
        case .video: return "video.fill"
        case .audio: return "waveform"
        case .hlsStream: return "play.tv.fill"
        case .document: return "doc.fill"
        case .directFile: return "arrow.down.doc.fill"
        }
    }

    public var color: Color {
        switch self {
        case .video: return .purple
        case .audio: return .pink
        case .hlsStream: return .indigo
        case .document: return .orange
        case .directFile: return .blue
        }
    }
}

public struct SniffedMedia: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let url: URL
    public let pageUrl: URL
    public var title: String
    public var mediaType: SniffedMediaType
    public var format: String // "MP4", "M3U8", "M4A", "WEBM", "MP3", "PDF"
    public var resolution: String? // "1080p", "720p", "4K"
    public var bitrate: String? // "320 kbps", "5 Mbps"
    public var estimatedSizeBytes: Int64?
    public var mimeType: String?
    public var headers: [String: String]
    public var detectedAt: Date

    public init(
        id: UUID = UUID(),
        url: URL,
        pageUrl: URL,
        title: String,
        mediaType: SniffedMediaType,
        format: String,
        resolution: String? = nil,
        bitrate: String? = nil,
        estimatedSizeBytes: Int64? = nil,
        mimeType: String? = nil,
        headers: [String: String] = [:],
        detectedAt: Date = Date()
    ) {
        self.id = id
        self.url = url
        self.pageUrl = pageUrl
        self.title = title
        self.mediaType = mediaType
        self.format = format.uppercased()
        self.resolution = resolution
        self.bitrate = bitrate
        self.estimatedSizeBytes = estimatedSizeBytes
        self.mimeType = mimeType
        self.headers = headers
        self.detectedAt = detectedAt
    }

    public var formattedSize: String {
        if let size = estimatedSizeBytes, size > 0 {
            return ByteCountFormatter.formatBytes(size)
        }
        return "Unknown size"
    }

    public var qualityBadge: String {
        if let res = resolution, !res.isEmpty {
            return res
        }
        if let bit = bitrate, !bit.isEmpty {
            return bit
        }
        return format
    }
}
