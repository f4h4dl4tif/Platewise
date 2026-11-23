import SwiftUI

/// Full recipe: scaling, allergy warnings, nutrition, videos and actions (plan, grocery, save, variants).
struct RecipeDetailView: View {
    @EnvironmentObject var store: Store
    let recipe: Recipe
    var photo: NSImage? = nil
    var loadingVideos = false
    var onVariant: ((String) -> Void)? = nil
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    @State private var servings = 0
    @State private var showPlan = false
    @State private var toast: String?
    @State private var fetchingVideos = false
    @State private var confirmDelete = false
    @Environment(\.glassOn) private var glassOn

    private var saved: Recipe? { store.recipe(recipe.id) }
    private var current: Recipe { saved ?? recipe }
    private var image: NSImage? { photo ?? store.photo(for: current) }
    private var scale: Double { Double(max(servings, 1)) / Double(max(current.servings, 1)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                actions
                warnings
                HStack(alignment: .top, spacing: 20) {
                    ingredients.frame(width: 330)
                    steps
                }
                nutrition
                if !current.tips.isEmpty { tips }
                videos
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .leading)
        }
        .onAppear { servings = current.servings }
        .onChange(of: recipe.id) { servings = current.servings }
        .toast($toast)
        .confirmationDialog("Delete “\(current.name)”?", isPresented: $confirmDelete) {
            Button("Delete Recipe", role: .destructive) { onDelete?() }
        } message: { Text("It's also removed from your meal plan. This can't be undone.") }
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
                    .frame(width: 230, height: 170).clipShape(RoundedRectangle(cornerRadius: 14))
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(current.name).font(.largeTitle.bold()).textSelection(.enabled)
                HStack(spacing: 6) {
                    if !current.cuisine.isEmpty { Text(current.cuisine).foregroundStyle(Theme.accent) }
                    Text("·").foregroundStyle(.tertiary)
                    Text(current.source).foregroundStyle(.secondary)
                }
                .font(.headline)
                if !current.summary.isEmpty {
                    Text(current.summary).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                FlowLayout {
                    if current.prepMinutes > 0 { Chip(text: "Prep \(current.prepMinutes) min", symbol: "knife", color: .secondary) }
                    if current.cookMinutes > 0 { Chip(text: "Cook \(current.cookMinutes) min", symbol: "flame", color: .secondary) }
                    Chip(text: current.difficulty, symbol: "chart.bar", color: .secondary)
                    if current.nutrition.calories > 0 {
                        Chip(text: "\(current.nutrition.calories) kcal / serving", symbol: "bolt.heart", color: Theme.warm)
                    }
                    ForEach(current.dietaryFlags, id: \.self) { Chip(text: $0, symbol: "checkmark.seal") }
                    ForEach(current.tags, id: \.self) { Chip(text: $0, color: .indigo) }
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button { showPlan = true } label: { Label("Add to Meal Plan", systemImage: "calendar.badge.plus") }
                .buttonStyle(.borderedProminent)
                .glassButtons(glassOn, prominent: true)
                .popover(isPresented: $showPlan, arrowEdge: .bottom) {
                    AddToPlanPopover(defaultServings: store.prefs.householdSize) { day, slot, n in
                        let r = store.saveRecipe(current, photo: photo)
                        store.addToPlan(r, day: day, slot: slot, servings: n)
                        showPlan = false
                        toast = "Added to \(slot.rawValue.lowercased()) on \(day.formatted(.dateTime.weekday(.wide)))"
                    }
                }
            Button {
                store.addToGrocery(current, servings: max(servings, 1))
                toast = "\(current.ingredients.count) ingredients added to your grocery list"
            } label: { Label("Add to Grocery List", systemImage: "cart.badge.plus") }

            if saved == nil {
                Button {
                    store.saveRecipe(current, photo: photo)
                    toast = "Saved to your recipes"
                } label: { Label("Save Recipe", systemImage: "square.and.arrow.down") }
            } else {
                Button { store.toggleFavorite(current) } label: {
                    Label(current.favorite ? "Favorite" : "Add to Favorites", systemImage: current.favorite ? "heart.fill" : "heart")
                }
            }

            if let onVariant, store.aiStatus.canWrite {
                Menu {
                    ForEach(["healthier", "vegetarian", "vegan", "quicker (under 30 minutes)", "spicier", "kid-friendly", "budget-friendly"], id: \.self) { v in
                        Button(v.prefix(1).uppercased() + v.dropFirst()) { onVariant(v) }
                    }
                } label: { Label("Make it…", systemImage: "wand.and.stars") }
                    .fixedSize()
                    .glassMenu(glassOn)
            }
            Spacer()
            if let onEdit { Button("Edit", systemImage: "pencil", action: onEdit) }
            if onDelete != nil {
                Button(role: .destructive) { confirmDelete = true } label: { Image(systemName: "trash") }.help("Delete recipe")
            }
        }
        .controlSize(.large)
        .glassButtons(glassOn)
    }

