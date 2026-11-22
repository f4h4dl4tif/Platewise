import Foundation

/// A few starter recipes so the planner isn't empty on first launch.
enum SampleData {
    static var recipes: [Recipe] {
        [
            Recipe(
                name: "Masoor Daal", cuisine: "Pakistani",
                summary: "Comforting red lentils simmered with turmeric and finished with a sizzling garlic-cumin tarka.",
                servings: 4, prepMinutes: 10, cookMinutes: 30, difficulty: "Easy",
                ingredients: [
                    i("red lentils (masoor)", 1, "cup", "rinsed", .pantry),
                    i("water", 4, "cup", "", .other),
                    i("onion", 1, "", "finely chopped", .produce),
                    i("tomatoes", 2, "", "chopped", .produce),
                    i("garlic", 4, "clove", "sliced", .produce),
                    i("ginger", 1, "tsp", "grated", .produce),
                    i("turmeric", 0.5, "tsp", "", .spices),
                    i("red chili powder", 1, "tsp", "", .spices),
                    i("cumin seeds", 1, "tsp", "", .spices),
                    i("ghee or oil", 3, "tbsp", "", .pantry),
                    i("salt", 0, "", "", .spices),
                    i("fresh coriander", 0.25, "cup", "chopped", .produce),
                ],
                steps: [
                    "Boil the lentils in the water with turmeric and salt, skimming off the foam, for 20 minutes until soft.",
                    "In a pan, cook the onion in 2 tbsp ghee until golden. Add ginger, tomato and chili powder and cook until the tomato breaks down.",
                    "Stir the masala into the lentils and simmer 5 minutes. Add water if it's too thick.",
                    "For the tarka, heat the remaining ghee, fry the cumin seeds and garlic until golden, and pour it over the daal.",
                    "Top with coriander and serve with rice or roti.",
                ],
                nutrition: Nutrition(calories: 290, protein: 14, carbs: 38, fat: 10),
                tags: ["Comfort food", "Weeknight"], dietaryFlags: ["Vegetarian", "Gluten-free"],
                videoQuery: "masoor daal recipe", source: "Sample"),
            Recipe(
                name: "Greek Salad", cuisine: "Greek",
                summary: "Crunchy cucumber, ripe tomatoes, olives and feta with a lemony oregano dressing.",
                servings: 2, prepMinutes: 15, cookMinutes: 0, difficulty: "Easy",
                ingredients: [
                    i("tomatoes", 3, "", "cut in wedges", .produce),
                    i("cucumber", 1, "", "sliced", .produce),
                    i("red onion", 0.5, "", "thinly sliced", .produce),
                    i("kalamata olives", 0.33, "cup", "", .pantry),
                    i("feta", 150, "g", "", .dairy),
                    i("olive oil", 3, "tbsp", "", .pantry),
                    i("lemon juice", 1, "tbsp", "", .produce),
                    i("dried oregano", 1, "tsp", "", .spices),
                ],
                steps: [
                    "Combine the tomatoes, cucumber, onion and olives in a bowl.",
                    "Whisk olive oil, lemon juice, oregano and a pinch of salt.",
                    "Pour over the salad, lay the feta on top and finish with more oregano.",
                ],
                nutrition: Nutrition(calories: 340, protein: 10, carbs: 14, fat: 28),
                tags: ["Fresh", "No-cook"], dietaryFlags: ["Vegetarian", "Gluten-free"],
                videoQuery: "greek salad recipe", source: "Sample"),
            Recipe(
                name: "Overnight Oats", cuisine: "International",
                summary: "Creamy make-ahead oats with banana, honey and a crunch of nuts.",
                servings: 1, prepMinutes: 5, cookMinutes: 0, difficulty: "Easy",
                ingredients: [
                    i("rolled oats", 0.5, "cup", "", .pantry),
                    i("milk", 0.5, "cup", "", .dairy),
                    i("yogurt", 0.25, "cup", "", .dairy),
                    i("chia seeds", 1, "tbsp", "", .pantry),
                    i("honey", 1, "tsp", "", .pantry),
                    i("banana", 0.5, "", "sliced", .produce),
                    i("almonds", 1, "tbsp", "chopped", .pantry),
                ],
                steps: [
                    "Stir the oats, milk, yogurt, chia and honey together in a jar.",
                    "Cover and refrigerate overnight (at least 6 hours).",
                    "Top with banana and almonds in the morning.",
                ],
                nutrition: Nutrition(calories: 380, protein: 15, carbs: 55, fat: 11),
                tags: ["Breakfast", "Make-ahead"], dietaryFlags: ["Vegetarian"],
                videoQuery: "overnight oats recipe", source: "Sample"),
        ]
    }

    private static func i(_ name: String, _ q: Double, _ unit: String, _ note: String, _ aisle: Aisle) -> Ingredient {
        Ingredient(name: name, quantity: q, unit: unit, note: note, aisle: aisle)
    }
}
