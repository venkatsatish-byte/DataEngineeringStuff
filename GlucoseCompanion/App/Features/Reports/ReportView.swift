import GlucoseCore
import SwiftUI

struct ReportView: View {
    @Environment(AppModel.self) private var model
    @State private var days = 14
    @State private var pdfURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        let report = DoctorReport(samples: model.samples, meals: model.meals, activities: model.activities,
                                  profile: model.profile, days: days)
        Form {
            Section {
                Picker("Period", selection: $days) {
                    Text("14 days").tag(14)
                    Text("30 days").tag(30)
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("A summary to share with your doctor or diabetes educator: averages, time in range, an estimated A1C, daily trends and how meals affected you.")
            }

            Section("Preview") {
                LabeledContent("Readings", value: "\(report.stats.readingCount)")
                LabeledContent("Average", value: report.stats.mean.map(report.unit.formatWithUnit) ?? "—")
                LabeledContent(report.stats.inRangeLabel, value: Format.percent(report.stats.inRangeFraction))
                LabeledContent(report.a1c.label, value: report.a1c.percent.map { String(format: "%.1f%%", $0) } ?? "Not enough data")
            }

            Section {
                if let pdfURL {
                    ShareLink(item: pdfURL) {
                        Label("Share PDF", systemImage: "square.and.arrow.up")
                    }
                }
                Button(pdfURL == nil ? "Create PDF" : "Create again") {
                    do { pdfURL = try ReportRenderer.makePDF(report: report) } catch {
                        errorMessage = "The PDF couldn't be created. \(error.localizedDescription)"
                    }
                }
                .disabled(report.stats.readingCount == 0)
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            } footer: {
                Text("The PDF is created on your iPhone and only leaves it if you share it.")
            }
        }
        .navigationTitle("Doctor report")
        .onChange(of: days) { pdfURL = nil }
    }
}

/// Page 1 of the PDF.
struct ReportSummaryPage: View {
    var report: DoctorReport

    var body: some View {
        let unit = report.unit
        VStack(alignment: .leading, spacing: 14) {
            ReportHeader(report: report)

            HStack(spacing: 10) {
                summaryBox("Average", report.stats.mean.map(unit.formatWithUnit) ?? "—")
                summaryBox(report.stats.inRangeLabel, Format.percent(report.stats.inRangeFraction))
                summaryBox(report.a1c.label, report.a1c.percent.map { String(format: "%.1f%%", $0) } ?? "—")
                summaryBox("Variability (CV)", Format.percent(report.stats.coefficientOfVariation))
            }

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Time in ranges").font(.system(size: 12, weight: .semibold))
                    TimeInRangeBar(stats: report.stats)
                        .font(.system(size: 10))
                }
                .frame(width: 190)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Daily average and range").font(.system(size: 12, weight: .semibold))
                    DailyTrendChart(days: report.daily, targets: report.targets, unit: unit)
                        .frame(height: 170)
                }
            }

            Text("""
                Target \(unit.format(report.targets.low))–\(unit.formatWithUnit(report.targets.high)). \
                \(report.stats.readingCount) readings, \(report.stats.lowEpisodes) low and \(report.stats.highEpisodes) high episodes. \
                \(report.a1c.explanation)
                """)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)

            if !report.biggestRises.isEmpty {
                Text("Meals with the biggest rise").font(.system(size: 12, weight: .semibold))
                ForEach(report.biggestRises) { line in mealLine(line, unit: unit) }
                Text("Meals with the smallest rise").font(.system(size: 12, weight: .semibold))
                ForEach(report.gentlestMeals) { line in mealLine(line, unit: unit) }
            }
            if let walk = report.walkInsight {
                Text("After meals followed by a walk, glucose rose \(unit.formatWithUnit(walk.averageRiseWithWalk)) on average (\(walk.mealsWithWalk) meals) versus \(unit.formatWithUnit(walk.averageRiseWithoutWalk)) without (\(walk.mealsWithoutWalk) meals).")
                    .font(.system(size: 10))
            }
            Spacer()
            ReportFooter()
        }
        .padding(36)
        .foregroundStyle(.black)
        .background(.white)
        .environment(\.colorScheme, .light)
    }

    private func summaryBox(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 8)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 16, weight: .bold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }

    private func mealLine(_ line: DoctorReport.MealLine, unit: GlucoseUnit) -> some View {
        HStack {
            Text(line.meal.date.formatted(.dateTime.month().day().hour().minute())).frame(width: 90, alignment: .leading)
            Text("\(line.meal.displayName), \(Int(line.meal.carbsGrams)) g carbs")
            Spacer()
            Text("\(unit.formatDelta(line.response.rise)) \(unit.symbol)\(line.response.walkedAfter ? " · walked" : "")")
        }
        .font(.system(size: 10))
    }
}

/// Logbook pages: manual and meter readings.
struct ReportLogbookPage: View {
    static let rowsPerPage = 38
    var report: DoctorReport
    var rows: [GlucoseSample]
    var page: Int
    var of: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ReportHeader(report: report)
            Text("Logbook (\(page) of \(of))").font(.system(size: 12, weight: .semibold))
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 3) {
                GridRow {
                    Text("Date and time"); Text("Reading"); Text("When"); Text("Note")
                }
                .font(.system(size: 9, weight: .semibold))
                ForEach(rows) { sample in
                    GridRow {
                        Text(sample.date.formatted(date: .abbreviated, time: .shortened))
                        Text(report.unit.formatWithUnit(sample.mgdL))
                            .foregroundStyle(report.targets.contains(sample.mgdL) ? .black : .red)
                        Text(sample.context.title)
                        Text(sample.note).lineLimit(1)
                    }
                    .font(.system(size: 9))
                }
            }
            Spacer()
            ReportFooter()
        }
        .padding(36)
        .foregroundStyle(.black)
        .background(.white)
        .environment(\.colorScheme, .light)
    }
}

struct ReportHeader: View {
    var report: DoctorReport

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Glucose summary").font(.system(size: 20, weight: .bold))
            Text("\(report.period.start.formatted(date: .abbreviated, time: .omitted)) – \(report.period.end.formatted(date: .abbreviated, time: .omitted)) · \(report.days) days · created \(report.generatedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }
}

struct ReportFooter: View {
    var body: some View {
        Text("Created with GlucoseCompanion from the patient's own data. \(SafetyCopy.shortDisclaimer)")
            .font(.system(size: 8))
            .foregroundStyle(.secondary)
    }
}
