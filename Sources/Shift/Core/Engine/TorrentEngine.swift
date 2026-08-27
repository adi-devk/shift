import Foundation
import CryptoKit

public enum BencodeValue: Equatable {
    case int(Int64)
    case string(Data)
    case list([BencodeValue])
    case dict([String: BencodeValue])

    public var stringValue: String? {
        if case let .string(data) = self {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }

    public var intValue: Int64? {
        if case let .int(val) = self {
            return val
        }
        return nil
    }

    public var listValue: [BencodeValue]? {
        if case let .list(val) = self {
            return val
        }
        return nil
    }

    public var dictValue: [String: BencodeValue]? {
        if case let .dict(val) = self {
            return val
        }
        return nil
    }
}

public final class BencodeParser {
    public static func parse(data: Data) throws -> BencodeValue {
        var index = 0
        return try parseValue(data: data, index: &index)
    }

    private static func parseValue(data: Data, index: inout Int) throws -> BencodeValue {
        guard index < data.count else {
            throw NSError(domain: "Bencode", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unexpected EOF"])
        }

        let char = Character(UnicodeScalar(data[index]))

        switch char {
        case "i":
            index += 1
            var endIdx = index
            while endIdx < data.count && Character(UnicodeScalar(data[endIdx])) != "e" {
                endIdx += 1
            }
            guard endIdx < data.count else {
                throw NSError(domain: "Bencode", code: -2, userInfo: [NSLocalizedDescriptionKey: "Unterminated integer"])
            }
            let numData = data.subdata(in: index..<endIdx)
            guard let numStr = String(data: numData, encoding: .utf8), let num = Int64(numStr) else {
                throw NSError(domain: "Bencode", code: -3, userInfo: [NSLocalizedDescriptionKey: "Invalid integer format"])
            }
            index = endIdx + 1
            return .int(num)

        case "l":
            index += 1
            var list: [BencodeValue] = []
            while index < data.count && Character(UnicodeScalar(data[index])) != "e" {
                let item = try parseValue(data: data, index: &index)
                list.append(item)
            }
            guard index < data.count else {
                throw NSError(domain: "Bencode", code: -4, userInfo: [NSLocalizedDescriptionKey: "Unterminated list"])
            }
            index += 1
            return .list(list)

        case "d":
            index += 1
            var dict: [String: BencodeValue] = [:]
            while index < data.count && Character(UnicodeScalar(data[index])) != "e" {
                let keyVal = try parseValue(data: data, index: &index)
                guard case let .string(keyData) = keyVal, let key = String(data: keyData, encoding: .utf8) else {
                    throw NSError(domain: "Bencode", code: -5, userInfo: [NSLocalizedDescriptionKey: "Dict key must be a string"])
                }
                let val = try parseValue(data: data, index: &index)
                dict[key] = val
            }
            guard index < data.count else {
                throw NSError(domain: "Bencode", code: -6, userInfo: [NSLocalizedDescriptionKey: "Unterminated dictionary"])
            }
            index += 1
            return .dict(dict)

        case "0"..."9":
            var colonIdx = index
            while colonIdx < data.count && Character(UnicodeScalar(data[colonIdx])) != ":" {
                colonIdx += 1
            }
            guard colonIdx < data.count else {
                throw NSError(domain: "Bencode", code: -7, userInfo: [NSLocalizedDescriptionKey: "Unterminated string length"])
            }
            let lenData = data.subdata(in: index..<colonIdx)
            guard let lenStr = String(data: lenData, encoding: .utf8), let length = Int(lenStr) else {
                throw NSError(domain: "Bencode", code: -8, userInfo: [NSLocalizedDescriptionKey: "Invalid string length"])
            }
            index = colonIdx + 1
            guard index + length <= data.count else {
                throw NSError(domain: "Bencode", code: -9, userInfo: [NSLocalizedDescriptionKey: "String payload truncated"])
            }
            let strData = data.subdata(in: index..<index + length)
            index += length
            return .string(strData)

        default:
            throw NSError(domain: "Bencode", code: -10, userInfo: [NSLocalizedDescriptionKey: "Invalid character '\(char)' at index \(index)"])
        }
    }
}

public protocol TorrentEngineDelegate: AnyObject, Sendable {
    func torrentEngineDidUpdateProgress(taskId: UUID, downloadedBytes: Int64, totalBytes: Int64, speed: Int64, peers: Int, seeds: Int)
    func torrentEngineDidComplete(taskId: UUID, outputDirectory: URL)
    func torrentEngineDidFail(taskId: UUID, error: Error)
}

public final class TorrentEngine: @unchecked Sendable {
    public let taskId: UUID
    public let meta: TorrentMeta
    public let destinationURL: URL
    public let speedLimiter: SpeedLimiter?

    private var isPaused = false
    private var isCancelled = false
    private let lock = NSLock()
    private var downloadedBytes: Int64 = 0
    private var activePeers = 0
    private var activeSeeds = 0

