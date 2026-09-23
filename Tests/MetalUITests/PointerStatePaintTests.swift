import Testing
import Metal
import MetalUICore
import MetalUILayout
import MetalUIRender
@testable import MetalUI

// What `Box.paint` draws once the pointer and the keyboard have an opinion:
// `Decoration.hoverBackground` and `Decoration.focusBackground`, the token swaps
// that make hover and focus *visible*. Everything else in this repo asserts
// where a hitbox is or which handler ran; nothing before this file asserted that
// any of it changes a pixel.
//
// **Every fixture here goes through a real `Window`**, for `HitboxTests`'
// measured reason: hover resolves inside `Frame.render` at the prepaint/paint
// boundary, from a `mousePosition` that only `Window.drawFrameIfNeeded` threads
// in, so a `Frame` built by hand with a literal `mousePosition:` is blind to the
// one line that connects an actual mouse event to a painted colour.

private func px(_ v: Float) -> Pixels { Pixels(v) }

private func pt(_ x: Float, _ y: Float) -> Point<Pixels> {
    Point(x: Pixels(x), y: Pixels(y))
}

private func mouseMoved(to position: Point<Pixels>) -> InputEvent {
    .mouseMoved(MouseEvent(position: position))
}

/// The 40x40 rect the fixtures below key on. Every other rect in those scenes
/// is a different size, so this identifies the button without depending on
/// emission order.
private func buttonRect(_ scene: Scene) throws -> MUIRect {
    try #require(scene.rects.first {
        $0.bounds.size.width == 40 && $0.bounds.size.height == 40
    })
}

/// Whether `rect` was filled with `token` out of `theme`.
///
/// Component-wise because `MUIHsla` is a C struct with no `Equatable` — the
/// same reason `GlyphEmitterTests` compares its four fields by hand.
private func isFilled(_ rect: MUIRect, with token: ColorToken, in theme: Theme) -> Bool {
    let want = theme[token]
    return rect.background.h == want.h && rect.background.s == want.s
        && rect.background.l == want.l && rect.background.a == want.a
}

/// A hovered element paints `hoverBackground`, and an unhovered one paints
/// `background` — through the production wiring, not a hand-built `Frame`.
///
/// **The two halves are one test on purpose.** "Paints the hover token" alone
/// is satisfied by a `Box.paint` that ignores `isHovered` and always prefers
/// `hoverBackground` when one is declared, which is a real and plausible
/// mistake (`decoration.hoverBackground ?? decoration.background`, with the
/// query dropped). The first assertion — the *same* element, the *same* frame
/// loop, before any mouse event has ever reached the window — is what rules
/// that out. The three tokens are distinct by `Theme`'s own asserted invariant
/// (`noTwoTokensCollideWithinAVariant`), so neither answer can be right by
/// coincidence.
///
/// `(20, 50)` rather than `(20, 20)`: `Row` centres on the cross axis (ruling
/// EP-8), so a 40pt-tall child of a 100pt-tall root occupies y = 30…70 — the
/// same geometry `aMouseMovedEventMakesTheBoxUnderItHoveredOnTheNextFrame`
/// relies on.
///
/// Stage 6b (`LR-DG`, R-fill): every `auto` axis of the window's root carries
/// the window's extent (`.width`/`.height`, `Self`-returning — no layer, no id
/// level). The legacy root filled those axes itself (`CS-I`, divergence 4) and
/// sat at (0, 0); under the proposal authority a hugging root is centred at its
/// own answer (`CN-J`), so the literals below — written for a top-left root —
/// hold on both authorities only with the fill spelled.
@Test @MainActor func aHoveredBoxPaintsItsHoverBackground() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 100) {
        Row {
            Box()
                .width(px(40)).height(px(40))
                .background(.surface)
                .hoverBackground(.accent)
                .onClick {}
        }.width(px(100)).height(px(100))
    }
    window.drawFrameIfNeeded()
    let cold = try buttonRect(window.lastScene)
    #expect(isFilled(cold, with: .surface, in: window.theme),
            "no mouse event has reached the window, so the plain background is what paints")

    platformWindow.simulateInput(mouseMoved(to: pt(20, 50)))
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    let hovered = try buttonRect(window.lastScene)
    #expect(isFilled(hovered, with: .accent, in: window.theme),
            "the frame after mouseMoved fills the box under the pointer with its hover token")
}

