import SwiftUI
#if canImport(Shift)
import Shift
#endif

@main
struct ShiftApplication: App {
    var body: some Scene {
        WindowGroup {
            ShiftRootView()
        }
    }
}
