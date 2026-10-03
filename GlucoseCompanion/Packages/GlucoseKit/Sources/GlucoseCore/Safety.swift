import Foundation

/// User-facing safety wording. Changes here should be reviewed by the
/// clinical reviewer; bump `disclaimerVersion` for material changes so users
/// see and accept the new text.
public enum SafetyCopy {
    public static let disclaimerVersion = 1

    public static let disclaimerTitle = "Before you start"

    public static let disclaimerPoints: [String] = [
        "GlucoseCompanion helps you track and understand your blood sugar. It is not a medical device and does not diagnose or treat any condition.",
        "It never gives insulin or medication advice. Keep following the plan you agreed with your care team.",
        "Talk to your doctor before changing your diet, exercise or medication.",
        "Readings from Apple Health can arrive late. Your CGM or meter's own app remains your alarm for highs and lows.",
        "In an emergency, call your local emergency number.",
    ]

    public static let shortDisclaimer =
        "Not a substitute for medical care. Talk to your doctor before changing your diet, exercise or medication."

    public static let privacySummary =
        "Your health data stays on this device and in your own Apple Health. GlucoseCompanion has no account, no servers and no analytics, and never shares your data."
}

public struct UrgentAlert: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable { case low, high }

    public var id: UUID { readingID }
    public var readingID: UUID
    public var kind: Kind
    public var mgdL: Double
    public var readingDate: Date

    public init(readingID: UUID, kind: Kind, mgdL: Double, readingDate: Date) {
        self.readingID = readingID
        self.kind = kind
        self.mgdL = mgdL
        self.readingDate = readingDate
    }

    public var title: String {
        kind == .low ? "Your blood sugar is very low" : "Your blood sugar is very high"
    }

    public var steps: [String] {
        switch kind {
        case .low:
            return [
                "Follow your care plan for low blood sugar now.",
                "If you can't safely eat or drink, feel confused, or might pass out, call emergency services or ask someone nearby for help.",
                "Recheck your blood sugar as your care plan says, and don't drive until you have recovered.",
            ]
        case .high:
            return [
                "Follow your care plan for high blood sugar.",
                "Recheck your blood sugar to confirm the reading.",
                "Get medical help right away if you are vomiting, very drowsy, confused or breathing fast, or if your blood sugar stays this high.",
            ]
        }
    }
}

public enum SafetyGuidance {
    /// Returns an urgent alert for readings beyond the user's urgent thresholds.
    public static func alert(for sample: GlucoseSample, targets: TargetRange) -> UrgentAlert? {
        switch targets.band(for: sample.mgdL) {
        case .urgentLow:
            return UrgentAlert(readingID: sample.id, kind: .low, mgdL: sample.mgdL, readingDate: sample.date)
        case .urgentHigh:
            return UrgentAlert(readingID: sample.id, kind: .high, mgdL: sample.mgdL, readingDate: sample.date)
        default:
            return nil
        }
    }

    /// Manual entries outside this range are almost certainly typos.
    public static let plausibleRange: ClosedRange<Double> = 20...600

    /// Values that are plausible but unusual enough to confirm before saving.
    public static func needsConfirmation(_ mgdL: Double) -> Bool {
        mgdL < 54 || mgdL > 300
    }
}
