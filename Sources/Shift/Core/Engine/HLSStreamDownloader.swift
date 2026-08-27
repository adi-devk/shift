import Foundation
import CryptoKit

public struct HLSSegmentItem: Sendable {
    public let index: Int
    public let url: URL
    public let duration: Double
    public let keyURL: URL?
    public let keyIV: Data?
    public var byteRange: Range<Int64>?

    public init(index: Int, url: URL, duration: Double, keyURL: URL? = nil, keyIV: Data? = nil, byteRange: Range<Int64>? = nil) {
        self.index = index
        self.url = url
        self.duration = duration
        self.keyURL = keyURL
        self.keyIV = keyIV
        self.byteRange = byteRange
    }
}

public struct HLSVariantStream: Sendable {
    public let bandwidth: Int
    public let resolution: String?
    public let codecs: String?
    public let url: URL
}

public final class HLSPlaylistParser: Sendable {
    public init() {}

    public static func parse(content: String, baseURL: URL) -> (variants: [HLSVariantStream], segments: [HLSSegmentItem]) {
        let lines = content.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        
        var variants: [HLSVariantStream] = []
        var segments: [HLSSegmentItem] = []

        var currentBandwidth = 0
        var currentResolution: String? = nil
        var currentCodecs: String? = nil
        
        var currentDuration = 0.0
        var currentKeyURL: URL? = nil
        var currentKeyIV: Data? = nil
        var segmentIndex = 0

        for line in lines {
            if line.hasPrefix("#EXT-X-STREAM-INF:") {
                let attributes = line.dropFirst("#EXT-X-STREAM-INF:".count)
                if let bwRange = attributes.range(of: "BANDWIDTH=([0-9]+)", options: .regularExpression) {
                    let bwStr = attributes[bwRange].replacingOccurrences(of: "BANDWIDTH=", with: "")
                    currentBandwidth = Int(bwStr) ?? 0
                }
                if let resRange = attributes.range(of: "RESOLUTION=([0-9]+x[0-9]+)", options: .regularExpression) {
                    currentResolution = attributes[resRange].replacingOccurrences(of: "RESOLUTION=", with: "")
                }
                if let codecsRange = attributes.range(of: "CODECS=\"([^\"]+)\"", options: .regularExpression) {
                    currentCodecs = attributes[codecsRange].replacingOccurrences(of: "CODECS=\"", with: "").replacingOccurrences(of: "\"", with: "")
                }
            } else if line.hasPrefix("#EXT-X-KEY:") {
                if let uriRange = line.range(of: "URI=\"([^\"]+)\"", options: .regularExpression) {
                    let uriStr = line[uriRange].replacingOccurrences(of: "URI=\"", with: "").replacingOccurrences(of: "\"", with: "")
                    if let keyURL = URL(string: uriStr, relativeTo: baseURL)?.absoluteURL {
                        currentKeyURL = keyURL
                    }
                }
            } else if line.hasPrefix("#EXTINF:") {
                let durStr = line.dropFirst("#EXTINF:".count).components(separatedBy: ",")[0]
                currentDuration = Double(durStr) ?? 0.0
            } else if !line.hasPrefix("#") {
                if let segURL = URL(string: line, relativeTo: baseURL)?.absoluteURL {
                    if currentBandwidth > 0 {
                        variants.append(HLSVariantStream(bandwidth: currentBandwidth, resolution: currentResolution, codecs: currentCodecs, url: segURL))
                        currentBandwidth = 0
                        currentResolution = nil
                        currentCodecs = nil
                    } else {
                        segments.append(
                            HLSSegmentItem(
                                index: segmentIndex,
                                url: segURL,
                                duration: currentDuration,
                                keyURL: currentKeyURL,
                                keyIV: currentKeyIV
                            )
                        )
                        segmentIndex += 1
                        currentDuration = 0.0
                    }
                }
            }
        }

        return (variants, segments)
    }
}

public protocol HLSStreamDownloaderDelegate: AnyObject, Sendable {
    func hlsDownloaderDidUpdateProgress(taskId: UUID, downloadedSegments: Int, totalSegments: Int, downloadedBytes: Int64, speed: Int64)
    func hlsDownloaderDidComplete(taskId: UUID, fileURL: URL)
    func hlsDownloaderDidFail(taskId: UUID, error: Error)
}

public final class HLSStreamDownloader: @unchecked Sendable {
    public let taskId: UUID
    public let masterURL: URL
    public let destinationURL: URL
    public let maxConcurrency: Int
    public let customHeaders: [String: String]
    public let userAgent: String?
    public let speedLimiter: SpeedLimiter?

    private var isPaused = false
    private var isCancelled = false
    private let lock = NSLock()
    private var downloadedBytes: Int64 = 0
    private var completedSegmentsCount = 0
    private var lastSpeedCalcTime = Date()
    private var bytesSinceLastCalc: Int64 = 0
    private var currentSpeed: Int64 = 0

    public weak var delegate: HLSStreamDownloaderDelegate?

