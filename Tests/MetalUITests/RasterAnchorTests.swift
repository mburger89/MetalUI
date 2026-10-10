import Testing
import Metal
import MetalUICore
import MetalUILayout
import MetalUIPath
import MetalUIScene
@testable import MetalUI

// C13 / PERF-a, lane 1 — translation-free raster keys (rulings `PF-A`, `PF-B`,
// `PF-C`, `PF-D`, `PF-G`, `PF-I`, `PF-J`; spec
// `docs/superpowers/specs/2026-10-09-shadow-cache-design.md` §3, §8, tests
// L1.1–L1.10 and L1.13).
//
// Performance pins count work, never time: `RasterCache.lastBlurredPixels`,
// `lastRasterizedPixels` and `lastTexturesMade` after each frame, and the
// `ImageTexture` identity every image draws (`TE-AF`: a renderer uploads once
// per identity). Every drag pin was red at lane 1's first commit (the counter
// added, the keys unchanged): every frame missed.
//
// The fixtures sit at the top-left of a 300-point window through padding, so
// a layout move is a padding change; a pan is an `.offset` outside the
// shadowed content (a flattened render effect, `GX-G`).

private func px(_ v: Float) -> Pixels { Pixels(v) }

/// A diagonal gradient: never the strip, always the full raster (`LK-J`).
private let diagonal = LinearGradient(colors: [Color(red: 1, green: 0, blue: 0), Color(red: 0, green: 0, blue: 1)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing)

/// A MetalCreator-style node's content: nine leaves (a rounded rectangle, six
/// bars, a circle and a text draw).
@MainActor private func nodeContent() -> some ProposalElementGroup {
    VStack(spacing: px(2)) {
        RoundedRectangle(cornerRadius: 4).fill(.accent).frame(width: px(70), height: px(12))
        Color(.separator).frame(width: px(60), height: px(6))
        Color(.separator).frame(width: px(50), height: px(6))
        Color(.separator).frame(width: px(60), height: px(6))
        Color(.separator).frame(width: px(40), height: px(6))
        Color(.separator).frame(width: px(60), height: px(6))
        Color(.separator).frame(width: px(30), height: px(6))
        Circle().fill(.accent).frame(width: px(10), height: px(10))
        Text("Node").font(size: 11)
    }
}

/// `content` at `(x, y)` points in a top-leading 300-point root.
@MainActor private func placed<C: ProposalElementGroup>(_ content: C, x: Float, y: Float)
    -> some Element & ProposalElementGroup {
    content.padding(Edges(top: px(y), right: px(0), bottom: px(0), left: px(x)))
        .frame(width: px(300), height: px(300), alignment: .topLeading)
}

/// What one frame did and drew.
private struct Work {
    var blurred: Int
    var rasterized: Int
    var made: Int
    var images: [(image: MUIImage, texture: ImageTexture)]
}

@MainActor private func render<E: Element>(_ h: TransitionHarness, _ element: E, scale: Float = 1) -> Work {
    let frame = h.frame(0, nil, element, side: 300, scaleFactor: scale)
    let rasters = h.store.rasters
    return Work(blurred: rasters.lastBlurredPixels, rasterized: rasters.lastRasterizedPixels,
                made: rasters.lastTexturesMade, images: gxImages(frame.finalizedScene()))
}

/// Drives `frames` frames of `tree(i)` in one harness and checks frames 2…n
/// did no raster work and drew frame 1's textures; returns a description of
/// every frame that did not, empty when all hit.
@MainActor private func dragMisses<E: Element>(frames: Int = 5, scale: Float = 1, _ tree: (Int) -> E,
                                               expectImages: Int) throws -> [String] {
    let h = TransitionHarness()
    let first = render(h, tree(0), scale: scale)
    try #require(first.images.count == expectImages, "frame 1 draws \(expectImages) images: \(first.images.count)")
    try #require(first.rasterized > 0, "frame 1 rasterized: \(first.rasterized)")
    var misses: [String] = []
    for i in 1..<frames {
        let w = render(h, tree(i), scale: scale)
        let same = w.images.count == first.images.count
            && zip(w.images, first.images).allSatisfy { $0.texture === $1.texture }
        if w.blurred != 0 || w.rasterized != 0 || w.made != 0 || !same {
            misses.append("frame \(i + 1): blurred \(w.blurred), rasterized \(w.rasterized), made \(w.made), same textures \(same)")
        }
    }
    return misses
}

// MARK: - L1.1 (PF-A, PF-G): a layout drag

/// **L1.1** (`PF-A` item 3, `PF-G`). A nine-leaf `.shadow(radius: 10)`
/// container moved 1 px per frame at 1× and 1 pt per frame at 2× for five
/// frames (layout places on whole points, so a half-point layout move does not
/// exist; the half-point move at 2× is an `.offset`): frames 2–5 blur 0,
/// rasterize 0 and make 0 textures, and every image draws frame 1's texture. Mutation **M1a** (key `full` with
/// its absolute translation), **M1f** (stored rect not shifted).
@Test @MainActor func aShadowedContainerDraggedByWholePixelsHitsTheCache() throws {
    let node = nodeContent().shadow(radius: px(10))
    let one = try dragMisses({ placed(node, x: 40 + Float($0), y: 50) }, expectImages: 9)
    #expect(one.isEmpty, "1×: \(one)")
    let two = try dragMisses(scale: 2, { placed(node, x: 40 + Float($0), y: 50 - Float($0)) }, expectImages: 9)
    #expect(two.isEmpty, "2×: \(two)")
    let half = try dragMisses(scale: 2, { ZStack { placed(node, x: 40, y: 50) }.offset(y: px(0.5 * Float($0))) },
                              expectImages: 9)
    #expect(half.isEmpty, "2×, half points: \(half)")
}

/// **L1.1b** (`PF-A`, M1f). A hit draws its image where the content now is:
/// each frame's shadow images sit exactly one point (1 or 2 device px) right
/// of the frame before's, at 1× and 2×.
@Test @MainActor func aCachedShadowIsPlacedAtTheNewPosition() throws {
    let node = nodeContent().shadow(radius: px(10))
    for scale: Float in [1, 2] {
        let h = TransitionHarness()
        var previous = render(h, placed(node, x: 40, y: 50), scale: scale).images
        for i in 1..<4 {
            let now = render(h, placed(node, x: 40 + Float(i), y: 50), scale: scale).images
            try #require(now.count == previous.count, "\(scale)×: same image count")
            for (a, b) in zip(now, previous) {
                let x = a.image.bounds, y = b.image.bounds
                let moved = x.origin.x == y.origin.x + scale && x.origin.y == y.origin.y && x.size.width == y.size.width
                let note = "\(scale)× frame \(i + 1): \(gxDescribe(x)) after \(gxDescribe(y))"
                #expect(moved, Comment(rawValue: note))
            }
            previous = now
        }
    }
}

// MARK: - L1.2 (PF-A): a pan

/// **L1.2** (`PF-A` item 3). The same node under a parent `.offset` that
/// changes by whole device pixels (a pan, a flattened effect): frames 2–5 do
/// no raster work and draw frame 1's textures. Mutation **M1a**.
@Test @MainActor func aShadowedContainerPannedByWholePixelsHitsTheCache() throws {
    let node = nodeContent().shadow(radius: px(10))
    let one = try dragMisses({ ZStack { placed(node, x: 40, y: 50) }.offset(x: px(Float($0)), y: px(-Float($0))) },
                             expectImages: 9)
    #expect(one.isEmpty, "1×: \(one)")
    let two = try dragMisses(scale: 2, { ZStack { placed(node, x: 40, y: 50) }.offset(x: px(0.5 * Float($0))) },
                             expectImages: 9)
    #expect(two.isEmpty, "2×: \(two)")
}

// MARK: - L1.3 (PF-A, LK-K): a blur drag

/// **L1.3** (`PF-A`, `LK-K`). A `.blur(radius: 4)` container dragged by whole
/// pixels: frames 2–5 blur, rasterize and make nothing, same textures.
/// Mutation **M1a**.
@Test @MainActor func aBlurredContainerDraggedByWholePixelsHitsTheCache() throws {
    let node = nodeContent().blur(radius: px(4))
    let one = try dragMisses({ placed(node, x: 40 + Float($0), y: 50) }, expectImages: 9)
    #expect(one.isEmpty, "1×: \(one)")
    let two = try dragMisses(scale: 2, { placed(node, x: 40, y: 50 + Float($0)) }, expectImages: 9)
    #expect(two.isEmpty, "2×: \(two)")
}

// MARK: - L1.4 (PF-A item 1): history independence

/// Every image of `a` and `b` equal: bounds and texture bytes.
private func sameImages(_ a: [(image: MUIImage, texture: ImageTexture)],
                        _ b: [(image: MUIImage, texture: ImageTexture)]) -> String? {
    guard a.count == b.count else { return "\(a.count) vs \(b.count) images" }
    for (i, (x, y)) in zip(a, b).enumerated() {
        if gxDescribe(x.image.bounds) != gxDescribe(y.image.bounds) {
            return "image \(i): \(gxDescribe(x.image.bounds)) vs \(gxDescribe(y.image.bounds))"
        }
        if x.texture.pixels != y.texture.pixels {
            let differing = zip(x.texture.pixels, y.texture.pixels).filter { $0 != $1 }.count
            return "image \(i): \(differing) bytes differ"
        }
    }
    return nil
}

/// **L1.4** (`PF-A` item 1, `PF-D`). A raster is a pure function of its key:
/// warm at x, then moved to x + 0.3 by an `.offset` (layout places on whole
/// points; a fraction that misses), every image
/// equals a cold window's at x + 0.3, bounds and bytes — shadow, blur, path
/// and gradient, at 1× and 2×. Mutation **M1b** (the fraction `f` dropped from
/// the key: the warm window draws the x raster at x + 0.3).
@Test @MainActor func aRasterIsTheSameWarmOrCold() throws {
    let content = VStack(spacing: px(4)) {
        nodeContent().shadow(radius: px(6), x: px(2), y: px(3))
        Color(.accent).frame(width: px(30), height: px(20)).blur(radius: px(3))
        gxTriangle(30).stroke(.accent, lineWidth: px(3)).frame(width: px(30), height: px(30))
        Circle().fill(diagonal).frame(width: px(30), height: px(30))
    }
    for scale: Float in [1, 2] {
        let warm = TransitionHarness()
        _ = render(warm, placed(content, x: 30, y: 20).offset(x: px(0)), scale: scale)
        _ = render(warm, placed(content, x: 30, y: 20).offset(x: px(0)), scale: scale)
        let moved = render(warm, placed(content, x: 30, y: 20).offset(x: px(0.3)), scale: scale)
        try #require(moved.rasterized > 0, "\(scale)×: a 0.3 move misses")
        let cold = render(TransitionHarness(), placed(content, x: 30, y: 20).offset(x: px(0.3)), scale: scale)
        try #require(cold.images.count == 12, "\(scale)×: twelve images: \(cold.images.count)")
        #expect(sameImages(moved.images, cold.images) == nil,
                "\(scale)×: \(sameImages(moved.images, cold.images) ?? "")")
    }
}

