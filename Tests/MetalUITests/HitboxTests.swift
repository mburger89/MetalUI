import Testing
import Metal
import MetalUICore
import MetalUILayout
import MetalUIText
import MetalUIPlatform
@testable import MetalUI

private func px(_ v: Float) -> Pixels { Pixels(v) }

private func pt(_ x: Float, _ y: Float) -> Point<Pixels> {
    Point(x: px(x), y: px(y))
}

private func rect(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> Bounds<Pixels> {
    Bounds(origin: pt(x, y), size: Size(width: px(w), height: px(h)))
}

/// A bare `Frame` with no element tree — every test here drives `PrepaintPass`
/// directly, because a hitbox is registered in prepaint and read back off the
/// frame, and no element registers one yet (Task 8's `onClick` is what will).
@MainActor private func bareFrame(_ side: Float = 300) -> Frame {
    Frame(contentSize: Size(width: px(side), height: px(side)),
          scaleFactor: 1, stateTable: StateTable(),
          shapingCache: ShapingCache(), glyphAtlas: GlyphAtlas(width: 64, height: 64),
          theme: Theme.forAppearance(.light))
}

/// Distinct element ids, so a record's `id` can be told from its neighbour's.
/// Named rather than positional: a name replaces a position (`ElementID.swift`),
/// so these can never collide however the frame's own root path is built.
@MainActor private func eid(_ name: String) -> GlobalElementID {
    GlobalElementID.child(of: nil, at: 0, name: ElementID(name))
}

// MARK: - The walk

/// Two overlapping opaque hitboxes: the one registered LAST is the one on top,
/// and it is the one a point in the overlap resolves to.
///
/// **The loser is pinned by the second PROBE POINT, not by `hit != lower`.**
/// `topmostHitbox` returns one optional, so `hit == upper` already entails
/// `hit != lower` and that line catches nothing on its own — it is kept only
/// because it names the loser for a reader. What makes this a two-sided test
/// is geometry: the rects overlap in a 20×20 square with the first probe
/// inside it, and each also has a private corner probed below, so an
/// implementation that always answered `upper` reddens at (10, 10) and one
/// that always answered `lower` reddens at (50, 50) and (90, 90).
@Test @MainActor func theTopmostOpaqueHitWins() throws {
    let frame = bareFrame()
    let pass = PrepaintPass(frame: frame)
    let lower = pass.insertHitbox(rect(0, 0, 60, 60), id: eid("lower"), opaque: true)
    let upper = pass.insertHitbox(rect(40, 40, 60, 60), id: eid("upper"), opaque: true)

    let hit = try #require(frame.topmostHitbox(at: pt(50, 50)))
    #expect(hit == upper, "the later registration paints on top and takes the point")
    #expect(hit != lower, "named for the reader; entailed by the line above")
    #expect(frame.topmostHitbox(at: pt(10, 10)) == lower,
            "outside the overlap the lower one is the only candidate")
    #expect(frame.topmostHitbox(at: pt(90, 90)) == upper,
            "outside the overlap the upper one is the only candidate")
}

/// A point over nothing resolves to nothing.
///
/// The positive control for every `nil` this file expects: without it, an
/// implementation that always returned `nil` would satisfy the clip test below
/// and only the hit tests would notice.
@Test @MainActor func aPointOverNoHitboxResolvesToNothing() {
    let frame = bareFrame()
    let pass = PrepaintPass(frame: frame)
    _ = pass.insertHitbox(rect(0, 0, 20, 20), id: eid("box"), opaque: true)

    #expect(frame.topmostHitbox(at: pt(100, 100)) == nil)
    #expect(frame.topmostHitbox(at: pt(20, 20)) == nil,
            "half-open on the max edges, as Bounds.contains is")
}

