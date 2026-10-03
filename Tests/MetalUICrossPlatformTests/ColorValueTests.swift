import Testing
import MetalUICore
@testable import MetalUI

// Colour and colour scheme, lane 1 — the `Color` value (spec
// `docs/superpowers/specs/2026-10-03-colour-design.md` §6.1, tests 1.1–1.10;
// rulings `CR-C`, `CR-F`, `CR-G`, `CR-H`, `CR-O`, `CR-R`). SwiftUI's side is
// `docs/probes/swiftui-colour.swift`; arm ids (`R…`, `N…`, `O…`, `Q…`, `D…`,
// `E…`) are its.
//
// **Portable**: no frame, no Metal — `Color.resolve(in:)` against an
// `EnvironmentValues` whose `colorScheme` (public) and `theme` (internal) are
// set, so Linux and Windows CI run these.

/// An environment at `scheme` over `theme`.
func colourEnvironment(_ scheme: ColorScheme, _ theme: Theme = .light) -> EnvironmentValues {
    var values = EnvironmentValues()
    values.colorScheme = scheme
    values.theme = theme
    return values
}

/// Componentwise, each component named.
func expectResolved(_ got: Color.Resolved, _ r: Float, _ g: Float, _ b: Float, _ a: Float,
                    tolerance: Float = 1e-5, _ what: String,
                    sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(abs(got.red - r) <= tolerance, "\(what): red expected \(r), got \(got.red)",
            sourceLocation: sourceLocation)
    #expect(abs(got.green - g) <= tolerance, "\(what): green expected \(g), got \(got.green)",
            sourceLocation: sourceLocation)
    #expect(abs(got.blue - b) <= tolerance, "\(what): blue expected \(b), got \(got.blue)",
            sourceLocation: sourceLocation)
    #expect(abs(got.opacity - a) <= tolerance, "\(what): opacity expected \(a), got \(got.opacity)",
            sourceLocation: sourceLocation)
}

/// `0xRRGGBB` as three 0…1 components.
private func hex(_ v: UInt32) -> (Float, Float, Float) {
    (Float((v >> 16) & 0xFF) / 255, Float((v >> 8) & 0xFF) / 255, Float(v & 0xFF) / 255)
}

/// **1.1** (`R0`, `R1`, `R2`, `R7`). The literal initialisers author
/// gamma-encoded sRGB: white 0.5 resolves 0.5, not linear light's 0.214.
/// Mutation: store `w * w` in `Color(white:)` (R1, R7 redden).
@Test func literalInitialisersAuthorGammaSRGB() {
    for scheme in ColorScheme.allCases {
        let e = colourEnvironment(scheme)
        expectResolved(Color(red: 1, green: 0, blue: 0).resolve(in: e), 1, 0, 0, 1, "R0 \(scheme)")
        expectResolved(Color(white: 0.5).resolve(in: e), 0.5, 0.5, 0.5, 1, tolerance: 1e-6, "R1 \(scheme)")
        expectResolved(Color(.sRGB, red: 0.2, green: 0.4, blue: 0.6, opacity: 0.8).resolve(in: e),
                       0.2, 0.4, 0.6, 0.8, "R2 \(scheme)")
        expectResolved(Color(white: 0.5, opacity: 0.25).resolve(in: e), 0.5, 0.5, 0.5, 0.25, "R7 \(scheme)")
    }
}

/// **1.2** (`R3`). `.sRGBLinear` converts to gamma at init with the sRGB
/// transfer function: 0.2 → 0.4845. Mutation: treat `.sRGBLinear` as `.sRGB`.
@Test func sRGBLinearConvertsToGammaAtInit() {
    let e = colourEnvironment(.light)
    expectResolved(Color(.sRGBLinear, red: 0.2, green: 0.4, blue: 0.6).resolve(in: e),
                   0.4845, 0.6652, 0.7977, 1, tolerance: 1e-4, "R3")
    expectResolved(Color(.sRGBLinear, white: 0.2).resolve(in: e),
                   0.4845, 0.4845, 0.4845, 1, tolerance: 1e-4, "R3 through white:")
}

/// **1.3** (`R6`). HSB converts like SwiftUI's: (0.5, 1, 1) → cyan, and a
/// hand-derived mid arm (0.1, 0.5, 0.8): C = 0.4, H' = 0.6, X = 0.24, m = 0.4
/// → (0.8, 0.64, 0.4). Mutation: HSL instead of HSB.
@Test func hueSaturationBrightnessConvertsLikeSwiftUI() {
    let e = colourEnvironment(.light)
    expectResolved(Color(hue: 0.5, saturation: 1, brightness: 1).resolve(in: e), 0, 1, 1, 1, "R6")
    expectResolved(Color(hue: 0.1, saturation: 0.5, brightness: 0.8, opacity: 0.5).resolve(in: e),
                   0.8, 0.64, 0.4, 0.5, "the mid arm")
}

