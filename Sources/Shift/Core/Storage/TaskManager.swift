import Foundation

public final class TaskManager: @unchecked Sendable {
    public static let shared = TaskManager()

    private let fileManager = FileManager.default
    private let tasksFileURL: URL

    public init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        let admDir = appSupport.appendingPathComponent("Shift", isDirectory: true)
        if !fileManager.fileExists(atPath: admDir.path) {
            try? fileManager.createDirectory(at: admDir, withIntermediateDirectories: true)
        }
        self.tasksFileURL = admDir.appendingPathComponent("tasks_store.json")
    }

    public func clearAllTasks() {
        try? fileManager.removeItem(at: tasksFileURL)
    }

    public func saveTasks(_ tasks: [DownloadTask]) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(tasks)
            try data.write(to: tasksFileURL, options: .atomic)
        } catch {
            print("Failed to save tasks: \(error)")
        }
    }

    public func loadTasks() -> [DownloadTask] {
        guard fileManager.fileExists(atPath: tasksFileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: tasksFileURL)
            let decoder = JSONDecoder()
            var tasks = try decoder.decode([DownloadTask].self, from: data)

            for i in 0..<tasks.count {
                if tasks[i].status == .downloading || tasks[i].status == .connecting {
                    tasks[i].status = .paused
                }
            }
            return tasks
        } catch {
            print("Failed to load tasks: \(error)")
            return []
        }
    }
}
