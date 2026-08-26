import Testing
import Metal
import MetalUICore
import MetalUILayout
import MetalUIRender
import MetalUIShaderTypes
@testable import MetalUI

// Spec §7.9. Two halves, and they fail independently:
//
// 1. The **values** — a theme whose two variants share a number is untestable at
//    that point, so a `background`/`surface` mix-up would paint correctly and
//    mean nothing. Swept token by token below rather than spot-checked.
// 2. The **wiring** — that a `ColorToken` written at a call site becomes the
//    frame's theme's colour in the scene, and that swapping the host appearance
//    swaps what the next frame paints.

/// `MUIHsla` is a C struct with no `Equatable`, so comparisons go through this.
private func hsla(_ c: MUIHsla) -> Hsla { Hsla(h: c.h, s: c.s, l: c.l, a: c.a) }

// MARK: - The values

/// The brief's requirement: light and dark must differ in **values a test can
/// distinguish**.
///
/// Swept over `allCases` rather than written out, so a token added later is
/// covered the day it is added rather than the day someone remembers this file.
@Test func everyTokenDiffersBetweenLightAndDark() {
    for token in ColorToken.allCases {
        #expect(Theme.light[token] != Theme.dark[token],
                "\(token) holds the same colour in both variants, so nothing downstream can tell the two themes apart at that token")
    }
}

/// The other half, and the one that is easy to leave out: two tokens with the
/// same value inside one variant are indistinguishable *within* a frame, so a
/// `surface`/`surfaceSecondary` swap in an element would paint correctly.
@Test func noTwoTokensCollideWithinAVariant() {
    for (name, theme) in [("light", Theme.light), ("dark", Theme.dark)] {
        let values = Set(ColorToken.allCases.map { theme[$0] })
        #expect(values.count == ColorToken.allCases.count,
                "two tokens share a colour in the \(name) variant")
    }
}

/// Every arm of the subscript's `switch` asserted separately, against a theme
/// whose five colours differ in every component.
///
/// `Theme.light` cannot do this job: a transposed arm — `.surface` returning
/// `surfaceSecondary` — would still return *a* plausible colour, and only
/// distinct authored values make the swap visible.
@Test func theSubscriptReturnsEachTokensOwnProperty() {
    let theme = Theme(
        background:       Hsla(h: 0.10, s: 0.11, l: 0.12, a: 0.13),
        surface:          Hsla(h: 0.20, s: 0.21, l: 0.22, a: 0.23),
        surfaceSecondary: Hsla(h: 0.30, s: 0.31, l: 0.32, a: 0.33),
        accent:           Hsla(h: 0.40, s: 0.41, l: 0.42, a: 0.43),
        separator:        Hsla(h: 0.50, s: 0.51, l: 0.52, a: 0.53))

    #expect(theme[.background] == theme.background)
    #expect(theme[.surface] == theme.surface)
    #expect(theme[.surfaceSecondary] == theme.surfaceSecondary)
    #expect(theme[.accent] == theme.accent)
    #expect(theme[.separator] == theme.separator)

    // …and pinned to literals too, because the five expectations above all pass
    // against a subscript that returns `background` for every token *if* the
    // properties themselves were transposed on the way in.
    #expect(theme[.background].h == 0.10)
    #expect(theme[.surface].h == 0.20)
    #expect(theme[.surfaceSecondary].h == 0.30)
    #expect(theme[.accent].h == 0.40)
    #expect(theme[.separator].h == 0.50)
    #expect(theme[.separator].a == 0.53)
}

/// The single place the two variants are chosen between. Returning `light`
/// unconditionally here is Step 5's second mutation, and it reddens this test
/// and `aHostAppearanceChangeSwapsTheThemeAndRepaints` below.
@Test func darkAppearanceSelectsTheDarkTheme() {
    #expect(Theme.forAppearance(.dark) == Theme.dark)
    #expect(Theme.forAppearance(.light) == Theme.light)
    // Not the same answer for both inputs — the assertion the mutation is about.
    #expect(Theme.forAppearance(.dark) != Theme.forAppearance(.light))
}

// MARK: - Token to pixel: what an element's background actually resolves to

