import SwiftUI
import QuickLook

public struct CategoryFilterButton: View {
    public let category: TaskCategory
    public let isSelected: Bool
    public let action: () -> Void

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: category.iconName)
                    .font(.caption)
                Text(category.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? category.color : Color.tertiarySystemFillColor)
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(20)
        }
    }
}

public struct FileRowItemView: View {
    public let file: LocalFileItem
    public let onPlay: () -> Void
    public let onDelete: () -> Void
    public let onShare: () -> Void
    public let onRename: () -> Void
    public let onSelect: () -> Void

    public var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(file.category.color.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: file.category.iconName)
                    .foregroundColor(file.category.color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(file.formattedSize)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(file.formattedDate)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if file.category == .video || file.category == .audio {
                Button(action: onPlay) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button(action: onShare) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .tint(.blue)

            Button(action: onRename) {
                Label("Rename", systemImage: "pencil")
            }
            .tint(.orange)
        }
    }
}

public struct FilesListView: View {
    @State private var selectedCategory: TaskCategory = .all
    @State private var searchText = ""
    @State private var files: [LocalFileItem] = []
    @State private var previewURL: URL?
    @State private var mediaPlayItem: LocalFileItem?
    @State private var fileToRename: LocalFileItem?
    @State private var renameText = ""
    @State private var showingRenameAlert = false
    @State private var fileToShare: URL?

    public init() {}

    private var filteredFiles: [LocalFileItem] {
        files.filter { file in
            let matchCat = (selectedCategory == .all) || (file.category == selectedCategory)
            if !matchCat { return false }
            if !searchText.isEmpty {
                return file.name.localizedCaseInsensitiveContains(searchText)
            }
            return true
        }
    }

    public var body: some View {
        NavigationStack {
            List {
                // iOS Files App banner (Google Chrome style)
                Section {
                    Button {
                        HapticManager.triggerImpact(.light)
                        FileStorageService.shared.revealInFilesApp()
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.blue.opacity(0.15))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "folder.badge.gearshape")
                                    .font(.system(size: 16))
                                    .foregroundColor(.blue)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Open in iOS Files App")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                Text("Browse in 'On My iPhone > Shift'")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Image(systemName: "arrow.up.forward.app")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }

                // Category Pills Carousel
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(TaskCategory.allCases) { cat in
                                CategoryFilterButton(category: cat, isSelected: selectedCategory == cat) {
                                    HapticManager.triggerImpact(.light)
                                    selectedCategory = cat
                                    loadFiles()
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }

                // File Items
                if filteredFiles.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "No Files in \(selectedCategory.displayName)",
                            systemImage: selectedCategory.iconName,
                            description: Text("Downloaded files in this category will be organized here.")
                        )
                    }
                } else {
                    Section {
                        ForEach(filteredFiles) { file in
                            FileRowItemView(
                                file: file,
                                onPlay: { mediaPlayItem = file },
                                onDelete: { deleteFile(file) },
                                onShare: { fileToShare = file.url },
                                onRename: {
                                    fileToRename = file
                                    renameText = file.name
                                    showingRenameAlert = true
                                },
                                onSelect: {
                                    if file.category == .video || file.category == .audio {
                                        mediaPlayItem = file
                                    } else {
                                        previewURL = file.url
                                    }
                                }
                            )
                        }
                    }
                }
            }
            .shiftListStyle()
            .navigationTitle("Files")
            .searchable(text: $searchText, prompt: "Search downloaded files")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        FileStorageService.shared.revealInFilesApp()
                    } label: {
                        Label("Files App", systemImage: "folder.badge.gearshape")
                    }
                }
            }
            .onAppear {
                loadFiles()
            }
            .sheet(item: $mediaPlayItem) { item in
                MediaPlayerView(fileURL: item.url, title: item.name)
            }
            .sheet(isPresented: Binding(
                get: { fileToShare != nil },
                set: { if !$0 { fileToShare = nil } }
            )) {
                if let shareURL = fileToShare {
                    #if canImport(UIKit)
                    ShareSheet(activityItems: [shareURL])
                    #else
                    Text("Sharing \(shareURL.lastPathComponent)")
                    #endif
                }
            }
            .alert("Rename File", isPresented: $showingRenameAlert) {
                TextField("File name", text: $renameText)
                Button("Cancel", role: .cancel) {}
                Button("Rename") {
                    if let item = fileToRename, !renameText.isEmpty {
                        _ = try? FileStorageService.shared.renameFile(at: item.url, newName: renameText)
                        loadFiles()
                    }
                }
            }
        }
    }

    private func loadFiles() {
        self.files = FileStorageService.shared.listFiles(in: selectedCategory)
    }

    private func deleteFile(_ item: LocalFileItem) {
        try? FileStorageService.shared.deleteFile(at: item.url)
        loadFiles()
    }
}
