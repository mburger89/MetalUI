import Testing
import Metal
import MetalUICore
import MetalUILayout
import MetalUIScene
@testable import MetalUI

// Paths, shadows and transforms, lane 3 — `Path` and `Shape.path(in:)`
// (rulings `GX-B`, `GX-C`, `GX-D`, `GX-K`; spec
// `docs/superpowers/specs/2026-10-02-paths-shadows-transforms-design.md` §8,
// tests 3.1–3.6, 3.9–3.14, 3.25). SwiftUI's side is
// `docs/probes/swiftui-paths-shadows-transforms.swift`, arms PA1–PA9, T16, N7.
//
// Every arm renders headless `Frame`s (lane 2's `effectFrame`/
// `TransitionHarness`, a 200-point square; the root is centred, `CN-J`) and
// reads the scene: a path reaches it as ONE image (filter nearest, integer
// device bounds, texture the same size) over a `RasterCache` texture.

// MARK: - Fixtures

func gxPoint(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: Pixels(x), y: Pixels(y)) }

func gxRect(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> Bounds<Pixels> {
    Bounds(origin: gxPoint(x, y), size: Size(width: Pixels(w), height: Pixels(h)))
}

/// Every image in `scene` with its texture.
func gxImages(_ scene: Scene) -> [(image: MUIImage, texture: ImageTexture)] {
    scene.images.map { ($0, scene.textures[Int($0.texture)]) }
}

/// The RGBA bytes of `texture` at (x, y), or zeros outside it.
func gxTexel(_ texture: ImageTexture, _ x: Int, _ y: Int) -> [Int] {
    guard x >= 0, y >= 0, x < texture.width, y < texture.height else { return [0, 0, 0, 0] }
    let i = (y * texture.width + x) * 4
    return (0..<4).map { Int(texture.pixels[i + $0]) }
}

/// The alpha an image draws at device pixel (x, y) — its texel, 1 : 1 — or 0
/// outside it.
func gxAlpha(_ entry: (image: MUIImage, texture: ImageTexture), _ x: Int, _ y: Int) -> Int {
    gxTexel(entry.texture, x - Int(entry.image.bounds.origin.x), y - Int(entry.image.bounds.origin.y))[3]
}

func gxDescribe(_ b: MUIBounds) -> String { "(\(b.origin.x), \(b.origin.y), \(b.size.width)×\(b.size.height))" }

/// A closed rectangle path at local (x, y).
func gxRectPath(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> Path { Path(gxRect(x, y, w, h)) }

/// A right triangle filling the lower-left half of a `side` square.
func gxTriangle(_ side: Float) -> Path {
    Path { p in
        p.move(to: gxPoint(0, 0))
        p.addLine(to: gxPoint(side, side))
        p.addLine(to: gxPoint(0, side))
        p.closeSubpath()
    }
}

/// A shape that records the rect `path(in:)` receives (PA9).
final class GXRectLog: @unchecked Sendable { var rects: [Bounds<Pixels>] = [] }

struct GXRecordingShape: Shape {
    let log: GXRectLog
    func path(in rect: Bounds<Pixels>) -> Path {
        log.rects.append(rect)
        return Path(rect)
    }
}

/// A shape implementing neither requirement (`GX-D`'s trap).
struct GXNeitherShape: Shape {}

private let linear1 = Animation.linear(duration: 1)

// MARK: - 3.1 (PA1, PA1b)

/// **3.1** (PA1, PA1b). A `Path` view answers its proposal and draws its own
/// coordinates from its layout origin: a 50 × 40 rect path at (20, 30) in a
/// 30 × 30 frame (centred at 85, 85 in the 200 window) at scale 2 is ONE image
/// at device ((85 + 20) × 2, (85 + 30) × 2), 100 × 80 — neither scaled into
/// the frame nor clipped by it. Red before: no image. Mutation **M3a**: the path
/// scaled into its frame.
@Test @MainActor func aPathViewAnswersItsProposalAndDrawsAtItsOwnCoordinates() throws {
    let frame = effectFrame(gxRectPath(20, 30, 50, 40).frame(width: Pixels(30), height: Pixels(30)),
                            scaleFactor: 2)
    let images = gxImages(frame.finalizedScene())
    try #require(images.count == 1, "one image: \(images.count)")
    let image = images[0].image
    #expect(gxDescribe(image.bounds) == "(210.0, 230.0, 100.0×80.0)", "\(gxDescribe(image.bounds))")
    #expect(image.filterKind == ImageFilter.nearest.rawValue && image.transformIndex == 0,
            "nearest, untransformed: filter \(image.filter)")
    #expect(images[0].texture.width == 100 && images[0].texture.height == 80, "one texel per device pixel")
    #expect(gxTexel(images[0].texture, 50, 40)[3] == 255, "solid inside")
}

// MARK: - 3.2 (PA8)

/// **3.2** (PA8). A bare `Path` fills with the foreground style: `.textPrimary`
/// by default, `.accent` under `.foregroundStyle(.accent)` — its solid texel is
/// the token's colour. Mutation **M3b**: a fixed colour.
@Test @MainActor func aBarePathFillsWithTheForegroundStyle() throws {
    func solid(_ element: some Element) throws -> [Int] {
        let images = gxImages(effectFrame(element).finalizedScene())
        try #require(images.count == 1, "one image")
        return gxTexel(images[0].texture, 20, 20)
    }
    func bytes(_ token: ColorToken) -> [Int] {
        let c = Theme.light[token].toRgba()
        return [c.r, c.g, c.b].map { Int(($0 * 255).rounded()) } + [255]
    }
    let plain = try solid(gxRectPath(0, 0, 40, 40).frame(width: Pixels(40), height: Pixels(40)))
    let styled = try solid(VStack { gxRectPath(0, 0, 40, 40).frame(width: Pixels(40), height: Pixels(40))
        .foregroundStyle(.accent) })
    #expect(plain == bytes(.textPrimary), "textPrimary by default: \(plain)")
    #expect(styled == bytes(.accent), "the foreground style: \(styled)")
}

// MARK: - 3.3 (PA9)

/// **3.3** (PA9). `path(in:)` receives the shape's LOCAL rect, origin (0, 0):
/// a recording shape laid out away from the window's origin is asked for
/// (0, 0, 50 × 30), and its image lands at its layout origin. Mutation
/// **M3c**: the window rect passed.
@Test @MainActor func pathInReceivesTheLocalRect() throws {
    let log = GXRectLog()
    let frame = effectFrame(GXRecordingShape(log: log).frame(width: Pixels(50), height: Pixels(30))
        .padding(Edges(top: Pixels(10), right: Pixels(0), bottom: Pixels(0), left: Pixels(18))))
    try #require(!log.rects.isEmpty, "path(in:) was asked")
    #expect(log.rects.allSatisfy { $0 == gxRect(0, 0, 50, 30) }, "local rects: \(log.rects)")
    let images = gxImages(frame.finalizedScene())
    try #require(images.count == 1, "one image")
    // The padded 68 × 40 root is centred at (66, 80); the shape at + (18, 10).
    #expect(gxDescribe(images[0].image.bounds) == "(84.0, 90.0, 50.0×30.0)",
            "drawn at its layout origin: \(gxDescribe(images[0].image.bounds))")
}

