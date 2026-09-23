import Testing
import Metal
import Observation
import MetalUICore
import MetalUILayout
import MetalUIPlatform
import MetalUIRender
@testable import MetalUI

// Lane 2 of plan task 5
// (`docs/superpowers/specs/2026-09-15-outer-modifiers-design.md`): the
// **paint-only decoration** surface — `border`/`hoverBorder`/`focusBorder`,
// `opacity`, `clipped()` — and the two named holes it closes, the focus ring
// (`OM-L`) and a border a caller can actually draw (`OM-B`, `OM-M`).
//
// Rulings: `OM-B`, `OM-G`, `OM-L`, `OM-M`, `OM-N`, `OM-P`, `OM-U`, `OM-V`,
// `OM-W`, `OM-Y`, `OM-AA` in
// `docs/superpowers/2026-09-15-outer-modifiers-decisions.md`. Every SwiftUI
// expectation below cites an arm of `docs/probes/swiftui-border-clip-paint.swift`
// or `docs/probes/swiftui-outer-modifier-order.swift`, recorded 2026-09-15.
//
// **Two tests read PIXELS rather than `MUIRect` fields**, and that is the point
// of them: `aBorderIsPaintedInsideTheElementsBoxAndChangesNoLayout` and
// `aBorderIsVisibleOverAChildThatFillsTheBox` are the proof that the two
// parameters reach the fragment shader and land where SwiftUI's border lands.
// Asserting `rect.borderWidths == 4` would be asserting back the number the
// test itself handed in, which is true of a `Frame.fill` that dropped both
// parameters on the floor.
//
// **Colours are compared against reference RENDERS, never against a
// hand-converted `Hsla`.** `hsla_to_srgba` lives in `shaders.metal` and the
// surface composites in the display's own space; a test that re-derived the
// expected byte triple would be a second implementation of the shader, free to
// agree with itself. Each pixel arm renders the pure token on its own and
// compares bytes, and `#require`s the two references to disagree first.
//
// **The three typecheck guards for this lane live in
// `DecorationCompileGuards.swift`**, because a `@testable` import cannot
// demonstrate a `private(set)` narrowing (taxonomy shape 16).

private func px(_ v: Float) -> Pixels { Pixels(v) }

private func pt(_ x: Float, _ y: Float) -> Point<Pixels> {
    Point(x: Pixels(x), y: Pixels(y))
}

private func why(_ message: String) -> Comment { "\(message)" }

private func mouseMoved(to position: Point<Pixels>) -> InputEvent {
    .mouseMoved(MouseEvent(position: position))
}

@MainActor
private final class ClickCounter {
    var count = 0
    func bump() { count += 1 }
}

/// The BGRA bytes at `(x, y)` of the last frame the fake surface rendered.
@MainActor
private func pixel(_ platform: FakePlatformWindow, _ x: Int, _ y: Int, side: Int) -> [UInt8] {
    let pixels = platform.fakeSurface.readPixels()
    let offset = (y * side + x) * 4
    return Array(pixels[offset..<offset + 4])
}

/// Renders `make` in a fresh `side`x`side` fake window and returns it.
@MainActor
private func render<E: Element>(side: Int = 64, authority: LayoutAuthority = .legacy,
                                _ make: @escaping @MainActor () -> E) throws
    -> (Window, FakePlatformWindow) {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let (window, platform) = try makeFakeWindow(device: device, size: side,
                                                layoutAuthority: authority, content: make)
    window.drawFrameIfNeeded()
    return (window, platform)
}

/// `Row { subject; 1x1 marker }.alignItems(.flexStart)` — the fixture shape
/// record §15's scratch arms and `OuterModifierMatrixTests` both use. The
/// `alignItems` is load-bearing: `Row` centres on the cross axis (EP-8), so
/// without it a subject's cross size is the container's answer rather than the
/// modifier's.
@MainActor
private func inRow<E: Element>(_ make: @escaping @MainActor () -> E) -> some Element {
    Row {
        make()
        Box().width(px(1)).height(px(1)).background(.scrim)
    }.alignItems(.flexStart)
}

/// `inRow` with the window's extent declared on both of the row's axes — stage
/// 6b's R-fill (`LR-DG`). The legacy root filled every `auto` axis with the
/// window (`CS-I`, divergence 4) and sat at (0, 0); a proposal root is centred
/// at its own answer (`CN-J`), so a fixture that reads absolute coordinates off
/// a hugging row spells the window's extent itself. `Self`-returning sizing adds
/// no layer, so identity is unchanged, and the legacy answer is unchanged
/// because it is the one `CS-I` computed.
@MainActor
private func inFilledRow<E: Element>(side: Int,
                                     _ make: @escaping @MainActor () -> E) -> some Element {
    Row {
        make()
        Box().width(px(1)).height(px(1)).background(.scrim)
    }.alignItems(.flexStart).width(px(Float(side))).height(px(Float(side)))
}

/// Whether `rect` was filled with exactly `token` out of `theme`, ignoring the
/// alpha — so an opacity scope does not read as a different colour.
@MainActor
private func isFilled(_ rect: MUIRect, with token: ColorToken, in theme: Theme) -> Bool {
    let want = theme[token]
    return rect.background.h == want.h && rect.background.s == want.s
        && rect.background.l == want.l
}

/// Whether `rect`'s BORDER was drawn in exactly `token`.
@MainActor
private func isBordered(_ rect: MUIRect, with token: ColorToken, in theme: Theme) -> Bool {
    let want = theme[token]
    return rect.borderColor.h == want.h && rect.borderColor.s == want.s
        && rect.borderColor.l == want.l && rect.borderColor.a > 0
}

/// Where each primitive sits in the **finalized** paint order, across both
/// arrays.
///
/// `Scene` stores rects and glyphs in two arrays (one pipeline each) and
/// `finalize()` restores a total order over both in `drawList`. A `Text`'s
/// border is a rect and its content is glyphs, so "the border is emitted after
/// the content" is a claim about that merged order and cannot be read off
/// either array's own indices.
private func paintPositions(_ scene: Scene) -> (rects: [Int], glyphs: [Int]) {
    var rects = [Int](repeating: -1, count: scene.rects.count)
    var glyphs = [Int](repeating: -1, count: scene.glyphs.count)
    var next = 0
    for run in scene.drawList {
        for i in run.start..<(run.start + run.count) {
            switch run.kind {
            case .rect: rects[i] = next
            case .glyph: glyphs[i] = next
            }
            next += 1
        }
    }
    return (rects, glyphs)
}

/// What one site's CONTENT reads: the alpha it was emitted with, the clip it was
/// emitted under, and where it sits in the finalized paint order.
private struct ContentReading {
    var alpha: Float
    var mask: MUIBounds
    var position: Int
}

private func describe(_ b: MUIBounds) -> String {
    "[\(b.origin.x) \(b.origin.y) \(b.size.width)x\(b.size.height)]"
}

private func describe(_ r: MUIRect) -> String {
    let b = r.bounds
    let m = r.contentMask
    let w = r.borderWidths
    return "[\(b.origin.x) \(b.origin.y) \(b.size.width)x\(b.size.height)]"
        + " bg(\(r.background.h),\(r.background.s),\(r.background.l),\(r.background.a))"
        + " border(\(w.top),\(w.right),\(w.bottom),\(w.left))"
        + " borderColor(\(r.borderColor.h),\(r.borderColor.s),\(r.borderColor.l),\(r.borderColor.a))"
        + " mask[\(m.origin.x) \(m.origin.y) \(m.size.width)x\(m.size.height)]"
}

/// The one rect whose bounds are `w` x `h`. Found by size rather than by index
/// so a marker, a glyph or a child can never be mistaken for the subject.
private func rect(_ scene: Scene, _ w: Float, _ h: Float) throws -> MUIRect {
    let matches = scene.rects.filter { $0.bounds.size.width == w && $0.bounds.size.height == h }
    try #require(matches.count == 1,
                 why("expected exactly one \(w)x\(h) rect, got \(matches.count): "
                     + scene.rects.map(describe).joined(separator: " | ")))
    return matches[0]
}

// MARK: - 1, 2, 2a, 3, 3a: where the border draws, and what it costs

