import Charts
import GlucoseCore
import SwiftUI
import WidgetKit

// Compiled into both the iOS widget extension and the watchOS widget extension
// (complications). Widgets only read the snapshot the app writes to the App
// Group, and always show the reading's time so stale data is obvious.

@main
struct GlucoseWidgetBundle: WidgetBundle {
    var body: some Widget {
        LatestReadingWidget()
        TimeInRangeWidget()
    }
}

// MARK: Timeline

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot

    var isStale: Bool { snapshot.isStale(at: date) }
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        let snapshot = context.isPreview ? .placeholder : (SharedStore().loadSnapshot() ?? .placeholder)
        completion(SnapshotEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let snapshot = SharedStore().loadSnapshot() ?? .empty
        let now = Date.now
        var entries = [SnapshotEntry(date: now, snapshot: snapshot)]
        // A second entry at the moment the reading becomes stale, so the widget
        // greys it out even if the app hasn't run since.
        if let latest = snapshot.latestDate {
            let staleAt = latest.addingTimeInterval(GlucoseAnalytics.staleAfter + 1)
            if staleAt > now { entries.append(SnapshotEntry(date: staleAt, snapshot: snapshot)) }
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(15 * 60))))
    }
}

// MARK: Latest reading

struct LatestReadingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LatestReading", provider: SnapshotProvider()) { entry in
            LatestReadingWidgetView(entry: entry)
                .containerBackground(for: .widget) { backgroundColor(entry) }
        }
        .configurationDisplayName("Latest glucose")
        .description("Your most recent reading, trend and how long ago it was taken.")
        .supportedFamilies(Self.families)
    }

    #if os(watchOS)
    static let families: [WidgetFamily] = [.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner]
    #else
    static let families: [WidgetFamily] = [.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline]
    #endif

    private func backgroundColor(_ entry: SnapshotEntry) -> Color {
        #if os(watchOS)
        return .clear
        #else
        guard let band = entry.snapshot.latestBand, !entry.isStale else { return Color(.systemBackground) }
        return band.color.opacity(0.15)
        #endif
    }
}

struct LatestReadingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: SnapshotEntry

    private var snapshot: WidgetSnapshot { entry.snapshot }

    private var valueText: String {
        snapshot.latestMgdL.map(snapshot.unit.format) ?? "—"
    }

    private var arrow: String {
        entry.isStale ? "" : (snapshot.trend?.symbol ?? "")
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            if let date = snapshot.latestDate {
                Text("\(valueText) \(arrow) · \(date, style: .time)")
            } else {
                Text("No readings")
            }

        case .accessoryCircular:
            VStack(spacing: 0) {
                Text(valueText).font(.system(.title3, design: .rounded).weight(.bold)).minimumScaleFactor(0.6)
                Text(arrow.isEmpty ? snapshot.unit.symbol : arrow).font(.caption2)
            }
            .widgetAccentable()
            .opacity(entry.isStale ? 0.5 : 1)

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(valueText).font(.system(.title2, design: .rounded).weight(.bold))
                    Text(arrow).font(.headline)
                    Text(snapshot.unit.symbol).font(.caption2)
                }
                .widgetAccentable()
                if let date = snapshot.latestDate {
                    Text(entry.isStale ? "Stale · \(date.formatted(date: .omitted, time: .shortened))" : "at \(date.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                }
                if let tir = snapshot.todayInRangeFraction {
                    Text("\(Int((tir * 100).rounded()))% in range today").font(.caption2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        #if os(watchOS)
        case .accessoryCorner:
            Text(valueText)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .widgetCurvesContent()
                .widgetLabel {
                    if let date = snapshot.latestDate {
                        Text("\(arrow) \(date.formatted(date: .omitted, time: .shortened))")
                    }
                }
        #endif

        default:
            SystemReadingView(entry: entry, showChart: family == .systemMedium)
        }
    }
}

/// Home Screen widgets (iOS).
struct SystemReadingView: View {
    var entry: SnapshotEntry
    var showChart: Bool

    var body: some View {
        let snapshot = entry.snapshot
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Glucose").font(.caption).foregroundStyle(.secondary)
                if let value = snapshot.latestMgdL, let band = snapshot.latestBand {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(snapshot.unit.format(value))
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundStyle(entry.isStale ? .secondary : .primary)
                        if !entry.isStale, let trend = snapshot.trend {
                            Text(trend.symbol).font(.title2.weight(.semibold))
                        }
                    }
                    Text(snapshot.unit.symbol).font(.caption2).foregroundStyle(.secondary)
                    Label(band.title, systemImage: band.systemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(band.color)
                    Spacer(minLength: 0)
                    if let date = snapshot.latestDate {
                        Text(entry.isStale ? "No new reading since \(date.formatted(date: .omitted, time: .shortened))" : "at \(date.formatted(date: .omitted, time: .shortened))")
                            .font(.caption2)
                            .foregroundStyle(entry.isStale ? .orange : .secondary)
                    }
                } else {
                    Text("No readings").font(.headline)
                    Text("Open the app to connect Apple Health.").font(.caption2).foregroundStyle(.secondary)
                }
            }
            if showChart, !snapshot.recent.isEmpty {
                Chart {
                    RectangleMark(
                        yStart: .value("Low", snapshot.unit.value(fromMgdL: snapshot.targets.low)),
                        yEnd: .value("High", snapshot.unit.value(fromMgdL: snapshot.targets.high))
                    )
                    .foregroundStyle(GlucoseBand.inRange.color.opacity(0.15))
                    ForEach(snapshot.recent, id: \.date) { point in
                        LineMark(x: .value("Time", point.date), y: .value("Glucose", snapshot.unit.value(fromMgdL: point.mgdL)))
                            .interpolationMethod(.monotone)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
            }
        }
    }
}

// MARK: Time in range

struct TimeInRangeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TimeInRange", provider: SnapshotProvider()) { entry in
            TimeInRangeWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Time in range today")
        .description("How much of today your glucose has been in your target range.")
        .supportedFamilies(Self.families)
    }

    #if os(watchOS)
    static let families: [WidgetFamily] = [.accessoryCircular, .accessoryRectangular]
    #else
    static let families: [WidgetFamily] = [.systemSmall, .accessoryCircular, .accessoryRectangular]
    #endif
}

struct TimeInRangeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: SnapshotEntry

    var body: some View {
        let fraction = entry.snapshot.todayInRangeFraction
        let label = entry.snapshot.todayIsContinuous ? "in range" : "readings in range"
        switch family {
        case .accessoryCircular:
            Gauge(value: fraction ?? 0) {
                Text("TIR")
            } currentValueLabel: {
                Text(fraction.map { "\(Int(($0 * 100).rounded()))" } ?? "—")
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Text("Today").font(.caption2)
                Text(fraction.map { "\(Int(($0 * 100).rounded()))% \(label)" } ?? "No readings today")
                    .font(.headline)
                    .widgetAccentable()
                Gauge(value: fraction ?? 0) { EmptyView() }.gaugeStyle(.accessoryLinearCapacity)
            }
        default:
            VStack(alignment: .leading, spacing: 6) {
                Text("Today").font(.caption).foregroundStyle(.secondary)
                Text(fraction.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(GlucoseBand.inRange.color)
                Text(label).font(.caption)
                Gauge(value: fraction ?? 0) { EmptyView() }
                    .gaugeStyle(.accessoryLinearCapacity)
                    .tint(GlucoseBand.inRange.color)
            }
        }
    }
}