/// A non-opaque hitbox does not stop the walk: a point over it, with an opaque
/// hitbox beneath, resolves to the one beneath.
///
/// **The non-opaque one is registered SECOND on purpose**, so it is genuinely
/// on top — registering it first would let a walk that ignores `opaque`
/// entirely still return the opaque one, and the test would pass against the
/// mutant it exists to catch. It is also the larger rect, so it covers the
/// opaque one completely and there is no point at which the two disagree for
/// a geometric reason.
///
/// **The second probe point is what pins the other half.** `hit != overlay`
/// follows from `hit == beneath` for a single-valued return and catches
/// nothing alone; (80, 80) — over the non-opaque overlay and nothing else —
/// is the assertion that fails if `opaque` stops being a filter.
@Test @MainActor func aNonOpaqueHitboxDoesNotStopTheWalk() throws {
    let frame = bareFrame()
    let pass = PrepaintPass(frame: frame)
    let beneath = pass.insertHitbox(rect(10, 10, 40, 40), id: eid("beneath"), opaque: true)
    let overlay = pass.insertHitbox(rect(0, 0, 100, 100), id: eid("overlay"), opaque: false)

    let hit = try #require(frame.topmostHitbox(at: pt(20, 20)))
    #expect(hit == beneath, "the walk passes through the non-opaque overlay")
    #expect(hit != overlay, "named for the reader; entailed by the line above")
    #expect(frame.topmostHitbox(at: pt(80, 80)) == nil,
            "over the non-opaque overlay alone there is nothing to hit at all")
}

/// A hitbox is recorded at its bounds intersected with the clip that was active
/// when it registered, so a point inside its declared rect but outside that
/// clip misses.
///
/// **Both halves, and the second is what a "returns nothing" mutant fails.**
/// The declared rect is the whole 300×300 surface and the clip is a 20×20
/// window at (50, 50): (55, 55) is inside both and must hit, (100, 100) is
/// inside the declared rect and outside the clip and must miss. Modelled on
/// `Frame.registerScrollRegion`, which stores the clipped bounds for the same
/// reason — a region the user cannot see must not take the event.
@Test @MainActor func aHitboxIsClippedByTheActiveClip() throws {
    let frame = bareFrame()
    let pass = PrepaintPass(frame: frame)
    let clip = rect(50, 50, 20, 20)
    var wide: HitboxID!
    pass.clipped(to: clip, offsetBy: pt(0, 0)) {
        wide = pass.insertHitbox(rect(0, 0, 300, 300), id: eid("wide"), opaque: true)
    }

    #expect(frame.topmostHitbox(at: pt(55, 55)) == wide,
            "inside the clip and inside the declared bounds")
    #expect(frame.topmostHitbox(at: pt(100, 100)) == nil,
            "inside the declared bounds but outside the clip that was active")
    let record = try #require(frame.hitboxes.first)
    #expect(record.bounds == clip, "the stored rect is the intersection, not the declared 300×300")
}

/// Layer beats registration order: a hitbox on the root layer registered FIRST
/// still outranks an ordinary one registered after it.
///
/// **Registration order is deliberately the opposite of the expected answer**,
/// exactly as `aDeferredFillDrawsAfterAPlainSiblingEmittedLater` arranges it
/// for paint. If the walk ordered by registration sequence alone, the plain
/// hitbox — registered second, so "on top" by that rule — would win. Two
/// hitboxes that happened to share a layer would leave the walk no signal but
/// sequence, and the test would pass whether or not the layer was read at all.
@Test @MainActor func aHigherLayerBeatsALaterRegistration() throws {
    let frame = bareFrame()
    let pass = PrepaintPass(frame: frame)
    var hoisted: HitboxID!
    pass.deferred {
        hoisted = pass.insertHitbox(rect(0, 0, 100, 100), id: eid("hoisted"), opaque: true)
    }
    let plain = pass.insertHitbox(rect(0, 0, 100, 100), id: eid("plain"), opaque: true)

    let hit = try #require(frame.topmostHitbox(at: pt(50, 50)))
    #expect(hit == hoisted, "layer 1 outranks layer 0 whatever the registration order")
    #expect(hit != plain, "the later registration on the lower layer must lose")
    #expect(try #require(frame.hitboxes.first).layer == Frame.rootLayer,
            "the deferred registration carries the root layer")
    #expect(try #require(frame.hitboxes.last).layer == 0,
            "and the layer came back down after the block")
}

