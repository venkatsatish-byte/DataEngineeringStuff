import Foundation

/// Everything the doctor report shows, computed once so the PDF and the
/// command-line demo print the same numbers.
public struct DoctorReport: Sendable {
    public struct MealLine: Identifiable, Sendable {
        public var id: UUID { meal.id }
        public var meal: MealEvent
        public var response: MealResponse
    }

    public var period: DateInterval
    public var days: Int
    public var unit: GlucoseUnit
    public var targets: TargetRange
    public var stats: GlucoseStats
    public var a1c: A1CEstimate
    public var daily: [DailyGlucose]
    public var biggestRises: [MealLine]
    public var gentlestMeals: [MealLine]
    public var walkInsight: WalkInsight?
    public var logbook: [GlucoseSample]
    public var generatedAt: Date

    public init(
        samples: [GlucoseSample], meals: [MealEvent], activities: [ActivityEvent], profile: UserProfile,
        days: Int, now: Date = .now, calendar: Calendar = .current
    ) {
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now)) ?? now
        let period = DateInterval(start: start, end: now)
        let inPeriod = samples.filter { period.contains($0.date) }
        let lines = meals.filter { period.contains($0.date) }.compactMap { meal in
            GlucoseAnalytics.mealResponse(for: meal, samples: inPeriod, activities: activities, now: now)
                .map { MealLine(meal: meal, response: $0) }
        }.filter(\.response.isComplete)
        let byRise = lines.sorted { $0.response.rise > $1.response.rise }

        self.period = period
        self.days = days
        unit = profile.unit
        targets = profile.targets
        stats = GlucoseAnalytics.stats(for: inPeriod, in: period, targets: profile.targets)
        a1c = GlucoseAnalytics.estimateA1C(from: samples, now: now, calendar: calendar)
        daily = GlucoseAnalytics.dailySummaries(for: inPeriod, days: days, targets: profile.targets, now: now, calendar: calendar)
        biggestRises = Array(byRise.prefix(3))
        gentlestMeals = Array(byRise.reversed().prefix(3))
        walkInsight = GlucoseAnalytics.walkInsight(from: lines.map(\.response))
        // Manual and meter readings, newest first. CGM traces are summarized, not listed.
        logbook = inPeriod.filter { $0.source != .cgm }.sorted { $0.date > $1.date }
        generatedAt = now
    }
}