// MARK: - 3.4 (GX-D)

/// **3.4** (exit test, `GX-D`). A shape implementing neither `geometry(in:)`
/// nor `path(in:)` traps at its first paint naming `GX-D`, rather than
/// recursing; a shape implementing `path(in:)` alone renders. Mutation
/// **M3d**: the reentrancy check removed (the recursion overflows the stack
/// with no message).
@Test func aShapeImplementingNeitherRequirementTrapsNamingGXD() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        await MainActor.run {
            _ = effectFrame(GXNeitherShape().frame(width: Pixels(10), height: Pixels(10)))
        }
    }
    let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(stderr.contains("implements neither geometry(in:) nor path(in:)") && stderr.contains("GX-D"),
            "aborted, but not at GX-D's check:\n\(stderr)")
    await #expect(processExitsWith: .success) {
        await MainActor.run {
            _ = effectFrame(GXRecordingShape(log: GXRectLog()).frame(width: Pixels(10), height: Pixels(10)))
        }
    }
}

// MARK: - 3.5 (GX-D)

/// **3.5** (`GX-D`, pin). The built-ins keep their analytic primitive:
/// `Circle().fill` and `RoundedRectangle(8).stroke(lineWidth: 2)` each draw one
/// `MUIRect` and no image. Mutation **M3e**: the default `geometry(in:)` routed
/// through `path(in:)` for every shape.
@Test @MainActor func builtInShapesStillDrawOneSDFRect() {
    let circle = effectFrame(Circle().fill(.accent).frame(width: Pixels(40), height: Pixels(40))).finalizedScene()
    #expect(circle.rects.count == 1 && circle.images.isEmpty,
            "circle: \(circle.rects.count) rects, \(circle.images.count) images")
    let rounded = effectFrame(RoundedRectangle(cornerRadius: Pixels(8)).stroke(.accent, lineWidth: Pixels(2))
        .frame(width: Pixels(60), height: Pixels(40))).finalizedScene()
    #expect(rounded.rects.count == 1 && rounded.images.isEmpty,
            "rounded stroke: \(rounded.rects.count) rects, \(rounded.images.count) images")
}