/// A `Deferred` hitbox outranks one it paints over — the portal's two halves
/// composed, which is the case `Deferred` actually exists for.
///
/// A scrim declared inside a narrow `ScrollView` viewport and registered from
/// inside `deferred` must (a) escape that viewport's clip, so it covers the
/// whole window, and (b) outrank a hitbox registered afterwards outside the
/// portal. Either half alone leaves a half-portal: a scrim clipped to the
/// scroller cannot swallow a click on the window's edge, and one that does not
/// hoist loses to whatever registers after it.
///
/// **Nothing in the paint phase can see this.** Hitboxes are written in
/// prepaint and read back off the frame; a scene assertion would say nothing
/// about which of two overlapping registrations takes a point.
@Test @MainActor func aDeferredHitboxOutranksAndEscapesTheOneItPaintsOver() throws {
    let frame = bareFrame()
    let pass = PrepaintPass(frame: frame)
    let viewport = rect(0, 0, 100, 300)
    var scrim: HitboxID!
    var row: HitboxID!
    pass.clipped(to: viewport, offsetBy: pt(0, 0)) {
        pass.deferred {
            scrim = pass.insertHitbox(rect(0, 0, 300, 300), id: eid("scrim"), opaque: true)
        }
        row = pass.insertHitbox(rect(0, 0, 100, 40), id: eid("row"), opaque: true)
    }

    #expect(frame.topmostHitbox(at: pt(250, 250)) == scrim,
            "the scrim escaped the 100-wide viewport clip and covers the whole window")
    let overlap = try #require(frame.topmostHitbox(at: pt(50, 20)))
    #expect(overlap == scrim, "over the row, the hoisted scrim takes the point")
    #expect(overlap != row, "the row is declared after the scrim and still loses")
}

// MARK: - What a record carries

/// The returned `HitboxID` is a dense index into `Frame.hitboxes`, and the
/// record at that index carries the `GlobalElementID` the caller supplied.
///
/// **This is the contract Tasks 6-8 consume, so it is asserted rather than
/// assumed.** A `HitboxID` cannot persist — the list is rebuilt every frame —
/// so hover, active state and scroll routing all have to recover the owning
/// element's id from the record. A `HitboxID` that did not index its own list
/// would make every one of them read the wrong element, silently.
@Test @MainActor func aHitboxIDIndexesTheFramesOwnList() throws {
    let frame = bareFrame()
    let pass = PrepaintPass(frame: frame)
    let first = pass.insertHitbox(rect(0, 0, 10, 10), id: eid("first"), opaque: true)
    let second = pass.insertHitbox(rect(0, 0, 10, 10), id: eid("second"), opaque: false)

    #expect(first.index == 0)
    #expect(second.index == 1)
    let records = frame.hitboxes
    try #require(records.count == 2)
    #expect(records[first.index].id == eid("first"))
    #expect(records[second.index].id == eid("second"))
    #expect(records[first.index].opaque)
    #expect(!records[second.index].opaque)
}

