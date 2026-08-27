import SwiftUI
import Combine

@MainActor
public final class AppEnvironment: ObservableObject {
    public static let shared = AppEnvironment()

    public let engine: ShiftDownloadEngine
    private var cancellables = Set<AnyCancellable>()

    public init() {
        // Bootstrap base documents directories so iOS Files app registers the Shift folder
        FileStorageService.shared.bootstrapDirectories()

        let loadedTasks = TaskManager.shared.loadTasks()
        let initialEngine = ShiftDownloadEngine()
        initialEngine.tasks = loadedTasks

        self.engine = initialEngine

        // Auto-persist tasks on change on background queue
        initialEngine.$tasks
            .debounce(for: .seconds(2), scheduler: DispatchQueue.global(qos: .utility))
            .sink { tasks in
                TaskManager.shared.saveTasks(tasks)
            }
            .store(in: &cancellables)
    }
}
