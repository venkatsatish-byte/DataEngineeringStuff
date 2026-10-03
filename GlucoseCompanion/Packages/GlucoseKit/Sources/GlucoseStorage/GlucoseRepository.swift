#if canImport(SwiftData)
import Foundation
import GlucoseCore
import SwiftData

@Model
public final class StoredReading {
    @Attribute(.unique) public var id: UUID
    public var date: Date
    public var mgdL: Double
    public var contextRaw: String
    public var sourceRaw: String
    public var sourceName: String
    public var note: String

    public init(_ sample: GlucoseSample) {
        id = sample.id
        date = sample.date
        mgdL = sample.mgdL
        contextRaw = sample.context.rawValue
        sourceRaw = sample.source.rawValue
        sourceName = sample.sourceName
        note = sample.note
    }

    func update(from sample: GlucoseSample) {
        date = sample.date
        mgdL = sample.mgdL
        contextRaw = sample.context.rawValue
        sourceRaw = sample.source.rawValue
        sourceName = sample.sourceName
        note = sample.note
    }

    public var sample: GlucoseSample {
        GlucoseSample(
            id: id, date: date, mgdL: mgdL,
            context: ReadingContext(rawValue: contextRaw) ?? .other,
            source: ReadingSource(rawValue: sourceRaw) ?? .meter,
            sourceName: sourceName, note: note
        )
    }
}

@Model
public final class StoredMeal {
    @Attribute(.unique) public var id: UUID
    public var date: Date
    public var kindRaw: String
    public var name: String
    public var carbsGrams: Double
    public var note: String
    @Attribute(.externalStorage) public var photo: Data?

    public init(_ meal: MealEvent, photo: Data?) {
        id = meal.id
        date = meal.date
        kindRaw = meal.kind.rawValue
        name = meal.name
        carbsGrams = meal.carbsGrams
        note = meal.note
        self.photo = photo
    }

    public var meal: MealEvent {
        MealEvent(id: id, date: date, kind: MealKind(rawValue: kindRaw) ?? .snack, name: name, carbsGrams: carbsGrams, note: note)
    }
}

/// Local store: a mirror of Apple Health glucose plus the app's own meal
/// records. Never synced through CloudKit (App Store Guideline 5.1.3).
@MainActor
public final class GlucoseRepository {
    public let container: ModelContainer
    private let defaults: UserDefaults
    private var context: ModelContext { container.mainContext }

    public init(inMemory: Bool = false, defaults: UserDefaults = .standard) throws {
        let schema = Schema([StoredReading.self, StoredMeal.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
        container = try ModelContainer(for: schema, configurations: [configuration])
        self.defaults = defaults
    }

    /// HealthKit anchor for the next incremental sync.
    public var healthAnchor: Data? {
        get { defaults.data(forKey: "healthAnchor.glucose") }
        set { defaults.set(newValue, forKey: "healthAnchor.glucose") }
    }

    // MARK: Readings

    public func readings(from start: Date, to end: Date) throws -> [GlucoseSample] {
        let descriptor = FetchDescriptor<StoredReading>(
            predicate: #Predicate { $0.date >= start && $0.date <= end },
            sortBy: [SortDescriptor(\.date)]
        )
        return try context.fetch(descriptor).map(\.sample)
    }

    public func upsert(_ samples: [GlucoseSample]) throws {
        guard let first = samples.map(\.date).min(), let last = samples.map(\.date).max() else { return }
        let descriptor = FetchDescriptor<StoredReading>(predicate: #Predicate { $0.date >= first && $0.date <= last })
        var existing = Dictionary(uniqueKeysWithValues: try context.fetch(descriptor).map { ($0.id, $0) })
        for sample in samples {
            if let stored = existing[sample.id] {
                stored.update(from: sample)
            } else {
                // Editing a manual entry can move its time outside the fetched
                // range, so look it up by ID. Imported readings never move.
                let id = sample.id
                if sample.source == .manual,
                   let moved = try context.fetch(FetchDescriptor<StoredReading>(predicate: #Predicate { $0.id == id })).first {
                    moved.update(from: sample)
                } else {
                    let stored = StoredReading(sample)
                    context.insert(stored)
                    existing[sample.id] = stored
                }
            }
        }
        try context.save()
    }

    public func deleteReadings(ids: [UUID]) throws {
        guard !ids.isEmpty else { return }
        try context.delete(model: StoredReading.self, where: #Predicate { ids.contains($0.id) })
        try context.save()
    }

    // MARK: Meals

    public func meals(from start: Date, to end: Date) throws -> [MealEvent] {
        let descriptor = FetchDescriptor<StoredMeal>(
            predicate: #Predicate { $0.date >= start && $0.date <= end },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return try context.fetch(descriptor).map(\.meal)
    }

    public func save(meal: MealEvent, photo: Data?) throws {
        let id = meal.id
        if let stored = try context.fetch(FetchDescriptor<StoredMeal>(predicate: #Predicate { $0.id == id })).first {
            stored.date = meal.date
            stored.kindRaw = meal.kind.rawValue
            stored.name = meal.name
            stored.carbsGrams = meal.carbsGrams
            stored.note = meal.note
            if let photo { stored.photo = photo }
        } else {
            context.insert(StoredMeal(meal, photo: photo))
        }
        try context.save()
    }

    public func deleteMeal(id: UUID) throws {
        try context.delete(model: StoredMeal.self, where: #Predicate { $0.id == id })
        try context.save()
    }

    public func photo(forMeal id: UUID) -> Data? {
        try? context.fetch(FetchDescriptor<StoredMeal>(predicate: #Predicate { $0.id == id })).first?.photo
    }
}
#endif