/// A hitbox registered inside a scrolled region is recorded where it PAINTS,
/// not where the engine stored it.
///
/// **This is where `insertHitbox` deliberately differs from
/// `registerScrollRegion`, which does not translate.** `PaintPass.fill` adds
/// the active offset before emitting, so a row inside a `ScrollView` scrolled
/// by 30 draws 30 points higher than `bounds(of:)` reports; a hitbox that
/// skipped the same translation would sit 30 points below the pixels the user
/// is clicking on.
///
/// **`registerScrollRegion` has the same omission and it is a live routing
/// defect today, not a hypothetical this task creates.** Its only production
/// caller registers outside its OWN `clipped(to:offsetBy:)` block, which
/// zeroes only its own contribution — an ancestor scroller's offset is still
/// in effect, because the inner element's whole `prepaint` runs inside the
/// outer's block. Measured with the outer scrolled by 120, the inner scroller
/// registers `(0, 300) 200x0` while painting at `(0, 180) 200x150`, so it
/// receives no wheel events at all. Fixing it changes wheel routing and
/// belongs with the task that folds the two lists together; this test pins
/// only the hitbox half.
///
/// The clip is the full viewport and the row is well inside it, so the
/// intersection removes nothing: the only thing that can move the stored rect
/// here is the translation.
@Test @MainActor func aHitboxInsideAScrolledRegionIsRecordedWhereItPaints() throws {
    let frame = bareFrame()
    let pass = PrepaintPass(frame: frame)
    let viewport = rect(0, 0, 100, 100)
    pass.clipped(to: viewport, offsetBy: pt(0, -30)) {
        _ = pass.insertHitbox(rect(0, 40, 100, 20), id: eid("row"), opaque: true)
    }

    let record = try #require(frame.hitboxes.first)
    #expect(record.bounds == rect(0, 10, 100, 20),
            "translated up by the scroll offset, exactly as PaintPass.fill translates it")
    #expect(frame.topmostHitbox(at: pt(50, 15)) != nil, "hits where it paints")
    #expect(frame.topmostHitbox(at: pt(50, 45)) == nil, "misses where the engine stored it")
}

// MARK: - Hover (design spec §3.3)

/// The topmost hitbox under the pointer is hovered **in the same frame it was
/// registered** — §8.1/§3.3's no-lag promise.
///
/// **A test that checked this on the NEXT frame would pass under a lagging
/// implementation** — one that resolved hover from the PREVIOUS frame's
/// hitboxes, say, or that only ever caught up a frame late. Everything here
/// happens against one `Frame`: `insertHitbox` registers, `resolveHover(at:)`
/// resolves — the same call `Frame.render` makes at the prepaint/paint
/// boundary — and `PaintPass.isHovered(_:)` is asked in the same breath, with
/// no second frame anywhere in the test.
@Test @MainActor func theTopmostHitboxUnderThePointerIsHoveredInTheSameFrameItRegistered() throws {
    let frame = bareFrame()
    let prepaintPass = PrepaintPass(frame: frame)
    let box = prepaintPass.insertHitbox(rect(0, 0, 100, 100), id: eid("box"), opaque: true)

    frame.resolveHover(at: pt(50, 50))

    let paintPass = PaintPass(frame: frame)
    #expect(paintPass.isHovered(box),
            "resolved against this frame's own hitboxes before paint ever runs")
}

/// A hitbox beneath an opaque one is NOT hovered — the loser half.
///
/// **Asserting only the winner passes under an implementation that hovers
/// everything under the pointer** rather than only the topmost — `isHovered`
/// returning `true` for both `lower` and `upper` would satisfy a test that
/// checked `upper` alone. Modelled on `theTopmostOpaqueHitWins` above, with
/// the same overlap geometry, so the loser really is under the pointer and
/// not merely absent from it.
@Test @MainActor func aHitboxBeneathAnOpaqueOneIsNotHovered() throws {
    let frame = bareFrame()
    let prepaintPass = PrepaintPass(frame: frame)
    let lower = prepaintPass.insertHitbox(rect(0, 0, 60, 60), id: eid("lower"), opaque: true)
    let upper = prepaintPass.insertHitbox(rect(40, 40, 60, 60), id: eid("upper"), opaque: true)

    frame.resolveHover(at: pt(50, 50))

    let paintPass = PaintPass(frame: frame)
    #expect(paintPass.isHovered(upper), "the later registration paints on top and is hovered")
    #expect(!paintPass.isHovered(lower),
            "under the same point but beneath the opaque winner — not hovered")
}

