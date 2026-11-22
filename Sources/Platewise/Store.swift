import AppKit
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case snap = "Snap & Cook", plan = "Meal Plan", recipes = "Recipes", grocery = "Grocery List", settings = "Settings"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .snap: return "camera.viewfinder"
        case .plan: return "calendar"
        case .recipes: return "book.closed"
        case .grocery: return "cart"
        case .settings: return "gearshape"
        }
    }
}

/// All app data, saved as JSON in ~/Library/Application Support/Platewise.
@MainActor
final class Store: ObservableObject {
    @Published var recipes: [Recipe] = [] { didSet { save() } }
    @Published var plan: [PlanEntry] = [] { didSet { save() } }
    @Published var grocery: [GroceryItem] = [] { didSet { save() } }
    @Published var prefs = Preferences() { didSet { save() } }

    @Published var aiStatus: AIStatus = .checking
    @Published var youtubeKey: String {
        didSet { if youtubeKey != oldValue { keychainError = Keychain.set(youtubeKey, for: "youtube") } }
    }
    @Published var keychainError: String?
    @Published var section: AppSection = .snap

    let folder: URL
    private var photoFolder: URL { folder.appendingPathComponent("Photos", isDirectory: true) }
    private var dataFile: URL { folder.appendingPathComponent("library.json") }
    private var loading = true
    private var photoCache: [String: NSImage] = [:]

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        folder = base.appendingPathComponent("Platewise", isDirectory: true)
        youtubeKey = Keychain.get("youtube") ?? ""
        try? FileManager.default.createDirectory(at: folder.appendingPathComponent("Photos"), withIntermediateDirectories: true)

