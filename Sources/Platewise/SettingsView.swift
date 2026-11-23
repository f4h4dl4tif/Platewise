import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @AppStorage(GlassTheme.key) private var glassTheme = false
    @Environment(\.glassOn) private var glassOn
    var body: some View {
        Form {
            Section("Appearance") {
                Toggle(isOn: $glassTheme) {
                    Text("Liquid Glass theme")
                    Text(GlassTheme.supported ? "Floating toolbars, panels and buttons use Apple's Liquid Glass."
                                              : "Requires macOS 26.")
                }
                .disabled(!GlassTheme.supported)
            }

            Section {
                switch store.aiStatus {
                case .checking:
                    HStack { ProgressView().controlSize(.small); Text("Checking…") }
                case .ready:
                    Label("Ready: photo scanning and recipe writing", systemImage: "checkmark.seal.fill").foregroundStyle(Theme.accent)
                case .textOnly:
                    Label("Recipe writing works; photo scanning needs a newer Apple Intelligence", systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                case .unavailable(let reason):
                    Label(reason, systemImage: "xmark.octagon.fill").foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Button("Open Apple Intelligence Settings") { AIStatusBanner.openSettings() }
                    Button("Check Again") { store.refreshAI() }
                }
            } header: {
                Text("Apple Intelligence (powers Snap & Cook)")
            } footer: {
                Text("Dish recognition and recipes run on Apple's on-device model. Photos never leave your Mac, and there's no key or cost. Needs macOS 27 on a Mac with Apple silicon, with Apple Intelligence turned on.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                SecureField("YouTube Data API v3 key", text: $store.youtubeKey)
                keyStatus(has: !store.youtubeKey.isEmpty)
                Link("How to get a free key (Google Cloud Console)", destination: URL(string: "https://developers.google.com/youtube/v3/getting-started")!)
                    .font(.callout)
            } header: {
                Text("YouTube API key (optional)")
            } footer: {
                Text("With a key, each recipe shows the top 3 tutorial videos with thumbnails. Without one, you get a YouTube search link instead.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Household") {
                Stepper("Default servings: \(store.prefs.householdSize)", value: $store.prefs.householdSize, in: 1...20)
            }

            Section("Diet") {
                toggles(Preferences.dietOptions, selection: $store.prefs.diets)
            }

            Section {
                toggles(Preferences.allergyOptions, selection: $store.prefs.allergies)
                TextField("Other allergies (comma separated)", text: $store.prefs.customAllergies)
                TextField("Foods you dislike", text: $store.prefs.dislikes)
            } header: {
                Text("Allergies & dislikes")
            } footer: {
                Text("Recipes warn you about matching ingredients, and Apple Intelligence suggests swaps. Always double-check labels for serious allergies.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Your data") {
                Button("Show Library in Finder") { NSWorkspace.shared.activateFileViewerSelecting([store.folder]) }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(glassOn ? .hidden : .automatic)
    }

    @ViewBuilder private func keyStatus(has: Bool) -> some View {
        if let err = store.keychainError {
            Label(err, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.callout)
        } else if has {
            Label("Saved in your Keychain", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.accent).font(.callout)
        }
    }

    private func toggles(_ options: [String], selection: Binding<[String]>) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading, spacing: 8) {
            ForEach(options, id: \.self) { option in
                Toggle(option, isOn: Binding(
                    get: { selection.wrappedValue.contains(option) },
                    set: { on in
                        if on { selection.wrappedValue.append(option) } else { selection.wrappedValue.removeAll { $0 == option } }
                    }))
                .toggleStyle(.checkbox)
            }
        }
    }
}
