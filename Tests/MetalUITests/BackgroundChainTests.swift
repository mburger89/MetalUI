import Testing
import Metal
import MetalUICore
import MetalUILayout
import MetalUIRender
@testable import MetalUI

// The `focusBackground ?? hoverBackground ?? background` chain on EVERY
// conformer that fills its own background — `Box.paint`, `Stack.paint` and
// `Text.paint`, the three background `pass.fill` sites. `Column`, `Row` and
// `List` forward paint to a wrapped `Box` and so reach the `Box` arm.
//
// **Why a file of its own rather than two more arms somewhere else.**
// `hoverBackground(_:)` and `focusBackground(_:)` are declared on
// `extension StyledElement`, so they compile on all of those types; until this
// file existed only `Box.paint` read either field, and `Stack` and `Text`
// painted their plain `background` whatever the pointer or the keyboard said.
// Nothing noticed, for two different reasons:
//
// - `PointerStatePaintTests` — the file that asserts a hover or focus token
//   reaches a pixel — has only `Box` fixtures.
// - `everyBackgroundPaintingSiteAnimatesItsColour` (`AnimationTests.swift`) has
//   one arm per site, but its arms declare no `onClick` and no `focusable()`,
//   so none of them is ever hovered or focused and the chain collapses to
//   `background` on all three whether or not a site honours it.
//
// So every arm below is GENUINELY hovered or focused, through a real `Window`:
// a pointer event reaching `Window.drawFrameIfNeeded`'s `mousePosition` and a
// `Window.focus(_:)` call, resolved by `Frame.render` at the prepaint/paint
// boundary — `PointerStatePaintTests`' measured reason for not hand-building a
// `Frame`. The `Box` arm is the control: it was green before the fix, and the
// `Stack` and `Text` arms were red, so the arms disagree about the unfixed
// source rather than agreeing by construction.

private func px(_ v: Float) -> Pixels { Pixels(v) }

private func pt(_ x: Float, _ y: Float) -> Point<Pixels> {
    Point(x: Pixels(x), y: Pixels(y))
}

private func mouseMoved(to position: Point<Pixels>) -> InputEvent {
    .mouseMoved(MouseEvent(position: position))
}

/// The subject's 40x40 background rect. Found by size rather than by emission
/// order, so a `Text`'s glyphs or a `Stack`'s child can never be mistaken for
/// it — neither emits a 40x40 rect.
private func subjectRect(_ scene: Scene) throws -> MUIRect {
    try #require(scene.rects.first {
        $0.bounds.size.width == 40 && $0.bounds.size.height == 40
    }, "the subject painted no 40x40 background rect")
}

/// Whether `rect` was filled with exactly `token` out of `theme`.
private func isFilled(_ rect: MUIRect, with token: ColorToken, in theme: Theme) -> Bool {
    let want = theme[token]
    return rect.background.h == want.h && rect.background.s == want.s
        && rect.background.l == want.l && rect.background.a == want.a
}

/// A readable name for a rect's fill, for failure messages only.
private func describe(_ rect: MUIRect, in theme: Theme) -> String {
    for (name, token) in [("surface", ColorToken.surface), ("accent", .accent),
                          ("separator", .separator)] where isFilled(rect, with: token, in: theme) {
        return name
    }
    return "(h \(rect.background.h), s \(rect.background.s), l \(rect.background.l))"
}