/// A `hoverBackground` on an element with no `onClick` never paints, because
/// nothing registers a hitbox for it to be hovered *through*.
///
/// **The inert-API shape, pinned rather than only documented.** `Handlers`
/// gates hitbox registration on `onClick` alone (`isPointerTarget`), so
/// `.hoverBackground(.accent)` with no click handler is an API that compiles,
/// reads as an affordance and does nothing — CLAUDE.md's declared-but-inert
/// shape arrived at by composition instead of by omission. This is the
/// differential against `aHoveredBoxPaintsItsHoverBackground` above: identical
/// geometry, identical mouse event, identical tokens, and the *only*
/// difference is the missing `.onClick {}`.
@Test @MainActor func hoverBackgroundWithoutAClickHandlerNeverPaints() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 100) {
        Row {
            Box()
                .width(px(40)).height(px(40))
                .background(.surface)
                .hoverBackground(.accent)
        }
    }
    window.drawFrameIfNeeded()
    #expect(window.lastHitboxes.isEmpty,
            "no onClick, so nothing registered a hitbox — which is why the hover cannot resolve")

    platformWindow.simulateInput(mouseMoved(to: pt(20, 50)))
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    #expect(isFilled(try buttonRect(window.lastScene), with: .surface, in: window.theme),
            "the pointer is squarely over it and it still paints its plain background")
}

/// Focus outranks hover: an element that is **both** paints `focusBackground`.
///
/// **The ordering is a decision and this is where it is checkable**
/// (`Decoration.focusBackground`'s doc carries the reasoning). Hover follows
/// the pointer and a user recovers it by moving; focus is where the keyboard is
/// pointing and has no other indication. Reversing the two `??` operands in
/// `Box.paint` makes a focused element lose its only affordance exactly when
/// the pointer happens to rest on it — which is when a user is about to type.
///
/// **The fixture puts the element in all three states in one window**, which is
/// what makes it a precedence test rather than three separate ones: plain,
/// then hovered-and-unfocused, then hovered-and-focused. Without the middle
/// step, "focus wins" would be indistinguishable from "hover never worked
/// here".
///
/// `Window.focus(_:)` takes the element's own `GlobalElementID`, which is read
/// back off the registered hitbox rather than reconstructed — a hand-built path
/// would pass whatever this test believed the identity to be, and pass equally
/// well if the framework disagreed.
///
/// Stage 6b (`LR-DG`, R-fill): every `auto` axis of the window's root carries
/// the window's extent (`.width`/`.height`, `Self`-returning — no layer, no id
/// level). The legacy root filled those axes itself (`CS-I`, divergence 4) and
/// sat at (0, 0); under the proposal authority a hugging root is centred at its
/// own answer (`CN-J`), so the literals below — written for a top-left root —
/// hold on both authorities only with the fill spelled.
@Test @MainActor func focusOutranksHoverWhenAnElementIsBoth() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 100) {
        Row {
            Box()
                .width(px(40)).height(px(40))
                .background(.surface)
                .hoverBackground(.accent)
                .focusBackground(.separator)
                .focusable()
                .onClick {}
        }.width(px(100)).height(px(100))
    }
    window.drawFrameIfNeeded()
    #expect(isFilled(try buttonRect(window.lastScene), with: .surface, in: window.theme),
            "neither hovered nor focused")

    platformWindow.simulateInput(mouseMoved(to: pt(20, 50)))
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    #expect(isFilled(try buttonRect(window.lastScene), with: .accent, in: window.theme),
            "hovered and unfocused: the hover token, so the middle state is real")

    let button = try #require(window.lastHitboxes.first).id
    window.focus(button)
    window.drawFrameIfNeeded()
    #expect(isFilled(try buttonRect(window.lastScene), with: .separator, in: window.theme),
            "hovered AND focused: focus wins")
}

