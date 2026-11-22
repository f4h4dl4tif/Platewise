import SwiftUI

@main
struct PlatewiseApp: App {
    @StateObject private var store = Store()
    @StateObject private var scan = ScanModel()

    var body: some Scene {
        WindowGroup("Platewise") {
            ContentView()
                .environmentObject(store)
                .environmentObject(scan)
                .frame(minWidth: 1020, minHeight: 680)
                .tint(Theme.accent)
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Go") {
                ForEach(Array(AppSection.allCases.enumerated()), id: \.element) { i, s in
                    Button(s.rawValue) { store.section = s }
                        .keyboardShortcut(KeyEquivalent(Character(String(i + 1))), modifiers: .command)
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(store)
                .frame(width: 580, height: 660)
                .tint(Theme.accent)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { store.section }, set: { if let s = $0 { store.section = s } })) {
                ForEach(AppSection.allCases) { s in
                    Label(s.rawValue, systemImage: s.symbol)
                        .badge(s == .grocery ? store.grocery.filter { !$0.checked }.count : 0)
                        .tag(s)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            switch store.section {
            case .snap: ScanView()
            case .plan: PlannerView()
            case .recipes: RecipesView()
            case .grocery: GroceryView()
            case .settings: ScrollView { SettingsView().frame(maxWidth: 640) }.frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(store.section.rawValue)
        .task {
            await SelfTest.runIfRequested(store: store)
            await DebugSnapshot.runIfRequested(store: store)
        }
    }
}