/// **1.4** (`N`). Every named static resolves to the probed macOS 27 value in
/// both schemes (spec §3.2), within half a step. Mutations: swap the halves
/// in `dynamic` resolution; one hex digit in `red`'s light value (only the
/// `red` arm reddens).
@Test func everyNamedStaticResolvesToTheProbedValueInBothSchemes() {
    let table: [(String, Color, UInt32, UInt32)] = [
        ("gray", .gray, 0x8E8E93, 0x98989D), ("red", .red, 0xFF383C, 0xFF4245),
        ("orange", .orange, 0xFF8D28, 0xFF9230), ("yellow", .yellow, 0xFFCC00, 0xFFD600),
        ("green", .green, 0x34C759, 0x30D158), ("mint", .mint, 0x00C8B3, 0x00DAC3),
        ("teal", .teal, 0x00C3D0, 0x00D2E0), ("cyan", .cyan, 0x00C0E8, 0x3CD3FE),
        ("blue", .blue, 0x0088FF, 0x0091FF), ("indigo", .indigo, 0x6155F5, 0x6D7CFF),
        ("purple", .purple, 0xCB30E0, 0xDB34F2), ("pink", .pink, 0xFF2D55, 0xFF375F),
        ("brown", .brown, 0xAC7F5E, 0xB78A66),
        ("black", .black, 0x000000, 0x000000), ("white", .white, 0xFFFFFF, 0xFFFFFF),
    ]
    let step: Float = 0.5 / 255
    for (name, color, light, dark) in table {
        for (scheme, value) in [(ColorScheme.light, light), (.dark, dark)] {
            let (r, g, b) = hex(value)
            expectResolved(color.resolve(in: colourEnvironment(scheme)), r, g, b, 1, tolerance: step,
                           "\(name) \(scheme)")
        }
    }
    for scheme in ColorScheme.allCases {
        expectResolved(Color.clear.resolve(in: colourEnvironment(scheme)), 0, 0, 0, 0, "clear \(scheme)")
    }
}

/// **1.5** (divergence 116). `primary`, `secondary` and `accentColor` resolve
/// through the theme: `textPrimary`, `textPrimary` at SwiftUI's
/// secondary/primary alpha ratio (0.588 light, 0.648 dark), and `accent`.
/// Mutation: `accentColor` a fixed `.blue`.
@Test func theSemanticStaticsResolveThroughTheTheme() {
    for (scheme, theme, ratio) in [(ColorScheme.light, Theme.light, Float(0.588)), (.dark, .dark, 0.648)] {
        let e = colourEnvironment(scheme, theme)
        let text = theme.textPrimary.toRgba(), accent = theme.accent.toRgba()
        expectResolved(Color.primary.resolve(in: e), text.r, text.g, text.b, text.a, "primary \(scheme)")
        expectResolved(Color.accentColor.resolve(in: e), accent.r, accent.g, accent.b, accent.a,
                       "accentColor \(scheme)")
        expectResolved(Color.secondary.resolve(in: e), text.r, text.g, text.b, text.a * ratio,
                       "secondary \(scheme)")
    }
}

/// **1.6** (`O1`, `O3`, `O4`, `O5`, `R5`; `CR-R`). `opacity(_:)` multiplies,
/// and resolution clamps every component and the opacity to 0…1; a NaN is
/// stored as 0, so a NaN colour equals its zero twin. Mutations: `opacity(_:)`
/// assigns (O3); remove the clamp (O4, O5, R5); drop the NaN
/// canonicalisation (the NaN arms).
@Test func opacityMultipliesAndClampsAtResolution() {
    let light = colourEnvironment(.light)
    let (r, g, b) = hex(0xFF383C)
    expectResolved(Color.red.opacity(0.5).resolve(in: light), r, g, b, 0.5, tolerance: 0.5 / 255, "O1")
    expectResolved(Color(white: 0, opacity: 0.5).opacity(0.5).resolve(in: light), 0, 0, 0, 0.25, "O3")
    expectResolved(Color.red.opacity(1.5).resolve(in: light), r, g, b, 1, tolerance: 0.5 / 255, "O4")
    expectResolved(Color.red.opacity(-1).resolve(in: light), r, g, b, 0, tolerance: 0.5 / 255, "O5")
    expectResolved(Color(red: 1.2, green: -0.1, blue: 0.5).resolve(in: light), 1, 0, 0.5, 1, "R5")
    expectResolved(Color(red: .nan, green: 0.5, blue: 0.5).resolve(in: light), 0, 0.5, 0.5, 1,
                   "a NaN component resolves 0")
    #expect(Color(red: .nan, green: 0, blue: 0) == Color(red: 0, green: 0, blue: 0),
            "CR-R: a NaN is stored as 0, so the colour equals itself and its zero twin")
    #expect(Color(white: 1, opacity: .nan) == Color(white: 1, opacity: 0), "CR-R: a NaN opacity is stored as 0")
    #expect(Color.red.opacity(.nan) == Color.red.opacity(0), "CR-R: a NaN multiplier is stored as 0")
}

