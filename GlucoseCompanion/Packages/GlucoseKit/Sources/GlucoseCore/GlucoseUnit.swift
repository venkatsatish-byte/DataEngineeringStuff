import Foundation

/// Display unit for glucose. Values are always stored in mg/dL and converted
/// only for display and entry.
public enum GlucoseUnit: String, Codable, CaseIterable, Identifiable, Sendable {
    case mgdL
    case mmolL

    public var id: String { rawValue }

    /// mg/dL per mmol/L, from glucose's molar mass (180.156 g/mol). HealthKit
    /// uses the same molar mass, so values don't drift between the two.
    public static let mgdLPerMmolL = 18.015588

    public var symbol: String {
        switch self {
        case .mgdL: return "mg/dL"
        case .mmolL: return "mmol/L"
        }
    }

    public func value(fromMgdL mgdL: Double) -> Double {
        self == .mgdL ? mgdL : mgdL / Self.mgdLPerMmolL
    }

    public func mgdL(from value: Double) -> Double {
        self == .mgdL ? value : value * Self.mgdLPerMmolL
    }

    /// "142" for mg/dL, "7.9" for mmol/L.
    public func format(_ mgdL: Double) -> String {
        let value = value(fromMgdL: mgdL)
        switch self {
        case .mgdL: return String(Int(value.rounded()))
        case .mmolL: return String(format: "%.1f", value)
        }
    }

    public func formatWithUnit(_ mgdL: Double) -> String {
        "\(format(mgdL)) \(symbol)"
    }

    /// A signed change, e.g. "+45" or "-1.2".
    public func formatDelta(_ deltaMgdL: Double) -> String {
        let value = value(fromMgdL: deltaMgdL)
        switch self {
        case .mgdL:
            let rounded = Int(value.rounded())
            return rounded > 0 ? "+\(rounded)" : "\(rounded)"
        case .mmolL:
            return String(format: "%+.1f", value)
        }
    }

    /// Step size for steppers and the Digital Crown.
    public var entryStep: Double { self == .mgdL ? 1 : 0.1 }
}