/// Hovering one click target does **not** light up its sibling.
///
/// **Written because a mutation reddened nothing.** Replacing
/// `PaintPass.isHovered(_ id: GlobalElementID)`'s body with
/// `frame.hoveredElement != nil` — an element-blind "is anything hovered" —
/// left the suite green as it stood before this test existed (733 at the time
/// it was measured; 736 at the end of the milestone, re-taken). Not because the
/// assertions above are weak: every other fixture in this file has exactly
/// **one** hoverable element, and with one element "this one is hovered" and
/// "something is hovered" are the same proposition. Ruling MP-J's shape — the
/// fixture could not express the defect, and the assertion strength was never
/// what was missing.
///
/// The mutant was proved to behave differently before this test was banked: it
/// makes the 30x30 box below paint `.accent` while the pointer sits squarely on
/// the 40x40 one. Re-run on the finished suite it reddens **this test alone**.
///
/// **Two different sizes rather than two ids**, so each rect is found by a
/// property of its own geometry and the test never depends on emission order.
@Test @MainActor func hoveringOneClickTargetDoesNotHoverItsSibling() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 100) {
        Row {
            Box()
                .width(px(40)).height(px(40))
                .background(.surface).hoverBackground(.accent).onClick {}
            Box()
                .width(px(30)).height(px(30))
                .background(.surface).hoverBackground(.accent).onClick {}
        }
    }
    window.drawFrameIfNeeded()
    try #require(window.lastHitboxes.count == 2, "both boxes register a click target")

    // (20, 50) is inside the first box (x 0…40, y 30…70 after `Row`'s cross-axis
    // centring) and outside the second (x 40…70).
    platformWindow.simulateInput(mouseMoved(to: pt(20, 50)))
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()

    let sibling = try #require(window.lastScene.rects.first {
        $0.bounds.size.width == 30 && $0.bounds.size.height == 30
    })
    #expect(isFilled(try buttonRect(window.lastScene), with: .accent, in: window.theme),
            "the box under the pointer is hovered")
    #expect(isFilled(sibling, with: .surface, in: window.theme),
            "and its sibling, which is not under the pointer, keeps its plain background")
}

/// A `focusBackground` paints only while the element actually holds focus, and
/// clearing focus takes it away again.
///
/// **The second half is the one that catches a real mistake.** `isFocused`
/// reads `Frame.focusedElement`, which `Frame.resolveFocus()` may clear at the
/// prepaint/paint boundary; a `Box.paint` that cached the answer, or a `Window`
/// that never handed the cleared value back, would light the affordance up and
/// leave it on. "It turns on" is the assertion a wrong implementation passes.
@Test @MainActor func focusBackgroundPaintsOnlyWhileFocusIsHeld() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, _) = try makeFakeWindow(device: device, size: 100) {
        Row {
            Box()
                .width(px(40)).height(px(40))
                .background(.surface)
                .focusBackground(.separator)
                .focusable()
                .onClick {}
        }
    }
    window.drawFrameIfNeeded()
    let button = try #require(window.lastHitboxes.first).id
    #expect(isFilled(try buttonRect(window.lastScene), with: .surface, in: window.theme))

    window.focus(button)
    window.drawFrameIfNeeded()
    #expect(isFilled(try buttonRect(window.lastScene), with: .separator, in: window.theme),
            "focused")

    window.focus(nil)
    window.drawFrameIfNeeded()
    #expect(isFilled(try buttonRect(window.lastScene), with: .surface, in: window.theme),
            "and unfocusing puts the plain background back")
}
