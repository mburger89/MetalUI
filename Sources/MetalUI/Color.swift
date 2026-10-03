import Foundation
import MetalUICore

/// A colour — SwiftUI's `Color`, as a **value** (rulings `CR-B`, `CR-C`):
/// a literal in sRGB, a theme token, a colour that follows the colour scheme,
/// or an app palette key. Every API that takes a `ColorToken` takes a `Color`
/// too (`CR-E`), and a `Color` placed as a view fills whatever it is offered,
/// as SwiftUI's does (its `Element` conformance is an extension, `CR-D`, so
/// the value and its statics are usable off the main actor).
///
/// **Literals are gamma-encoded sRGB** (probe `swiftui-colour.swift` R1:
/// `Color(white: 0.5)` resolves 0.5, not linear light's 0.214), stored as
/// written and **clamped when resolved** (`R5`, `O4`, `O5`; divergence 118).
/// Like the theme's tokens they are written to a layer whose colour space is
/// Display P3 on AppKit, so they render slightly more saturated than the hex
/// implies — divergence 1, which literals share (`CR-I`).
///
/// **Equality compares components** (`Q4`, `Q5`): `Color(white: 1) == .white
/// == Color(red: 1, green: 1, blue: 1)`. A dynamic colour equals only a
/// dynamic colour with equal halves; a token-backed colour equals the same
/// token; a palette colour the same key.
///
/// **Storage** (`CR-R`): `Float` components (every consumer is `Float`), a NaN
/// stored as 0 so a declared colour always equals itself — `CR-H` compares
/// declared colours frame to frame, and `Float.nan != .nan` would restart a
/// fade every frame. At most 24 bytes (`aColorIsAtMostTwentyFourBytes`).
public struct Color: Hashable, Sendable {
    /// The colour space a literal's components are written in — SwiftUI's
    /// `Color.RGBColorSpace` without `.displayP3` (`CR-C` item 6: MetalUI
    /// would clamp SwiftUI's extended-sRGB answer and draw it into a P3 layer,
    /// wrong twice, so the spelling does not compile rather than mis-drawing).
    public enum RGBColorSpace: Hashable, Sendable {
        /// Gamma-encoded sRGB, the components as drawn (probe R1, R2).
        case sRGB
        /// Linear-light sRGB, converted to gamma at init with the sRGB transfer
        /// function (probe R3: 0.2 → 0.4845).
        case sRGBLinear
    }

    /// What a colour is before a theme and a scheme resolve it (`CR-C` item 3).
    enum Provider: Hashable, Sendable {
        /// Gamma sRGB as written (NaN stored as 0); the fourth is the opacity.
        case srgb(Float, Float, Float, Float)
        /// A theme token: resolves to `theme[token]`, bit-exactly (`CR-H`).
        case token(ColorToken)
        /// The light half or the dark half, by the environment's scheme (`CR-O`).
        indirect case dynamic(light: Color, dark: Color)
        /// An app palette key (`CR-N`): the theme's override, else the key's default.
        case palette(PaletteKey)
    }

    var provider: Provider
    /// The `opacity(_:)` multiplier of a non-literal colour (a literal folds
    /// it into its own opacity); applied after resolution, clamped.
    var opacityFactor: Float

    init(provider: Provider, opacityFactor: Float = 1) {
        self.provider = provider
        self.opacityFactor = opacityFactor
    }

    /// A NaN stored as 0 (`CR-R` item 2); every other value as written.
    static func canonical(_ value: Float) -> Float { value.isNaN ? 0 : value }

    /// A literal from gamma-encoded sRGB components.
    init(srgb r: Float, _ g: Float, _ b: Float, _ a: Float) {
        self.init(provider: .srgb(Self.canonical(r), Self.canonical(g), Self.canonical(b), Self.canonical(a)))
    }

    /// The `0xRRGGBB` literal.
    init(hex: UInt32) {
        self.init(srgb: Float((hex >> 16) & 0xFF) / 255, Float((hex >> 8) & 0xFF) / 255,
                  Float(hex & 0xFF) / 255, 1)
    }

    /// One linear-light component in gamma encoding (the sRGB transfer
    /// function, sign-preserving for extended values).
    static func gamma(_ linear: Double) -> Double {
        let magnitude = abs(linear)
        let encoded = magnitude <= 0.0031308 ? 12.92 * magnitude : 1.055 * Foundation.pow(magnitude, 1 / 2.4) - 0.055
        return linear < 0 ? -encoded : encoded
    }

