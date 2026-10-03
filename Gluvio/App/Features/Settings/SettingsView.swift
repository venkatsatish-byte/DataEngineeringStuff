import GlucoseCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppHost.self) private var host

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section("Glucose") {
                    Picker("Units", selection: $model.profile.unit) {
                        ForEach(GlucoseUnit.allCases) { Text($0.symbol).tag($0) }
                    }
                    NavigationLink {
                        TargetRangeView()
                    } label: {
                        LabeledContent("Target range",
                                       value: "\(model.profile.unit.format(model.profile.targets.low))–\(model.profile.unit.formatWithUnit(model.profile.targets.high))")
                    }
                    Toggle("I use a CGM", isOn: $model.profile.usesCGM)
                }

                Section("Daily goals") {
                    Stepper(value: $model.profile.stepGoal, in: 1000...30000, step: 500) {
                        LabeledContent("Steps", value: model.profile.stepGoal.formatted())
                    }
                    Stepper(value: $model.profile.activeMinutesGoal, in: 5...180, step: 5) {
                        LabeledContent("Active minutes", value: "\(model.profile.activeMinutesGoal)")
                    }
                }

                Section {
                    NavigationLink("Reminders") { RemindersView() }
                    Toggle("Haptic for readings outside my range", isOn: $model.profile.hapticAlertsEnabled)
                } header: {
                    Text("Reminders and alerts")
                } footer: {
                    Text("For information only. Readings can reach Apple Health late, so your CGM or meter's own app remains your alarm for highs and lows.")
                }

                Section {
                    TextField("Name", text: $model.profile.careContactName)
                    TextField("Phone", text: $model.profile.careContactPhone)
                        .keyboardType(.phonePad)
                } header: {
                    Text("Care contact")
                } footer: {
                    Text("Shown with a call button when a reading is very low or very high.")
                }

                Section("Doctor report") {
                    NavigationLink {
                        ReportView()
                    } label: {
                        Label("Create a PDF report", systemImage: "doc.richtext")
                    }
                }

                Section {
                    Button("Review Apple Health access") { Task { await model.requestHealthAccess() } }
                    if let url = URL(string: "x-apple-health://") {
                        Link("Open the Health app", destination: url)
                    }
                } header: {
                    Text("Apple Health")
                } footer: {
                    Text("To change what Gluvio can read or write, open Health → your profile → Apps → Gluvio.")
                }

                Section("About") {
                    NavigationLink("Medical disclaimer") { DisclaimerView() }
                    NavigationLink("Privacy") {
                        ScrollView { Text(SafetyCopy.privacySummary).padding() }.navigationTitle("Privacy")
                    }
                    Toggle("Explore with sample data", isOn: Binding(
                        get: { model.isDemo },
                        set: { host.setDemoMode($0) }
                    ))
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                }
            }
            .navigationTitle("Settings")
        }
    }
}

struct TargetRangeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var targets = TargetRange.standard

    var body: some View {
        let unit = model.profile.unit
        Form {
            Section {
                TargetStepper(title: "Low", value: $targets.low, unit: unit, range: 60...110)
                TargetStepper(title: "High", value: $targets.high, unit: unit, range: 120...250)
            } header: {
                Text("Target range")
            } footer: {
                Text("Use the range your care team recommends. The common default is 70–180 mg/dL (3.9–10.0 mmol/L).")
            }
            Section {
                TargetStepper(title: "Very low below", value: $targets.urgentLow, unit: unit, range: 40...65)
                TargetStepper(title: "Very high above", value: $targets.urgentHigh, unit: unit, range: 200...400)
            } header: {
                Text("Urgent thresholds")
            } footer: {
                Text("Readings beyond these show urgent guidance to follow your care plan. Set them with your care team.")
            }
            if !targets.isValid {
                Text("Each threshold must be in order: very low < low < high < very high.")
                    .foregroundStyle(.red)
            }
            Section {
                Button("Reset to defaults") { targets = .standard }
            }
        }
        .navigationTitle("Target range")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    model.profile.targets = targets
                    dismiss()
                }
                .disabled(!targets.isValid)
            }
        }
        .onAppear { targets = model.profile.targets }
    }
}

