import Foundation
import Combine
import SwiftUI

@MainActor
public final class ShiftDownloadEngine: ObservableObject, ChunkedDownloaderDelegate, HLSStreamDownloaderDelegate, TorrentEngineDelegate {
    @Published public var tasks: [DownloadTask] = []
    @Published public var settings: AppSettings = AppSettings.load() {
        didSet {
            settings.save()
            updateSpeedLimit()
        }
    }
    @Published public var globalDownloadSpeed: Int64 = 0
    @Published public var totalDownloadedBytes: Int64 = 0

    private var activeDownloaders: [UUID: ChunkedDownloader] = [:]
    private var activeHLSDownloaders: [UUID: HLSStreamDownloader] = [:]
    private var activeTorrentEngines: [UUID: TorrentEngine] = [:]
    private var taskWorkers: [UUID: Task<Void, Never>] = [:]
    
    private let globalSpeedLimiter = SpeedLimiter()
    private var speedTimer: DispatchSourceTimer?

    public init(settings: AppSettings = AppSettings.load()) {
        self.settings = settings
        updateSpeedLimit()
        startSpeedMonitor()
    }

    deinit {
        speedTimer?.cancel()
    }

    public func updateSettings(_ newSettings: AppSettings) {
        self.settings = newSettings
        newSettings.save()
        updateSpeedLimit()
    }

    private func updateSpeedLimit() {
        if settings.globalSpeedLimitEnabled {
            globalSpeedLimiter.setLimit(bytesPerSecond: settings.globalSpeedLimitBytesPerSec)
        } else {
            globalSpeedLimiter.setLimit(bytesPerSecond: 0)
        }
    }