/// **1.7** (`Q1`–`Q5`). Equality compares components: `Color(white: 1) ==
/// .white == Color(red: 1, green: 1, blue: 1)`, and a token- or
/// palette-backed colour equals its own spelling. Mutation: give
/// `Color(white:)` its own provider case (Q4, Q5 redden).
@Test func equalityComparesComponentsLikeSwiftUI() {
    #expect(Color.red == Color.red, "Q1")
    #expect(Color(red: 1, green: 0, blue: 0) == Color(red: 1, green: 0, blue: 0), "Q2")
    #expect(Color.red.opacity(0.5) == Color.red.opacity(0.5), "Q3")
    #expect(Color(white: 1) == .white, "Q4")
    #expect(Color(white: 1).hashValue == Color.white.hashValue, "Q4 hashes equal")
    #expect(Color(red: 1, green: 1, blue: 1) == Color(white: 1), "Q5")
    #expect(Color(.surface) == .surface, "a token-backed colour equals the token static")
    #expect(Color(ValueTestBrand.self) == Color(ValueTestBrand.self), "a palette colour equals itself")
    #expect(Color.red != Color.blue && Color(.surface) != Color(.accent), "the control: different colours differ")
}

/// **1.8** (`CR-H` item 1). A token-backed colour resolves **bit-exactly** to
/// its token's `Hsla` — the same value, no round trip — so every existing
/// token draws 0 differing pixels. Mutation: resolve `token` through
/// `toRgba().toHsla()`.
@Test func aTokenBackedColorResolvesBitExactlyToItsToken() {
    for (scheme, theme) in [(ColorScheme.light, Theme.light), (.dark, .dark)] {
        for token in ColorToken.allCases {
            #expect(Color(token).resolved(theme: theme, scheme: scheme) == theme[token],
                    "\(token) under \(scheme) is not bit-exact")
        }
    }
}

/// **1.9** (`CR-O`, `D2`). `Color(light:dark:)` picks by the environment's
/// scheme; halves may be dynamic themselves; opacity applies after the half is
/// chosen. Mutation: ignore the scheme.
@Test func aDynamicColourFollowsTheEnvironmentsScheme() {
    let a = Color(red: 0.1, green: 0.2, blue: 0.3), b = Color(red: 0.9, green: 0.8, blue: 0.7)
    let c = Color(red: 0.4, green: 0.5, blue: 0.6)
    let dynamic = Color(light: a, dark: b)
    expectResolved(dynamic.resolve(in: colourEnvironment(.light)), 0.1, 0.2, 0.3, 1, "the light half")
    expectResolved(dynamic.resolve(in: colourEnvironment(.dark)), 0.9, 0.8, 0.7, 1, "the dark half")
    let nested = Color(light: Color(light: c, dark: a), dark: b)
    expectResolved(nested.resolve(in: colourEnvironment(.light)), 0.4, 0.5, 0.6, 1, "a dynamic of dynamics")
    expectResolved(dynamic.opacity(0.5).resolve(in: colourEnvironment(.dark)), 0.9, 0.8, 0.7, 0.5,
                   "D2: opacity after the half is chosen")
}

/// **1.10** (`E0`, `Q6`). A bare environment reads `.light`, and the cases are
/// SwiftUI's, in its order. Mutation: default `.dark`.
@Test func aBareEnvironmentReadsLightLikeSwiftUI() {
    #expect(EnvironmentValues().colorScheme == .light, "E0")
    #expect(ColorScheme.allCases == [.light, .dark], "Q6")
}

/// **`CR-R` item 3.** `Color` stays at most 24 bytes (Float storage, the
/// indirect cases boxed) — a `Decoration` holds six colours and elements are
/// copied through deep generic chains on 1 MB Windows stacks.
@Test func aColorIsAtMostTwentyFourBytes() {
    #expect(MemoryLayout<Color>.size <= 24, "MemoryLayout<Color>.size = \(MemoryLayout<Color>.size)")
}

/// A palette key for the value tests.
struct ValueTestBrand: ThemeColorKey {
    static let defaultValue = Color(light: Color(red: 0.1, green: 0.2, blue: 0.3),
                                    dark: Color(red: 0.7, green: 0.6, blue: 0.5))
}
