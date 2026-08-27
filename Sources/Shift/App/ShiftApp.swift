import SwiftUI

public struct ShiftRootView: View {
    @StateObject private var environment = AppEnvironment.shared

    public init() {}

    public var body: some View {
        MainTabView(engine: environment.engine)
    }
}
