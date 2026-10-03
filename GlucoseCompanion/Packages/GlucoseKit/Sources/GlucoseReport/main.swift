// Prints the same summary the app shows, built from synthetic sample data.
//
//   swift run glucose-report                 30 days of demo CGM data
//   swift run glucose-report --fingerstick   4 meter readings a day instead
//   swift run glucose-report --mmol          show mmol/L

import Foundation
import GlucoseCore

let arguments = CommandLine.arguments
let continuous = !arguments.contains("--fingerstick")
var profile = UserProfile()
profile.unit = arguments.contains("--mmol") ? .mmolL : .mgdL
profile.usesCGM = continuous

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "UTC")!
// A fixed "now" so every run prints the same report.
let now = ISO8601DateFormatter().date(from: "2026-10-02T19:30:00Z")!
let data = SampleData.make(days: 30, now: now, continuous: continuous, calendar: calendar)
let unit = profile.unit

func pct(_ value: Double?) -> String {
    value.map { String(format: "%.0f%%", $0 * 100) } ?? "—"
}

func bar(_ fraction: Double, width: Int = 40) -> String {
    String(repeating: "█", count: Int((fraction * Double(width)).rounded()))
}

let time = DateFormatter()
time.calendar = calendar
time.timeZone = calendar.timeZone
time.dateFormat = "EEE MMM d, HH:mm"
let dayFormat = DateFormatter()
dayFormat.calendar = calendar
dayFormat.timeZone = calendar.timeZone
dayFormat.dateFormat = "EEE MMM d"

print("""
═══════════════════════════════════════════════════════════════
 GlucoseCompanion — sample report (\(continuous ? "CGM" : "fingerstick") demo data)
 \(SafetyCopy.shortDisclaimer)
═══════════════════════════════════════════════════════════════
""")

// Latest reading, as the Today screen and the Watch show it.
if let latest = data.samples.last {
    let band = profile.targets.band(for: latest.mgdL)
    let trend = GlucoseAnalytics.trend(from: Array(data.samples.suffix(12)))
    print("\nLATEST READING")
    print("  \(unit.formatWithUnit(latest.mgdL)) \(trend?.symbol ?? "")  \(band.title)  ·  \(GlucoseAnalytics.ageDescription(of: latest.date, now: now))  (\(time.string(from: latest.date)))")
    if let trend { print("  Trend: \(trend.accessibilityLabel)") }
}

// Today.
let todayInterval = DateInterval(start: calendar.startOfDay(for: now), end: now)
let today = GlucoseAnalytics.stats(for: data.samples, in: todayInterval, targets: profile.targets)
print("\nTODAY")
print("  Average            \(today.mean.map(unit.formatWithUnit) ?? "—")")
print("  \(today.inRangeLabel.padding(toLength: 19, withPad: " ", startingAt: 0))\(pct(today.inRangeFraction))")
print("  Lows / highs       \(today.lowEpisodes) / \(today.highEpisodes)")
print("  Steps              \(data.today.steps.formatted()) of \(profile.stepGoal.formatted())")
print("  Suggestion         \(Coaching.suggestion(now: now, meals: data.meals, activities: data.activities, today: data.today, profile: profile))")

// Report for the doctor.
for days in [7, 30] {
    let report = DoctorReport(samples: data.samples, meals: data.meals, activities: data.activities,
                              profile: profile, days: days, now: now, calendar: calendar)
    let s = report.stats
    print("\nLAST \(days) DAYS  (\(s.readingCount) readings)")
    print("  Average            \(s.mean.map(unit.formatWithUnit) ?? "—")")
    print("  Variability (CV)   \(pct(s.coefficientOfVariation))   (target ≤ 36%)")
    print("  Lows / highs       \(s.lowEpisodes) / \(s.highEpisodes)")
    print("  \(s.inRangeLabel):")
    for band in GlucoseBand.allCases.reversed() {
        let fraction = s.bandFractions[band, default: 0]
        print("    \(band.title.padding(toLength: 10, withPad: " ", startingAt: 0)) \(pct(fraction).padding(toLength: 5, withPad: " ", startingAt: 0)) \(bar(fraction))")
    }
}

let report = DoctorReport(samples: data.samples, meals: data.meals, activities: data.activities,
                          profile: profile, days: 30, now: now, calendar: calendar)
print("\n\(report.a1c.label.uppercased())")
print("  \(report.a1c.percent.map { String(format: "%.1f%%", $0) } ?? "—")")
print("  \(report.a1c.explanation)")

print("\nDAILY AVERAGES (last 7 days)")
for day in report.daily.suffix(7) {
    let width = Int((unit.value(fromMgdL: day.mean) / unit.value(fromMgdL: 250)) * 30)
    print("  \(dayFormat.string(from: day.day))  \(unit.format(day.mean).padding(toLength: 5, withPad: " ", startingAt: 0)) \(String(repeating: "▇", count: max(1, width)))  \(pct(day.inRangeFraction)) in range")
}

print("\nMEALS: BIGGEST RISES")
for line in report.biggestRises {
    print("  \(time.string(from: line.meal.date))  \(line.meal.displayName) (\(Int(line.meal.carbsGrams)) g carbs)  \(unit.formatDelta(line.response.rise)) \(unit.symbol), peak after \(line.response.minutesToPeak) min\(line.response.walkedAfter ? ", walked after" : "")")
}
print("\nMEALS: GENTLEST")
for line in report.gentlestMeals {
    print("  \(time.string(from: line.meal.date))  \(line.meal.displayName) (\(Int(line.meal.carbsGrams)) g carbs)  \(unit.formatDelta(line.response.rise)) \(unit.symbol)\(line.response.walkedAfter ? ", walked after" : "")")
}

if let walk = report.walkInsight {
    print("\nINSIGHT")
    print("  After meals followed by a walk your glucose rose \(unit.formatWithUnit(walk.averageRiseWithWalk)) on average (\(walk.mealsWithWalk) meals),")
    print("  compared with \(unit.formatWithUnit(walk.averageRiseWithoutWalk)) without one (\(walk.mealsWithoutWalk) meals).")
}

// What the urgent screen says for a very low reading.
let low = GlucoseSample(date: now, mgdL: 48, source: .manual)
if let alert = SafetyGuidance.alert(for: low, targets: profile.targets) {
    print("\nURGENT SCREEN EXAMPLE (manual entry of \(unit.formatWithUnit(low.mgdL)))")
    print("  \(alert.title)")
    for step in alert.steps { print("  • \(step)") }
}
print("")