// MARK: - L1.5 (PF-C): canonical = absolute

/// 2155f1e's absolute rasters, recomputed from the helpers the canonical path
/// calls (`shadowCoverage`, `blurLayer`, `PathRaster`, `gradientPixels`) at the
/// primitive's absolute position: the rect and the premultiplied bytes, or
/// `nil` when nothing is visible; `strip` when the gradient takes the strip.
private enum Absolute {
    case image(RasterRect, [UInt8])
    case none
    case strip
}

@MainActor private func absolute(_ kind: CapturedPrimitive.Kind, _ t: PrimitiveTransform?, in frame: Frame) -> Absolute {
    let cache = RasterCache()
    func placement(_ mask: MUIBounds, _ radii: MUICorners) -> RasterPlacement {
        RasterPlacement(contentMask: mask, radii: radii, transform: t, target: frame.rasterTarget)
    }
    let outer = t?.affine ?? .identity
    switch kind {
    case let .shadow(p):
        let place = placement(p.contentMask, p.maskCornerRadii)
        guard !place.clip.isEmpty, p.color.a > 0, !p.leaf.isEmpty else { return .none }
        let full = outer.concatenating(p.local)
        let mask = place.applyingLocalMask(RasterMath.crop(frame.shadowCoverage(p, full: full, clip: place.clip,
                                                                                cache: cache), to: place.clip),
                                           cache: cache)
        guard !mask.rect.isEmpty else { return .none }
        return .image(mask.rect, RasterCache.tint(mask, color: p.color).pixels)
    case let .blur(p):
        let place = placement(p.contentMask, p.maskCornerRadii)
        guard !place.clip.isEmpty, p.alpha > 0, !p.leaf.isEmpty else { return .none }
        let full = outer.concatenating(p.local)
        var layer = frame.blurLayer(p, full: full, clip: place.clip, cache: cache).cropped(to: place.clip)
        if let local = place.localMask, !layer.rect.isEmpty {
            layer = layer.multiplied(by: RasterMath.maskCoverage(local.bounds, local.radii, map: local.map,
                                                                 clip: layer.rect, cache: cache))
        }
        guard !layer.rect.isEmpty else { return .none }
        return .image(layer.rect, layer.pixels)
    case let .path(p):
        let place = placement(p.contentMask, p.maskCornerRadii)
        guard !place.clip.isEmpty, p.color.a > 0 else { return .none }
        let full = outer.concatenating(p.local)
        var rasterizer = CoverageRasterizer()
        let coverage: AlphaMask
        switch p.mode {
        case let .fill(rule, antialiased):
            coverage = PathRaster.fill(p.geometry, rule: rule, transform: full.pathAffine, clip: place.clip,
                                       antialiased: antialiased, rasterizer: &rasterizer)
        case let .stroke(style):
            coverage = PathRaster.stroke(p.geometry, style: style, transform: full.pathAffine, clip: place.clip,
                                         rasterizer: &rasterizer)
        }
        let mask = place.applyingLocalMask(coverage, cache: cache)
        guard !mask.rect.isEmpty else { return .none }
        return .image(mask.rect, RasterCache.tint(mask, color: p.color).pixels)
    case let .gradient(g):
        let place = placement(g.contentMask, g.maskCornerRadii)
        guard !place.clip.isEmpty, g.opacity > 0, !g.stops.isEmpty else { return .none }
        let full = outer.concatenating(g.local)
        var layer = frame.gradientPixels(g, full: full, clip: place.clip, cache: cache)
        guard !layer.rect.isEmpty else { return .none }
        if let local = place.localMask {
            layer = layer.multiplied(by: RasterMath.maskCoverage(local.bounds, local.radii, map: local.map,
                                                                 clip: layer.rect, cache: cache))
        }
        guard !layer.rect.isEmpty else { return .none }
        return .image(layer.rect, layer.pixels)
    default:
        return .none
    }
}

