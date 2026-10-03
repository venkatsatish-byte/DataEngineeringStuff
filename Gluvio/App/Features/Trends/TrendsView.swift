import GlucoseCore
import SwiftUI

struct TrendsView: View {
    @Environment(AppModel.self) private var model
    @State private var period: TrendPeriod = .week

    var body: some View {
        let vm = TrendsViewModel(model: model, period: period)
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("Period", selection: $period) {
                        ForEach(TrendPeriod.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    Card(title: period == .day ? "Last 24 hours" : "Daily average and range") {
                        if vm.stats.readingCount == 0 {
                            Text("No readings in this period yet.").foregroundStyle(.secondary)
                        } else if period == .day {
                            GlucoseChart(samples: vm.recentSamples, meals: vm.recentMeals, activities: vm.recentActivities,
                                         targets: vm.targets, unit: vm.unit, domain: vm.dayDomain)
                                .frame(height: 240)
                        } else {
                            DailyTrendChart(days: vm.daily, targets: vm.targets, unit: vm.unit)
                                .frame(height: 240)
                            Text("Dots show each day's average; grey bars show its lowest to highest reading.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                        GridRow {
                            StatTile(title: "Average", value: vm.stats.mean.map(vm.unit.format) ?? "—", caption: vm.unit.symbol)
                            StatTile(title: "Variability", value: Format.percent(vm.stats.coefficientOfVariation), caption: "goal 36% or less")
                        }
                        GridRow {
                            StatTile(title: "Lows", value: "\(vm.stats.lowEpisodes)", caption: "episodes")
                            StatTile(title: "Highs", value: "\(vm.stats.highEpisodes)", caption: "episodes")
                        }
                    }

                    Card(title: vm.stats.inRangeLabel) {
                        TimeInRangeBar(stats: vm.stats)
                        Text(vm.stats.isContinuous
                             ? "Consensus goal for most adults: more than 70% in range and less than 4% below range. Your care team may set different goals."
                             : "Based on \(vm.stats.readingCount) fingerstick readings. These are often taken at set times, so this isn't the same as time in range from a CGM.")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    Card(title: vm.a1c.label) {
                        if let percent = vm.a1c.percent {
                            Text(percent.formatted(.number.precision(.fractionLength(1))) + "%")
                                .font(.system(size: 40, weight: .bold, design: .rounded))
                        }
                        Text(vm.a1c.explanation).font(.footnote).foregroundStyle(.secondary)
                        Text("This is an estimate, not a lab result.")
                            .font(.footnote.weight(.semibold))
                    }

                    Card(title: "What affects you") {
                        if let walk = vm.walkInsight {
                            insight(
                                systemImage: "figure.walk",
                                text: "After meals followed by a walk, your glucose rose \(vm.unit.formatWithUnit(walk.averageRiseWithWalk)) on average, compared with \(vm.unit.formatWithUnit(walk.averageRiseWithoutWalk)) without one.",
                                detail: "Based on \(walk.mealsWithWalk + walk.mealsWithoutWalk) meals."
                            )
                        }
                        if let days = vm.activeDayComparison {
                            insight(
                                systemImage: "flame",
                                text: "On days with a workout your average was \(vm.unit.formatWithUnit(days.activeAverage)), and \(vm.unit.formatWithUnit(days.quietAverage)) on other days.",
                                detail: "Last 30 days."
                            )
                        }
                        if vm.walkInsight == nil && vm.activeDayComparison == nil {
                            Text("Log meals and keep your Apple Watch or iPhone with you for a week or two. Patterns appear here once there is enough data.")
                                .foregroundStyle(.secondary)
                        }
                        Text("These are patterns in your own data, not proof of cause and effect.")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    DisclaimerFooter()
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Trends")
        }
    }

    private func insight(systemImage: String, text: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage).font(.title3).foregroundStyle(.tint).frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(text)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
