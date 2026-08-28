import Testing
import MetalUICore
import MetalUILayout
import MetalUIText
@testable import MetalUI

/// A fill inside `clipped(to:offsetBy:)` is translated and masked on the way
/// into the scene, while `bounds(of:)` keeps returning engine geometry.
///
/// A wrong implementation that forgot to apply the offset before scene
/// insertion (or applied it to the wrong axis) would leave `r.bounds.origin.y`
/// at 30 rather than 5; one that passed the whole-surface mask instead of
/// `activeClip` would leave `contentMask` at 200 tall rather than 50.
///
/// **The offset is `-25`, not the rounder `-20`, and that is load-bearing.**
/// At `-20` the translated bounds and the pushed clip land on the same y
/// origin (10 and 10), so swapping `bounds:`/`contentMask:` in `Frame.fill`'s
/// `scene.insert(MUIRect(...))` would leave every assertion here green — the
/// shape-1 fixture-coincidence `docs/practices/verifying-tests-can-fail.md`
/// warns about, and the one `MUIRect`'s own converter test was already
/// written around. At `-25` the translated origin is 5 and the clip's is 10:
/// a swap now makes `r.bounds.origin.y` read 10 and `r.contentMask.origin.y`
/// read 5, and both assertions below catch it.
@Test @MainActor func aFillInsideAClipIsTranslatedAndMasked() throws {
    let frame = Frame(contentSize: Size(width: Pixels(200), height: Pixels(200)),
                      scaleFactor: 1, stateTable: StateTable(),
                      shapingCache: ShapingCache(), glyphAtlas: GlyphAtlas(width: 64, height: 64),
                      theme: Theme.forAppearance(.light))
    let pass = PaintPass(frame: frame)
    pass.clipped(to: Bounds(origin: Point(x: Pixels(10), y: Pixels(10)),
                            size: Size(width: Pixels(50), height: Pixels(50))),
                 offsetBy: Point(x: Pixels(0), y: Pixels(-25))) {
        pass.fill(Bounds(origin: Point(x: Pixels(10), y: Pixels(30)),
                         size: Size(width: Pixels(50), height: Pixels(50))),
                  color: Hsla(h: 0, s: 0, l: 1, a: 1))
    }
    let scene = frame.finalizedScene()
    let r = try #require(scene.rects.first)
    #expect(r.bounds.origin.y == 5, "y 30 offset by -25 must reach the scene at 5")
    #expect(r.contentMask.origin.y == 10, "the pushed clip's own origin, not the translated fill")
    #expect(r.contentMask.size.height == 50)
}

/// Nested clips INTERSECT. An inner clip larger than its outer must not widen
/// it — clamping the wrong way here is how a nested scroller paints over its
/// parent's chrome.
///
/// The inner clip is deliberately WIDER (500) than the outer (60): if
/// `pushClip` replaced instead of intersecting, the emitted mask would be 500
/// wide, not 60. Sharing a coordinate between inner and outer here would make
/// this assertion pass whether the code intersects or replaces — the width
/// mismatch is what forces the two to disagree.
@Test @MainActor func nestedClipsIntersectRatherThanReplace() throws {
    let frame = Frame(contentSize: Size(width: Pixels(200), height: Pixels(200)),
                      scaleFactor: 1, stateTable: StateTable(),
                      shapingCache: ShapingCache(), glyphAtlas: GlyphAtlas(width: 64, height: 64),
                      theme: Theme.forAppearance(.light))
    let pass = PaintPass(frame: frame)
    let outer = Bounds(origin: Point(x: Pixels(0), y: Pixels(0)),
                       size: Size(width: Pixels(60), height: Pixels(200)))
    let widerInner = Bounds(origin: Point(x: Pixels(0), y: Pixels(0)),
                            size: Size(width: Pixels(500), height: Pixels(200)))
    pass.clipped(to: outer, offsetBy: Point(x: Pixels(0), y: Pixels(0))) {
        pass.clipped(to: widerInner, offsetBy: Point(x: Pixels(0), y: Pixels(0))) {
            pass.fill(Bounds(origin: Point(x: Pixels(0), y: Pixels(0)),
                             size: Size(width: Pixels(200), height: Pixels(10))),
                      color: Hsla(h: 0, s: 0, l: 1, a: 1))
        }
    }
    let scene = frame.finalizedScene()
    let r = try #require(scene.rects.first)
    #expect(r.contentMask.size.width == 60, "the inner clip must not widen the outer")
}

/// Translations compose by addition down the stack.
///
/// A wrong implementation that replaced the offset at each push instead of
/// accumulating it would land the fill at 100 - 7 = 93, not 88.
@Test @MainActor func nestedOffsetsCompose() throws {
    let frame = Frame(contentSize: Size(width: Pixels(200), height: Pixels(200)),
                      scaleFactor: 1, stateTable: StateTable(),
                      shapingCache: ShapingCache(), glyphAtlas: GlyphAtlas(width: 64, height: 64),
                      theme: Theme.forAppearance(.light))
    let pass = PaintPass(frame: frame)
    let full = Bounds(origin: Point(x: Pixels(0), y: Pixels(0)),
                      size: Size(width: Pixels(200), height: Pixels(200)))
    pass.clipped(to: full, offsetBy: Point(x: Pixels(-5), y: Pixels(0))) {
        pass.clipped(to: full, offsetBy: Point(x: Pixels(-7), y: Pixels(0))) {
            pass.fill(Bounds(origin: Point(x: Pixels(100), y: Pixels(0)),
                             size: Size(width: Pixels(10), height: Pixels(10))),
                      color: Hsla(h: 0, s: 0, l: 1, a: 1))
        }
    }
    let scene = frame.finalizedScene()
    let r = try #require(scene.rects.first)
    #expect(r.bounds.origin.x == 88, "100 - 5 - 7")
}