/// The canonical rasters of `content`'s frame against `absolute`, compared
/// **on the device** — each texel at its device pixel, 0 outside its rect — so
/// an extra all-zero row is no difference: how many rasters, how many have
/// other bounds, how many device bytes differ, by how much at most, and the
/// kinds that differ.
private struct Comparison: CustomStringConvertible {
    var rasters = 0, strips = 0, boundsDiffer = 0, bytesDiffer = 0, maxDelta = 0
    var differing: [String] = []
    var description: String {
        "\(rasters) rasters (\(strips) strips), \(boundsDiffer) other bounds, \(bytesDiffer) device bytes differ, "
            + "max Δ \(maxDelta)\(differing.isEmpty ? "" : " in \(differing)")"
    }
}

/// The name of a raster kind and its first leaf's, for a report.
private func kindName(_ kind: CapturedPrimitive.Kind) -> String {
    func name(_ k: CapturedPrimitive.Kind) -> String {
        switch k {
        case .rect: "rect"
        case .glyph: "glyph"
        case .image: "image"
        case .surface: "surface"
        case .path: "path"
        case let .shadow(p): "shadow(\(p.leaf.first.map { name($0.kind) } ?? ""))"
        case .gradient: "gradient"
        case let .blur(p): "blur(\(p.leaf.first.map { name($0.kind) } ?? ""))"
        }
    }
    return name(kind)
}

