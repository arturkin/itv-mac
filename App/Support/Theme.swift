import SwiftUI

/// The app's dark visual design. The app is always dark (see `ITVLiveApp`), so
/// these are explicit colors rather than light/dark semantic pairs — that also
/// makes the headless `ImageRenderer` snapshots deterministic.
enum Theme {
    // Surfaces, back-to-front.
    /// Deepest layer — the player letterbox / window base.
    static let background = Color(red: 0.066, green: 0.066, blue: 0.078)   // #111114
    /// The sidebar column.
    static let sidebar = Color(red: 0.094, green: 0.094, blue: 0.106)      // #18181B
    /// Raised bars: now-playing header, timeline day bar.
    static let surface = Color(red: 0.137, green: 0.137, blue: 0.153)      // #232327
    /// Hovered / inset chips (search field, logo well).
    static let surfaceHi = Color(red: 0.18, green: 0.18, blue: 0.20)       // #2E2E33

    // Lines & fills.
    static let separator = Color.white.opacity(0.08)
    static let hairline  = Color.white.opacity(0.05)

    // Text tiers.
    static let textPrimary   = Color(white: 0.95)
    static let textSecondary = Color(white: 0.62)
    static let textTertiary  = Color(white: 0.40)

    // Brand / state.
    /// Teal accent — selection, buttons, focus, catch-up affordances.
    static let accent = Color(red: 0.157, green: 0.804, blue: 0.733)       // #28CDBB
    /// Live / now — the universal red, kept distinct from the accent.
    static let live = Color(red: 1.0, green: 0.27, blue: 0.23)            // #FF453A
    /// Favorites.
    static let star = Color(red: 1.0, green: 0.84, blue: 0.04)            // #FFD60A

    /// Selected-row fill in the sidebar.
    static let selection = Color(red: 0.157, green: 0.804, blue: 0.733).opacity(0.18)
}

extension View {
    /// A consistently-styled section header for the snapshot sidebar and lists.
    func itvSectionHeader() -> some View {
        self.font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.textTertiary)
            .textCase(.uppercase)
    }
}
