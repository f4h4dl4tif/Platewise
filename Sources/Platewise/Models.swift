import Foundation

// MARK: - Aisles & meal slots

enum Aisle: String, Codable, CaseIterable, Identifiable {
    case produce = "Produce"
    case meat = "Meat & Seafood"
    case dairy = "Dairy & Eggs"
    case bakery = "Bakery"
    case pantry = "Pantry"
    case spices = "Spices & Condiments"
    case frozen = "Frozen"
    case beverages = "Beverages"
    case other = "Other"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .produce: return "carrot"
        case .meat: return "fish"
        case .dairy: return "cup.and.saucer"
        case .bakery: return "birthday.cake"
        case .pantry: return "takeoutbag.and.cup.and.straw"
        case .spices: return "leaf"
        case .frozen: return "snowflake"
        case .beverages: return "waterbottle"
        case .other: return "basket"
        }
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Aisle(rawValue: raw) ?? .other
    }

    /// Best-effort aisle for a typed ingredient name.
    static func guess(_ name: String) -> Aisle {
        let n = name.lowercased()
        let table: [(Aisle, [String])] = [
            (.spices, ["salt", "pepper", "cumin", "turmeric", "paprika", "chili powder", "garam masala", "cinnamon", "oregano",
                       "basil, dried", "spice", "masala", "coriander powder", "vinegar", "soy sauce", "ketchup", "mustard", "mayo"]),
            (.meat, ["chicken", "beef", "lamb", "mutton", "pork", "turkey", "fish", "salmon", "tuna", "shrimp", "prawn", "mince", "bacon"]),
            (.dairy, ["milk", "butter", "cheese", "cream", "yogurt", "yoghurt", "egg", "ghee", "paneer", "feta"]),
            (.bakery, ["bread", "bun", "tortilla", "naan", "pita", "roti", "croissant"]),
            (.frozen, ["frozen", "ice cream", "peas, frozen"]),
            (.beverages, ["juice", "coffee", "tea", "soda", "water"]),
            (.produce, ["onion", "garlic", "tomato", "potato", "carrot", "lettuce", "spinach", "cucumber", "lemon", "lime",
                        "ginger", "chili", "pepper, bell", "bell pepper", "cilantro", "coriander", "mint", "parsley", "apple",
                        "banana", "berries", "avocado", "mushroom", "zucchini", "cabbage", "broccoli", "olive", "herb", "scallion"]),
            (.pantry, ["rice", "flour", "sugar", "oil", "pasta", "noodle", "lentil", "daal", "dal", "bean", "chickpea", "oats",
                       "stock", "broth", "honey", "nut", "almond", "can", "tin", "sauce"]),
        ]
        for (aisle, words) in table where words.contains(where: { n.contains($0) }) { return aisle }
        return .other
    }
}

enum MealSlot: String, Codable, CaseIterable, Identifiable {
    case breakfast = "Breakfast", lunch = "Lunch", dinner = "Dinner", snack = "Snack"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .breakfast: return "sunrise"
        case .lunch: return "sun.max"
        case .dinner: return "moon.stars"
        case .snack: return "carrot"
        }
    }
}

// MARK: - Recipe

struct Ingredient: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var quantity: Double = 0      // 0 means "to taste" / unmeasured
    var unit: String = ""
    var note: String = ""
    var aisle: Aisle = .other

    func display(scale: Double = 1) -> String {
        let q = Qty.format(quantity * scale)
        var parts: [String] = []
        if !q.isEmpty { parts.append(q) }
        if !unit.isEmpty { parts.append(Qty.plural(unit, quantity * scale)) }
        parts.append(name)
        var s = parts.joined(separator: " ")
        if quantity == 0 && unit.isEmpty { s += " (to taste)" }
        if !note.isEmpty { s += ", \(note)" }
        return s
    }
}

struct Nutrition: Codable, Hashable {
    var calories = 0, protein = 0, carbs = 0, fat = 0
}

struct VideoLink: Codable, Hashable, Identifiable {
    var id = UUID()
    var title: String
    var channel: String
    var url: String
    var thumbnailURL: String?
    /// True for a "search YouTube" link (used when no YouTube API key is set).
    var isSearch = false
}