@MainActor private func compareCanonical<E: Element>(_ element: E, scale: Float) -> Comparison {
    let h = TransitionHarness()
    var captured: [(CapturedPrimitive.Kind, PrimitiveTransform?)] = []
    h.store.rasters.onRaster = { captured.append(($0, $1)) }
    let frame = h.frame(0, nil, element, side: 300, scaleFactor: scale)
    h.store.rasters.onRaster = nil
    var c = Comparison()
    for (kind, t) in captured {
        let drawn: (MUIImage, ImageTexture)?
        switch kind {
        case let .shadow(p): drawn = frame.shadowImage(p, transform: t)
        case let .blur(p): drawn = frame.blurImage(p, transform: t)
        case let .path(p): drawn = frame.pathImage(p, transform: t)
        case let .gradient(g): drawn = frame.gradientImage(g, transform: t)
        default: drawn = nil
        }
        c.rasters += 1
        let reference: (RasterRect, [UInt8])
        switch absolute(kind, t, in: frame) {
        case .strip:
            c.strips += 1
            continue
        case .none:
            reference = (RasterRect(x: 0, y: 0, width: 0, height: 0), [])
        case let .image(rect, bytes):
            reference = (rect, bytes)
        }
        var mine = (RasterRect(x: 0, y: 0, width: 0, height: 0), [UInt8]())
        if let (quad, texture) = drawn {
            if quad.filter & 0xFF == ImageFilter.linear.rawValue { c.strips += 1; continue }
            mine = (RasterRect(x: Int(quad.bounds.origin.x), y: Int(quad.bounds.origin.y), width: texture.width,
                               height: texture.height), texture.pixels)
        }
        if mine.0 != reference.0 { c.boundsDiffer += 1 }
        func byte(_ r: (RasterRect, [UInt8]), _ x: Int, _ y: Int, _ k: Int) -> Int {
            guard x >= r.0.x, y >= r.0.y, x < r.0.maxX, y < r.0.maxY else { return 0 }
            return Int(r.1[((y - r.0.y) * r.0.width + (x - r.0.x)) * 4 + k])
        }
        let union = mine.0.union(reference.0)
        var differs = false
        for y in union.y..<union.maxY {
            for x in union.x..<union.maxX {
                for k in 0..<4 {
                    let d = abs(byte(mine, x, y, k) - byte(reference, x, y, k))
                    if d > 0 { c.bytesDiffer += 1; c.maxDelta = max(c.maxDelta, d); differs = true }
                }
            }
        }
        if differs { c.differing.append(kindName(kind)) }
    }
    return c
}

