import Charts
import GlucoseCore
import SwiftUI

struct WatchRootView: View {
    var body: some View {
        NavigationStack {
            TabView {
                LatestReadingPage()
                TodayPage()
                QuickLogPage()
            }
            .tabViewStyle(.verticalPage)
        }
    }
}

struct LatestReadingPage: View {
    @Environment(WatchModel.self) private var model

    var body: some View {
        let unit = model.profile.unit
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(spacing: 4) {
                if let latest = model.latest {
                    let band = model.profile.targets.band(for: latest.mgdL)
                    let stale = GlucoseAnalytics.isStale(latest, now: context.date)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(unit.format(latest.mgdL))
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .minimumScaleFactor(0.6)
                        if let trend = model.trend, !stale {
                            Text(trend.symbol)
                                .font(.system(size: 30, weight: .semibold))
                                .accessibilityLabel(trend.accessibilityLabel)
                        }
                    }
                    .foregroundStyle(stale ? .secondary : .primary)
                    Text("\(unit.symbol) · \(band.title)")
                        .font(.headline)
                    Text(stale ? "No new reading for \(GlucoseAnalytics.ageDescription(of: latest.date, now: context.date).replacingOccurrences(of: " ago", with: ""))"
                               : GlucoseAnalytics.ageDescription(of: latest.date, now: context.date))
                        .font(.footnote)
                        .foregroundStyle(stale ? .orange : .secondary)
                } else {
                    Image(systemName: "drop").font(.largeTitle)
                    Text("No readings yet").font(.headline)
                    NavigationLink("Log glucose") { GlucoseEntryView() }
                }
                if let message = model.message {
                    Text(message).font(.caption2).foregroundStyle(.orange).multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .containerBackground(backgroundColor.gradient, for: .tabView)
        .navigationTitle("Glucose")
    }

    private var backgroundColor: Color {
        guard let latest = model.latest, !GlucoseAnalytics.isStale(latest) else { return .gray.opacity(0.4) }
        return model.profile.targets.band(for: latest.mgdL).color.opacity(0.55)
    }
}

struct TodayPage: View {
    @Environment(WatchModel.self) private var model

    var body: some View {
        let stats = model.todayStats
        let unit = model.profile.unit
        let recent = model.samples.filter { Date.now.timeIntervalSince($0.date) <= 3 * 3600 }
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Gauge(value: stats.inRangeFraction ?? 0) {
                        Text("TIR")
                    } currentValueLabel: {
                        Text(Self.percent(stats.inRangeFraction))
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .tint(GlucoseBand.inRange.color)
                    VStack(alignment: .leading) {
                        Text(stats.inRangeLabel).font(.caption2).foregroundStyle(.secondary)
                        Text("Avg \(stats.mean.map(unit.format) ?? "—")").font(.headline)
                        Text("\(stats.lowEpisodes) low · \(stats.highEpisodes) high").font(.caption2)
                    }
                }
                if !recent.isEmpty {
                    Chart {
                        RectangleMark(
                            yStart: .value("Low", unit.value(fromMgdL: model.profile.targets.low)),
                            yEnd: .value("High", unit.value(fromMgdL: model.profile.targets.high))
                        )
                        .foregroundStyle(GlucoseBand.inRange.color.opacity(0.2))
                        ForEach(recent) { sample in
                            LineMark(x: .value("Time", sample.date), y: .value("Glucose", unit.value(fromMgdL: sample.mgdL)))
                                .interpolationMethod(.monotone)
                        }
                    }
                    .chartXAxis(.hidden)
                    .frame(height: 70)
                    Text("Last 3 hours").font(.caption2).foregroundStyle(.secondary)
                }
                Text(SafetyCopy.shortDisclaimer).font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Today")
    }

    static func percent(_ value: Double?) -> String {
        value.map { "\(Int(($0 * 100).rounded()))%" } ?? "—"
    }
}

struct QuickLogPage: View {
    @Environment(WatchModel.self) private var model
    @State private var savedWater = false

    var body: some View {
        List {
            NavigationLink { GlucoseEntryView() } label: {
                Label("Glucose", systemImage: "drop.fill")
            }
            NavigationLink { MealQuickLogView() } label: {
                Label("Meal", systemImage: "fork.knife")
            }
            Button {
                Task { savedWater = await model.logWater(milliliters: 250) }
            } label: {
                Label(savedWater ? "Water saved" : "Water · 250 ml", systemImage: savedWater ? "checkmark.circle.fill" : "waterbottle.fill")
            }
        }
        .navigationTitle("Log")
    }
}

struct GlucoseEntryView: View {
    @Environment(WatchModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var value: Double = 0
    @State private var context: ReadingContext = .other
    @State private var confirming = false

    var body: some View {
        let unit = model.profile.unit
        let range = unit.value(fromMgdL: SafetyGuidance.plausibleRange.lowerBound)...unit.value(fromMgdL: SafetyGuidance.plausibleRange.upperBound)
        ScrollView {
            VStack(spacing: 8) {
                Text(unit == .mgdL ? "\(Int(value.rounded()))" : String(format: "%.1f", value))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .focusable()
                    .digitalCrownRotation($value, from: range.lowerBound, through: range.upperBound, by: unit.entryStep,
                                          sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true)
                    .accessibilityLabel("Reading")
                    .accessibilityValue(unit.formatWithUnit(unit.mgdL(from: value)))
                Text("Turn the Digital Crown · \(unit.symbol)").font(.caption2).foregroundStyle(.secondary)
                Picker("When", selection: $context) {
                    ForEach(ReadingContext.allCases) { Text($0.title).tag($0) }
                }
                Button("Save") {
                    if SafetyGuidance.needsConfirmation(unit.mgdL(from: value)) { confirming = true } else { save() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .navigationTitle("Glucose")
        .onAppear {
            value = unit.value(fromMgdL: model.latest?.mgdL ?? 120)
            if unit == .mgdL { value = value.rounded() } else { value = (value * 10).rounded() / 10 }
        }
        .confirmationDialog("Save \(unit.formatWithUnit(unit.mgdL(from: value)))?", isPresented: $confirming) {
            Button("Save") { save() }
            Button("Change", role: .cancel) {}
        } message: {
            Text("This is outside the usual range.")
        }
    }

    private func save() {
        let mgdL = model.profile.unit.mgdL(from: value)
        Task {
            if await model.logGlucose(mgdL: mgdL, context: context) { dismiss() }
        }
    }
}

struct MealQuickLogView: View {
    @Environment(WatchModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var kind = MealKind.suggested(for: .now)
    @State private var carbs: Double = 45

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Picker("Meal", selection: $kind) {
                    ForEach(MealKind.allCases) { Text($0.title).tag($0) }
                }
                Text("\(Int(carbs)) g carbs")
                    .font(.title2.bold())
                    .focusable()
                    .digitalCrownRotation($carbs, from: 0, through: 200, by: 5, sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true)
                Button("Save") {
                    Task { if await model.logMeal(kind: kind, carbs: carbs) { dismiss() } }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .navigationTitle("Meal")
    }
}