/// The stack pops. A fill after the block is untranslated and unclipped.
///
/// A wrong `clipped` that omitted its `defer { frame.popClip() }` would leave
/// the -50 offset and the 10-wide clip active for this fill too, landing it
/// at x 50 with a 10-wide mask instead of x 100 with a 200-wide one.
@Test @MainActor func theStackPopsWhenTheBlockReturns() throws {
    let frame = Frame(contentSize: Size(width: Pixels(200), height: Pixels(200)),
                      scaleFactor: 1, stateTable: StateTable(),
                      shapingCache: ShapingCache(), glyphAtlas: GlyphAtlas(width: 64, height: 64),
                      theme: Theme.forAppearance(.light))
    let pass = PaintPass(frame: frame)
    pass.clipped(to: Bounds(origin: Point(x: Pixels(0), y: Pixels(0)),
                            size: Size(width: Pixels(10), height: Pixels(10))),
                 offsetBy: Point(x: Pixels(-50), y: Pixels(0))) { }
    pass.fill(Bounds(origin: Point(x: Pixels(100), y: Pixels(0)),
                     size: Size(width: Pixels(10), height: Pixels(10))),
              color: Hsla(h: 0, s: 0, l: 1, a: 1))
    let scene = frame.finalizedScene()
    let r = try #require(scene.rects.first)
    #expect(r.bounds.origin.x == 100, "the offset must not survive the block")
    #expect(r.contentMask.size.width == 200, "the clip must not survive the block")
}

/// `Frame.draw`'s Retina path: the offset the clip stack carries is in
/// **points**, but a glyph's own `bounds` are already **device pixels**, so
/// `dx`/`dy` must scale `activeOffset` by `scaleFactor` before adding it — the
/// one place `draw` is not `fill`'s mirror (`fill` scales the whole translated
/// rect at the end instead).
///
/// **Every other test in this file drives `fill`, and every one of them runs
/// at `scaleFactor: 1`.** At 1x, `dx = offset * 1` and `dx = offset` are the
/// same number, so a `draw` that dropped `* scaleFactor` entirely would still
/// pass anywhere that path is reached in the rest of the suite — which is
/// nowhere, since nothing else calls `pass.draw` inside a `clipped` block
/// either. This test is the only thing that exercises `draw`'s offset at all,
/// which is why it drives at `scaleFactor: 2` and asserts the exact device-pixel
/// shift.
///
/// The same glyph is drawn twice — once with no clip active, once inside a
/// `clipped` block — so the assertions compare the shift against an
/// independently-drawn baseline rather than against a hand-computed atlas
/// bearing, which this test has no way to predict (the rasterizer's `left`/
/// `top` are internal). A wrong implementation that dropped `* scaleFactor`
/// from `dx`/`dy` would leave the clipped glyph offset by 10/5 device pixels
/// instead of 20/10; one that scaled `bounds` instead of `activeOffset` would
/// leave it unchanged from the baseline entirely.
@Test @MainActor func aDrawInsideAClipIsScaledAndMasked() throws {
    let frame = Frame(contentSize: Size(width: Pixels(200), height: Pixels(200)),
                      scaleFactor: 2, stateTable: StateTable(),
                      shapingCache: ShapingCache(), glyphAtlas: GlyphAtlas(width: 64, height: 64),
                      theme: Theme.forAppearance(.light))
    let pass = PaintPass(frame: frame)
    let font = FontResolver.resolve(family: nil, size: 13)
    let placed = try #require(
        Shaper.shape("H", font: font, wrappingAt: nil)
            .placedGlyphs(at: (x: 0, y: 0), font: font, scaleFactor: 2).first,
        "the platform UI font must place at least one glyph for \"H\"")

    // Baseline: the identical `PlacedGlyph`, drawn with no clip active — same
    // atlas key, so the same rasterizer bearings apply to both draws below.
    pass.draw(placed, color: Hsla(h: 0, s: 0, l: 1, a: 1))
    let baseline = try #require(frame.finalizedScene().glyphs.first)

    let clip = Bounds(origin: Point(x: Pixels(0), y: Pixels(0)),
                      size: Size(width: Pixels(30), height: Pixels(30)))
    pass.clipped(to: clip, offsetBy: Point(x: Pixels(10), y: Pixels(5))) {
        pass.draw(placed, color: Hsla(h: 0, s: 0, l: 1, a: 1))
    }
    let scene = frame.finalizedScene()
    try #require(scene.glyphs.count == 2)
    let clipped = scene.glyphs[1]

    #expect(clipped.bounds.origin.x == baseline.bounds.origin.x + 20,
            "10pt offset at scaleFactor 2 must land 20 device pixels over")
    #expect(clipped.bounds.origin.y == baseline.bounds.origin.y + 10,
            "5pt offset at scaleFactor 2 must land 10 device pixels down")
    #expect(clipped.contentMask.origin.x == 0)
    #expect(clipped.contentMask.size.width == 60, "30pt clip at scaleFactor 2 is 60 device pixels")
}
