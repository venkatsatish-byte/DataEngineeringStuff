import GlucoseCore
import SwiftUI

// Compiled into the iPhone app, the Watch app and both widget extensions.
extension GlucoseBand {
    /// Colors follow the usual ambulatory glucose profile convention.
    var color: Color {
        switch self {
        case .urgentLow: return Color(red: 0.70, green: 0.07, blue: 0.13)
        case .low: return Color(red: 0.90, green: 0.22, blue: 0.21)
        case .inRange: return Color(red: 0.20, green: 0.66, blue: 0.33)
        case .high: return Color(red: 0.96, green: 0.70, blue: 0.10)
        case .urgentHigh: return Color(red: 0.93, green: 0.45, blue: 0.10)
        }
    }

    var systemImage: String {
        switch self {
        case .urgentLow, .urgentHigh: return "exclamationmark.triangle.fill"
        case .low: return "arrow.down.circle.fill"
        case .inRange: return "checkmark.circle.fill"
        case .high: return "arrow.up.circle.fill"
        }
    }
}