// MARK: - 3.6 (GX-D)

/// **3.6** (`GX-D`). A built-in's default `path(in:)` is its geometry: on a
/// 1-point grid of pixel centres, `path(in:).contains` equals
/// `geometry(in:).contains` for a rounded rectangle (r 40), a capsule, a
/// circle and a rectangle — at most one disagreement per shape, where a centre
/// lies within the flattening tolerance of the edge — and an ellipse at most
/// eight (four cubics approximate it to 0.027 % of its radius, about 0.016
/// points here, measured: 4). Mutation
/// **M3f**: the corner arcs' control-arm constant 0.5 for 0.5523.
@Test @MainActor func aBuiltInShapesPathMatchesItsGeometry() {
    let rect = gxRect(0, 0, 120, 100)
    func disagreements<S: Shape>(_ shape: S) -> Int {
        let geometry = shape.geometry(in: rect)
        let path = shape.path(in: rect)
        var count = 0
        for j in 0..<100 {
            for i in 0..<120 {
                let p = gxPoint(Float(i) + 0.5, Float(j) + 0.5)
                if path.contains(p) != geometry.contains(p) { count += 1 }
            }
        }
        return count
    }
    let rounded = disagreements(RoundedRectangle(cornerRadius: Pixels(40)))
    let capsule = disagreements(Capsule())
    let circle = disagreements(Circle())
    let ellipse = disagreements(Ellipse())
    let rectangle = disagreements(Rectangle())
    #expect(rounded <= 1 && capsule <= 1 && circle <= 1 && ellipse <= 8 && rectangle == 0,
            "disagreements: rounded \(rounded) capsule \(capsule) circle \(circle) ellipse \(ellipse) rect \(rectangle)")
}

// MARK: - 3.9 (GX-D, IX-L)

/// **3.9** (`GX-D`). `contentShape(path)` hits by winding: a tappable 100 × 100
/// box whose content shape is the lower-left triangle hits at local (20, 80),
/// and misses at its bounding box's corner (80, 20). Mutation **M3i**: a path
/// geometry's `contains` is its bounding box.
@Test @MainActor func contentShapeOfAPathHitsByWinding() throws {
    let frame = effectFrame(Box().frame(width: Pixels(100), height: Pixels(100)).background(.accent)
        .onClick {}.contentShape(gxTriangle(100)))
    let hitbox = try #require(frame.hitboxes.first { $0.handlers.onClick != nil }, "the tap registered")
    let o = hitbox.bounds.origin
    #expect(hitbox.contains(gxPoint(o.x.value + 20, o.y.value + 80)), "inside the triangle hits")
    #expect(!hitbox.contains(gxPoint(o.x.value + 80, o.y.value + 20)), "the box's other corner misses")
}

// MARK: - 3.10 (divergence 91)

/// **3.10** (exit test, divergence 91 amended, `GX-D`). `clipShape` of a path
/// traps naming divergence 91 — every primitive's mask is a rounded rectangle;
/// a rounded rectangle still clips. Mutation **M3j**: a path clip treated as
/// its bounding box.
@Test func clipShapeOfAPathTrapsNamingDivergence91() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        await MainActor.run {
            _ = effectFrame(Color(.accent).frame(width: Pixels(40), height: Pixels(40))
                .clipShape(gxTriangle(40)))
        }
    }
    let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(stderr.contains("clipShape(_:) of a path") && stderr.contains("divergence 91"),
            "aborted, but not at the path clip:\n\(stderr)")
    await #expect(processExitsWith: .success) {
        await MainActor.run {
            _ = effectFrame(Color(.accent).frame(width: Pixels(40), height: Pixels(40))
                .clipShape(RoundedRectangle(cornerRadius: Pixels(8))))
        }
    }
}

// MARK: - 3.11 (T16)

