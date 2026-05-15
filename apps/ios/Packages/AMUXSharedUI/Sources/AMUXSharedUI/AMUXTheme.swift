import SwiftUI

/// AMUX visual tokens — the **Hai 灰** wabi-sabi palette ratified for v1.
///
/// Six tokens drive the entire surface set: five paper/ink neutrals plus a
/// single restrained vermillion accent. The principle is "spare the
/// vermillion" — coral is reserved for the active session dot, the primary
/// CTA, and the unread/permission marker. Everywhere else stays in
/// Mist / Pebble / Slate / Basalt / Onyx.
///
/// The tokens are exposed as `Color.amux.*` so call sites read like a
/// design spec rather than a hex bag.
public enum AMUXTheme {
    /// `#F2F0EC` — Mist. Primary background. Replaces iOS systemGray6.
    public static let mist        = Color(red: 0xF2 / 255, green: 0xF0 / 255, blue: 0xEC / 255)
    /// `#F8F6F1` — Paper. Soft white card surface. Replaces pure white.
    public static let paper       = Color(red: 0xF8 / 255, green: 0xF6 / 255, blue: 0xF1 / 255)
    /// `#E2DFD9` — Pebble. Secondary surface (chips, dividers, inactive).
    public static let pebble      = Color(red: 0xE2 / 255, green: 0xDF / 255, blue: 0xD9 / 255)
    /// `#A6A39C` — Slate. Tertiary text / muted decoration.
    public static let slate       = Color(red: 0xA6 / 255, green: 0xA3 / 255, blue: 0x9C / 255)
    /// `#5E5B55` — Basalt. Secondary text / icon stroke.
    public static let basalt      = Color(red: 0x5E / 255, green: 0x5B / 255, blue: 0x55 / 255)
    /// `#22201D` — Onyx. Primary text / ink. Replaces iOS label primary.
    public static let onyx        = Color(red: 0x22 / 255, green: 0x20 / 255, blue: 0x1D / 255)
    /// `#B84B36` — Cinnabar. The single accent. Active state, primary CTA,
    /// unread dot, permission marker.
    public static let cinnabar    = Color(red: 0xB8 / 255, green: 0x4B / 255, blue: 0x36 / 255)
    /// `#8E3A2C` — Cinnabar deep. Destructive variant. Replaces iOS red.
    public static let cinnabarDeep = Color(red: 0x8E / 255, green: 0x3A / 255, blue: 0x2C / 255)
    /// `#6B8E5A` — Sage. Muted "active green". Replaces iOS green for the
    /// breathing dot so it doesn't read as alarming next to Mist.
    public static let sage        = Color(red: 0x6B / 255, green: 0x8E / 255, blue: 0x5A / 255)

    /// Hairline color — `Onyx` at low opacity. Use for row separators and
    /// quiet card borders. The warm tint matches the Mist background so
    /// hairlines never look bluish-cool against the paper.
    public static let hairline    = Color(red: 0x22 / 255, green: 0x20 / 255, blue: 0x1D / 255)
        .opacity(0.10)
}

public extension Color {
    /// Namespaced access to the Hai palette tokens. Prefer
    /// `Color.amux.cinnabar` over hard-coding hex; switching themes later
    /// becomes a single-file change.
    enum amux {
        public static var mist: Color         { AMUXTheme.mist }
        public static var paper: Color        { AMUXTheme.paper }
        public static var pebble: Color       { AMUXTheme.pebble }
        public static var slate: Color        { AMUXTheme.slate }
        public static var basalt: Color       { AMUXTheme.basalt }
        public static var onyx: Color         { AMUXTheme.onyx }
        public static var cinnabar: Color     { AMUXTheme.cinnabar }
        public static var cinnabarDeep: Color { AMUXTheme.cinnabarDeep }
        public static var sage: Color         { AMUXTheme.sage }
        public static var hairline: Color     { AMUXTheme.hairline }
    }
}

public extension Font {
    /// Editorial serif title for hero copy — matches the design system's
    /// EB Garamond direction using the system serif (New York). For italic
    /// accents combine with `.italic()` at the call site.
    static func amuxSerif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}
