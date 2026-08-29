import Testing
import MetalUICore
import MetalUILayout
import MetalUIText
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
/// **Both halves are asserted, and the second is the load-bearing one.** "The
/// later one won" alone passes under an implementation that returns every
/// candidate's id, or the first, or a fixed one — so the test also pins that
/// the loser is *not* the answer, by naming it. The two rects overlap only in
/// a 20×20 square, and the probe point is inside it; each rect also has a
/// private corner, probed below, so a mutant that returned the wrong one
/// everywhere would redden three assertions rather than one.
@Test @MainActor func theTopmostOpaqueHitWins() throws {
    let frame = bareFrame()
    let pass = PrepaintPass(frame: frame)
    let lower = pass.insertHitbox(rect(0, 0, 60, 60), id: eid("lower"), opaque: true)
    let upper = pass.insertHitbox(rect(40, 40, 60, 60), id: eid("upper"), opaque: true)

    let hit = try #require(frame.topmostHitbox(at: pt(50, 50)))
    #expect(hit == upper, "the later registration paints on top and takes the point")
    #expect(hit != lower, "the covered hitbox must not win in the overlap")
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
@Test @MainActor func aNonOpaqueHitboxDoesNotStopTheWalk() throws {
    let frame = bareFrame()
    let pass = PrepaintPass(frame: frame)
    let beneath = pass.insertHitbox(rect(10, 10, 40, 40), id: eid("beneath"), opaque: true)
    let overlay = pass.insertHitbox(rect(0, 0, 100, 100), id: eid("overlay"), opaque: false)

    let hit = try #require(frame.topmostHitbox(at: pt(20, 20)))
    #expect(hit == beneath, "the walk passes through the non-opaque overlay")
    #expect(hit != overlay, "a non-opaque hitbox is never the answer")
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
/// is clicking on. `registerScrollRegion`'s only production caller registers
/// OUTSIDE its own `clipped(to:offsetBy:)` block, where the offset is zero, so
/// that omission has never been reachable there.
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
