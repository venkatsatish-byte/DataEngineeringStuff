#if canImport(HealthKit) && !os(macOS)
import Foundation
import GlucoseCore
import HealthKit

/// Live Apple Health access for iPhone and Apple Watch.
public final class HealthKitService: HealthDataProviding, @unchecked Sendable {
    /// Metadata key holding this app's full reading context. HealthKit's own
    /// meal-time key only knows "before meal" and "after meal".
    public static let contextMetadataKey = "GCReadingContext"
    /// Prefix for sync identifiers on samples this app writes, so edits
    /// replace the earlier version instead of duplicating it.
    static let syncPrefix = "gc-"

    private let store = HKHealthStore()

    static let mgdL = HKUnit(from: "mg/dL")
    private let glucoseType = HKQuantityType(.bloodGlucose)
    private let carbsType = HKQuantityType(.dietaryCarbohydrates)
    private let waterType = HKQuantityType(.dietaryWater)
    private let stepsType = HKQuantityType(.stepCount)
    private let exerciseType = HKQuantityType(.appleExerciseTime)

    public init() {}

    public var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Only what the app uses today. Request more (sleep, heart rate) when a
    /// feature that needs it ships; App Review checks for unused permissions.
    private var readTypes: Set<HKObjectType> {
        [glucoseType, carbsType, waterType, stepsType, exerciseType, HKObjectType.workoutType()]
    }

    private var shareTypes: Set<HKSampleType> {
        [glucoseType, carbsType, waterType]
    }

    public func requestAuthorization() async throws {
        guard isAvailable else { return }
        try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
    }

    // MARK: Glucose