/// **A border draws INSIDE the element's box and changes no layout** (`OM-B`).
///
/// Probe `swiftui-border-clip-paint` B1: `red.border(blue, width: 4)` on a 40x40
/// reads the border colour at (1, 1) and (3, 3) and the content at (6, 6) — not
/// centred on the edge and not outset. Probe `swiftui-outer-modifier-order` L2:
/// `.border` leaves a 20x20 leaf 20x20, where `.padding(8)` reads 36x36.
///
/// **This reads PIXELS**, off the fake surface's `.shared` texture, because
/// what is under test is whether `borderColor` and `borderWidths` reach the
/// fragment shader at all. `MUIRect.borderWidths == 4` is the number this test
/// handed in and would read back identically from a `Frame.fill` that dropped
/// both parameters.
///
/// **The two references must disagree before either is believed** (shape 15):
/// a pure-accent and a pure-separator 40x40, rendered on their own. If the two
/// tokens composited to the same bytes, "the corner is the border colour" and
/// "the centre is the fill" would both hold against an element that drew one
/// flat colour.
@Test @MainActor func aBorderIsPaintedInsideTheElementsBoxAndChangesNoLayout() throws {
    let side = 64
    @MainActor func box() -> Box<EmptyGroup> { Box().width(px(40)).height(px(40)) }

    let (_, fillOnly) = try render(side: side) {
        inFilledRow(side: side) { box().background(.accent) }
    }
    let (_, borderOnly) = try render(side: side) {
        inFilledRow(side: side) { box().background(.separator) }
    }
    let accentByte = pixel(fillOnly, 20, 20, side: side)
    let separatorByte = pixel(borderOnly, 20, 20, side: side)
    try #require(accentByte != separatorByte,
                 why("set up — the two reference tokens must composite to different bytes, "
                     + "or every assertion below holds against one flat colour. accent "
                     + "\(accentByte), separator \(separatorByte)"))

    let (window, platform) = try render(side: side) {
        inFilledRow(side: side) { box().background(.accent).border(.separator, width: px(4)) }
    }
    #expect(pixel(platform, 1, 1, side: side) == separatorByte,
            why("SwiftUI B1: the border colour at (1, 1). got \(pixel(platform, 1, 1, side: side))"))
    #expect(pixel(platform, 3, 3, side: side) == separatorByte,
            why("SwiftUI B1: still the border at (3, 3), one point inside the 4pt width. got "
                + "\(pixel(platform, 3, 3, side: side))"))
    #expect(pixel(platform, 6, 6, side: side) == accentByte,
            why("SwiftUI B1: the CONTENT at (6, 6) — the border is inside the box, not centred "
                + "on the edge and not outset. got \(pixel(platform, 6, 6, side: side))"))
    #expect(pixel(platform, 20, 20, side: side) == accentByte,
            "and the centre is the fill")

    // Layout-neutral, SwiftUI L2. The marker is the element after the subject in
    // the row, so its x IS the subject's outer width.
    let (bare, _) = try render(side: side) { inFilledRow(side: side) { box().background(.accent) } }
    let bareMarker = try rect(bare.lastScene, 1, 1)
    let borderedMarker = try rect(window.lastScene, 1, 1)
    #expect(borderedMarker.bounds.origin.x == bareMarker.bounds.origin.x,
            why("SwiftUI L2: a border adds no layout. bare marker at "
                + "\(bareMarker.bounds.origin.x), bordered at \(borderedMarker.bounds.origin.x)"))
}

/// **The background is emitted BEFORE the children and the border AFTER them**
/// (`OM-V`).
///
/// This replaces `aBackgroundAndABorderAreOneEmittedRect`, the shape the first
/// draft of the spec specified: one `MUIRect` carrying both. Probe arm B3 is
/// what inverted it — SwiftUI's `.border` is an **overlay**, and a child filling
/// the box does not hide it, so a single emission before the children cannot be
/// SwiftUI's answer. `aBorderIsVisibleOverAChildThatFillsTheBox` below is the
/// pixel half; this is the emission-order half, which is what a mutation that
/// swapped the two would move.
///
/// Three rects, identified by size and by what they carry rather than by index:
/// the parent's 40x40 fill, the child's 20x20 fill, the parent's 40x40 border.
@Test @MainActor func aBackgroundIsEmittedBeforeTheChildrenAndABorderAfter() throws {
    let (window, _) = try render {
        inRow {
            Box { Box().width(px(20)).height(px(20)).background(.surface) }
                .width(px(40)).height(px(40))
                .background(.accent).border(.separator, width: px(4))
        }
    }
    let theme = window.theme
    let rects = window.lastScene.rects
    let all = rects.map(describe).joined(separator: " | ")

    let backgroundIndex = try #require(rects.firstIndex {
        $0.bounds.size.width == 40 && isFilled($0, with: .accent, in: theme)
    }, why("the parent painted no accent background: " + all))
    let childIndex = try #require(rects.firstIndex {
        $0.bounds.size.width == 20 && isFilled($0, with: .surface, in: theme)
    }, why("the child painted no rect: " + all))
    let borderIndex = try #require(rects.firstIndex {
        isBordered($0, with: .separator, in: theme)
    }, why("nothing painted a separator border: " + all))

    // The three must be three, or "before" and "after" are claims about one
    // rect compared with itself.
    try #require(Set([backgroundIndex, childIndex, borderIndex]).count == 3,
                 why("set up — background, child and border must be three distinct emissions; "
                     + "got \(backgroundIndex), \(childIndex), \(borderIndex): " + all))

    #expect(backgroundIndex < childIndex,
            why("the background is emitted BEFORE the children — emission order is paint order, "
                + "so a fill after them would paint over them. got \(backgroundIndex) and "
                + "\(childIndex)"))
    #expect(childIndex < borderIndex,
            why("and the border AFTER them (OM-V, probe B3: SwiftUI's border is an overlay). "
                + "got \(childIndex) and \(borderIndex)"))
}

/// **A border is visible over a child that fills the whole box** — probe arm
/// **B3**, and the defect `OM-V` exists to prevent.
///
/// `Color.clear.frame(40, 40).overlay(red).border(blue, width: 4)` reads the
/// border colour at the corner in SwiftUI. If MetalUI emitted one rect before
/// its children, a child filling the box would cover the ring completely — and
/// the shape a caller writes for a focus ring is exactly
/// `Box { content }.focusBorder(…)`, so the ring would be invisible on the one
/// call it exists for, with no diagnostic anywhere.
///
/// A pixel test rather than an emission-order one, because emission order is
/// only a proxy for "can you see it".
@Test @MainActor func aBorderIsVisibleOverAChildThatFillsTheBox() throws {
    let side = 64
    let (_, separatorRef) = try render(side: side) {
        inFilledRow(side: side) { Box().width(px(40)).height(px(40)).background(.separator) }
    }
    let (_, accentRef) = try render(side: side) {
        inFilledRow(side: side) { Box().width(px(40)).height(px(40)).background(.accent) }
    }
    let separatorByte = pixel(separatorRef, 1, 1, side: side)
    let accentByte = pixel(accentRef, 1, 1, side: side)
    try #require(separatorByte != accentByte,
                 why("set up — the two tokens must composite differently: \(separatorByte) vs "
                     + "\(accentByte)"))

    let (_, platform) = try render(side: side) {
        inFilledRow(side: side) {
            Box { Box().width(px(40)).height(px(40)).background(.accent) }
                .width(px(40)).height(px(40))
                .border(.separator, width: px(4))
        }
    }
    let corner = pixel(platform, 1, 1, side: side)
    #expect(corner == separatorByte,
            why("probe B3: a child filling the whole box must NOT hide the border. Reading the "
                + "child's colour here means the border was emitted before the children, which "
                + "is a focus ring that is sometimes not drawn. got \(corner), border "
                + "\(separatorByte), child \(accentByte)"))
    #expect(pixel(platform, 20, 20, side: side) == accentByte,
            "and the child still fills the middle")
}

/// **An element with neither a background nor a border emits no rect at all.**
///
/// `Decoration`'s own rule, and the reason `nil` is not "a transparent colour":
/// rects are what the renderer's per-frame budget is spent on, and a helper that
/// filled unconditionally would make every `Box` in a tree a primitive.
@Test @MainActor func anElementWithNeitherABackgroundNorABorderEmitsNoRect() throws {
    let (window, _) = try render {
        inRow { Box().width(px(40)).height(px(40)) }
    }
    let rects = window.lastScene.rects
    // The marker is the control: if the fixture had not painted at all, "no
    // 40x40 rect" would be true for the wrong reason.
    try #require(rects.contains { $0.bounds.size.width == 1 },
                 why("set up — the 1x1 marker must have painted: "
                     + rects.map(describe).joined(separator: " | ")))
    #expect(!rects.contains { $0.bounds.size.width == 40 },
            why("an undecorated Box must emit nothing: "
                + rects.map(describe).joined(separator: " | ")))
}

/// **A background-only element still emits exactly ONE rect** — `OM-V`'s cost
/// bound.
///
/// Two rects only when a border resolves. `OM-O`'s budget argument survives its
/// own supersession: the demo declares sixteen corner radii and no border at
/// all, so the second emission costs it nothing.
@Test @MainActor func aBackgroundOnlyElementStillEmitsExactlyOneRect() throws {
    let (plain, _) = try render {
        inRow { Box().width(px(40)).height(px(40)).background(.accent) }
    }
    let plainCount = plain.lastScene.rects.filter { $0.bounds.size.width == 40 }.count
    #expect(plainCount == 1,
            why("a background-only element costs one rect, got \(plainCount): "
                + plain.lastScene.rects.map(describe).joined(separator: " | ")))

    // The disagreeing arm: the bordered case must cost two, or "exactly one"
    // would also pass against a helper that never emits a border.
    let (bordered, _) = try render {
        inRow {
            Box().width(px(40)).height(px(40)).background(.accent)
                .border(.separator, width: px(4))
        }
    }
    let borderedCount = bordered.lastScene.rects.filter { $0.bounds.size.width == 40 }.count
    #expect(borderedCount == 2,
            why("and a bordered one costs two, got \(borderedCount): "
                + bordered.lastScene.rects.map(describe).joined(separator: " | ")))
}

// MARK: - 4, 5, 6: every site, and the chain

