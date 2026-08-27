import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

public final class WidgetDataManager: @unchecked Sendable {
    public static let shared = WidgetDataManager()
    public static let appGroupIdentifier = "group.com.shift.downloadmanager"
    private static let storageKey = "shift_widget_snapshot_v1"
    private static let sharedFileName = "shift_widget_snapshot.json"
    private static let globalSimulatorPath = "/tmp/shift_widget_snapshot.json"

    private var lastReloadTime: Date = Date.distantPast
    private var lastActiveCount: Int = -1
    private var lastDownloadedBytes: Int64 = -1
    private let lock = NSLock()

    private init() {}

    private var sharedFileURLs: [URL] {
        var urls: [URL] = []
        // 1. App Group shared container directory
        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier) {
            urls.append(container.appendingPathComponent(Self.sharedFileName))
        }
        // 2. Global simulator path
        urls.append(URL(fileURLWithPath: Self.globalSimulatorPath))
        return urls
    }

    public func saveSnapshot(_ snapshot: WidgetDataSnapshot) {
        lock.lock()
        defer { lock.unlock() }

        do {
            let data = try JSONEncoder().encode(snapshot)

            // 1. Save to Shared Keychain (Guaranteed to cross sandbox boundaries on physical iPhones)
            KeychainWidgetBridge.save(data)

            // 2. App Group UserDefaults (Immediate disk sync)
            if let groupDefaults = UserDefaults(suiteName: Self.appGroupIdentifier) {
                groupDefaults.set(data, forKey: Self.storageKey)
                groupDefaults.synchronize()
            }
            UserDefaults.standard.set(data, forKey: Self.storageKey)
            UserDefaults.standard.synchronize()

            // 3. Write to shared App Group container file
            for fileURL in sharedFileURLs {
                try? data.write(to: fileURL, options: .atomic)
            }

            // 4. Broadcast Darwin notification across process boundaries
            #if os(iOS)
            CFNotificationCenterPostNotification(
                CFNotificationCenterGetDarwinNotifyCenter(),
                CFNotificationName("com.shift.widget.update" as CFString),
                nil,
                nil,
                true
            )
            #endif

            // 5. Notify WidgetKit to reload timelines
            let now = Date()
            if now.timeIntervalSince(lastReloadTime) > 0.8 {
                lastReloadTime = now
                #if canImport(WidgetKit)
                WidgetCenter.shared.reloadTimelines(ofKind: "ShiftDownloadWidget")
                WidgetCenter.shared.reloadAllTimelines()
                #endif
            }
        } catch {
            // Ignore encoding errors
        }
    }

    public func loadSnapshot() -> WidgetDataSnapshot {
        lock.lock()
        defer { lock.unlock() }

        // 1. Try Shared Keychain (100% shared on physical devices & sideloaded builds)
        if let keychainData = KeychainWidgetBridge.load(),
           let snapshot = try? JSONDecoder().decode(WidgetDataSnapshot.self, from: keychainData) {
            return snapshot
        }

        // 2. Try App Group UserDefaults
        if let data = UserDefaults(suiteName: Self.appGroupIdentifier)?.data(forKey: Self.storageKey),
           let snapshot = try? JSONDecoder().decode(WidgetDataSnapshot.self, from: data) {
            return snapshot
        }

        // 3. Try App Group Shared Files
        for fileURL in sharedFileURLs {
            if let fileData = try? Data(contentsOf: fileURL),
               let snapshot = try? JSONDecoder().decode(WidgetDataSnapshot.self, from: fileData) {
                return snapshot
            }
        }

        // 4. Fallback to standard UserDefaults
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let snapshot = try? JSONDecoder().decode(WidgetDataSnapshot.self, from: data) {
            return snapshot
        }

        return .empty
    }

    public func update(from tasks: [DownloadTask], globalSpeed: Int64) {
        let active = tasks.filter { $0.status == .downloading }
        let totalActiveSize = active.reduce(Int64(0)) { $0 + max(0, $1.fileSize) }
        let totalActiveDownloaded = active.reduce(Int64(0)) { $0 + $1.downloadedBytes }

        // Power saving: If completely idle and already recorded as idle, avoid redundant writes
        if active.isEmpty && lastActiveCount == 0 {
            return
        }
        lastActiveCount = active.count
        lastDownloadedBytes = totalActiveDownloaded

        let overallProgress: Double
        if totalActiveSize > 0 {
            overallProgress = min(1.0, max(0.0, Double(totalActiveDownloaded) / Double(totalActiveSize)))
        } else if !active.isEmpty {
            overallProgress = active.map { $0.progress }.reduce(0, +) / Double(active.count)
        } else {
            overallProgress = 0.0
        }

        let snapshots: [WidgetTaskSnapshot] = active.prefix(5).map { task in
            WidgetTaskSnapshot(
                id: task.id,
                fileName: task.fileName,
                progress: task.progress,
                speedFormatted: task.formattedSpeed,
                downloadedFormatted: task.formattedDownloadedSize,
                totalFormatted: task.formattedTotalSize,
                etaFormatted: task.formattedETA,
                categoryIcon: task.category.iconName,
                statusRaw: task.status.rawValue
            )
        }

        let snapshot = WidgetDataSnapshot(
            activeTasks: snapshots,
            totalActiveCount: active.count,
            overallProgress: overallProgress,
            globalSpeedFormatted: ByteCountFormatter.formatSpeed(bytesPerSecond: globalSpeed),
            globalSpeedBytes: globalSpeed,
            totalDownloadedFormatted: ByteCountFormatter.formatBytes(totalActiveDownloaded),
            totalSizeFormatted: ByteCountFormatter.formatBytes(totalActiveSize),
            totalDownloadedBytes: totalActiveDownloaded,
            totalFileSizeBytes: totalActiveSize,
            lastUpdated: Date()
        )

        saveSnapshot(snapshot)
    }
}