/// Every raster kind L1.5 names, side by side: a rect, a rounded rect, an
/// ellipse, a bordered rounded legacy box, a text, an image, a mitred stroke
/// (alone and shadowed), a nested shadow, a gradient (alone and shadowed), a
/// blur, a blurred leaf in a shadow, a shadow in a blur. Each leaf is moved by
/// `inner` inside its shadow or blur (a flattened `.offset`), so the leaf's own
/// device bounds carry the fraction; an `.offset` outside the whole set moves
/// each raster's map instead.
@MainActor private func everyRasterKind(inner: (x: Float, y: Float)) -> some Element & ProposalElementGroup {
    let bitmap = ImageBitmap(width: 6, height: 6, rgba: (0..<36).flatMap { i -> [UInt8] in
        let a = UInt8((i * 37) % 256)
        return [a, a / 2, 0, a]
    })
    let dx = px(inner.x), dy = px(inner.y)
    let rowOne = HStack(spacing: px(3)) {
        Color(.accent).frame(width: px(20), height: px(14)).offset(x: dx, y: dy)
            .shadow(color: .textPrimary, radius: px(4), x: px(2), y: px(3))
        RoundedRectangle(cornerRadius: 5).fill(.accent).frame(width: px(20), height: px(14)).offset(x: dx, y: dy)
            .shadow(color: .textPrimary, radius: px(3))
        Circle().fill(.accent).frame(width: px(15), height: px(15)).offset(x: dx, y: dy)
            .shadow(color: .textPrimary, radius: px(2.5))
        VStack { Box().frame(width: px(20), height: px(14)).background(.accent).border(.separator, width: px(2))
            .cornerRadius(px(4)).offset(x: dx, y: dy).shadow(color: .textPrimary, radius: px(3)) }
    }
    let rowTwo = HStack(spacing: px(3)) {
        Text("Shadow").font(size: 13).offset(x: dx, y: dy).shadow(color: .textPrimary, radius: px(2), x: px(1), y: px(1))
        Image(decorative: bitmap, scale: 1).offset(x: dx, y: dy).shadow(color: .textPrimary, radius: px(2))
        gxTriangle(16).stroke(.accent, style: StrokeStyle(lineWidth: px(3), lineJoin: .miter, miterLimit: 6))
            .frame(width: px(16), height: px(16)).offset(x: dx, y: dy)
        gxTriangle(16).stroke(.accent, style: StrokeStyle(lineWidth: px(2), lineJoin: .miter))
            .frame(width: px(16), height: px(16)).offset(x: dx, y: dy).shadow(color: .textPrimary, radius: px(2))
    }
    let rowThree = HStack(spacing: px(3)) {
        Color(.accent).frame(width: px(16), height: px(12)).offset(x: dx, y: dy)
            .shadow(color: .textPrimary, radius: px(2), x: px(2)).shadow(color: .accent, radius: px(3), y: px(2))
        Circle().fill(diagonal).frame(width: px(18), height: px(18)).offset(x: dx, y: dy)
        Circle().fill(diagonal).frame(width: px(18), height: px(18)).offset(x: dx, y: dy)
            .shadow(color: .textPrimary, radius: px(2))
        Color(.accent).frame(width: px(16), height: px(12)).offset(x: dx, y: dy).blur(radius: px(2))
        Color(.accent).frame(width: px(16), height: px(12)).offset(x: dx, y: dy).blur(radius: px(1.5))
            .shadow(color: .textPrimary, radius: px(2))
        Color(.accent).frame(width: px(16), height: px(12)).offset(x: dx, y: dy)
            .shadow(color: .textPrimary, radius: px(2)).blur(radius: px(1.5))
    }
    return VStack(spacing: px(3)) {
        rowOne
        rowTwo
        rowThree
    }
}

