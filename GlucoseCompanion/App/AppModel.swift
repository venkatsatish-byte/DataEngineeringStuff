import Foundation
import GlucoseCore
import GlucoseHealth
import GlucoseStorage
import Observation
import UIKit
import WidgetKit

/// App-wide state and actions. Feature view models read from it; views call
/// its actions. All health data flows Apple Health → local mirror → screens.
@Observable
@MainActor
final class AppModel {
    var profile: UserProfile {
        didSet {
            guard profile != oldValue else { return }
            sharedStore.save(profile)
            connectivity.send(profile)
            updateSnapshot()
        }
    }

    var reminders: [Reminder] {
        didSet {
            guard reminders != oldValue else { return }
            sharedStore.save(reminders)
            let reminders = reminders
            Task { await scheduler.reschedule(reminders) }
        }
    }

    var selectedTab: AppTab
    var urgentAlert: UrgentAlert?
    var errorMessage: String?

    private(set) var samples: [GlucoseSample] = []
    private(set) var meals: [MealEvent] = []
    private(set) var activities: [ActivityEvent] = []
    private(set) var todayActivity = DailyActivity(date: .now, steps: 0, exerciseMinutes: 0)
    private(set) var isRefreshing = false

    let isDemo: Bool
    @ObservationIgnored let scheduler = ReminderScheduler()
    @ObservationIgnored private let options: LaunchOptions
    @ObservationIgnored private let health: any HealthDataProviding
    @ObservationIgnored private let repository: GlucoseRepository
    @ObservationIgnored private let sharedStore: SharedStore
    @ObservationIgnored private let connectivity = PhoneConnectivity()
    @ObservationIgnored private var lastAlertedReadingID: UUID?
    @ObservationIgnored private var started = false

    init(options: LaunchOptions) {
        self.options = options
        isDemo = options.demoMode
        selectedTab = options.initialTab

        let defaults: UserDefaults
        if options.demoMode, let demoDefaults = UserDefaults(suiteName: "GlucoseCompanion.demo") {
            demoDefaults.removePersistentDomain(forName: "GlucoseCompanion.demo")
            defaults = demoDefaults
        } else {
            defaults = AppGroup.defaults
        }
        sharedStore = SharedStore(defaults: defaults)

        var profile = sharedStore.loadProfile()
        if options.demoMode {
            profile.hasCompletedOnboarding = !options.showOnboarding
            if !options.showOnboarding { profile.acceptDisclaimer() }
            profile.careContactName = "Dr. Rivera (sample)"
        }
        self.profile = profile
        reminders = sharedStore.loadReminders()

        if options.demoMode {
            health = DemoHealthService(dataset: SampleData.make(days: 30, continuous: profile.usesCGM))
        } else {
            health = HealthKitService()
        }

        do {
            repository = try GlucoseRepository(inMemory: options.demoMode, defaults: defaults)
        } catch {
            // A corrupt store must never block the app; rebuild from Apple Health.
            repository = try! GlucoseRepository(inMemory: true, defaults: defaults)
            errorMessage = "Local data couldn't be opened and will be rebuilt from Apple Health."
        }
    }

    // MARK: Lifecycle

    func start() async {
        guard !started else { return }
        started = true

        if let demo = health as? DemoHealthService {
            for meal in demo.meals { try? repository.save(meal: meal, photo: nil) }
        }
        if options.showUrgentDemo {
            urgentAlert = UrgentAlert(readingID: UUID(), kind: .low, mgdL: 48, readingDate: .now)
        }
        connectivity.onMealReceived = { [weak self] meal in
            Task { @MainActor in await self?.importWatchMeal(meal) }
        }
        health.startObservingGlucose { [weak self] in
            Task { @MainActor in await self?.refresh() }
        }
        connectivity.send(profile)
        if profile.hasCompletedOnboarding {
            await refresh()
        }
        await scheduler.reschedule(reminders)
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let changes = try await health.glucoseChanges(since: repository.healthAnchor)
            try repository.upsert(changes.added)
            try repository.deleteReadings(ids: changes.deletedIDs)
            repository.healthAnchor = changes.anchor
            reload()
            checkForUrgentReading(in: changes.added)
        } catch {
            errorMessage = "Couldn't read glucose from Apple Health. \(error.localizedDescription)"
        }

