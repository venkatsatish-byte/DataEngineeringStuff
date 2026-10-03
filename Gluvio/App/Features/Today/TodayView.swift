import GlucoseCore
import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var model
    @State private var logging: LogKind?

    var body: some View {
        let vm = TodayViewModel(model: model)
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if model.isDemo { DemoBanner() }
                    if let message = model.errorMessage {
                        ErrorBanner(message: message) { model.errorMessage = nil }
                    }
                    LatestReadingCard(vm: vm) { logging = .glucose }
                    statsGrid(vm)
                    Card(title: "Today") {
                        GlucoseChart(samples: vm.samples, meals: vm.meals, activities: vm.activities,
                                     targets: vm.targets, unit: vm.unit, domain: vm.domain)
                            .frame(height: 220)
                        HStack(spacing: 16) {
                            Label("Meal", systemImage: "fork.knife").foregroundStyle(.orange)
                            Label("Activity", systemImage: "figure.walk").foregroundStyle(.mint)
                            Label("Target", systemImage: "square.fill").foregroundStyle(GlucoseBand.inRange.color.opacity(0.5))
                        }
                        .font(.caption)
                    }
                    Card(title: "Activity") {
                        GoalProgressRow(title: "Steps", systemImage: "shoeprints.fill", value: vm.activity.steps, goal: vm.stepGoal, unit: "")
                        GoalProgressRow(title: "Active minutes", systemImage: "flame", value: vm.activity.exerciseMinutes, goal: vm.minutesGoal, unit: "min")
                        Label(vm.suggestion, systemImage: "lightbulb")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    quickActions
                    DisclaimerFooter()
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .primaryAction) { LogMenu(selection: $logging) }
            }
            .refreshable { await model.refresh() }
            .sheet(item: $logging) { LogSheet(kind: $0) }
        }
    }

    private func statsGrid(_ vm: TodayViewModel) -> some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                StatTile(title: "Average", value: vm.stats.mean.map(vm.unit.format) ?? "—", caption: vm.unit.symbol)
                StatTile(title: vm.stats.inRangeLabel, value: Format.percent(vm.stats.inRangeFraction),
                         caption: "\(vm.unit.format(vm.targets.low))–\(vm.unit.format(vm.targets.high))")
            }
            GridRow {
                StatTile(title: "Lows", value: "\(vm.stats.lowEpisodes)", caption: "below \(vm.unit.format(vm.targets.low))")
                StatTile(title: "Highs", value: "\(vm.stats.highEpisodes)", caption: "above \(vm.unit.format(vm.targets.high))")
            }
        }
    }

    private var quickActions: some View {
        HStack(spacing: 12) {
            quickAction("Glucose", systemImage: "drop.fill", kind: .glucose)
            quickAction("Meal", systemImage: "fork.knife", kind: .meal)
            quickAction("Water", systemImage: "waterbottle.fill", kind: .water)
        }
    }

    private func quickAction(_ title: String, systemImage: String, kind: LogKind) -> some View {
        Button { logging = kind } label: {
            VStack(spacing: 6) {
                Image(systemName: systemImage).font(.title2)
                Text(title).font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Log \(title.lowercased())")
    }
}

struct LatestReadingCard: View {
    var vm: TodayViewModel
    var onAdd: () -> Void

    var body: some View {
        Card {
            if let latest = vm.latest, let band = vm.band {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Latest reading").font(.subheadline).foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(vm.unit.format(latest.mgdL))
                                .font(.system(size: 56, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(vm.isStale ? Color.secondary : band.color)
                            Text(vm.unit.symbol).font(.title3).foregroundStyle(.secondary)
                            if let trend = vm.trend, !vm.isStale {
                                Text(trend.symbol)
                                    .font(.system(size: 36, weight: .semibold))
                                    .foregroundStyle(band.color)
                                    .accessibilityLabel(trend.accessibilityLabel)
                            }
                        }
                    }
                    Spacer()
                    Label(band.title, systemImage: band.systemImage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(band.color)
                }
                HStack {
                    Image(systemName: vm.isStale ? "clock.badge.exclamationmark" : "clock")
                    Text(vm.isStale ? "No new reading for \(vm.ageText.replacingOccurrences(of: " ago", with: "")). Check your CGM app." : vm.ageText)
                    Text("·")
                    Text(latest.sourceName.isEmpty ? latest.source.rawValue : latest.sourceName)
                }
                .font(.footnote)
                .foregroundStyle(vm.isStale ? .orange : .secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No readings yet").font(.title3.bold())
                    Text("Readings from your CGM or meter appear here once they reach Apple Health. You can also add one yourself.")
                        .foregroundStyle(.secondary)
                    Button("Add a reading", action: onAdd).buttonStyle(.borderedProminent)
                }
            }
        }
    }
}

struct ErrorBanner: View {
    var message: String
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
            Text(message).font(.footnote)
            Spacer()
            Button(action: onDismiss) { Image(systemName: "xmark") }
                .accessibilityLabel("Dismiss")
        }
        .padding(10)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}
