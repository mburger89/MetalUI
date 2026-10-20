import Testing
import MetalUICore
import MetalUILayout
import MetalUIPath
import MetalUIScene
@testable import MetalUI

// P4 lane 1 — overscan for shadows, blurs and full gradients (rulings `OS-A`…`OS-G`;
// spec `docs/superpowers/specs/2026-10-20-raster-overscan-design.md` §3, tests S1–S8).
//
// `PN-A` rasterized a path over its extent and keyed it uncut. A shadow, a blur and a
// full gradient crossing a `.clipped()` edge still keyed on the clip (`RasterAnchor`
// `.cut`), so every whole-pixel pan re-rasterized, re-blurred and re-tinted them. These
// pins count work, never time: `lastRasterizedPixels`, `lastBlurredPixels` and
// `lastTexturesMade` after each frame.

private func px(_ v: Float) -> Pixels { Pixels(v) }

private let diagonal = LinearGradient(colors: [.red, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
private let vertical = LinearGradient(colors: [.red, .blue], startPoint: .top, endPoint: .bottom)
private let radial = RadialGradient(colors: [.red, .blue], center: .center, startRadius: px(0), endRadius: px(30))

/// `content` in a 100-point `.clipped()` canvas at (20, 20) of a root, panned by `pan`
/// points inside the clip (`PanRasterTests`' canvas).
@MainActor private func canvas<C: Element & ProposalElementGroup>(_ content: C, pan: Float = 0, size: Float = 100)
    -> some Element {
    ZStack { content.offset(x: px(pan)) }
        .frame(width: px(size), height: px(size), alignment: .topLeading).clipped()
        .padding(Edges(top: px(20), right: px(0), bottom: px(0), left: px(20)))
        .frame(width: px(300), height: px(300), alignment: .topLeading)
}

private enum Kind: CaseIterable { case shadow, blur, diagonal, radialGradient }

/// One 40 × 40 card of `kind`, its raster reaching past the card (a glow) and so over the
/// clip's left edge when panned a little.
@MainActor private func card(_ kind: Kind, radius: Float = 8, width: Float = 40) -> some Element & ProposalElementGroup {
    ZStack {
        switch kind {
        case .shadow:
            Color.black.frame(width: px(width), height: px(40)).shadow(radius: px(radius), x: px(2), y: px(3))
        case .blur:
            Color.red.frame(width: px(width), height: px(40)).blur(radius: px(radius))
        case .diagonal:
            Rectangle().fill(diagonal).frame(width: px(width), height: px(40))
        case .radialGradient:
            Rectangle().fill(radial).frame(width: px(width), height: px(40))
        }
    }
}

private struct Work {
    var rasterized: Int
    var blurred: Int
    var made: Int
    var images: [(image: MUIImage, texture: ImageTexture)]
}

@MainActor private func render<E: Element>(_ h: TransitionHarness, _ element: E, side: Float = 300,
                                            scale: Float = 1) -> Work {
    let frame = h.frame(0, nil, element, side: side, scaleFactor: scale)
    let r = h.store.rasters
    return Work(rasterized: r.lastRasterizedPixels, blurred: r.lastBlurredPixels, made: r.lastTexturesMade,
                images: gxImages(frame.finalizedScene()))
}

/// Pans `card(kind)` by whole pixels across the clip's left edge: frames 2–6 rasterize and
/// blur 0 pixels, make 0 textures and draw frame 1's texture.
@MainActor private func requireANoWorkPan(_ kind: Kind, radius: Float = 8) throws {
    let h = TransitionHarness()
    let first = render(h, canvas(card(kind, radius: radius), pan: 0))
    try #require(first.images.count == 1, "\(kind): frame 1 draws one image: \(first.images.count)")
    try #require(first.rasterized > 0, "\(kind): frame 1 rasterizes: \(first.rasterized)")
    for i in 1...5 {
        let w = render(h, canvas(card(kind, radius: radius), pan: Float(i)))
        #expect(w.rasterized == 0 && w.blurred == 0 && w.made == 0,
                "\(kind) pan \(i): \(w.rasterized) px rasterized, \(w.blurred) blurred, \(w.made) textures made")
        #expect(w.images.count == 1 && w.images[0].texture === first.images[0].texture,
                "\(kind) pan \(i): frame 1's texture")
    }
}