/// One subject per decoration-painting site, each declaring all three border
/// fields with **distinct tokens**, a click handler (what makes hover
/// resolvable at all) and `focusable()` (what keeps `Frame.resolveFocus()` from
/// clearing the focus these tests move).
///
/// The shape is `BackgroundChainTests`' `Subject`, one chain over; the two
/// `ModifiedElement` arms are there for `MC-I`'s reason — a `.padding`/`.frame`
/// chain is ONE element that paints each layer, so it needs a subject with the
/// decoration on an inner layer and one with it on the outermost.
@MainActor private enum BorderSubject {
    static func box() -> some Element {
        Box().width(px(40)).height(px(40))
            .border(.surface, width: px(4)).hoverBorder(.accent, width: px(4))
            .focusBorder(.separator, width: px(4))
            .focusable().onClick {}
    }
    static func stack() -> some Element {
        Stack { Box() }.width(px(40)).height(px(40))
            .border(.surface, width: px(4)).hoverBorder(.accent, width: px(4))
            .focusBorder(.separator, width: px(4))
            .focusable().onClick {}
    }
    static func text() -> some Element {
        Text("hi").width(px(40)).height(px(40))
            .border(.surface, width: px(4)).hoverBorder(.accent, width: px(4))
            .focusBorder(.separator, width: px(4))
            .focusable().onClick {}
    }
    /// The INNER layer of a two-layer chain is the 40x40 subject, at (8, 8)
    /// inside an undecorated padding-8 layer.
    static func modifiedInner() -> some Element {
        Box().width(px(30)).height(px(30))
            .padding(Edges(all: .pixels(px(5))))
            .border(.surface, width: px(4)).hoverBorder(.accent, width: px(4))
            .focusBorder(.separator, width: px(4))
            .focusable().onClick {}
            .padding(Edges(all: .pixels(px(8))))
            .width(px(56)).height(px(56))
    }
    /// The same chain with the decoration on the OUTERMOST layer.
    static func modifiedOutermost() -> some Element {
        Box().width(px(24)).height(px(24))
            .padding(Edges(all: .pixels(px(4))))
            .padding(Edges(all: .pixels(px(4))))
            .width(px(40)).height(px(40))
            .border(.surface, width: px(4)).hoverBorder(.accent, width: px(4))
            .focusBorder(.separator, width: px(4))
            .focusable().onClick {}
    }
}

/// **Every decoration-painting site draws its border** (`OM-P`).
///
/// One arm per site: `Box`, `Stack`, `Text` and a `ModifiedElement` layer.
/// Dropping the `paintDecoration` call at any ONE of them reddens exactly that
/// arm — which is the failure mode this repo has already shipped twice, once
/// when the `focusBackground ?? hoverBackground ?? background` chain lived in
/// `Box.paint` alone (`BackgroundChainTests`' own header) and once when the AX
/// gate did.
@Test @MainActor func everyDecorationPaintingSiteDrawsItsBorder() throws {
    @MainActor func check<E: Element>(_ site: String, _ make: @escaping @MainActor () -> E) throws {
        let (window, _) = try render(side: 100) { make() }
        let theme = window.theme
        let all = window.lastScene.rects.map(describe).joined(separator: " | ")
        let bordered = window.lastScene.rects.filter { isBordered($0, with: .surface, in: theme) }
        try #require(bordered.count == 1,
                     why("\(site): expected exactly one rect carrying the plain border, got "
                         + "\(bordered.count): " + all))
        #expect(bordered[0].bounds.size.width == 40 && bordered[0].bounds.size.height == 40,
                why("\(site): the border is drawn at the element's own 40x40 box; got "
                    + describe(bordered[0])))
        #expect(bordered[0].borderWidths.top == 4 && bordered[0].borderWidths.right == 4
                    && bordered[0].borderWidths.bottom == 4 && bordered[0].borderWidths.left == 4,
                why("\(site): with the declared widths; got " + describe(bordered[0])))
    }
    try check("Box", BorderSubject.box)
    try check("Stack", BorderSubject.stack)
    try check("Text", BorderSubject.text)
    try check("ModifiedElement inner layer", BorderSubject.modifiedInner)
    try check("ModifiedElement outermost layer", BorderSubject.modifiedOutermost)
}

/// **A focus ring outranks a hover border, and both outrank a plain border**
/// (`OM-L`) — the same precedence `focusBackground` states one chain over, and
/// stated once rather than twice: `effectiveForPointerState` is shared.
///
/// Five states in one window, in an order where each neighbouring pair differs
/// in one input — `BackgroundChainTests`' shape. Plain; focused with the
/// pointer elsewhere (so a site honouring hover alone is red here); focused AND
/// hovered (focus must win, so a reversed chain is red here); hovered with focus
/// cleared (so a site honouring focus alone is red here); and plain again, so a
/// site that latched a token rather than re-reading the state each frame is red
/// at the end.
@Test @MainActor func aFocusRingOutranksAHoverBorderAndABorder() throws {
    // Stage 6b (`LR-DG`, R-centre): the 40x40 root is centred in the 100x100
    // window at (100 - 40) / 2 = 30, so the hover point is (50, 50) where the
    // legacy top-left root read (20, 20); (80, 80) is off it on both.
    let (window, platform) = try render(side: 100, authority: .proposal) { BorderSubject.box() }
    let theme = window.theme

    @MainActor func expectBorder(_ token: ColorToken, _ state: String) throws {
        let all = window.lastScene.rects.map(describe).joined(separator: " | ")
        let bordered = try #require(window.lastScene.rects.first { $0.borderColor.a > 0 },
                                    why("\(state): nothing painted a border at all: " + all))
        #expect(isBordered(bordered, with: token, in: theme),
                why("\(state): expected the \(token) border; got " + describe(bordered)))
    }

    try expectBorder(.surface, "neither hovered nor focused")
    let hitboxes = window.lastHitboxes
    try #require(hitboxes.count == 1,
                 "set up — onClick registers exactly one hitbox, got \(hitboxes.count)")
    let id = hitboxes[0].id

    window.focus(id)
    window.drawFrameIfNeeded()
    try expectBorder(.separator, "focused, pointer elsewhere")

    platform.simulateInput(mouseMoved(to: pt(50, 50)))
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    try expectBorder(.separator, "focused AND hovered — focus outranks hover")

    window.focus(nil)
    window.drawFrameIfNeeded()
    try expectBorder(.accent, "hovered, focus cleared")

    platform.simulateInput(mouseMoved(to: pt(80, 80)))
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    try expectBorder(.surface, "neither again, pointer moved off")
}

/// **Every decoration-painting site honours the border's hover and focus
/// chain**, not only `Box`.
///
/// `aFocusRingOutranksAHoverBorderAndABorder` above proves the precedence on one
/// site; this proves the chain is consulted at all five. The distinction is the
/// one `BackgroundChainTests` exists for: `hoverBorder`/`focusBorder` are
/// declared on `extension StyledElement`, so they compile on every conformer,
/// and a site that resolved `decoration.border` alone would paint the plain
/// border forever with no diagnostic.
///
/// Every arm is GENUINELY hovered or focused, through a real `Window`.
@Test @MainActor func everyDecorationPaintingSiteHonoursTheBorderHoverAndFocusChain() throws {
    @MainActor func check<E: Element>(_ site: String,
                                      _ make: @escaping @MainActor () -> E) throws {
        // Stage 6b (`LR-DG`, R-centre — predicted "fill", but every subject
        // declares both axes): each root is centred in the 100x100 window — the
        // 40x40 subjects at 30..70, `modifiedInner`'s 56x56 chain at 22..78 with
        // its bordered inner layer at 30..70 — so (50, 50) is inside every one.
        let (window, platform) = try render(side: 100, authority: .proposal) { make() }
        let theme = window.theme

        @MainActor func borderToken(_ state: String) throws -> MUIRect {
            let all = window.lastScene.rects.map(describe).joined(separator: " | ")
            return try #require(window.lastScene.rects.first { $0.borderColor.a > 0 },
                                why("\(site), \(state): nothing painted a border: " + all))
        }

        let plain = try borderToken("resting")
        try #require(isBordered(plain, with: .surface, in: theme),
                     why("\(site): set up — the resting border is the plain one; got "
                         + describe(plain)))

        let hitboxes = window.lastHitboxes
        try #require(hitboxes.count == 1, "\(site): set up — one hitbox")
        window.focus(hitboxes[0].id)
        window.drawFrameIfNeeded()
        let focused = try borderToken("focused")
        #expect(isBordered(focused, with: .separator, in: theme),
                why("\(site): a focused element draws its focusBorder; got "
                    + describe(focused)))

        window.focus(nil)
        platform.simulateInput(mouseMoved(to: pt(50, 50)))
        window.setNeedsRedraw()
        window.drawFrameIfNeeded()
        let hovered = try borderToken("hovered")
        #expect(isBordered(hovered, with: .accent, in: theme),
                why("\(site): a hovered element draws its hoverBorder; got "
                    + describe(hovered)))
    }
    try check("Box", BorderSubject.box)
    try check("Stack", BorderSubject.stack)
    try check("Text", BorderSubject.text)
    try check("ModifiedElement inner layer", BorderSubject.modifiedInner)
    try check("ModifiedElement outermost layer", BorderSubject.modifiedOutermost)
}

// MARK: - the SCOPE half, per site

