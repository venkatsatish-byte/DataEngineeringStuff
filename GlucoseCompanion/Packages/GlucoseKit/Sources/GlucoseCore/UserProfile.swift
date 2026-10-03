import Foundation

public struct UserProfile: Codable, Equatable, Sendable {
    public var unit: GlucoseUnit = .mgdL
    public var targets: TargetRange = .standard
    public var usesCGM: Bool = true
    public var stepGoal: Int = 7000
    public var activeMinutesGoal: Int = 30
    public var careContactName: String = ""
    public var careContactPhone: String = ""
    public var hapticAlertsEnabled: Bool = true
    public var hasCompletedOnboarding: Bool = false
    public var acceptedDisclaimerVersion: Int = 0
    public var acceptedDisclaimerAt: Date?

    public init() {}

    public var hasAcceptedCurrentDisclaimer: Bool {
        acceptedDisclaimerVersion >= SafetyCopy.disclaimerVersion
    }

    public mutating func acceptDisclaimer(at date: Date = .now) {
        acceptedDisclaimerVersion = SafetyCopy.disclaimerVersion
        acceptedDisclaimerAt = date
    }

    // Decoding falls back to defaults for missing keys, so adding a setting in
    // a later version never wipes the user's saved profile.
    private enum CodingKeys: String, CodingKey {
        case unit, targets, usesCGM, stepGoal, activeMinutesGoal, careContactName, careContactPhone
        case hapticAlertsEnabled, hasCompletedOnboarding, acceptedDisclaimerVersion, acceptedDisclaimerAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = UserProfile()
        unit = try c.decodeIfPresent(GlucoseUnit.self, forKey: .unit) ?? d.unit
        targets = try c.decodeIfPresent(TargetRange.self, forKey: .targets) ?? d.targets
        usesCGM = try c.decodeIfPresent(Bool.self, forKey: .usesCGM) ?? d.usesCGM
        stepGoal = try c.decodeIfPresent(Int.self, forKey: .stepGoal) ?? d.stepGoal
        activeMinutesGoal = try c.decodeIfPresent(Int.self, forKey: .activeMinutesGoal) ?? d.activeMinutesGoal
        careContactName = try c.decodeIfPresent(String.self, forKey: .careContactName) ?? d.careContactName
        careContactPhone = try c.decodeIfPresent(String.self, forKey: .careContactPhone) ?? d.careContactPhone
        hapticAlertsEnabled = try c.decodeIfPresent(Bool.self, forKey: .hapticAlertsEnabled) ?? d.hapticAlertsEnabled
        hasCompletedOnboarding = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? d.hasCompletedOnboarding
        acceptedDisclaimerVersion = try c.decodeIfPresent(Int.self, forKey: .acceptedDisclaimerVersion) ?? d.acceptedDisclaimerVersion
        acceptedDisclaimerAt = try c.decodeIfPresent(Date.self, forKey: .acceptedDisclaimerAt)
    }
}

public struct Reminder: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Identifiable, Sendable {
        case glucoseCheck, medication, activity, hydration, postMealWalk

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .glucoseCheck: return "Check glucose"
            case .medication: return "Medication"
            case .activity: return "Get moving"
            case .hydration: return "Drink water"
            case .postMealWalk: return "Walk after meals"
            }
        }

        public var systemImage: String {
            switch self {
            case .glucoseCheck: return "drop"
            case .medication: return "pills"
            case .activity: return "figure.walk"
            case .hydration: return "waterbottle"
            case .postMealWalk: return "figure.walk.motion"
            }
        }

        /// Post-meal walk reminders fire after each logged meal, not at a set time.
        public var isMealTriggered: Bool { self == .postMealWalk }
    }

    public var id: UUID
    public var kind: Kind
    /// Free text. Medication reminders hold a label only; there is no dose field.
    public var title: String
    public var hour: Int
    public var minute: Int
    /// Calendar weekdays, 1 = Sunday … 7 = Saturday. Empty means every day.
    public var weekdays: Set<Int>
    /// For meal-triggered reminders: minutes after the meal.
    public var minutesAfterMeal: Int
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(), kind: Kind, title: String? = nil, hour: Int = 9, minute: Int = 0,
        weekdays: Set<Int> = [], minutesAfterMeal: Int = 20, isEnabled: Bool = true
    ) {
        self.id = id
        self.kind = kind
        self.title = title ?? kind.title
        self.hour = hour
        self.minute = minute
        self.weekdays = weekdays
        self.minutesAfterMeal = minutesAfterMeal
        self.isEnabled = isEnabled
    }

    public static let defaults: [Reminder] = [
        Reminder(kind: .glucoseCheck, title: "Morning glucose check", hour: 7, minute: 30),
        Reminder(kind: .postMealWalk, title: "Short walk after meals", minutesAfterMeal: 20),
        Reminder(kind: .hydration, title: "Drink a glass of water", hour: 14, minute: 0, isEnabled: false),
    ]
}
