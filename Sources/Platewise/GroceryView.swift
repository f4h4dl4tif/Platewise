import SwiftUI

struct GroceryView: View {
    @EnvironmentObject var store: Store
    @State private var newItem = ""
    @State private var toast: String?
    @State private var confirmClearAll = false
    @Environment(\.glassOn) private var glassOn

    private var remaining: Int { store.grocery.filter { !$0.checked }.count }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                TextField("Add an item, e.g. “2 lb chicken thighs”", text: $newItem)
                    .textFieldStyle(.roundedBorder).onSubmit(add)
                Button("Add", action: add).disabled(newItem.trimmingCharacters(in: .whitespaces).isEmpty)
                    .glassButtons(glassOn, prominent: true)
                Divider().frame(height: 20)
                Button {
                    let n = store.buildGrocery(week: Days.weekStart(for: Date()))
                    toast = n == 0 ? "No meals planned this week" : "Updated from this week's meal plan"
                } label: { Label("From This Week", systemImage: "calendar") }
                    .glassButtons(glassOn)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(store.groceryText, forType: .string)
                    toast = "List copied. Paste it into Notes or Messages"
                } label: { Label("Copy", systemImage: "doc.on.doc") }
                    .glassButtons(glassOn)
                    .disabled(remaining == 0)
                Menu {
                    Button("Remove Checked Items") { store.grocery.removeAll { $0.checked } }
                    Button("Uncheck All") { for i in store.grocery.indices { store.grocery[i].checked = false } }
                    Divider()
                    Button("Clear Entire List", role: .destructive) { confirmClearAll = true }
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuIndicator(.hidden).fixedSize()
                    .glassMenu(glassOn)
            }
            .controlSize(.large)
            .padding(14)
            .glassPanel(glassOn, in: RoundedRectangle(cornerRadius: 18))
            .padding(glassOn ? 14 : 0)
            if !glassOn { Divider() }

            if store.grocery.isEmpty {
                ContentUnavailableView {
                    Label("Your grocery list is empty", systemImage: "cart")
                } description: {
                    Text("Plan some meals and press Build Grocery List, add a recipe's ingredients from its page, or type items above.")
                } actions: {
                    Button("Go to Meal Plan") { store.section = .plan }
                }
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(Aisle.allCases) { aisle in
                        let items = store.grocery.filter { $0.aisle == aisle }.sorted { ($0.checked ? 1 : 0, $0.name) < ($1.checked ? 1 : 0, $1.name) }
                        if !items.isEmpty {
                            Section {
                                ForEach(items) { item in row(item) }
                            } header: {
                                Label(aisle.rawValue, systemImage: aisle.symbol).font(.headline)
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .clipShape(RoundedRectangle(cornerRadius: glassOn ? 14 : 0))
                .padding(.horizontal, glassOn ? 14 : 0)
                HStack {
                    Text("\(remaining) to buy · \(store.grocery.count - remaining) in the cart").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
            }
        }
        .toast($toast)
        .confirmationDialog("Clear the whole grocery list?", isPresented: $confirmClearAll) {
            Button("Clear List", role: .destructive) { store.grocery.removeAll() }
        }
    }

    private func row(_ item: GroceryItem) -> some View {
        HStack {
            Toggle(isOn: Binding(
                get: { item.checked },
                set: { v in if let i = store.grocery.firstIndex(where: { $0.id == item.id }) { store.grocery[i].checked = v } }
            )) {
                Text(item.display)
                    .strikethrough(item.checked)
                    .foregroundStyle(item.checked ? .secondary : .primary)
            }
            .toggleStyle(.checkbox)
            Spacer()
            if item.fromPlan { Image(systemName: "calendar").font(.caption).foregroundStyle(.tertiary).help("From your meal plan") }
        }
        .padding(.vertical, 2)
        .contextMenu {
            Menu("Move to Aisle") {
                ForEach(Aisle.allCases) { a in
                    Button(a.rawValue) { if let i = store.grocery.firstIndex(where: { $0.id == item.id }) { store.grocery[i].aisle = a } }
                }
            }
            Button("Delete", role: .destructive) { store.grocery.removeAll { $0.id == item.id } }
        }
    }

    private func add() {
        let text = newItem.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        store.addGroceryLine(text)
        newItem = ""
    }
}