/// **3.11** (T16). A 1-point diagonal stroked width 1 under `scaleEffect(4)`
/// is rasterized at the scaled resolution: one untransformed image about
/// 40 × 40 with solid (255) pixels — a 1-pixel diagonal resampled ×4 has none
/// (its best pixel is about 233). Mutation **M3k**: the raster made at the
/// local resolution and the image transformed.
@Test @MainActor func aPathUnderScaleEffectIsRasterizedAtTheScaledResolution() throws {
    let line = Path { p in
        p.move(to: gxPoint(0, 0))
        p.addLine(to: gxPoint(10, 10))
    }
    let frame = effectFrame(line.stroke(.accent, lineWidth: Pixels(1)).frame(width: Pixels(10), height: Pixels(10))
        .scaleEffect(4))
    let images = gxImages(frame.finalizedScene())
    try #require(images.count == 1, "one image: \(images.count)")
    let (image, texture) = images[0]
    #expect(image.transformIndex == 0, "untransformed")
    #expect(abs(image.bounds.size.width - 42) <= 2 && abs(image.bounds.size.height - 42) <= 2,
            "about 40 × 40 (and the cap): \(gxDescribe(image.bounds))")
    let solid = stride(from: 3, to: texture.pixels.count, by: 4).filter { texture.pixels[$0] == 255 }.count
    #expect(solid >= 40, "solid pixels along the scaled diagonal: \(solid)")
}

// MARK: - 3.12 (GX-B)

/// **3.12** (`GX-B`). A path under a rotation is rasterized in device space:
/// a 40 × 10 rect path turned 90° is one UNTRANSFORMED image about 10 wide and
/// 40 tall, solid at its centre. Mutation **M3k**.
@Test @MainActor func aRotatedPathIsRasterizedInDeviceSpace() throws {
    let frame = effectFrame(gxRectPath(0, 0, 40, 10).fill(.accent).frame(width: Pixels(40), height: Pixels(10))
        .rotationEffect(.degrees(90)))
    let scene = frame.finalizedScene()
    let images = gxImages(scene)
    try #require(images.count == 1, "one image: \(images.count)")
    let image = images[0].image
    #expect(image.transformIndex == 0 && scene.transforms.isEmpty, "no record: \(scene.transforms.count)")
    #expect(abs(image.bounds.size.width - 10) <= 1 && abs(image.bounds.size.height - 40) <= 1,
            "turned: \(gxDescribe(image.bounds))")
    #expect(gxAlpha(images[0], 100, 100) == 255, "solid at the centre")
}

// MARK: - 3.13 (GX-K)

/// **3.13** (`GX-K`). A raster is reused across frames and dropped when unused:
/// frame 2 draws the same `ImageTexture` (identity) and rasterizes nothing;
/// after a frame without the path the cache is empty, and the path's return
/// rasterizes a new texture. Mutation **M3l**: no cache.
@Test @MainActor func aRasterIsReusedAcrossFramesAndDroppedWhenUnused() throws {
    let h = TransitionHarness()
    func tree(_ shown: Bool) -> some Element {
        VStack {
            Color(.separator).frame(width: Pixels(10), height: Pixels(10))
            if shown { gxTriangle(40).fill(.accent).frame(width: Pixels(40), height: Pixels(40)) }
        }
    }
    let first = h.frame(0, nil, tree(true), side: 200)
    let texture1 = try #require(first.scene.textures.first, "frame 1 drew the path")
    try #require(h.store.rasters.lastRasterizedPixels > 0, "frame 1 rasterized")
    let second = h.frame(0, nil, tree(true), side: 200)
    let texture2 = try #require(second.scene.textures.first, "frame 2 drew the path")
    #expect(texture1 === texture2, "the same texture identity")
    #expect(h.store.rasters.lastRasterizedPixels == 0, "nothing rasterized: \(h.store.rasters.lastRasterizedPixels)")
    h.frame(0, nil, tree(false), side: 200)
    #expect(h.store.rasters.textureCount == 0, "dropped: \(h.store.rasters.textureCount)")
    let fourth = h.frame(0, nil, tree(true), side: 200)
    let texture4 = try #require(fourth.scene.textures.first, "frame 4 drew the path")
    #expect(texture4 !== texture1 && h.store.rasters.lastRasterizedPixels > 0, "re-rasterized on return")
}

// MARK: - 3.14 (GX-K)

