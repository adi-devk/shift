import SwiftUI

public struct DownloadDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject public var engine: ShiftDownloadEngine
    public let taskId: UUID

    @State private var showingShareSheet = false
    @State private var showingCopiedAlert = false
    @State private var showingChangeURLSheet = false
    @State private var previewItemURL: URL?

    public init(engine: ShiftDownloadEngine, taskId: UUID) {
        self.engine = engine
        self.taskId = taskId
    }

    private var task: DownloadTask? {
        engine.tasks.first(where: { $0.id == taskId })
    }

    public var body: some View {
        Group {
            if let task = task {
                List {
                    // Header Overview Card
                    Section {
                        VStack(spacing: 16) {
                            HStack(spacing: 14) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(task.category.color.opacity(0.15))
                                        .frame(width: 56, height: 56)
                                    Image(systemName: task.category.iconName)
                                        .font(.system(size: 26, weight: .semibold))
                                        .foregroundColor(task.category.color)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(task.fileName)
                                        .font(.title3)
                                        .fontWeight(.bold)
                                        .lineLimit(2)

                                    HStack {
                                        StatusPill(status: task.status)
                                        CategoryBadge(category: task.category)
                                    }
                                }
                            }

                            // Progress
                            VStack(spacing: 6) {
                                if !task.segments.isEmpty {
                                    MultiSegmentProgressBar(segments: task.segments, height: 10)
                                } else {
                                    ProgressView(value: task.progress)
                                        .tint(task.status.color)
                                }

                                HStack {
                                    Text("\(Int(task.progress * 100))%")
                                        .font(.system(.subheadline, design: .monospaced))
                                        .fontWeight(.bold)
                                    Spacer()
                                    Text("\(task.formattedDownloadedSize) of \(task.formattedTotalSize)")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            }

                            // Action buttons
                            HStack(spacing: 12) {
                                if task.status == .downloading {
                                    Button {
                                        HapticManager.triggerImpact(.medium)
                                        engine.pauseTask(id: task.id)
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "pause.fill")
                                                .font(.system(size: 14, weight: .bold))
                                            Text("Pause")
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.orange)
                                } else if task.status == .paused || task.status == .failed {
                                    Button {
                                        HapticManager.triggerImpact(.medium)
                                        engine.resumeTask(id: task.id)
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "play.fill")
                                                .font(.system(size: 14, weight: .bold))
                                            Text(task.status == .failed ? "Retry" : "Resume")
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.blue)
                                }

                                Button {
                                    showingShareSheet = true
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "square.and.arrow.up")
                                            .font(.system(size: 14, weight: .semibold))
                                        Text("Share")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(.vertical, 6)
                    }

                    // Live Throughput Chart
                    if task.status == .downloading {
                        Section("Real-time Performance") {
                            SpeedChartView(history: task.speedHistory, currentSpeed: task.speedBytesPerSec)
                                .listRowInsets(EdgeInsets())
                                .padding(.vertical, 4)
                        }
                    }

                    // Multi-Thread Segment Inspection
                    if !task.segments.isEmpty {
                        Section("Active Threads & Segments (\(task.segments.count) Connections)") {
                            DetailedSegmentGridView(segments: task.segments)
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                    }

                    // Transfer Details
                    Section("Transfer Statistics") {
                        LabeledContent("Current Speed", value: task.formattedSpeed)
                        LabeledContent("Average Speed", value: task.formattedAverageSpeed)
                        LabeledContent("Time Remaining (ETA)", value: task.formattedETA)
                        LabeledContent("Protocol", value: task.protocolType.rawValue)
                        LabeledContent("Connections", value: "\(task.maxConnections) threads")
                        LabeledContent("Resume Supported", value: task.supportsResume ? "Yes" : "No")
                        if let etag = task.etag {
                            LabeledContent("ETag", value: etag)
                        }
                    }

                    // Connection Details
                    Section("Connection Details") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Source URL")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(task.url.absoluteString)
                                .font(.system(.footnote, design: .monospaced))
                                .textSelection(.enabled)
                        }

                        if let ua = task.userAgent, !ua.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("User-Agent")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(ua)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Destination Path")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(task.destinationPath)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }

                    // Actions
                    Section {
                        if task.status != .completed {
                            Button {
                                showingChangeURLSheet = true
                            } label: {
                                Label("Change Download URL / Refresh Link", systemImage: "link.badge.plus")
                            }
                        }

                        Button {
                            ClipboardHelper.copy(task.url.absoluteString)
                            showingCopiedAlert = true
                        } label: {
                            Label("Copy Download URL", systemImage: "doc.on.doc")
                        }

                        Button {
                            let url = URL(fileURLWithPath: task.destinationPath)
                            FileStorageService.shared.revealInFilesApp(url: url)
                        } label: {
                            Label("Reveal in iOS Files App", systemImage: "folder")
                        }

                        if task.status == .completed {
                            Button {
                                let url = URL(fileURLWithPath: task.destinationPath)
                                #if canImport(Photos) && os(iOS)
                                FileStorageService.shared.exportVideoToCameraRoll(fileURL: url) { success, _ in
                                    if success {
                                        HapticManager.triggerNotification(.success)
                                    }
                                }
                                #endif
                            } label: {
                                Label("Save to Photos Library", systemImage: "photo.badge.arrow.down")
                            }
                        }

                        Button(role: .destructive) {
                            engine.deleteTask(id: task.id, deleteFile: true)
                            dismiss()
                        } label: {
                            Label("Delete Download & File", systemImage: "trash")
                        }
                    }
                }
                .shiftListStyle()
                .navigationTitle("Download Details")
                .navigationBarBackButtonHidden(true)
                .toolbar {
                    #if os(iOS)
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            dismiss()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.backward")
                                    .font(.system(size: 16, weight: .semibold))
                                Text("Downloads")
                                    .font(.body)
                            }
                            .foregroundColor(.blue)
                        }
                    }
                    #else
                    ToolbarItem(placement: .navigation) {
                        Button {
                            dismiss()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.backward")
                                Text("Downloads")
                            }
                        }
                    }
                    #endif
                }
                .sheet(isPresented: $showingShareSheet) {
                    if let fileURL = URL(string: "file://" + task.destinationPath) {
                        #if canImport(UIKit)
                        ShareSheet(activityItems: [fileURL])
                        #else
                        Text("Sharing \(fileURL.lastPathComponent)")
                        #endif
                    }
                }
                .sheet(isPresented: $showingChangeURLSheet) {
                    ChangeURLSheet(engine: engine, taskId: task.id, currentURL: task.url.absoluteString)
                }
            } else {
                VStack(spacing: 16) {
                    ContentUnavailableView("Task Removed", systemImage: "trash", description: Text("This download task was completed or removed."))
                    Button("Back to Downloads") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .navigationTitle("Details")
                .navigationBarBackButtonHidden(true)
                .toolbar {
                    #if os(iOS)
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            dismiss()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.backward")
                                    .font(.system(size: 16, weight: .semibold))
                                Text("Downloads")
                            }
                            .foregroundColor(.blue)
                        }
                    }
                    #else
                    ToolbarItem(placement: .navigation) {
                        Button {
                            dismiss()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.backward")
                                Text("Downloads")
                            }
                        }
                    }
                    #endif
                }
            }
        }
    }
}
