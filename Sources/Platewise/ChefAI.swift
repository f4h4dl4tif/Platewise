import AppKit

// MARK: - Answer shapes (the helper returns snake_case JSON; the decoder maps it to camelCase)

struct DishCandidate: Decodable, Hashable, Identifiable {
    var id: String { name }
    var name: String
    var cuisine: String
    var confidence: Int
    var reason: String
}

struct IdentifyResult: Decodable, Equatable {
    var photoDescription: String?
    var isFood: Bool
    var candidates: [DishCandidate]
    var visibleIngredients: [String]
    var note: String
}

private struct RecipeDTO: Decodable {
    struct Ing: Decodable { var name: String; var quantity: Double; var unit: String; var note: String; var aisle: String }
    struct Nut: Decodable { var calories: Int; var proteinG: Int; var carbsG: Int; var fatG: Int }
    var name: String
    var cuisine: String
    var summary: String
    var servings: Int
    var prepMinutes: Int
    var cookMinutes: Int
    var difficulty: String
    var ingredients: [Ing]
    var steps: [String]
    var nutritionPerServing: Nut
    var tags: [String]
    var dietaryFlags: [String]
    var allergyWarnings: [String]
    var tips: [String]
    var youtubeSearchQuery: String

    func recipe(source: String) -> Recipe {
        Recipe(
            name: name, cuisine: cuisine, summary: summary, servings: max(servings, 1),
            prepMinutes: max(prepMinutes, 0), cookMinutes: max(cookMinutes, 0), difficulty: difficulty,
            ingredients: ingredients.map {
                Ingredient(name: $0.name, quantity: max($0.quantity, 0), unit: $0.unit, note: $0.note,
                           aisle: Aisle(rawValue: $0.aisle) ?? Aisle.guess($0.name))
            },
            steps: steps,
            nutrition: Nutrition(calories: nutritionPerServing.calories, protein: nutritionPerServing.proteinG,
                                 carbs: nutritionPerServing.carbsG, fat: nutritionPerServing.fatG),
            tags: tags, dietaryFlags: dietaryFlags, allergyWarnings: allergyWarnings, tips: tips,
            videoQuery: youtubeSearchQuery, source: source)
    }
}

// MARK: - Prompts (the schemas live in the helper)

enum ChefAI {
    static func identify(image: NSImage, hint: String) async throws -> IdentifyResult {
        guard let jpeg = ImageTools.jpegData(image, maxDimension: 1024, quality: 0.85) else {
            throw AppError("Couldn't read that image. Try a JPEG or PNG photo.")
        }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("platewise-scan-\(UUID().uuidString).jpg")
        try jpeg.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        var prompt = "Identify the dish in this photo."
        let h = hint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !h.isEmpty { prompt += " Context from the user: \(h)" }
        var result = try await AppleAI.identify(imagePath: file.path, prompt: prompt)

        // The small model's confidences don't always add up; scale them to a total of at most 100.
        result.candidates = result.candidates.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        let total = result.candidates.map { max($0.confidence, 0) }.reduce(0, +)
        if total > 100 {
            for i in result.candidates.indices {
                result.candidates[i].confidence = Int((Double(max(result.candidates[i].confidence, 0)) * 100 / Double(total)).rounded())
            }
        }
        if !result.isFood { result.candidates = [] }
        if result.note.isEmpty, !result.isFood, let d = result.photoDescription { result.note = "This looks like: \(d)" }
        return result
    }

    static func recipe(dish: String, cuisine: String, visibleIngredients: [String], prefs: Preferences) async throws -> Recipe {
        var request = "Write a complete, reliable home-cook recipe for: \(dish)"
        if !cuisine.isEmpty { request += " (\(cuisine))" }
        request += "."
        if !visibleIngredients.isEmpty {
            request += "\nIngredients seen in the user's photo: \(visibleIngredients.joined(separator: ", "))."
        }
        request += "\n" + profile(prefs)
        return try await generate(request, prefs: prefs)
    }