    public func glucoseChanges(since anchorData: Data?) async throws -> GlucoseChanges {
        let anchor = anchorData.flatMap {
            try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0)
        }
        // The first sync imports the last 90 days; later syncs fetch only changes.
        let start = Date.now.addingTimeInterval(-90 * 86_400)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil)
        let descriptor = HKAnchoredObjectQueryDescriptor(
            predicates: [.quantitySample(type: glucoseType, predicate: predicate)],
            anchor: anchor
        )
        let result = try await descriptor.result(for: store)
        let newAnchor: HKQueryAnchor? = result.newAnchor
        return GlucoseChanges(
            added: result.addedSamples.map(Self.makeSample),
            deletedIDs: result.deletedObjects.map { Self.sampleID(uuid: $0.uuid, metadata: $0.metadata) },
            anchor: newAnchor.flatMap { try? NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true) }
        )
    }

    public func glucoseSamples(from start: Date, to end: Date) async throws -> [GlucoseSample] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: glucoseType, predicate: HKQuery.predicateForSamples(withStart: start, end: end))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        return try await descriptor.result(for: store).map(Self.makeSample)
    }

    public func save(_ reading: GlucoseSample) async throws {
        var metadata: [String: Any] = [
            HKMetadataKeySyncIdentifier: Self.syncPrefix + reading.id.uuidString,
            // Increases with every save, so an edit replaces the older sample.
            HKMetadataKeySyncVersion: Int(Date.now.timeIntervalSince1970 * 1000),
            HKMetadataKeyWasUserEntered: true,
            Self.contextMetadataKey: reading.context.rawValue,
        ]
        switch reading.context {
        case .fasting, .beforeMeal:
            metadata[HKMetadataKeyBloodGlucoseMealTime] = HKBloodGlucoseMealTime.preprandial.rawValue
        case .afterMeal:
            metadata[HKMetadataKeyBloodGlucoseMealTime] = HKBloodGlucoseMealTime.postprandial.rawValue
        case .bedtime, .other:
            break
        }
        let sample = HKQuantitySample(
            type: glucoseType,
            quantity: HKQuantity(unit: Self.mgdL, doubleValue: reading.mgdL),
            start: reading.date,
            end: reading.date,
            metadata: metadata
        )
        try await store.save(sample)
    }

    public func deleteReading(id: UUID) async throws {
        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeySyncIdentifier,
            allowedValues: [Self.syncPrefix + id.uuidString]
        )
        let type = glucoseType
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.deleteObjects(of: type, predicate: predicate) { _, _, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    // MARK: Food and water

    public func save(meal: MealEvent) async throws {
        let carbs = HKQuantitySample(
            type: carbsType,
            quantity: HKQuantity(unit: .gram(), doubleValue: meal.carbsGrams),
            start: meal.date,
            end: meal.date,
            metadata: [HKMetadataKeyFoodType: meal.displayName]
        )
        guard let foodType = HKObjectType.correlationType(forIdentifier: .food) else { return }
        let food = HKCorrelation(
            type: foodType,
            start: meal.date,
            end: meal.date,
            objects: [carbs],
            metadata: [
                HKMetadataKeyFoodType: meal.displayName,
                HKMetadataKeySyncIdentifier: Self.syncPrefix + meal.id.uuidString,
                HKMetadataKeySyncVersion: Int(Date.now.timeIntervalSince1970 * 1000),
            ]
        )
        try await store.save(food)
    }

    public func saveWater(milliliters: Double, at date: Date) async throws {
        let sample = HKQuantitySample(
            type: waterType,
            quantity: HKQuantity(unit: .literUnit(with: .milli), doubleValue: milliliters),
            start: date,
            end: date
        )
        try await store.save(sample)
    }

    // MARK: Activity

    public func activity(for day: Date) async throws -> DailyActivity {
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? day
        async let steps = sum(stepsType, unit: .count(), from: start, to: end)
        async let minutes = sum(exerciseType, unit: .minute(), from: start, to: end)
        return DailyActivity(date: start, steps: Int(await steps), exerciseMinutes: Int(await minutes))
    }

    public func activities(from start: Date, to end: Date) async throws -> [ActivityEvent] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(HKQuery.predicateForSamples(withStart: start, end: end))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        return try await descriptor.result(for: store).map { workout in
            ActivityEvent(id: workout.uuid, start: workout.startDate, end: workout.endDate,
                          kind: Self.kind(for: workout.workoutActivityType))
        }
    }

    /// Returns 0 when there is no data or no permission. HealthKit reports both
    /// the same way, on purpose, so apps can't tell what a user declined.
    private func sum(_ type: HKQuantityType, unit: HKUnit, from start: Date, to end: Date) async -> Double {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: .cumulativeSum
        )
        let statistics = try? await descriptor.result(for: store)
        return statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0
    }

    // MARK: Observing

    public func startObservingGlucose(_ onChange: @escaping @Sendable () -> Void) {
        let query = HKObserverQuery(sampleType: glucoseType, predicate: nil) { _, completion, error in
            if error == nil { onChange() }
            completion()
        }
        store.execute(query)
        // Background delivery is best effort: the system decides how often it
        // runs, which is why the app never presents itself as an alarm.
        store.enableBackgroundDelivery(for: glucoseType, frequency: .immediate) { _, _ in }
    }

    // MARK: Mapping

    static func makeSample(_ sample: HKQuantitySample) -> GlucoseSample {
        let metadata = sample.metadata
        let ownContext = (metadata?[contextMetadataKey] as? String).flatMap(ReadingContext.init(rawValue:))
        let source: ReadingSource = ownContext != nil ? .manual : (isCGM(sample) ? .cgm : .meter)
        return GlucoseSample(
            id: sampleID(uuid: sample.uuid, metadata: metadata),
            date: sample.startDate,
            mgdL: sample.quantity.doubleValue(for: mgdL),
            context: ownContext ?? mealTimeContext(metadata) ?? .other,
            source: source,
            sourceName: sample.sourceRevision.source.name
        )
    }

    /// Samples this app wrote keep the app's own ID, so the local copy and the
    /// Apple Health copy stay one record.
    static func sampleID(uuid: UUID, metadata: [String: Any]?) -> UUID {
        if let sync = metadata?[HKMetadataKeySyncIdentifier] as? String, sync.hasPrefix(syncPrefix),
           let id = UUID(uuidString: String(sync.dropFirst(syncPrefix.count))) {
            return id
        }
        return uuid
    }

    static func mealTimeContext(_ metadata: [String: Any]?) -> ReadingContext? {
        guard let raw = metadata?[HKMetadataKeyBloodGlucoseMealTime] as? NSNumber,
              let mealTime = HKBloodGlucoseMealTime(rawValue: raw.intValue) else { return nil }
        switch mealTime {
        case .preprandial: return .beforeMeal
        case .postprandial: return .afterMeal
        @unknown default: return nil
        }
    }

    /// HealthKit doesn't say whether a reading came from a CGM, so this looks at
    /// the writing app and device. Unknown sources count as meter readings,
    /// which is the conservative choice (no time in range, no trend arrow).
    static func isCGM(_ sample: HKQuantitySample) -> Bool {
        let text = [
            sample.sourceRevision.source.name,
            sample.sourceRevision.source.bundleIdentifier,
            sample.device?.name ?? "",
            sample.device?.model ?? "",
            sample.device?.manufacturer ?? "",
        ].joined(separator: " ").lowercased()
        let markers = ["dexcom", "libre", "freestyle", "eversense", "guardian", "simplera", "stelo", "lingo", "cgm"]
        return markers.contains { text.contains($0) }
    }

    static func kind(for type: HKWorkoutActivityType) -> ActivityKind {
        switch type {
        case .walking, .hiking: return .walk
        case .running: return .run
        case .cycling: return .cycling
        case .traditionalStrengthTraining, .functionalStrengthTraining: return .strength
        default: return .other
        }
    }
}
#endif