    /// A colour from red, green and blue components in `colorSpace`, and an
    /// opacity — SwiftUI's `Color(_:red:green:blue:opacity:)` (probe R0–R3).
    /// Out-of-range values are kept and clamped when resolved (R5).
    public init(_ colorSpace: RGBColorSpace = .sRGB, red: Double, green: Double, blue: Double,
                opacity: Double = 1) {
        switch colorSpace {
        case .sRGB:
            self.init(srgb: Float(red), Float(green), Float(blue), Float(opacity))
        case .sRGBLinear:
            self.init(srgb: Float(Self.gamma(red)), Float(Self.gamma(green)), Float(Self.gamma(blue)),
                      Float(opacity))
        }
    }

    /// A grey of `white` in `colorSpace` — SwiftUI's `Color(_:white:opacity:)`
    /// (probe R1, R7): `(white, white, white)`, a literal like any other.
    public init(_ colorSpace: RGBColorSpace = .sRGB, white: Double, opacity: Double = 1) {
        self.init(colorSpace, red: white, green: white, blue: white, opacity: opacity)
    }

    /// A colour from hue, saturation and brightness (HSB, each 0…1), converted
    /// to sRGB at once — SwiftUI's `Color(hue:saturation:brightness:opacity:)`
    /// (probe R6).
    public init(hue: Double, saturation: Double, brightness: Double, opacity: Double = 1) {
        let h = hue.isFinite ? (hue - hue.rounded(.down)) * 6 : 0
        let chroma = brightness * saturation
        let x = chroma * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        let m = brightness - chroma
        let (r, g, b): (Double, Double, Double) =
            switch h {
            case ..<1: (chroma, x, 0)
            case ..<2: (x, chroma, 0)
            case ..<3: (0, chroma, x)
            case ..<4: (0, x, chroma)
            case ..<5: (x, 0, chroma)
            default:   (chroma, 0, x)
            }
        self.init(srgb: Float(r + m), Float(g + m), Float(b + m), Float(opacity))
    }

    /// The colour `token` names in the active theme: it follows a theme swap
    /// and the window's light/dark variant (MetalUI-only; `CR-C` item 5).
    public init(_ token: ColorToken) {
        self.init(provider: .token(token))
    }

    /// A literal from MetalUI's `Hsla` (MetalUI-only; `CR-C` item 4) — the
    /// bridge from `Hsla.rgb(0x…)` hex and a hand-written element's colours.
    public init(_ hsla: Hsla) {
        let rgba = hsla.toRgba()
        self.init(srgb: rgba.r, rgba.g, rgba.b, rgba.a)
    }

    /// A colour that is `light` in the light scheme and `dark` in the dark
    /// one (MetalUI-only, ruling `CR-O`: SwiftUI has no such initialiser and
    /// spells it through `NSColor(name:dynamicProvider:)`, probe D1). Either
    /// half may itself be dynamic, token-backed or a palette colour;
    /// `opacity(_:)` applies after the half is chosen (D2).
    public init(light: Color, dark: Color) {
        self.init(provider: .dynamic(light: light, dark: dark))
    }

    /// The app palette colour `key` names (MetalUI-only, ruling `CR-N`): the
    /// theme's override for `key` if it has one, else `key.defaultValue`.
    /// Apps spell `extension Color { static let brand = Color(Brand.self) }`.
    public init<K: ThemeColorKey>(_ key: K.Type) {
        self.init(provider: .palette(PaletteKey(type: key)))
    }

    /// This colour with its opacity multiplied by `opacity` — SwiftUI's
    /// `Color.opacity(_:)` (ruling `CR-G`; probe O2, O3: twice multiplies).
    /// Clamped when resolved (O4, O5). On a `Color` placed as a view, a
    /// literal argument reaches this method, not the view modifier, so it is
    /// one fill at that alpha with no opacity layer (probe `O6`).
    public func opacity(_ opacity: Double) -> Color {
        let factor = Self.canonical(Float(opacity))
        if case let .srgb(r, g, b, a) = provider {
            return Color(srgb: r, g, b, a * factor)
        }
        return Color(provider: provider, opacityFactor: Self.canonical(opacityFactor * factor))
    }

    /// The token this colour was built from, or `nil` for any other colour.
    @available(*, deprecated, message: "a Color is a value now: compare it, or resolve it with PaintPass.resolve(_:)")
    public var color: ColorToken? {
        if case let .token(token) = provider, opacityFactor == 1 { return token }
        return nil
    }

    // MARK: Resolution (CR-H)

    /// `value` clamped to 0…1, NaN to 0.
    static func clamped(_ value: Float) -> Float { value.isNaN ? 0 : min(max(value, 0), 1) }