/// **3.14** (`GX-K`). The cache key holds every field that decides a byte:
/// from a resting frame, changing the colour re-tints (a new texture, nothing
/// rasterized); changing the transform, the clip or the path re-rasterizes.
/// Mutations **M3m** (four): each key field dropped in turn.
@Test @MainActor func theCacheKeyIncludesColourTransformAndClip() throws {
    struct Variant { var token: ColorToken = .accent; var scale = 1.0; var clip: Float = 60; var side: Float = 40 }
    func tree(_ v: Variant) -> some Element {
        gxTriangle(v.side).fill(v.token).frame(width: Pixels(40), height: Pixels(40)).scaleEffect(v.scale)
            .frame(width: Pixels(v.clip), height: Pixels(40)).clipped()
    }
    func change(_ v: Variant) throws -> (same: Bool, rasterized: Int) {
        let h = TransitionHarness()
        let rest = h.frame(0, nil, tree(Variant()), side: 200).scene.textures
        let changed = h.frame(0, nil, tree(v), side: 200).scene.textures
        try #require(rest.count == 1 && changed.count == 1, "both frames drew the path")
        return (rest[0] === changed[0], h.store.rasters.lastRasterizedPixels)
    }
    let colour = try change(Variant(token: .separator))
    #expect(!colour.same && colour.rasterized == 0, "colour re-tints: same \(colour.same), \(colour.rasterized) px")
    let transform = try change(Variant(scale: 1.5))
    #expect(!transform.same && transform.rasterized > 0, "transform: same \(transform.same), \(transform.rasterized) px")
    let clip = try change(Variant(clip: 20))
    #expect(!clip.same && clip.rasterized > 0, "clip: same \(clip.same), \(clip.rasterized) px")
    let path = try change(Variant(side: 30))
    #expect(!path.same && path.rasterized > 0, "path: same \(path.same), \(path.rasterized) px")
}

// MARK: - 3.25 (N7)

/// **3.25** (N7, pin). A `Path` view whose path changes snaps under
/// `withAnimation`: half-way through a 20 → 60 wide rect the image is 60 wide.
/// Mutation **M3x**: the path view's outline interpolated.
@Test @MainActor func aPathViewWhosePathChangesSnaps() throws {
    let h = TransitionHarness()
    func tree(_ wide: Bool) -> some Element {
        gxRectPath(0, 0, wide ? 60 : 20, 20).frame(width: Pixels(100), height: Pixels(100))
    }
    h.frame(0, nil, tree(false), side: 200)
    h.frame(0, linear1, tree(true), side: 200)
    let images = gxImages(h.frame(0.5, nil, tree(true), side: 200).finalizedScene())
    try #require(images.count == 1, "one image")
    #expect(images[0].image.bounds.size.width == 60, "snapped to 60: \(gxDescribe(images[0].image.bounds))")
}

// MARK: - 3.29 (divergence 106)

/// **3.29** (divergence 106, `GX-L`; pin, green on arrival). Text under a
/// scale effect is RESAMPLED, not re-rasterized: under `scaleEffect(3)` every
/// glyph keeps its atlas slot (the same size as unscaled) and draws it three
/// times larger — SwiftUI re-rasterizes at the effective scale (T15b). A path
/// is re-rasterized (3.11).
@Test @MainActor func aTextUnderScaleEffectIsResampledNotReRasterized() throws {
    let plain = effectFrame(Text("Aa").font(size: 12)).finalizedScene()
    let scaled = effectFrame(Text("Aa").font(size: 12).scaleEffect(3)).finalizedScene()
    try #require(!plain.glyphs.isEmpty && plain.glyphs.count == scaled.glyphs.count, "the same glyphs")
    for (p, s) in zip(plain.glyphs, scaled.glyphs) {
        #expect(s.atlasBounds.size.width == p.atlasBounds.size.width
                && s.atlasBounds.size.height == p.atlasBounds.size.height, "the same atlas slot")
        #expect(abs(s.bounds.size.width - 3 * p.bounds.size.width) < 1e-3, "drawn ×3: \(s.bounds.size.width)")
    }
}

// MARK: - 3.30 (divergence 97 amended)

/// **3.30** (divergence 97 amended, N8; pin, green on arrival). A shape's
/// stroke width snaps where SwiftUI animates it: half-way through
/// `stroke(lineWidth:)` 2 → 10 under `withAnimation` the band is 10 wide.
@Test @MainActor func aShapesStrokeWidthSnaps() throws {
    let h = TransitionHarness()
    func tree(_ wide: Bool) -> some Element {
        Rectangle().stroke(.accent, lineWidth: Pixels(wide ? 10 : 2)).frame(width: Pixels(60), height: Pixels(40))
    }
    h.frame(0, nil, tree(false), side: 200)
    h.frame(0, linear1, tree(true), side: 200)
    let rects = h.frame(0.5, nil, tree(true), side: 200).finalizedScene().rects
    try #require(rects.count == 1, "one band")
    #expect(rects[0].borderWidths.top == 10, "snapped to 10: \(rects[0].borderWidths.top)")
}
