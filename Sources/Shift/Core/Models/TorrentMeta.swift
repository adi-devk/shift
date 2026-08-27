import Foundation

public struct TorrentFileItem: Identifiable, Codable, Sendable {
    public let id: UUID
    public let path: String
    public let length: Int64
    public var isSelected: Bool

    public init(id: UUID = UUID(), path: String, length: Int64, isSelected: Bool = true) {
        self.id = id
        self.path = path
        self.length = length
        self.isSelected = isSelected
    }

    public var formattedLength: String {
        ByteCountFormatter.formatBytes(length)
    }
}

public struct TorrentMeta: Identifiable, Codable, Sendable {
    public let id: UUID
    public var infoHash: String
    public var displayName: String
    public var trackers: [String]
    public var totalLength: Int64
    public var pieceLength: Int
    public var pieceCount: Int
    public var files: [TorrentFileItem]
    public var comment: String?
    public var createdBy: String?
    public var creationDate: Date?

    public init(
        id: UUID = UUID(),
        infoHash: String,
        displayName: String,
        trackers: [String] = [],
        totalLength: Int64 = 0,
        pieceLength: Int = 262144, // 256KB default
        pieceCount: Int = 0,
        files: [TorrentFileItem] = [],
        comment: String? = nil,
        createdBy: String? = nil,
        creationDate: Date? = nil
    ) {
        self.id = id
        self.infoHash = infoHash
        self.displayName = displayName
        self.trackers = trackers
        self.totalLength = totalLength
        self.pieceLength = pieceLength
        self.pieceCount = pieceCount
        self.files = files
        self.comment = comment
        self.createdBy = createdBy
        self.creationDate = creationDate
    }

    public var formattedSize: String {
        ByteCountFormatter.formatBytes(totalLength)
    }

    public static func parseMagnetLink(_ uriString: String) -> TorrentMeta? {
        guard uriString.hasPrefix("magnet:?") else { return nil }
        guard let urlComponents = URLComponents(string: uriString) else { return nil }

        var infoHash = ""
        var displayName = "Untitled Torrent"
        var trackers: [String] = []

        for item in urlComponents.queryItems ?? [] {
            if item.name == "xt", let value = item.value {
                if value.lowercased().hasPrefix("urn:btih:") {
                    infoHash = String(value.dropFirst(9)).uppercased()
                }
            } else if item.name == "dn", let value = item.value {
                let cleanVal = value.replacingOccurrences(of: "+", with: " ")
                displayName = cleanVal.removingPercentEncoding ?? cleanVal
            } else if item.name == "tr", let value = item.value {
                let cleanVal = value.replacingOccurrences(of: "+", with: " ")
                if let decoded = cleanVal.removingPercentEncoding {
                    trackers.append(decoded)
                }
            }
        }

        guard !infoHash.isEmpty else { return nil }

        return TorrentMeta(
            infoHash: infoHash,
            displayName: displayName,
            trackers: trackers
        )
    }
}
