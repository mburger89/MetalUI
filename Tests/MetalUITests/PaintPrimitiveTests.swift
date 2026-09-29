import Testing
import MetalUICore
import MetalUILayout
import MetalUIText
@testable import MetalUI

// Lane 1 of plan task 11 part 2: the paint API a custom element (and lane 2's
// shapes, lane 3's `Image`) draws the two new capabilities through —
// `PaintPass.fill(…, shape:)` (ruling TE-AE) and `PaintPass.drawImage`
// (ruling TE-AF).

@MainActor
private func makeFrame(scaleFactor: Float) -> Frame {
    Frame(contentSize: Size(width: Pixels(200), height: Pixels(200)),
          scaleFactor: scaleFactor, stateTable: StateTable(),
          shapingCache: ShapingCache(), glyphAtlas: GlyphAtlas(width: 64, height: 64),
          theme: Theme.forAppearance(.light))
}

private func box(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> Bounds<Pixels> {
    Bounds(origin: Point(x: Pixels(x), y: Pixels(y)), size: Size(width: Pixels(w), height: Pixels(h)))
}

/// 1.11 — `drawImage` stamps the active offset (scaled), clip (scaled), clip
/// radii and opacity exactly as `fill` does, and the scene carries the texture
/// once for two draws. The numbers repeat `aFillInsideAClipIsTranslatedAndMasked`'s
/// separating choices: offset −25 (so the translated origin, 5 pt, and the
/// clip's, 10 pt, cannot coincide) at scale 2 (so a scaled and an unscaled
/// mask cannot either).
@Test @MainActor func drawImageEmitsOneImageAtTheActiveOffsetClipOpacityAndLayer() throws {
    let frame = makeFrame(scaleFactor: 2)
    let pass = PaintPass(frame: frame)
    let texture = ImageTexture(width: 2, height: 1, premultipliedRGBA: [255, 0, 0, 255, 0, 0, 255, 255])
    pass.clipped(to: box(10, 10, 50, 50), offsetBy: Point(x: Pixels(0), y: Pixels(-25)),
                 cornerRadii: Corners(all: Pixels(6))) {
        pass.opacity(0.5) {
            pass.drawImage(texture, in: box(10, 30, 40, 20))
            pass.drawImage(texture, in: box(10, 60, 40, 20), filter: .nearest)
        }
    }
    let scene = frame.finalizedScene()
    try #require(scene.images.count == 2)
    #expect(scene.textures.count == 1 && scene.textures.first === texture,
            "two draws of one texture carry it once")
    let first = scene.images[0]
    #expect(first.bounds.origin.x == 20 && first.bounds.origin.y == 10,
            "(10, 30) offset by −25 is (10, 5) pt, (20, 10) px at scale 2")
    #expect(first.bounds.size.width == 80 && first.bounds.size.height == 40)
    #expect(first.contentMask.origin.y == 20 && first.contentMask.size.height == 100,
            "the pushed clip, scaled — not the translated image")
    #expect(first.maskCornerRadii.topLeft == 12, "the clip's radii, scaled")
    #expect(first.opacity == 0.5)
    #expect(first.filter == 0 && first.texture == 0)
    #expect(scene.images[1].filter == 1 && scene.images[1].texture == 0)
    #expect(scene.drawList.map { "\($0.kind) \($0.start)+\($0.count)" } == ["image 0+2"])
}

/// 1.12 — `PaintPass.fill(…, shape: .ellipse)` emits the ellipse kind; the
/// default stays the rounded rectangle every existing caller draws.
@Test @MainActor func fillCarriesTheEllipseShapeKind() throws {
    let frame = makeFrame(scaleFactor: 1)
    let pass = PaintPass(frame: frame)
    pass.fill(box(0, 0, 100, 60), color: Hsla(h: 0, s: 1, l: 0.5, a: 1), shape: .ellipse)
    pass.fill(box(0, 0, 100, 60), color: Hsla(h: 0, s: 1, l: 0.5, a: 1))
    let scene = frame.finalizedScene()
    try #require(scene.rects.count == 2)
    #expect(scene.rects[0].shape == PrimitiveShape.ellipse.rawValue)
    #expect(scene.rects[1].shape == PrimitiveShape.roundedRectangle.rawValue)
}
