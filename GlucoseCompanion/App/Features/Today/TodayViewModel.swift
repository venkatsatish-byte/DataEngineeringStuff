import Foundation
import GlucoseCore

/// Everything the Today screen shows, computed from `AppModel` in one place so
/// the view stays declarative and this logic is easy to test.
struct TodayViewModel {
    var latest: GlucoseSample?
    var trend: TrendArrow?
    var band: GlucoseBand?
    var isStale: Bool
    var ageText: String
    var stats: GlucoseStats
    var unit: GlucoseUnit
    var targets: TargetRange
    var samples: [GlucoseSample]
    var meals: [MealEvent]
    var activities: [ActivityEvent]
    var domain: ClosedRange<Date>
    var activity: DailyActivity
    var stepGoal: Int
    var minutesGoal: Int
    var suggestion: String

    @MainActor
    init(model: AppModel, now: Date = .now, calendar: Calendar = .current) {
        let startOfDay = calendar.startOfDay(for: now)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? now
        let today = DateInterval(start: startOfDay, end: now)

        latest = model.latest
        trend = model.trend
        band = latest.map { model.profile.targets.band(for: $0.mgdL) }
        isStale = latest.map { GlucoseAnalytics.isStale($0, now: now) } ?? false
        ageText = latest.map { GlucoseAnalytics.ageDescription(of: $0.date, now: now) } ?? ""
        stats = GlucoseAnalytics.stats(for: model.samples, in: today, targets: model.profile.targets)
        unit = model.profile.unit
        targets = model.profile.targets
        samples = model.samples(in: today)
        meals = model.meals.filter { $0.date >= startOfDay }
        activities = model.activities.filter { $0.start >= startOfDay }
        domain = startOfDay...endOfDay
        activity = model.todayActivity
        stepGoal = model.profile.stepGoal
        minutesGoal = model.profile.activeMinutesGoal
        suggestion = Coaching.suggestion(now: now, meals: model.meals, activities: model.activities,
                                         today: model.todayActivity, profile: model.profile)
    }
}
