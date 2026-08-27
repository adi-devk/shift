import SwiftUI

public struct BookmarksHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject public var tabManager: BrowserTabManager
    public let onSelectURL: (URL) -> Void

    @State private var selectedSegment = 0 // 0 = Bookmarks, 1 = History
    @State private var searchQuery = ""
    @State private var showingClearConfirmation = false
    @State private var showingAddBookmarkAlert = false
    @State private var newBookmarkTitle = ""
    @State private var newBookmarkURLString = ""

    public init(
        tabManager: BrowserTabManager,
        onSelectURL: @escaping (URL) -> Void
    ) {
        self.tabManager = tabManager
        self.onSelectURL = onSelectURL
    }

    private var filteredBookmarks: [BookmarkItem] {
        if searchQuery.isEmpty {
            return tabManager.bookmarks
        }
        return tabManager.bookmarks.filter {
            $0.title.localizedCaseInsensitiveContains(searchQuery) ||
            $0.url.absoluteString.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    private var filteredHistory: [HistoryItem] {
        if searchQuery.isEmpty {
            return tabManager.history
        }
        return tabManager.history.filter {
            $0.title.localizedCaseInsensitiveContains(searchQuery) ||
            $0.url.absoluteString.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    public var body: some View {
        NavigationStack {
            List {
                // Segmented Selector
                Picker("Section", selection: $selectedSegment) {
                    Label("Bookmarks", systemImage: "book").tag(0)
                    Label("History", systemImage: "clock").tag(1)
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))

                if selectedSegment == 0 {
                    // MARK: - Bookmarks Tab
                    if filteredBookmarks.isEmpty {
                        Section {
                            VStack(spacing: 8) {
                                Image(systemName: "bookmark")
                                    .font(.system(size: 32))
                                    .foregroundColor(.secondary)
                                Text("No Bookmarks")
                                    .font(.headline)
                                Text("Websites you bookmark will appear here.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                        }
                    } else {
                        Section {
                            ForEach(filteredBookmarks) { item in
                                Button {
                                    HapticManager.triggerImpact(.light)
                                    onSelectURL(item.url)
                                    dismiss()
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "bookmark.fill")
                                            .foregroundColor(.blue)
                                            .font(.system(size: 16))

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.title)
                                                .font(.body)
                                                .foregroundColor(.primary)
                                                .lineLimit(1)
                                            Text(item.url.host ?? item.url.absoluteString)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                            .onDelete { indices in
                                for idx in indices {
                                    let item = filteredBookmarks[idx]
                                    tabManager.deleteBookmark(id: item.id)
                                }
                            }
                        }
                    }
                } else {
                    // MARK: - History Tab
                    if filteredHistory.isEmpty {
                        Section {
                            VStack(spacing: 8) {
                                Image(systemName: "clock")
                                    .font(.system(size: 32))
                                    .foregroundColor(.secondary)
                                Text("No History")
                                    .font(.headline)
                                Text("Pages you visit will be shown here.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                        }
                    } else {
                        Section {
                            ForEach(filteredHistory) { item in
                                Button {
                                    HapticManager.triggerImpact(.light)
                                    onSelectURL(item.url)
                                    dismiss()
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "globe")
                                            .foregroundColor(.secondary)
                                            .font(.system(size: 16))

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.displayTitle)
                                                .font(.body)
                                                .foregroundColor(.primary)
                                                .lineLimit(1)
                                            HStack {
                                                Text(item.url.host ?? item.url.absoluteString)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                    .lineLimit(1)
                                                Spacer()
                                                Text(item.visitedAt, style: .time)
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                            .onDelete { indices in
                                for idx in indices {
                                    let item = filteredHistory[idx]
                                    tabManager.history.removeAll(where: { $0.id == item.id })
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchQuery, prompt: selectedSegment == 0 ? "Search Bookmarks" : "Search History")
            .shiftListStyle()
            .navigationTitle(selectedSegment == 0 ? "Bookmarks" : "History")
            .shiftInlineTitle()
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) {
                    if selectedSegment == 1 && !tabManager.history.isEmpty {
                        Button("Clear") {
                            showingClearConfirmation = true
                        }
                        .foregroundColor(.red)
                    }
                }
                #else
                ToolbarItem(placement: .navigation) {
                    if selectedSegment == 1 && !tabManager.history.isEmpty {
                        Button("Clear") {
                            showingClearConfirmation = true
                        }
                        .foregroundColor(.red)
                    }
                }
                #endif

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Clear Browsing History", isPresented: $showingClearConfirmation, titleVisibility: .visible) {
                Button("All History", role: .destructive) {
                    HapticManager.triggerNotification(.success)
                    tabManager.clearHistory()
                }
                Button("Today Only", role: .destructive) {
                    HapticManager.triggerNotification(.success)
                    let startOfDay = Calendar.current.startOfDay(for: Date())
                    tabManager.clearHistory(olderThan: startOfDay)
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}