    private func startSpeedMonitor() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now(), repeating: .milliseconds(750), leeway: .milliseconds(50))
        timer.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshGlobalMetrics()
            }
        }
        timer.resume()
        self.speedTimer = timer
    }

    private func refreshGlobalMetrics() {
        var totalSpeed: Int64 = 0
        var totalBytes: Int64 = 0
        var hasActiveDownloads = false

        for task in tasks {
            if task.status == .downloading {
                totalSpeed += task.speedBytesPerSec
                hasActiveDownloads = true
            }
            totalBytes += task.downloadedBytes
        }

        if self.globalDownloadSpeed != totalSpeed {
            self.globalDownloadSpeed = totalSpeed
        }
        if self.totalDownloadedBytes != totalBytes {
            self.totalDownloadedBytes = totalBytes
        }

        // Dynamically manage background audio keepalive & battery conservation
        BackgroundDownloadService.shared.updateActiveState(
            hasActiveDownloads: hasActiveDownloads,
            isEnabled: settings.unrestrictedBackgroundDownloads
        )

        // Sync live snapshot to widget
        WidgetDataManager.shared.update(from: tasks, globalSpeed: totalSpeed)
    }

    public func findExistingTask(fileName: String) -> DownloadTask? {
        return tasks.first { $0.fileName.caseInsensitiveCompare(fileName) == .orderedSame }
    }

    // MARK: - Task Operations

    @discardableResult
    public func addDownloadTask(
        url: URL,
        fileName: String? = nil,
        category: TaskCategory? = nil,
        maxConnections: Int? = nil,
        headers: [String: String] = [:],
        userAgent: String? = nil,
        destinationFolder: URL? = nil,
        replaceExisting: Bool = false
    ) -> DownloadTask {
        let conns = maxConnections ?? settings.defaultConnectionsPerDownload
        let resolvedCategory = category ?? TaskCategory.determineCategory(from: fileName ?? url.lastPathComponent)
        
        let documentsDir = destinationFolder ?? FileStorageService.shared.getCategoryDirectory(for: resolvedCategory)
        let resolvedFileName = fileName ?? (url.lastPathComponent.isEmpty ? "download_\(Int(Date().timeIntervalSince1970))" : url.lastPathComponent)
        let destURL = documentsDir.appendingPathComponent(resolvedFileName)

        if replaceExisting {
            if let existing = findExistingTask(fileName: resolvedFileName) {
                deleteTask(id: existing.id, deleteFile: true)
            } else {
                try? FileManager.default.removeItem(at: destURL)
            }
        }

        let task = DownloadTask(
            url: url,
            fileName: resolvedFileName,
            status: .queued,
            category: resolvedCategory,
            protocolType: .http,
            maxConnections: conns,
            headers: headers,
            userAgent: userAgent ?? settings.userAgentPreset.userAgentString,
            destinationPath: destURL.path
        )

        tasks.insert(task, at: 0)
        startTaskExecution(task.id)
        return task
    }

    public func addHLSTask(
        url: URL,
        fileName: String,
        headers: [String: String] = [:],
        replaceExisting: Bool = false
    ) -> DownloadTask {
        let category: TaskCategory = .video
        let documentsDir = FileStorageService.shared.getCategoryDirectory(for: category)
        let finalFileName = fileName.hasSuffix(".mp4") || fileName.hasSuffix(".ts") ? fileName : "\(fileName).mp4"
        let destURL = documentsDir.appendingPathComponent(finalFileName)

        if replaceExisting {
            if let existing = findExistingTask(fileName: finalFileName) {
                deleteTask(id: existing.id, deleteFile: true)
            } else {
                try? FileManager.default.removeItem(at: destURL)
            }
        }

        let task = DownloadTask(
            url: url,
            fileName: finalFileName,
            status: .queued,
            category: category,
            protocolType: .hls,
            maxConnections: settings.defaultConnectionsPerDownload,
            headers: headers,
            userAgent: settings.userAgentPreset.userAgentString,
            destinationPath: destURL.path
        )

        tasks.insert(task, at: 0)
        startTaskExecution(task.id)
        return task
    }

    public func addTorrentTask(
        meta: TorrentMeta,
        destinationFolder: URL? = nil,
        replaceExisting: Bool = false
    ) -> DownloadTask {
        let category: TaskCategory = .torrent
        let documentsDir = destinationFolder ?? FileStorageService.shared.getCategoryDirectory(for: category)
        let destURL = documentsDir.appendingPathComponent(meta.displayName)

        if replaceExisting {
            if let existing = findExistingTask(fileName: meta.displayName) {
                deleteTask(id: existing.id, deleteFile: true)
            } else {
                try? FileManager.default.removeItem(at: destURL)
            }
        }

        guard let fakeURL = URL(string: "magnet:?xt=urn:btih:\(meta.infoHash)&dn=\(meta.displayName)") else {
            fatalError("Invalid magnet URI")
        }

        let task = DownloadTask(
            url: fakeURL,
            fileName: meta.displayName,
            fileSize: meta.totalLength,
            status: .queued,
            category: category,
            protocolType: .torrent,
            destinationPath: destURL.path
        )

        tasks.insert(task, at: 0)
        startTaskExecution(task.id)
        return task
    }

    public func addBatchTasks(urls: [URL], category: TaskCategory? = nil) {
        for url in urls {
            addDownloadTask(url: url, category: category)
        }
    }

    public func pauseTask(id: UUID) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        var task = tasks[idx]
        task.status = .paused
        task.speedBytesPerSec = 0
        task.etaSeconds = nil
        for sIdx in 0..<task.segments.count {
            if task.segments[sIdx].status != .completed {
                task.segments[sIdx].status = .paused
            }
        }
        tasks[idx] = task

        let downloader = activeDownloaders.removeValue(forKey: id)
        downloader?.pause()

        let hlsDownloader = activeHLSDownloaders.removeValue(forKey: id)
        hlsDownloader?.pause()

        let torrentEngine = activeTorrentEngines.removeValue(forKey: id)
        torrentEngine?.pause()

        taskWorkers.removeValue(forKey: id)?.cancel()

        processQueue()
    }

    public func resumeTask(id: UUID) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        var task = tasks[idx]
        task.status = .downloading
        task.errorDescription = nil
        for sIdx in 0..<task.segments.count {
            if task.segments[sIdx].status == .failed || task.segments[sIdx].status == .paused {
                if !task.segments[sIdx].isFinished {
                    task.segments[sIdx].status = .pending
                    task.segments[sIdx].errorDescription = nil
                }
            }
        }
        tasks[idx] = task
        startTaskExecution(id)
    }

    public func cancelTask(id: UUID) {
        pauseTask(id: id)
    }

    public func retryTask(id: UUID) {
        resumeTask(id: id)
    }

    public func deleteTask(id: UUID, deleteFile: Bool = false) {
        pauseTask(id: id)
        if let idx = tasks.firstIndex(where: { $0.id == id }) {
            let path = tasks[idx].destinationPath
            if deleteFile && !path.isEmpty {
                try? FileManager.default.removeItem(atPath: path)
            }
            tasks.remove(at: idx)
        }
    }

    public func updateTaskURL(id: UUID, newURL: URL, resumeImmediately: Bool = true) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }

        // 1. Pause existing workers if active
        if tasks[idx].status == .downloading {
            pauseTask(id: id)
        }

        // 2. Update URL and clear error states
        var updated = tasks[idx]
        updated.url = newURL
        updated.errorDescription = nil
        if updated.status == .failed {
            updated.status = .paused
        }
        for sIdx in 0..<updated.segments.count {
            if updated.segments[sIdx].status == .failed {
                updated.segments[sIdx].status = .pending
                updated.segments[sIdx].errorDescription = nil
            }
        }
        tasks[idx] = updated
        ShiftLogger.shared.info("🔄 Changed download URL for [\(updated.fileName)] to: \(newURL.absoluteString)", category: .engine)

        // 3. Resume if requested
        if resumeImmediately {
            resumeTask(id: id)
        }
    }

    public func clearCompleted() {
        tasks.removeAll { $0.status == .completed }
    }

    // MARK: - Queue Processor

    public func processQueue() {
        let activeRealCount = activeDownloaders.count + activeHLSDownloaders.count + activeTorrentEngines.count
        guard activeRealCount < settings.maxConcurrentDownloads else { return }

        let slots = settings.maxConcurrentDownloads - activeRealCount
        let queued = tasks.filter { $0.status == .queued }.prefix(slots)

        for task in queued {
            startTaskExecution(task.id)
        }
    }

    private func startTaskExecution(_ taskId: UUID) {
        guard let idx = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        var currentTask = tasks[idx]
        currentTask.status = .downloading
        currentTask.startedAt = currentTask.startedAt ?? Date()
        tasks[idx] = currentTask

        let destURL = URL(fileURLWithPath: currentTask.destinationPath)

        switch currentTask.protocolType {
        case .http:
            let downloader = ChunkedDownloader(
                taskId: taskId,
                url: currentTask.url,
                destinationURL: destURL,
                maxConnections: currentTask.maxConnections,
                customHeaders: currentTask.headers,
                userAgent: currentTask.userAgent,
                speedLimiter: settings.globalSpeedLimitEnabled ? globalSpeedLimiter : nil,
                existingSegments: currentTask.segments
            )
            
            downloader.delegate = self
            activeDownloaders[taskId] = downloader
            downloader.start()

        case .hls:
            let hlsDownloader = HLSStreamDownloader(
                taskId: taskId,
                masterURL: currentTask.url,
                destinationURL: destURL,
                maxConcurrency: currentTask.maxConnections,
                customHeaders: currentTask.headers,
                userAgent: currentTask.userAgent,
                speedLimiter: settings.globalSpeedLimitEnabled ? globalSpeedLimiter : nil
            )
            
            hlsDownloader.delegate = self
            activeHLSDownloaders[taskId] = hlsDownloader

            let worker = Task {
                await hlsDownloader.start()
            }
            taskWorkers[taskId] = worker

        case .torrent:
            let meta = TorrentMeta.parseMagnetLink(currentTask.url.absoluteString) ?? TorrentMeta(
                infoHash: "MOCK_HASH",
                displayName: currentTask.fileName,
                totalLength: currentTask.fileSize > 0 ? currentTask.fileSize : 50 * 1024 * 1024
            )
            let torrentEngine = TorrentEngine(
                taskId: taskId,
                meta: meta,
                destinationURL: destURL,
                speedLimiter: settings.globalSpeedLimitEnabled ? globalSpeedLimiter : nil
            )

            torrentEngine.delegate = self
            activeTorrentEngines[taskId] = torrentEngine

            let worker = Task {
                await torrentEngine.start()
            }
            taskWorkers[taskId] = worker
        }
    }

    // MARK: - ChunkedDownloaderDelegate

    nonisolated public func chunkedDownloaderDidUpdateProgress(taskId: UUID, downloadedBytes: Int64, totalBytes: Int64, speed: Int64, segments: [DownloadSegment]) {
        Task { @MainActor in
            guard let idx = self.tasks.firstIndex(where: { $0.id == taskId }),
                  self.activeDownloaders[taskId] != nil,
                  self.tasks[idx].status == .downloading else { return }

            var task = self.tasks[idx]
            task.downloadedBytes = downloadedBytes
            if totalBytes > 0 { task.fileSize = totalBytes }
            task.speedBytesPerSec = speed
            task.segments = segments

            // Record rolling speed history
            let sample = DownloadSpeedSample(bytesPerSecond: speed)
            task.speedHistory.append(sample)
            if task.speedHistory.count > 30 {
                task.speedHistory.removeFirst(task.speedHistory.count - 30)
            }

            // Calculate ETA
            if task.fileSize > 0 && speed > 0 {
                let remainingBytes = max(0, task.fileSize - task.downloadedBytes)
                task.etaSeconds = Double(remainingBytes) / Double(speed)
            } else {
                task.etaSeconds = nil
            }

            self.tasks[idx] = task
            self.refreshGlobalMetrics()
        }
    }

    nonisolated public func chunkedDownloaderDidComplete(taskId: UUID, fileURL: URL) {
        Task { @MainActor in
            guard let idx = self.tasks.firstIndex(where: { $0.id == taskId }),
                  self.activeDownloaders[taskId] != nil,
                  self.tasks[idx].status == .downloading else { return }

            var task = self.tasks[idx]
            task.status = .completed
            task.completedAt = Date()
            task.speedBytesPerSec = 0
            task.etaSeconds = nil
            if task.fileSize > 0 {
                task.downloadedBytes = task.fileSize
            }
            for sIdx in 0..<task.segments.count {
                task.segments[sIdx].status = .completed
                task.segments[sIdx].currentOffset = task.segments[sIdx].endOffset + 1
            }
            self.tasks[idx] = task
            ShiftLogger.shared.info("✅ Completed download [\(task.fileName)] - Size: \(task.formattedTotalSize)", category: .engine)

            self.activeDownloaders.removeValue(forKey: taskId)
            self.processQueue()
        }
    }

    nonisolated public func chunkedDownloaderDidFail(taskId: UUID, error: Error) {
        Task { @MainActor in
            guard let idx = self.tasks.firstIndex(where: { $0.id == taskId }),
                  self.activeDownloaders[taskId] != nil,
                  self.tasks[idx].status == .downloading else { return }

            var task = self.tasks[idx]
            task.status = .failed
            task.errorDescription = error.localizedDescription
            task.speedBytesPerSec = 0
            task.etaSeconds = nil
            self.tasks[idx] = task
            ShiftLogger.shared.error("❌ Download failed [\(task.fileName)]: \(error.localizedDescription)", category: .engine)

            self.activeDownloaders.removeValue(forKey: taskId)
            self.processQueue()
        }
    }

    // MARK: - HLSStreamDownloaderDelegate

    nonisolated public func hlsDownloaderDidUpdateProgress(taskId: UUID, downloadedSegments: Int, totalSegments: Int, downloadedBytes: Int64, speed: Int64) {
        Task { @MainActor in
            guard let idx = self.tasks.firstIndex(where: { $0.id == taskId }),
                  self.activeHLSDownloaders[taskId] != nil,
                  self.tasks[idx].status == .downloading else { return }

            var task = self.tasks[idx]
            task.downloadedBytes = downloadedBytes
            task.speedBytesPerSec = speed
            self.tasks[idx] = task
            self.refreshGlobalMetrics()
        }
    }

    nonisolated public func hlsDownloaderDidComplete(taskId: UUID, fileURL: URL) {
        Task { @MainActor in
            guard let idx = self.tasks.firstIndex(where: { $0.id == taskId }),
                  self.activeHLSDownloaders[taskId] != nil,
                  self.tasks[idx].status == .downloading else { return }

            var task = self.tasks[idx]
            task.status = .completed
            task.completedAt = Date()
            task.speedBytesPerSec = 0
            task.etaSeconds = nil
            self.tasks[idx] = task
            self.refreshGlobalMetrics()
            
            self.activeHLSDownloaders.removeValue(forKey: taskId)
            self.taskWorkers.removeValue(forKey: taskId)
            self.processQueue()
        }
    }

    nonisolated public func hlsDownloaderDidFail(taskId: UUID, error: Error) {
        Task { @MainActor in
            guard let idx = self.tasks.firstIndex(where: { $0.id == taskId }),
                  self.activeHLSDownloaders[taskId] != nil,
                  self.tasks[idx].status == .downloading else { return }

            var task = self.tasks[idx]
            task.status = .failed
            task.errorDescription = error.localizedDescription
            task.speedBytesPerSec = 0
            task.etaSeconds = nil
            self.tasks[idx] = task
            self.refreshGlobalMetrics()
            
            self.activeHLSDownloaders.removeValue(forKey: taskId)
            self.taskWorkers.removeValue(forKey: taskId)
            self.processQueue()
        }
    }

    // MARK: - TorrentEngineDelegate

    nonisolated public func torrentEngineDidUpdateProgress(taskId: UUID, downloadedBytes: Int64, totalBytes: Int64, speed: Int64, peers: Int, seeds: Int) {
        Task { @MainActor in
            guard let idx = self.tasks.firstIndex(where: { $0.id == taskId }),
                  self.activeTorrentEngines[taskId] != nil,
                  self.tasks[idx].status == .downloading else { return }

            var task = self.tasks[idx]
            task.downloadedBytes = downloadedBytes
            task.fileSize = totalBytes
            task.speedBytesPerSec = speed
            self.tasks[idx] = task
            self.refreshGlobalMetrics()
        }
    }

    nonisolated public func torrentEngineDidComplete(taskId: UUID, outputDirectory: URL) {
        Task { @MainActor in
            guard let idx = self.tasks.firstIndex(where: { $0.id == taskId }),
                  self.activeTorrentEngines[taskId] != nil,
                  self.tasks[idx].status == .downloading else { return }

            var task = self.tasks[idx]
            task.status = .completed
            task.completedAt = Date()
            task.speedBytesPerSec = 0
            task.etaSeconds = nil
            self.tasks[idx] = task
            
            self.activeTorrentEngines.removeValue(forKey: taskId)
            self.taskWorkers.removeValue(forKey: taskId)
            self.processQueue()
        }
    }

    nonisolated public func torrentEngineDidFail(taskId: UUID, error: Error) {
        Task { @MainActor in
            guard let idx = self.tasks.firstIndex(where: { $0.id == taskId }),
                  self.activeTorrentEngines[taskId] != nil,
                  self.tasks[idx].status == .downloading else { return }

            var task = self.tasks[idx]
            task.status = .failed
            task.errorDescription = error.localizedDescription
            task.speedBytesPerSec = 0
            task.etaSeconds = nil
            self.tasks[idx] = task
            
            self.activeTorrentEngines.removeValue(forKey: taskId)
            self.taskWorkers.removeValue(forKey: taskId)
            self.processQueue()
        }
    }
}
