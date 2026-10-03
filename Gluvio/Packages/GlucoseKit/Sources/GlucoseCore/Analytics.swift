import Foundation

public struct GlucoseStats: Equatable, Sendable {
    public var readingCount: Int
    public var mean: Double?
    public var standardDeviation: Double?
    public var minimum: Double?
    public var maximum: Double?
    /// Share of readings in each band (0…1). Empty when there are no readings.
    public var bandFractions: [GlucoseBand: Double]
    public var lowEpisodes: Int
    public var highEpisodes: Int
    /// Share of 15-minute blocks in the period that contain a CGM reading.
    public var cgmCoverage: Double

    /// Time in range is only meaningful for continuous data. With fingersticks
    /// the app labels the same number "readings in range" instead.
    public var isContinuous: Bool { cgmCoverage >= 0.5 }

    public var inRangeFraction: Double? {
        readingCount == 0 ? nil : bandFractions[.inRange, default: 0]
    }

    public var belowRangeFraction: Double? {
        readingCount == 0 ? nil : bandFractions[.low, default: 0] + bandFractions[.urgentLow, default: 0]
    }

    public var aboveRangeFraction: Double? {
        readingCount == 0 ? nil : bandFractions[.high, default: 0] + bandFractions[.urgentHigh, default: 0]
    }

    /// Glucose variability. Consensus target is 36% or lower.
    public var coefficientOfVariation: Double? {
        guard let mean, let standardDeviation, mean > 0 else { return nil }
        return standardDeviation / mean
    }

    public var inRangeLabel: String { isContinuous ? "Time in range" : "Readings in range" }
}

public enum A1CEstimate: Equatable, Sendable {
    /// Glucose Management Indicator from at least 14 days of CGM data.
    case gmi(percent: Double, days: Int)
    /// ADAG estimate from fingerstick readings.
    case estimated(percent: Double, readings: Int)
    case notEnoughData(reason: String)

    public var percent: Double? {
        switch self {
        case .gmi(let p, _), .estimated(let p, _): return p
        case .notEnoughData: return nil
        }
    }

    public var label: String {
        switch self {
        case .gmi: return "GMI (estimated A1C)"
        case .estimated, .notEnoughData: return "Estimated A1C"
        }
    }

    public var explanation: String {
        switch self {
        case .gmi(_, let days):
            return "Glucose Management Indicator from your last \(days) days of CGM data (GMI = 3.31 + 0.02392 × average mg/dL). It's an estimate and can differ from a lab A1C."
        case .estimated(_, let readings):
            return "Estimated from \(readings) readings over the last 30 days using the ADAG formula. Fingerstick readings are often taken before meals, so this can read lower than a lab A1C."
        case .notEnoughData(let reason):
            return reason
        }
    }
}

public enum TrendArrow: String, Codable, Sendable {
    case risingQuickly, rising, risingSlightly, flat, fallingSlightly, falling, fallingQuickly

    /// Standard CGM trend rates in mg/dL per minute.
    public init(ratePerMinute rate: Double) {
        switch rate {
        case 3...: self = .risingQuickly
        case 2..<3: self = .rising
        case 1..<2: self = .risingSlightly
        case -1..<1: self = .flat
        case -2..<(-1): self = .fallingSlightly
        case -3..<(-2): self = .falling
        default: self = .fallingQuickly
        }
    }

    public var symbol: String {
        switch self {
        case .risingQuickly: return "↑↑"
        case .rising: return "↑"
        case .risingSlightly: return "↗"
        case .flat: return "→"
        case .fallingSlightly: return "↘"
        case .falling: return "↓"
        case .fallingQuickly: return "↓↓"
        }
    }

    public var accessibilityLabel: String {
        switch self {
        case .risingQuickly: return "Rising quickly"
        case .rising: return "Rising"
        case .risingSlightly: return "Rising slowly"
        case .flat: return "Steady"
        case .fallingSlightly: return "Falling slowly"
        case .falling: return "Falling"
        case .fallingQuickly: return "Falling quickly"
        }
    }
}

public struct MealResponse: Identifiable, Equatable, Sendable {
    public var id: UUID { mealID }
    public var mealID: UUID
    public var baseline: Double
    public var peak: Double
    public var peakDate: Date
    public var minutesToPeak: Int
    public var walkedAfter: Bool
    /// True with enough CGM readings to see the real peak.
    public var isHighConfidence: Bool
    /// True once the 3-hour window after the meal has passed.
    public var isComplete: Bool

    public var rise: Double { peak - baseline }
}

public struct WalkInsight: Equatable, Sendable {
    public var averageRiseWithWalk: Double
    public var averageRiseWithoutWalk: Double
    public var mealsWithWalk: Int
    public var mealsWithoutWalk: Int

