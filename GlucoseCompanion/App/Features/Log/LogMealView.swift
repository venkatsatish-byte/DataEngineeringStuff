import GlucoseCore
import PhotosUI
import SwiftUI

struct LogMealView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var kind = MealKind.suggested(for: .now)
    @State private var name = ""
    @State private var carbs: Double = 45
    @State private var date = Date.now
    @State private var note = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Meal", selection: $kind) {
                        ForEach(MealKind.allCases) { Label($0.title, systemImage: $0.systemImage).tag($0) }
                    }
                    TextField("What did you eat? (optional)", text: $name)
                    DatePicker("Time", selection: $date, in: ...Date.now)
                }

                Section {
                    Stepper(value: $carbs, in: 0...300, step: 5) {
                        HStack {
                            Text("Carbohydrates")
                            Spacer()
                            Text("\(Int(carbs)) g").monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(GuideContent.carbReferences) { food in
                                Button("\(food.name) +\(food.grams)g") { carbs = min(300, carbs + Double(food.grams)) }
                                    .buttonStyle(.bordered)
                                    .font(.caption)
                            }
                        }
                    }
                    Button("Reset to 0 g") { carbs = 0 }.font(.footnote)
                } header: {
                    Text("Carbs")
                } footer: {
                    Text("Tap common foods to add approximate carbs, then adjust. Food labels give the most accurate numbers.")
                }

                Section {
                    NavigationLink("How to build a balanced plate") { PlateMethodView() }
                }

                Section("Photo and notes") {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label(photoData == nil ? "Add photo" : "Change photo", systemImage: "camera")
                    }
                    if let photoData, let image = UIImage(data: photoData) {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 160).clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    TextField("Notes (optional)", text: $note, axis: .vertical)
                }
            }
            .navigationTitle("Log meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(isSaving)
                }
            }
            .onChange(of: photoItem) { _, item in
                Task { photoData = try? await item?.loadTransferable(type: Data.self) }
            }
            .onChange(of: date) { _, newDate in kind = MealKind.suggested(for: newDate) }
        }
    }

    private func save() {
        isSaving = true
        let meal = MealEvent(date: date, kind: kind, name: name.trimmingCharacters(in: .whitespaces), carbsGrams: carbs, note: note)
        Task {
            let saved = await model.logMeal(meal, photo: photoData)
            isSaving = false
            if saved { dismiss() }
        }
    }
}
