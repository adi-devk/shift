import Foundation
import Combine
import SwiftUI

@MainActor
public final class BrowserTabManager: ObservableObject {
    public static let shared = BrowserTabManager()

    @Published public var tabs: [BrowserTab] = []
    @Published public var activeTabId: UUID = UUID()
    
    @Published public var privateTabs: [BrowserTab] = []
    @Published public var activePrivateTabId: UUID = UUID()
    
    @Published public var isPrivateMode: Bool = false
    @Published public var isTabOverviewPresented: Bool = false
    @Published public var isFindOnPagePresented: Bool = false
    @Published public var isPageMenuPresented: Bool = false
    
    @Published public var history: [HistoryItem] = []
    @Published public var bookmarks: [BookmarkItem] = []
    
    private var recentlyClosedTabs: [BrowserTab] = []
    
    private let tabsStorageKey = "shift_browser_tabs_v1"
    private let historyStorageKey = "shift_browser_history_v1"
    private let bookmarksStorageKey = "shift_browser_bookmarks_v1"

    public init() {
        loadPersistedState()
        ensureDefaultTabExists()
    }

    // MARK: - Active Tab Resolvers

    public var currentTabs: [BrowserTab] {
        get { isPrivateMode ? privateTabs : tabs }
        set {
            if isPrivateMode {
                privateTabs = newValue
            } else {
                tabs = newValue
                saveTabs()
            }
        }
    }

    public var currentActiveTabId: UUID {
        get { isPrivateMode ? activePrivateTabId : activeTabId }
        set {
            if isPrivateMode {
                activePrivateTabId = newValue
            } else {
                activeTabId = newValue
            }
        }
    }

    public var activeTab: BrowserTab? {
        let currentList = currentTabs
        let activeId = currentActiveTabId
        return currentList.first(where: { $0.id == activeId }) ?? currentList.first
    }

    // MARK: - Tab Operations

    @discardableResult
    public func createNewTab(
        url: URL = URL(string: "https://duckduckgo.com")!,
        title: String = "New Tab",
        isPrivate: Bool? = nil,
        makeActive: Bool = true
    ) -> BrowserTab {
        let privateFlag = isPrivate ?? isPrivateMode
        let newTab = BrowserTab(
            title: title,
            url: url,
            urlString: url.absoluteString,
            isPrivate: privateFlag
        )

        if privateFlag {
            privateTabs.append(newTab)
            if makeActive {
                isPrivateMode = true
                activePrivateTabId = newTab.id
            }
        } else {
            tabs.append(newTab)
            if makeActive {
                isPrivateMode = false
                activeTabId = newTab.id
            }
            saveTabs()
        }

        return newTab
    }

    public func closeTab(id: UUID) {
        if isPrivateMode {
            if let idx = privateTabs.firstIndex(where: { $0.id == id }) {
                let tab = privateTabs.remove(at: idx)
                recentlyClosedTabs.append(tab)
                if activePrivateTabId == id {
                    if !privateTabs.isEmpty {
                        let newIdx = min(idx, privateTabs.count - 1)
                        activePrivateTabId = privateTabs[newIdx].id
                    } else {
                        createNewTab(isPrivate: true, makeActive: true)
                    }
                }
            }
        } else {
            if let idx = tabs.firstIndex(where: { $0.id == id }) {
                let tab = tabs.remove(at: idx)
                recentlyClosedTabs.append(tab)
                if activeTabId == id {
                    if !tabs.isEmpty {
                        let newIdx = min(idx, tabs.count - 1)
                        activeTabId = tabs[newIdx].id
                    } else {
                        createNewTab(isPrivate: false, makeActive: true)
                    }
                }
                saveTabs()
            }
        }
    }

    public func closeAllTabs() {
        if isPrivateMode {
            privateTabs.removeAll()
            createNewTab(isPrivate: true, makeActive: true)
        } else {
            tabs.removeAll()
            createNewTab(isPrivate: false, makeActive: true)
            saveTabs()
        }
    }

    public func selectTab(id: UUID) {
        currentActiveTabId = id
        isTabOverviewPresented = false
    }

    public func duplicateTab(id: UUID) {
        guard let existing = (tabs + privateTabs).first(where: { $0.id == id }) else { return }
        createNewTab(
            url: existing.url,
            title: existing.title,
            isPrivate: existing.isPrivate,
            makeActive: true
        )
    }

    public func restoreLastClosedTab() {
        guard let last = recentlyClosedTabs.popLast() else { return }
        if last.isPrivate {
            privateTabs.append(last)
            activePrivateTabId = last.id
            isPrivateMode = true
        } else {
            tabs.append(last)
            activeTabId = last.id
            isPrivateMode = false
            saveTabs()
        }
    }

    // MARK: - Tab State Updates