    /// Positive when meals followed by a walk rose less.
    public var difference: Double { averageRiseWithoutWalk - averageRiseWithWalk }
}

public struct DailyGlucose: Identifiable, Equatable, Sendable {
    public var id: Date { day }
    public var day: Date
    public var mean: Double
    public var minimum: Double
    public var maximum: Double
    public var inRangeFraction: Double
    public var readingCount: Int
}

public enum GlucoseAnalytics {
    public static let staleAfter: TimeInterval = 20 * 60

    // MARK: Summary statistics

    public static func stats(for samples: [GlucoseSample], in interval: DateInterval, targets: TargetRange) -> GlucoseStats {
        let readings = samples.filter { interval.contains($0.date) }.sorted { $0.date < $1.date }
        let values = readings.map(\.mgdL)
        var fractions: [GlucoseBand: Double] = [:]
        if !values.isEmpty {
            for value in values { fractions[targets.band(for: value), default: 0] += 1 }
            for band in fractions.keys { fractions[band]! /= Double(values.count) }
        }
        let mean = Self.mean(values)
        let sd: Double? = mean.flatMap { m in
            values.count > 1 ? (values.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(values.count - 1)).squareRoot() : nil
        }
        return GlucoseStats(
            readingCount: values.count,
            mean: mean,
            standardDeviation: sd,
            minimum: values.min(),
            maximum: values.max(),
            bandFractions: fractions,
            lowEpisodes: episodes(in: readings) { $0 < targets.low },
            highEpisodes: episodes(in: readings) { $0 > targets.high },
            cgmCoverage: cgmCoverage(readings, in: interval)
        )
    }

    /// Counts separate runs of readings matching `predicate`. Readings more than
    /// `maxGap` apart start a new episode, so each fingerstick low counts once.
    public static func episodes(in sorted: [GlucoseSample], maxGap: TimeInterval = 30 * 60, where predicate: (Double) -> Bool) -> Int {
        var count = 0
        var lastHit: Date?
        var previousWasHit = false
        for sample in sorted {
            if predicate(sample.mgdL) {
                let gapTooLong = lastHit.map { sample.date.timeIntervalSince($0) > maxGap } ?? true
                if !previousWasHit || gapTooLong { count += 1 }
                lastHit = sample.date
                previousWasHit = true
            } else {
                previousWasHit = false
            }
        }
        return count
    }

    /// Share of 15-minute blocks that contain a CGM reading. Works for sensors
    /// that report every 1, 5 or 15 minutes.
    public static func cgmCoverage(_ samples: [GlucoseSample], in interval: DateInterval) -> Double {
        let block: TimeInterval = 15 * 60
        let total = max(1, Int((interval.duration / block).rounded(.up)))
        var blocks = Set<Int>()
        for sample in samples where sample.source == .cgm && interval.contains(sample.date) {
            blocks.insert(Int(sample.date.timeIntervalSince(interval.start) / block))
        }
        return min(1, Double(blocks.count) / Double(total))
    }

    // MARK: A1C

    public static func gmi(meanMgdL: Double) -> Double { 3.31 + 0.02392 * meanMgdL }

    public static func adagA1C(meanMgdL: Double) -> Double { (meanMgdL + 46.7) / 28.7 }

    public static func estimateA1C(from samples: [GlucoseSample], now: Date = .now, calendar: Calendar = .current) -> A1CEstimate {
        let day: TimeInterval = 86_400
        let cgmWindow = DateInterval(start: now.addingTimeInterval(-14 * day), end: now)
        let cgm = samples.filter { $0.source == .cgm && cgmWindow.contains($0.date) }
        if cgmCoverage(cgm, in: cgmWindow) >= 0.7, let mean = mean(cgm.map(\.mgdL)) {
            return .gmi(percent: gmi(meanMgdL: mean), days: 14)
        }

        let window = DateInterval(start: now.addingTimeInterval(-30 * day), end: now)
        let readings = samples.filter { window.contains($0.date) }
        let days = Set(readings.map { calendar.startOfDay(for: $0.date) }).count
        if readings.count >= 28, days >= 14, let mean = mean(readings.map(\.mgdL)) {
            return .estimated(percent: adagA1C(meanMgdL: mean), readings: readings.count)
        }
        return .notEnoughData(reason: "Needs 14 days of CGM data (worn at least 70% of the time), or at least 28 readings on 14 different days in the last 30 days.")
    }

    // MARK: Trend and freshness

