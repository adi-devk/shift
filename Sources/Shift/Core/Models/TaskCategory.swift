import Foundation
import SwiftUI

public enum TaskCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case video = "Video"
    case audio = "Audio"
    case documents = "Documents"
    case compressed = "Archives"
    case torrent = "Torrents"
    case images = "Images"
    case other = "Other"

    public var id: String { rawValue }

    public var displayName: String { rawValue }

    public var iconName: String {
        switch self {
        case .all: return "tray.full.fill"
        case .video: return "play.rectangle.fill"
        case .audio: return "music.note"
        case .documents: return "doc.text.fill"
        case .compressed: return "archivebox.fill"
        case .torrent: return "point.3.filled.connected.trianglepath.dotted"
        case .images: return "photo.fill"
        case .other: return "questionmark.folder.fill"
        }
    }

    public var color: Color {
        switch self {
        case .all: return .blue
        case .video: return .purple
        case .audio: return .pink
        case .documents: return .orange
        case .compressed: return .yellow
        case .torrent: return .green
        case .images: return .teal
        case .other: return .gray
        }
    }

    public static func determineCategory(from fileName: String, mimeType: String? = nil) -> TaskCategory {
        let ext = (fileName as NSString).pathExtension.lowercased()
        
        let videoExtensions = ["mp4", "mkv", "avi", "mov", "flv", "webm", "m3u8", "ts", "m4v", "wmv", "3gp"]
        let audioExtensions = ["mp3", "m4a", "aac", "flac", "wav", "ogg", "wma", "aiff", "opus"]
        let docExtensions = ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "rtf", "csv", "epub"]
        let archiveExtensions = ["zip", "rar", "7z", "tar", "gz", "bz2", "xz", "iso", "dmg", "pkg", "ipa", "apk"]
        let imageExtensions = ["jpg", "jpeg", "png", "gif", "webp", "svg", "bmp", "heic", "tiff"]
        let torrentExtensions = ["torrent"]

        if torrentExtensions.contains(ext) {
            return .torrent
        } else if videoExtensions.contains(ext) {
            return .video
        } else if audioExtensions.contains(ext) {
            return .audio
        } else if docExtensions.contains(ext) {
            return .documents
        } else if archiveExtensions.contains(ext) {
            return .compressed
        } else if imageExtensions.contains(ext) {
            return .images
        }

        if let mime = mimeType?.lowercased() {
            if mime.contains("video") { return .video }
            if mime.contains("audio") { return .audio }
            if mime.contains("image") { return .images }
            if mime.contains("pdf") || mime.contains("document") || mime.contains("text") { return .documents }
            if mime.contains("zip") || mime.contains("compressed") || mime.contains("archive") { return .compressed }
            if mime.contains("bittorrent") { return .torrent }
        }

        return .other
    }
}