@MainActor
@Test func aBoxResolvesItsBackgroundTokenAgainstTheFramesTheme() {
    var element = Box().width(Pixels(30)).height(Pixels(20)).background(.accent)
    let frame = Frame(contentSize: Size(width: Pixels(30), height: Pixels(20)),
                      scaleFactor: 1, theme: .dark)
    frame.render(&element)

    #expect(frame.scene.rects.count == 1)
    let painted = hsla(frame.scene.rects[0].background)

    // Three separate claims, because each fails for a different bug: the right
    // token, the right theme, and not the other theme's answer for that token.
    #expect(painted == Theme.dark.accent)
    #expect(painted != Theme.dark.surface, "the subscript ignored the token")
    #expect(painted != Theme.light.accent, "the frame resolved against the wrong theme")
}

@MainActor
@Test func theSameElementPaintsDifferentColoursUnderTheTwoThemes() {
    // The end-to-end form of the claim above: one element value, two frames.
    // Nothing about the element changes between them — which is what makes a
    // theme swap a repaint rather than a rebuild.
    func paintedBackground(theme: Theme) -> Hsla {
        var element = Box().width(Pixels(10)).height(Pixels(10)).background(.surfaceSecondary)
        let frame = Frame(contentSize: Size(width: Pixels(10), height: Pixels(10)),
                          scaleFactor: 1, theme: theme)
        frame.render(&element)
        return hsla(frame.scene.rects[0].background)
    }

    #expect(paintedBackground(theme: .light) == Theme.light.surfaceSecondary)
    #expect(paintedBackground(theme: .dark) == Theme.dark.surfaceSecondary)
    #expect(paintedBackground(theme: .light) != paintedBackground(theme: .dark))
}

@MainActor
@Test func anElementWithNoBackgroundEmitsNoPrimitiveAtAll() {
    // `nil` is not "fill with transparent". A transparent fill would still cost
    // a rect, and rects are what the per-frame budget is spent on — so this is
    // the difference between a spacer costing nothing and costing a draw.
    var element = Box().width(Pixels(30)).height(Pixels(20))
    let frame = Frame(contentSize: Size(width: Pixels(30), height: Pixels(20)), scaleFactor: 1)
    frame.render(&element)

    #expect(frame.scene.rects.isEmpty)
}

@MainActor
@Test func aContainerPaintsItsBackgroundBeneathItsChildren() {
    // Every rect is emitted at `order: 0` and `Scene.finalize()` sorts stably,
    // so emission sequence *is* paint order. A container that emitted after its
    // children would cover them — and the layout would still be perfect, so
    // only this ordering assertion can see it.
    var element = Column(gap: Pixels(0)) {
        Box().height(Pixels(10)).background(.accent)
    }
    .width(Pixels(50)).height(Pixels(40)).background(.surface)

    let frame = Frame(contentSize: Size(width: Pixels(50), height: Pixels(40)),
                      scaleFactor: 1, theme: .light)
    frame.render(&element)

    let rects = frame.finalizedScene().rects
    #expect(rects.count == 2)
    #expect(hsla(rects[0].background) == Theme.light.surface, "the container must paint first")
    #expect(hsla(rects[1].background) == Theme.light.accent)

    // And the container is the *bigger* one, so this cannot pass by accident on
    // two rects that happen to be in the right colour order.
    #expect(rects[0].bounds.size.height == 40)
    #expect(rects[1].bounds.size.height == 10)
}

@MainActor
@Test func cornersAreScaledPerCornerAndNotTransposed() {
    // Four distinct radii, asserted one by one: `cornerRadius(_:)` sets all four
    // equal, and a uniform set cannot detect a transposition inside
    // `Corners.scaled(by:)` (practices doc, shape 1). `Frame.fill` is internal,
    // which is how this reaches the per-corner form the modifier does not offer.
    let frame = Frame(contentSize: Size(width: Pixels(100), height: Pixels(50)), scaleFactor: 2)
    frame.fill(Bounds(origin: Point(x: Pixels(3), y: Pixels(7)),
                      size: Size(width: Pixels(40), height: Pixels(25))),
               color: .white,
               cornerRadii: Corners(topLeft: Pixels(1), topRight: Pixels(2),
                                    bottomRight: Pixels(3), bottomLeft: Pixels(4)))

    let r = frame.scene.rects[0]
    #expect(r.cornerRadii.topLeft == 2)
    #expect(r.cornerRadii.topRight == 4)
    #expect(r.cornerRadii.bottomRight == 6)
    #expect(r.cornerRadii.bottomLeft == 8)

    // The scale factor reaches the geometry too — otherwise "scaled" above could
    // be pinning a coincidence.
    #expect(r.bounds.origin.x == 6)
    #expect(r.bounds.origin.y == 14)
    #expect(r.bounds.size.width == 80)
    #expect(r.bounds.size.height == 50)
}