/// The same no-lag claim, but through a REAL `Frame.render` rather than
/// `PrepaintPass` driven directly by hand.
///
/// **This is the test that is actually sensitive to WHERE inside `render`
/// hover resolves** — the two tests above drive `insertHitbox` and
/// `resolveHover(at:)` by hand and never call `render` at all, so they cannot
/// tell "resolved after prepaint" from "resolved before it"; both would pass
/// either way. `render` is called here, once, and the hitbox is registered by
/// the element's own `prepaint`, from inside it — so if `resolveHover` moved
/// to run before `prepaint`, this is what would catch it.
@Test @MainActor func hoverResolvedThroughARealRenderHasNoLag() throws {
    let idBox = HitboxIDBox()
    var probe = HitboxProbe(elementID: ElementID("btn"),
                            size: Size(width: px(40), height: px(40)), idBox: idBox)
    let frame = Frame(contentSize: Size(width: px(100), height: px(100)), scaleFactor: 1,
                      stateTable: StateTable(), shapingCache: ShapingCache(),
                      glyphAtlas: GlyphAtlas(width: 64, height: 64),
                      theme: Theme.forAppearance(.light), mousePosition: pt(20, 20))

    frame.render(&probe)

    let hitbox = try #require(idBox.id, "prepaint must have registered a hitbox")
    let paintPass = PaintPass(frame: frame)
    #expect(paintPass.isHovered(hitbox),
            "resolved before paint ran, inside the same render() call — no one-frame lag")
}

// MARK: - Active (design spec §3.4) — driven through a real `Window`

/// The smallest element that can drive the active-tracking tests below
/// through a real `Window`: it registers exactly one opaque hitbox, sized and
/// positioned by its own `Style`, at its own resolved bounds.
///
/// **No production element inserts a hitbox yet** — `Box`, `Column`, `Row`
/// etc. carry no interactive surface until Task 8's `onClick` lands — so
/// `active`'s cross-frame behaviour can only be exercised today with a
/// purpose-built `Element`, the same way `aNamedChildUnderDeferredResolvesTheSameAsUnderABox`
/// in `DeferredTests.swift` builds its own fixtures rather than reusing one.
private struct HitboxProbe: Element {
    var elementID: ElementID?
    var size: Size<Pixels>

    /// Where `prepaint` writes back the `HitboxID` it registered, so a caller
    /// driving a real `Frame.render` — which owns the only `PrepaintPass` in
    /// play and returns nothing from `prepaint` but `Empty` — can still get the
    /// id back out to query `PaintPass.isHovered(_:)` with. A reference type
    /// because `HitboxProbe` itself is copied into `render`'s local `var root`;
    /// a stored `HitboxID?` field would not be readable from the caller's copy.
    var idBox: HitboxIDBox? = nil

    /// Where `paint` writes back whether `pass.isHovered(_:)` said yes, so a
    /// caller driving a real `Window` — which owns the only `PaintPass` in
    /// play and exposes no hover query of its own — can still read the
    /// answer back out. Same reference-type reasoning as `idBox` above.
    var hoverBox: HoverBox? = nil

    struct Empty {}

    mutating func requestLayout(_ id: GlobalElementID,
                                pass: inout LayoutPass) -> (LayoutNodeID, Empty) {
        var style = Style()
        style.size = Size(width: .length(.pixels(size.width)),
                          height: .length(.pixels(size.height)))
        return (pass.requestNode(style: style, children: []), Empty())
    }

    /// Returns the registered `HitboxID` itself as `PrepaintState`, threaded
    /// straight into `paint` below — the ordinary `Element` pipeline shape,
    /// and simpler than `idBox` for a value `paint` needs but nothing outside
    /// this one element does.
    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                           layout: inout Empty, pass: inout PrepaintPass) -> HitboxID {
        // NOT `idBox?.id = pass.insertHitbox(...)` — Swift does not evaluate
        // the right-hand side of an optional-chained assignment when the
        // chain is nil, so that spelling would silently register NO hitbox
        // at all for every test below that leaves `idBox` at its default
        // `nil` (every "Active" test). Measured, not assumed: the three
        // `active` tests all failed with `window.active == nil` under that
        // spelling, even though the hitbox's bounds and opaqueness were
        // otherwise correct.
        let hitbox = pass.insertHitbox(bounds, id: id, opaque: true)
        idBox?.id = hitbox
        return hitbox
    }

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                        layout: inout Empty, prepaint: inout HitboxID,
                        pass: inout PaintPass) {
        hoverBox?.isHovered = pass.isHovered(prepaint)
    }
}

