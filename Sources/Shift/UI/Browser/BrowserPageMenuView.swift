import SwiftUI

public struct BrowserPageMenuView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject public var tabManager: BrowserTabManager
    public let tab: BrowserTab
    public let onFindOnPage: () -> Void
    public let onReload: () -> Void

    public init(
        tabManager: BrowserTabManager,
        tab: BrowserTab,
        onFindOnPage: @escaping () -> Void,
        onReload: @escaping () -> Void
    ) {
        self.tabManager = tabManager
        self.tab = tab
        self.onFindOnPage = onFindOnPage
        self.onReload = onReload
    }

    public var body: some View {
        NavigationStack {
            List {
                // Page Zoom Section
                Section {
                    HStack {
                        Button {
                            HapticManager.triggerImpact(.light)
                            tabManager.setZoom(for: tab.id, zoom: tab.pageZoom - 0.1)
                        } label: {
                            Image(systemName: "textformat.size.smaller")
                                .font(.headline)
                                .frame(width: 44, height: 32)
                        }
                        .disabled(tab.pageZoom <= 0.5)

                        Spacer()

                        Text("\(Int(tab.pageZoom * 100))%")
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.semibold)

                        Spacer()

                        Button {
                            HapticManager.triggerImpact(.light)
                            tabManager.setZoom(for: tab.id, zoom: tab.pageZoom + 0.1)
                        } label: {
                            Image(systemName: "textformat.size.larger")
                                .font(.headline)
                                .frame(width: 44, height: 32)
                        }
                        .disabled(tab.pageZoom >= 2.0)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Text & Page Zoom")
                }

                // Page Actions
                Section {
                    Button {
                        HapticManager.triggerImpact(.medium)
                        tabManager.toggleDesktopMode(for: tab.id)
                        onReload()
                        dismiss()
                    } label: {
                        Label(
                            tab.isDesktopMode ? "Request Mobile Website" : "Request Desktop Website",
                            systemImage: tab.isDesktopMode ? "iphone" : "desktopcomputer"
                        )
                        .foregroundColor(.primary)
                    }

                    Button {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            onFindOnPage()
                        }
                    } label: {
                        Label("Find on Page", systemImage: "magnifyingglass")
                            .foregroundColor(.primary)
                    }

                    Button {
                        HapticManager.triggerImpact(.light)
                        tabManager.toggleBookmark(title: tab.title, url: tab.url)
                    } label: {
                        Label(
                            tabManager.isBookmarked(url: tab.url) ? "Remove Bookmark" : "Add Bookmark",
                            systemImage: tabManager.isBookmarked(url: tab.url) ? "bookmark.fill" : "bookmark"
                        )
                        .foregroundColor(tabManager.isBookmarked(url: tab.url) ? .blue : .primary)
                    }

                    Button {
                        onReload()
                        dismiss()
                    } label: {
                        Label("Reload Page", systemImage: "arrow.clockwise")
                            .foregroundColor(.primary)
                    }
                }

                // Security & Privacy Info
                Section("Privacy & Protection") {
                    HStack {
                        Label("Content & Ad Blocker", systemImage: "shield.checkered")
                        Spacer()
                        Text("Active")
                            .font(.subheadline)
                            .foregroundColor(.green)
                    }

                    HStack {
                        Label("Browsing Mode", systemImage: tab.isPrivate ? "lock.shield.fill" : "globe")
                        Spacer()
                        Text(tab.isPrivate ? "Private" : "Standard")
                            .font(.subheadline)
                            .foregroundColor(tab.isPrivate ? .purple : .secondary)
                    }
                }
            }
            .shiftListStyle()
            .navigationTitle(tab.hostDomain)
            .shiftInlineTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