/// **S1** (`OS-A`). A shadowed card crossing the clip edge, panned by whole device pixels:
/// frames 2–6 rasterize and blur 0 pixels, make 0 textures and draw frame 1's texture.
/// Mutations: `overscanLimit = 0`; remove the `overscanned` call in `shadowImage`.
@Test @MainActor func aShadowedCardPannedByWholePixelsAcrossTheClipEdgeRasterizesNothing() throws {
    try requireANoWorkPan(.shadow)
}

/// **S2** (`OS-A`). As S1 for a blurred leaf. Mutations: `overscanLimit = 0`; remove the
/// call in `blurImage`.
@Test @MainActor func aBlurredLeafPannedByWholePixelsAcrossTheClipEdgeBlursNothing() throws {
    try requireANoWorkPan(.blur)
}

/// **S3** (`OS-A`, `OS-G`). As S1 for the full raster of a diagonal linear and of a radial
/// gradient. A vertical linear gradient is the separating arm: it is the strip, already
/// translation-free, green before. Mutations: `overscanLimit = 0`; remove the call in
/// `gradientImage`.
@Test @MainActor func aFullGradientPannedByWholePixelsAcrossTheClipEdgeRasterizesNothing() throws {
    try requireANoWorkPan(.diagonal)
    try requireANoWorkPan(.radialGradient)
    // The strip arm: a vertical gradient laid out (no transform) at whole-pixel steps.
    func strip(_ x: Float) -> some Element {
        ZStack { Rectangle().fill(vertical).frame(width: px(40), height: px(40)) }
            .frame(width: px(100), height: px(100), alignment: .topLeading)
            .padding(Edges(top: px(20), right: px(0), bottom: px(0), left: px(20 + x)))
            .frame(width: px(300), height: px(300), alignment: .topLeading)
    }
    let h = TransitionHarness()
    _ = render(h, strip(0))
    for i in 1...3 {
        let w = render(h, strip(Float(i)))
        #expect(w.made == 0, "strip step \(i): \(w.made) textures made")
    }
}

/// The device pixels a scene's images draw: each image's texels inside its bounds and its
/// content mask (the draw-time cut), keyed by device x/y, zero texels left out.
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

/// **S5** (`OS-A`). A panned card draws the pixels a cold render of the same position
/// draws, for every kind: a warm frame (an uncut raster from the first, placed at a
/// whole-pixel offset and cut at draw time) against a fresh window and cache, at 1× and 2×,
/// across the clip's edges; nothing draws outside the canvas (20…120). Mutations: keep the
/// cut raster but key it uncut (`rasterClip = placement.clip`); drop the draw-time cut;
/// drop the outside-the-clip drop.
@Test @MainActor func aPannedShadowBlurAndGradientDrawTheColdRendersPixels() throws {
    for kind in Kind.allCases {
        for scale: Float in [1, 2] {
            let warm = TransitionHarness()
            _ = render(warm, canvas(card(kind), pan: 0), scale: scale)
            var warmHits = 0
            for pan: Float in [1, 2, 3, 5, 8, 13, 21, 34, 55, 70, 90] {
                let w = render(warm, canvas(card(kind), pan: pan), scale: scale)
                let cold = render(TransitionHarness(), canvas(card(kind), pan: pan), scale: scale)
                let drawn = drawnTexels(cold.images)
                try #require(!drawn.isEmpty, "\(kind) \(scale)× pan \(pan): the cold render draws pixels")
                let got = drawnTexels(w.images)
                let lo = Int(20 * scale), hi = Int(120 * scale)
                let outside = got.keys.filter { k in
                    let x = k % 100_000, y = k / 100_000
                    return x < lo || x >= hi || y < lo || y >= hi
                }.count
                #expect(outside == 0, "\(kind) \(scale)× pan \(pan): \(outside) pixels drawn outside the clip")
                if w.rasterized == 0 && w.blurred == 0 { warmHits += 1 }
                let differing = Set(drawn.keys).union(got.keys).filter { drawn[$0] != got[$0] }.count
                #expect(differing == 0, "\(kind) \(scale)× pan \(pan): \(differing) drawn pixels differ from the cold render")
            }
            #expect(warmHits >= 5, "\(kind) \(scale)×: \(warmHits) warm frames hit the cache")
        }
    }
}