struct Recipe: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var cuisine = ""
    var summary = ""
    var servings = 4
    var prepMinutes = 0
    var cookMinutes = 0
    var difficulty = "Easy"
    var ingredients: [Ingredient] = []
    var steps: [String] = []
    var nutrition = Nutrition()
    var tags: [String] = []
    var dietaryFlags: [String] = []
    var allergyWarnings: [String] = []
    var tips: [String] = []
    var videoQuery = ""
    var videos: [VideoLink] = []
    var photoFile: String?
    var favorite = false
    var source = "Manual"
    var createdAt = Date()

    var totalMinutes: Int { prepMinutes + cookMinutes }
    var searchQuery: String { videoQuery.isEmpty ? "\(name) recipe" : videoQuery }
}

// MARK: - Plan, grocery, preferences

struct PlanEntry: Codable, Hashable, Identifiable {
    var id = UUID()
    var day: String          // yyyy-MM-dd
    var slot: MealSlot
    var recipeID: UUID
    var servings: Int
}

struct GroceryItem: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var quantity: Double = 0
    var unit: String = ""
    var aisle: Aisle = .other
    var checked = false
    var fromPlan = false

    var display: String {
        let q = Qty.format(quantity)
        return [q, Qty.plural(unit, quantity), name].filter { !$0.isEmpty }.joined(separator: " ")
    }
    var mergeKey: String { Self.key(name: name, unit: unit) }
    static func key(name: String, unit: String) -> String {
        name.lowercased().trimmingCharacters(in: .whitespaces) + "|" + Qty.normalizeUnit(unit)
    }
}

struct Preferences: Codable, Hashable {
    var diets: [String] = []
    var allergies: [String] = []
    var customAllergies = ""
    var dislikes = ""
    var householdSize = 2

    var allAllergies: [String] {
        allergies + customAllergies.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    static let dietOptions = ["Vegetarian", "Vegan", "Pescatarian", "Halal", "Gluten-free", "Dairy-free", "Keto", "Low-carb", "High-protein"]
    static let allergyOptions = ["Peanuts", "Tree nuts", "Milk", "Eggs", "Fish", "Shellfish", "Soy", "Wheat/Gluten", "Sesame"]
    static let allergyKeywords: [String: [String]] = [
        "Peanuts": ["peanut"],
        "Tree nuts": ["almond", "cashew", "walnut", "pecan", "pistachio", "hazelnut", "macadamia", "pine nut"],
        "Milk": ["milk", "butter", "cheese", "cream", "yogurt", "yoghurt", "ghee", "paneer", "feta", "parmesan",
                 "mozzarella", "ricotta", "cheddar", "halloumi", "labneh", "kefir", "mascarpone", "khoya", "malai", "dahi"],
        "Eggs": ["egg"],
        "Fish": ["salmon", "tuna", "cod", "fish", "anchov", "sardine", "tilapia"],
        "Shellfish": ["shrimp", "prawn", "crab", "lobster", "clam", "mussel", "oyster", "scallop"],
        "Soy": ["soy", "tofu", "edamame", "miso", "tempeh"],
        "Wheat/Gluten": ["flour", "wheat", "bread", "pasta", "noodle", "semolina", "couscous", "barley", "naan", "pita", "tortilla"],
        "Sesame": ["sesame", "tahini"],
    ]

    /// Plant-based look-alikes that contain a keyword but not the allergen ("peanut butter" isn't dairy).
    static let allergyExceptions: [String: [String]] = [
        "Milk": ["peanut butter", "almond butter", "nut butter", "cocoa butter", "coconut milk", "coconut cream",
                 "almond milk", "oat milk", "soy milk", "rice milk", "cashew milk", "vegan"],
        "Eggs": ["eggplant", "eggless"],
    ]

    /// Ingredients in `recipe` that match one of the saved allergies.
    func conflicts(in recipe: Recipe) -> [String] {
        var hits: [String] = []
        for allergy in allAllergies {
            let words = Self.allergyKeywords[allergy] ?? [allergy.lowercased()]
            let exceptions = Self.allergyExceptions[allergy] ?? []
            let matched = recipe.ingredients.filter { ing in
                let n = ing.name.lowercased()
                return words.contains { n.contains($0) } && !exceptions.contains { n.contains($0) }
            }
            if !matched.isEmpty {
                hits.append("\(allergy): " + matched.map(\.name).joined(separator: ", "))
            }
        }
        return hits
    }
}

struct AppData: Codable {
    var recipes: [Recipe] = []
    var plan: [PlanEntry] = []
    var grocery: [GroceryItem] = []
    var prefs = Preferences()
}

// MARK: - Quantities

enum Qty {
    static func format(_ q: Double) -> String {
        guard q > 0.001 else { return "" }
        let whole = floor(q), frac = q - whole
        if frac < 0.04 { return String(Int(whole)) }
        if frac > 0.96 { return String(Int(whole) + 1) }
        let fractions: [(Double, String)] = [(0.125, "⅛"), (0.25, "¼"), (1.0 / 3, "⅓"), (0.5, "½"), (2.0 / 3, "⅔"), (0.75, "¾")]
        if let f = fractions.first(where: { abs($0.0 - frac) < 0.02 }) {
            return whole > 0 ? "\(Int(whole))\(f.1)" : f.1
        }
        var s = String(format: q < 10 ? "%.2f" : "%.1f", q)
        while s.contains(".") && (s.hasSuffix("0") || s.hasSuffix(".")) { s.removeLast() }
        return s
    }

