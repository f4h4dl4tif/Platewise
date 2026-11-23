import SwiftUI

/// Week grid: days × meal slots. Drag recipes in from the drawer, or use + in any cell.
struct PlannerView: View {
    @EnvironmentObject var store: Store
    @State private var weekStart = Days.weekStart(for: Date())
    @State private var open: Recipe?
    @State private var drawerSearch = ""
    @State private var toast: String?
    @State private var confirmClear = false
    @Environment(\.glassOn) private var glassOn

    private var days: [Date] { Days.week(from: weekStart) }

    var body: some View {
        Group {
            if glassOn {
                VStack(spacing: 0) {
                    toolbar
                        .glassPanel(true, in: RoundedRectangle(cornerRadius: 18))
                        .padding([.horizontal, .top], 14)
                    HStack(spacing: 0) {
                        ScrollView([.vertical, .horizontal]) { grid.padding(16) }
                        drawer
                            .glassPanel(true, in: RoundedRectangle(cornerRadius: 18))
                            .frame(width: 240)
                            .padding([.trailing, .vertical], 14)
                    }
                }
            } else {
                VStack(spacing: 0) {
                    toolbar
                    Divider()
                    HStack(spacing: 0) {
                        ScrollView([.vertical, .horizontal]) { grid.padding(16) }
                        Divider()
                        drawer.frame(width: 240)
                    }
                }
            }
        }
        .sheet(item: $open) { r in
            VStack(spacing: 0) {
                HStack { Spacer(); Button("Done") { open = nil }.keyboardShortcut(.cancelAction) }.padding(12)
                RecipeDetailView(recipe: r)
            }
            .frame(width: 900, height: 720)
        }
        .toast($toast)
        .confirmationDialog("Remove every meal from this week?", isPresented: $confirmClear) {
            Button("Clear Week", role: .destructive) { store.clearWeek(weekStart) }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button { shift(-7) } label: { Image(systemName: "chevron.left") }.glassButtons(glassOn)
            Button { shift(7) } label: { Image(systemName: "chevron.right") }.glassButtons(glassOn)
            Text(rangeTitle).font(.title2.bold())
            if !Days.calendar.isDate(weekStart, inSameDayAs: Days.weekStart(for: Date())) {
                Button("This Week") { weekStart = Days.weekStart(for: Date()) }.glassButtons(glassOn)
            }
            Spacer()
            Button(role: .destructive) { confirmClear = true } label: { Label("Clear Week", systemImage: "trash") }
                .glassButtons(glassOn)
            Button {
                let n = store.buildGrocery(week: weekStart)
                toast = n == 0 ? "No meals planned this week yet" : "Grocery list built from this week's meals"
                if n > 0 { store.section = .grocery }
            } label: { Label("Build Grocery List", systemImage: "cart") }
                .buttonStyle(.borderedProminent)
                .glassButtons(glassOn, prominent: true)
        }
        .controlSize(.large)
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var rangeTitle: String {
        guard let last = days.last else { return "" }
        return "\(weekStart.formatted(.dateTime.month(.abbreviated).day())) – \(last.formatted(.dateTime.month(.abbreviated).day().year()))"
    }

    private func shift(_ d: Int) {
        weekStart = Days.calendar.date(byAdding: .day, value: d, to: weekStart) ?? weekStart
    }

    private var grid: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                Color.clear.frame(width: 90, height: 1)
                ForEach(days, id: \.self) { day in
                    let today = Days.calendar.isDateInToday(day)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(day.formatted(.dateTime.weekday(.abbreviated))).font(.caption.bold()).foregroundStyle(today ? Theme.accent : .secondary)
                        Text(day.formatted(.dateTime.day())).font(.title2.bold()).foregroundStyle(today ? Theme.accent : .primary)
                        let kcal = store.calories(on: day)
                        Text(kcal > 0 ? "~\(kcal) kcal" : " ").font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(minWidth: 128, maxWidth: .infinity, alignment: .leading)
                }
            }
            ForEach(MealSlot.allCases) { slot in
                GridRow {
                    Label(slot.rawValue, systemImage: slot.symbol).font(.callout.bold()).foregroundStyle(.secondary)
                        .frame(width: 90, alignment: .leading).padding(.top, 8)
                    ForEach(days, id: \.self) { day in
                        PlanCell(day: day, slot: slot, open: $open)
                    }
                }
            }
        }
    }

    private var drawer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recipes").font(.headline)
            Text("Drag onto a day").font(.caption).foregroundStyle(.secondary)
            TextField("Search", text: $drawerSearch).textFieldStyle(.roundedBorder)
            List {
                ForEach(drawerRecipes) { r in
                    HStack {
                        Image(systemName: r.favorite ? "heart.fill" : "fork.knife").foregroundStyle(r.favorite ? .pink : Theme.accent)
                        VStack(alignment: .leading) {
                            Text(r.name).lineLimit(1)
                            Text("\(r.totalMinutes) min · \(r.nutrition.calories) kcal").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .draggable(r.id.uuidString)
                    .onTapGesture(count: 2) { open = r }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(glassOn ? .hidden : .automatic)
            Button { store.section = .snap } label: { Label("Snap a new dish", systemImage: "camera.viewfinder") }
                .buttonStyle(.borderless)
        }
        .padding(12)
    }

    private var drawerRecipes: [Recipe] {
        let list = store.recipes.sorted { ($0.favorite ? 0 : 1, $0.name) < ($1.favorite ? 0 : 1, $1.name) }
        guard !drawerSearch.isEmpty else { return list }
        return list.filter { $0.name.localizedCaseInsensitiveContains(drawerSearch) || $0.cuisine.localizedCaseInsensitiveContains(drawerSearch) }
    }
}

private struct PlanCell: View {
    @EnvironmentObject var store: Store
    let day: Date
    let slot: MealSlot
    @Binding var open: Recipe?
    @State private var targeted = false
    @Environment(\.glassOn) private var glassOn

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(store.entries(day: day, slot: slot)) { e in
                if let r = store.recipe(e.recipeID) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.name).font(.callout.weight(.semibold)).lineLimit(2)
                        Text("\(e.servings) serving\(e.servings == 1 ? "" : "s")").font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                    .onTapGesture { open = r }
                    .contextMenu {
                        Button("Open Recipe") { open = r }
                        Button("More Servings") { store.setServings(e, e.servings + 1) }
                        Button("Fewer Servings") { store.setServings(e, e.servings - 1) }
                        Divider()
                        Button("Remove", role: .destructive) { store.removeFromPlan(e) }
                    }
                    .help("\(r.name). Right-click for options")
                }
            }
            Menu {
                if store.recipes.isEmpty { Text("No recipes yet") }
                ForEach(store.recipes.sorted { $0.name < $1.name }) { r in
                    Button(r.name) { store.addToPlan(r, day: day, slot: slot) }
                }
            } label: {
                Image(systemName: "plus").frame(maxWidth: .infinity)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .foregroundStyle(.secondary)
            .opacity(0.7)
        }
        .padding(6)
        .frame(minWidth: 128, maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .modifier(CellSurface(targeted: targeted, glassOn: glassOn))
        .dropDestination(for: String.self) { ids, _ in
            var added = false
            for id in ids {
                if let uuid = UUID(uuidString: id), let r = store.recipe(uuid) { store.addToPlan(r, day: day, slot: slot); added = true }
            }
            return added
        } isTargeted: { targeted = $0 }
    }
}

/// A plan cell's background: the solid card, or glass when the Liquid Glass theme is on.
private struct CellSurface: ViewModifier {
    let targeted: Bool
    let glassOn: Bool

    func body(content: Content) -> some View {
        if glassOn {
            content
                .glassPanel(true, in: RoundedRectangle(cornerRadius: 12), tint: targeted ? Theme.accent.opacity(0.35) : nil)
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.accent, lineWidth: targeted ? 2 : 0))
        } else {
            content
                .background(targeted ? Theme.accent.opacity(0.12) : Theme.card, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(targeted ? Theme.accent : Theme.subtle, lineWidth: targeted ? 2 : 1))
        }
    }
}