    /// **The one resolution function** (ruling `CR-H` item 1): this colour
    /// against `theme` and `scheme`. A literal clamps; a token returns
    /// `theme[token]` **bit-exactly** (no round trip, so every token draws the
    /// pixels it drew before); a dynamic colour picks by `scheme`; a palette
    /// colour resolves the theme's override or its key's default, trapping
    /// on a cycle (`CR-N` item 5). The opacity multiplier applies last.
    func resolved(theme: Theme, scheme: ColorScheme, depth: Int = 0) -> Hsla {
        var base: Hsla
        switch provider {
        case let .srgb(r, g, b, a):
            return Rgba(r: Self.clamped(r), g: Self.clamped(g), b: Self.clamped(b), a: Self.clamped(a)).toHsla()
        case let .token(token):
            base = theme[token]
        case let .dynamic(light, dark):
            base = (scheme == .dark ? dark : light).resolved(theme: theme, scheme: scheme, depth: depth)
        case let .palette(key):
            if depth >= 16 { fatalError("ThemeColorKey cycle through \(key.name)") }
            base = theme.paletteColor(key).resolved(theme: theme, scheme: scheme, depth: depth + 1)
        }
        if opacityFactor != 1 { base.a *= Self.clamped(opacityFactor) }
        return base
    }

    /// A resolved colour: gamma-encoded sRGB components and an opacity, each
    /// clamped to 0…1 — SwiftUI's `Color.Resolved` (ruling `CR-H` item 4).
    /// **Divergence 118**: SwiftUI keeps extended-range values here and
    /// clamps only when drawing.
    public struct Resolved: Hashable, Sendable {
        /// Red, gamma-encoded, 0…1.
        public var red: Float
        /// Green, gamma-encoded, 0…1.
        public var green: Float
        /// Blue, gamma-encoded, 0…1.
        public var blue: Float
        /// Opacity, 0…1.
        public var opacity: Float
    }

    /// This colour resolved in `environment` — its theme and its
    /// `colorScheme` — SwiftUI's `Color.resolve(in:)` (ruling `CR-H` item 4).
    /// The theme itself stays paint-only (`EV-G`); a colour resolves wherever
    /// an environment is in hand.
    public func resolve(in environment: EnvironmentValues) -> Resolved {
        let rgba = resolved(theme: environment.theme, scheme: environment.colorScheme).toRgba()
        return Resolved(red: rgba.r, green: rgba.g, blue: rgba.b, opacity: rgba.a)
    }

    // MARK: Named statics (CR-F; probe N, macOS 27 values, divergence 117)

    /// Opaque black, `000000` in both schemes (probe N).
    public static let black = Color(srgb: 0, 0, 0, 1)
    /// Opaque white, `FFFFFF` in both schemes (probe N).
    public static let white = Color(srgb: 1, 1, 1, 1)
    /// Fully transparent black (probe N).
    public static let clear = Color(srgb: 0, 0, 0, 0)
    /// System gray: `8E8E93` light, `98989D` dark (probe N; divergence 117).
    public static let gray = Color(light: Color(hex: 0x8E8E93), dark: Color(hex: 0x98989D))
    /// System red: `FF383C` light, `FF4245` dark (probe N; divergence 117).
    public static let red = Color(light: Color(hex: 0xFF383C), dark: Color(hex: 0xFF4245))
    /// System orange: `FF8D28` light, `FF9230` dark (probe N; divergence 117).
    public static let orange = Color(light: Color(hex: 0xFF8D28), dark: Color(hex: 0xFF9230))
    /// System yellow: `FFCC00` light, `FFD600` dark (probe N; divergence 117).
    public static let yellow = Color(light: Color(hex: 0xFFCC00), dark: Color(hex: 0xFFD600))
    /// System green: `34C759` light, `30D158` dark (probe N; divergence 117).
    public static let green = Color(light: Color(hex: 0x34C759), dark: Color(hex: 0x30D158))
    /// System mint: `00C8B3` light, `00DAC3` dark (probe N; divergence 117).
    public static let mint = Color(light: Color(hex: 0x00C8B3), dark: Color(hex: 0x00DAC3))
    /// System teal: `00C3D0` light, `00D2E0` dark (probe N; divergence 117).
    public static let teal = Color(light: Color(hex: 0x00C3D0), dark: Color(hex: 0x00D2E0))
    /// System cyan: `00C0E8` light, `3CD3FE` dark (probe N; divergence 117).
    public static let cyan = Color(light: Color(hex: 0x00C0E8), dark: Color(hex: 0x3CD3FE))
    /// System blue: `0088FF` light, `0091FF` dark (probe N; divergence 117).
    public static let blue = Color(light: Color(hex: 0x0088FF), dark: Color(hex: 0x0091FF))
    /// System indigo: `6155F5` light, `6D7CFF` dark (probe N; divergence 117).
    public static let indigo = Color(light: Color(hex: 0x6155F5), dark: Color(hex: 0x6D7CFF))
    /// System purple: `CB30E0` light, `DB34F2` dark (probe N; divergence 117).
    public static let purple = Color(light: Color(hex: 0xCB30E0), dark: Color(hex: 0xDB34F2))
    /// System pink: `FF2D55` light, `FF375F` dark (probe N; divergence 117).
    public static let pink = Color(light: Color(hex: 0xFF2D55), dark: Color(hex: 0xFF375F))
    /// System brown: `AC7F5E` light, `B78A66` dark (probe N; divergence 117).
    public static let brown = Color(light: Color(hex: 0xAC7F5E), dark: Color(hex: 0xB78A66))

