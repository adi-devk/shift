import SwiftUI
#if canImport(WidgetKit)
import WidgetKit

public struct ShiftEntry: TimelineEntry {
    public let date: Date
    public let snapshot: WidgetDataSnapshot

    public init(date: Date, snapshot: WidgetDataSnapshot) {
        self.date = date
        self.snapshot = snapshot
    }
}

public struct ShiftTimelineProvider: TimelineProvider {
    public init() {}

    public func placeholder(in context: Context) -> ShiftEntry {
        ShiftEntry(date: Date(), snapshot: .empty)
    }

    public func getSnapshot(in context: Context, completion: @escaping (ShiftEntry) -> Void) {
        let snapshot = WidgetDataManager.shared.loadSnapshot()
        completion(ShiftEntry(date: Date(), snapshot: snapshot))
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<ShiftEntry>) -> Void) {
        let snapshot = WidgetDataManager.shared.loadSnapshot()
        let currentDate = Date()

        if snapshot.totalActiveCount > 0 && snapshot.globalSpeedBytes > 0 {
            // Extrapolate timeline entries across 60 seconds (12 steps of 5s)
            // This ensures smooth, live ticking even if iOS defers background reloads!
            var entries: [ShiftEntry] = []
            let speed = snapshot.globalSpeedBytes
            let totalSize = snapshot.totalFileSizeBytes

            for step in 0..<12 {
                let stepDate = currentDate.addingTimeInterval(Double(step * 5))
                let addedBytes = Int64(step * 5) * speed
                let simulatedDownloaded = totalSize > 0 ? min(totalSize, snapshot.totalDownloadedBytes + addedBytes) : (snapshot.totalDownloadedBytes + addedBytes)
                let simulatedProgress = totalSize > 0 ? Double(simulatedDownloaded) / Double(totalSize) : snapshot.overallProgress

                let simulatedSnapshot = WidgetDataSnapshot(
                    activeTasks: snapshot.activeTasks,
                    totalActiveCount: snapshot.totalActiveCount,
                    overallProgress: min(1.0, simulatedProgress),
                    globalSpeedFormatted: snapshot.globalSpeedFormatted,
                    globalSpeedBytes: speed,
                    totalDownloadedFormatted: ByteCountFormatter.formatBytes(simulatedDownloaded),
                    totalSizeFormatted: snapshot.totalSizeFormatted,
                    totalDownloadedBytes: simulatedDownloaded,
                    totalFileSizeBytes: totalSize,
                    lastUpdated: stepDate
                )
                entries.append(ShiftEntry(date: stepDate, snapshot: simulatedSnapshot))
            }

            let nextUpdate = currentDate.addingTimeInterval(30)
            let timeline = Timeline(entries: entries, policy: .after(nextUpdate))
            completion(timeline)
        } else {
            let entry = ShiftEntry(date: currentDate, snapshot: snapshot)
            let refreshSeconds = snapshot.totalActiveCount > 0 ? 5 : 300
            let nextUpdate = currentDate.addingTimeInterval(Double(refreshSeconds))
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            completion(timeline)
        }
    }
}