struct DisclaimerView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            ForEach(SafetyCopy.disclaimerPoints, id: \.self) { Text($0) }
            if let date = model.profile.acceptedDisclaimerAt {
                Text("Accepted \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(SafetyCopy.disclaimerTitle)
    }
}

struct RemindersView: View {
    @Environment(AppModel.self) private var model
    @State private var notificationsAllowed = true

    var body: some View {
        @Bindable var model = model
        List {
            if !notificationsAllowed {
                Section {
                    Button("Allow notifications") {
                        Task {
                            notificationsAllowed = await model.scheduler.requestPermission()
                            await model.scheduler.reschedule(model.reminders)
                        }
                    }
                } footer: {
                    Text("Reminders need notification permission. If you turned it off before, change it in the Settings app.")
                }
            }
            Section {
                ForEach($model.reminders) { $reminder in
                    NavigationLink {
                        ReminderEditView(reminder: $reminder)
                    } label: {
                        Toggle(isOn: $reminder.isEnabled) {
                            Label {
                                VStack(alignment: .leading) {
                                    Text(reminder.title)
                                    Text(schedule(for: reminder)).font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: reminder.kind.systemImage)
                            }
                        }
                    }
                }
                .onDelete { model.reminders.remove(atOffsets: $0) }
            } footer: {
                Text("Reminders also appear on your Apple Watch.")
            }
            Section {
                Menu {
                    ForEach(Reminder.Kind.allCases) { kind in
                        Button { model.reminders.append(Reminder(kind: kind)) } label: {
                            Label(kind.title, systemImage: kind.systemImage)
                        }
                    }
                } label: {
                    Label("Add reminder", systemImage: "plus")
                }
            }
        }
        .navigationTitle("Reminders")
        .task { notificationsAllowed = await model.scheduler.isAuthorized() }
    }

    private func schedule(for reminder: Reminder) -> String {
        if reminder.kind.isMealTriggered { return "\(reminder.minutesAfterMeal) min after each meal you log" }
        var components = DateComponents()
        components.hour = reminder.hour
        components.minute = reminder.minute
        let time = Calendar.current.date(from: components).map(Format.time) ?? ""
        if reminder.weekdays.isEmpty { return "Every day at \(time)" }
        let names = reminder.weekdays.sorted().map { Calendar.current.shortWeekdaySymbols[$0 - 1] }
        return "\(names.joined(separator: ", ")) at \(time)"
    }
}

struct ReminderEditView: View {
    @Binding var reminder: Reminder

    var body: some View {
        Form {
            Section {
                Picker("Type", selection: $reminder.kind) {
                    ForEach(Reminder.Kind.allCases) { Text($0.title).tag($0) }
                }
                TextField("Label", text: $reminder.title)
                if reminder.kind == .medication {
                    Text("Use a name you'll recognise. The app doesn't store or suggest doses.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            if reminder.kind.isMealTriggered {
                Section {
                    Stepper("\(reminder.minutesAfterMeal) minutes after a meal", value: $reminder.minutesAfterMeal, in: 5...90, step: 5)
                }
            } else {
                Section {
                    DatePicker("Time", selection: timeBinding, displayedComponents: .hourAndMinute)
                    WeekdayPicker(selection: $reminder.weekdays)
                } footer: {
                    Text("No days selected means every day.")
                }
            }
        }
        .navigationTitle(reminder.title)
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(from: DateComponents(hour: reminder.hour, minute: reminder.minute)) ?? .now
            },
            set: {
                let parts = Calendar.current.dateComponents([.hour, .minute], from: $0)
                reminder.hour = parts.hour ?? 9
                reminder.minute = parts.minute ?? 0
            }
        )
    }
}

struct WeekdayPicker: View {
    @Binding var selection: Set<Int>

    var body: some View {
        HStack {
            ForEach(1...7, id: \.self) { day in
                let isOn = selection.contains(day)
                Button(Calendar.current.veryShortWeekdaySymbols[day - 1]) {
                    if isOn { selection.remove(day) } else { selection.insert(day) }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(isOn ? Color.accentColor : Color(uiColor: .systemGray5), in: Circle())
                .foregroundStyle(isOn ? .white : .primary)
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}
