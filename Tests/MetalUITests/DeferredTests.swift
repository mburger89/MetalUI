import Testing
import MetalUICore
import MetalUILayout
import MetalUIText
@testable import MetalUI

private func px(_ v: Float) -> Pixels { Pixels(v) }

private func sized(_ w: Float, _ h: Float) -> Style {
    var s = Style()
    s.size = Size(width: .length(.pixels(px(w))), height: .length(.pixels(px(h))))
    return s
}

/// A `deferred` block's fills carry a higher layer than an ordinary sibling's,
/// and that layer sorts AHEAD of emission order.
///
/// **Emission order is deliberately the opposite of the expected paint
/// order.** The deferred fill is emitted FIRST and the plain one SECOND: if
/// `deferred` did nothing to the layer, `Scene.finalize()`'s `(layer, order,
/// sequence)` sort would keep the emission order and this test would see
/// `[deferred, plain]`. Seeing `[plain, deferred]` instead is only possible
/// because the deferred fill's layer (1) sorts after the plain one's (0)
/// regardless of which was emitted first — the shape CLAUDE.md's "siblings
/// share a layer proves nothing" hazard warns against is avoided by giving
/// the two genuinely different layers and reversing emission order against
/// paint order to prove it.
@Test @MainActor func aDeferredFillDrawsAfterAPlainSiblingEmittedLater() throws {
    let frame = Frame(contentSize: Size(width: px(200), height: px(200)),
                      scaleFactor: 1, stateTable: StateTable(),
                      shapingCache: ShapingCache(), glyphAtlas: GlyphAtlas(width: 64, height: 64),
                      theme: Theme.forAppearance(.light))
    let pass = PaintPass(frame: frame)
    let deferredColor = Hsla(h: 0, s: 0, l: 1, a: 1)
    let plainColor = Hsla(h: 0, s: 0, l: 0, a: 1)
    pass.deferred {
        pass.fill(Bounds(origin: Point(x: px(0), y: px(0)), size: Size(width: px(10), height: px(10))),
                  color: deferredColor)
    }
    pass.fill(Bounds(origin: Point(x: px(0), y: px(0)), size: Size(width: px(10), height: px(10))),
              color: plainColor)

    let scene = frame.finalizedScene()
    try #require(scene.rects.count == 2)
    #expect(scene.rects[0].background.l == 0,
            "the plain fill (layer 0) draws first even though it was EMITTED second")
    #expect(scene.rects[1].background.l == 1,
            "the deferred fill (layer 1) draws last even though it was emitted first — a `deferred` that left the layer at 0 would keep emission order and reverse this")
}

/// A `deferred` block started from inside a REAL active clip is masked to the
/// whole surface, not to the ambient clip — the portal half of the mechanism.
///
/// **Started from inside `clipped(to:offsetBy:)`, not from a bare pass.** A
/// `deferred` block with no ancestor clip active would be masked to the whole
/// surface either way — "reset to the whole surface" and "no clip was ever
/// pushed" are the same answer there, so a `deferred` that does nothing to the
/// clip stack would still pass. Nesting inside a real 20×20 clip is what
/// forces the two apart: only a correct reset produces the full 300×300
/// mask instead of the pushed one.
///
/// **The offset is reset too, and this test checks that as well.** The
/// pushed clip carries a nonzero offset (`-40, -25`); a `deferred` that reset
/// only the clip bounds and left the offset accumulated would still
/// translate the fill by that amount, which is wrong for the same reason the
/// clip reset is: a modal must not slide with the scroll it is meant to
/// escape.
@Test @MainActor func aDeferredFillInsideAnActiveClipEscapesToTheWholeSurface() throws {
    let frame = Frame(contentSize: Size(width: px(300), height: px(300)),
                      scaleFactor: 1, stateTable: StateTable(),
                      shapingCache: ShapingCache(), glyphAtlas: GlyphAtlas(width: 64, height: 64),
                      theme: Theme.forAppearance(.light))
    let pass = PaintPass(frame: frame)
    pass.clipped(to: Bounds(origin: Point(x: px(10), y: px(10)),
                            size: Size(width: px(20), height: px(20))),
                 offsetBy: Point(x: px(-40), y: px(-25))) {
        pass.deferred {
            pass.fill(Bounds(origin: Point(x: px(5), y: px(5)),
                             size: Size(width: px(10), height: px(10))),
                      color: Hsla(h: 0, s: 0, l: 1, a: 1))
        }
    }

    let scene = frame.finalizedScene()
    let r = try #require(scene.rects.first)
    #expect(r.contentMask.origin.x == 0, "the whole surface, not the pushed clip's origin (10)")
    #expect(r.contentMask.origin.y == 0)
    #expect(r.contentMask.size.width == 300, "the whole surface's width, not the pushed clip's (20)")
    #expect(r.contentMask.size.height == 300)
    #expect(r.bounds.origin.x == 5,
            "no accumulated offset applied — the raw fill origin, not 5 + (-40)")
    #expect(r.bounds.origin.y == 5, "not 5 + (-25)")
}

