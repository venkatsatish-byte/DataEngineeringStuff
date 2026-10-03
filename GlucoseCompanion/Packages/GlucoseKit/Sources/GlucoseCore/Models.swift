import Foundation

public enum ReadingContext: String, Codable, CaseIterable, Identifiable, Sendable {
    case fasting, beforeMeal, afterMeal, bedtime, other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .fasting: return "Fasting"
        case .beforeMeal: return "Before meal"
        case .afterMeal: return "After meal"
        case .bedtime: return "Bedtime"
        case .other: return "Other"
        }
    }
}

public enum ReadingSource: String, Codable, Sendable {
    /// Typed into this app.
    case manual
    /// A continuous glucose monitor, via Apple Health.
    case cgm
    /// A meter or another app, via Apple Health.
    case meter
}

public struct GlucoseSample: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var date: Date
    public var mgdL: Double
    public var context: ReadingContext
    public var source: ReadingSource
    public var sourceName: String
    public var note: String

    public init(
        id: UUID = UUID(),
        date: Date,
        mgdL: Double,
        context: ReadingContext = .other,
        source: ReadingSource,
        sourceName: String = "",
        note: String = ""
    ) {
        self.id = id
        self.date = date
        self.mgdL = mgdL
        self.context = context
        self.source = source
        self.sourceName = sourceName
        self.note = note
    }
}

public enum MealKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case breakfast, lunch, dinner, snack

    public var id: String { rawValue }

    public var title: String { rawValue.capitalized }

    public var systemImage: String {
        switch self {
        case .breakfast: return "sunrise"
        case .lunch: return "sun.max"
        case .dinner: return "moon.stars"
        case .snack: return "carrot"
        }
    }

    /// A sensible default for the time of day.
    public static func suggested(for date: Date, calendar: Calendar = .current) -> MealKind {
        switch calendar.component(.hour, from: date) {
        case 4..<11: return .breakfast
        case 11..<16: return .lunch
        case 16..<22: return .dinner
        default: return .snack
        }
    }
}

public struct MealEvent: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var date: Date
    public var kind: MealKind
    public var name: String
    public var carbsGrams: Double
    public var note: String

    public init(id: UUID = UUID(), date: Date, kind: MealKind, name: String = "", carbsGrams: Double, note: String = "") {
        self.id = id
        self.date = date
        self.kind = kind
        self.name = name
        self.carbsGrams = carbsGrams
        self.note = note
    }

    public var displayName: String { name.isEmpty ? kind.title : name }
}

public enum ActivityKind: String, Codable, Sendable {
    case walk, run, cycling, strength, other

    public var title: String {
        switch self {
        case .walk: return "Walk"
        case .run: return "Run"
        case .cycling: return "Cycling"
        case .strength: return "Strength training"
        case .other: return "Workout"
        }
    }
}

public struct ActivityEvent: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var start: Date
    public var end: Date
    public var kind: ActivityKind

    public init(id: UUID = UUID(), start: Date, end: Date, kind: ActivityKind) {
        self.id = id
        self.start = start
        self.end = end
        self.kind = kind
    }

    public var durationMinutes: Int { Int(end.timeIntervalSince(start) / 60) }
}

public struct DailyActivity: Codable, Equatable, Sendable {
    public var date: Date
    public var steps: Int
    public var exerciseMinutes: Int

    public init(date: Date, steps: Int, exerciseMinutes: Int) {
        self.date = date
        self.steps = steps
        self.exerciseMinutes = exerciseMinutes
    }
}
