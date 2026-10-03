import Foundation

/// General education content. Reviewed by a clinician before release; never
/// tailored to an individual reading in a way that would amount to treatment.
public enum GuideContent {
    public struct PlateSection: Identifiable, Sendable {
        public var id: String { title }
        public var title: String
        public var share: Double
        public var examples: String
    }

    public struct Swap: Identifiable, Sendable {
        public var id: String { instead }
        public var instead: String
        public var tryThis: String
        public var why: String
    }

    public struct ExerciseIdea: Identifiable, Sendable {
        public var id: String { title }
        public var title: String
        public var detail: String
        public var systemImage: String
    }

    public static let plate: [PlateSection] = [
        PlateSection(title: "Non-starchy vegetables", share: 0.5,
                     examples: "Salad greens, broccoli, peppers, green beans, tomatoes, cauliflower"),
        PlateSection(title: "Protein", share: 0.25,
                     examples: "Chicken, fish, eggs, tofu, beans, lean meat"),
        PlateSection(title: "Carbohydrate foods", share: 0.25,
                     examples: "Whole grains, brown rice, whole-wheat pasta, potatoes, fruit, milk"),
    ]

    public static let plateTip =
        "Use a 9-inch (23 cm) plate. Fill half with non-starchy vegetables, a quarter with protein and a quarter with carbohydrate foods, and choose water or an unsweetened drink."

    public static let swaps: [Swap] = [
        Swap(instead: "White bread", tryThis: "100% whole-grain or seeded bread", why: "More fiber, so sugar enters the blood more slowly."),
        Swap(instead: "White rice", tryThis: "Brown rice, quinoa, or half rice and half cauliflower rice", why: "Fewer fast carbs per serving."),
        Swap(instead: "Sugary cereal", tryThis: "Rolled or steel-cut oats with nuts", why: "Fiber and fat slow the rise after breakfast."),
        Swap(instead: "Fruit juice", tryThis: "A whole piece of fruit", why: "The fiber in whole fruit blunts the spike."),
        Swap(instead: "Regular soda", tryThis: "Sparkling water with lemon or lime", why: "No sugar at all."),
        Swap(instead: "Potato chips", tryThis: "A small handful of unsalted nuts", why: "Very few carbs, and filling."),
        Swap(instead: "Mashed potatoes", tryThis: "Mashed cauliflower, or lentils", why: "Far fewer fast-acting carbs."),
        Swap(instead: "Flavored yogurt", tryThis: "Plain Greek yogurt with berries", why: "Less added sugar and more protein."),
    ]

    public static let exercise: [ExerciseIdea] = [
        ExerciseIdea(title: "Walk after meals", detail: "A 10–15 minute walk starting within 30 minutes of eating can help lower the rise after meals.", systemImage: "figure.walk"),
        ExerciseIdea(title: "Build up to 150 minutes a week", detail: "Brisk walking, cycling or swimming spread over at least 3 days, with no more than 2 days in a row off.", systemImage: "calendar"),
        ExerciseIdea(title: "Strength training", detail: "2–3 sessions a week on non-consecutive days: squats to a chair, wall push-ups, resistance bands.", systemImage: "dumbbell"),
        ExerciseIdea(title: "Break up sitting", detail: "Every 30 minutes, stand up and move for a few minutes.", systemImage: "chair"),
        ExerciseIdea(title: "Balance and flexibility", detail: "Gentle stretching, yoga or tai chi 2–3 times a week.", systemImage: "figure.mind.and.body"),
    ]

    public struct CarbReference: Identifiable, Sendable {
        public var id: String { name }
        public var name: String
        public var grams: Int
    }

    /// Typical carbohydrate content of common servings, rounded. Approximate:
    /// food labels and USDA FoodData Central give exact values.
    public static let carbReferences: [CarbReference] = [
        CarbReference(name: "Slice of bread", grams: 15),
        CarbReference(name: "1 cup rice", grams: 45),
        CarbReference(name: "1 cup pasta", grams: 45),
        CarbReference(name: "Medium potato", grams: 35),
        CarbReference(name: "Tortilla", grams: 15),
        CarbReference(name: "1 cup oatmeal", grams: 27),
        CarbReference(name: "1 cup beans", grams: 40),
        CarbReference(name: "Apple", grams: 25),
        CarbReference(name: "Banana", grams: 27),
        CarbReference(name: "1 cup milk", grams: 12),
    ]

    public static let exerciseCaution =
        "Check with your doctor before starting a new exercise routine. If you take medicines that can cause low blood sugar, ask your care team how to stay safe during exercise."
}

/// Picks the single most useful, general suggestion for right now.
public enum Coaching {
    public static func suggestion(
        now: Date, meals: [MealEvent], activities: [ActivityEvent], today: DailyActivity, profile: UserProfile
    ) -> String {
        if let meal = meals.filter({ $0.date <= now && now.timeIntervalSince($0.date) <= 45 * 60 }).max(by: { $0.date < $1.date }),
           !activities.contains(where: { $0.start >= meal.date }) {
            return "You logged \(meal.displayName.lowercased()) recently. A 10–15 minute walk now can help with the rise after meals."
        }
        let remaining = profile.stepGoal - today.steps
        if remaining > 0 {
            return "\(remaining.formatted()) steps to reach today's goal of \(profile.stepGoal.formatted())."
        }
        return "You reached today's step goal. Nice work."
    }
}