/// **L1.5** (`PF-C` item 2, as `PF-M` amends it). The canonical raster,
/// shifted by `S`, against 2155f1e's absolute call — every raster kind, at an
/// integer, a dyadic and a non-dyadic position (each a fraction of the leaves
/// inside their effect and of the maps outside it), at 1× and 2×, compared on
/// the device: at most 1 apart anywhere, 0 at integer positions. A dyadic
/// position is not always exact (`PF-M` item 1: a curved outline's deposits
/// round differently in the rasterizer's running sum at another magnitude, and
/// a half-covered pixel at exactly 128 can read 127); the measured counts are
/// in record §90.
@Test @MainActor func aCanonicalRasterEqualsTheAbsoluteOne() throws {
    let positions: [(inner: (Float, Float), outer: (Float, Float), integer: Bool)] =
        [((0, 0), (0, 0), true), ((0.25, 0.5), (0.5, 0.25), false), ((0.3, 0.7), (0.1, 0.45), false)]
    for scale: Float in [1, 2] {
        for p in positions {
            let tree = placed(everyRasterKind(inner: p.inner), x: 20, y: 30).offset(x: px(p.outer.0), y: px(p.outer.1))
            let c = compareCanonical(tree, scale: scale)
            let note = "\(scale)× inner \(p.inner) outer \(p.outer): \(c)"
            try #require(c.rasters >= 20, Comment(rawValue: note))
            #expect(c.strips == 0 && c.maxDelta <= 1, Comment(rawValue: note))
            if p.integer { #expect(c.bytesDiffer == 0, Comment(rawValue: note)) }
            print("L1.5 \(note)")
        }
    }
}

/// **L1.5b** (`PF-M` item 2, pin). Where a resampled leaf's box lands within a
/// `Float` rounding of an integer at one magnitude and not the other — here a
/// 6 × 6 image whose inner and outer fractions sum to whole device pixels —
/// 2155f1e's `Float` bounding box and the canonical one enclose different
/// rectangles, and the column the canonical raster gains or loses holds the
/// bilinear filter's bleed past the image's edge. Pinned as measured: only the
/// resampled kinds differ, by at most 4 after the blur; every outline stays
/// within 1.
@Test @MainActor func aResampledLeafAtAnIntegerCoincidenceMayGainItsBleedColumn() throws {
    let c = compareCanonical(placed(everyRasterKind(inner: (0.7, 0.3)), x: 20, y: 30).offset(x: px(0.3), y: px(0.7)),
                             scale: 2)
    let note = "\(c)"
    try #require(c.rasters >= 20, Comment(rawValue: note))
    let resampled: Set<String> = ["shadow(image)", "shadow(glyph)", "blur(image)", "blur(glyph)"]
    #expect(Set(c.differing).isSubset(of: resampled) && c.maxDelta <= 4, Comment(rawValue: note))
    print("L1.5b \(note)")
}

// MARK: - L1.6 (PF-B, PF-J): a cut raster misses

/// **L1.6** (`PF-B` item 2, `PF-J`). A shadow cut by a `.clipped()` box keeps
/// today's clipped key: dragged by whole pixels it re-rasterizes every frame,
/// and its image stays cut at the clip's edge (x 100). Two fixtures: a crisp
/// shadow whose offset crosses the edge, and a blurred one where only the
/// blur's padding crosses it. Mutations **M1d** (always uncut), **M1e** (`E`
/// without the blur's padding: the second fixture hits and draws past 100).
@Test @MainActor func aShadowCutByItsClipIsRasterizedOnEveryMove() throws {
    func tree(_ x: Float, radius: Float, offset: Float) -> some Element {
        Color(.accent).frame(width: px(40), height: px(40))
            .shadow(color: .textPrimary, radius: px(radius), x: px(offset), y: px(offset))
            .padding(Edges(top: px(30), right: px(0), bottom: px(0), left: px(x)))
            .frame(width: px(100), height: px(100), alignment: .topLeading).clipped()
            .frame(width: px(300), height: px(300), alignment: .topLeading)
    }
    for (start, radius, offset) in [(Float(70), Float(0), Float(10)), (Float(48), Float(4), Float(0))] {
        let h = TransitionHarness()
        for i in 0..<4 {
            let w = render(h, tree(start + Float(i), radius: radius, offset: offset))
            try #require(w.images.count == 1, "radius \(radius) frame \(i + 1): one shadow")
            let b = w.images[0].image.bounds
            #expect(b.origin.x + b.size.width == 100, "radius \(radius) frame \(i + 1): cut at 100: \(gxDescribe(b))")
            #expect(w.rasterized > 0, "radius \(radius) frame \(i + 1): re-rasterized: \(w.rasterized)")
        }
    }
    // 3.20's literal, unchanged.
    let first = render(TransitionHarness(), tree(70, radius: 0, offset: 10))
    #expect(gxDescribe(first.images[0].image.bounds) == "(80.0, 40.0, 20.0×40.0)",
            "cut bounds: \(gxDescribe(first.images[0].image.bounds))")
}

