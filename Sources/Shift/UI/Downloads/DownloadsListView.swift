import SwiftUI

public enum DownloadFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case active = "Active"
    case completed = "Done"
    case paused = "Paused"

    public var id: String { rawValue }
}

public struct DownloadsListView: View {
    @ObservedObject public var engine: ShiftDownloadEngine

    @State private var selectedFilter: DownloadFilter = .all
    @State private var searchText = ""
    @State private var showingNewDownloadSheet = false
    @State private var showingBatchDownloadSheet = false
    @State private var initialNewDownloadURL = ""
    @State private var selectedTaskForURLChange: DownloadTask? = nil
    @State private var navigationPath = NavigationPath()

    public init(engine: ShiftDownloadEngine) {
        self.engine = engine
    }

    private var activeCount: Int {
        engine.tasks.filter { $0.status == .downloading || $0.status == .connecting }.count
    }

    private var pausedCount: Int {
        engine.tasks.filter { $0.status == .paused || $0.status == .failed }.count
    }

    private var completedCount: Int {
        engine.tasks.filter { $0.status == .completed }.count
    }

    private var filteredTasks: [DownloadTask] {
        engine.tasks.filter { task in
            let matchesFilter: Bool
            switch selectedFilter {
            case .all:
                matchesFilter = true
            case .active:
                matchesFilter = task.status == .downloading || task.status == .connecting || task.status == .queued
            case .completed:
                matchesFilter = task.status == .completed
            case .paused:
                matchesFilter = task.status == .paused || task.status == .failed
            }

            if !matchesFilter { return false }

            if !searchText.isEmpty {
                return task.fileName.localizedCaseInsensitiveContains(searchText) ||
                       task.url.absoluteString.localizedCaseInsensitiveContains(searchText)
            }
            return true
        }
    }

