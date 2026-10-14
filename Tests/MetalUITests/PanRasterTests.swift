import Testing
import MetalUICore
import MetalUILayout
import MetalUIPath
import MetalUIScene
@testable import MetalUI

// P3 — pan path rasters (rulings `PN-A`…`PN-F`; spec
// `docs/superpowers/specs/2026-10-14-pan-rasters-design.md` §7, tests T1–T7).
//
// A wire (a stroked cubic) crossing a `.clipped()` canvas edge used to key its
// raster on the clip (`RasterAnchor` `.cut`), so every pan re-rasterized and
// re-tinted it. These pins count work, never time: `lastRasterizedPixels`,
// `lastTexturesMade` and `lastTintedPixels` after each frame.

private func px(_ v: Float) -> Pixels { Pixels(v) }

/// A cubic from the left of the canvas to its right, so it crosses the clip
/// on both sides (the bracket canvas's wire).
private func wirePath(dy: Float = 0) -> Path {
    Path { p in
        p.move(to: gxPoint(-30, 20))
        p.addCurve(to: gxPoint(150, 80 + dy), control1: gxPoint(40, -10), control2: gxPoint(80, 120))
    }
}

/// `content` in a 100-point `.clipped()` canvas at (20, 20) of a root, panned
/// by `pan` points inside the clip.
@MainActor private func canvas<C: Element & ProposalElementGroup>(_ content: C, pan: Float = 0, size: Float = 100)
    -> some Element {
    ZStack { content.offset(x: px(pan)) }
        .frame(width: px(size), height: px(size), alignment: .topLeading).clipped()
        .padding(Edges(top: px(20), right: px(0), bottom: px(0), left: px(20)))
        .frame(width: px(300), height: px(300), alignment: .topLeading)
}

private struct Work {
    var rasterized: Int
    var made: Int
    var tinted: Int
    var images: [(image: MUIImage, texture: ImageTexture)]
}

@MainActor private func render<E: Element>(_ h: TransitionHarness, _ element: E, side: Float = 300,
                                            scale: Float = 1) -> Work {
    let frame = h.frame(0, nil, element, side: side, scaleFactor: scale)
    let r = h.store.rasters
    return Work(rasterized: r.lastRasterizedPixels, made: r.lastTexturesMade, tinted: r.lastTintedPixels,
                images: gxImages(frame.finalizedScene()))
}

@MainActor private func wire(_ dy: Float = 0) -> some Element & ProposalElementGroup {
    wirePath(dy: dy).stroke(.accent, lineWidth: px(2)).frame(width: px(200), height: px(130))
}

/// **T1** (`PN-A`). A wire crossing the clip edge, panned by whole device
/// pixels: frames 2–6 rasterize 0 pixels, make 0 textures and draw frame 1's
/// texture. Mutation: `overscanLimit = 0` (every wire keeps the cut key).
@Test @MainActor func aWirePannedByWholePixelsAcrossTheClipEdgeRasterizesNothing() throws {
    let h = TransitionHarness()
    let first = render(h, canvas(wire(), pan: 0))
    try #require(first.images.count == 1, "frame 1 draws the wire: \(first.images.count)")
    try #require(first.rasterized > 0, "frame 1 rasterizes: \(first.rasterized)")
    for i in 1...5 {
        let w = render(h, canvas(wire(), pan: Float(i)))
        #expect(w.rasterized == 0 && w.made == 0, "pan \(i): \(w.rasterized) px rasterized, \(w.made) textures made")
        #expect(w.images.count == 1 && w.images[0].texture === first.images[0].texture, "pan \(i): frame 1's texture")
    }
}