@MainActor
@Test func cornerRadiusReachesTheSceneThroughTheModifier() {
    // The per-corner test above goes through `Frame.fill` directly, so on its
    // own it would still pass if `Decoration.cornerRadius` were never read.
    var element = Box().width(Pixels(40)).height(Pixels(20))
        .background(.accent).cornerRadius(Pixels(8))
    let frame = Frame(contentSize: Size(width: Pixels(40), height: Pixels(20)), scaleFactor: 1)
    frame.render(&element)

    #expect(frame.scene.rects[0].cornerRadii.topLeft == 8)
    #expect(frame.scene.rects[0].cornerRadii.bottomRight == 8)
}

// MARK: - The window's half of §7.9

@MainActor
@Test func theWindowOpensInTheHostsAppearance() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let (dark, _) = try makeFakeWindow(device: device, appearance: .dark) {
        Box().background(.surface)
    }
    #expect(dark.theme == Theme.dark)

    // Both directions: a window hard-coded to dark would pass the line above.
    let (light, _) = try makeFakeWindow(device: device, appearance: .light) {
        Box().background(.surface)
    }
    #expect(light.theme == Theme.light)
}

/// §7.9: "System appearance and accent changes swap the active theme and mark
/// §4.4's dirty flag."
///
/// This covers the `Window` half: callback in, theme swapped, dirty flag set,
/// next frame repainted. The AppKit half — that
/// `viewDidChangeEffectiveAppearance` fires at all and reports the right value —
/// is covered separately by
/// `theWindowFollowsTheApplicationsEffectiveAppearance` in
/// `MetalUIPlatformTests`, which drives `NSApplication.shared.appearance`
/// directly. The fake is used here to keep a `Window` test out of
/// application-wide state, not because the real path resists testing.
@MainActor
@Test func aHostAppearanceChangeSwapsTheThemeAndRepaints() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platformWindow) = try makeFakeWindow(device: device, appearance: .light) {
        Box().background(.surface)
    }

    window.drawFrameIfNeeded()
    #expect(!window.needsRedraw)
    let beforeSwap = hsla(window.lastScene.rects[0].background)
    #expect(beforeSwap == Theme.light.surface)

    platformWindow.simulateAppearanceChange(to: .dark)

    #expect(window.theme == Theme.dark)
    #expect(window.needsRedraw, "a theme swap must mark §4.4's dirty flag, or the window shows the old colours until something else invalidates it")

    // And the *next frame* actually carries the new colours. Asserting the theme
    // property alone would pass against a `Frame` built with a stale one.
    window.drawFrameIfNeeded()
    let afterSwap = hsla(window.lastScene.rects[0].background)
    #expect(afterSwap == Theme.dark.surface)
    #expect(afterSwap != beforeSwap)
}

@MainActor
@Test func settingTheThemeToItsCurrentValueDoesNotWakeTheDisplay() throws {
    // The equality guard in `theme`'s `didSet`. AppKit reports tint and contrast
    // changes through the same hook, and a window that repainted for each would
    // wake the display for nothing.
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platformWindow) = try makeFakeWindow(device: device, appearance: .light) {
        Box().background(.surface)
    }
    window.drawFrameIfNeeded()
    #expect(!window.needsRedraw)

    platformWindow.simulateAppearanceChange(to: .light)
    #expect(!window.needsRedraw, "an appearance change that does not cross the light/dark line must not dirty the window")

    // The guard must not be so eager that a real change is swallowed.
    platformWindow.simulateAppearanceChange(to: .dark)
    #expect(window.needsRedraw)
}
