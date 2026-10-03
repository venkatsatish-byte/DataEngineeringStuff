import Foundation

/// The App Group shared by the app, its widgets and complications. The
/// identifier comes from each target's Info.plist (`GCAppGroupIdentifier`),
/// which the project file fills in from one build setting.
public enum AppGroup {
    public static var identifier: String? {
        Bundle.main.object(forInfoDictionaryKey: "GCAppGroupIdentifier") as? String
    }

    public static var defaults: UserDefaults {
        identifier.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }
}

/// What widgets and complications show. Written by the app after each refresh;
/// widgets never query HealthKit or the database themselves.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public struct Point: Codable, Equatable, Sendable {
        public var date: Date
        public var mgdL: Double
    }

    public var latestMgdL: Double?
    public var latestDate: Date?
    public var latestSource: ReadingSource?
    public var trend: TrendArrow?
    public var todayInRangeFraction: Double?
    public var todayIsContinuous: Bool
    public var unit: GlucoseUnit
    public var targets: TargetRange
    public var recent: [Point]
    public var updatedAt: Date

    public static func make(from samples: [GlucoseSample], profile: UserProfile, now: Date = .now, calendar: Calendar = .current) -> WidgetSnapshot {
        let sorted = samples.filter { $0.date <= now }.sorted { $0.date < $1.date }
        let latest = sorted.last
        let today = DateInterval(start: calendar.startOfDay(for: now), end: now)
        let stats = GlucoseAnalytics.stats(for: sorted, in: today, targets: profile.targets)
        return WidgetSnapshot(
            latestMgdL: latest?.mgdL,
            latestDate: latest?.date,
            latestSource: latest?.source,
            trend: GlucoseAnalytics.trend(from: Array(sorted.suffix(12))),
            todayInRangeFraction: stats.inRangeFraction,
            todayIsContinuous: stats.isContinuous,
            unit: profile.unit,
            targets: profile.targets,
            recent: sorted.filter { now.timeIntervalSince($0.date) <= 3 * 3600 }.map { Point(date: $0.date, mgdL: $0.mgdL) },
            updatedAt: now
        )
    }

    public var latestBand: GlucoseBand? { latestMgdL.map(targets.band(for:)) }

    public func isStale(at date: Date) -> Bool {
        guard let latestDate, latestSource == .cgm else { return false }
        return date.timeIntervalSince(latestDate) > GlucoseAnalytics.staleAfter
    }

    public static let empty = WidgetSnapshot(
        latestMgdL: nil, latestDate: nil, latestSource: nil, trend: nil, todayInRangeFraction: nil,
        todayIsContinuous: false, unit: .mgdL, targets: .standard, recent: [], updatedAt: .distantPast
    )

    /// Shown in the widget gallery.
    public static var placeholder: WidgetSnapshot {
        let now = Date()
        let points = (0..<36).map { i in
            Point(date: now.addingTimeInterval(Double(i - 35) * 300), mgdL: 120 + 25 * sin(Double(i) / 6))
        }
        return WidgetSnapshot(
            latestMgdL: 128, latestDate: now.addingTimeInterval(-180), latestSource: .cgm, trend: .flat,
            todayInRangeFraction: 0.82, todayIsContinuous: true, unit: .mgdL, targets: .standard,
            recent: points, updatedAt: now
        )
    }
}

/// Small JSON documents kept in the App Group's UserDefaults.
public struct SharedStore: @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults
    }

    private static let snapshotKey = "widgetSnapshot.v1"
    private static let profileKey = "userProfile.v1"
    private static let remindersKey = "reminders.v1"

    public func loadSnapshot() -> WidgetSnapshot? { load(WidgetSnapshot.self, key: Self.snapshotKey) }
    public func save(_ snapshot: WidgetSnapshot) { save(snapshot, key: Self.snapshotKey) }

    public func loadProfile() -> UserProfile { load(UserProfile.self, key: Self.profileKey) ?? UserProfile() }
    public func save(_ profile: UserProfile) { save(profile, key: Self.profileKey) }

    public func loadReminders() -> [Reminder] { load([Reminder].self, key: Self.remindersKey) ?? Reminder.defaults }
    public func save(_ reminders: [Reminder]) { save(reminders, key: Self.remindersKey) }

    private func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }
}
