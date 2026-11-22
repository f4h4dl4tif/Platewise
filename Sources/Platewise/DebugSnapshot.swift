import AppKit

/// Developer aid: `PLATEWISE_SELFTEST=/path/report.json` runs the live Snap & Cook pipeline headlessly through
/// the bundled Apple Intelligence helper and writes a report. Optional: PLATEWISE_SELFTEST_IMAGE=/path/photo.jpg,
/// PLATEWISE_SELFTEST_DISH="Chicken Karahi".
@MainActor
enum SelfTest {
    static func runIfRequested(store: Store) async {
        let env = ProcessInfo.processInfo.environment
        guard let out = env["PLATEWISE_SELFTEST"], !out.isEmpty else { return }
        let status = await AppleAI.status()
        var report: [String: Any] = ["ai": "Apple Intelligence (on-device)", "status": "\(status)", "hasYouTubeKey": !store.youtubeKey.isEmpty]

        if let path = env["PLATEWISE_SELFTEST_IMAGE"], let image = NSImage(contentsOfFile: path) {
            let t = Date()
            do {
                let r = try await ChefAI.identify(image: image, hint: "")
                report["identify"] = ["ok": true, "seconds": Int(Date().timeIntervalSince(t)), "isFood": r.isFood, "note": r.note, "photo": r.photoDescription ?? "",
                                      "candidates": r.candidates.map { "\($0.name) (\($0.cuisine)) \($0.confidence)%: \($0.reason)" },
                                      "visible": r.visibleIngredients]
                if env["PLATEWISE_SELFTEST_DISH"] == nil, r.isFood, let top = r.candidates.first {
                    report["dishFromPhoto"] = top.name
                }
            } catch { report["identify"] = ["ok": false, "error": error.localizedDescription] }
        }

        if let dish = env["PLATEWISE_SELFTEST_DISH"] ?? report["dishFromPhoto"] as? String {
            let t = Date()
            do {
                let r = try await ChefAI.recipe(dish: dish, cuisine: "", visibleIngredients: [], prefs: store.prefs)
                let videos = await YouTube.videos(for: r.searchQuery, apiKey: store.youtubeKey)
                report["recipe"] = ["ok": true, "seconds": Int(Date().timeIntervalSince(t)), "name": r.name, "cuisine": r.cuisine,
                                    "servings": r.servings, "prep": r.prepMinutes, "cook": r.cookMinutes, "difficulty": r.difficulty,
                                    "ingredients": r.ingredients.map { "\($0.display())  [\($0.aisle.rawValue)]" },
                                    "steps": r.steps, "nutrition": "\(r.nutrition.calories) kcal, P\(r.nutrition.protein) C\(r.nutrition.carbs) F\(r.nutrition.fat)",
                                    "flags": r.dietaryFlags, "warnings": r.allergyWarnings, "tips": r.tips,
                                    "videoQuery": r.videoQuery, "videos": videos.map { "\($0.title) | \($0.channel) | \($0.url)" }]
            } catch { report["recipe"] = ["ok": false, "error": error.localizedDescription] }
        }

        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: out))
        }
        NSApp.terminate(nil)
    }
}

/// Developer aid: `PLATEWISE_SNAPSHOT=/some/folder Platewise` renders each section of the app's own window
/// to PNG files and quits. Needs no Screen Recording permission. Does nothing in normal use.
@MainActor
enum DebugSnapshot {
    static func runIfRequested(store: Store) async {
        guard let dir = ProcessInfo.processInfo.environment["PLATEWISE_SNAPSHOT"], !dir.isEmpty else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        // cacheDisplay skips the window's own background, so dark-mode text would land on white.
        let mode = ProcessInfo.processInfo.environment["PLATEWISE_SNAPSHOT_APPEARANCE"] == "dark" ? NSAppearance.Name.darkAqua : .aqua
        NSApp.appearance = NSAppearance(named: mode)
        try? await Task.sleep(for: .seconds(1.5))
        for section in AppSection.allCases {
            store.section = section
            try? await Task.sleep(for: .seconds(1.2))
            guard let view = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil })?.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            let name = section.rawValue.lowercased().replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: "&", with: "and")
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
        NSApp.terminate(nil)
    }
}