/// **L1.6b** (`PF-J` item 1; lane 1 verifier's issues 1 and 2). Two more cut
/// fixtures whose extent crosses the clip only through a padding `E` must
/// hold: a `.blur(radius: 4)` square whose blur padding alone reaches the edge
/// (mutation **X1**, `blurImage`'s `E` without `BoxBlur.padding`, lets it hit
/// and draw past 100), and a crisp outer shadow of an inner `radius: 4`
/// shadow, where only the INNER effect's padding crosses (mutation **X5**,
/// `RasterExtent.of`'s nested arms grown by 1, lets the outer raster of the
/// inner shadow hit and draw past 100). Every frame of a whole-pixel drag
/// re-rasterizes, and no image passes the clip's edge.
@Test @MainActor func aBlurOrNestedShadowCutOnlyByItsPaddingIsRasterizedOnEveryMove() throws {
    func clipped(_ e: some Element & ProposalElementGroup, _ x: Float) -> some Element {
        e.padding(Edges(top: px(30), right: px(0), bottom: px(0), left: px(x)))
            .frame(width: px(100), height: px(100), alignment: .topLeading).clipped()
            .frame(width: px(300), height: px(300), alignment: .topLeading)
    }
    func blurred(_ x: Float) -> some Element {
        clipped(Color(.accent).frame(width: px(40), height: px(40)).blur(radius: px(4)), x)
    }
    func nested(_ x: Float) -> some Element {
        clipped(Color(.accent).frame(width: px(40), height: px(40))
            .shadow(color: .textPrimary, radius: px(4))
            .shadow(color: .textPrimary, radius: px(0)), x)
    }
    let hb = TransitionHarness()
    for i in 0..<4 {
        let w = render(hb, blurred(48 + Float(i)))
        try #require(w.images.count == 1, "blur frame \(i + 1): one image: \(w.images.count)")
        let b = w.images[0].image.bounds
        #expect(b.origin.x + b.size.width == 100, "blur frame \(i + 1): cut at 100: \(gxDescribe(b))")
        #expect(w.rasterized + w.blurred > 0, "blur frame \(i + 1): re-rasterized: \(w.rasterized) \(w.blurred)")
    }
    let hn = TransitionHarness()
    for i in 0..<4 {
        let w = render(hn, nested(48 + Float(i)))
        try #require(w.images.count == 3, "nested frame \(i + 1): three images: \(w.images.count)")
        let past = w.images.map(\.image.bounds).filter { $0.origin.x + $0.size.width > 100 }
        #expect(past.isEmpty, "nested frame \(i + 1): nothing past 100: \(past.map(gxDescribe))")
        #expect(w.rasterized > 0, "nested frame \(i + 1): re-rasterized: \(w.rasterized)")
    }
}

// MARK: - L1.7, L1.8 (PF-A): a path and a gradient dragged

/// **L1.7** (`PF-A`). A filled path and a mitred stroke dragged by whole
/// pixels: nothing rasterized or made after frame 1, same textures. Mutation
/// **M1a**.
@Test @MainActor func aPathDraggedByWholePixelsHitsTheCache() throws {
    let content = VStack(spacing: px(4)) {
        gxTriangle(40).fill(.accent).frame(width: px(40), height: px(40))
        gxTriangle(30).stroke(.accent, lineWidth: px(3)).frame(width: px(30), height: px(30))
    }
    let one = try dragMisses({ placed(content, x: 40 + Float($0), y: 50 + Float($0)) }, expectImages: 2)
    #expect(one.isEmpty, "1×: \(one)")
    let two = try dragMisses(scale: 2, { placed(content, x: 40 + Float($0), y: 50).offset(x: px(0.5 * Float($0))) },
                             expectImages: 2)
    #expect(two.isEmpty, "2×: \(two)")
}

