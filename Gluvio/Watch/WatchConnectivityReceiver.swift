import Foundation
import GlucoseCore
import WatchConnectivity

/// Receives settings from the iPhone and sends meals logged on the Watch.
final class WatchConnectivityReceiver: NSObject, WCSessionDelegate {
    private let onProfile: (UserProfile) -> Void

    init(onProfile: @escaping (UserProfile) -> Void) {
        self.onProfile = onProfile
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Queued and delivered even if the iPhone is out of range right now.
    func send(_ meal: MealEvent) {
        guard WCSession.isSupported(), let data = try? JSONEncoder().encode(meal) else { return }
        WCSession.default.transferUserInfo(["meal": data])
    }

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        handle(session.receivedApplicationContext)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        handle(applicationContext)
    }

    private func handle(_ context: [String: Any]) {
        guard let data = context["profile"] as? Data,
              let profile = try? JSONDecoder().decode(UserProfile.self, from: data) else { return }
        onProfile(profile)
    }
}