private final class HoverBox {
    var isHovered = false
}

private final class HitboxIDBox {
    var id: HitboxID?
}

private func mouseDown(at position: Point<Pixels>) -> InputEvent {
    .mouseDown(MouseEvent(position: position))
}

private func mouseUp(at position: Point<Pixels>) -> InputEvent {
    .mouseUp(MouseEvent(position: position))
}

private func mouseMoved(to position: Point<Pixels>) -> InputEvent {
    .mouseMoved(MouseEvent(position: position))
}

/// `active` is set on `mouseDown` over a hitbox and cleared on `mouseUp` —
/// nothing before the first event, the pressed element's id after `mouseDown`,
/// `nil` again after `mouseUp`.
@Test @MainActor func activeIsSetOnMouseDownAndHeldUntilMouseUp() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 100) {
        HitboxProbe(elementID: ElementID("btn"), size: Size(width: px(40), height: px(40)))
    }
    window.drawFrameIfNeeded()
    let expected = GlobalElementID.child(of: nil, at: 0, name: ElementID("btn"))

    #expect(window.active == nil, "nothing is active before any mouse event")

    platformWindow.simulateInput(mouseDown(at: pt(20, 20)))
    #expect(window.active == expected, "mouseDown over the hitbox makes it active")

    platformWindow.simulateInput(mouseUp(at: pt(20, 20)))
    #expect(window.active == nil, "mouseUp clears it")
}

/// A press that leaves the hitbox and returns stays active — §3.4's "what
/// makes a button feel like a button". Moving off the hitbox while the button
/// is held must not clear `active`, and moving back onto it must not need to
/// re-set it (it was never cleared).
@Test @MainActor func aPressThatLeavesTheHitboxAndReturnsStaysActive() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 100) {
        HitboxProbe(elementID: ElementID("btn"), size: Size(width: px(40), height: px(40)))
    }
    window.drawFrameIfNeeded()
    let expected = GlobalElementID.child(of: nil, at: 0, name: ElementID("btn"))

    platformWindow.simulateInput(mouseDown(at: pt(20, 20)))
    #expect(window.active == expected)

    platformWindow.simulateInput(mouseMoved(to: pt(90, 90)))
    #expect(window.active == expected,
            "moving off the hitbox while the button is held does not clear active")

    platformWindow.simulateInput(mouseMoved(to: pt(20, 20)))
    #expect(window.active == expected, "and it is still active back on the hitbox")

    platformWindow.simulateInput(mouseUp(at: pt(20, 20)))
    #expect(window.active == nil, "released at last, wherever the pointer ends up")
}

/// A mutable flag a test can flip between two `drawFrameIfNeeded()` calls, to
/// make the SECOND frame's tree shaped differently from the first — a class,
/// so the content closure (which runs fresh every frame) reads the current
/// value rather than one captured at `makeFakeWindow` time.
private final class ToggleBox {
    var extraSiblingFirst = false
}

