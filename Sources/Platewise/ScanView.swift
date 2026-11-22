import SwiftUI
import UniformTypeIdentifiers

/// Snap & Cook: photo → likely dishes → full recipe + YouTube videos.
@MainActor
final class ScanModel: ObservableObject {
    enum Phase: Equatable {
        case idle, identifying, candidates, cooking(String), recipe, failed(String)
    }

    @Published var image: NSImage?
    @Published var hint = ""
    @Published var phase: Phase = .idle
    @Published var result: IdentifyResult?
    @Published var recipe: Recipe?
    @Published var loadingVideos = false
    private var retry: (() -> Void)?
    private var task: Task<Void, Never>?

    func setImage(_ img: NSImage) {
        task?.cancel()
        image = img
        phase = .idle
        result = nil
        recipe = nil
    }

    func clear() {
        task?.cancel()
        image = nil; hint = ""; phase = .idle; result = nil; recipe = nil
    }

    func identify(store: Store) {
        guard let image else { return }
        let hint = hint
        retry = { [weak self] in self?.identify(store: store) }
        run(.identifying) {
            let r = try await ChefAI.identify(image: image, hint: hint)
            self.result = r
            self.phase = .candidates
        }
    }

    func choose(_ name: String, cuisine: String, store: Store) {
        let prefs = store.prefs, seen = result?.visibleIngredients ?? []
        retry = { [weak self] in self?.choose(name, cuisine: cuisine, store: store) }
        run(.cooking(name)) {
            let r = try await ChefAI.recipe(dish: name, cuisine: cuisine, visibleIngredients: seen, prefs: prefs)
            self.recipe = r
            self.phase = .recipe
            await self.loadVideos(store: store)
        }
    }

    func variant(_ change: String, store: Store) {
        guard let base = recipe else { return }
        let prefs = store.prefs
        retry = { [weak self] in self?.variant(change, store: store) }
        run(.cooking("a \(change) version")) {
            let r = try await ChefAI.variant(of: base, change: change, prefs: prefs)
            self.recipe = r
            self.phase = .recipe
            await self.loadVideos(store: store)
        }
    }

    func loadVideos(store: Store) async {
        guard let r = recipe else { return }
        loadingVideos = true
        let videos = await YouTube.videos(for: r.searchQuery, apiKey: store.youtubeKey)
        if recipe?.id == r.id { recipe?.videos = videos }
        // Saved while videos were still loading: update the library copy too.
        if var savedCopy = store.recipe(r.id), savedCopy.videos.isEmpty { savedCopy.videos = videos; store.upsert(savedCopy) }
        loadingVideos = false
    }

    func backToMatches() { phase = result == nil ? .idle : .candidates }
    func tryAgain() { retry?() }

    private func run(_ phase: Phase, _ work: @escaping () async throws -> Void) {
        task?.cancel()
        self.phase = phase
        task = Task {
            do { try await work() } catch is CancellationError {} catch {
                if !Task.isCancelled { self.phase = .failed(error.localizedDescription) }
            }
        }
    }
}