    @ViewBuilder private var warnings: some View {
        let local = store.prefs.conflicts(in: current)
        let all = current.allergyWarnings + local.filter { l in !current.allergyWarnings.contains { $0.localizedCaseInsensitiveContains(l.components(separatedBy: ":")[0]) } }
        if !all.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label("Check before cooking", systemImage: "exclamationmark.triangle.fill").font(.headline).foregroundStyle(.orange)
                ForEach(all, id: \.self) { Text("• " + $0).fixedSize(horizontal: false, vertical: true) }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var ingredients: some View {
        Card(readable: true) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Ingredients").font(.title3.bold())
                    Spacer()
                    Stepper(value: $servings, in: 1...40) {
                        Text("\(servings) serving\(servings == 1 ? "" : "s")").monospacedDigit()
                    }
                    .fixedSize()
                }
                ForEach(current.ingredients) { ing in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle().fill(Theme.accent).frame(width: 6, height: 6)
                        Text(ing.display(scale: scale)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    }
                }
            }
        }
    }

    private var steps: some View {
        Card(readable: true) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Method").font(.title3.bold())
                ForEach(Array(current.steps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(i + 1)").font(.callout.bold()).foregroundStyle(.white)
                            .frame(width: 26, height: 26).background(Theme.accent, in: Circle())
                        Text(step).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    }
                }
            }
        }
    }

    private var nutrition: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Nutrition").font(.title3.bold())
                Text("per serving · estimated").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                tile("Calories", "\(current.nutrition.calories)", "kcal", Theme.warm)
                tile("Protein", "\(current.nutrition.protein)", "g", .blue)
                tile("Carbs", "\(current.nutrition.carbs)", "g", .purple)
                tile("Fat", "\(current.nutrition.fat)", "g", .pink)
            }
        }
    }

    private func tile(_ label: String, _ value: String, _ unit: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.title2.bold().monospacedDigit())
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }

    private var tips: some View {
        Card(readable: true) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Tips", systemImage: "lightbulb").font(.title3.bold())
                ForEach(current.tips, id: \.self) { Text("• " + $0).fixedSize(horizontal: false, vertical: true) }
            }
        }
    }

    private var videos: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Cook along on YouTube", systemImage: "play.rectangle.fill").font(.title3.bold())
            if loadingVideos || fetchingVideos {
                HStack { ProgressView().controlSize(.small); Text("Finding videos…").foregroundStyle(.secondary) }
            } else if current.videos.isEmpty {
                Button { fetchVideos() } label: { Label("Find Videos", systemImage: "magnifyingglass") }
                    .glassButtons(glassOn)
            } else {
                ForEach(current.videos) { VideoRow(video: $0) }
                if store.youtubeKey.isEmpty {
                    Text("Tip: add a free YouTube API key in Settings to see the top videos right here.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func fetchVideos() {
        fetchingVideos = true
        Task {
            let found = await YouTube.videos(for: current.searchQuery, apiKey: store.youtubeKey)
            if var r = store.recipe(current.id) { r.videos = found; store.upsert(r) }
            fetchingVideos = false
        }
    }
}

private struct VideoRow: View {
    let video: VideoLink
    @State private var hover = false

    var body: some View {
        Link(destination: URL(string: video.url)!) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.12))
                    if let thumb = video.thumbnailURL, let url = URL(string: thumb) {
                        AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { ProgressView().controlSize(.small) }
                    } else {
                        Image(systemName: video.isSearch ? "magnifyingglass" : "play.fill").font(.title2).foregroundStyle(.red)
                    }
                }
                .frame(width: video.isSearch ? 60 : 160, height: video.isSearch ? 40 : 90)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text(video.title).font(.headline).foregroundStyle(.primary).multilineTextAlignment(.leading).lineLimit(2)
                    Text(video.channel).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right.square").foregroundStyle(.tertiary)
            }
            .padding(10)
            .background(hover ? Theme.subtle : .clear, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(video.url)
    }
}

struct AddToPlanPopover: View {
    let defaultServings: Int
    let onAdd: (Date, MealSlot, Int) -> Void
    @State private var day = Date()
    @State private var slot: MealSlot = .dinner
    @State private var servings = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add to Meal Plan").font(.headline)
            DatePicker("Day", selection: $day, displayedComponents: .date).datePickerStyle(.graphical).labelsHidden()
            Picker("Meal", selection: $slot) {
                ForEach(MealSlot.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            Stepper("Servings: \(servings)", value: $servings, in: 1...40)
            Button { onAdd(day, slot, servings) } label: { Text("Add").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
        }
        .padding(16)
        .frame(width: 300)
        .onAppear { servings = defaultServings }
    }
}