/// Active survives a frame boundary: the element is rebuilt between
/// `mouseDown` and `mouseUp`, and `active` still names it — **even though its
/// `HitboxID` changes**, which is the part a single-hitbox tree cannot prove.
///
/// **This is what keying by `GlobalElementID` rather than `HitboxID` buys, and
/// nothing else in the suite can see it.** A tree with only ever one hitbox in
/// it is not sensitive to this at all: that hitbox is index 0 on every frame
/// purely by being alone, so an implementation that (wrongly) keyed active by
/// `HitboxID` would still happen to agree with one that keys it correctly —
/// the exact trap the brief's "prove the mutant behaves differently before
/// banking a coverage gap" warns about, caught here by first shipping this
/// test with a single hitbox and mutating Step 5's implementation against it:
/// nothing reddened.
///
/// So the second frame inserts a NAMED sibling — `ElementID("extra")` —
/// **before** `btn` in the same `Row`. `btn` keeps its own `GlobalElementID`
/// across that (`.named` replaces position rather than joining it — the
/// vanishing-`if` rule this project already relies on elsewhere), but its
/// `HitboxID` shifts from index 0 to index 1, because `extra`'s `prepaint` now
/// registers first. An implementation keyed on the raw index would either
/// point at `extra` or fall off the end; one keyed on `GlobalElementID` is
/// unaffected either way.
@Test @MainActor func activeSurvivesAFrameBoundary() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let toggle = ToggleBox()
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 100) {
        Row {
            if toggle.extraSiblingFirst {
                HitboxProbe(elementID: ElementID("extra"),
                           size: Size(width: px(10), height: px(10)))
            }
            HitboxProbe(elementID: ElementID("btn"), size: Size(width: px(40), height: px(40)))
        }
    }
    window.drawFrameIfNeeded()
    let rootID = GlobalElementID.child(of: nil, at: 0, name: nil)
    // The index passed here is inert for a NAMED child — `GlobalElementID
    // .child(of:at:name:)` takes `.named(_)` whenever `name` is non-nil and
    // never consults `at:` in that case — so this is `btn`'s id whichever
    // position it occupies in the row.
    let expected = GlobalElementID.child(of: rootID, at: 0, name: ElementID("btn"))
    try #require(window.lastHitboxes.count == 1, "only btn is in the tree on frame 1")
    #expect(window.lastHitboxes[0].id == expected, "and it is HitboxID index 0")

    // (20, 50), not (20, 20): `Row` centres on the cross axis (ruling EP-8),
    // so `btn`'s 40pt-tall hitbox sits at y = 30…70 in a 100pt-tall root, not
    // at y = 0…40. Stays inside `btn`'s hitbox in both frames below, whether
    // or not `extra` (10pt tall, also centred) shares the row with it.
    platformWindow.simulateInput(mouseDown(at: pt(20, 50)))
    #expect(window.active == expected)

    // A second, independent frame — `extra` now precedes `btn`, so `btn`'s
    // hitbox is registered SECOND — with no mouse event in between.
    toggle.extraSiblingFirst = true
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    try #require(window.lastHitboxes.count == 2, "extra's hitbox now precedes btn's")
    #expect(window.lastHitboxes[1].id == expected,
            "btn's OWN id is unchanged, but it is now HitboxID index 1, not 0")

    #expect(window.active == expected,
            "the element was rebuilt, its hitbox reindexed, and active still names it")

    platformWindow.simulateInput(mouseUp(at: pt(20, 50)))
    #expect(window.active == nil)
}

// MARK: - Hover through a real Window (production wiring, not hand-driven)