/// The layer AND the clip both pop when `deferred`'s block returns, restoring
/// exactly what was active before it — not the whole surface, and not layer 1.
///
/// **A `deferred` block that does not sit at the end of the scene.** A test
/// that only ever defers as the LAST thing painted cannot see a broken pop:
/// there would be nothing painted afterward to show the stale state. This one
/// pushes an ordinary clip, defers inside it, and then fills AGAIN inside the
/// same ordinary clip — so a `popClip`/`popLayer` that did nothing would leave
/// the second fill on the whole-surface mask and layer 1 instead of the
/// pushed clip and layer 0.
@Test @MainActor func deferredsLayerAndClipBothPopOnExit() throws {
    let frame = Frame(contentSize: Size(width: px(300), height: px(300)),
                      scaleFactor: 1, stateTable: StateTable(),
                      shapingCache: ShapingCache(), glyphAtlas: GlyphAtlas(width: 64, height: 64),
                      theme: Theme.forAppearance(.light))
    let pass = PaintPass(frame: frame)
    let deferredColor = Hsla(h: 0, s: 0, l: 1, a: 1)
    let afterColor = Hsla(h: 0, s: 0, l: 0, a: 1)
    pass.clipped(to: Bounds(origin: Point(x: px(20), y: px(20)),
                            size: Size(width: px(40), height: px(40))),
                 offsetBy: Point(x: px(0), y: px(0))) {
        pass.deferred {
            pass.fill(Bounds(origin: Point(x: px(0), y: px(0)),
                             size: Size(width: px(5), height: px(5))),
                      color: deferredColor)
        }
        pass.fill(Bounds(origin: Point(x: px(0), y: px(0)),
                         size: Size(width: px(5), height: px(5))),
                  color: afterColor)
    }

    let scene = frame.finalizedScene()
    try #require(scene.rects.count == 2)
    // Layer restored to 0: the "after" fill, emitted SECOND, draws FIRST —
    // exactly the reversal `aDeferredFillDrawsAfterAPlainSiblingEmittedLater`
    // proves for a fresh `deferred`, now proving the layer came back down.
    #expect(scene.rects[0].background.l == 0, "afterColor, restored to layer 0")
    #expect(scene.rects[1].background.l == 1, "deferredColor, stayed on layer 1")
    // Clip restored to the pushed 40×40 mask, not the whole surface.
    let afterRect = scene.rects[0]
    #expect(afterRect.contentMask.origin.x == 20, "the outer clip's origin, not 0")
    #expect(afterRect.contentMask.size.width == 40, "the outer clip's width, not 300")
}

/// The prepaint half's own assertion: a scroll region registered from inside
/// `deferred` is recorded against the whole surface, not the ambient clip —
/// which is what makes hit-testing agree with where the paint half actually
/// draws.
///
/// **A paint-only test cannot see this.** `registerScrollRegion` writes to
/// `Frame.scrollRegions`, which nothing in the paint phase reads back; the
/// only way to see whether hoisting reached prepaint is to register something
/// from inside `PrepaintPass.deferred` and read the registry directly.
@Test @MainActor func deferredOnPrepaintEscapesTheActiveClipForScrollRegistration() throws {
    let frame = Frame(contentSize: Size(width: px(300), height: px(300)),
                      scaleFactor: 1, stateTable: StateTable(),
                      shapingCache: ShapingCache(), glyphAtlas: GlyphAtlas(width: 64, height: 64),
                      theme: Theme.forAppearance(.light))
    let pass = PrepaintPass(frame: frame)
    let narrowClip = Bounds(origin: Point(x: px(50), y: px(50)),
                            size: Size(width: px(20), height: px(20)))
    let wideRegion = Bounds(origin: Point(x: px(0), y: px(0)),
                            size: Size(width: px(300), height: px(300)))
    let id = GlobalElementID.child(of: nil, at: 0, name: nil)
    pass.clipped(to: narrowClip, offsetBy: Point(x: px(0), y: px(0))) {
        pass.deferred {
            pass.registerScrollRegion(wideRegion, id: id, axis: .vertical)
        }
    }

    let region = try #require(frame.scrollRegions.first)
    #expect(region.bounds == wideRegion,
            "intersected against the whole surface leaves it untouched — a broken clip reset would intersect it down to the narrow 20×20 clip instead")
}

/// The `Deferred` element itself, not just `pass.deferred` — proves the
/// wiring in `Deferred.swift` reaches both phases through a real element
/// tree, and that it introduces no layout node of its own (both boxes keep
/// their declared sizes).
///
/// Mirrors the first test's shape: the `Deferred`-wrapped box is declared
/// (and therefore emitted) FIRST, the plain sibling second, and only a
/// correct hoist reverses that into paint order.
@Test @MainActor func aDeferredElementHoistsItsChildAboveASiblingDeclaredAfterIt() throws {
    var row = Row {
        Deferred {
            Box(style: sized(30, 30)).background(.accent)
        }
        Box(style: sized(40, 40)).background(.surface)
    }
    let frame = Frame(contentSize: Size(width: px(200), height: px(200)), scaleFactor: 1)
    frame.render(&row)

    let scene = frame.finalizedScene()
    try #require(scene.rects.count == 2)
    #expect(scene.rects[0].bounds.size.width == 40,
            "the plain 40-wide sibling draws first, on the ordinary layer")
    #expect(scene.rects[1].bounds.size.width == 30,
            "the deferred 30-wide box draws last, hoisted, even though it was declared first")
}