/// One subject per background-painting site, each declaring all three tokens,
/// a click handler (what makes hover resolvable at all) and `focusable()` (what
/// keeps `Frame.resolveFocus()` from clearing the focus this test moves).
///
/// The three tokens are distinct by `Theme`'s own asserted invariant
/// (`noTwoTokensCollideWithinAVariant`), so no state can read right by
/// coincidence.
@MainActor private enum Subject {
    static func box() -> some Element {
        Box().cssWidth(px(40)).cssHeight(px(40))
            .background(.surface).hoverBackground(.accent).focusBackground(.separator)
            .focusable().onClick {}
    }
    static func stack() -> some Element {
        Stack { Box() }.cssWidth(px(40)).cssHeight(px(40))
            .background(.surface).hoverBackground(.accent).focusBackground(.separator)
            .focusable().onClick {}
    }
    static func text() -> some Element {
        Text("hi").cssWidth(px(40)).cssHeight(px(40))
            .background(.surface).hoverBackground(.accent).focusBackground(.separator)
            .focusable().onClick {}
    }
    /// Ruling MC-I: a `.padding`/`.frame` chain is ONE `ModifiedElement` that
    /// registers and paints each layer in a loop, so it gets two subjects over
    /// a two-layer chain. Here the INNER layer (padding 5 around a 30x30 box)
    /// is the 40x40 subject, at (8, 8) inside the outermost padding-8 layer,
    /// which declares no background and no handler — so the one hitbox and the
    /// one 40x40 rect are the inner layer's. The outermost layer is sized
    /// 56x56 so the root does not stretch it to the window.
    static func modifiedInner() -> some Element {
        Box().cssWidth(px(30)).cssHeight(px(30))
            .padding(Edges(all: .pixels(px(5))))
            .background(.surface).hoverBackground(.accent).focusBackground(.separator)
            .focusable().onClick {}
            .padding(Edges(all: .pixels(px(8))))
            .cssWidth(px(56)).cssHeight(px(56))
    }
    /// The same chain with the subject on the OUTERMOST layer (40x40 at the
    /// origin) and nothing declared on the inner one.
    static func modifiedOutermost() -> some Element {
        Box().cssWidth(px(24)).cssHeight(px(24))
            .padding(Edges(all: .pixels(px(4))))
            .padding(Edges(all: .pixels(px(4))))
            .cssWidth(px(40)).cssHeight(px(40))
            .background(.surface).hoverBackground(.accent).focusBackground(.separator)
            .focusable().onClick {}
    }
}

/// Each background-painting site paints `focusBackground` while focused,
/// `hoverBackground` while hovered, focus over hover when both, and
/// `background` otherwise.
///
/// **Five states in one window, in an order chosen so each neighbouring pair
/// differs in one input.** Plain; focused with the pointer elsewhere (so a site
/// that honoured hover alone is red here); focused AND hovered (focus must
/// win, so a reversed chain is red here); hovered with focus cleared (so a site
/// that honoured focus alone is red here); and plain again, so a site that
/// latched a token rather than re-reading the state each frame is red at the
/// end.
@Test @MainActor func everyBackgroundPaintingSiteHonoursHoverAndFocus() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())

    func check<E: Element>(_ site: String,
                           _ make: @escaping @MainActor () -> E) throws {
        // Stage 6b (`LR-DG`, R-centre — predicted "centre"): every subject's
        // root declares both axes, so it is centred in the 100x100 window — the
        // 40x40 subjects at 30..70, `modifiedInner`'s 56x56 chain at 22..78 with
        // its 40x40 inner layer at 30..70 — and (50, 50) is inside each where
        // the legacy top-left root read (20, 20); (80, 80) is off every one.
        let (window, platformWindow) = try makeFakeWindow(device: device, size: 100,
                                                          content: make)
        let theme = window.theme
        func expectFill(_ token: ColorToken, _ state: String) throws {
            let rect = try subjectRect(window.lastScene)
            #expect(isFilled(rect, with: token, in: theme),
                    "\(site), \(state): painted \(describe(rect, in: theme))")
        }

        window.drawFrameIfNeeded()
        try expectFill(.surface, "neither hovered nor focused")
        // Read back off the registered hitbox rather than reconstructed, for
        // `focusOutranksHoverWhenAnElementIsBoth`'s reason: a hand-built path
        // passes whatever this test believes the identity to be.
        let hitboxes = window.lastHitboxes
        try #require(hitboxes.count == 1,
                     "\(site): set up — onClick registers exactly one hitbox, got \(hitboxes.count)")
        let id = hitboxes[0].id

        window.focus(id)
        window.drawFrameIfNeeded()
        try expectFill(.separator, "focused, pointer elsewhere")

        platformWindow.simulateInput(mouseMoved(to: pt(50, 50)))
        window.setNeedsRedraw()
        window.drawFrameIfNeeded()
        try expectFill(.separator, "focused AND hovered — focus outranks hover")

        window.focus(nil)
        window.drawFrameIfNeeded()
        try expectFill(.accent, "hovered, focus cleared")

        platformWindow.simulateInput(mouseMoved(to: pt(80, 80)))
        window.setNeedsRedraw()
        window.drawFrameIfNeeded()
        try expectFill(.surface, "neither again, pointer moved off")
    }

    try check("Box", Subject.box)
    try check("Stack", Subject.stack)
    try check("Text", Subject.text)
    try check("ModifiedElement inner layer", Subject.modifiedInner)
    try check("ModifiedElement outermost layer", Subject.modifiedOutermost)
}

