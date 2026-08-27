import Foundation

public struct WidgetTaskSnapshot: Codable, Identifiable, Sendable {
    public let id: UUID
    public let fileName: String
    public let progress: Double
    public let speedFormatted: String
    public let downloadedFormatted: String
    public let totalFormatted: String
    public let etaFormatted: String
    public let categoryIcon: String
    public let statusRaw: String

    public init(
        id: UUID,
        fileName: String,
        progress: Double,
        speedFormatted: String,
        downloadedFormatted: String,
        totalFormatted: String,
        etaFormatted: String,
        categoryIcon: String,
        statusRaw: String
    ) {
        self.id = id
        self.fileName = fileName
        self.progress = progress
        self.speedFormatted = speedFormatted
        self.downloadedFormatted = downloadedFormatted
        self.totalFormatted = totalFormatted
        self.etaFormatted = etaFormatted
        self.categoryIcon = categoryIcon
        self.statusRaw = statusRaw
    }
}

public struct WidgetDataSnapshot: Codable, Sendable {
    public let activeTasks: [WidgetTaskSnapshot]
    public let totalActiveCount: Int
    public let overallProgress: Double
    public let globalSpeedFormatted: String
    public let globalSpeedBytes: Int64
    public let totalDownloadedFormatted: String
    public let totalSizeFormatted: String
    public let totalDownloadedBytes: Int64
    public let totalFileSizeBytes: Int64
    public let lastUpdated: Date

    public init(
        activeTasks: [WidgetTaskSnapshot] = [],
        totalActiveCount: Int = 0,
        overallProgress: Double = 0.0,
        globalSpeedFormatted: String = "0 B/s",
        globalSpeedBytes: Int64 = 0,
        totalDownloadedFormatted: String = "0 B",
        totalSizeFormatted: String = "0 B",
        totalDownloadedBytes: Int64 = 0,
        totalFileSizeBytes: Int64 = 0,
        lastUpdated: Date = Date()
    ) {
        self.activeTasks = activeTasks
        self.totalActiveCount = totalActiveCount
        self.overallProgress = overallProgress
        self.globalSpeedFormatted = globalSpeedFormatted
        self.globalSpeedBytes = globalSpeedBytes
        self.totalDownloadedFormatted = totalDownloadedFormatted
        self.totalSizeFormatted = totalSizeFormatted
        self.totalDownloadedBytes = totalDownloadedBytes
        self.totalFileSizeBytes = totalFileSizeBytes
        self.lastUpdated = lastUpdated
    }

    public static let empty = WidgetDataSnapshot()
}
