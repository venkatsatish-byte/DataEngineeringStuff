import GlucoseCore
import SwiftUI

struct LogGlucoseView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var valueText = ""
    @State private var date = Date.now
    @State private var context: ReadingContext = .other
    @State private var note = ""
    @State private var confirmingUnusual = false
    @State private var isSaving = false
    @FocusState private var valueFocused: Bool

    private var unit: GlucoseUnit { model.profile.unit }

    private var mgdL: Double? {
        Double(valueText.replacingOccurrences(of: ",", with: ".")).map(unit.mgdL(from:))
    }

    private var validationMessage: String? {
        guard !valueText.isEmpty else { return nil }
        guard let mgdL else { return "Enter a number." }
        guard SafetyGuidance.plausibleRange.contains(mgdL) else {
            return "That doesn't look like a valid reading. Check the number and the units (\(unit.symbol))."
        }
        if date > .now.addingTimeInterval(60) { return "The time can't be in the future." }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Reading", text: $valueText)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .focused($valueFocused)
                        Text(unit.symbol).foregroundStyle(.secondary)
                    }
                    if let validationMessage {
                        Text(validationMessage).font(.footnote).foregroundStyle(.red)
                    } else if let mgdL {
                        let band = model.profile.targets.band(for: mgdL)
                        Label(band.title, systemImage: band.systemImage).foregroundStyle(band.color).font(.footnote)
                    }
                }
                Section {
                    DatePicker("Time", selection: $date, in: ...Date.now)
                    Picker("When", selection: $context) {
                        ForEach(ReadingContext.allCases) { Text($0.title).tag($0) }
                    }
                }
                Section("Note") {
                    TextField("Optional", text: $note, axis: .vertical)
                }
                Section {
                    Text("Saved to Apple Health as well as this app.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Glucose reading")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let mgdL else { return }
                        if SafetyGuidance.needsConfirmation(mgdL) { confirmingUnusual = true } else { save() }
                    }
                    .disabled(mgdL == nil || validationMessage != nil || isSaving)
                }
            }
            .confirmationDialog(
                "Save a reading of \(mgdL.map(unit.formatWithUnit) ?? "")?",
                isPresented: $confirmingUnusual,
                titleVisibility: .visible
            ) {
                Button("Save reading") { save() }
                Button("Check the number", role: .cancel) { valueFocused = true }
            } message: {
                Text("This is outside the usual range. Please make sure it's correct.")
            }
            .onAppear {
                context = suggestedContext()
                valueFocused = true
            }
        }
    }

    private func save() {
        guard let mgdL else { return }
        isSaving = true
        Task {
            let saved = await model.logGlucose(mgdL: mgdL, date: date, context: context, note: note)
            isSaving = false
            if saved { dismiss() }
        }
    }

    /// Guesses the context from the time and recent meals; the user can change it.
    private func suggestedContext() -> ReadingContext {
        let now = Date.now
        if let lastMeal = model.meals.first(where: { $0.date <= now }),
           now.timeIntervalSince(lastMeal.date) < 3 * 3600 {
            return .afterMeal
        }
        let hour = Calendar.current.component(.hour, from: now)
        if hour < 9 { return .fasting }
        if hour >= 21 { return .bedtime }
        return .beforeMeal
    }
}
