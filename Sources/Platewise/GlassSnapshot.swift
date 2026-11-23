#if DEBUG
import AppKit
import SwiftUI

/// Developer aid (debug builds only): `Platewise --glass-snapshot <dir>` captures every section with the
/// Liquid Glass theme off and on, in light and dark, using the app's own window capture (renders real glass),
/// then restores the saved setting and quits.
@MainActor
enum GlassSnapshot {
    static func runIfRequested(store: Store, scan: ScanModel) async {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--glass-snapshot"), i + 1 < args.count else { return }
        let dir = URL(fileURLWithPath: args[i + 1])
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: GlassTheme.key)
        defer {
            if let original { defaults.set(original, forKey: GlassTheme.key) } else { defaults.removeObject(forKey: GlassTheme.key) }
        }
        NSApp.activate(ignoringOtherApps: true)
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }) else { NSApp.terminate(nil); return }
        window.setContentSize(NSSize(width: 1280, height: 820))
        window.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .seconds(1))

        for dark in [false, true] {
            NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            for glass in [false, true] {
                defaults.set(glass, forKey: GlassTheme.key)
                let suffix = "\(glass ? "glass" : "plain")-\(dark ? "dark" : "light")"
                for section in AppSection.allCases {
                    store.section = section
                    NSApp.activate(ignoringOtherApps: true)
                    try? await Task.sleep(for: .seconds(1.2))
                    await capture(window, to: dir.appendingPathComponent("\(slug(section))-\(suffix).png"))
                }
                // Snap & Cook with a photo and dish matches (in memory only; nothing is saved).
                store.section = .snap
                // A very tall photo must stay inside the drop zone.
                let tall = NSImage(size: NSSize(width: 300, height: 1500), flipped: false) { r in
                    NSGradient(colors: [.systemOrange, .systemRed, .systemPurple])?.draw(in: r, angle: 90); return true }
                scan.setImage(tall)
                scan.result = IdentifyResult(photoDescription: nil, isFood: true, candidates: [
                    DishCandidate(name: "Chicken Karahi", cuisine: "Pakistani", confidence: 82, reason: "Tomato-rich red gravy, green chillies and ginger juliennes in a wok-style pan."),
                    DishCandidate(name: "Butter Chicken", cuisine: "North Indian", confidence: 41, reason: "Similar colour, but the sauce looks less creamy."),
                    DishCandidate(name: "Chicken Jalfrezi", cuisine: "Indian", confidence: 23, reason: "Peppers would usually be visible."),
                ], visibleIngredients: ["chicken", "tomato", "green chilli", "ginger", "coriander"], note: "")
                scan.phase = .candidates
                try? await Task.sleep(for: .seconds(1.2))
                await capture(window, to: dir.appendingPathComponent("snap-candidates-\(suffix).png"))
                scan.clear()

                // Settings window.
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                try? await Task.sleep(for: .seconds(1.2))
                if let settings = NSApp.windows.first(where: { $0.isVisible && $0 !== window && $0.contentView != nil && $0.frame.width > 300 }) {
                    await capture(settings, to: dir.appendingPathComponent("settings-window-\(suffix).png"))
                    settings.close()
                }
                window.makeKeyAndOrderFront(nil)
            }
        }
        store.section = .snap
        if let original { defaults.set(original, forKey: GlassTheme.key) } else { defaults.removeObject(forKey: GlassTheme.key) }
        NSApp.terminate(nil)
    }

    private static func slug(_ s: AppSection) -> String {
        s.rawValue.lowercased().replacingOccurrences(of: " & ", with: "-").replacingOccurrences(of: " ", with: "-")
    }

    private typealias CapFn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

    private static func capture(_ window: NSWindow, to url: URL) async {
        // Other apps may hold focus; retry briefly so the window draws in its active state.
        for _ in 0..<30 where !(NSApp.isActive && window.isKeyWindow) {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .milliseconds(100))
        }
        try? await Task.sleep(for: .milliseconds(300))
        if !NSApp.isActive { FileHandle.standardError.write("inactive: \(url.lastPathComponent)\n".data(using: .utf8)!) }
        guard let sym = dlsym(dlopen(nil, RTLD_NOW), "CGWindowListCreateImage") else { return }
        let f = unsafeBitCast(sym, to: CapFn.self)
        guard let img = f(.null, 8, UInt32(window.windowNumber), 1 | 8)?.takeRetainedValue() else { return }
        try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