/// **Every decoration-scoping site puts its own content INSIDE the scope**
/// (`OM-AI`) — the opacity, the clip, and the border's position relative to the
/// content.
///
/// `everyDecorationPaintingSiteDrawsItsBorder` above is the *emission* guard: it
/// sees whether a site calls `paintDecoration` at all. It cannot see the shape
/// of the call, and the shape is half the helper. A site that keeps the call and
/// paints its content **outside** the `content()` closure —
///
/// ```swift
/// pass.paintDecoration(decoration, in: bounds, for: id) { }
/// content.paintGroup(layout: &layout.content, prepaint: &prepaint, pass: &pass)
/// ```
///
/// — still draws its border at the right box with the right widths, still fades
/// its own fill, and is wrong in three ways at once: the children are not faded,
/// the children are not clipped, and the border lands **under** them, which is
/// the focus ring invisible on the exact call it exists for (`OM-V`). That
/// mutation was applied at `Stack.paint` and at `Text.paint` and the whole suite
/// stayed green, which is what this test exists for: measured in the mutated
/// tree, `Stack { Box().background(.accent) }.opacity(0.5)` emitted its child at
/// alpha **1.0** where the unmutated tree emits **0.5**, and
/// `Text("hi").background(.accent).opacity(0.5)` emitted glyph alphas **1.0**
/// where the unmutated tree emits **0.5** — with the element's own background
/// rect still reading 0.5 in both, which is exactly why the emission guard
/// cannot see it.
///
/// One arm per site, each with a content emission that is a **separate**
/// primitive from the element's own decoration: a 60x60 `flexShrink(0)` child
/// that overflows the 40x40 subject (so the clip has something to cut), and for
/// `Text` the glyphs. The `ModifiedElement` arm is a **two-layer** chain with
/// the decoration on the outermost layer, for `OM-AD`'s reason — a one-layer
/// chain cannot tell a scope that contains the layers inside it from one that
/// contains only the content.
@Test @MainActor func everyDecorationScopingSiteContainsItsOwnContent() throws {
    @MainActor func check<E: Element>(
        _ site: String,
        _ make: @escaping @MainActor (_ opacity: Float, _ clipped: Bool, _ bordered: Bool) -> E,
        read: @escaping @MainActor (Scene) throws -> ContentReading
    ) throws {
        @MainActor func reading(_ opacity: Float, _ clipped: Bool,
                                _ bordered: Bool) throws -> (ContentReading, Scene) {
            let (window, _) = try render(side: 200) {
                inFilledRow(side: 200) { make(opacity, clipped, bordered) }
            }
            return (try read(window.lastScene), window.lastScene)
        }

        // (i) the content is inside the OPACITY scope.
        let (plain, _) = try reading(1, false, false)
        try #require(plain.alpha > 0,
                     why("\(site): set up — the content must paint at all, got \(plain.alpha)"))
        let (faded, _) = try reading(0.5, false, false)
        #expect(abs(faded.alpha - plain.alpha * 0.5) < 0.001,
                why("\(site): the element's opacity scope must contain its own CONTENT, not "
                    + "only its own fill (OM-N, OM-AI): expected \(plain.alpha * 0.5), got "
                    + "\(faded.alpha)"))

        // (ii) the content is inside the CLIP. The unclipped arm is the control:
        // without it, "the mask is the element's box" would also hold for a mask
        // that was always the element's box.
        try #require(plain.mask.size.width == 200 && plain.mask.size.height == 200,
                     why("\(site): set up — without `.clipped()` the content's mask is the whole "
                         + "surface; got " + describe(plain.mask)))
        let (clipped, _) = try reading(1, true, false)
        #expect(clipped.mask.origin.x == 0 && clipped.mask.origin.y == 0
                    && clipped.mask.size.width == 40 && clipped.mask.size.height == 40,
                why("\(site): `.clipped()` must cut the CONTENT to the element's own 40x40 box; "
                    + "got " + describe(clipped.mask)))

        // (iii) the border is emitted AFTER the content, in the order that
        // survives `finalize()` across both primitive arrays.
        let (content, scene) = try reading(1, false, true)
        let positions = paintPositions(scene)
        let borderIndex = try #require(scene.rects.firstIndex { $0.borderColor.a > 0 },
                                       why("\(site): nothing painted a border: "
                                           + scene.rects.map(describe).joined(separator: " | ")))
        #expect(positions.rects[borderIndex] > content.position,
                why("\(site): the border is an OVERLAY (OM-V, probe B3) — it must be painted "
                    + "after this element's own content. border at "
                    + "\(positions.rects[borderIndex]), content at \(content.position)"))
    }

    /// The 60x60 child, wherever the site put it.
    @MainActor func readChildRect(_ scene: Scene) throws -> ContentReading {
        let positions = paintPositions(scene)
        let index = try #require(scene.rects.firstIndex {
            $0.bounds.size.width == 60 && $0.bounds.size.height == 60
        }, why("no 60x60 content rect: " + scene.rects.map(describe).joined(separator: " | ")))
        return ContentReading(alpha: scene.rects[index].background.a,
                              mask: scene.rects[index].contentMask,
                              position: positions.rects[index])
    }

    /// A `Text`'s content is its glyphs, and **all** of them must agree — one
    /// faded glyph and one opaque one would be a scope that closed early.
    @MainActor func readGlyphs(_ scene: Scene) throws -> ContentReading {
        let positions = paintPositions(scene)
        try #require(scene.glyphs.count >= 2,
                     why("set up — the text must have shaped at least two glyphs, got "
                         + "\(scene.glyphs.count)"))
        let first = scene.glyphs[0]
        try #require(scene.glyphs.allSatisfy {
            $0.color.a == first.color.a
                && $0.contentMask.origin.x == first.contentMask.origin.x
                && $0.contentMask.size.width == first.contentMask.size.width
        }, why("the glyphs disagree about their alpha or their clip: "
               + scene.glyphs.map { "a=\($0.color.a) mask" + describe($0.contentMask) }
                   .joined(separator: " | ")))
        // The LAST glyph's position, so "the border is after the content" is a
        // claim about all of them.
        let last = positions.glyphs.max() ?? -1
        return ContentReading(alpha: first.color.a, mask: first.contentMask, position: last)
    }

    @MainActor func boxSite(_ opacity: Float, _ clipped: Bool, _ bordered: Bool)
        -> Box<Box<EmptyGroup>> {
        var subject = Box {
            Box().width(px(60)).height(px(60)).flexShrink(0).background(.surface)
        }.width(px(40)).height(px(40))
        if opacity < 1 { subject = subject.opacity(opacity) }
        if clipped { subject = subject.clipped() }
        if bordered { subject = subject.border(.separator, width: px(4)) }
        return subject
    }

    @MainActor func stackSite(_ opacity: Float, _ clipped: Bool, _ bordered: Bool)
        -> Stack<Box<EmptyGroup>> {
        var subject = Stack {
            Box().width(px(60)).height(px(60)).flexShrink(0).background(.surface)
        }.width(px(40)).height(px(40))
        if opacity < 1 { subject = subject.opacity(opacity) }
        if clipped { subject = subject.clipped() }
        if bordered { subject = subject.border(.separator, width: px(4)) }
        return subject
    }

    @MainActor func textSite(_ opacity: Float, _ clipped: Bool, _ bordered: Bool) -> Text {
        var subject = Text("hi").width(px(40)).height(px(40))
        if opacity < 1 { subject = subject.opacity(opacity) }
        if clipped { subject = subject.clipped() }
        if bordered { subject = subject.border(.separator, width: px(4)) }
        return subject
    }

    /// TWO layers, the decoration on the outermost: `.padding(2)` is the inner
    /// layer and `.frame(40x40)` the outer one, so a scope that reached only its
    /// own layer's content would miss the child entirely (`OM-AD`).
    @MainActor func modifiedSite(_ opacity: Float, _ clipped: Bool, _ bordered: Bool)
        -> ModifiedElement<Box<EmptyGroup>> {
        var subject = Box().width(px(60)).height(px(60)).flexShrink(0).background(.surface)
            .padding(Edges(all: .pixels(px(2))))
            .frame(width: px(40), height: px(40))
        if opacity < 1 { subject = subject.opacity(opacity) }
        if clipped { subject = subject.clipped() }
        if bordered { subject = subject.border(.separator, width: px(4)) }
        return subject
    }

    try check("Box", boxSite, read: readChildRect)
    try check("Stack", stackSite, read: readChildRect)
    try check("Text", textSite, read: readGlyphs)
    try check("ModifiedElement outermost layer", modifiedSite, read: readChildRect)
}

// MARK: - `.border` x `.cornerRadius`: OM-W's divergence

