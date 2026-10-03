import SwiftUI

@main
struct GlucoseCompanionWatchApp: App {
    @State private var model = WatchModel()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(model)
                .task { await model.start() }
        }
    }
}
