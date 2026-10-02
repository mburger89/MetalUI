import MetalUICore

/// A semantic colour slot (spec §7.9): "Colors in element code are **semantic
/// tokens** … never literals."
///
/// That is why `StyledElement.background(_:)` takes a token and not an `Hsla`.
/// A literal would paint the same pixels in both appearances, and — worse — it
/// would do so *invisibly*: nothing about a call site holding a hex value says
/// it will not follow the theme.
///
/// **Every case below is paintable today.** That rule is what kept
/// `textPrimary` out until the glyph emitter landed: §7.9 names it as an
/// example, but a token with no primitive to apply it to is a value nothing
/// reads — the shape CLAUDE.md's inert-API table exists to catch. `Text.paint`
/// now tints glyphs with it, so it is here on the same footing as the rest;
/// `separator` earned its place earlier for the same reason, a separator being
/// a thin filled box that `fill` already draws.
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
    /// Body text on `background` or `surface`.
    ///
    /// The default a `Text` tints with when the author names no colour, which
    /// is why it is a token and not a literal: unthemed text is the single
    /// easiest thing to leave black in a dark window.
    case textPrimary
    /// The `ScrollView` overlay thumb (Task 9 of the clipping/scroll design).
    ///
    /// Added in this task rather than reused from an existing token: the
    /// indicator draws over arbitrary content — including `textPrimary`-tinted
    /// glyphs, which is the whole point of Task 1's draw list — so it needs a
    /// value translucent enough to read as an overlay rather than a full-alpha
    /// hairline the way `separator` is authored. `ScrollView.paint` multiplies
    /// this token's own alpha by the fade's `alpha` on top, so the base value
    /// here is what a freshly-scrolled thumb looks like at full opacity.
    case scrollIndicator
    /// The dimming wash a modal lays over the window behind it.
    ///
    /// Translucent, like `scrollIndicator` and unlike every other token here,
    /// for the same structural reason: it is authored to be seen *through*. An
    /// opaque scrim would make "the modal covers the window" and "the modal
    /// replaced the window" indistinguishable to the only check that can see
    /// either — a human looking at the demo.
    case scrim
    /// A shadow's default colour (ruling `GX-J`): black at 0.33 alpha in both
    /// appearances — SwiftUI's default `shadow(radius:)` colour reads 171 over
    /// white (probe SH2). **The one token the two themes share**, by
    /// SwiftUI's own answer (`everyTokenDiffersBetweenLightAndDark` exempts it
    /// by name). **New since paths, shadows and transforms**: an exhaustive
    /// `switch` over `ColorToken` outside the package gains an arm.
    case shadow
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
    /// The window background.
    public var background: Hsla
    /// A raised surface, such as a card or a button's chrome.
    public var surface: Hsla
    /// A secondary surface, such as a segmented picker's track.
    public var surfaceSecondary: Hsla
    /// The accent colour: selection, an on toggle, a slider's fill.
    public var accent: Hsla
    /// Separators, and a control's accent outside the key window (`IX-H`).
    public var separator: Hsla
    /// The primary text colour.
    public var textPrimary: Hsla
    /// The scroll indicator's thumb.
    public var scrollIndicator: Hsla
    /// The dimming behind a modal presentation.
    public var scrim: Hsla
    /// A shadow's default colour (`GX-J`).
    public var shadow: Hsla

    /// SwiftUI's default shadow colour: black at 0.33 alpha (probe SH2).
    public static let defaultShadow = Hsla.rgb(0x000000, alpha: 0.33)

    /// A theme from one colour per token. `shadow` is trailing and defaulted
    /// (ruling `GX-Q`), so a theme written before the token existed compiles
    /// unchanged and gets SwiftUI's default.
    public init(background: Hsla, surface: Hsla, surfaceSecondary: Hsla,
                accent: Hsla, separator: Hsla, textPrimary: Hsla, scrollIndicator: Hsla,
                scrim: Hsla, shadow: Hsla = Theme.defaultShadow) {
        self.background = background
        self.surface = surface
        self.surfaceSecondary = surfaceSecondary
        self.accent = accent
        self.separator = separator
        self.textPrimary = textPrimary
        self.scrollIndicator = scrollIndicator
        self.scrim = scrim
        self.shadow = shadow
    }

    /// The colour this theme gives `token`.
    public subscript(token: ColorToken) -> Hsla {
        switch token {
        case .background:       background
        case .surface:          surface
        case .surfaceSecondary: surfaceSecondary
        case .accent:           accent
        case .separator:        separator
        case .textPrimary:      textPrimary
        case .scrollIndicator:  scrollIndicator
        case .scrim:            scrim
        case .shadow:           shadow
        }
    }

    /// **No two tokens share a value, in either variant, and no token but
    /// `shadow` holds the same value in both** (`shadow` is SwiftUI's one
    /// default for both appearances, probe SH2). That is a property of these constants rather than
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
        separator:        .rgb(0xC8CDD6),
        textPrimary:      .rgb(0x14181F),
        scrollIndicator:  .rgb(0x000000, alpha: 0.35),
        scrim:            .rgb(0x0B1020, alpha: 0.32),
        shadow:           Theme.defaultShadow)

    /// See `light` for why every value here differs from its counterpart.
    public static let dark = Theme(
        background:       .rgb(0x0B1020),
        surface:          .rgb(0x161C2E),
        surfaceSecondary: .rgb(0x27304A),
        accent:           .rgb(0x60A5FA),
        separator:        .rgb(0x3A4260),
        textPrimary:      .rgb(0xE9EDF5),
        scrollIndicator:  .rgb(0xFFFFFF, alpha: 0.35),
        scrim:            .rgb(0x000000, alpha: 0.42),
        shadow:           Theme.defaultShadow)

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
