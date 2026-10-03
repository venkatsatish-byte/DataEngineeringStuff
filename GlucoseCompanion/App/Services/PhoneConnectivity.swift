import Foundation
import GlucoseCore
import WatchConnectivity

/// Sends the user's settings (units, targets, alert preference) to the Watch,
/// and receives meals logged on the Watch. Glucose itself travels through
/// Apple Health, not through here.
final class PhoneConnectivity: NSObject, WCSessionDelegate {
    private var pending: UserProfile?
    /// Called on the main queue with each meal logged on the Watch.
    var onMealReceived: ((MealEvent) -> Void)?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ profile: UserProfile) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else {
            pending = profile
            return
        }
        guard session.isPaired, session.isWatchAppInstalled,
              let data = try? JSONEncoder().encode(profile) else { return }
        try? session.updateApplicationContext(["profile": data])
    }

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        guard state == .activated, let profile = pending else { return }
        pending = nil
        DispatchQueue.main.async { self.send(profile) }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo["meal"] as? Data, let meal = try? JSONDecoder().decode(MealEvent.self, from: data) else { return }
        DispatchQueue.main.async { self.onMealReceived?(meal) }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // Called when switching to another paired watch.
        session.activate()
    }
}