    public init(
        taskId: UUID,
        masterURL: URL,
        destinationURL: URL,
        maxConcurrency: Int = 8,
        customHeaders: [String: String] = [:],
        userAgent: String? = nil,
        speedLimiter: SpeedLimiter? = nil
    ) {
        self.taskId = taskId
        self.masterURL = masterURL
        self.destinationURL = destinationURL
        self.maxConcurrency = max(1, min(16, maxConcurrency))
        self.customHeaders = customHeaders
        self.userAgent = userAgent
        self.speedLimiter = speedLimiter
    }

    private func resetStatus() {
        lock.lock()
        isPaused = false
        isCancelled = false
        lock.unlock()
    }

    public func start() async {
        resetStatus()

        do {
            var request = URLRequest(url: masterURL)
            for (k, v) in customHeaders { request.setValue(v, forHTTPHeaderField: k) }
            if let ua = userAgent, !ua.isEmpty { request.setValue(ua, forHTTPHeaderField: "User-Agent") }

            let (data, _) = try await URLSession.shared.data(for: request)
            guard let content = String(data: data, encoding: .utf8) else {
                throw NSError(domain: "Shift_HLS", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid M3U8 UTF-8 playlist data"])
            }

            var (variants, segments) = HLSPlaylistParser.parse(content: content, baseURL: masterURL)

            if segments.isEmpty && !variants.isEmpty {
                let highest = variants.sorted { $0.bandwidth > $1.bandwidth }.first!
                var varRequest = URLRequest(url: highest.url)
                for (k, v) in customHeaders { varRequest.setValue(v, forHTTPHeaderField: k) }
                if let ua = userAgent, !ua.isEmpty { varRequest.setValue(ua, forHTTPHeaderField: "User-Agent") }

                let (varData, _) = try await URLSession.shared.data(for: varRequest)
                if let varContent = String(data: varData, encoding: .utf8) {
                    let parsed = HLSPlaylistParser.parse(content: varContent, baseURL: highest.url)
                    segments = parsed.segments
                }
            }

            guard !segments.isEmpty else {
                throw NSError(domain: "Shift_HLS", code: -2, userInfo: [NSLocalizedDescriptionKey: "No media segments found in M3U8 playlist"])
            }

            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("adm_hls_\(taskId.uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            var segmentBuffers: [Int: Data] = [:]
            let totalSegments = segments.count

            try await withThrowingTaskGroup(of: (Int, Data).self) { group in
                var iterator = segments.makeIterator()
                var activeCount = 0

                while activeCount < self.maxConcurrency, let next = iterator.next() {
                    group.addTask {
                        let segData = try await self.downloadSegmentData(next)
                        return (next.index, segData)
                    }
                    activeCount += 1
                }

                while let result = try await group.next() {
                    let (idx, segData) = result
                    self.recordSegmentCompletion(index: idx, data: segData, totalSegments: totalSegments, buffers: &segmentBuffers)

                    if let next = iterator.next() {
                        group.addTask {
                            let nextData = try await self.downloadSegmentData(next)
                            return (next.index, nextData)
                        }
                    }
                }
            }

            // Merge segments sequentially to destination file
            let destDir = destinationURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: destinationURL.path, contents: nil)
            
            let fileHandle = try FileHandle(forWritingTo: destinationURL)
            for i in 0..<totalSegments {
                if let segData = segmentBuffers[i] {
                    try fileHandle.write(contentsOf: segData)
                }
            }
            try fileHandle.close()
            try? FileManager.default.removeItem(at: tempDir)

            delegate?.hlsDownloaderDidComplete(taskId: taskId, fileURL: destinationURL)
        } catch {
            delegate?.hlsDownloaderDidFail(taskId: taskId, error: error)
        }
    }

    private func recordSegmentCompletion(index: Int, data: Data, totalSegments: Int, buffers: inout [Int: Data]) {
        lock.lock()
        buffers[index] = data
        self.downloadedBytes += Int64(data.count)
        self.completedSegmentsCount += 1
        self.bytesSinceLastCalc += Int64(data.count)
        
        let now = Date()
        let interval = now.timeIntervalSince(self.lastSpeedCalcTime)
        if interval >= 0.5 {
            self.currentSpeed = Int64(Double(self.bytesSinceLastCalc) / interval)
            self.bytesSinceLastCalc = 0
            self.lastSpeedCalcTime = now
        }

        let curDown = self.downloadedBytes
        let curCount = self.completedSegmentsCount
        let curSpeed = self.currentSpeed
        lock.unlock()

        delegate?.hlsDownloaderDidUpdateProgress(
            taskId: self.taskId,
            downloadedSegments: curCount,
            totalSegments: totalSegments,
            downloadedBytes: curDown,
            speed: curSpeed
        )
    }

    private func downloadSegmentData(_ segment: HLSSegmentItem) async throws -> Data {
        var request = URLRequest(url: segment.url)
        request.timeoutInterval = 20.0
        for (k, v) in customHeaders { request.setValue(v, forHTTPHeaderField: k) }
        if let ua = userAgent, !ua.isEmpty { request.setValue(ua, forHTTPHeaderField: "User-Agent") }

        if let limiter = speedLimiter {
            await limiter.consume(bytes: 4096)
        }

        let (data, _) = try await URLSession.shared.data(for: request)
        return data
    }

    public func pause() {
        lock.lock()
        isPaused = true
        lock.unlock()
    }

    public func cancel() {
        lock.lock()
        isCancelled = true
        lock.unlock()
    }
}