/// **PINNED WRONG ON PURPOSE.** MetalUI's rounded border follows the corner
/// arc; SwiftUI's `.border(w).cornerRadius(r)` clips a **square** border by the
/// radius, leaving the arc's interior unbordered (`OM-W`).
///
/// Probe `swiftui-border-clip-paint`, the two arms added in design review round
/// 2:
///
///     D2 red.border(blue, 4).cornerRadius(12) : arc(5,5)=rgb(1.00,0.15,0.00)  ← the FILL
///     M1 RoundedRect(12) fill+strokeBorder 4  : arc(5,5)=rgb(0.02,0.20,1.00)  ← the BORDER
///
/// M1 is MetalUI's single emission written in SwiftUI. The two agree at all five
/// of the points the first recording sampled — the corner and (3, 3) outside the
/// arc, (6, 6) and the centre deep inside, the edge midpoint border in both — so
/// the first draft of the spec called them the same answer on evidence that
/// could not have seen a difference. (5, 5) is inside the outer arc (distance
/// 9.9 from the arc's centre, radius 12) and outside the inner one (inner radius
/// 8), which is what makes it the discriminating point.
///
/// Not expressible on the legacy path: `border` and `cornerRadius` are fields of
/// one `Decoration`, so their relative order is not observable at all. A caller
/// who needs SwiftUI's answer puts a `Box` between them.
@Test @MainActor func aRoundedBorderFollowsTheArcWhereSwiftUIsClippedSquareBorderDoesNot() throws {
    let side = 64
    let (_, fillRef) = try render(side: side) {
        inFilledRow(side: side) { Box().width(px(40)).height(px(40)).background(.accent) }
    }
    let (_, borderRef) = try render(side: side) {
        inFilledRow(side: side) { Box().width(px(40)).height(px(40)).background(.separator) }
    }
    let fillByte = pixel(fillRef, 20, 20, side: side)
    let borderByte = pixel(borderRef, 20, 20, side: side)
    try #require(fillByte != borderByte,
                 why("set up — the two tokens must composite differently: \(fillByte) vs "
                     + "\(borderByte)"))

    let (_, platform) = try render(side: side) {
        inFilledRow(side: side) {
            Box().width(px(40)).height(px(40)).background(.accent)
                .border(.separator, width: px(4)).cornerRadius(px(12))
        }
    }
    // The control, first: the modifier IS live at the edge midpoint, where
    // SwiftUI's D2 also reads the border. Without it, "the arc reads the
    // border" could be true of an element drawing one flat border everywhere.
    try #require(pixel(platform, 20, 1, side: side) == borderByte,
                 why("set up — the top edge's midpoint must be the border in both frameworks "
                     + "(probe D2 topmid); got \(pixel(platform, 20, 1, side: side))"))
    #expect(pixel(platform, 1, 1, side: side) != borderByte,
            why("and the corner OUTSIDE the arc must not be the border — the radius is live; "
                + "got \(pixel(platform, 1, 1, side: side))"))

    let arc = pixel(platform, 5, 5, side: side)
    #expect(arc == borderByte,
            why("DIVERGENCE (OM-W): MetalUI's rounded stroke follows the arc, so (5, 5) is the "
                + "BORDER. SwiftUI's D2 reads the FILL there — it clips a square border by the "
                + "radius and leaves the arc's interior unbordered. got \(arc), border "
                + "\(borderByte), fill \(fillByte)"))
}

// MARK: - 7, 8, 10a: opacity

/// **Two opacity SCOPES multiply, and a scope fades the element's own
/// background** — probe arms G1, G2 and G3.
///
/// G1/G2: `red.opacity(0.5)` samples rgb(1.00,0.58,0.58) over white and
/// `.opacity(0.5).opacity(0.5)` samples rgb(1.00,0.80,0.80), so two halves
/// compose to a quarter rather than replacing each other. `Frame.activeOpacity`
/// already multiplies; what this pins is that `paintDecoration` opens the scope
/// around the element's **own fill** and not only around its children (`OM-N`).
///
/// **The multiplying arm is NESTED boxes, and SwiftUI's G1/G2 is one view with
/// two `.opacity` calls — that is a substitution, and it is deliberate.** Two
/// `.opacity` calls on ONE MetalUI element write the same `Decoration.opacity`
/// field, so the second REPLACES the first and the pair reads 0.5, not 0.25:
/// `OM-H`'s not-expressible mechanism in its fifth instance, pinned as a
/// divergence by `aSecondOpacityOnOneElementReplacesTheFirstWhereSwiftUIMultiplies`
/// below (`OM-AH`). What multiplies here is two *scopes* — two elements, or two
/// layers of one chain — which is what `Frame.activeOpacity` composes.
///
/// Read off the emitted rect's alpha rather than off pixels: `Frame.fill`
/// multiplies `color.a * activeOpacity` on the way into the scene, so the alpha
/// IS the composition, exactly.
@Test @MainActor func opacityMultipliesAndFadesTheElementsOwnBackground() throws {
    @MainActor func alpha<E: Element>(_ make: @escaping @MainActor () -> E) throws -> Float {
        let (window, _) = try render { inRow { make() } }
        return try rect(window.lastScene, 40, 40).background.a
    }

    let opaque = try alpha { Box().width(px(40)).height(px(40)).background(.accent) }
    try #require(opaque > 0, "set up — the resting token must be visible at all, got \(opaque)")

    let half = try alpha { Box().width(px(40)).height(px(40)).background(.accent).opacity(0.5) }
    #expect(abs(half - opaque * 0.5) < 0.001,
            why("the element's OWN fill is inside its opacity scope (OM-N, probe G3): expected "
                + "\(opaque * 0.5), got \(half)"))

    // Nested, for the multiplication — probe G2, with the substitution this
    // test's doc names: SwiftUI's G2 is one view with two `.opacity` calls,
    // which on the legacy path is `OM-AH`'s divergence, so the multiplying arm
    // here is two SCOPES. The inner box's own fill sees both.
    let quarter = try alpha {
        Box {
            Box().width(px(40)).height(px(40)).background(.accent).opacity(0.5)
        }.opacity(0.5)
    }
    #expect(abs(quarter - opaque * 0.25) < 0.001,
            why("two opacity scopes MULTIPLY rather than replace (probe G1/G2): expected "
                + "\(opaque * 0.25), got \(quarter)"))
    try #require(abs(quarter - half) > 0.001,
                 why("set up — a nested fade must read differently from a single one, or "
                     + "`multiplies` is unfalsifiable here. \(quarter) vs \(half)"))
}

/// **PINNED WRONG ON PURPOSE.** `.opacity(0.5).background(x)` fades the
/// background, where SwiftUI's leaves it opaque (probe arm **G4**) — and where
/// MetalUI's own **proposal** path leaves it opaque too (`OM-N`, `OM-AA` a).
///
/// The mechanism is `OM-H`'s: on the legacy path `opacity` and `background` are
/// fields of one `Decoration`, so the order in which they were written is not
/// observable at all, and only one of the two orders can be right. The one a
/// caller actually writes — fade a whole panel, fill included — was chosen;
/// leaving the fill opaque there would look like a bug at every call site.
///
/// **Two divergences, not one.** Against SwiftUI, and against MetalUI's other
/// element system: a caller porting a subtree between the two paths — which is
/// what plan tasks 6 and 7 are for — would find a fade appear or vanish with no
/// modifier changed. Task 7's unification is the fix.
///
/// The spelling that gets SwiftUI's answer today is a layer between them:
/// `Box { … }.opacity(0.5).background(x)` — a `Box` is a layer, and layers do
/// order.
@Test @MainActor func opacityReachesABackgroundWrittenAfterItWhereSwiftUIDoesNot() throws {
    @MainActor func alpha<E: Element>(_ make: @escaping @MainActor () -> E) throws -> Float {
        let (window, _) = try render { inRow { make() } }
        return try rect(window.lastScene, 40, 40).background.a
    }

    let opaque = try alpha { Box().width(px(40)).height(px(40)).background(.accent) }
    let backgroundFirst = try alpha {
        Box().width(px(40)).height(px(40)).background(.accent).opacity(0.5)
    }
    let opacityFirst = try alpha {
        Box().width(px(40)).height(px(40)).opacity(0.5).background(.accent)
    }

    // The control: an unfaded fill must read differently from a faded one, or
    // "both orders fade" is satisfied by a modifier that does nothing.
    try #require(abs(opaque - backgroundFirst) > 0.001,
                 why("set up — `.opacity(0.5)` must move the alpha at all: opaque \(opaque), "
                     + "faded \(backgroundFirst)"))

    #expect(abs(backgroundFirst - opaque * 0.5) < 0.001,
            why("probe G3, AGREEING: `.background(x).opacity(0.5)` fades the fill. got "
                + "\(backgroundFirst)"))
    #expect(abs(opacityFirst - opaque * 0.5) < 0.001,
            why("DIVERGENCE (OM-N): `.opacity(0.5).background(x)` fades it too. SwiftUI's G4 "
                + "reads the FULL fill, and so does MetalUI's own proposal path, where "
                + "`.opacity` is its own ModifiedContent layer (OM-AA a). got \(opacityFirst)"))
    #expect(abs(opacityFirst - backgroundFirst) < 0.001,
            why("the two orders are not distinguishable on the legacy path at all — both "
                + "modifiers write one Decoration (OM-H). got \(opacityFirst) and "
                + "\(backgroundFirst)"))
}

