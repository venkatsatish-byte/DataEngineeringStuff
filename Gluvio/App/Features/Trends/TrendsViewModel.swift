import Foundation
import GlucoseCore

enum TrendPeriod: Int, CaseIterable, Identifiable {
    case day = 1, week = 7, month = 30

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .day: return "24 hours"
        case .week: return "7 days"
        case .month: return "30 days"
        }
    }
}

struct TrendsViewModel {
    var period: TrendPeriod
    var unit: GlucoseUnit
    var targets: TargetRange
    var stats: GlucoseStats
    var daily: [DailyGlucose]
    var recentSamples: [GlucoseSample]
    var recentMeals: [MealEvent]
    var recentActivities: [ActivityEvent]
    var dayDomain: ClosedRange<Date>
    var a1c: A1CEstimate
    var walkInsight: WalkInsight?
    var activeDayComparison: (activeAverage: Double, quietAverage: Double)?

    @MainActor
    init(model: AppModel, period: TrendPeriod, now: Date = .now, calendar: Calendar = .current) {
        self.period = period
        unit = model.profile.unit
        targets = model.profile.targets

        let interval: DateInterval
        if period == .day {
            interval = DateInterval(start: now.addingTimeInterval(-86_400), end: now)
        } else {
            let start = calendar.date(byAdding: .day, value: -(period.rawValue - 1), to: calendar.startOfDay(for: now)) ?? now
            interval = DateInterval(start: start, end: now)
        }
        stats = GlucoseAnalytics.stats(for: model.samples, in: interval, targets: targets)
        daily = GlucoseAnalytics.dailySummaries(for: model.samples, days: period.rawValue, targets: targets, now: now, calendar: calendar)
        recentSamples = model.samples(in: interval)
        recentMeals = model.meals.filter { interval.contains($0.date) }
        recentActivities = model.activities.filter { interval.contains($0.start) }
        dayDomain = interval.start...interval.end
        a1c = GlucoseAnalytics.estimateA1C(from: model.samples, now: now, calendar: calendar)

        let responses = model.meals.compactMap { model.response(for: $0) }
        walkInsight = GlucoseAnalytics.walkInsight(from: responses)

        // Days with a workout against days without, over the last 30 days.
        let activeDays = Set(model.activities.map { calendar.startOfDay(for: $0.start) })
        let month = GlucoseAnalytics.dailySummaries(for: model.samples, days: 30, targets: targets, now: now, calendar: calendar)
            .filter { $0.day < calendar.startOfDay(for: now) }
        let active = month.filter { activeDays.contains($0.day) }.map(\.mean)
        let quiet = month.filter { !activeDays.contains($0.day) }.map(\.mean)
        if active.count >= 3, quiet.count >= 3 {
            activeDayComparison = (active.reduce(0, +) / Double(active.count), quiet.reduce(0, +) / Double(quiet.count))
        }
    }
}
