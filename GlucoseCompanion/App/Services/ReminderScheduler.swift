import Foundation
import GlucoseCore
import UserNotifications

/// Local notifications only. When the iPhone is locked, iOS mirrors them to
/// Apple Watch, which is how the Watch gets gentle reminders.
@MainActor
final class ReminderScheduler {
    private let center = UNUserNotificationCenter.current()
    private static let prefix = "reminder."

    func requestPermission() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func isAuthorized() async -> Bool {
        let status = await center.notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional
    }

    /// Replaces all scheduled time-based reminders with `reminders`.
    func reschedule(_ reminders: [Reminder]) async {
        guard await isAuthorized() else { return }
        let existing = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.prefix) }
        center.removePendingNotificationRequests(withIdentifiers: existing)

        for reminder in reminders where reminder.isEnabled && !reminder.kind.isMealTriggered {
            let days: [Int?] = reminder.weekdays.isEmpty ? [nil] : reminder.weekdays.sorted().map { Optional($0) }
            for day in days {
                var components = DateComponents()
                components.hour = reminder.hour
                components.minute = reminder.minute
                components.weekday = day
                let request = UNNotificationRequest(
                    identifier: "\(Self.prefix)\(reminder.id.uuidString).\(day ?? 0)",
                    content: content(title: reminder.title, body: Self.body(for: reminder.kind)),
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                )
                try? await center.add(request)
            }
        }
    }

    /// One-off nudges after a meal: a short walk, and for fingerstick users a
    /// two-hour check so the app can learn how the meal affected them.
    func mealLogged(_ meal: MealEvent, reminders: [Reminder], remindToCheck: Bool) async {
        guard await isAuthorized() else { return }
        if let walk = reminders.first(where: { $0.kind == .postMealWalk && $0.isEnabled }) {
            await scheduleOnce(
                id: "meal.\(meal.id.uuidString).walk",
                at: meal.date.addingTimeInterval(Double(walk.minutesAfterMeal) * 60),
                title: walk.title,
                body: Self.body(for: .postMealWalk)
            )
        }
        if remindToCheck {
            await scheduleOnce(
                id: "meal.\(meal.id.uuidString).check",
                at: meal.date.addingTimeInterval(2 * 3600),
                title: "2-hour check",
                body: "Check your blood sugar now to see how \(meal.displayName.lowercased()) affected you."
            )
        }
    }

    private func scheduleOnce(id: String, at date: Date, title: String, body: String) async {
        let interval = date.timeIntervalSinceNow
        guard interval > 1 else { return }
        let request = UNNotificationRequest(
            identifier: id,
            content: content(title: title, body: body),
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        )
        try? await center.add(request)
    }

    private func content(title: String, body: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        return content
    }

    static func body(for kind: Reminder.Kind) -> String {
        switch kind {
        case .glucoseCheck: return "Time to check your blood sugar."
        case .medication: return "Time for your medication, as your care team prescribed."
        case .activity: return "A few minutes of movement helps. Stand up and stretch or take a short walk."
        case .hydration: return "A glass of water is a good idea."
        case .postMealWalk: return "A 10–15 minute walk now can help with the rise after your meal."
        }
    }
}
