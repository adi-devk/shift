import SwiftUI

public struct DiagnosticsLogView: View {
    @ObservedObject private var logger = ShiftLogger.shared
    @State private var selectedLevel: LogLevel? = nil
    @State private var selectedCategory: LogCategory? = nil
    @State private var searchQuery: String = ""
    @State private var showingClearAlert: Bool = false
    @State private var showingShareSheet: Bool = false
    @State private var shareURL: URL?

    public init() {}

    private var filteredEntries: [LogEntry] {
        logger.entries.reversed().filter { entry in
            if let level = selectedLevel, entry.level != level {
                return false
            }
            if let category = selectedCategory, entry.category != category {
                return false
            }
            if !searchQuery.isEmpty {
                return entry.message.localizedCaseInsensitiveContains(searchQuery) ||
                       entry.file.localizedCaseInsensitiveContains(searchQuery)
            }
            return true
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Filter Bar
            VStack(spacing: 8) {
                // Log Level Selector
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterPill(
                            title: "All Levels (\(logger.entries.count))",
                            icon: "list.bullet",
                            isSelected: selectedLevel == nil,
                            color: .blue
                        ) {
                            selectedLevel = nil
                        }

                        FilterPill(
                            title: "Errors",
                            icon: LogLevel.error.icon,
                            isSelected: selectedLevel == .error,
                            color: .red
                        ) {
                            selectedLevel = (selectedLevel == .error) ? nil : .error
                        }

                        FilterPill(
                            title: "Warnings",
                            icon: LogLevel.warning.icon,
                            isSelected: selectedLevel == .warning,
                            color: .orange
                        ) {
                            selectedLevel = (selectedLevel == .warning) ? nil : .warning
                        }

                        FilterPill(
                            title: "Info",
                            icon: LogLevel.info.icon,
                            isSelected: selectedLevel == .info,
                            color: .green
                        ) {
                            selectedLevel = (selectedLevel == .info) ? nil : .info
                        }

                        FilterPill(
                            title: "Debug",
                            icon: LogLevel.debug.icon,
                            isSelected: selectedLevel == .debug,
                            color: .purple
                        ) {
                            selectedLevel = (selectedLevel == .debug) ? nil : .debug
                        }
                    }
                    .padding(.horizontal, 14)
                }

                // Category Selector
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        CategoryPill(title: "All Categories", isSelected: selectedCategory == nil) {
                            selectedCategory = nil
                        }

                        ForEach(LogCategory.allCases, id: \.self) { cat in
                            CategoryPill(title: cat.rawValue, isSelected: selectedCategory == cat) {
                                selectedCategory = (selectedCategory == cat) ? nil : cat
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                }
            }
            .padding(.vertical, 8)
            .background(Color.secondaryGroupedBg)

            Divider()

            // Log Items List
            if filteredEntries.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 44))
                        .foregroundColor(.secondary)
                    Text("No Matching Log Entries")
                        .font(.headline)
                    Text("Events and diagnostic traces will appear here automatically.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List {
                    ForEach(filteredEntries) { entry in
                        LogRowView(entry: entry)
                    }
                }
                .shiftListStyle()
            }
        }
        .searchable(text: $searchQuery, prompt: "Search logs or file names")
        .navigationTitle("Diagnostics & Logs")
        .shiftInlineTitle()
        .toolbar {
            #if os(iOS)
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button {
                        HapticManager.triggerImpact(.light)
                        let text = logger.exportLogsText()
                        ClipboardHelper.copy(text)
                    } label: {
                        Label("Copy All to Clipboard", systemImage: "doc.on.doc")
                    }

                    Button {
                        HapticManager.triggerImpact(.light)
                        shareURL = logger.getLogFileURL()
                        showingShareSheet = true
                    } label: {
                        Label("Export & Share Log File", systemImage: "square.and.arrow.up")
                    }

                    Divider()

                    Button(role: .destructive) {
                        showingClearAlert = true
                    } label: {
                        Label("Clear All Logs", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            #else
            ToolbarItem(placement: .confirmationAction) {
                Button("Export") {
                    shareURL = logger.getLogFileURL()
                    showingShareSheet = true
                }
            }
            #endif
        }
        .confirmationDialog("Clear All Logs?", isPresented: $showingClearAlert, titleVisibility: .visible) {
            Button("Clear All", role: .destructive) {
                HapticManager.triggerNotification(.success)
                logger.clearLogs()
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showingShareSheet) {
            if let url = shareURL {
                #if canImport(UIKit)
                ShareSheet(activityItems: [url])
                #else
                Text("Sharing \(url.lastPathComponent)")
                #endif
            }
        }
    }
}

// MARK: - Filter Pill
struct FilterPill: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isSelected ? color.opacity(0.18) : Color.tertiarySystemFillColor)
            .foregroundColor(isSelected ? color : .primary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isSelected ? color : Color.clear, lineWidth: 1.2)
            )
        }
        .buttonStyle(.plain)
    }
}

struct CategoryPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isSelected ? Color.blue.opacity(0.15) : Color.tertiarySystemFillColor)
                .foregroundColor(isSelected ? .blue : .secondary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Log Row
struct LogRowView: View {
    let entry: LogEntry

    private var levelColor: Color {
        switch entry.level {
        case .debug: return .purple
        case .info: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: entry.level.icon)
                    .foregroundColor(levelColor)
                    .font(.system(size: 12))

                Text(entry.level.rawValue)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(levelColor)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .background(levelColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 3))

                Text(entry.category.rawValue)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .background(Color.tertiarySystemFillColor)
                    .clipShape(RoundedRectangle(cornerRadius: 3))

                Spacer()

                Text(entry.timestamp, style: .time)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Text(entry.message)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.primary)
                .textSelection(.enabled)

            HStack {
                Text("\(entry.file):\(entry.line)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.8))
                Spacer()
            }
        }
        .padding(.vertical, 2)
    }
}