    /// The primary content colour: the theme's `textPrimary` (divergence 116 —
    /// SwiftUI's is the system label colour, black/white at 0.8471).
    public static let primary = Color(ColorToken.textPrimary)
    /// The secondary content colour: `textPrimary` at SwiftUI's secondary to
    /// primary alpha ratio, 0.588 light and 0.648 dark (divergence 116).
    public static let secondary = Color(light: Color(ColorToken.textPrimary).opacity(0.588),
                                        dark: Color(ColorToken.textPrimary).opacity(0.648))
    /// The accent colour: the theme's `accent` (divergence 116 — SwiftUI's
    /// is the user's system accent).
    public static let accentColor = Color(ColorToken.accent)

    // MARK: Token statics (CR-E item 2)

    /// `Color(.background)`: the theme's window background.
    public static let background = Color(ColorToken.background)
    /// `Color(.surface)`: the theme's raised surface.
    public static let surface = Color(ColorToken.surface)
    /// `Color(.surfaceSecondary)`: the theme's secondary surface.
    public static let surfaceSecondary = Color(ColorToken.surfaceSecondary)
    /// `Color(.accent)`: the theme's accent.
    public static let accent = Color(ColorToken.accent)
    /// `Color(.separator)`: the theme's separator.
    public static let separator = Color(ColorToken.separator)
    /// `Color(.textPrimary)`: the theme's primary text colour.
    public static let textPrimary = Color(ColorToken.textPrimary)
    /// `Color(.scrollIndicator)`: the theme's scroll indicator thumb.
    public static let scrollIndicator = Color(ColorToken.scrollIndicator)
    /// `Color(.scrim)`: the theme's modal scrim.
    public static let scrim = Color(ColorToken.scrim)
    /// `Color(.shadow)`: the theme's default shadow colour (`GX-J`).
    public static let shadow = Color(ColorToken.shadow)
}

/// An app palette key's identity: the key type, compared and hashed by its
/// `ObjectIdentifier`, its name kept for the cycle trap (`CR-N`).
struct PaletteKey: Hashable, @unchecked Sendable {
    let type: any ThemeColorKey.Type

    var id: ObjectIdentifier { ObjectIdentifier(type) }
    var name: String { String(describing: type) }

    static func == (lhs: PaletteKey, rhs: PaletteKey) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// A colour in an app's palette, with a light and dark default and a
/// per-theme override — `EnvironmentKey`'s shape over the theme (MetalUI-only,
/// ruling `CR-N`). SwiftUI's answer is an asset catalog's named colour; a
/// typed key gives the same "one name, two appearances" with no catalog or
/// string, and a theme can override it:
///
/// ```swift
/// struct Brand: ThemeColorKey {
///     static let defaultValue = Color(light: Color(red: 0.1, green: 0.3, blue: 0.8),
///                                     dark: Color(red: 0.4, green: 0.6, blue: 1))
/// }
/// extension Color { static let brand = Color(Brand.self) }
/// window.darkTheme[Brand.self] = .purple
/// ```
public protocol ThemeColorKey {
    /// The colour when the theme holds no override; usually a
    /// `Color(light:dark:)`.
    static var defaultValue: Color { get }
}

/// The context a colour resolves against in paint: the element's theme and
/// colour scheme (`CR-H` item 2), and the resolution of a colour in it.
struct ColorContext {
    var theme: Theme
    var scheme: ColorScheme

    func resolve(_ color: Color) -> Hsla { color.resolved(theme: theme, scheme: scheme) }
}

extension Frame {
    /// The colour scheme at the current position, read in place (not through
    /// a counted environment snapshot).
    var colorScheme: ColorScheme { environmentTop.colorScheme }

    /// The resolution context at the current position.
    var colorContext: ColorContext { ColorContext(theme: environmentTop.theme, scheme: environmentTop.colorScheme) }

    /// `color` resolved against the current position's theme and scheme —
    /// `PaintPass.resolve(_:)`'s implementation (`CR-H` item 1).
    func resolve(_ color: Color) -> Hsla {
        color.resolved(theme: environmentTop.theme, scheme: environmentTop.colorScheme)
    }
}
