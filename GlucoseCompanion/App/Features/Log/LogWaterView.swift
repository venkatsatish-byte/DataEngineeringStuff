import SwiftUI

struct LogWaterView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private struct Option: Identifiable {
        var title: String
        var milliliters: Double
        var systemImage: String
        var id: Double { milliliters }
    }

    private let options = [
        Option(title: "Glass · 250 ml", milliliters: 250, systemImage: "cup.and.saucer"),
        Option(title: "Bottle · 500 ml", milliliters: 500, systemImage: "waterbottle"),
        Option(title: "Large bottle · 750 ml", milliliters: 750, systemImage: "waterbottle.fill"),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(options) { option in
                        Button {
                            Task {
                                await model.logWater(milliliters: option.milliliters)
                                dismiss()
                            }
                        } label: {
                            Label(option.title, systemImage: option.systemImage)
                        }
                    }
                } footer: {
                    Text("Saved to Apple Health.")
                }
            }
            .navigationTitle("Log water")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
    }
}
