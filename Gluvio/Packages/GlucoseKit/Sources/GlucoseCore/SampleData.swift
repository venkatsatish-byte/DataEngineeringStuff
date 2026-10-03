import Foundation

/// Deterministic synthetic data for demo mode, previews, App Review and tests.
/// It is clearly fictional and never written to Apple Health.
public enum SampleData {
    public struct Dataset: Sendable {
        public var samples: [GlucoseSample]
        public var meals: [MealEvent]
        public var activities: [ActivityEvent]
        public var today: DailyActivity
    }

    public static func make(
        days: Int = 30, now: Date = .now, continuous: Bool = true, seed: UInt64 = 7, calendar: Calendar = .current
    ) -> Dataset {
        var rng = SplitMix64(seed: seed)
        let today = calendar.startOfDay(for: now)
        var meals: [MealEvent] = []
        var activities: [ActivityEvent] = []

        // Plan meals and walks day by day.
        for offset in stride(from: -(days - 1), through: 0, by: 1) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let plan: [(MealKind, Double, Double, String)] = [
                (.breakfast, 7.5, 45, "Oatmeal with berries"),
                (.lunch, 12.5, 60, "Turkey sandwich"),
                (.dinner, 18.5, 70, "Pasta with chicken"),
            ]
            for (kind, hour, carbs, name) in plan {
                let jitter = rng.uniform(-0.5, 0.5)
                let date = day.addingTimeInterval((hour + jitter) * 3600)
                guard date <= now else { continue }
                let meal = MealEvent(date: date, kind: kind, name: name, carbsGrams: (carbs + rng.uniform(-10, 15)).rounded())
                meals.append(meal)
                let walkChance = kind == .dinner ? 0.55 : (kind == .lunch ? 0.35 : 0.15)
                if rng.uniform(0, 1) < walkChance {
                    let start = date.addingTimeInterval(rng.uniform(10, 25) * 60)
                    let end = start.addingTimeInterval(rng.uniform(12, 25) * 60)
                    if end <= now { activities.append(ActivityEvent(start: start, end: end, kind: .walk)) }
                }
            }
        }

        // Shape of the day: overnight baseline with a dawn rise, plus a bump
        // after each meal that is smaller when a walk followed.
        func baseline(at date: Date) -> Double {
            let hour = date.timeIntervalSince(calendar.startOfDay(for: date)) / 3600
            let dawn = hour > 4 && hour < 9 ? 18 * sin((hour - 4) / 5 * .pi) : 0
            return 112 + dawn
        }
        var mealEffects: [(Date, Double)] = meals.map { meal in
            let walked = activities.contains { $0.start >= meal.date && $0.start <= meal.date.addingTimeInterval(3600) }
            let sensitivity = 1.35 * (walked ? 0.62 : 1.0)
            return (meal.date, meal.carbsGrams * sensitivity)
        }
        // A few out-of-range events so the demo shows lows and highs.
        if days >= 4, let lowDay = calendar.date(byAdding: .day, value: -3, to: today) {
            mealEffects.append((lowDay.addingTimeInterval(2.6 * 3600), -62))
        }
        if days >= 6, let highDay = calendar.date(byAdding: .day, value: -5, to: today) {
            mealEffects.append((highDay.addingTimeInterval(19.2 * 3600), 95))
        }

        func value(at date: Date, noise: Double) -> Double {
            var v = baseline(at: date)
            for (start, rise) in mealEffects {
                let minutes = date.timeIntervalSince(start) / 60
                guard minutes > 0, minutes < 300 else { continue }
                let peakAt = 50.0
                v += rise * (minutes / peakAt) * exp(1 - minutes / peakAt)
            }
            return min(400, max(40, v + noise))
        }

        var samples: [GlucoseSample] = []
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) else {
            return Dataset(samples: [], meals: meals, activities: activities, today: DailyActivity(date: today, steps: 0, exerciseMinutes: 0))
        }
        if continuous {
            var noise = 0.0
            var t = start
            while t <= now {
                noise = noise * 0.8 + rng.uniform(-3, 3)
                samples.append(GlucoseSample(date: t, mgdL: value(at: t, noise: noise).rounded(), source: .cgm, sourceName: "Demo CGM"))
                t = t.addingTimeInterval(5 * 60)
            }
        } else {
            for offset in 0..<days {
                guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
                let checks: [(Double, ReadingContext)] = [(7.0, .fasting), (12.2, .beforeMeal), (20.5, .afterMeal), (22.5, .bedtime)]
                for (hour, context) in checks {
                    let date = day.addingTimeInterval((hour + rng.uniform(-0.3, 0.3)) * 3600)
                    guard date <= now else { continue }
                    samples.append(GlucoseSample(date: date, mgdL: value(at: date, noise: rng.uniform(-6, 6)).rounded(),
                                                 context: context, source: .meter, sourceName: "Demo meter"))
                }
            }
        }

        let dayFraction = min(1, now.timeIntervalSince(today) / (20 * 3600))
        let todaySteps = Int(8200 * dayFraction)
        let todayMinutes = activities.filter { $0.start >= today }.reduce(0) { $0 + $1.durationMinutes } + Int(9 * dayFraction)
        return Dataset(
            samples: samples,
            meals: meals,
            activities: activities,
            today: DailyActivity(date: today, steps: todaySteps, exerciseMinutes: todayMinutes)
        )
    }
}

/// Small, fast, seedable generator so sample data is the same on every run.
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func uniform(_ low: Double, _ high: Double) -> Double {
        low + (high - low) * Double(next() >> 11) / Double(1 << 53)
    }
}