/// **PINNED WRONG ON PURPOSE.** A second `.opacity` on ONE element **replaces**
/// the first; SwiftUI's G1/G2 multiply (`OM-AH`).
///
/// The fifth instance of `OM-H`'s mechanism, and the one the first draft of the
/// spec's §6.2 matrix filed as an **agreement** ("`.opacity(0.5).opacity(0.5)` |
/// multiplies | G1/G2 | same (`Frame.activeOpacity`)"). `Frame.activeOpacity`
/// does multiply — but nothing puts two values into it here: both calls write
/// `Decoration.opacity`, the last one wins, and the element opens exactly one
/// scope.
///
/// Probe `swiftui-border-clip-paint` G1/G2 is one view:
/// `red.opacity(0.5)` reads rgb(1.00,0.58,0.58) and
/// `red.opacity(0.5).opacity(0.5)` reads rgb(1.00,0.80,0.80).
///
/// **Three arms, because "replaces" needs two things to be true**: the doubled
/// call reads the SAME alpha as the single one, and a shape that genuinely
/// multiplies reads a quarter in the same fixture. The nested arm is the
/// disagreeing one — without it, "0.5 == 0.5" would also hold in a framework
/// where nothing multiplied at all.
///
/// The spelling that multiplies is a scope between the two calls: a nested `Box`,
/// or a layer — `.opacity(0.5).padding(2).opacity(0.5)` reads 0.25, because
/// `.padding` opens a new `ModifierLayer` and the second call configures that.
@Test @MainActor func aSecondOpacityOnOneElementReplacesTheFirstWhereSwiftUIMultiplies() throws {
    @MainActor func alpha<E: Element>(_ make: @escaping @MainActor () -> E) throws -> Float {
        let (window, _) = try render { inRow { make() } }
        return try rect(window.lastScene, 40, 40).background.a
    }

    let once = try alpha { Box().width(px(40)).height(px(40)).background(.accent).opacity(0.5) }
    let twice = try alpha {
        Box().width(px(40)).height(px(40)).background(.accent).opacity(0.5).opacity(0.5)
    }
    let nested = try alpha {
        Box {
            Box().width(px(40)).height(px(40)).background(.accent).opacity(0.5)
        }.opacity(0.5)
    }
    let layered = try alpha {
        Box().width(px(40)).height(px(40)).background(.accent).opacity(0.5)
            .padding(Edges(all: .pixels(px(2))))
            .opacity(0.5)
    }
    let opaque = try alpha { Box().width(px(40)).height(px(40)).background(.accent) }
    try #require(abs(nested - once) > 0.001,
                 why("set up — two SCOPES must read differently from one, or `replaces` below "
                     + "is unfalsifiable. nested \(nested), single \(once)"))

    #expect(abs(twice - once) < 0.001,
            why("DIVERGENCE (OM-AH): a second `.opacity` on the same element REPLACES the first "
                + "— both write one `Decoration` field (OM-H). SwiftUI's G2 composes to a "
                + "quarter. single \(once), doubled \(twice)"))
    #expect(abs(nested - opaque * 0.25) < 0.001,
            why("and the spelling that DOES multiply is two scopes: expected "
                + "\(opaque * 0.25), got \(nested)"))
    #expect(abs(layered - opaque * 0.25) < 0.001,
            why("a LAYER between the two calls multiplies too — `.padding` opens one, and the "
                + "second `.opacity` configures it: expected \(opaque * 0.25), got \(layered)"))
}

/// **An outer layer's opacity and clip contain the layers INSIDE it**, not only
/// the wrapped element.
///
/// This is why `ModifiedElement.paint` is a recursion and not the loop it used
/// to be. The loop emitted every layer's fill in sequence and then painted the
/// content once, which is correct while a `Decoration` is a set of leaf
/// emissions and wrong the moment one of them is a **scope**: an `.opacity` on
/// the outermost layer would leave every inner layer's fill opaque, and a
/// `.clipped()` there would clip nothing but the content.
///
/// The fixture is a two-layer chain — `.padding(4).background(.accent)` is the
/// INNER layer, `.padding(8).opacity(0.5)` the outer — so the faded rect
/// belongs to a layer the scope has to reach across. A one-layer chain cannot
/// see this at all, which is `OM-AD`'s finding in its paint form.
@Test @MainActor func aChainsOuterLayerScopesContainTheLayersInsideIt() throws {
    @MainActor func innerLayerRect(faded: Bool, clipped: Bool) throws -> MUIRect {
        let (window, _) = try render(side: 200) {
            inFilledRow(side: 200) {
                { () -> ModifiedElement<Box<EmptyGroup>> in
                    let chain = Box().width(px(20)).height(px(20))
                        .padding(Edges(all: .pixels(px(4))))
                        .background(.accent)
                        .padding(Edges(all: .pixels(px(8))))
                    let withFade = faded ? chain.opacity(0.5) : chain
                    return clipped ? withFade.clipped() : withFade
                }()
            }
        }
        return try rect(window.lastScene, 28, 28)
    }

    let plain = try innerLayerRect(faded: false, clipped: false)
    let faded = try innerLayerRect(faded: true, clipped: false)
    let clipped = try innerLayerRect(faded: false, clipped: true)

    try #require(plain.bounds.origin.x == 8 && plain.bounds.origin.y == 8,
                 why("set up — the inner layer's 28x28 box sits 8 points inside the outer "
                     + "layer's 44x44, or the two layers are not nested at all; got "
                     + describe(plain)))
    #expect(abs(faded.background.a - plain.background.a * 0.5) < 0.001,
            why("the OUTER layer's opacity fades the INNER layer's fill: expected "
                + "\(plain.background.a * 0.5), got \(faded.background.a)"))
    #expect(clipped.contentMask.size.width == 44 && clipped.contentMask.size.height == 44,
            why("and the outer layer's clip bounds it — the mask is the outer layer's own "
                + "44x44 box, not the surface; got " + describe(clipped)))
    try #require(describe(plain) != describe(clipped),
                 why("set up — the clipped arm must differ from the plain one: "
                     + describe(plain)))
}

/// **A `Deferred` portal inside a faded subtree is still faded** (`OM-AA` b).
///
/// `Deferred` resets the clip stack and the accumulated scroll translation
/// (`AP-I`) and **does not** reset `opacityStack` — `Frame.pushLayer` and
/// `pushRootClip` leave it alone. That was unreachable until `.opacity` existed
/// on the legacy path, so the answer had to be chosen rather than inherited, and
/// today's behaviour is kept: a portal's resets exist because it must not
/// inherit *geometry* it has escaped, and opacity is not geometry. A subtree
/// faded to 0.5 with a tooltip inside it reads as one faded thing, which is what
/// the caller writing the fade meant.
///
/// The escape, if it is ever wanted, is to declare the `Deferred` outside the
/// faded element — a structural change, not a modifier.
///
/// The control is the same portal with no fade above it: without it, "the
/// portal's alpha is half" would also hold for a portal whose own token happened
/// to be semi-transparent.
///
/// **Under both authorities** (plan task 7 stage 5 lane 3, spec 3.7, `LR-CO`).
/// The portal here is **in-flow** — it already lowers to the legacy answer, so no
/// presentation root is involved; the presentation-shaped twin is
/// `aPresentationInsideAFadedSubtreeIsStillFadedUnderBothAuthorities`
/// (`PresentationWindowTests`). The window's root is the row itself, so under the
/// proposal authority it is centred at its answer (`CN-J`); only the alpha is read.
/// Pre-flighted: the same content's differential report is required empty before
/// a proposal window opens (`LR-BX`). Mutation **M3a** (the opacity stack reset
/// by `pass.deferred`) must redden both arms.
@Test(arguments: AuthorityCoverage.authorities) @MainActor
func aDeferredPortalInsideAFadedSubtreeIsStillFaded(_ authority: LayoutAuthority) throws {
    AuthorityCoverage.record(#function, authority)
    @MainActor func portalAlpha(faded: Bool) throws -> Float {
        @MainActor func tree() -> some Element {
            inRow {
                Box {
                    Deferred {
                        Box().width(px(20)).height(px(20)).background(.accent)
                    }
                }
                .width(px(40)).height(px(40))
                .opacity(faded ? 0.5 : 1)
            }
        }
        let preflight = LayoutDifferential.compare(width: 64, height: 64) { tree() }
        try #require(preflight.unlowerable.isEmpty, "\(preflight.unlowerable)")
        let (window, _) = try render(authority: authority) { tree() }
        return try rect(window.lastScene, 20, 20).background.a
    }

    let plain = try portalAlpha(faded: false)
    let faded = try portalAlpha(faded: true)
    try #require(plain > 0, "set up — the portal must paint at all, got \(plain)")
    #expect(abs(faded - plain * 0.5) < 0.001,
            why("OM-AA (b): Deferred resets clip and scroll offset and NOT opacity, so a portal "
                + "inside a faded subtree is faded with it. expected \(plain * 0.5), got \(faded)"))
}

// MARK: - 9, 9a, 10: the clip