        if let data = try? Data(contentsOf: dataFile) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let saved = try? decoder.decode(AppData.self, from: data) {
                recipes = saved.recipes; plan = saved.plan; grocery = saved.grocery; prefs = saved.prefs
            } else {
                // Keep a copy of a file we couldn't read instead of overwriting it.
                try? FileManager.default.copyItem(at: dataFile, to: folder.appendingPathComponent("library-unreadable-\(Int(Date().timeIntervalSince1970)).json"))
            }
        } else {
            recipes = SampleData.recipes
        }
        loading = false
        save()
        Keychain.set("", for: "anthropic")   // tidy up a key saved by the earlier Claude-based build
        refreshAI()
    }

    /// Checks whether Apple Intelligence is on and can look at photos.
    func refreshAI() {
        aiStatus = .checking
        Task { aiStatus = await AppleAI.status() }
    }

    private func save() {
        guard !loading else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = AppData(recipes: recipes, plan: plan, grocery: grocery, prefs: prefs)
        if let json = try? encoder.encode(data) { try? json.write(to: dataFile, options: .atomic) }
    }

    // MARK: Recipes

    func recipe(_ id: UUID?) -> Recipe? {
        guard let id else { return nil }
        return recipes.first { $0.id == id }
    }

    func isSaved(_ r: Recipe) -> Bool { recipes.contains { $0.id == r.id } }

    func upsert(_ r: Recipe) {
        if let i = recipes.firstIndex(where: { $0.id == r.id }) { recipes[i] = r } else { recipes.insert(r, at: 0) }
    }

    @discardableResult
    func saveRecipe(_ r: Recipe, photo: NSImage?) -> Recipe {
        if let existing = recipe(r.id) { return existing }
        var r = r
        if r.photoFile == nil, let photo { r.photoFile = savePhoto(photo) }
        upsert(r)
        return r
    }

    func delete(_ r: Recipe) {
        recipes.removeAll { $0.id == r.id }
        plan.removeAll { $0.recipeID == r.id }
        if let file = r.photoFile { try? FileManager.default.removeItem(at: photoFolder.appendingPathComponent(file)) }
    }

    func toggleFavorite(_ r: Recipe) {
        guard var saved = recipe(r.id) else { return }
        saved.favorite.toggle()
        upsert(saved)
    }

    // MARK: Photos

    func savePhoto(_ image: NSImage) -> String? {
        guard let data = ImageTools.jpegData(image, maxDimension: 1600, quality: 0.85) else { return nil }
        let name = UUID().uuidString + ".jpg"
        do { try data.write(to: photoFolder.appendingPathComponent(name)); return name } catch { return nil }
    }

    func photo(for r: Recipe) -> NSImage? {
        guard let file = r.photoFile else { return nil }
        if let cached = photoCache[file] { return cached }
        let img = NSImage(contentsOf: photoFolder.appendingPathComponent(file))
        photoCache[file] = img
        return img
    }

    // MARK: Plan

    func entries(day: Date, slot: MealSlot) -> [PlanEntry] {
        let key = Days.key(day)
        return plan.filter { $0.day == key && $0.slot == slot }
    }

    func addToPlan(_ r: Recipe, day: Date, slot: MealSlot, servings: Int? = nil) {
        plan.append(PlanEntry(day: Days.key(day), slot: slot, recipeID: r.id, servings: servings ?? prefs.householdSize))
    }

    func removeFromPlan(_ e: PlanEntry) { plan.removeAll { $0.id == e.id } }

    func setServings(_ e: PlanEntry, _ n: Int) {
        guard let i = plan.firstIndex(where: { $0.id == e.id }) else { return }
        plan[i].servings = max(1, n)
    }

    func clearWeek(_ start: Date) {
        let keys = Set(Days.week(from: start).map(Days.key))
        plan.removeAll { keys.contains($0.day) }
    }

    func calories(on day: Date) -> Int {
        let key = Days.key(day)
        return plan.filter { $0.day == key }.compactMap { recipe($0.recipeID)?.nutrition.calories }.reduce(0, +)
    }

    // MARK: Grocery

    /// Replaces the list's plan-generated items with the ingredients for every meal in the week.
    /// Items you added yourself are kept.
    @discardableResult
    func buildGrocery(week start: Date) -> Int {
        let keys = Set(Days.week(from: start).map(Days.key))
        var items: [(Ingredient, Double)] = []
        for e in plan where keys.contains(e.day) {
            guard let r = recipe(e.recipeID) else { continue }
            let scale = Double(e.servings) / Double(max(r.servings, 1))
            items += r.ingredients.map { ($0, scale) }
        }
        var list = grocery.filter { !$0.fromPlan }
        merge(items, into: &list, fromPlan: true)
        grocery = list
        return items.count
    }

    func addToGrocery(_ r: Recipe, servings: Int) {
        let scale = Double(servings) / Double(max(r.servings, 1))
        var list = grocery
        merge(r.ingredients.map { ($0, scale) }, into: &list, fromPlan: false)
        grocery = list
    }

    private func merge(_ items: [(Ingredient, Double)], into list: inout [GroceryItem], fromPlan: Bool) {
        for (ing, scale) in items {
            let key = GroceryItem.key(name: ing.name, unit: ing.unit)
            if let i = list.firstIndex(where: { $0.mergeKey == key && !$0.checked }) {
                list[i].quantity += ing.quantity * scale
            } else {
                list.append(GroceryItem(name: ing.name, quantity: ing.quantity * scale, unit: Qty.normalizeUnit(ing.unit),
                                        aisle: ing.aisle, fromPlan: fromPlan))
            }
        }
    }

    func addGroceryLine(_ line: String) {
        guard let ing = Qty.parseIngredient(line) else { return }
        var list = grocery
        merge([(ing, 1)], into: &list, fromPlan: false)
        grocery = list
    }

    var groceryText: String {
        Aisle.allCases.compactMap { aisle -> String? in
            let items = grocery.filter { $0.aisle == aisle && !$0.checked }
            guard !items.isEmpty else { return nil }
            return aisle.rawValue.uppercased() + "\n" + items.map { "☐ " + $0.display }.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }
}
