import Foundation
import SwiftUI
#if canImport(Photos)
import Photos
#endif
#if canImport(UIKit)
import UIKit
#endif

public struct LocalFileItem: Identifiable, Sendable {
    public let id = UUID()
    public let url: URL
    public let name: String
    public let size: Int64
    public let category: TaskCategory
    public let modificationDate: Date
    public let isDirectory: Bool

    public var formattedSize: String {
        ByteCountFormatter.formatBytes(size)
    }

    public var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: modificationDate)
    }
}

public struct StorageBreakdown: Sendable {
    public let totalDiskSpace: Int64
    public let freeDiskSpace: Int64
    public let appUsageBytes: Int64
    public let downloadsBytes: Int64
    public let categoryBytes: [TaskCategory: Int64]
}

public final class FileStorageService: @unchecked Sendable {
    public static let shared = FileStorageService()

    private let fileManager = FileManager.default

    /// The base documents directory that appears directly in the iOS Files app under "On My iPhone > Shift"
    public var baseDownloadsURL: URL {
        let urls = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        let docURL = urls.first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        if !fileManager.fileExists(atPath: docURL.path) {
            try? fileManager.createDirectory(at: docURL, withIntermediateDirectories: true)
        }
        return docURL
    }

    /// Pre-creates category directories and initial marker file so iOS Files app immediately displays Shift folder
    public func bootstrapDirectories() {
        let docURL = baseDownloadsURL
        let categories = TaskCategory.allCases.filter { $0 != .all }
        for cat in categories {
            _ = getCategoryDirectory(for: cat)
        }
        
        let marker = docURL.appendingPathComponent(".shift_initialized")
        if !fileManager.fileExists(atPath: marker.path) {
            try? "Shift Download Manager Initialized".write(to: marker, atomically: true, encoding: .utf8)
        }
        // Clean legacy log and initialization files from Documents if they exist
        try? fileManager.removeItem(at: docURL.appendingPathComponent("Shift_Diagnostics.log"))
        try? fileManager.removeItem(at: docURL.appendingPathComponent(".adm_initialized"))
    }

    public func getCategoryDirectory(for category: TaskCategory) -> URL {
        let catURL = baseDownloadsURL.appendingPathComponent(category.rawValue, isDirectory: true)
        if !fileManager.fileExists(atPath: catURL.path) {
            try? fileManager.createDirectory(at: catURL, withIntermediateDirectories: true)
        }
        return catURL
    }

    public func suggestUniqueFileName(baseName: String, category: TaskCategory) -> String {
        let dir = getCategoryDirectory(for: category)
        let nameURL = URL(fileURLWithPath: baseName)
        let nameWithoutExt = nameURL.deletingPathExtension().lastPathComponent
        let ext = nameURL.pathExtension

        var counter = 1
        var candidate = baseName
        while fileManager.fileExists(atPath: dir.appendingPathComponent(candidate).path) {
            if ext.isEmpty {
                candidate = "\(nameWithoutExt) (\(counter))"
            } else {
                candidate = "\(nameWithoutExt) (\(counter)).\(ext)"
            }
            counter += 1
        }
        return candidate
    }

    public func fileExists(fileName: String, category: TaskCategory) -> Bool {
        let path = getCategoryDirectory(for: category).appendingPathComponent(fileName).path
        return fileManager.fileExists(atPath: path)
    }

    public func listFiles(in category: TaskCategory? = nil) -> [LocalFileItem] {
        var results: [LocalFileItem] = []
        let searchDir = (category != nil && category != .all) ? getCategoryDirectory(for: category!) : baseDownloadsURL

        guard let enumerator = fileManager.enumerator(
            at: searchDir,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey]) else {
                continue
            }

            let isDir = resourceValues.isDirectory ?? false
            let size = Int64(resourceValues.fileSize ?? 0)
            let modDate = resourceValues.contentModificationDate ?? Date()
            let cat = TaskCategory.determineCategory(from: fileURL.lastPathComponent)
            let filename = fileURL.lastPathComponent

            // Strictly filter out internal logs, diagnostic files, and hidden dotfiles
            if !isDir && !filename.hasPrefix(".") && !filename.hasSuffix(".log") && filename != "Shift_Diagnostics.log" {
                results.append(
                    LocalFileItem(
                        url: fileURL,
                        name: filename,
                        size: size,
                        category: cat,
                        modificationDate: modDate,
                        isDirectory: false
                    )
                )
            }
        }

        return results.sorted { $0.modificationDate > $1.modificationDate }
    }

    public func deleteFile(at url: URL) throws {
        try fileManager.removeItem(at: url)
    }

    public func renameFile(at url: URL, newName: String) throws -> URL {
        let newURL = url.deletingLastPathComponent().appendingPathComponent(newName)
        try fileManager.moveItem(at: url, to: newURL)
        return newURL
    }

    public func calculateStorageBreakdown() -> StorageBreakdown {
        var catUsage: [TaskCategory: Int64] = [:]
        for cat in TaskCategory.allCases { catUsage[cat] = 0 }

        var totalDownloadsSize: Int64 = 0
        let files = listFiles(in: .all)

        for file in files {
            catUsage[file.category, default: 0] += file.size
            totalDownloadsSize += file.size
        }

        var totalSpace: Int64 = 0
        var freeSpace: Int64 = 0

        if let attrs = try? fileManager.attributesOfFileSystem(forPath: baseDownloadsURL.path) {
            totalSpace = (attrs[.systemSize] as? NSNumber)?.int64Value ?? 0
            freeSpace = (attrs[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        }

        return StorageBreakdown(
            totalDiskSpace: totalSpace,
            freeDiskSpace: freeSpace,
            appUsageBytes: totalDownloadsSize,
            downloadsBytes: totalDownloadsSize,
            categoryBytes: catUsage
        )
    }

    public func clearAllDownloads() {
        for cat in TaskCategory.allCases where cat != .all {
            let catDir = getCategoryDirectory(for: cat)
            try? fileManager.removeItem(at: catDir)
        }
        bootstrapDirectories()
    }

    public func revealInFilesApp(url: URL? = nil) {
        let targetURL = url ?? baseDownloadsURL
        #if canImport(UIKit) && os(iOS)
        if let shareddocuments = URL(string: "shareddocuments://\(targetURL.path)"),
           UIApplication.shared.canOpenURL(shareddocuments) {
            UIApplication.shared.open(shareddocuments)
        } else {
            UIApplication.shared.open(targetURL)
        }
        #endif
    }

    #if canImport(Photos) && os(iOS)
    public func exportVideoToCameraRoll(fileURL: URL, completion: @escaping (Bool, Error?) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                completion(false, NSError(domain: "Photos", code: -1, userInfo: [NSLocalizedDescriptionKey: "Photos access denied"]))
                return
            }

            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
            }) { success, error in
                DispatchQueue.main.async {
                    completion(success, error)
                }
            }
        }
    }
    #endif
}