struct ScanView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var scan: ScanModel
    @State private var showCamera = false
    @State private var showImporter = false
    @State private var dropTargeted = false
    @State private var customName = ""

    var body: some View {
        HStack(spacing: 0) {
            photoPanel
                .frame(width: 360)
                .padding(20)
            Divider()
            results
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $showCamera) { CameraSheet { scan.setImage($0) } }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.image]) { result in
            if case .success(let url) = result, let img = NSImage(contentsOf: url) { scan.setImage(img) }
        }
    }

    // MARK: Left: photo

    private var photoPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            AIStatusBanner()

            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(dropTargeted ? Theme.accent.opacity(0.12) : Theme.subtle)
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: scan.image == nil ? [7] : []))
                        .foregroundStyle(dropTargeted ? Theme.accent : Color.secondary.opacity(0.35)))
                if let img = scan.image {
                    Image(nsImage: img).resizable().scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(alignment: .topTrailing) {
                            Button { scan.clear() } label: {
                                Image(systemName: "xmark.circle.fill").font(.title2).symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .black.opacity(0.5))
                            }
                            .buttonStyle(.plain).padding(8).help("Remove photo")
                        }
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "fork.knife.circle").font(.system(size: 54, weight: .light)).foregroundStyle(Theme.accent)
                        Text("Drop a food photo here").font(.headline)
                        Text("or use the camera, choose a file, or paste").font(.callout).foregroundStyle(.secondary)
                    }
                    .padding()
                }
            }
            .frame(height: 300)
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first, let img = NSImage(contentsOf: url) else { return false }
                scan.setImage(img); return true
            } isTargeted: { dropTargeted = $0 }

            HStack(spacing: 8) {
                Button { showCamera = true } label: { Label("Camera", systemImage: "camera") }
                Button { showImporter = true } label: { Label("Choose…", systemImage: "photo.on.rectangle") }
                Button {
                    if let img = ImageTools.fromPasteboard() { scan.setImage(img) }
                } label: { Label("Paste", systemImage: "doc.on.clipboard") }
                    .keyboardShortcut("v", modifiers: [.command, .shift])
            }
            .controlSize(.large)

            TextField("Optional hint, e.g. “from a Lahore street stall”", text: $scan.hint, axis: .vertical)
                .textFieldStyle(.roundedBorder).lineLimit(1...3)

            Button {
                scan.identify(store: store)
            } label: {
                Label("Identify Dish", systemImage: "sparkles").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(scan.image == nil || !store.aiStatus.canSee || scan.phase == .identifying)

            Spacer()
        }
    }

    // MARK: Right: results

    @ViewBuilder private var results: some View {
        switch scan.phase {
        case .idle:
            ContentUnavailableView {
                Label(scan.image == nil ? "Snap a dish, get the recipe" : "Ready when you are", systemImage: "camera.macro")
            } description: {
                Text(scan.image == nil
                     ? "Add a photo of any dish. Apple Intelligence suggests what it is and writes the full recipe with nutrition, right on your Mac, and Platewise finds YouTube videos to cook along with."
                     : "Click Identify Dish (⌘↩) to see what's on the plate.")
            }
        case .identifying:
            progress("Looking closely at your photo…")
        case .cooking(let name):
            progress("Writing the recipe for \(name)…")
        case .failed(let message):
            ContentUnavailableView {
                Label("Something went wrong", systemImage: "exclamationmark.triangle")
            } description: { Text(message) } actions: {
                Button("Try Again") { scan.tryAgain() }.buttonStyle(.borderedProminent)
            }
        case .candidates:
            if let r = scan.result { candidates(r) }
        case .recipe:
            if let r = scan.recipe {
                VStack(spacing: 0) {
                    HStack {
                        if scan.result != nil {
                            Button { scan.backToMatches() } label: { Label("Other matches", systemImage: "chevron.left") }
                                .buttonStyle(.borderless)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 24).padding(.top, 14)
                    RecipeDetailView(recipe: r, photo: scan.image, loadingVideos: scan.loadingVideos,
                                     onVariant: { scan.variant($0, store: store) })
                }
            }
        }
    }

    private func progress(_ text: String) -> some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text(text).font(.title3).foregroundStyle(.secondary)
        }
    }

    private func candidates(_ r: IdentifyResult) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !r.isFood || r.candidates.isEmpty {
                    Card {
                        Label(r.note.isEmpty ? "That doesn't look like a dish. Try another photo, or type the dish name below." : r.note,
                              systemImage: "questionmark.circle")
                    }
                } else {
                    Text("Is it one of these?").font(.title2.bold())
                    Text("Pick the right match to get the full recipe.").foregroundStyle(.secondary)
                    ForEach(Array(r.candidates.enumerated()), id: \.element) { i, c in
                        Button { scan.choose(c.name, cuisine: c.cuisine, store: store) } label: {
                            CandidateRow(candidate: c, best: i == 0)
                        }
                        .buttonStyle(.plain)
                    }
                    if !r.note.isEmpty { Text(r.note).font(.callout).foregroundStyle(.secondary) }
                }

                if !r.visibleIngredients.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Spotted in the photo").font(.headline)
                        FlowLayout { ForEach(r.visibleIngredients, id: \.self) { Chip(text: $0, symbol: "eye") } }
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("None of these?").font(.headline)
                        HStack {
                            TextField("Type the dish name", text: $customName).textFieldStyle(.roundedBorder)
                                .onSubmit(chooseCustom)
                            Button("Get Recipe", action: chooseCustom)
                                .disabled(customName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
        }
    }

    private func chooseCustom() {
        let name = customName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        scan.choose(name, cuisine: "", store: store)
        customName = ""
    }
}

private struct CandidateRow: View {
    let candidate: DishCandidate
    let best: Bool
    @State private var hover = false

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(Theme.subtle, lineWidth: 6)
                Circle().trim(from: 0, to: CGFloat(min(max(candidate.confidence, 0), 100)) / 100)
                    .stroke(best ? Theme.accent : Theme.warm, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(candidate.confidence)%").font(.caption.bold().monospacedDigit())
            }
            .frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(candidate.name).font(.title3.bold())
                    if best { Chip(text: "Best match", symbol: "star.fill") }
                }
                if !candidate.cuisine.isEmpty { Text(candidate.cuisine).font(.subheadline).foregroundStyle(Theme.accent) }
                Text(candidate.reason).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(hover ? Theme.accent.opacity(0.08) : Theme.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(best ? Theme.accent.opacity(0.5) : Theme.subtle))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }
}
