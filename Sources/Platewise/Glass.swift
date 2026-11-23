import SwiftUI

/// Optional Liquid Glass theme (Settings › Appearance). Off by default; needs macOS 26.
enum GlassTheme {
    static let key = "glassTheme"
    static var supported: Bool {
        if #available(macOS 26, *) { return true }
        return false
    }
}

private struct GlassOnKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// True when the glass theme is turned on and the system supports it.
    var glassOn: Bool {
        get { self[GlassOnKey.self] }
        set { self[GlassOnKey.self] = newValue }
    }
}

/// Reads the stored setting and publishes `glassOn` to the views below.
struct GlassThemeRoot: ViewModifier {
    @AppStorage(GlassTheme.key) private var stored = false
    func body(content: Content) -> some View {
        content.environment(\.glassOn, stored && GlassTheme.supported)
    }
}

extension View {
    func glassThemeRoot() -> some View { modifier(GlassThemeRoot()) }

    /// Glass in `shape` when `on`; otherwise the view is returned untouched.
    @ViewBuilder
    func glassPanel<S: Shape>(_ on: Bool, in shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if on {
            if #available(macOS 26, *) {
                self.glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
            } else { self }
        } else { self }
    }

    /// Glass buttons when `on`; otherwise the existing button style is left alone.
    @ViewBuilder
    func glassButtons(_ on: Bool, prominent: Bool = false) -> some View {
        if on {
            if #available(macOS 26, *) {
                if prominent { self.buttonStyle(.glassProminent).buttonBorderShape(.capsule).tint(Theme.accent) } else { self.buttonStyle(.glass).tint(nil) }
            } else { self }
        } else { self }
    }

    /// Pull-down menus drawn as glass buttons when `on`.
    @ViewBuilder
    func glassMenu(_ on: Bool) -> some View {
        if on {
            if #available(macOS 26, *) {
                self.menuStyle(.borderlessButton)
                    .padding(.horizontal, 12).frame(minHeight: 32)
                    .glassEffect(.regular.interactive(), in: Capsule())
            } else { self }
        } else { self }
    }

    /// Groups nearby glass shapes so they blend and render together.
    @ViewBuilder
    func glassGroup(_ on: Bool, spacing: CGFloat = 12) -> some View {
        if on {
            if #available(macOS 26, *) {
                GlassEffectContainer(spacing: spacing) { self }
            } else { self }
        } else { self }
    }

    /// Soft basil/saffron wash behind a screen so the glass surfaces on it have something to refract.
    @ViewBuilder
    func glassBackdrop(_ on: Bool) -> some View {
        if on {
            self.background {
                ZStack {
                    Color(nsColor: .windowBackgroundColor)
                    LinearGradient(colors: [Theme.accent.opacity(0.20), Theme.warm.opacity(0.10), Theme.accent.opacity(0.06)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                .ignoresSafeArea()
            }
        } else { self }
    }
}