/// **The RESOLVED token is what animates, on every site** — one value, not
/// three fields (`AnimatedColor.swift`'s top doc). A hover or focus change made
/// under a transaction fades on `Stack` and `Text` exactly as it does on `Box`.
///
/// Driven through the production hand-off rather than the lexical slot:
/// `withAnimation { window.focus(id) }` parks the transaction because `focus`
/// dirties the window, and the next display-link tick's frame consumes it. The
/// hover arm wraps the pointer event the same way, with an explicit
/// `setNeedsRedraw()` — nothing in the framework parks a transaction around
/// pointer-move handling (CLAUDE.md's animation section), so this is a caller
/// choosing to, which is the only way a hover fade is reachable today.
///
/// The mid-flight assertion is deliberately "neither endpoint", not a
/// hand-computed midpoint: the interpolation arithmetic is pinned by
/// `AnimationTests.swift`, and what this test owns is whether the chain's
/// output reaches `animatedColor` at all. A site that snapped its hover or
/// focus token — by resolving the chain AFTER the helper, or by not resolving
/// it — reads an endpoint on the halfway frame.
@Test @MainActor func everyBackgroundPaintingSiteFadesItsResolvedHoverAndFocusColour() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())

    func check<E: Element>(_ site: String, _ state: String, to target: ColorToken,
                           _ make: @escaping @MainActor () -> E,
                           change: (Window, FakePlatformWindow, GlobalElementID) -> Void) throws {
        // Stage 6b (`LR-DG`, R-centre): as in the test above, every root is
        // centred and (50, 50) is inside each subject.
        let (window, platformWindow) = try makeFakeWindow(device: device, size: 100,
                                                          startsDisplayLink: true,
                                                          content: make)
        let theme = window.theme

        platformWindow.simulateTick(timestamp: 100)
        let resting = try subjectRect(window.lastScene)
        try #require(isFilled(resting, with: .surface, in: theme),
                     "\(site) \(state): set up — the resting token, got \(describe(resting, in: theme))")
        let hitboxes = window.lastHitboxes
        try #require(hitboxes.count == 1, "\(site) \(state): set up — one hitbox")
        let id = hitboxes[0].id

        withAnimation(.linear(duration: 1)) { change(window, platformWindow, id) }

        platformWindow.simulateTick(timestamp: 100.2)
        let start = try subjectRect(window.lastScene)
        #expect(isFilled(start, with: .surface, in: theme),
                "\(site) \(state): the frame that starts the fade reads its own `from`, got \(describe(start, in: theme))")
        #expect(window.hasActiveAnimations,
                "\(site) \(state): a \(state) change under a transaction must be an active animation")

        platformWindow.simulateTick(timestamp: 100.7)
        let mid = try subjectRect(window.lastScene)
        #expect(!isFilled(mid, with: .surface, in: theme) && !isFilled(mid, with: target, in: theme),
                "\(site) \(state): halfway through the fade must be neither endpoint, got \(describe(mid, in: theme))")

        platformWindow.simulateTick(timestamp: 101.3)
        let landed = try subjectRect(window.lastScene)
        #expect(isFilled(landed, with: target, in: theme),
                "\(site) \(state): lands exactly on the resolved token, got \(describe(landed, in: theme))")
        #expect(!window.hasActiveAnimations, "\(site) \(state): settled")
    }

    // Each site written out rather than looped over an erased element: an
    // `AnyElement` would put the subject behind a wrapper this test is not
    // about (CLAUDE.md's inert table has a row for it).
    func focusAndHover<E: Element>(_ site: String,
                                   _ make: @escaping @MainActor () -> E) throws {
        try check(site, "focus", to: .separator, make) { window, _, id in
            window.focus(id)
        }
        try check(site, "hover", to: .accent, make) { window, platformWindow, _ in
            platformWindow.simulateInput(mouseMoved(to: pt(50, 50)))
            window.setNeedsRedraw()
        }
    }
    try focusAndHover("Box", Subject.box)
    try focusAndHover("Stack", Subject.stack)
    try focusAndHover("Text", Subject.text)
    try focusAndHover("ModifiedElement inner layer", Subject.modifiedInner)
    try focusAndHover("ModifiedElement outermost layer", Subject.modifiedOutermost)
}
