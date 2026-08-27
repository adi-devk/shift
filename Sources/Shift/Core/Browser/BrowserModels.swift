import Foundation

public struct BrowserTab: Identifiable, Codable, Equatable {
    public var id: UUID
    public var title: String
    public var url: URL
    public var urlString: String
    public var canGoBack: Bool
    public var canGoForward: Bool
    public var isLoading: Bool
    public var estimatedProgress: Double
    public var isDesktopMode: Bool
    public var isPrivate: Bool
    public var pageZoom: Double
    public var createdAt: Date
    public var lastActiveAt: Date

    public init(
        id: UUID = UUID(),
        title: String = "New Tab",
        url: URL = URL(string: "https://duckduckgo.com")!,
        urlString: String = "https://duckduckgo.com",
        canGoBack: Bool = false,
        canGoForward: Bool = false,
        isLoading: Bool = false,
        estimatedProgress: Double = 0.0,
        isDesktopMode: Bool = false,
        isPrivate: Bool = false,
        pageZoom: Double = 1.0,
        createdAt: Date = Date(),
        lastActiveAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.urlString = urlString
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.isLoading = isLoading
        self.estimatedProgress = estimatedProgress
        self.isDesktopMode = isDesktopMode
        self.isPrivate = isPrivate
        self.pageZoom = pageZoom
        self.createdAt = createdAt
        self.lastActiveAt = lastActiveAt
    }

    public var displayTitle: String {
        if !title.isEmpty && title != "New Tab" {
            return title
        }
        if let host = url.host {
            return host.replacingOccurrences(of: "www.", with: "")
        }
        return "New Tab"
    }

    public var hostDomain: String {
        return url.host?.replacingOccurrences(of: "www.", with: "") ?? url.absoluteString
    }

    public static func == (lhs: BrowserTab, rhs: BrowserTab) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.url == rhs.url &&
        lhs.isLoading == rhs.isLoading &&
        lhs.estimatedProgress == rhs.estimatedProgress &&
        lhs.canGoBack == rhs.canGoBack &&
        lhs.canGoForward == rhs.canGoForward &&
        lhs.isDesktopMode == rhs.isDesktopMode &&
        lhs.isPrivate == rhs.isPrivate &&
        lhs.pageZoom == rhs.pageZoom
    }
}

public struct BookmarkItem: Identifiable, Codable, Equatable {
    public var id: UUID
    public var title: String
    public var url: URL
    public var dateAdded: Date

    public init(id: UUID = UUID(), title: String, url: URL, dateAdded: Date = Date()) {
        self.id = id
        self.title = title
        self.url = url
        self.dateAdded = dateAdded
    }
}

public struct HistoryItem: Identifiable, Codable, Equatable {
    public var id: UUID
    public var title: String
    public var url: URL
    public var visitedAt: Date

    public init(id: UUID = UUID(), title: String, url: URL, visitedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.url = url
        self.visitedAt = visitedAt
    }

    public var displayTitle: String {
        title.isEmpty ? (url.host ?? url.absoluteString) : title
    }
}

public enum FindMatchState {
    case idle
    case searching(query: String, currentMatch: Int, totalMatches: Int)
}