/// **T3** (`PN-B`). The limit binds: a wire whose extent is over 2²⁰ pixels,
/// and one whose extent leaves the window by more than half its size, keep the
/// cut key and miss on a pan. Mutations: remove the area test; remove the
/// window test.
@Test @MainActor func aRasterOverTheLimitKeepsTheCutKey() throws {
    // Area: 1100 × 1000 > 2²⁰ inside a 1200-point window.
    func big(_ pan: Float) -> some Element {
        let path = Path { p in
            p.move(to: gxPoint(0, 0))
            p.addCurve(to: gxPoint(1090, 990), control1: gxPoint(900, 0), control2: gxPoint(100, 990))
        }
        return canvas(path.stroke(.accent, lineWidth: px(2)).frame(width: px(1100), height: px(1000)), pan: pan,
                      size: 600)
    }
    let h = TransitionHarness()
    _ = render(h, big(0), side: 1200)
    for i in 1...2 {
        let w = render(h, big(Float(i)), side: 1200)
        #expect(w.rasterized > 0, "over the area limit, pan \(i): \(w.rasterized) px rasterized")
    }
    // Window: 1000 × 60 in a 300-point window leaves it by far more than half.
    func long(_ pan: Float) -> some Element {
        let path = Path { p in
            p.move(to: gxPoint(0, 0))
            p.addCurve(to: gxPoint(990, 50), control1: gxPoint(300, 0), control2: gxPoint(600, 50))
        }
        return canvas(path.stroke(.accent, lineWidth: px(2)).frame(width: px(1000), height: px(60)), pan: pan)
    }
    let g = TransitionHarness()
    _ = render(g, long(0))
    for i in 1...2 {
        let w = render(g, long(Float(i)))
        #expect(w.rasterized > 0, "outside the window bound, pan \(i): \(w.rasterized) px rasterized")
    }
}

/// **T4** (`PN-C`). A path under a local mask (a clip pushed inside a
/// rotation) keeps its absolute key: the pan frames rasterize exactly what
/// 34491ff4 did, the literal below. Mutation: route mode 3 through overscan.
@Test @MainActor func aPathUnderALocalMaskKeepsItsAbsoluteKey() throws {
    func tree(_ pan: Float) -> some Element {
        ZStack {
            ZStack { wire() }.frame(width: px(100), height: px(100), alignment: .topLeading).clipped()
                .rotationEffect(.degrees(10))
        }
        .offset(x: px(pan)).padding(Edges(top: px(40), right: px(0), bottom: px(0), left: px(40)))
        .frame(width: px(300), height: px(300), alignment: .topLeading)
    }
    let h = TransitionHarness()
    let first = render(h, tree(0))
    try #require(first.rasterized > 0)
    let moved = render(h, tree(3))
    #expect(moved.rasterized == 22736, "a panned masked wire rasterizes \(moved.rasterized) px")
}

/// **T5** (`PN-D`). A diagonal cubic's tint multiplies only the covered words:
/// fewer than a third of the mask's pixels, at least its non-zero ones.
/// Mutation: tint the whole row.
@Test @MainActor func aDiagonalCubicsTintWorkIsItsCoveredWords() throws {
    let tree = ZStack { wire() }.frame(width: px(300), height: px(300), alignment: .topLeading)
    let h = TransitionHarness()
    let w = render(h, tree)
    try #require(w.images.count == 1)
    let texture = w.images[0].texture
    let area = texture.width * texture.height
    let nonzero = stride(from: 3, to: texture.pixels.count, by: 4).filter { texture.pixels[$0] != 0 }.count
    #expect(w.tinted >= nonzero, "tinted \(w.tinted) covers the \(nonzero) covered pixels")
    #expect(w.tinted * 3 < area, "tinted \(w.tinted) of \(area) pixels: under a third")
}

/// **T7** (`PN-E`, characterization). A drag moves one wire's endpoint: the
/// static wire rasterizes 0 pixels, the moving one rasterizes every frame; a
/// sub-pixel pan keeps its fraction in the key and misses.
@Test @MainActor func aDragRastersOnlyTheMovingWires() throws {
    func both(_ dy: Float) -> some Element {
        canvas(ZStack { wire(); wire(dy) })
    }
    func movingOnly(_ dy: Float) -> some Element { canvas(ZStack { wire(dy) }) }
    let h = TransitionHarness()
    _ = render(h, both(0))
    let cold = TransitionHarness()
    _ = render(cold, movingOnly(0))
    for i in 1...3 {
        let w = render(h, both(Float(i)))
        let alone = render(cold, movingOnly(Float(i)))
        #expect(w.rasterized > 0 && w.rasterized == alone.rasterized,
                "drag \(i): \(w.rasterized) px, the moving wire alone \(alone.rasterized)")
    }
    let g = TransitionHarness()
    _ = render(g, canvas(wire(), pan: 0))
    let half = render(g, canvas(wire(), pan: 0.5), scale: 1)
    #expect(half.rasterized > 0, "a half-pixel pan misses: \(half.rasterized)")
}