    /// Derives a CGM-style trend arrow from the slope of the last 20 minutes of
    /// CGM readings. Apple Health doesn't store the sensor's own arrow.
    public static func trend(from samples: [GlucoseSample]) -> TrendArrow? {
        let cgm = samples.filter { $0.source == .cgm }.sorted { $0.date < $1.date }
        guard let last = cgm.last else { return nil }
        let window = cgm.filter { last.date.timeIntervalSince($0.date) <= 20 * 60 }
        guard window.count >= 3, let first = window.first, last.date.timeIntervalSince(first.date) >= 10 * 60 else {
            return nil
        }
        let xs = window.map { $0.date.timeIntervalSince(first.date) / 60 }
        let ys = window.map(\.mgdL)
        let xMean = xs.reduce(0, +) / Double(xs.count)
        let yMean = ys.reduce(0, +) / Double(ys.count)
        var numerator = 0.0
        var denominator = 0.0
        for (x, y) in zip(xs, ys) {
            numerator += (x - xMean) * (y - yMean)
            denominator += (x - xMean) * (x - xMean)
        }
        guard denominator > 0 else { return nil }
        return TrendArrow(ratePerMinute: numerator / denominator)
    }

    public static func isStale(_ sample: GlucoseSample, now: Date = .now) -> Bool {
        sample.source == .cgm && now.timeIntervalSince(sample.date) > staleAfter
    }

    public static func ageDescription(of date: Date, now: Date = .now) -> String {
        let minutes = Int(now.timeIntervalSince(date) / 60)
        switch minutes {
        case ..<1: return "Just now"
        case ..<60: return "\(minutes) min ago"
        case ..<(24 * 60):
            let hours = minutes / 60
            let rest = minutes % 60
            return rest == 0 || hours >= 3 ? "\(hours) h ago" : "\(hours) h \(rest) min ago"
        default:
            let days = minutes / (24 * 60)
            return days == 1 ? "Yesterday" : "\(days) days ago"
        }
    }

    // MARK: Meals

    /// How glucose changed after a meal: the last reading in the 30 minutes
    /// before it, against the highest reading in the 3 hours after it.
    public static func mealResponse(
        for meal: MealEvent, samples: [GlucoseSample], activities: [ActivityEvent], now: Date = .now
    ) -> MealResponse? {
        let windowEnd = meal.date.addingTimeInterval(3 * 3600)
        let baseline = samples
            .filter { $0.date >= meal.date.addingTimeInterval(-30 * 60) && $0.date <= meal.date }
            .max { $0.date < $1.date }
        let after = samples.filter { $0.date > meal.date && $0.date <= windowEnd }
        guard let baseline, let peak = after.max(by: { $0.mgdL < $1.mgdL }) else { return nil }

        let walked = activities.contains {
            $0.start >= meal.date && $0.start <= meal.date.addingTimeInterval(60 * 60) && $0.durationMinutes >= 10
        }
        return MealResponse(
            mealID: meal.id,
            baseline: baseline.mgdL,
            peak: peak.mgdL,
            peakDate: peak.date,
            minutesToPeak: Int(peak.date.timeIntervalSince(meal.date) / 60),
            walkedAfter: walked,
            isHighConfidence: after.filter { $0.source == .cgm }.count >= 8,
            isComplete: now >= windowEnd
        )
    }

    /// Compares meals followed by a walk with those that weren't. Needs at least
    /// three complete meals in each group to say anything.
    public static func walkInsight(from responses: [MealResponse], minimumPerGroup: Int = 3) -> WalkInsight? {
        let complete = responses.filter(\.isComplete)
        let walked = complete.filter(\.walkedAfter).map(\.rise)
        let didNot = complete.filter { !$0.walkedAfter }.map(\.rise)
        guard walked.count >= minimumPerGroup, didNot.count >= minimumPerGroup,
              let withWalk = mean(walked), let withoutWalk = mean(didNot) else { return nil }
        return WalkInsight(
            averageRiseWithWalk: withWalk,
            averageRiseWithoutWalk: withoutWalk,
            mealsWithWalk: walked.count,
            mealsWithoutWalk: didNot.count
        )
    }

    // MARK: Daily summaries

    public static func dailySummaries(
        for samples: [GlucoseSample], days: Int, targets: TargetRange, now: Date = .now, calendar: Calendar = .current
    ) -> [DailyGlucose] {
        let today = calendar.startOfDay(for: now)
        guard let firstDay = calendar.date(byAdding: .day, value: -(days - 1), to: today) else { return [] }
        let grouped = Dictionary(grouping: samples.filter { $0.date >= firstDay && $0.date <= now }) {
            calendar.startOfDay(for: $0.date)
        }
        return grouped.keys.sorted().compactMap { day in
            let values = grouped[day]!.map(\.mgdL)
            guard let mean = mean(values), let lo = values.min(), let hi = values.max() else { return nil }
            let inRange = Double(values.filter(targets.contains).count) / Double(values.count)
            return DailyGlucose(day: day, mean: mean, minimum: lo, maximum: hi, inRangeFraction: inRange, readingCount: values.count)
        }
    }

    static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}