    static func variant(of r: Recipe, change: String, prefs: Preferences) async throws -> Recipe {
        let request = """
        Rewrite this recipe to make it \(change). Keep the spirit of the dish, rename it if the change warrants \
        (e.g. "Vegetarian Biryani"), and explain the key swaps in tips.
        Dish: \(r.name) (\(r.cuisine)), serves \(r.servings).
        Ingredients: \(r.ingredients.map { $0.display() }.joined(separator: "; ")).
        Steps: \(r.steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: " "))
        \(profile(prefs))
        """
        var v = try await generate(request, prefs: prefs)
        v.photoFile = r.photoFile
        return v
    }

    private static func profile(_ prefs: Preferences) -> String {
        var lines = ["Write it for \(prefs.householdSize) serving\(prefs.householdSize == 1 ? "" : "s")."]
        if !prefs.diets.isEmpty { lines.append("The user's diet preferences: \(prefs.diets.joined(separator: ", ")).") }
        if !prefs.allAllergies.isEmpty { lines.append("The user's allergies: \(prefs.allAllergies.joined(separator: ", ")).") }
        if !prefs.dislikes.isEmpty { lines.append("The user dislikes: \(prefs.dislikes).") }
        return lines.joined(separator: " ")
    }

    private static func generate(_ request: String, prefs: Preferences) async throws -> Recipe {
        let dto: RecipeDTO = try AppleAI.decode(try await AppleAI.recipe(prompt: request))
        return tidy(dto.recipe(source: "Snap & Cook"), prefs: prefs)
    }

    /// The on-device model is small, so check its work against the ingredient list.
    static func tidy(_ recipe: Recipe, prefs: Preferences) -> Recipe {
        var r = recipe
        // "Chicken Karahi (Pakistani)" → "Chicken Karahi"
        if !r.cuisine.isEmpty, r.name.hasSuffix("(\(r.cuisine))") {
            r.name = r.name.dropLast(r.cuisine.count + 2).trimmingCharacters(in: .whitespaces)
        }
        // "5 leaves basil leaves" → "5 basil leaves"
        for i in r.ingredients.indices {
            let unit = r.ingredients[i].unit.lowercased().trimmingCharacters(in: .whitespaces)
            if !unit.isEmpty, r.ingredients[i].name.lowercased().contains(unit) { r.ingredients[i].unit = "" }
        }
        // The app numbers steps itself: drop "1. " / "Step 1:" prefixes.
        r.steps = r.steps.map { step in
            step.replacingOccurrences(of: #"^\s*(step\s*)?\d+\s*[.):-]\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
        }.filter { !$0.isEmpty }

        // Remove diet labels the ingredients contradict (e.g. "Dairy-free" on a mozzarella pizza).
        let names = r.ingredients.map { $0.name.lowercased() }
        func has(_ allergy: String) -> Bool {
            let words = Preferences.allergyKeywords[allergy] ?? []
            let exceptions = Preferences.allergyExceptions[allergy] ?? []
            return names.contains { n in words.contains { n.contains($0) } && !exceptions.contains { n.contains($0) } }
        }
        let meat = ["chicken", "beef", "lamb", "mutton", "pork", "bacon", "turkey", "goat", "mince", "sausage", "ham"]
        let hasMeat = names.contains { n in meat.contains { n.contains($0) } }
        let hasFish = has("Fish") || has("Shellfish")
        let animal = has("Milk") || has("Eggs") || names.contains { $0.contains("honey") }
        r.dietaryFlags = r.dietaryFlags.filter { flag in
            switch flag.lowercased() {
            case "dairy-free": return !has("Milk")
            case "gluten-free": return !has("Wheat/Gluten")
            case "nut-free": return !has("Peanuts") && !has("Tree nuts")
            case "egg-free": return !has("Eggs")
            case "vegetarian": return !hasMeat && !hasFish
            case "vegan": return !hasMeat && !hasFish && !animal
            case "pescatarian": return !hasMeat
            default: return true
            }
        }
        // Allergy warnings only make sense when the user has set allergies or diets.
        if prefs.allAllergies.isEmpty && prefs.diets.isEmpty { r.allergyWarnings = [] }
        return r
    }
}