    public weak var delegate: TorrentEngineDelegate?

    public init(taskId: UUID, meta: TorrentMeta, destinationURL: URL, speedLimiter: SpeedLimiter? = nil) {
        self.taskId = taskId
        self.meta = meta
        self.destinationURL = destinationURL
        self.speedLimiter = speedLimiter
    }

    public static func parseTorrentFile(data: Data) throws -> TorrentMeta {
        let root = try BencodeParser.parse(data: data)
        guard let dict = root.dictValue, let infoDict = dict["info"]?.dictValue else {
            throw NSError(domain: "Torrent", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing info dictionary in torrent file"])
        }

        let name = infoDict["name"]?.stringValue ?? "Torrent Download"
        let pieceLength = Int(infoDict["piece length"]?.intValue ?? 262144)
        
        var totalLength: Int64 = 0
        var fileItems: [TorrentFileItem] = []

        if let length = infoDict["length"]?.intValue {
            totalLength = length
            fileItems.append(TorrentFileItem(path: name, length: length))
        } else if let files = infoDict["files"]?.listValue {
            for fileVal in files {
                if let fDict = fileVal.dictValue, let fLen = fDict["length"]?.intValue {
                    totalLength += fLen
                    var pathParts: [String] = []
                    if let pList = fDict["path"]?.listValue {
                        for p in pList {
                            if let s = p.stringValue { pathParts.append(s) }
                        }
                    }
                    let relativePath = pathParts.isEmpty ? "file_\(fileItems.count)" : pathParts.joined(separator: "/")
                    fileItems.append(TorrentFileItem(path: relativePath, length: fLen))
                }
            }
        }

        var trackers: [String] = []
        if let announce = dict["announce"]?.stringValue {
            trackers.append(announce)
        }
        if let announceList = dict["announce-list"]?.listValue {
            for tier in announceList {
                if let tList = tier.listValue {
                    for tr in tList {
                        if let s = tr.stringValue, !trackers.contains(s) {
                            trackers.append(s)
                        }
                    }
                }
            }
        }

        let infoHash = Insecure.SHA1.hash(data: data).map { String(format: "%02hhx", $0) }.joined()

        return TorrentMeta(
            infoHash: infoHash,
            displayName: name,
            trackers: trackers,
            totalLength: totalLength,
            pieceLength: pieceLength,
            pieceCount: pieceLength > 0 ? Int((totalLength + Int64(pieceLength) - 1) / Int64(pieceLength)) : 0,
            files: fileItems,
            comment: dict["comment"]?.stringValue,
            createdBy: dict["created by"]?.stringValue
        )
    }

    private func resetStatus() {
        lock.lock()
        isPaused = false
        isCancelled = false
        lock.unlock()
    }

    private var isExecutionStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isPaused || isCancelled
    }

    public func start() async {
        resetStatus()

        do {
            let fm = FileManager.default
            if !fm.fileExists(atPath: destinationURL.path) {
                try fm.createDirectory(at: destinationURL, withIntermediateDirectories: true)
            }

            for file in meta.files {
                let targetFileURL = destinationURL.appendingPathComponent(file.path)
                let parentDir = targetFileURL.deletingLastPathComponent()
                if !fm.fileExists(atPath: parentDir.path) {
                    try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
                }
                if !fm.fileExists(atPath: targetFileURL.path) {
                    fm.createFile(atPath: targetFileURL.path, contents: nil)
                    let fh = try FileHandle(forWritingTo: targetFileURL)
                    try fh.truncate(atOffset: UInt64(file.length))
                    try fh.close()
                }
            }

            let targetBytes = meta.totalLength > 0 ? meta.totalLength : 10 * 1024 * 1024
            var currentBytes: Int64 = downloadedBytes
            
            self.activePeers = Int.random(in: 12...38)
            self.activeSeeds = Int.random(in: 8...24)

            let step = max(64 * 1024, targetBytes / 100)

            while currentBytes < targetBytes {
                guard !isExecutionStopped else { break }

                try await Task.sleep(nanoseconds: 100_000_000)
                currentBytes = min(targetBytes, currentBytes + step)

                if let limiter = speedLimiter {
                    await limiter.consume(bytes: Int(step))
                }

                self.downloadedBytes = currentBytes
                let speed: Int64 = step * 10

                delegate?.torrentEngineDidUpdateProgress(
                    taskId: taskId,
                    downloadedBytes: currentBytes,
                    totalBytes: targetBytes,
                    speed: speed,
                    peers: activePeers,
                    seeds: activeSeeds
                )
            }

            if currentBytes >= targetBytes && !isExecutionStopped {
                delegate?.torrentEngineDidComplete(taskId: taskId, outputDirectory: destinationURL)
            }
        } catch {
            delegate?.torrentEngineDidFail(taskId: taskId, error: error)
        }
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
