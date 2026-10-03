import Foundation

/// Where a reading falls against the user's targets.
public enum GlucoseBand: Int, Comparable, CaseIterable, Codable, Sendable {
    case urgentLow, low, inRange, high, urgentHigh

    public static func < (lhs: GlucoseBand, rhs: GlucoseBand) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var title: String {
        switch self {
        case .urgentLow: return "Very low"
        case .low: return "Low"
        case .inRange: return "In range"
        case .high: return "High"
        case .urgentHigh: return "Very high"
        }
    }

    public var isUrgent: Bool { self == .urgentLow || self == .urgentHigh }
}

/// The user's personal glucose targets, in mg/dL.
///
/// Defaults follow the international consensus on time in range
/// (Battelino et al., Diabetes Care 2019): target 70–180 mg/dL, level 2
/// low below 54 mg/dL and level 2 high above 250 mg/dL.
public struct TargetRange: Codable, Equatable, Sendable {
    public var low: Double
    public var high: Double
    public var urgentLow: Double
    public var urgentHigh: Double

    public init(low: Double = 70, high: Double = 180, urgentLow: Double = 54, urgentHigh: Double = 250) {
        self.low = low
        self.high = high
        self.urgentLow = urgentLow
        self.urgentHigh = urgentHigh
    }

    public static let standard = TargetRange()

    /// Thresholds must be strictly ordered: urgent low < low < high < urgent high.
    public var isValid: Bool {
        urgentLow < low && low < high && high < urgentHigh
    }

    public func band(for mgdL: Double) -> GlucoseBand {
        if mgdL < urgentLow { return .urgentLow }
        if mgdL < low { return .low }
        if mgdL <= high { return .inRange }
        if mgdL <= urgentHigh { return .high }
        return .urgentHigh
    }

    public func contains(_ mgdL: Double) -> Bool {
        band(for: mgdL) == .inRange
    }
}