/// **S6** (`OS-D`). The limit binds: a shadow whose extent is over 2²⁰ pixels, and one
/// whose extent leaves the window by more than half its size, keep the cut key and miss on
/// a pan. Mutations: remove the area test; remove the window test.
@Test @MainActor func aShadowOverTheLimitOrOutsideTheWindowKeepsTheCutKey() throws {
    // Area: radius 200 makes a ~1240-pixel square extent (> 2²⁰) inside a 1200-point window.
    let a = TransitionHarness()
    _ = render(a, canvas(card(.shadow, radius: 200), pan: 0, size: 600), side: 1200)
    for i in 1...2 {
        let w = render(a, canvas(card(.shadow, radius: 200), pan: Float(i), size: 600), side: 1200)
        #expect(w.rasterized > 0, "over the area limit, pan \(i): \(w.rasterized) px rasterized")
    }
    // Window: radius 100 makes a ~640-pixel extent, past half of a 300-point window.
    let g = TransitionHarness()
    _ = render(g, canvas(card(.shadow, radius: 100), pan: 0))
    for i in 1...2 {
        let w = render(g, canvas(card(.shadow, radius: 100), pan: Float(i)))
        #expect(w.rasterized > 0, "outside the window bound, pan \(i): \(w.rasterized) px rasterized")
    }
}

/// **S7** (`OS-E`). A shadow, a blur and a gradient under a local mask (a clip pushed
/// inside a rotation) keep their absolute key: a pan misses, as at 4d91f27f. Mutation:
/// route mode 3 through overscan.
@Test @MainActor func aShadowBlurAndGradientUnderALocalMaskKeepTheirAbsoluteKey() throws {
    for kind in Kind.allCases {
        func tree(_ pan: Float) -> some Element {
            ZStack {
                ZStack { card(kind) }.frame(width: px(100), height: px(100), alignment: .topLeading).clipped()
                    .rotationEffect(.degrees(10))
            }
            .offset(x: px(pan)).padding(Edges(top: px(40), right: px(0), bottom: px(0), left: px(40)))
            .frame(width: px(300), height: px(300), alignment: .topLeading)
        }
        let h = TransitionHarness()
        let first = render(h, tree(0))
        try #require(first.rasterized > 0, "\(kind)")
        let moved = render(h, tree(3))
        #expect(moved.rasterized > 0, "\(kind): a panned masked card rasterizes \(moved.rasterized) px")
    }
}

/// **S8** (characterization). A drag changes one card's size: the static card rasterizes 0
/// pixels, the changing one rasterizes every frame as it alone does; a half-pixel pan and a
/// radius change miss.
@Test @MainActor func aDragRastersOnlyTheMovingShadows() throws {
    func both(_ w: Float) -> some Element {
        canvas(ZStack(alignment: .topLeading) { card(.shadow); card(.shadow, width: w) })
    }
    func movingOnly(_ w: Float) -> some Element { canvas(ZStack(alignment: .topLeading) { card(.shadow, width: w) }) }
    let h = TransitionHarness()
    _ = render(h, both(40))
    let cold = TransitionHarness()
    _ = render(cold, movingOnly(40))
    for i in 1...3 {
        let w = render(h, both(40 + Float(i)))
        let alone = render(cold, movingOnly(40 + Float(i)))
        #expect(w.blurred > 0 && w.blurred == alone.blurred,
                "drag \(i): \(w.blurred) px blurred, the moving card alone \(alone.blurred)")
    }
    let g = TransitionHarness()
    _ = render(g, canvas(card(.shadow), pan: 0))
    let half = render(g, canvas(card(.shadow), pan: 0.5))
    #expect(half.blurred > 0, "a half-pixel pan misses: \(half.blurred)")
    let r = render(g, canvas(card(.shadow, radius: 9), pan: 0))
    #expect(r.blurred > 0, "a radius change misses: \(r.blurred)")
}

