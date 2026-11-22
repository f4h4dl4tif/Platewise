import SwiftUI

struct RecipesView: View {
    @EnvironmentObject var store: Store
    @State private var selection: UUID?
    @State private var search = ""
    @State private var favoritesOnly = false
    @State private var editing: Recipe?

    private var filtered: [Recipe] {
        store.recipes.filter { r in
            (!favoritesOnly || r.favorite) &&
            (search.isEmpty || r.name.localizedCaseInsensitiveContains(search) || r.cuisine.localizedCaseInsensitiveContains(search)
             || r.tags.contains { $0.localizedCaseInsensitiveContains(search) }
             || r.ingredients.contains { $0.name.localizedCaseInsensitiveContains(search) })
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack {
                    TextField("Search recipes or ingredients", text: $search).textFieldStyle(.roundedBorder)
                    Toggle(isOn: $favoritesOnly) { Image(systemName: favoritesOnly ? "heart.fill" : "heart") }
                        .toggleStyle(.button).help("Favorites only")
                }
                List(selection: $selection) {
                    ForEach(filtered) { r in RecipeRow(recipe: r).tag(r.id) }
                }
                .listStyle(.inset)
                .overlay {
                    if filtered.isEmpty {
                        ContentUnavailableView(store.recipes.isEmpty ? "No recipes yet" : "No matches", systemImage: "book.closed")
                    }
                }
                HStack {
                    Button { editing = Recipe(name: "") } label: { Label("New Recipe", systemImage: "plus") }
                    Spacer()
                    Button { store.section = .snap } label: { Label("Snap & Cook", systemImage: "camera.viewfinder") }
                }
                .buttonStyle(.borderless)
            }
            .padding(12)
            .frame(width: 310)
            Divider()
            Group {
                if let r = store.recipe(selection) {
                    RecipeDetailView(recipe: r, onVariant: nil, onEdit: { editing = r },
                                     onDelete: { store.delete(r); selection = nil })
                        .id(r.id)
                } else {
                    ContentUnavailableView("Pick a recipe", systemImage: "fork.knife",
                                           description: Text("Choose a recipe on the left, add one by hand, or snap a photo of a dish."))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(item: $editing) { r in
            RecipeEditorView(recipe: r) { savedRecipe in
                store.upsert(savedRecipe)
                selection = savedRecipe.id
            }
        }
        .onAppear { if selection == nil { selection = store.recipes.first?.id } }
    }
}

private struct RecipeRow: View {
    @EnvironmentObject var store: Store
    let recipe: Recipe

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let img = store.photo(for: recipe) {
                    Image(nsImage: img).resizable().scaledToFill()
                } else {
                    ZStack { Theme.accent.opacity(0.15); Image(systemName: "fork.knife").foregroundStyle(Theme.accent) }
                }
            }
            .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(recipe.name).font(.headline).lineLimit(1)
                Text([recipe.cuisine, recipe.totalMinutes > 0 ? "\(recipe.totalMinutes) min" : ""].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if recipe.favorite { Image(systemName: "heart.fill").foregroundStyle(.pink).font(.caption) }
            if recipe.source == "Snap & Cook" { Image(systemName: "camera.viewfinder").foregroundStyle(.secondary).font(.caption) }
        }
        .padding(.vertical, 3)
    }
}

/// Add or edit a recipe by hand. Ingredients are one per line ("1 1/2 cups flour, sifted").
struct RecipeEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let recipe: Recipe
    let onSave: (Recipe) -> Void

    @State private var name = ""
    @State private var cuisine = ""
    @State private var summary = ""
    @State private var servings = 4
    @State private var prep = 10
    @State private var cook = 20
    @State private var difficulty = "Easy"
    @State private var ingredientsText = ""
    @State private var stepsText = ""
    @State private var tagsText = ""
    @State private var calories = 0

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Recipe") {
                    TextField("Name", text: $name)
                    TextField("Cuisine", text: $cuisine)
                    TextField("Short description", text: $summary, axis: .vertical).lineLimit(1...3)
                    Stepper("Serves \(servings)", value: $servings, in: 1...40)
                    Stepper("Prep \(prep) min", value: $prep, in: 0...600, step: 5)
                    Stepper("Cook \(cook) min", value: $cook, in: 0...900, step: 5)
                    Picker("Difficulty", selection: $difficulty) { ForEach(["Easy", "Medium", "Hard"], id: \.self) { Text($0) } }
                    TextField("Calories per serving", value: $calories, format: .number)
                    TextField("Tags (comma separated)", text: $tagsText)
                }
                Section("Ingredients, one per line") {
                    TextEditor(text: $ingredientsText).font(.body.monospaced()).frame(minHeight: 140)
                }
                Section("Steps, one per line") {
                    TextEditor(text: $stepsText).frame(minHeight: 140)
                }
            }
            .formStyle(.grouped)
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") { save() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(16)
        }
        .frame(width: 560, height: 720)
        .onAppear(perform: load)
    }

    private func load() {
        name = recipe.name; cuisine = recipe.cuisine; summary = recipe.summary
        servings = recipe.servings; prep = recipe.prepMinutes; cook = recipe.cookMinutes
        difficulty = recipe.difficulty; calories = recipe.nutrition.calories
        ingredientsText = recipe.ingredients.map { $0.display() .replacingOccurrences(of: " (to taste)", with: "") }.joined(separator: "\n")
        stepsText = recipe.steps.joined(separator: "\n")
        tagsText = recipe.tags.joined(separator: ", ")
    }

    private func save() {
        var r = recipe
        r.name = name.trimmingCharacters(in: .whitespaces)
        r.cuisine = cuisine; r.summary = summary; r.servings = servings
        r.prepMinutes = prep; r.cookMinutes = cook; r.difficulty = difficulty
        r.nutrition.calories = calories
        let parsed = ingredientsText.split(whereSeparator: \.isNewline).compactMap { Qty.parseIngredient(String($0)) }
        // Keep the AI-assigned aisle for lines that didn't change.
        r.ingredients = parsed.map { p in
            var p = p
            if let old = recipe.ingredients.first(where: { $0.name.lowercased() == p.name.lowercased() }) { p.aisle = old.aisle }
            return p
        }
        r.steps = stepsText.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        r.tags = tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if r.videoQuery.isEmpty || r.name != recipe.name { r.videoQuery = "\(r.name) recipe"; r.videos = [] }
        onSave(r)
        dismiss()
    }
}