    public var body: some View {
        NavigationStack(path: $navigationPath) {
            List {
                // Total Bandwidth & Global Activity Header Card
                Section {
                    VStack(spacing: 12) {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(engine.globalDownloadSpeed > 0 ? Color.blue.opacity(0.15) : Color.secondary.opacity(0.12))
                                    .frame(width: 48, height: 48)
                                Image(systemName: engine.globalDownloadSpeed > 0 ? "arrow.down.circle.fill" : "arrow.down.circle")
                                    .font(.system(size: 26))
                                    .foregroundColor(engine.globalDownloadSpeed > 0 ? .blue : .secondary)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text("TOTAL BANDWIDTH")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.secondary)
                                    
                                    if engine.globalDownloadSpeed > 0 {
                                        Circle()
                                            .fill(Color.green)
                                            .frame(width: 7, height: 7)
                                    }
                                }

                                Text(engine.globalDownloadSpeed > 0 
                                     ? ByteCountFormatter.formatSpeed(bytesPerSecond: engine.globalDownloadSpeed) 
                                     : "0 B/s Idle")
                                    .font(.system(.title2, design: .monospaced))
                                    .fontWeight(.bold)
                                    .foregroundColor(engine.globalDownloadSpeed > 0 ? .blue : .primary)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 4) {
                                HStack(spacing: 4) {
                                    Image(systemName: "bolt.fill")
                                        .font(.caption2)
                                    Text("\(activeCount) Active")
                                        .font(.subheadline)
                                        .fontWeight(.bold)
                                }
                                .foregroundColor(activeCount > 0 ? .blue : .secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(activeCount > 0 ? Color.blue.opacity(0.12) : Color.tertiarySystemFillColor)
                                .cornerRadius(8)

                                Text("\(engine.tasks.count) Total Tasks")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Filter Segment Control
                Section {
                    Picker("Filter", selection: $selectedFilter) {
                        ForEach(DownloadFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }

                // Download Tasks List
                if filteredTasks.isEmpty {
                    Section {
                        ContentUnavailableView(
                            emptyTitle,
                            systemImage: emptyIcon,
                            description: Text(emptyDescription)
                        )
                    }
                } else {
                    Section {
                        ForEach(filteredTasks) { task in
                            NavigationLink(value: task.id) {
                                DownloadRowView(
                                    task: task,
                                    onPauseResume: {
                                        if task.status == .downloading {
                                            engine.pauseTask(id: task.id)
                                        } else {
                                            engine.resumeTask(id: task.id)
                                        }
                                    },
                                    onDelete: {
                                        engine.deleteTask(id: task.id, deleteFile: true)
                                    }
                                )
                                .contextMenu {
                                    if task.status != .completed {
                                        Button {
                                            selectedTaskForURLChange = task
                                        } label: {
                                            Label("Change URL / Refresh Link", systemImage: "link.badge.plus")
                                        }
                                    }

                                    Button {
                                        ClipboardHelper.copy(task.url.absoluteString)
                                    } label: {
                                        Label("Copy Download URL", systemImage: "doc.on.doc")
                                    }

                                    Button(role: .destructive) {
                                        engine.deleteTask(id: task.id, deleteFile: true)
                                    } label: {
                                        Label("Delete Download", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .shiftListStyle()
            .navigationTitle("Downloads")
            .navigationDestination(for: UUID.self) { taskId in
                DownloadDetailView(engine: engine, taskId: taskId)
            }
            .searchable(text: $searchText, prompt: "Search downloads")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Menu {
                        Button {
                            engine.clearCompleted()
                        } label: {
                            Label("Clear Completed", systemImage: "xmark.circle")
                        }

                        Button {
                            for t in engine.tasks where t.status == .downloading {
                                engine.pauseTask(id: t.id)
                            }
                        } label: {
                            Label("Pause All", systemImage: "pause.circle")
                        }

                        Button {
                            for t in engine.tasks where t.status == .paused {
                                engine.resumeTask(id: t.id)
                            }
                        } label: {
                            Label("Resume All", systemImage: "play.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            initialNewDownloadURL = ""
                            showingNewDownloadSheet = true
                        } label: {
                            Label("New URL Download", systemImage: "link.badge.plus")
                        }

                        Button {
                            showingBatchDownloadSheet = true
                        } label: {
                            Label("Batch Pattern Download", systemImage: "square.grid.3x3.topleft.filled")
                        }

                        Button {
                            if let paste = ClipboardHelper.text, !paste.isEmpty {
                                initialNewDownloadURL = paste.trimmingCharacters(in: .whitespacesAndNewlines)
                            } else {
                                initialNewDownloadURL = ""
                            }
                            showingNewDownloadSheet = true
                        } label: {
                            Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                    }
                }
            }
            .sheet(isPresented: $showingNewDownloadSheet) {
                NewDownloadSheet(engine: engine, initialURL: initialNewDownloadURL)
            }
            .sheet(isPresented: $showingBatchDownloadSheet) {
                BatchDownloadSheet(engine: engine)
            }
            .sheet(item: $selectedTaskForURLChange) { task in
                ChangeURLSheet(engine: engine, taskId: task.id, currentURL: task.url.absoluteString)
            }
        }
    }

    private var emptyTitle: String {
        switch selectedFilter {
        case .all: return "No Downloads"
        case .active: return "No Active Downloads"
        case .completed: return "No Completed Downloads"
        case .paused: return "No Paused Downloads"
        }
    }

    private var emptyIcon: String {
        switch selectedFilter {
        case .all: return "arrow.down.circle"
        case .active: return "network"
        case .completed: return "checkmark.circle"
        case .paused: return "pause.circle"
        }
    }

    private var emptyDescription: String {
        switch selectedFilter {
        case .all: return "Tap + to start a new multi-threaded download or browse the web."
        case .active: return "There are currently no running download tasks."
        case .completed: return "Completed files will appear here and in your Files tab."
        case .paused: return "Paused or failed tasks will appear here."
        }
    }
}
