import Foundation
#if canImport(BackgroundTasks)
import BackgroundTasks
#endif

public final class BackgroundManager: NSObject, @unchecked Sendable {
    public static let shared = BackgroundManager()
    public static let backgroundSessionIdentifier = "com.shift.downloadmanager.background"
    public static let bgTaskIdentifier = "com.shift.downloadmanager.refresh"

    private var backgroundCompletionHandler: (@Sendable () -> Void)?

    public override init() {
        super.init()
    }

    public func setBackgroundCompletionHandler(_ handler: @escaping @Sendable () -> Void) {
        self.backgroundCompletionHandler = handler
    }

    public func callBackgroundCompletionHandler() {
        DispatchQueue.main.async {
            self.backgroundCompletionHandler?()
            self.backgroundCompletionHandler = nil
        }
    }

    public func registerBackgroundTasks() {
        #if canImport(BackgroundTasks) && os(iOS)
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.bgTaskIdentifier, using: nil) { task in
            guard let appRefresh = task as? BGAppRefreshTask else { return }
            self.handleAppRefresh(task: appRefresh)
        }
        #endif
    }

    #if canImport(BackgroundTasks) && os(iOS)
    private func handleAppRefresh(task: BGAppRefreshTask) {
        task.expirationHandler = {
            // Clean up resources if timed out
        }
        // Background work
        task.setTaskCompleted(success: true)
    }

    public func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.bgTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 mins
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Could not schedule BGTask: \(error)")
        }
    }
    #endif
}
