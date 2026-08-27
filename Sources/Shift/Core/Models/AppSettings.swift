import Foundation

public enum SearchEngine: String, Codable, CaseIterable, Identifiable, Sendable {
    case google = "Google"
    case duckDuckGo = "DuckDuckGo"
    case bing = "Bing"
    case baidu = "Baidu"

    public var id: String { rawValue }

    public func searchURL(for query: String) -> URL? {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        switch self {
        case .google:
            return URL(string: "https://www.google.com/search?q=\(encoded)")
        case .duckDuckGo:
            return URL(string: "https://duckduckgo.com/?q=\(encoded)")
        case .bing:
            return URL(string: "https://www.bing.com/search?q=\(encoded)")
        case .baidu:
            return URL(string: "https://www.baidu.com/s?wd=\(encoded)")
        }
    }
}

public enum UserAgentPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case defaultSafari = "Mobile Safari (iOS)"
    case desktopMac = "Desktop Safari (macOS)"
    case chromeWindows = "Chrome (Windows)"
    case custom = "Custom"

    public var id: String { rawValue }

    public var userAgentString: String {
        switch self {
        case .defaultSafari:
            return "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
        case .desktopMac:
            return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"
        case .chromeWindows:
            return "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"
        case .custom:
            return ""
        }
    }
}

public struct AppSettings: Codable, Sendable {
    // Engine & Network
    public var maxConcurrentDownloads: Int
    public var defaultConnectionsPerDownload: Int
    public var globalSpeedLimitEnabled: Bool
    public var globalSpeedLimitBytesPerSec: Int64
    public var unrestrictedBackgroundDownloads: Bool
    public var autoResumeOnWifi: Bool
    public var allowCellularDownloads: Bool
    public var retryCountOnFailure: Int
    public var timeoutInterval: TimeInterval

    // Sniffer & Browser
    public var mediaSnifferEnabled: Bool
    public var sniffVideos: Bool
    public var sniffAudios: Bool
    public var sniffDocuments: Bool
    public var sniffHLSStreams: Bool
    public var autoPromptSniffedMedia: Bool
    public var adBlockerEnabled: Bool
    public var defaultSearchEngine: SearchEngine
    public var userAgentPreset: UserAgentPreset
    public var customUserAgent: String

    // Torrent
    public var torrentListeningPort: Int
    public var torrentMaxPeers: Int
    public var torrentDHTEnabled: Bool
    public var torrentUploadLimitBytesPerSec: Int64

    // Notifications & UI
    public var notifyOnCompletion: Bool
    public var notifyOnFailure: Bool
    public var hapticFeedbackEnabled: Bool
    public var autoClipboardDetect: Bool

    // Storage
    public var downloadDirectoryName: String
    public var autoCategorizeFiles: Bool

    public static let `default` = AppSettings(
        maxConcurrentDownloads: 3,
        defaultConnectionsPerDownload: 8,
        globalSpeedLimitEnabled: false,
        globalSpeedLimitBytesPerSec: 5 * 1024 * 1024, // 5 MB/s
        unrestrictedBackgroundDownloads: true,
        autoResumeOnWifi: true,
        allowCellularDownloads: true,
        retryCountOnFailure: 3,
        timeoutInterval: 30.0,
        mediaSnifferEnabled: true,
        sniffVideos: true,
        sniffAudios: true,
        sniffDocuments: true,
        sniffHLSStreams: true,
        autoPromptSniffedMedia: true,
        adBlockerEnabled: true,
        defaultSearchEngine: .duckDuckGo,
        userAgentPreset: .defaultSafari,
        customUserAgent: "",
        torrentListeningPort: 6881,
        torrentMaxPeers: 50,
        torrentDHTEnabled: true,
        torrentUploadLimitBytesPerSec: 0,
        notifyOnCompletion: true,
        notifyOnFailure: true,
        hapticFeedbackEnabled: true,
        autoClipboardDetect: true,
        downloadDirectoryName: "Downloads",
        autoCategorizeFiles: true
    )

    public static let storageKey = "shift_app_settings_v1"

    public static func load() -> AppSettings {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let settings = try? JSONDecoder().decode(AppSettings.self, from: data) {
            return settings
        }
        return .default
    }

    public func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: AppSettings.storageKey)
        }
    }
}