/// A `mouseMoved` event at a point makes the box under it hovered on the
/// **next** frame — the one production path from a real mouse move to a
/// resolved hover, with nothing hand-driven in between.
///
/// **This is the test the fix-round review asked for, and every hover test
/// above it in this file is blind to what it catches.** Both
/// `theTopmostHitboxUnderThePointerIsHoveredInTheSameFrameItRegistered` and
/// `aHitboxBeneathAnOpaqueOneIsNotHovered` drive `resolveHover(at:)` by hand,
/// and `hoverResolvedThroughARealRenderHasNoLag` builds a `Frame` with a
/// literal `mousePosition:` — none of the three goes through a `Window` at
/// all. The review confirmed this by mutating `Window.drawFrameIfNeeded` to
/// pass `mousePosition: nil` regardless of `lastMousePosition`: the whole
/// 637-test suite stayed green, because nothing exercised the one line that
/// threads a real mouse position from an input event into a `Frame`. This
/// test does, through `FakePlatformWindow.simulateInput` and a real
/// `Window.drawFrameIfNeeded()` — see the report for that mutation's redden
/// after this test was added.
@Test @MainActor func aMouseMovedEventMakesTheBoxUnderItHoveredOnTheNextFrame() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let hoverBox = HoverBox()
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 100) {
        Row {
            HitboxProbe(elementID: ElementID("btn"), size: Size(width: px(40), height: px(40)),
                       hoverBox: hoverBox)
        }
    }
    window.drawFrameIfNeeded()
    #expect(!hoverBox.isHovered, "no mouse event has ever reached the window")

    // (20, 50), not (20, 20): `Row` centres on the cross axis (ruling EP-8),
    // the same geometry `activeSurvivesAFrameBoundary` above already relies
    // on — btn's 40pt-tall hitbox sits at y = 30…70 in a 100pt-tall root.
    // `simulateInput` alone only updates `Window.lastMousePosition`; hover
    // resolves inside the NEXT `render`, at the prepaint/paint boundary — so
    // nothing is asserted between this call and the next `drawFrameIfNeeded`.
    platformWindow.simulateInput(mouseMoved(to: pt(20, 50)))

    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    #expect(hoverBox.isHovered, "the frame after mouseMoved hovers the box under it")
}

// MARK: - One list, two kinds (design spec §3.1)

/// **A scroll region IS a hitbox — one list — and `scrollRegions` is a derived
/// view of it that reports only the records carrying a scroll axis.**
///
/// `Frame.scrollRegions` was a second registry until scroll regions folded into
/// this one; keeping the name as an accessor is what lets every assertion
/// written against the old list keep reading the same fields. This pins that it
/// is genuinely derived (the scroller appears in `hitboxes` too, at the index
/// its `HitboxID` names) and genuinely filtered (the plain hitbox does not
/// appear in `scrollRegions`).
///
/// **Written because dropping the filter reddened NOTHING**, on the full
/// 643-test suite: replacing `compactMap { box.scroll.map { … } }` with
/// `map { … box.scroll ?? .vertical … }` passed everywhere. Not because the
/// assertion was weak — because no fixture in the suite put both kinds of
/// record in one frame and then read `Frame.scrollRegions` back, so the filter
/// had nothing to filter (ruling MP-J's shape). `Window.lastScrollRegions`'
/// own filter IS covered, by the two scrim tests in `ScrollRoutingTests`; this
/// is `Frame`'s.
///
/// The two are registered in this order deliberately: the plain hitbox FIRST,
/// so a `scrollRegions` that forgot to filter would report it at index 0 and
/// the scroller's own index in the derived list would shift.
@Test @MainActor func scrollRegionsAreTheScrollingSubsetOfTheOneHitboxList() throws {
    let frame = bareFrame()
    let pass = PrepaintPass(frame: frame)
    let plain = pass.insertHitbox(rect(0, 0, 40, 40), id: eid("plain"), opaque: true)
    pass.registerScrollRegion(rect(0, 0, 80, 80), id: eid("scroller"), axis: .horizontal)

    try #require(frame.hitboxes.count == 2, "both kinds live in the ONE list")
    #expect(frame.hitboxes[plain.index].scroll == nil, "a plain hitbox carries no axis")
    #expect(frame.hitboxes[1].scroll == .horizontal,
            "and the scroller carries the axis its ScrollView declared")
    #expect(frame.hitboxes[1].opaque,
            "a scroller is opaque: a transparent record could never take a wheel event")

    let regions = frame.scrollRegions
    try #require(regions.count == 1, "the derived view reports only the scrolling record")
    #expect(regions[0].id == eid("scroller"))
    #expect(regions[0].axis == .horizontal)
    #expect(regions[0].bounds == rect(0, 0, 80, 80))
    #expect(regions[0].layer == 0)
}
