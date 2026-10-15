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

/// **T2** (`PN-A`). Rasterized over its extent, a path's coverage equals the
/// one rasterized over the clip, on every pixel of the clip: a stroked cubic,
/// a mitred triangle whose tip crosses the edge, and a filled blob, at 1× and
/// 2×. Mutation: `PathPaint.bounds`' stroke pad `max(miterLimit, 2)` made 0, so
/// the extent lacks the miter tips (a shrink of `pathExtent` by 3 px survived:
/// the pad is generous, record 118).
@Test @MainActor func anOverscannedRasterEqualsTheCutOneInsideTheClip() throws {
    let blob = Path { p in
        p.move(to: gxPoint(0, 10))
        p.addCurve(to: gxPoint(70, 50), control1: gxPoint(40, -20), control2: gxPoint(90, 10))
        p.addCurve(to: gxPoint(0, 10), control1: gxPoint(40, 90), control2: gxPoint(-30, 60))
        p.closeSubpath()
    }
    let miter = gxTriangle(80).stroke(.accent, style: StrokeStyle(lineWidth: px(6), lineJoin: .miter))
    for scale: Float in [1, 2] {
        let h = TransitionHarness()
        var seen: [(PathPaint, PrimitiveTransform?)] = []
        h.store.rasters.onRaster = { kind, transform in
            if case let .path(paint) = kind { seen.append((paint, transform)) }
        }
        let tree = canvas(ZStack {
            wire()
            miter.frame(width: px(80), height: px(80))
            blob.fill(.accent).frame(width: px(70), height: px(60))
        }, pan: 45)
        let frame = h.frame(0, nil, tree, side: 300, scaleFactor: scale)
        let target = frame.rasterTarget
        try #require(seen.count >= 3, "three paths seen: \(seen.count)")
        var compared = 0
        for (paint, transform) in seen {
            let placement = RasterPlacement(contentMask: paint.contentMask, radii: paint.maskCornerRadii,
                                            transform: transform, target: target)
            let outer = transform?.affine ?? .identity
            let map = outer.concatenating(paint.local).pathAffine
            let extent = RasterAnchor.pathExtent(paint, outer: outer)
            func raster(over clip: RasterRect) -> AlphaMask {
                var rasterizer = CoverageRasterizer()
                switch paint.mode {
                case let .fill(rule, antialiased):
                    return PathRaster.fill(paint.geometry, rule: rule, transform: map, clip: clip,
                                           antialiased: antialiased, rasterizer: &rasterizer)
                case let .stroke(style):
                    return PathRaster.stroke(paint.geometry, style: style, transform: map, clip: clip,
                                             rasterizer: &rasterizer)
                }
            }
            let clip = placement.clip
            guard !clip.isEmpty, !extent.intersection(clip).isEmpty else { continue }
            let cut = raster(over: clip), over = raster(over: extent)
            var differing = 0, maxDelta = 0
            for y in clip.y..<clip.maxY {
                for x in clip.x..<clip.maxX {
                    let d = abs(Int(cut.value(atX: x, y: y)) - Int(over.value(atX: x, y: y)))
                    if d != 0 { differing += 1; maxDelta = max(maxDelta, d) }
                }
            }
            compared += 1
            #expect(differing == 0, "\(scale)×: \(differing) clip bytes differ, max delta \(maxDelta)")
        }
        #expect(compared >= 3, "\(scale)×: compared \(compared) paths")
    }
}

/// The device pixels a scene's images draw: each image's texels inside its
/// bounds and its content mask (the draw-time cut), keyed by device x/y, zero
/// texels left out. Two renders that draw alike give equal maps.
private func drawnTexels(_ images: [(image: MUIImage, texture: ImageTexture)]) -> [Int: [UInt8]] {
    var out: [Int: [UInt8]] = [:]
    for (image, texture) in images {
        let b = image.bounds, m = image.contentMask
        let ox = Int(b.origin.x), oy = Int(b.origin.y)
        for ty in 0..<texture.height {
            for tx in 0..<texture.width {
                let x = ox + tx, y = oy + ty
                guard Float(x) >= m.origin.x, Float(x) < m.origin.x + m.size.width,
                      Float(y) >= m.origin.y, Float(y) < m.origin.y + m.size.height else { continue }
                let i = (ty * texture.width + tx) * 4
                let texel = Array(texture.pixels[i..<(i + 4)])
                if texel.contains(where: { $0 != 0 }) { out[y * 100_000 + x] = texel }
            }
        }
    }
    return out
}

/// **T8** (`PN-K`). A panned wire draws the pixels a cold render of the same
/// position draws: a warm frame (an uncut raster from the first, placed at a
/// whole-pixel offset and cut at draw time) against a fresh window and cache,
/// at 1× and 2×, across the clip's edge. The count pins of T1 cannot see a
/// stale raster (a cut raster keyed as uncut hits and draws wrong pixels at the
/// edge). Mutations: keep the cut raster but key it uncut (`rasterClip =
/// placement.clip`); drop the draw-time cut (the quad's `contentMask` made its bounds).
@Test @MainActor func aPannedWireDrawsTheColdRendersPixels() throws {
    for scale: Float in [1, 2] {
        let warm = TransitionHarness()
        _ = render(warm, canvas(wire(), pan: 0), scale: scale)
        var warmHits = 0
        for pan: Float in [1, 2, 3, 5, 8, 13, 21, 34, 55] {
            let w = render(warm, canvas(wire(), pan: pan), scale: scale)
            let cold = render(TransitionHarness(), canvas(wire(), pan: pan), scale: scale)
            let drawn = drawnTexels(cold.images)
            try #require(!drawn.isEmpty, "\(scale)× pan \(pan): the cold render draws pixels")
            let got = drawnTexels(w.images)
            // The cold render shares the draw-time cut, so the clip itself is the
            // independent reference: nothing draws outside the canvas (20…120).
            let lo = Int(20 * scale), hi = Int(120 * scale)
            let outside = got.keys.filter { k in
                let x = k % 100_000, y = k / 100_000
                return x < lo || x >= hi || y < lo || y >= hi
            }.count
            #expect(outside == 0, "\(scale)× pan \(pan): \(outside) pixels drawn outside the clip")
            if w.rasterized == 0 { warmHits += 1 }
            let differing = Set(drawn.keys).union(got.keys).filter { drawn[$0] != got[$0] }.count
            #expect(differing == 0, "\(scale)× pan \(pan): \(differing) drawn pixels differ from the cold render")
        }
        #expect(warmHits >= 5, "\(scale)×: \(warmHits) warm frames hit the cache")
    }
}
