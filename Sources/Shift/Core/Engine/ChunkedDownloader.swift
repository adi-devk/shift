import Foundation
#if canImport(Darwin)
import Darwin
#endif

public protocol ChunkedDownloaderDelegate: AnyObject, Sendable {
    func chunkedDownloaderDidUpdateProgress(taskId: UUID, downloadedBytes: Int64, totalBytes: Int64, speed: Int64, segments: [DownloadSegment])
    func chunkedDownloaderDidComplete(taskId: UUID, fileURL: URL)
    func chunkedDownloaderDidFail(taskId: UUID, error: Error)
}

public final class ChunkedDownloader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    public let taskId: UUID
    public let url: URL
    public let destinationURL: URL
    public let maxConnections: Int
    public let customHeaders: [String: String]
    public let userAgent: String?
    public let speedLimiter: SpeedLimiter?

    private var segments: [DownloadSegment] = []
    private var segmentLastActiveTime: [Int: Date] = [:]
    private var isPaused = false
    private var isCancelled = false
    private var hasNotifiedTerminalState = false
    private let lock = NSRecursiveLock()
    
    private var fileDescriptor: Int32 = -1
    private var session: URLSession?
    private var dataTasks: [Int: URLSessionDataTask] = [:]
    private var taskToSegmentIndex: [Int: Int] = [:]
    private var segmentRetryCounts: [Int: Int] = [:]
    private let maxRetriesPerSegment: Int = 20

    // Independent Telemetry Engine with EMA Smoothing
    private var tickerTask: Task<Void, Never>?
    private var lastTickTime: Date = Date()
    private var lastTickDownloadedBytes: Int64 = 0
    private var smoothedSpeed: Double = 0.0
    private var totalFileSize: Int64 = -1
    private var actualDownloadURL: URL
    public private(set) var suggestedFileName: String? = nil
    
    public weak var delegate: ChunkedDownloaderDelegate?

    public init(
        taskId: UUID,
        url: URL,
        destinationURL: URL,
        maxConnections: Int = 8,
        customHeaders: [String: String] = [:],
        userAgent: String? = nil,
        speedLimiter: SpeedLimiter? = nil,
        existingSegments: [DownloadSegment] = []
    ) {
        self.taskId = taskId
        self.url = url
        self.actualDownloadURL = url
        self.destinationURL = destinationURL
        self.maxConnections = max(1, min(32, maxConnections))
        self.customHeaders = customHeaders
        self.userAgent = userAgent
        self.speedLimiter = speedLimiter
        
        // Clean segments on init: any unfinished segment should be pending
        var cleanedSegments: [DownloadSegment] = []
        for s in existingSegments {
            var seg = s
            if seg.isFinished || (seg.endOffset > 0 && seg.currentOffset > seg.endOffset) {
                seg.status = .completed
            } else {
                seg.status = .pending
                seg.errorDescription = nil
            }
            cleanedSegments.append(seg)
        }
        self.segments = cleanedSegments
        self.lastTickDownloadedBytes = cleanedSegments.reduce(0) { $0 + $1.downloadedBytes }
        super.init()
    }

    public struct ProbeResult: Sendable {
        public let fileSize: Int64
        public let supportsRanges: Bool
        public let suggestedFileName: String?
        public let mimeType: String?
        public let etag: String?
    }

    public static func getHeader(_ name: String, from http: HTTPURLResponse) -> String? {
        if let val = http.value(forHTTPHeaderField: name) { return val }
        for (k, v) in http.allHeaderFields {
            if let strKey = k as? String, strKey.caseInsensitiveCompare(name) == .orderedSame {
                return v as? String
            }
        }
        return nil
    }

    public static func probeURL(
        _ url: URL,
        customHeaders: [String: String] = [:],
        userAgent: String? = nil
    ) async throws -> ProbeResult {
        if let meta = try? await UniversalURLResolver.resolveURL(url, customHeaders: customHeaders, userAgent: userAgent) {
            return ProbeResult(
                fileSize: meta.fileSize,
                supportsRanges: meta.supportsRanges,
                suggestedFileName: meta.fileName,
                mimeType: meta.mimeType,
                etag: meta.etag
            )
        }

        return ProbeResult(fileSize: -1, supportsRanges: false, suggestedFileName: nil, mimeType: nil, etag: nil)
    }

    private static func parseHTTPResponse(_ http: HTTPURLResponse, url: URL) -> ProbeResult {
        var size: Int64 = -1
        var supportsRanges = false
        var fileName: String? = nil
        let mimeType: String? = http.mimeType
        let etag: String? = getHeader("ETag", from: http)

        if let acceptRanges = getHeader("Accept-Ranges", from: http), acceptRanges.lowercased().contains("bytes") {
            supportsRanges = true
        }

        if let contentRange = getHeader("Content-Range", from: http) {
            supportsRanges = true
            if let slashIndex = contentRange.lastIndex(of: "/") {
                let totalStr = String(contentRange[contentRange.index(after: slashIndex)...])
                if let parsed = Int64(totalStr.trimmingCharacters(in: .whitespaces)) {
                    size = parsed
                }
            }
        } else if let contentLengthStr = getHeader("Content-Length", from: http), let parsed = Int64(contentLengthStr) {
            size = parsed
        }

        if size <= 0 && http.expectedContentLength > 0 {
            size = http.expectedContentLength
        }

        if let disposition = getHeader("Content-Disposition", from: http) {
            fileName = ContentDispositionParser.extractFileName(from: disposition)
        }

        return ProbeResult(
            fileSize: size,
            supportsRanges: supportsRanges,
            suggestedFileName: fileName,
            mimeType: mimeType,
            etag: etag
        )
    }

    public func start() {
        lock.lock()
        isPaused = false
        isCancelled = false
        hasNotifiedTerminalState = false
        lock.unlock()

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            await self.bootstrapAndLaunch()
        }
    }

    private func bootstrapAndLaunch() async {
        do {
            let fm = FileManager.default
            let dir = destinationURL.deletingLastPathComponent()
            if !fm.fileExists(atPath: dir.path) {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }

            var targetURL = url
            var probeSize: Int64 = -1
            var rangeSupported = true

            if let resolvedMeta = try? await UniversalURLResolver.resolveURL(url, customHeaders: customHeaders, userAgent: userAgent) {
                targetURL = resolvedMeta.resolvedDirectURL
                probeSize = resolvedMeta.fileSize
                rangeSupported = resolvedMeta.supportsRanges && probeSize > 0
                if let suggested = resolvedMeta.fileName {
                    lock.lock()
                    self.suggestedFileName = suggested
                    lock.unlock()
                }
            }

            lock.lock()
            self.actualDownloadURL = targetURL
            lock.unlock()

            let existingCount = getSegmentsCount()
            if existingCount == 0 {
                if probeSize <= 0 {
                    let probe = (try? await Self.probeURL(targetURL, customHeaders: customHeaders, userAgent: userAgent)) ?? ProbeResult(fileSize: -1, supportsRanges: false, suggestedFileName: nil, mimeType: nil, etag: nil)
                    probeSize = probe.fileSize
                    rangeSupported = probe.supportsRanges && probeSize > 0
                }

                if rangeSupported && probeSize > 512 * 1024 && maxConnections > 1 {
                    let numParts = min(maxConnections, Int(max(1, probeSize / (1024 * 512))))
                    let chunkSize = probeSize / Int64(numParts)
                    var newSegments: [DownloadSegment] = []

                    for i in 0..<numParts {
                        let start = Int64(i) * chunkSize
                        let end = (i == numParts - 1) ? (probeSize - 1) : (start + chunkSize - 1)
                        newSegments.append(
                            DownloadSegment(
                                index: i,
                                startOffset: start,
                                currentOffset: start,
                                endOffset: end,
                                status: .pending
                            )
                        )
                    }
                    setSegments(newSegments)
                } else {
                    setSegments([
                        DownloadSegment(
                            index: 0,
                            startOffset: 0,
                            currentOffset: 0,
                            endOffset: max(0, probeSize > 0 ? (probeSize - 1) : 0),
                            status: .pending
                        )
                    ])
                }
            }

            lock.lock()
            self.totalFileSize = probeSize > 0 ? probeSize : getTotalFileSpan()
            let now = Date()
            self.lastTickTime = now
            self.lastTickDownloadedBytes = segments.reduce(0) { $0 + $1.downloadedBytes }
            self.smoothedSpeed = 0.0
            for idx in 0..<segments.count {
                self.segmentLastActiveTime[idx] = now
            }
            lock.unlock()

            // Open or create destination file descriptor with POSIX O_RDWR | O_CREAT
            let path = destinationURL.path
            let fd = open(path, O_RDWR | O_CREAT, 0o644)
            guard fd >= 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "Failed to open destination file"])
            }

            if probeSize > 0 && existingCount == 0 {
                _ = ftruncate(fd, off_t(probeSize))
            }

            lock.lock()
            self.fileDescriptor = fd
            lock.unlock()

            // Setup resilient URLSession configuration
            let queue = OperationQueue()
            queue.maxConcurrentOperationCount = max(8, maxConnections)
            queue.qualityOfService = .userInitiated
            let sessionConfig = URLSessionConfiguration.default
            sessionConfig.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            sessionConfig.timeoutIntervalForRequest = 45.0
            sessionConfig.timeoutIntervalForResource = 86400.0
            sessionConfig.httpMaximumConnectionsPerHost = 32
            sessionConfig.httpShouldUsePipelining = true
            sessionConfig.waitsForConnectivity = true
            
            let sess = URLSession(configuration: sessionConfig, delegate: self, delegateQueue: queue)
            lock.lock()
            self.session = sess
            lock.unlock()

            // Start Independent Telemetry & Watchdog Timer
            startIndependentTelemetryAndWatchdog()

            // Stagger dispatch across segments to avoid tripping server burst rate-limiters (HTTP 429)
            let snapshot = getSegmentsSnapshot()
            for (i, seg) in snapshot.enumerated() {
                if seg.isFinished || (seg.endOffset > 0 && seg.currentOffset > seg.endOffset) {
                    updateSegmentStatus(index: seg.index, status: .completed)
                } else {
                    launchSegmentTask(seg, delayMs: i * 80)
                }
            }
            checkAllFinishedOrFailed()
        } catch {
            cleanup()
            delegate?.chunkedDownloaderDidFail(taskId: taskId, error: error)
        }
    }

    // MARK: - Independent Telemetry & Stall Watchdog

    private func startIndependentTelemetryAndWatchdog() {
        tickerTask?.cancel()
        tickerTask = Task.detached(priority: .utility) { [weak self] in
            while true {
                try? await Task.sleep(nanoseconds: 500_000_000) // 500ms clean tick
                guard let self = self, !self.isExecutionStopped else { break }
                self.performTick()
            }
        }
    }

    private func performTick() {
        lock.lock()
        guard !hasNotifiedTerminalState, !isPaused, !isCancelled else {
            lock.unlock()
            return
        }

        let now = Date()
        let elapsed = max(0.1, now.timeIntervalSince(lastTickTime))
        self.lastTickTime = now

        let currentDownloaded = segments.reduce(0) { $0 + $1.downloadedBytes }
        let bytesDelta = max(0, currentDownloaded - lastTickDownloadedBytes)
        self.lastTickDownloadedBytes = currentDownloaded

        let instantSpeed = Double(bytesDelta) / elapsed
        if smoothedSpeed <= 0 {
            smoothedSpeed = instantSpeed
        } else {
            // Exponential Moving Average: 0.35 new data + 0.65 history for smooth curve
            smoothedSpeed = (smoothedSpeed * 0.65) + (instantSpeed * 0.35)
        }
        let speed = Int64(smoothedSpeed)

        let totalSize = totalFileSize > 0 ? totalFileSize : segments.reduce(0) { max($0, $1.endOffset + 1) }
        let snapshot = self.segments

        // Stall Watchdog: Only restart workers truly frozen with 0 bytes for > 15 seconds
        var stalledSegmentsToRestart: [DownloadSegment] = []
        for (idx, seg) in segments.enumerated() {
            if seg.status == .downloading && !seg.isFinished {
                let lastActive = segmentLastActiveTime[idx] ?? now
                if now.timeIntervalSince(lastActive) > 15.0 {
                    segmentLastActiveTime[idx] = now
                    stalledSegmentsToRestart.append(seg)
                }
            }
        }
        lock.unlock()

        // Restart only genuinely stalled workers on fresh TCP sockets
        for stalled in stalledSegmentsToRestart {
            lock.lock()
            let oldTask = dataTasks.removeValue(forKey: stalled.index)
            lock.unlock()
            oldTask?.cancel()
            launchSegmentTask(stalled)
        }

        // Send continuous live telemetry only if not paused
        lock.lock()
        let stillActive = !isPaused && !isCancelled
        lock.unlock()

        if stillActive {
            delegate?.chunkedDownloaderDidUpdateProgress(
                taskId: taskId,
                downloadedBytes: currentDownloaded,
                totalBytes: totalSize,
                speed: speed,
                segments: snapshot
            )
        }

        checkAllFinishedOrFailed()
    }

    private func launchSegmentTask(_ segment: DownloadSegment, delayMs: Int = 0) {
        if delayMs > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(delayMs)) { [weak self] in
                guard let self = self, !self.isExecutionStopped else { return }
                self.executeSegmentRequest(segment)
            }
        } else {
            executeSegmentRequest(segment)
        }
    }

    private func executeSegmentRequest(_ segment: DownloadSegment) {
        lock.lock()
        guard let sess = session, fileDescriptor >= 0, !isPaused, !isCancelled else {
            lock.unlock()
            return
        }

        let start = segment.currentOffset
        let end = segment.endOffset

        // If segment is already completed, do not request
        if end > 0 && start > end {
            segments[segment.index].status = .completed
            lock.unlock()
            checkAllFinishedOrFailed()
            return
        }

        updateSegmentStatus(index: segment.index, status: .downloading)
        segmentLastActiveTime[segment.index] = Date()
        let requestURL = actualDownloadURL
        lock.unlock()

        var request = URLRequest(url: requestURL)
        request.timeoutInterval = 45.0
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        for (k, v) in customHeaders { request.setValue(v, forHTTPHeaderField: k) }
        if let ua = userAgent, !ua.isEmpty { request.setValue(ua, forHTTPHeaderField: "User-Agent") }

        if end > 0 && end >= start {
            request.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
        } else if start > 0 {
            request.setValue("bytes=\(start)-", forHTTPHeaderField: "Range")
        }

        let task = sess.dataTask(with: request)
        
        lock.lock()
        dataTasks[segment.index] = task
        taskToSegmentIndex[task.taskIdentifier] = segment.index
        lock.unlock()

        task.resume()
    }

    // MARK: - URLSessionDataDelegate

    public func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        lock.lock()
        let stopped = isPaused || isCancelled
        lock.unlock()
        if stopped {
            completionHandler(.cancel)
            return
        }

        if let http = response as? HTTPURLResponse {
            // 1. Handle HTTP 416 (Range Not Satisfiable) as segment already completed
            if http.statusCode == 416 {
                lock.lock()
                if let segIdx = taskToSegmentIndex[dataTask.taskIdentifier], segIdx < segments.count {
                    segments[segIdx].status = .completed
                    segments[segIdx].currentOffset = max(segments[segIdx].currentOffset, segments[segIdx].endOffset + 1)
                }
                dataTasks.removeValue(forKey: taskToSegmentIndex[dataTask.taskIdentifier] ?? -1)
                taskToSegmentIndex.removeValue(forKey: dataTask.taskIdentifier)
                lock.unlock()
                completionHandler(.cancel)
                checkAllFinishedOrFailed()
                return
            }

            // 2. Handle HTTP 429 (Rate Limit) or HTTP 503: Automatic Exponential Backoff Retry
            if http.statusCode == 429 || http.statusCode == 503 {
                completionHandler(.cancel)
                lock.lock()
                guard let segIdx = taskToSegmentIndex[dataTask.taskIdentifier] else {
                    lock.unlock()
                    return
                }
                dataTasks.removeValue(forKey: segIdx)
                taskToSegmentIndex.removeValue(forKey: dataTask.taskIdentifier)

                let retrySecs: Double
                if let retryHeader = Self.getHeader("Retry-After", from: http), let parsed = Double(retryHeader) {
                    retrySecs = min(parsed, 4.0)
                } else {
                    retrySecs = 1.5
                }

                let retryCount = segmentRetryCounts[segIdx, default: 0]
                if retryCount < maxRetriesPerSegment {
                    segmentRetryCounts[segIdx] = retryCount + 1
                    updateSegmentStatus(index: segIdx, status: .pending)
                    lock.unlock()

                    DispatchQueue.global().asyncAfter(deadline: .now() + retrySecs) { [weak self] in
                        guard let self = self, !self.isExecutionStopped,
                              let seg = self.getSegment(at: segIdx), !seg.isFinished else { return }
                        self.launchSegmentTask(seg)
                    }
                } else {
                    updateSegmentStatus(index: segIdx, status: .failed, error: "Server rate limited (HTTP \(http.statusCode))")
                    lock.unlock()
                    checkAllFinishedOrFailed()
                }
                return
            }

            // 3. Fatal HTTP errors (401, 403, 404, 500)
            if http.statusCode >= 400 {
                delegate?.chunkedDownloaderDidFail(taskId: taskId, error: NSError(domain: "HTTPError", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server returned HTTP \(http.statusCode)"]))
                completionHandler(.cancel)
                return
            }

            // Discover size if previously unknown
            lock.lock()
            if self.totalFileSize <= 0 {
                var discoveredSize: Int64 = -1
                if let contentRange = Self.getHeader("Content-Range", from: http), let slashIdx = contentRange.lastIndex(of: "/") {
                    let totalStr = String(contentRange[contentRange.index(after: slashIdx)...])
                    discoveredSize = Int64(totalStr.trimmingCharacters(in: .whitespaces)) ?? -1
                } else if let lenStr = Self.getHeader("Content-Length", from: http), let parsed = Int64(lenStr) {
                    discoveredSize = parsed
                } else if http.expectedContentLength > 0 {
                    discoveredSize = http.expectedContentLength
                }

                if discoveredSize > 0 {
                    self.totalFileSize = discoveredSize
                    if let segIdx = taskToSegmentIndex[dataTask.taskIdentifier], segIdx < segments.count {
                        segments[segIdx].endOffset = discoveredSize - 1
                    }
                }
            }
            lock.unlock()
        }
        completionHandler(.allow)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard let segIdx = taskToSegmentIndex[dataTask.taskIdentifier],
              fileDescriptor >= 0,
              !isPaused, !isCancelled else {
            lock.unlock()
            return
        }

        let currentOffset = segments[segIdx].currentOffset
        let dataCount = data.count
        let fd = self.fileDescriptor
        lock.unlock()

        // Direct atomic POSIX write to exact byte offset
        data.withUnsafeBytes { rawBuffer in
            if let baseAddress = rawBuffer.baseAddress {
                _ = pwrite(fd, baseAddress, dataCount, off_t(currentOffset))
            }
        }

        lock.lock()
        guard !isPaused, !isCancelled else {
            lock.unlock()
            return
        }

        if segIdx >= 0 && segIdx < segments.count {
            segments[segIdx].currentOffset += Int64(dataCount)
            segmentLastActiveTime[segIdx] = Date()

            // When assigned range completes, mark completed immediately
            if segments[segIdx].endOffset > 0 && segments[segIdx].currentOffset > segments[segIdx].endOffset {
                segments[segIdx].status = .completed
                let taskToCancel = dataTasks.removeValue(forKey: segIdx)
                taskToSegmentIndex.removeValue(forKey: dataTask.taskIdentifier)
                lock.unlock()
                taskToCancel?.cancel()
                checkAllFinishedOrFailed()
                return
            }
        }
        lock.unlock()
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        guard let segIdx = taskToSegmentIndex[task.taskIdentifier] else {
            lock.unlock()
            return
        }
        dataTasks.removeValue(forKey: segIdx)
        taskToSegmentIndex.removeValue(forKey: task.taskIdentifier)
        let stopped = isPaused || isCancelled
        
        if stopped {
            lock.unlock()
            return
        }

        var isSegmentComplete = false
        if segIdx >= 0 && segIdx < segments.count {
            let seg = segments[segIdx]
            if (seg.endOffset > 0 && seg.currentOffset >= seg.endOffset) || (error == nil) {
                isSegmentComplete = true
                segments[segIdx].status = .completed
                segments[segIdx].currentOffset = max(segments[segIdx].currentOffset, segments[segIdx].endOffset + 1)
            }
        }
        lock.unlock()

        if isSegmentComplete {
            updateSegmentStatus(index: segIdx, status: .completed)
            checkAllFinishedOrFailed()
            return
        }

        if let error = error {
            if (error as NSError).code != NSURLErrorCancelled && !stopped {
                // Auto-retry transient connection drops (e.g. -1005, -1001, -1009)
                lock.lock()
                let retryCount = segmentRetryCounts[segIdx, default: 0]
                let seg = (segIdx >= 0 && segIdx < segments.count) ? segments[segIdx] : nil
                let canRetry = seg != nil && !seg!.isFinished && retryCount < maxRetriesPerSegment
                if canRetry {
                    segmentRetryCounts[segIdx] = retryCount + 1
                    segmentLastActiveTime[segIdx] = Date()
                }
                lock.unlock()

                if canRetry, seg != nil {
                    let delay = min(2.0, 0.4 * Double(retryCount + 1))
                    DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
                        guard let self = self, !self.isExecutionStopped, let freshSeg = self.getSegment(at: segIdx), !freshSeg.isFinished else { return }
                        self.launchSegmentTask(freshSeg)
                    }
                    return
                }

                updateSegmentStatus(index: segIdx, status: .failed, error: error.localizedDescription)
                checkAllFinishedOrFailed()
            }
        } else {
            updateSegmentStatus(index: segIdx, status: .completed)
            checkAllFinishedOrFailed()
        }
    }

    private func checkAllFinishedOrFailed() {
        lock.lock()
        guard !hasNotifiedTerminalState, !isPaused, !isCancelled else {
            lock.unlock()
            return
        }

        let allCompleted = segments.allSatisfy { $0.isFinished || $0.status == .completed }
        let hasFailures = segments.contains { $0.status == .failed }
        let anyActive = !dataTasks.isEmpty
        let snapshot = segments
        let finalSize = totalFileSize > 0 ? totalFileSize : snapshot.reduce(0) { max($0, $1.endOffset + 1) }

        if allCompleted {
            hasNotifiedTerminalState = true
            lock.unlock()
            cleanup()
            
            delegate?.chunkedDownloaderDidUpdateProgress(
                taskId: taskId,
                downloadedBytes: finalSize,
                totalBytes: finalSize,
                speed: 0,
                segments: snapshot.map { var s = $0; s.status = .completed; s.currentOffset = s.endOffset + 1; return s }
            )
            delegate?.chunkedDownloaderDidComplete(taskId: taskId, fileURL: destinationURL)
        } else if hasFailures && !anyActive {
            hasNotifiedTerminalState = true
            lock.unlock()
            cleanup()
            
            delegate?.chunkedDownloaderDidFail(taskId: taskId, error: NSError(domain: "Shift", code: -1, userInfo: [NSLocalizedDescriptionKey: "Download failed after multiple retries"]))
        } else {
            lock.unlock()
        }
    }

    public func pause() {
        lock.lock()
        isPaused = true
        tickerTask?.cancel()
        tickerTask = nil
        let tasksToCancel = Array(dataTasks.values)
        dataTasks.removeAll()
        taskToSegmentIndex.removeAll()
        let sess = session
        session = nil
        if fileDescriptor >= 0 {
            fsync(fileDescriptor)
            close(fileDescriptor)
            fileDescriptor = -1
        }
        lock.unlock()

        for t in tasksToCancel { t.cancel() }
        sess?.invalidateAndCancel()
    }

    public func cancel() {
        lock.lock()
        isCancelled = true
        tickerTask?.cancel()
        tickerTask = nil
        let tasksToCancel = Array(dataTasks.values)
        dataTasks.removeAll()
        taskToSegmentIndex.removeAll()
        let sess = session
        session = nil
        if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
        lock.unlock()

        for t in tasksToCancel { t.cancel() }
        sess?.invalidateAndCancel()
        try? FileManager.default.removeItem(at: destinationURL)
    }

    private func cleanup() {
        lock.lock()
        defer { lock.unlock() }
        tickerTask?.cancel()
        tickerTask = nil
        for (_, t) in dataTasks { t.cancel() }
        dataTasks.removeAll()
        taskToSegmentIndex.removeAll()
        session?.invalidateAndCancel()
        session = nil
        if fileDescriptor >= 0 {
            fsync(fileDescriptor)
            close(fileDescriptor)
            fileDescriptor = -1
        }
    }

    private var isExecutionStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isPaused || isCancelled
    }

    private func setSegments(_ newSegments: [DownloadSegment]) {
        lock.lock()
        self.segments = newSegments
        lock.unlock()
    }

    private func getSegmentsCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return segments.count
    }

    private func getSegmentsSnapshot() -> [DownloadSegment] {
        lock.lock()
        defer { lock.unlock() }
        return segments
    }

    private func getTotalFileSpan() -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        return segments.reduce(0) { max($0, $1.endOffset + 1) }
    }

    private func getSegment(at index: Int) -> DownloadSegment? {
        lock.lock()
        defer { lock.unlock() }
        guard index >= 0 && index < segments.count else { return nil }
        return segments[index]
    }

    private func updateSegmentStatus(index: Int, status: SegmentStatus, error: String? = nil) {
        lock.lock()
        defer { lock.unlock() }
        guard index >= 0 && index < segments.count else { return }
        segments[index].status = status
        if let err = error { segments[index].errorDescription = err }
    }
}