    public func updateTabState(
        id: UUID,
        title: String? = nil,
        url: URL? = nil,
        urlString: String? = nil,
        canGoBack: Bool? = nil,
        canGoForward: Bool? = nil,
        isLoading: Bool? = nil,
        estimatedProgress: Double? = nil,
        isDesktopMode: Bool? = nil,
        pageZoom: Double? = nil
    ) {
        let updateBlock: (inout BrowserTab) -> Void = { tab in
            if let title = title { tab.title = title }
            if let url = url { tab.url = url }
            if let urlString = urlString { tab.urlString = urlString }
            if let canGoBack = canGoBack { tab.canGoBack = canGoBack }
            if let canGoForward = canGoForward { tab.canGoForward = canGoForward }
            if let isLoading = isLoading { tab.isLoading = isLoading }
            if let estimatedProgress = estimatedProgress { tab.estimatedProgress = estimatedProgress }
            if let isDesktopMode = isDesktopMode { tab.isDesktopMode = isDesktopMode }
            if let pageZoom = pageZoom { tab.pageZoom = pageZoom }
            tab.lastActiveAt = Date()
        }

        if let idx = tabs.firstIndex(where: { $0.id == id }) {
            updateBlock(&tabs[idx])
            saveTabs()
        } else if let idx = privateTabs.firstIndex(where: { $0.id == id }) {
            updateBlock(&privateTabs[idx])
        }
    }

    public func toggleDesktopMode(for id: UUID) {
        if let idx = tabs.firstIndex(where: { $0.id == id }) {
            tabs[idx].isDesktopMode.toggle()
            saveTabs()
        } else if let idx = privateTabs.firstIndex(where: { $0.id == id }) {
            privateTabs[idx].isDesktopMode.toggle()
        }
    }

    public func setZoom(for id: UUID, zoom: Double) {
        if let idx = tabs.firstIndex(where: { $0.id == id }) {
            tabs[idx].pageZoom = max(0.5, min(2.0, zoom))
            saveTabs()
        } else if let idx = privateTabs.firstIndex(where: { $0.id == id }) {
            privateTabs[idx].pageZoom = max(0.5, min(2.0, zoom))
        }
    }

    // MARK: - History & Bookmarks

    public func recordHistory(title: String, url: URL) {
        // Never record history in private browsing mode
        if isPrivateMode { return }
        guard url.scheme?.hasPrefix("http") == true else { return }

        // Remove duplicate recent entry if exists
        history.removeAll(where: { $0.url.absoluteString == url.absoluteString })
        let item = HistoryItem(title: title, url: url, visitedAt: Date())
        history.insert(item, at: 0)

        // Keep maximum 500 items
        if history.count > 500 {
            history.removeLast(history.count - 500)
        }
        saveHistory()
    }

    public func clearHistory(olderThan: Date? = nil) {
        if let cutoff = olderThan {
            history.removeAll(where: { $0.visitedAt >= cutoff })
        } else {
            history.removeAll()
        }
        saveHistory()
    }

    public func toggleBookmark(title: String, url: URL) {
        if let idx = bookmarks.firstIndex(where: { $0.url.absoluteString == url.absoluteString }) {
            bookmarks.remove(at: idx)
        } else {
            let item = BookmarkItem(title: title.isEmpty ? (url.host ?? "Bookmark") : title, url: url)
            bookmarks.insert(item, at: 0)
        }
        saveBookmarks()
    }

    public func isBookmarked(url: URL) -> Bool {
        bookmarks.contains(where: { $0.url.absoluteString == url.absoluteString })
    }

    public func deleteBookmark(id: UUID) {
        bookmarks.removeAll(where: { $0.id == id })
        saveBookmarks()
    }

    // MARK: - Persistence

    private func ensureDefaultTabExists() {
        if tabs.isEmpty {
            let defaultTab = BrowserTab(
                title: "DuckDuckGo",
                url: URL(string: "https://duckduckgo.com")!,
                urlString: "https://duckduckgo.com"
            )
            tabs.append(defaultTab)
            activeTabId = defaultTab.id
        }
        if privateTabs.isEmpty {
            let defaultPrivateTab = BrowserTab(
                title: "Private Tab",
                url: URL(string: "https://duckduckgo.com")!,
                urlString: "https://duckduckgo.com",
                isPrivate: true
            )
            privateTabs.append(defaultPrivateTab)
            activePrivateTabId = defaultPrivateTab.id
        }
    }

    private func saveTabs() {
        if let data = try? JSONEncoder().encode(tabs) {
            UserDefaults.standard.set(data, forKey: tabsStorageKey)
        }
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: historyStorageKey)
        }
    }

    private func saveBookmarks() {
        if let data = try? JSONEncoder().encode(bookmarks) {
            UserDefaults.standard.set(data, forKey: bookmarksStorageKey)
        }
    }

    private func loadPersistedState() {
        if let data = UserDefaults.standard.data(forKey: tabsStorageKey),
           let savedTabs = try? JSONDecoder().decode([BrowserTab].self, from: data),
           !savedTabs.isEmpty {
            self.tabs = savedTabs
            self.activeTabId = savedTabs.first?.id ?? UUID()
        }

        if let data = UserDefaults.standard.data(forKey: historyStorageKey),
           let savedHistory = try? JSONDecoder().decode([HistoryItem].self, from: data) {
            self.history = savedHistory
        }

        if let data = UserDefaults.standard.data(forKey: bookmarksStorageKey),
           let savedBookmarks = try? JSONDecoder().decode([BookmarkItem].self, from: data) {
            self.bookmarks = savedBookmarks
        } else {
            // Default starter bookmarks
            self.bookmarks = [
                BookmarkItem(title: "Apple Developer", url: URL(string: "https://developer.apple.com")!),
                BookmarkItem(title: "GitHub Gopeed", url: URL(string: "https://github.com/GopeedLab/gopeed")!),
                BookmarkItem(title: "Internet Archive", url: URL(string: "https://archive.org")!),
                BookmarkItem(title: "Open Source Audio/Video Test", url: URL(string: "https://test-streams.mux.dev")!)
            ]
        }
    }
}
