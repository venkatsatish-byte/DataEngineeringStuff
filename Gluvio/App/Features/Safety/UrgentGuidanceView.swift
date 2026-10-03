import GlucoseCore
import SwiftUI

/// Shown over everything when a new reading is beyond the urgent thresholds.
/// It points to the user's care plan and to help; it never suggests a dose.
struct UrgentGuidanceView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var alert: UrgentAlert

    private var tint: Color { alert.kind == .low ? GlucoseBand.urgentLow.color : GlucoseBand.urgentHigh.color }

    var body: some View {
        let unit = model.profile.unit
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.white)
                Text(alert.title)
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                Text("\(unit.formatWithUnit(alert.mgdL)) at \(Format.time(alert.readingDate))")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(alert.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.headline)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(.white))
                                .foregroundStyle(tint)
                            Text(step).font(.body).foregroundStyle(.white)
                        }
                    }
                }

                VStack(spacing: 12) {
                    if !model.profile.careContactPhone.isEmpty, let url = phoneURL(model.profile.careContactPhone) {
                        Link(destination: url) {
                            Label("Call \(model.profile.careContactName.isEmpty ? "my care contact" : model.profile.careContactName)",
                                  systemImage: "phone.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)
                    }
                    if let url = phoneURL(Self.emergencyNumber) {
                        Link(destination: url) {
                            Label("Call emergency services (\(Self.emergencyNumber))", systemImage: "staroflife.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.white)
                        .foregroundStyle(tint)
                    }
                    Button {
                        model.urgentAlert = nil
                        dismiss()
                    } label: {
                        Text("I'm following my care plan").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                }
                .controlSize(.large)
                .padding(.top, 8)

                Text("This screen doesn't replace your care plan or medical advice.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(24)
        }
        .background(tint.gradient)
        .interactiveDismissDisabled()
    }

    private func phoneURL(_ number: String) -> URL? {
        URL(string: "tel:" + number.filter { $0.isNumber || $0 == "+" })
    }

    /// The local emergency number for the device's region.
    static var emergencyNumber: String {
        switch Locale.current.region?.identifier {
        case "US", "CA", "MX", "PR": return "911"
        case "GB", "IE": return "999"
        case "AU": return "000"
        case "NZ": return "111"
        case "IN": return "112"
        default: return "112"
        }
    }
}
