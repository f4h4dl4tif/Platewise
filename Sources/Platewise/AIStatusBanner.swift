import SwiftUI

/// Shows whether Apple Intelligence is ready, and how to fix it when it isn't.
struct AIStatusBanner: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var scan: ScanModel
    @State private var dish = ""

    var body: some View {
        switch store.aiStatus {
        case .checking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking Apple Intelligence…").font(.callout).foregroundStyle(.secondary)
            }
        case .ready:
            Chip(text: "Apple Intelligence · runs on this Mac", symbol: "apple.intelligence")
        case .textOnly:
            Card(readable: true) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Photo scanning isn't available", systemImage: "eye.slash").font(.headline)
                    Text("This Mac's Apple Intelligence can write recipes but can't look at photos yet. Type the dish instead.")
                        .font(.callout).foregroundStyle(.secondary)
                    HStack {
                        TextField("e.g. Chicken Karahi", text: $dish).textFieldStyle(.roundedBorder).onSubmit(go)
                        Button("Get Recipe", action: go).disabled(dish.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        case .unavailable(let reason):
            Card(readable: true) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Apple Intelligence is needed", systemImage: "apple.intelligence").font(.headline)
                    Text(reason).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Open Apple Intelligence Settings") { AIStatusBanner.openSettings() }
                        Button("Check Again") { store.refreshAI() }
                    }
                }
            }
        }
    }

    private func go() {
        let name = dish.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        scan.choose(name, cuisine: "", store: store)
        dish = ""
    }

    static func openSettings() {
        let urls = ["x-apple.systempreferences:com.apple.Siri-Settings.extension", "x-apple.systempreferences:"]
        for s in urls { if let u = URL(string: s), NSWorkspace.shared.open(u) { return } }
    }
}