/// **S4** (`OS-A`, `OS-B`). Rasterized over its extent, a shadow's coverage, a blur's layer
/// and a gradient's pixels equal the ones rasterized over the clip, on every pixel of the
/// clip, at 1× and 2×: rects, rounded rects, a path, text, under a scale effect, fill and
/// stroke gradients; the clip is chosen to cut across the blur tail. Mutations: the pad of
/// `shadowExtent` / `blurExtent` made 0; `gradientExtent` not grown.
@Test @MainActor func anOverscannedShadowBlurAndGradientEqualTheCutOnesInsideTheClip() throws {
    let blob = Path { p in
        p.move(to: gxPoint(0, 10))
        p.addCurve(to: gxPoint(40, 30), control1: gxPoint(20, -10), control2: gxPoint(50, 10))
        p.addCurve(to: gxPoint(0, 10), control1: gxPoint(20, 50), control2: gxPoint(-20, 40))
        p.closeSubpath()
    }
    func leaves() -> [(String, AnyKindBox)] {
        [("rect", AnyKindBox(card(.shadow))),
         ("rounded", AnyKindBox(ZStack { RoundedRectangle(cornerRadius: px(10)).fill(.black).frame(width: px(40), height: px(40)).shadow(radius: px(8)) })),
         ("path", AnyKindBox(ZStack { blob.fill(.black).frame(width: px(40), height: px(40)).shadow(radius: px(6), x: px(3), y: px(1)) })),
         ("text", AnyKindBox(ZStack { Text("Hi, you").font(size: 16).shadow(radius: px(4)) })),
         ("scaled", AnyKindBox(ZStack { card(.shadow).scaleEffect(1.5) })),
         ("blur rect", AnyKindBox(card(.blur))),
         ("blur text", AnyKindBox(ZStack { Text("Hi, you").font(size: 16).blur(radius: px(3)) })),
         ("blur scaled", AnyKindBox(ZStack { card(.blur).scaleEffect(1.5) })),
         ("diagonal", AnyKindBox(card(.diagonal))),
         ("radial", AnyKindBox(card(.radialGradient))),
         ("stroke gradient", AnyKindBox(ZStack { Rectangle().stroke(diagonal, lineWidth: px(6)).frame(width: px(40), height: px(40)) }))]
    }
    var compared = Set<String>()
    for scale: Float in [1, 2] {
        for pan: Float in [3, 75] {
            for (name, box) in leaves() {
                let h = TransitionHarness()
                var seen: [(CapturedPrimitive.Kind, PrimitiveTransform?)] = []
                h.store.rasters.onRaster = { kind, transform in seen.append((kind, transform)) }
                let frame = box.render(h, pan: pan, scale: scale)
                let target = frame.rasterTarget
                let cache = h.store.rasters
                for (kind, transform) in seen {
                    switch kind {
                    case let .shadow(paint):
                        let placement = RasterPlacement(contentMask: paint.contentMask, radii: paint.maskCornerRadii,
                                                        transform: transform, target: target)
                        let full = (transform?.affine ?? .identity).concatenating(paint.local)
                        var canonical = paint
                        canonical.local = .identity
                        let extent = RasterAnchor.shadowExtent(paint, full: full)
                        let clip = placement.clip
                        guard !clip.isEmpty, !extent.intersection(clip).isEmpty else { continue }
                        let cut = frame.shadowCoverage(canonical, full: full, clip: clip, cache: cache)
                        let over = frame.shadowCoverage(canonical, full: full, clip: extent, cache: cache)
                        var differing = 0
                        for y in clip.y..<clip.maxY {
                            for x in clip.x..<clip.maxX where cut.value(atX: x, y: y) != over.value(atX: x, y: y) {
                                differing += 1
                            }
                        }
                        compared.insert("shadow \(name)")
                        #expect(differing == 0, "shadow \(name) \(scale)× pan \(pan): \(differing) clip bytes differ")
                    case let .blur(paint):
                        let placement = RasterPlacement(contentMask: paint.contentMask, radii: paint.maskCornerRadii,
                                                        transform: transform, target: target)
                        let full = (transform?.affine ?? .identity).concatenating(paint.local)
                        var canonical = paint
                        canonical.local = .identity
                        let extent = RasterAnchor.blurExtent(paint, full: full)
                        let clip = placement.clip
                        guard !clip.isEmpty, !extent.intersection(clip).isEmpty else { continue }
                        let cut = frame.blurLayer(canonical, full: full, clip: clip, cache: cache)
                        let over = frame.blurLayer(canonical, full: full, clip: extent, cache: cache)
                        var differing = 0
                        for y in clip.y..<clip.maxY {
                            for x in clip.x..<clip.maxX {
                                let a = cut.texel(atX: x, y: y), b = over.texel(atX: x, y: y)
                                if a != b { differing += 1 }
                            }
                        }
                        compared.insert("blur \(name)")
                        #expect(differing == 0, "blur \(name) \(scale)× pan \(pan): \(differing) clip texels differ")
                    case let .gradient(paint):
                        let placement = RasterPlacement(contentMask: paint.contentMask, radii: paint.maskCornerRadii,
                                                        transform: transform, target: target)
                        let outer = transform?.affine ?? .identity
                        let full = outer.concatenating(paint.local)
                        let extent = RasterAnchor.gradientExtent(paint, outer: outer)
                        let clip = placement.clip
                        guard !clip.isEmpty, !extent.intersection(clip).isEmpty else { continue }
                        let cut = frame.gradientPixels(paint, full: full, clip: clip, cache: cache)
                        let over = frame.gradientPixels(paint, full: full, clip: extent, cache: cache)
                        var differing = 0
                        for y in clip.y..<clip.maxY {
                            for x in clip.x..<clip.maxX {
                                let a = cut.texel(atX: x, y: y), b = over.texel(atX: x, y: y)
                                if a != b { differing += 1 }
                            }
                        }
                        compared.insert("gradient \(name)")
                        #expect(differing == 0, "gradient \(name) \(scale)× pan \(pan): \(differing) clip texels differ")
                    default: break
                    }
                }
            }
        }
    }
    for name in ["shadow rect", "shadow rounded", "shadow path", "shadow text", "shadow scaled", "blur blur rect",
                 "blur blur text", "blur blur scaled", "gradient diagonal", "gradient radial",
                 "gradient stroke gradient"] {
        #expect(compared.contains(name), "compared \(name): \(compared.sorted())")
    }
}