/// **L1.8** (`PF-A`, `LK-J`). A full gradient raster (a diagonal gradient in a
/// circle, never the strip) dragged by whole pixels: nothing rasterized or
/// made after frame 1, same texture. Mutation **M1a**.
@Test @MainActor func aGradientRasterDraggedByWholePixelsHitsTheCache() throws {
    let content = Circle().fill(diagonal).frame(width: px(40), height: px(40))
    let one = try dragMisses({ placed(content, x: 40 + Float($0), y: 50) }, expectImages: 1)
    #expect(one.isEmpty, "1×: \(one)")
    let two = try dragMisses(scale: 2, { placed(content, x: 40, y: 50 + Float($0)).offset(y: px(0.5 * Float($0))) },
                             expectImages: 1)
    #expect(two.isEmpty, "2×: \(two)")
}

// MARK: - L1.9 (PF-I): inside a clipped panel

/// **L1.9** (`PF-I`). A shadowed node inside a `.clipped()` panel whose edge
/// the shadow never reaches, dragged by whole pixels: it hits — the panel's
/// clip is every leaf's mask, but it decides no byte, so it is not in the key.
/// Mutation **M1c** (key the masks that decide no byte).
@Test @MainActor func aShadowInsideAClippedPanelHitsWhenDragged() throws {
    let node = nodeContent().shadow(radius: px(10))
    func tree(_ i: Int) -> some Element {
        node.padding(Edges(top: px(50), right: px(0), bottom: px(0), left: px(40 + Float(i))))
            .frame(width: px(250), height: px(250), alignment: .topLeading).clipped()
            .frame(width: px(300), height: px(300), alignment: .topLeading)
    }
    let misses = try dragMisses(tree, expectImages: 9)
    #expect(misses.isEmpty, "\(misses)")
}

// MARK: - L1.10 (PF-D): a sub-pixel move misses

/// **L1.10** (`PF-D`, pin). A 0.25-px move misses (it re-rasterizes) and
/// draws the exact-position bytes — a cold window's at that position. No
/// quantization, no resampling.
@Test @MainActor func aSubPixelMoveMissesAndDrawsTheExactPosition() throws {
    let node = nodeContent().shadow(radius: px(10))
    let h = TransitionHarness()
    _ = render(h, placed(node, x: 40, y: 50).offset(x: px(0)))
    let moved = render(h, placed(node, x: 40, y: 50).offset(x: px(0.25)))
    #expect(moved.rasterized > 0 && moved.blurred > 0,
            "a quarter-pixel move misses: \(moved.rasterized) rasterized, \(moved.blurred) blurred")
    let cold = render(TransitionHarness(), placed(node, x: 40, y: 50).offset(x: px(0.25)))
    #expect(sameImages(moved.images, cold.images) == nil, "\(sameImages(moved.images, cold.images) ?? "")")
}

// MARK: - L1.13 (PF-G): textures made

/// **L1.13** (`PF-G`). `lastTexturesMade` counts what a frame created: frame
/// 1 of one shadowed square makes 1, an unchanged frame 0, a colour change 1
/// (a re-tint, nothing rasterized), and a frame with no raster 0. Mutation
/// **M1g** (the counter not incremented).
@Test @MainActor func texturesMadeCountsTintAndImageMisses() throws {
    func tree(_ color: ColorToken) -> some Element {
        placed(Color(.accent).frame(width: px(40), height: px(40)).shadow(color: color, radius: px(4)), x: 40, y: 40)
    }
    let h = TransitionHarness()
    let first = render(h, tree(.textPrimary))
    #expect(first.made == 1, "frame 1 makes the shadow's texture: \(first.made)")
    let hit = render(h, tree(.textPrimary))
    #expect(hit.made == 0 && hit.rasterized == 0, "a hit makes nothing: \(hit.made), \(hit.rasterized) px")
    let recoloured = render(h, tree(.accent))
    #expect(recoloured.made == 1 && recoloured.rasterized == 0,
            "a colour change re-tints once: \(recoloured.made) made, \(recoloured.rasterized) px")
    let blurred = render(h, placed(Color(.accent).frame(width: px(20), height: px(20)).blur(radius: px(2)), x: 40, y: 40))
    #expect(blurred.made == 1, "a blur's colour image is one texture: \(blurred.made)")
    let none = render(h, placed(Color(.accent).frame(width: px(20), height: px(20)), x: 40, y: 40))
    #expect(none.made == 0, "no raster, nothing made: \(none.made)")
}
