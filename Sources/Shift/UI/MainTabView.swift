import SwiftUI

public struct MainTabView: View {
    @ObservedObject public var engine: ShiftDownloadEngine

    @State private var selectedTab = 0

    public init(engine: ShiftDownloadEngine) {
        self.engine = engine
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            DownloadsListView(engine: engine)
                .tabItem {
                    Label("Downloads", systemImage: "arrow.down.circle.fill")
                }
                .badge(engine.tasks.filter { $0.status == .downloading }.count)
                .tag(0)

            BrowserView(engine: engine)
                .tabItem {
                    Label("Browser", systemImage: "safari.fill")
                }
                .tag(1)

            FilesListView()
                .tabItem {
                    Label("Files", systemImage: "folder.fill")
                }
                .tag(2)

            SettingsView(engine: engine)
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(3)
        }
        .tint(.blue)
    }
}