/// A leaf tree erased so one loop can render each in a pannable clipped canvas.
@MainActor private struct AnyKindBox {
    let run: (TransitionHarness, Float, Float) -> Frame
    init<C: Element & ProposalElementGroup>(_ content: C) {
        run = { h, pan, scale in
            h.frame(0, nil, canvas(content, pan: pan), side: 300, scaleFactor: scale)
        }
    }
    func render(_ h: TransitionHarness, pan: Float, scale: Float) -> Frame { run(h, pan, scale) }
}

/// **S10** (`OS-N`). A blurred line of text with glyphs wholly outside the clip's reach
/// draws: its out-of-reach glyphs are empty masks (width 0), which once trapped in
/// `ImageTexture` ("0×12 has a zero side", found by S4 at 4d91f27f). Mutation: drop the
/// empty-mask guard of `RGBALayer.init(mask:color:)` (the suite traps).
@Test @MainActor func aBlurredLineOfTextWithGlyphsOutsideTheClipDoesNotTrap() throws {
    let line = ZStack { Text("Hello wide world of blurred text").font(size: 16).blur(radius: px(2)) }
    let h = TransitionHarness()
    let w = render(h, canvas(line, pan: 0))
    #expect(w.images.count >= 1, "the visible glyphs draw: \(w.images.count) images")
}
