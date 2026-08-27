import SwiftUI

public struct DownloadRowView: View {
    public let task: DownloadTask
    public let onPauseResume: () -> Void
    public let onDelete: () -> Void

    public init(
        task: DownloadTask,
        onPauseResume: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.task = task
        self.onPauseResume = onPauseResume
        self.onDelete = onDelete
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(task.category.color.opacity(0.15))
                        .frame(width: 42, height: 42)
                    Image(systemName: task.category.iconName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(task.category.color)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(task.fileName)
                        .font(.headline)
                        .lineLimit(1)
                        .foregroundColor(.primary)

                    HStack(spacing: 6) {
                        StatusPill(status: task.status)
                        
                        if task.maxConnections > 1 && task.protocolType == .http {
                            Text("\(task.segments.count) parts")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.tertiarySystemFillColor)
                                .cornerRadius(4)
                        }

                        Spacer()

                        if task.status == .downloading {
                            Text(task.formattedSpeed)
                                .font(.system(.caption, design: .monospaced))
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
                        }
                    }
                }
            }

            if task.segments.count > 1 && task.status == .downloading {
                MultiSegmentProgressBar(segments: task.segments, height: 6)
            } else {
                ProgressView(value: task.progress)
                    .tint(task.status.color)
                    .scaleEffect(x: 1, y: 1.2, anchor: .center)
            }

            HStack {
                Text("\(task.formattedDownloadedSize) / \(task.formattedTotalSize)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)

                Spacer()

                if task.status == .downloading {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 10))
                        Text(task.formattedETA)
                            .font(.caption2)
                    }
                    .foregroundColor(.secondary)
                } else if task.status == .completed {
                    Text("Completed")
                        .font(.caption2)
                        .foregroundColor(.green)
                } else if task.status == .paused {
                    Text("Paused")
                        .font(.caption2)
                        .foregroundColor(.orange)
                } else if task.status == .failed {
                    Text(task.errorDescription ?? "Failed")
                        .font(.caption2)
                        .foregroundColor(.red)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            if task.status == .downloading {
                Button(action: onPauseResume) {
                    Label("Pause", systemImage: "pause.fill")
                }
                .tint(.orange)
            } else if task.status == .paused || task.status == .failed {
                Button(action: onPauseResume) {
                    Label("Resume", systemImage: "play.fill")
                }
                .tint(.blue)
            }
        }
        .contextMenu {
            if task.status == .downloading {
                Button(action: onPauseResume) {
                    Label("Pause Download", systemImage: "pause.fill")
                }
            } else if task.status == .paused || task.status == .failed {
                Button(action: onPauseResume) {
                    Label("Resume Download", systemImage: "play.fill")
                }
            }

            Button {
                ClipboardHelper.copy(task.url.absoluteString)
            } label: {
                Label("Copy Download URL", systemImage: "doc.on.doc")
            }

            Divider()

            Button(role: .destructive, action: onDelete) {
                Label("Delete Download", systemImage: "trash")
            }
        }
    }
}