/// **`.clipped()` cuts the subtree to the element's own box and rounds the cut
/// by its `cornerRadius`** (`OM-G`).
///
/// The control is `aBareCornerRadiusDoesNotClipTheChildren`'s subject with the
/// modifier removed: a bare `.cornerRadius` pushes no clip at all, so the child
/// keeps the whole surface as its mask. The two arms must disagree before either
/// is believed — a clip that did nothing and a radius that clipped by default
/// would otherwise read the same here.
///
/// `.flexShrink(0)` on the child is load-bearing: without it the 60x60 child is
/// shrunk to its 40pt parent and never overflows, so "clipped" and "unclipped"
/// are the same picture. That was measured on lane 1's first run.
@Test @MainActor func clippedCutsTheSubtreeToTheElementsBoxAndRoundsItByTheCornerRadius() throws {
    @MainActor func childMask(clipped: Bool) throws -> MUIRect {
        let (window, _) = try render(side: 200) {
            inFilledRow(side: 200) {
                { () -> Box<Box<EmptyGroup>> in
                    let box = Box {
                        Box().width(px(60)).height(px(60)).flexShrink(0).background(.surface)
                    }.width(px(40)).height(px(40)).background(.accent).cornerRadius(px(12))
                    return clipped ? box.clipped() : box
                }()
            }
        }
        return try rect(window.lastScene, 60, 60)
    }

    let unclipped = try childMask(clipped: false)
    let clipped = try childMask(clipped: true)
    try #require(describe(unclipped) != describe(clipped),
                 why("set up — the two arms must differ, or `.clipped()` is being asserted "
                     + "against itself. " + describe(unclipped)))
    try #require(unclipped.contentMask.size.width == 200
                    && unclipped.contentMask.size.height == 200,
                 why("set up — without `.clipped()` the child's mask is the whole surface "
                     + "(the bare-cornerRadius divergence); got " + describe(unclipped)))

    #expect(clipped.contentMask.origin.x == 0 && clipped.contentMask.origin.y == 0
                && clipped.contentMask.size.width == 40 && clipped.contentMask.size.height == 40,
            why("`.clipped()` cuts the child to the element's own 40x40 box; got "
                + describe(clipped)))
    #expect(clipped.maskCornerRadii.topLeft == 12 && clipped.maskCornerRadii.topRight == 12
                && clipped.maskCornerRadii.bottomRight == 12
                && clipped.maskCornerRadii.bottomLeft == 12,
            why("and rounds the cut by the element's own cornerRadius — `.cornerRadius(12)"
                + ".clipped()` is the spelling for SwiftUI's `.cornerRadius(12)` (OM-G); got "
                + describe(clipped)))
    #expect(clipped.bounds.size.width == 60,
            "the child is still LAID OUT at 60x60 — a clip is paint, not layout")
}

/// **A `.clipped()` box inside a scrolled `ScrollView` clips where it paints**
/// (`OM-U`) — divergence 15's one-line `Frame.pushClip` fix, seen from the
/// modifier this lane introduced rather than from the nested scroller the
/// divergence was named for.
///
/// This is why the fix was taken here instead of deferred again. Before it,
/// `pushClip` intersected an untranslated rect into a surface-space
/// `activeClip`, so a `.clipped()` row scrolled past the viewport got an empty
/// mask and drew nothing — in a list, every row that had ever scrolled.
///
/// The disagreeing arm is the same tree unscrolled: without it, "the mask
/// follows the paint" would also hold for a mask that never moved.
@Test @MainActor func aClippedBoxInsideAScrolledScrollViewClipsWhereItPaints() throws {
    @MainActor func maskAndPaint(scrollBy steps: Int) throws -> (mask: Float, paint: Float) {
        var style = Style()
        style.flexDirection = .column
        let (window, platform) = try render(side: 200) {
            ScrollView(.vertical, elementID: ElementID("outer")) {
                Box(style: style) {
                    Box().width(px(100)).height(px(150)).flexShrink(0).background(.surface)
                    Box {
                        Box().width(px(100)).height(px(90)).flexShrink(0).background(.accent)
                    }
                    .width(px(100)).height(px(60)).flexShrink(0).clipped()
                    Box().width(px(100)).height(px(150)).flexShrink(0).background(.scrim)
                }
            }
        }
        for _ in 0..<steps {
            platform.simulateInput(.scrollWheel(ScrollEvent(position: pt(100, 20),
                                                            delta: pt(0, -37),
                                                            isMomentum: false)))
            window.drawFrameIfNeeded()
        }
        let child = try rect(window.lastScene, 100, 90)
        return (child.contentMask.origin.y, child.bounds.origin.y)
    }

    let resting = try maskAndPaint(scrollBy: 0)
    let scrolled = try maskAndPaint(scrollBy: 3)
    try #require(resting.paint != scrolled.paint,
                 why("set up — the scroll must have moved the clipped box: resting paint "
                     + "\(resting.paint), scrolled \(scrolled.paint)"))

    #expect(resting.mask == resting.paint,
            why("unscrolled, the clip is at the box (the term this fix adds is a no-op at "
                + "activeOffset 0): mask \(resting.mask), paint \(resting.paint)"))
    #expect(scrolled.mask == scrolled.paint,
            why("OM-U: scrolled, the clip follows the paint. Before the `+ activeOffset` term "
                + "the mask stayed at the ENGINE's y while the box painted elsewhere, and the "
                + "intersection emptied. mask \(scrolled.mask), paint \(scrolled.paint)"))
}

/// **`.clipped()` clips the hitboxes inside it as well as the pixels, at every
/// site that registers children** (`OM-AI`).
///
/// The prepaint half of the clip, and the reason `registerAndScope` exists
/// rather than four copies of a `registerHandlers` call. `ScrollView.prepaint`
/// already pushes its clip on `PrepaintPass`; without the same call here a
/// `.clipped()` box would register click targets outside the region it draws,
/// so a user could click content that is not on screen — visible nowhere,
/// reproducible only by clicking on nothing.
///
/// **One arm per site, and that is the fix for what this test used to be.** It
/// was one `Box` fixture, so passing `Decoration()` to `registerAndScope` at
/// `Stack.prepaint` or at `ModifiedElement.prepaintLayerBody` — each of which
/// keeps the call and drops the scope — reddened **nothing** in the whole suite.
/// `Text` has no children, so its clip scope is a no-op and it has no arm here;
/// the paint-side scope at all four sites is
/// `everyDecorationScopingSiteContainsItsOwnContent`.
///
/// Two readings per arm: the registered region's height, and a real synthesized
/// click below the clip. The click is what makes it a behaviour rather than a
/// stored number.
///
/// **`unclippedRegion` differs per arm and is not a fudge.** `Stack` and
/// `.frame` both centre their content, so the overflowing 60x60 child starts at
/// −10 and `Frame.insertHitbox` intersects it with the root clip before the
/// element's own — 50, not 60. Each arm states its own number, and the
/// `#require` that the two arms disagree is what makes any of them a finding.
@Test @MainActor func clippedAlsoClipsTheHitboxesInsideIt() throws {
    @MainActor func check<E: Element>(
        _ site: String, unclippedRegion: Float,
        _ make: @escaping @MainActor (_ clipped: Bool, _ counter: ClickCounter) -> E
    ) throws {
        @MainActor func measure(clipped: Bool) throws -> (region: Float, clicksBelow: Int) {
            let counter = ClickCounter()
            let device = try #require(MTLCreateSystemDefaultDevice(),
                                      "no Metal device; run on macOS hardware")
            // Stage 6b (`LR-DG`, R-fill): the window's extent declared on the
            // row's two auto axes, so the row sits at (0, 0) on both authorities.
            let (window, platform) = try makeFakeWindow(device: device, size: 200) {
                Row { make(clipped, counter) }.alignItems(.flexStart)
                    .width(px(200)).height(px(200))
            }
            window.drawFrameIfNeeded()
            let boxes = window.lastHitboxes
            try #require(boxes.count == 1,
                         why("\(site): set up — the child registers exactly one hitbox, got "
                             + "\(boxes.count)"))
            // (20, 45) is inside the 60x60 child at every site and below the
            // 40x40 clip at every site.
            platform.simulateInput(.mouseDown(MouseEvent(position: pt(20, 45))))
            platform.simulateInput(.mouseUp(MouseEvent(position: pt(20, 45))))
            return (boxes[0].bounds.size.height.value, counter.count)
        }

        let unclipped = try measure(clipped: false)
        let clipped = try measure(clipped: true)
        try #require(unclipped.region != clipped.region,
                     why("\(site): set up — the two arms must differ: unclipped \(unclipped), "
                         + "clipped \(clipped)"))

        #expect(unclipped.region == unclippedRegion && unclipped.clicksBelow == 1,
                why("\(site): the control — without `.clipped()` the child's whole "
                    + "\(unclippedRegion)pt is hittable and a click at y 45 lands. got "
                    + "\(unclipped)"))
        #expect(clipped.region == 40,
                why("\(site): `.clipped()` registers the child against the clip, not against "
                    + "its own box; got \(clipped.region)"))
        #expect(clipped.clicksBelow == 0,
                why("\(site): and a click below the clip — on content that is not drawn — does "
                    + "not reach the handler; got \(clipped.clicksBelow)"))
    }

    try check("Box", unclippedRegion: 60) { clipped, counter in
        let box = Box {
            Box().width(px(60)).height(px(60)).flexShrink(0)
                .background(.surface).onClick { counter.bump() }
        }.width(px(40)).height(px(40))
        return clipped ? box.clipped() : box
    }
    try check("Stack", unclippedRegion: 50) { clipped, counter in
        let stack = Stack {
            Box().width(px(60)).height(px(60)).flexShrink(0)
                .background(.surface).onClick { counter.bump() }
        }.width(px(40)).height(px(40))
        return clipped ? stack.clipped() : stack
    }
    // TWO layers, the clip on the outermost, for `OM-AD`'s reason.
    try check("ModifiedElement outermost layer", unclippedRegion: 50) { clipped, counter in
        let chain = Box().width(px(60)).height(px(60)).flexShrink(0)
            .background(.surface).onClick { counter.bump() }
            .padding(Edges(all: .pixels(px(2))))
            .frame(width: px(40), height: px(40))
        return clipped ? chain.clipped() : chain
    }
}

