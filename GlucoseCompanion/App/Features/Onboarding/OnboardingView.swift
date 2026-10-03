import GlucoseCore
import SwiftUI

/// Welcome → disclaimer → targets → CGM → Apple Health → notifications.
/// A step-by-step flow (not swipeable pages) so the disclaimer can't be skipped.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppHost.self) private var host
    @State private var step = Step.welcome
    @State private var acceptedDisclaimer = false
    @State private var isWorking = false

    enum Step: Int, CaseIterable {
        case welcome, disclaimer, targets, cgm, health, notifications
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double(step.rawValue + 1), total: Double(Step.allCases.count))
                    .padding(.horizontal)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        content(profile: $model.profile)
                    }
                    .padding(24)
                }
                primaryButton
                    .padding(24)
            }
            .toolbar {
                if step != .welcome {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Back") { step = Step(rawValue: step.rawValue - 1) ?? .welcome }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func content(profile: Binding<UserProfile>) -> some View {
        switch step {
        case .welcome:
            Image(systemName: "drop.circle.fill").font(.system(size: 64)).foregroundStyle(.tint)
            Text("Understand your blood sugar").font(.largeTitle.bold())
            Text("Track readings, see your daily trends, and learn how meals and walks affect you, on your iPhone and Apple Watch.")
                .font(.title3).foregroundStyle(.secondary)
            Button("Explore with sample data") { host.setDemoMode(true) }
                .padding(.top)

        case .disclaimer:
            Text(SafetyCopy.disclaimerTitle).font(.largeTitle.bold())
            ForEach(SafetyCopy.disclaimerPoints, id: \.self) { point in
                Label(point, systemImage: "checkmark.shield").font(.body)
            }
            Toggle("I understand", isOn: $acceptedDisclaimer)
                .font(.headline)
                .padding(.top)

        case .targets:
            Text("Your targets").font(.largeTitle.bold())
            Picker("Units", selection: profile.unit) {
                ForEach(GlucoseUnit.allCases) { Text($0.symbol).tag($0) }
            }
            .pickerStyle(.segmented)
            TargetStepper(title: "Low end of range", value: profile.targets.low, unit: profile.wrappedValue.unit, range: 60...100)
            TargetStepper(title: "High end of range", value: profile.targets.high, unit: profile.wrappedValue.unit, range: 120...250)
            Text("Most adults with Type 2 diabetes use 70–180 mg/dL (3.9–10.0 mmol/L). Use the range your care team gave you. You can change it later in Settings.")
                .font(.footnote).foregroundStyle(.secondary)

        case .cgm:
            Text("How do you check?").font(.largeTitle.bold())
            Picker("Monitoring", selection: profile.usesCGM) {
                Text("Continuous glucose monitor (CGM)").tag(true)
                Text("Fingerstick meter").tag(false)
            }
            .pickerStyle(.inline)
            .labelsHidden()
            Text(profile.wrappedValue.usesCGM
                 ? "Readings from Dexcom, FreeStyle Libre and other CGMs reach the app through Apple Health. Some CGM apps write to Health with a delay, so your CGM's own app remains your alarm."
                 : "You can enter readings by hand, or use a meter that saves to Apple Health. After you log a meal, the app can remind you to check 2 hours later.")
                .foregroundStyle(.secondary)

        case .health:
            Image(systemName: "heart.text.square.fill").font(.system(size: 56)).foregroundStyle(.pink)
            Text("Connect Apple Health").font(.largeTitle.bold())
            Text("GlucoseCompanion reads:").font(.headline)
            Label("Blood glucose from your CGM, meter and manual entries", systemImage: "drop")
            Label("Steps, exercise minutes and workouts, to show how activity affects you", systemImage: "figure.walk")
            Label("Carbohydrates and water you log", systemImage: "fork.knife")
            Text("It saves the readings, meals and water you enter here back to Apple Health. \(SafetyCopy.privacySummary)")
                .font(.footnote).foregroundStyle(.secondary)

        case .notifications:
            Image(systemName: "bell.badge.fill").font(.system(size: 56)).foregroundStyle(.orange)
            Text("Gentle reminders").font(.largeTitle.bold())
            Text("Reminders to check your glucose and to take a short walk after meals. They also appear on your Apple Watch. You choose which ones in Settings.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch step {
        case .health:
            VStack(spacing: 12) {
                actionButton("Connect Apple Health") {
                    await model.requestHealthAccess()
                    step = .notifications
                }
                Button("Not now") { step = .notifications }
            }
        case .notifications:
            VStack(spacing: 12) {
                actionButton("Turn on reminders") {
                    _ = await model.scheduler.requestPermission()
                    await model.scheduler.reschedule(model.reminders)
                    await finish()
                }
                Button("Not now") { Task { await finish() } }
            }
        default:
            actionButton("Continue") { advance() }
                .disabled(step == .disclaimer && !acceptedDisclaimer)
        }
    }

    private func actionButton(_ title: String, action: @escaping () async -> Void) -> some View {
        Button {
            isWorking = true
            Task {
                await action()
                isWorking = false
            }
        } label: {
            Text(title).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(isWorking)
    }

    private func advance() {
        if step == .disclaimer { model.profile.acceptDisclaimer() }
        step = Step(rawValue: step.rawValue + 1) ?? .notifications
    }

    private func finish() async {
        await model.completeOnboarding()
    }
}

/// Edits a threshold stored in mg/dL, displayed in the user's unit.
struct TargetStepper: View {
    var title: String
    @Binding var value: Double
    var unit: GlucoseUnit
    var range: ClosedRange<Double>

    var body: some View {
        Stepper(value: Binding(
            get: { unit.value(fromMgdL: value) },
            set: { value = min(range.upperBound, max(range.lowerBound, unit.mgdL(from: $0))) }
        ), step: unit == .mgdL ? 5 : 0.1) {
            HStack {
                Text(title)
                Spacer()
                Text(unit.formatWithUnit(value)).monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }
}
