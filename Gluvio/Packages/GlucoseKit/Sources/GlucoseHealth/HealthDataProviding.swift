import Foundation
import GlucoseCore

/// Glucose samples added and removed in Apple Health since the last sync.
public struct GlucoseChanges: Sendable {
    public var added: [GlucoseSample]
    public var deletedIDs: [UUID]
    /// Opaque anchor to pass to the next call.
    public var anchor: Data?

    public init(added: [GlucoseSample], deletedIDs: [UUID], anchor: Data?) {
        self.added = added
        self.deletedIDs = deletedIDs
        self.anchor = anchor
    }
}

/// Everything the app needs from Apple Health. The live implementation uses
/// HealthKit; the demo implementation serves sample data for previews, tests,
/// screenshots and App Review.
public protocol HealthDataProviding: AnyObject, Sendable {
    var isAvailable: Bool { get }
    func requestAuthorization() async throws
    func glucoseChanges(since anchor: Data?) async throws -> GlucoseChanges
    func glucoseSamples(from start: Date, to end: Date) async throws -> [GlucoseSample]
    func save(_ reading: GlucoseSample) async throws
    func deleteReading(id: UUID) async throws
    func save(meal: MealEvent) async throws
    func saveWater(milliliters: Double, at date: Date) async throws
    func activity(for day: Date) async throws -> DailyActivity
    func activities(from start: Date, to end: Date) async throws -> [ActivityEvent]
    func startObservingGlucose(_ onChange: @escaping @Sendable () -> Void)
}

/// Serves `SampleData`. Writes are kept in memory only.
public final class DemoHealthService: HealthDataProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var dataset: SampleData.Dataset
    private var delivered = false
    private var pending: [GlucoseSample] = []

    public init(dataset: SampleData.Dataset) {
        self.dataset = dataset
    }

    public var isAvailable: Bool { true }

    public var meals: [MealEvent] { lock.withLock { dataset.meals } }

    public func requestAuthorization() async throws {}

    public func glucoseChanges(since anchor: Data?) async throws -> GlucoseChanges {
        lock.withLock {
            let added = delivered ? pending : dataset.samples
            delivered = true
            pending = []
            return GlucoseChanges(added: added, deletedIDs: [], anchor: Data("demo".utf8))
        }
    }

    public func glucoseSamples(from start: Date, to end: Date) async throws -> [GlucoseSample] {
        lock.withLock {
            dataset.samples.filter { $0.date >= start && $0.date <= end }.sorted { $0.date < $1.date }
        }
    }

    public func save(_ reading: GlucoseSample) async throws {
        lock.withLock {
            pending.append(reading)
            dataset.samples.append(reading)
        }
    }

    public func deleteReading(id: UUID) async throws {}

    public func save(meal: MealEvent) async throws {}

    public func saveWater(milliliters: Double, at date: Date) async throws {}

    public func activity(for day: Date) async throws -> DailyActivity {
        lock.withLock { dataset.today }
    }

    public func activities(from start: Date, to end: Date) async throws -> [ActivityEvent] {
        lock.withLock { dataset.activities.filter { $0.start >= start && $0.start <= end } }
    }

    public func startObservingGlucose(_ onChange: @escaping @Sendable () -> Void) {}
}