// MARK: - 11: the animation deferral

/// **The new paint-only decoration fields SNAP; they do not animate** — the
/// deferral to plan task 13, pinned rather than assumed.
///
/// A second animated colour needs an eighth reserved retention slot beside
/// `$anim-color`: `animColorRetentionSlot(for:)` is one named child per element,
/// so a border stored under it would alias the background's baseline and make a
/// border change retarget the fill's fade.
///
/// **The background is the control, and it is what makes this a finding.** One
/// subject changes its background AND its border under one `withAnimation`; half
/// way through, the background must be at neither endpoint and the border must
/// already be the new token. Without the control arm, "the border is the new
/// token" would also hold for a frame in which nothing animated at all —
/// because the transaction was never parked, because the tick never arrived,
/// because the fixture never changed.
@Test @MainActor func theNewPaintOnlyDecorationFieldsSnapRatherThanAnimate() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let model = BorderFlipModel()
    let (window, platform) = try makeFakeWindow(device: device, size: 100,
                                                startsDisplayLink: true) {
        Box().width(px(40)).height(px(40))
            .background(model.flipped ? .accent : .surface)
            .border(model.flipped ? .accent : .surface, width: px(4))
    }
    let theme = window.theme

    // A decorated element emits TWO 40x40 rects — the background before the
    // children and the border after them (`OM-V`) — so each is found by the
    // field it carries rather than by its size.
    @MainActor func fillAndBorder(_ state: String) throws -> (fill: MUIRect, border: MUIRect) {
        let all = window.lastScene.rects.map(describe).joined(separator: " | ")
        let both = window.lastScene.rects.filter { $0.bounds.size.width == 40 }
        try #require(both.count == 2,
                     why("\(state): a bordered element emits two 40x40 rects, got "
                         + "\(both.count): " + all))
        let fill = try #require(both.first { $0.borderColor.a == 0 },
                                why("\(state): no plain background rect: " + all))
        let border = try #require(both.first { $0.borderColor.a > 0 },
                                  why("\(state): no border rect: " + all))
        return (fill, border)
    }

    platform.simulateTick(timestamp: 100)
    let resting = try fillAndBorder("resting")
    try #require(isFilled(resting.fill, with: .surface, in: theme)
                    && isBordered(resting.border, with: .surface, in: theme),
                 why("set up — both fields rest on the same token; got "
                     + describe(resting.fill) + " / " + describe(resting.border)))

    withAnimation(.linear(duration: 1)) { model.flipped = true }

    // **The frame that STARTS a fade reads its own `from`** (`animatedColor`'s
    // own rule, and `BackgroundChainTests`' shape), so the contrast is at its
    // sharpest here: same element, same transaction, same frame — the
    // background still at the OLD token and the border already at the new one.
    platform.simulateTick(timestamp: 100.2)
    let start = try fillAndBorder("the frame that starts the fade")
    #expect(isFilled(start.fill, with: .surface, in: theme),
            why("THE CONTROL: the background begins its fade at its own `from`; got "
                + describe(start.fill)))
    #expect(isBordered(start.border, with: .accent, in: theme),
            why("DEFERRED to task 13: the border has already SNAPPED to its new token in the "
                + "same frame; got " + describe(start.border)))
    #expect(window.hasActiveAnimations,
            "the background's fade must be live, or `snaps` below is a claim about nothing")

    platform.simulateTick(timestamp: 100.7)
    let mid = try fillAndBorder("mid-flight")
    #expect(!isFilled(mid.fill, with: .surface, in: theme)
                && !isFilled(mid.fill, with: .accent, in: theme),
            why("THE CONTROL: half way through, the background is at neither endpoint; got "
                + describe(mid.fill)))
    #expect(isBordered(mid.border, with: .accent, in: theme),
            why("and the border is still simply the new token — no interpolation at any point; "
                + "got " + describe(mid.border)))
}

/// The model the snap test drives. **`@Observable`, so the write inside
/// `withAnimation` reaches the window through the production dirty path** —
/// `withAnimation` parks its transaction only when a frame build is coming,
/// which it decides from the observation counter, so a plain class here parks
/// nothing, the window never rebuilds, and every frame after the write reads
/// the resting values. Measured: with a plain class the "control" arm read the
/// resting token and the test failed as an instrument rather than as a finding.
@Observable
final class BorderFlipModel {
    var flipped = false
}

// MARK: - 14, 15, 15a: the traps

/// **An opacity above 1 traps at the modifier**, not a frame later inside
/// `PaintPass.opacity` (`OM-Y`).
///
/// **The arm is `1.5` and not a negative, and the reason is measured.**
/// `PaintPass.opacity` already carries `precondition((0...1).contains(value))`,
/// so an exit test that painted with a NEGATIVE opacity would abort whether or
/// not the modifier's own precondition were there — the mutation "remove the
/// modifier's precondition" would redden nothing and the test would pass for the
/// wrong reason over half its input range. A value above 1 does not have that
/// problem: `paintDecoration` opens the opacity scope only when the value is
/// **below** 1, so an unvalidated `1.5` never reaches that precondition at all.
@Test func anOpacityAboveOneTraps() async {
    await #expect(processExitsWith: .failure) {
        _ = await MainActor.run { Box().opacity(1.5) }
    }
    await #expect(processExitsWith: .failure) {
        _ = await MainActor.run { Box().opacity(.nan) }
    }
}

/// **A negative or non-finite border width traps.**
///
/// A negative width reaches `max(halfSize - border, 0.0)` in the fragment
/// shader (`shaders.metal:129-133`) and produces an inner rect LARGER than the
/// outer one — a rect that draws its border colour where its background should
/// be — with no diagnostic anywhere above it. Nothing downstream of
/// `BorderStyle` validates a width, so unlike the opacity case a negative value
/// is exactly the right arm here.
@Test func aNegativeBorderWidthTraps() async {
    await #expect(processExitsWith: .failure) {
        _ = BorderStyle(.accent, width: Pixels(-1))
    }
    await #expect(processExitsWith: .failure) {
        _ = BorderStyle(.accent, widths: Edges(top: Pixels(1), right: Pixels(1),
                                               bottom: Pixels(-1), left: Pixels(1)))
    }
    await #expect(processExitsWith: .failure) {
        _ = BorderStyle(.accent, width: Pixels(.infinity))
    }
}

/// **Both fields are validated where they are WRITTEN, not only where they are
/// initialised** (`OM-Y`).
///
/// The first draft put the preconditions on the `init`s while leaving the fields
/// public stored `var`s, and `Decoration` is public and reachable through
/// `Box(style:decoration:)` — so `var d = Decoration(); d.opacity = 2` and
/// `var b = BorderStyle(.accent, width: px(1)); b.widths = Edges(all: px(-5))`
/// both reached paint unchecked. Two exit tests would then have pinned a door
/// beside an open window.
///
/// The narrowing that makes `setOpacity`/`withWidths` the ONLY ways in is a
/// plain-import typecheck guard —
/// `theValidatedDecorationFieldsAreNotAssignableFromOutsideTheModule` — because
/// a `@testable` test sees the internal setter (taxonomy shape 16).
@Test func aBorderWidthSetAfterInitIsStillValidated() async {
    await #expect(processExitsWith: .failure) {
        _ = BorderStyle(.accent, width: Pixels(1)).withWidths(Edges(all: Pixels(-5)))
    }
}

@Test func anOpacitySetAfterInitIsStillValidated() async {
    await #expect(processExitsWith: .failure) {
        var d = Decoration()
        d.setOpacity(2)
        _ = d
    }
    await #expect(processExitsWith: .failure) {
        _ = Decoration(opacity: 2)
    }
}

/// The positive control for the four exit tests above (ruling CS-C's shape):
/// without it they all pass against a `precondition(false)`, or against a rule
/// that rejected every value including the legitimate ones.
///
/// **Each arm also checks what it admits still behaves, INSIDE the child
/// process, with `precondition` rather than `#expect`** — a bare `_ =` would
/// pass against a modifier that accepted the value and stored nothing.
@Test func theAdmittedOpacitiesAndBorderWidthsBehave() async {
    await #expect(processExitsWith: .success) {
        await MainActor.run {
            // The two endpoints and an interior value: 0 means invisible, not
            // invalid, and 1 is the default.
            for value in [Float(0), 0.5, 1] {
                let box = Box().opacity(value)
                precondition(box.decoration.opacity == value,
                             "opacity(\(value)) must be stored, got \(box.decoration.opacity)")
            }
            // Zero is a legitimate border width — "no border on this edge" —
            // and a very wide one is legitimate too.
            let zero = BorderStyle(.accent, width: Pixels(0))
            precondition(zero.widths.top.value == 0)
            let wide = BorderStyle(.accent, widths: Edges(top: Pixels(0), right: Pixels(4),
                                                          bottom: Pixels(1000), left: Pixels(0.5)))
            precondition(wide.widths.bottom.value == 1000 && wide.widths.left.value == 0.5,
                         "the per-edge widths must be stored as given")
            precondition(wide.withWidths(Edges(all: Pixels(2))).widths.right.value == 2,
                         "withWidths must produce the new widths")
            var decoration = Decoration()
            decoration.setOpacity(0)
            precondition(decoration.opacity == 0, "setOpacity(0) must be admitted and stored")
        }
    }
}