        let now = Date.now
        if let recent = try? await health.activities(from: now.addingTimeInterval(-31 * 86_400), to: now) {
            activities = recent
        }
        if let today = try? await health.activity(for: now) {
            todayActivity = today
        }
        updateSnapshot()
    }

    func requestHealthAccess() async {
        do {
            try await health.requestAuthorization()
            await refresh()
        } catch {
            errorMessage = "Apple Health access wasn't granted. You can change this in the Health app under Sharing → Apps."
        }
    }

    func completeOnboarding() async {
        profile.hasCompletedOnboarding = true
        await refresh()
    }

    // MARK: Logging

    /// Saves a manual reading to Apple Health and the local store. Returns false on failure.
    @discardableResult
    func logGlucose(mgdL: Double, date: Date, context: ReadingContext, note: String) async -> Bool {
        let sample = GlucoseSample(date: date, mgdL: mgdL, context: context, source: .manual,
                                   sourceName: "GlucoseCompanion", note: note)
        do {
            try await health.save(sample)
            try repository.upsert([sample])
        } catch {
            errorMessage = "The reading couldn't be saved to Apple Health. Check Health access in Settings."
            return false
        }
        reload()
        updateSnapshot()
        // Only recent readings call for urgent guidance; logging an old value doesn't.
        if Date.now.timeIntervalSince(date) < 3 * 3600, let alert = SafetyGuidance.alert(for: sample, targets: profile.targets) {
            present(alert)
        }
        return true
    }

    func deleteReading(_ sample: GlucoseSample) async {
        guard sample.source == .manual else { return }
        do {
            try await health.deleteReading(id: sample.id)
            try repository.deleteReadings(ids: [sample.id])
            reload()
            updateSnapshot()
        } catch {
            errorMessage = "The reading couldn't be deleted. \(error.localizedDescription)"
        }
    }

    @discardableResult
    func logMeal(_ meal: MealEvent, photo: Data?) async -> Bool {
        do {
            try repository.save(meal: meal, photo: photo)
        } catch {
            errorMessage = "The meal couldn't be saved. \(error.localizedDescription)"
            return false
        }
        reload()
        // Carbs also go to Apple Health; a failure there doesn't lose the meal.
        do { try await health.save(meal: meal) } catch {
            errorMessage = "Meal saved, but carbs couldn't be written to Apple Health."
        }
        await scheduler.mealLogged(meal, reminders: reminders, remindToCheck: !profile.usesCGM)
        return true
    }

    /// A meal logged on Apple Watch. The Watch already wrote its carbs to Apple Health.
    func importWatchMeal(_ meal: MealEvent) async {
        try? repository.save(meal: meal, photo: nil)
        reload()
        await scheduler.mealLogged(meal, reminders: reminders, remindToCheck: !profile.usesCGM)
    }

    func deleteMeal(_ meal: MealEvent) {
        try? repository.deleteMeal(id: meal.id)
        reload()
    }

    func mealPhoto(for meal: MealEvent) -> Data? {
        repository.photo(forMeal: meal.id)
    }

    func logWater(milliliters: Double) async {
        do { try await health.saveWater(milliliters: milliliters, at: .now) } catch {
            errorMessage = "Water couldn't be saved to Apple Health."
        }
    }

    // MARK: Derived data

    var latest: GlucoseSample? { samples.last }

    var trend: TrendArrow? { GlucoseAnalytics.trend(from: Array(samples.suffix(12))) }

    func samples(in interval: DateInterval) -> [GlucoseSample] {
        samples.filter { interval.contains($0.date) }
    }

    func response(for meal: MealEvent) -> MealResponse? {
        GlucoseAnalytics.mealResponse(for: meal, samples: samples, activities: activities)
    }

    // MARK: Private

    private func reload() {
        let now = Date.now
        let start = now.addingTimeInterval(-31 * 86_400)
        let end = now.addingTimeInterval(3600)
        samples = (try? repository.readings(from: start, to: end)) ?? []
        meals = (try? repository.meals(from: start, to: end)) ?? []
    }

    private func checkForUrgentReading(in added: [GlucoseSample]) {
        guard let newest = added.max(by: { $0.date < $1.date }),
              Date.now.timeIntervalSince(newest.date) < 30 * 60,
              let alert = SafetyGuidance.alert(for: newest, targets: profile.targets) else { return }
        present(alert)
    }

    private func present(_ alert: UrgentAlert) {
        guard alert.readingID != lastAlertedReadingID else { return }
        lastAlertedReadingID = alert.readingID
        urgentAlert = alert
        if profile.hapticAlertsEnabled {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }

    private func updateSnapshot() {
        guard !isDemo else { return }
        sharedStore.save(WidgetSnapshot.make(from: samples, profile: profile))
        WidgetCenter.shared.reloadAllTimelines()
    }
}
