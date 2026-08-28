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
/// at 30 rather than 10; one that passed the whole-surface mask instead of
/// `activeClip` would leave `contentMask` at 200 tall rather than 50.
@Test @MainActor func aFillInsideAClipIsTranslatedAndMasked() throws {
    let frame = Frame(contentSize: Size(width: Pixels(200), height: Pixels(200)),
                      scaleFactor: 1, stateTable: StateTable(),
                      shapingCache: ShapingCache(), glyphAtlas: GlyphAtlas(width: 64, height: 64),
                      theme: Theme.forAppearance(.light))
    let pass = PaintPass(frame: frame)
    pass.clipped(to: Bounds(origin: Point(x: Pixels(10), y: Pixels(10)),
                            size: Size(width: Pixels(50), height: Pixels(50))),
                 offsetBy: Point(x: Pixels(0), y: Pixels(-20))) {
        pass.fill(Bounds(origin: Point(x: Pixels(10), y: Pixels(30)),
                         size: Size(width: Pixels(50), height: Pixels(50))),
                  color: Hsla(h: 0, s: 0, l: 1, a: 1))
    }
    let scene = frame.finalizedScene()
    let r = try #require(scene.rects.first)
    #expect(r.bounds.origin.y == 10, "y 30 offset by -20 must reach the scene at 10")
    #expect(r.contentMask.origin.y == 10)
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