public struct ShiftWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    public var entry: ShiftEntry

    public init(entry: ShiftEntry) {
        self.entry = entry
    }

    public var body: some View {
        Group {
            switch family {
            case .systemSmall:
                SmallWidgetView(snapshot: entry.snapshot)
            case .systemMedium:
                MediumWidgetView(snapshot: entry.snapshot)
            default:
                LargeWidgetView(snapshot: entry.snapshot)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(iOS)
        .containerBackground(for: .widget) {
            Color(uiColor: .systemBackground)
        }
        #endif
    }
}

// MARK: - Small Widget (Edge-to-Edge Compact Overall Progress & Speed)
struct SmallWidgetView: View {
    let snapshot: WidgetDataSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 5) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundColor(.blue)
                    .font(.system(size: 13, weight: .semibold))
                Text("Shift")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                if snapshot.totalActiveCount > 0 {
                    Text("\(snapshot.totalActiveCount) Active")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(Color.blue.opacity(0.15))
                        .foregroundColor(.blue)
                        .clipShape(Capsule())
                }
            }

            Spacer()

            if snapshot.totalActiveCount > 0 {
                // Circular Progress Ring & Live Stats
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .stroke(Color.secondary.opacity(0.18), lineWidth: 4.5)
                        Circle()
                            .trim(from: 0.0, to: CGFloat(max(0.03, snapshot.overallProgress)))
                            .stroke(
                                LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing),
                                style: StrokeStyle(lineWidth: 4.5, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))

                        Text("\(Int(snapshot.overallProgress * 100))%")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .frame(width: 46, height: 46)

                    VStack(alignment: .leading, spacing: 2.5) {
                        Text(snapshot.globalSpeedFormatted)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.blue)
                            .lineLimit(1)

                        if let top = snapshot.activeTasks.first {
                            Text(top.fileName)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.primary)
                                .lineLimit(1)

                            Text(top.etaFormatted)
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } else {
                VStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 26))
                        .foregroundColor(.green)
                    Text("All Done")
                        .font(.system(size: 12, weight: .bold))
                    Text("No active tasks")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
    }
}

// MARK: - Medium Widget (Wide Multi-Metric Dashboard)
struct MediumWidgetView: View {
    let snapshot: WidgetDataSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundColor(.blue)
                    Text("Shift Downloads")
                        .font(.subheadline)
                        .fontWeight(.bold)
                }
                Spacer()
                if snapshot.totalActiveCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.caption2)
                        Text(snapshot.globalSpeedFormatted)
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(.bold)
                    }
                    .foregroundColor(.blue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.12))
                    .clipShape(Capsule())
                }
            }

            Spacer(minLength: 0)

            if snapshot.totalActiveCount > 0, let top = snapshot.activeTasks.first {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Image(systemName: top.categoryIcon)
                            .foregroundColor(.blue)
                            .font(.caption)
                        Text(top.fileName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                        Spacer()
                        Text(top.etaFormatted)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    // Progress Bar
                    ProgressView(value: top.progress)
                        .tint(.blue)

                    HStack {
                        Text("\(top.downloadedFormatted) / \(top.totalFormatted)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(top.progress * 100))% • \(top.speedFormatted)")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                    }
                }

                // Overall queue footer if multiple downloads active
                if snapshot.totalActiveCount > 1 {
                    HStack {
                        Text("Queue (\(snapshot.totalActiveCount) active):")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Total: \(Int(snapshot.overallProgress * 100))%")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.primary)
                    }
                }
            } else {
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.green)
                        Text("All Downloads Completed")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("New downloads will be tracked automatically.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
    }
}

// MARK: - Large Widget (Multi-Task List)
struct LargeWidgetView: View {
    let snapshot: WidgetDataSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundColor(.blue)
                Text("Shift Dashboard")
                    .font(.headline)
                    .fontWeight(.bold)
                Spacer()
                Text(snapshot.globalSpeedFormatted)
                    .font(.system(.subheadline, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
            }

            Divider()

            if snapshot.activeTasks.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No Active Downloads")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("Active downloads will appear here in real-time.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ForEach(snapshot.activeTasks.prefix(3)) { task in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: task.categoryIcon)
                                .foregroundColor(.blue)
                                .font(.caption2)
                            Text(task.fileName)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .lineLimit(1)
                            Spacer()
                            Text(task.speedFormatted)
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
                        }

                        ProgressView(value: task.progress)
                            .tint(.blue)

                        HStack {
                            Text("\(task.downloadedFormatted) of \(task.totalFormatted)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(Int(task.progress * 100))% • ETA: \(task.etaFormatted)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
    }
}

public struct ShiftDownloadWidget: Widget {
    public let kind: String = "ShiftDownloadWidget"

    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ShiftTimelineProvider()) { entry in
            ShiftWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Shift Downloads")
        .description("Track active download progress and live speed directly from your Home Screen.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        #if os(iOS)
        .contentMarginsDisabled()
        #endif
    }
}
#endif
