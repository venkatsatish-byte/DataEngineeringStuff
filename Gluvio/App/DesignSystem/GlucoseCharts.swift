import Charts
import GlucoseCore
import SwiftUI

/// Glucose over a time window: CGM as a line, meter and manual readings as
/// points colored by band, the target range shaded, meals and walks marked.
struct GlucoseChart: View {
    var samples: [GlucoseSample]
    var meals: [MealEvent] = []
    var activities: [ActivityEvent] = []
    var targets: TargetRange
    var unit: GlucoseUnit
    var domain: ClosedRange<Date>

    private var continuous: [GlucoseSample] { samples.filter { $0.source == .cgm } }
    private var points: [GlucoseSample] { samples.filter { $0.source != .cgm } }

    private var yDomain: ClosedRange<Double> {
        let values = samples.map(\.mgdL)
        let low = min(40, values.min() ?? 40)
        let high = max(300, (values.max() ?? 0) + 20)
        return unit.value(fromMgdL: low)...unit.value(fromMgdL: high)
    }

    var body: some View {
        Chart {
            RectangleMark(
                xStart: .value("Start", domain.lowerBound),
                xEnd: .value("End", domain.upperBound),
                yStart: .value("Target low", unit.value(fromMgdL: targets.low)),
                yEnd: .value("Target high", unit.value(fromMgdL: targets.high))
            )
            .foregroundStyle(GlucoseBand.inRange.color.opacity(0.12))

            ForEach(activities.filter { domain.contains($0.start) }) { activity in
                RectangleMark(
                    xStart: .value("Activity start", activity.start),
                    xEnd: .value("Activity end", activity.end),
                    yStart: .value("Bottom", yDomain.lowerBound),
                    yEnd: .value("Top", yDomain.upperBound)
                )
                .foregroundStyle(Color.mint.opacity(0.18))
            }

            ForEach(meals.filter { domain.contains($0.date) }) { meal in
                RuleMark(x: .value("Meal", meal.date))
                    .foregroundStyle(Color.orange.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, alignment: .center) {
                        Image(systemName: "fork.knife").font(.caption2).foregroundStyle(.orange)
                    }
            }

            ForEach(continuous) { sample in
                LineMark(x: .value("Time", sample.date), y: .value("Glucose", unit.value(fromMgdL: sample.mgdL)))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }

            ForEach(points) { sample in
                PointMark(x: .value("Time", sample.date), y: .value("Glucose", unit.value(fromMgdL: sample.mgdL)))
                    .foregroundStyle(targets.band(for: sample.mgdL).color)
                    .symbolSize(50)
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: yDomain)
        .chartYAxis {
            AxisMarks(position: .leading, values: [targets.low, targets.high].map(unit.value(fromMgdL:))) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(unit == .mgdL ? "\(Int(v))" : String(format: "%.1f", v)) }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour())
            }
        }
        .accessibilityLabel("Glucose chart")
        .accessibilityValue(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        guard let low = samples.map(\.mgdL).min(), let high = samples.map(\.mgdL).max() else { return "No readings" }
        return "\(samples.count) readings from \(unit.formatWithUnit(low)) to \(unit.formatWithUnit(high))"
    }
}

/// Daily averages with each day's low-to-high spread, for 7 and 30 days.
struct DailyTrendChart: View {
    var days: [DailyGlucose]
    var targets: TargetRange
    var unit: GlucoseUnit

    var body: some View {
        Chart {
            RuleMark(y: .value("Target high", unit.value(fromMgdL: targets.high)))
                .foregroundStyle(GlucoseBand.high.color.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            RuleMark(y: .value("Target low", unit.value(fromMgdL: targets.low)))
                .foregroundStyle(GlucoseBand.low.color.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))

            ForEach(days) { day in
                RuleMark(
                    x: .value("Day", day.day, unit: .day),
                    yStart: .value("Lowest", unit.value(fromMgdL: day.minimum)),
                    yEnd: .value("Highest", unit.value(fromMgdL: day.maximum))
                )
                .foregroundStyle(Color.secondary.opacity(0.3))
                .lineStyle(StrokeStyle(lineWidth: days.count > 10 ? 4 : 8, lineCap: .round))

                LineMark(x: .value("Day", day.day, unit: .day), y: .value("Average", unit.value(fromMgdL: day.mean)))
                    .foregroundStyle(Color.accentColor)
                    .interpolationMethod(.monotone)

                PointMark(x: .value("Day", day.day, unit: .day), y: .value("Average", unit.value(fromMgdL: day.mean)))
                    .foregroundStyle(targets.band(for: day.mean).color)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: days.count > 10 ? 7 : 1)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .accessibilityLabel("Daily average glucose")
    }
}

/// Stacked bar of how much time (or how many readings) fell in each band.
struct TimeInRangeBar: View {
    var stats: GlucoseStats

    private let order: [GlucoseBand] = [.urgentHigh, .high, .inRange, .low, .urgentLow]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    ForEach(order.reversed(), id: \.self) { band in
                        let fraction = stats.bandFractions[band, default: 0]
                        if fraction > 0 {
                            band.color.frame(width: max(3, proxy.size.width * fraction - 2))
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .frame(height: 18)

            ForEach(order, id: \.self) { band in
                HStack {
                    Circle().fill(band.color).frame(width: 10, height: 10)
                    Text(band.title).font(.subheadline)
                    Spacer()
                    Text(Format.percent(stats.bandFractions[band, default: 0]))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(band == .inRange ? .primary : .secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
