import SwiftUI

@main
struct GlucoseCompanionApp: App {
    @State private var host = AppHost()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(host)
                .environment(host.model)
                .task(id: ObjectIdentifier(host.model)) { await host.model.start() }
        }
    }
}

/// Owns the current `AppModel`, so the app can switch between real data and
/// sample data (for exploring the app, screenshots and App Review) without a
/// relaunch.
@Observable
@MainActor
final class AppHost {
    private(set) var model: AppModel

    init() {
        model = AppModel(options: .current)
    }

    func setDemoMode(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: LaunchOptions.demoModeKey)
        var options = LaunchOptions.current
        options.demoMode = on
        options.showOnboarding = false
        model = AppModel(options: options)
    }
}

/// Settings read from launch arguments, e.g. `-demoMode YES -initialTab trends`.
struct LaunchOptions {
    static let demoModeKey = "demoMode"

    var demoMode: Bool
    var initialTab: AppTab
    var showOnboarding: Bool
    var showUrgentDemo: Bool

    static var current: LaunchOptions {
        let defaults = UserDefaults.standard
        return LaunchOptions(
            demoMode: defaults.bool(forKey: demoModeKey),
            initialTab: defaults.string(forKey: "initialTab").flatMap(AppTab.init(rawValue:)) ?? .today,
            showOnboarding: defaults.bool(forKey: "showOnboarding"),
            showUrgentDemo: defaults.bool(forKey: "showUrgentDemo")
        )
    }
}

enum AppTab: String, Hashable {
    case today, trends, meals, guide, settings
}