    static let unitAliases: [String: String] = [
        "cup": "cup", "cups": "cup", "c": "cup",
        "tbsp": "tbsp", "tablespoon": "tbsp", "tablespoons": "tbsp", "tbs": "tbsp",
        "tsp": "tsp", "teaspoon": "tsp", "teaspoons": "tsp",
        "g": "g", "gram": "g", "grams": "g", "kg": "kg", "kilogram": "kg", "kilograms": "kg",
        "ml": "ml", "l": "l", "liter": "l", "liters": "l", "litre": "l", "litres": "l",
        "oz": "oz", "ounce": "oz", "ounces": "oz", "lb": "lb", "lbs": "lb", "pound": "lb", "pounds": "lb",
        "clove": "clove", "cloves": "clove", "pinch": "pinch", "can": "can", "cans": "can", "tin": "can",
        "slice": "slice", "slices": "slice", "piece": "piece", "pieces": "piece", "bunch": "bunch",
        "handful": "handful", "sprig": "sprig", "sprigs": "sprig", "stick": "stick", "sticks": "stick",
    ]

    /// "cup" → "cups" when there's more than one; abbreviations (tbsp, g, ml…) stay as they are.
    static func plural(_ unit: String, _ q: Double) -> String {
        guard q > 1.04 else { return unit }
        switch unit.lowercased() {
        case "cup", "clove", "can", "slice", "piece", "stick", "sprig", "handful": return unit + "s"
        case "pinch", "bunch": return unit + "es"
        default: return unit
        }
    }

    static func normalizeUnit(_ unit: String) -> String {
        let u = unit.lowercased().trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return unitAliases[u] ?? u
    }

    static func parseNumber(_ token: String) -> Double? {
        let unicode: [Character: Double] = ["½": 0.5, "¼": 0.25, "¾": 0.75, "⅓": 1.0 / 3, "⅔": 2.0 / 3, "⅛": 0.125]
        if let last = token.last, let f = unicode[last] {
            let head = token.dropLast()
            if head.isEmpty { return f }
            if let w = Double(head) { return w + f }
            return nil
        }
        if token.contains("/") {
            let p = token.split(separator: "/")
            if p.count == 2, let a = Double(p[0]), let b = Double(p[1]), b != 0 { return a / b }
            return nil
        }
        return Double(token)
    }

    /// Parses lines like "1 1/2 cups flour, sifted".
    static func parseIngredient(_ line: String) -> Ingredient? {
        var text = line.trimmingCharacters(in: .whitespaces)
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "-•* "))
        guard !text.isEmpty else { return nil }
        var note = ""
        if let comma = text.firstIndex(of: ",") {
            note = text[text.index(after: comma)...].trimmingCharacters(in: .whitespaces)
            text = String(text[..<comma])
        }
        var tokens = text.split(separator: " ").map(String.init)
        var qty = 0.0
        while let first = tokens.first, let n = parseNumber(first) {
            qty += n; tokens.removeFirst()
        }
        var unit = ""
        if let first = tokens.first, unitAliases[first.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))] != nil, tokens.count > 1 {
            unit = normalizeUnit(first); tokens.removeFirst()
        }
        let name = tokens.joined(separator: " ")
        guard !name.isEmpty else { return nil }
        return Ingredient(name: name, quantity: qty, unit: unit, note: note, aisle: Aisle.guess(name))
    }
}

// MARK: - Dates

enum Days {
    static let keyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2   // weeks start on Monday
        return c
    }()

    static func key(_ date: Date) -> String { keyFormatter.string(from: date) }

    static func weekStart(for date: Date) -> Date {
        let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: comps) ?? calendar.startOfDay(for: date)
    }

    static func week(from start: Date) -> [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }
}
