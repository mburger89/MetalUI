import MetalUICore

/// A semantic colour slot (spec §7.9): "Colors in element code are **semantic
/// tokens** … never literals."
///
/// That is why `StyledElement.background(_:)` takes a token and not an `Hsla`.
/// A literal would paint the same pixels in both appearances, and — worse — it
/// would do so *invisibly*: nothing about a call site holding a hex value says
/// it will not follow the theme.
///
/// **Every case below is paintable today**, which is the reason there is no
/// `textPrimary` here even though §7.9 names one as an example. There is no
/// text system until M2 and no glyph primitive for a colour to apply to, so a
/// `textPrimary` token would be a value with nothing to read it — the shape
/// CLAUDE.md's inert-API table exists to catch. `separator` earns its place
/// because a separator is a thin filled box, which `fill` already draws.
public enum ColorToken: Sendable, Hashable, CaseIterable {
    /// The window's canvas, behind everything else.
    case background
    /// A raised panel on the canvas.
    case surface
    /// A recessed or secondary region *inside* a surface.
    case surfaceSecondary
    /// The tint that marks the primary action or selection.
    case accent
    /// Hairlines between regions.
    case separator
}

/// The mapping from `ColorToken` to colour, for one appearance (spec §7.9).
///
/// **Supplied at the window level and propagated through the frame context**, so
/// no element reads global state: `Window` owns the active `Theme`, hands it to
/// each `Frame`, and `PaintPass.theme` is where an element reads it. There is no
/// singleton, no environment stack and no per-property inheritance — a token
/// resolves against exactly one theme, the one the frame was built with.
///
/// **Stored properties and a total subscript, not a dictionary.** A
/// `[ColorToken: Hsla]` has a missing-key case, and the only two answers to it
/// are a crash or a silent fallback colour. With one stored property per token
/// the `switch` below is exhaustive, so adding a case to `ColorToken` is a
/// compile error here rather than a colour that quietly resolves to grey.
///
/// **Colours are authored in sRGB while the layer's colorspace is Display P3**,
/// so these render somewhat more saturated than the hex implies. That is
/// divergence 1 in CLAUDE.md — expected and measured, not a bug to chase.
public struct Theme: Sendable, Hashable {
    public var background: Hsla
    public var surface: Hsla
    public var surfaceSecondary: Hsla
    public var accent: Hsla
    public var separator: Hsla

    public init(background: Hsla, surface: Hsla, surfaceSecondary: Hsla,
                accent: Hsla, separator: Hsla) {
        self.background = background
        self.surface = surface
        self.surfaceSecondary = surfaceSecondary
        self.accent = accent
        self.separator = separator
    }

    public subscript(token: ColorToken) -> Hsla {
        switch token {
        case .background:       background
        case .surface:          surface
        case .surfaceSecondary: surfaceSecondary
        case .accent:           accent
        case .separator:        separator
        }
    }

    /// **No two tokens share a value, in either variant, and no token holds the
    /// same value in both.** That is a property of these constants rather than
    /// of the type, and it is asserted — `everyTokenDiffersBetweenLightAndDark`
    /// and `noTwoTokensCollideWithinAVariant` in `ThemeTests.swift`. A theme
    /// where two tokens coincide gives a green test at a point where the two are
    /// indistinguishable, so a `background`/`surface` mix-up would paint
    /// correctly and mean nothing.
    public static let light = Theme(
        background:       .rgb(0xF5F5F7),
        surface:          .rgb(0xFFFFFF),
        surfaceSecondary: .rgb(0xE4E7EC),
        accent:           .rgb(0x2563EB),
        separator:        .rgb(0xC8CDD6))

    /// See `light` for why every value here differs from its counterpart.
    public static let dark = Theme(
        background:       .rgb(0x0B1020),
        surface:          .rgb(0x161C2E),
        surfaceSecondary: .rgb(0x27304A),
        accent:           .rgb(0x60A5FA),
        separator:        .rgb(0x3A4260))

    /// The theme the host's current appearance calls for.
    ///
    /// The single place the two variants are chosen between, which is what makes
    /// the choice mutable in one edit and therefore checkable: returning `light`
    /// unconditionally here reddens `darkAppearanceSelectsTheDarkTheme` and the
    /// window-level tests that follow it.
    public static func forAppearance(_ appearance: Appearance) -> Theme {
        switch appearance {
        case .light: light
        case .dark:  dark
        }
    }
}
