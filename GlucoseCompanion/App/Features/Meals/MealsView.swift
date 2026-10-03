import GlucoseCore
import SwiftUI

struct MealsView: View {
    @Environment(AppModel.self) private var model
    @State private var logging: LogKind?

    private struct DayGroup: Identifiable {
        var day: Date
        var meals: [MealEvent]
        var id: Date { day }
    }

    private var mealsByDay: [DayGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: model.meals) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { day in
            DayGroup(day: day, meals: grouped[day]!.sorted { $0.date > $1.date })
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("See how each meal affected your glucose: the rise from just before you ate to the highest point in the 3 hours after.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(mealsByDay) { group in
                    Section(group.day.formatted(.dateTime.weekday(.wide).month().day())) {
                        ForEach(group.meals) { meal in
                            NavigationLink(value: meal) {
                                MealRow(meal: meal, response: model.response(for: meal), unit: model.profile.unit)
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets { model.deleteMeal(group.meals[index]) }
                        }
                    }
                }
            }
            .overlay {
                if model.meals.isEmpty {
                    ContentUnavailableView {
                        Label("No meals yet", systemImage: "fork.knife")
                    } description: {
                        Text("Log what you eat and the app shows how each meal affects your glucose.")
                    } actions: {
                        Button("Log a meal") { logging = .meal }.buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Meals")
            .navigationDestination(for: MealEvent.self) { MealDetailView(meal: $0) }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { logging = .meal } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                        .accessibilityLabel("Log meal")
                }
            }
            .sheet(item: $logging) { LogSheet(kind: $0) }
        }
    }
}

struct MealRow: View {
    var meal: MealEvent
    var response: MealResponse?
    var unit: GlucoseUnit

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: meal.kind.systemImage)
                .font(.title3)
                .foregroundStyle(.orange)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(meal.displayName).font(.body.weight(.medium))
                Text("\(Format.time(meal.date)) · \(Int(meal.carbsGrams)) g carbs")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            ResponseBadge(response: response, unit: unit)
        }
    }
}

struct ResponseBadge: View {
    var response: MealResponse?
    var unit: GlucoseUnit

    var body: some View {
        if let response {
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(unit.formatDelta(response.rise)) \(unit.symbol)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                Group {
                    if !response.isComplete {
                        Text("in progress")
                    } else if response.walkedAfter {
                        Label("walked after", systemImage: "figure.walk").labelStyle(.titleAndIcon)
                    } else {
                        Text("peak at \(response.minutesToPeak) min")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        } else {
            Text("No readings").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct MealDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var meal: MealEvent

    var body: some View {
        let response = model.response(for: meal)
        let unit = model.profile.unit
        let window = DateInterval(start: meal.date.addingTimeInterval(-45 * 60), end: meal.date.addingTimeInterval(3.5 * 3600))
        List {
            Section {
                GlucoseChart(samples: model.samples(in: window), meals: [meal],
                             activities: model.activities.filter { window.contains($0.start) },
                             targets: model.profile.targets, unit: unit, domain: window.start...window.end)
                    .frame(height: 220)
                    .listRowInsets(EdgeInsets(top: 12, leading: 8, bottom: 12, trailing: 12))
            }
            Section("Glucose response") {
                if let response {
                    LabeledContent("Before the meal", value: unit.formatWithUnit(response.baseline))
                    LabeledContent("Highest after", value: unit.formatWithUnit(response.peak))
                    LabeledContent("Rise", value: "\(unit.formatDelta(response.rise)) \(unit.symbol)")
                    LabeledContent("Time to peak", value: "\(response.minutesToPeak) min")
                    LabeledContent("Walk afterwards", value: response.walkedAfter ? "Yes" : "No")
                    if !response.isHighConfidence {
                        Text("Based on a few fingerstick readings, so the true peak may have been higher.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text(model.profile.usesCGM
                         ? "Not enough readings around this meal yet."
                         : "Add a reading from just before the meal and one about 2 hours after to see its effect.")
                        .foregroundStyle(.secondary)
                }
            }
            Section("Meal") {
                LabeledContent("Type", value: meal.kind.title)
                LabeledContent("Time", value: meal.date.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Carbohydrates", value: "\(Int(meal.carbsGrams)) g")
                if !meal.note.isEmpty { Text(meal.note) }
                if let data = model.mealPhoto(for: meal), let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            Section {
                Button("Delete meal", role: .destructive) {
                    model.deleteMeal(meal)
                    dismiss()
                }
            }
        }
        .navigationTitle(meal.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
