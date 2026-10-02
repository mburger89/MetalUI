import MetalUICore
import MetalUIPath
import MetalUIPrimitives

// Paths, shadows and transforms, lane 3 — CPU rasters and their cache
// (rulings `GX-B`, `GX-J`, `GX-K`). Spec
// `docs/superpowers/specs/2026-10-02-paths-shadows-transforms-design.md` §4.1,
// §4.3.
//
// A path or a shadow travels through the paint scopes as a vector
// (`CapturedPrimitive.path`, `.shadow`) and is rasterized only at
// `Frame.insertIntoScene`, in device pixels under its composed transform, so
// it is crisp under any effect and a ghost or drag preview replays it at its
// replay-time transform. The result is one `MUIImage` (filter nearest, integer
// device bounds) over an `ImageTexture` from the window's `RasterCache`.

/// A path as a paint scope carries it (`GX-B`): the outline in path units
/// (points), how it is painted, the map from path units to (local) device
/// pixels, its colour, and the mask it was emitted under, in the same space as
/// a rect's (`contentMask`: screen space with no transform, local under one).
struct PathPaint {
    enum Mode: Hashable {
        case fill(FillRule, antialiased: Bool)
        case stroke(StrokeParameters)
    }

    var geometry: PathGeometry
    var mode: Mode
    var local: Affine2D
    var color: Hsla
    var contentMask: MUIBounds
    var maskCornerRadii: MUICorners

    /// The outline's control-point box under `local`.
    var bounds: MUIBounds {
        guard let box = geometry.controlPointBounds else {
            return MUIBounds(origin: MUIPoint(x: 0, y: 0), size: MUISize(width: 0, height: 0))
        }
        var b = local.boundingBox(of: MUIBounds(origin: MUIPoint(x: Float(box.minX), y: Float(box.minY)),
                                                size: MUISize(width: Float(box.maxX - box.minX),
                                                              height: Float(box.maxY - box.minY))))
        if case let .stroke(style) = mode {
            let pad = Float(style.width * local.linearScale) * Float(max(style.miterLimit, 2))
            b = MUIBounds(origin: MUIPoint(x: b.origin.x - pad, y: b.origin.y - pad),
                          size: MUISize(width: b.size.width + 2 * pad, height: b.size.height + 2 * pad))
        }
        return b
    }
}

/// One leaf's shadow as a paint scope carries it (`GX-J`): the leaf's
/// primitives as they reached the shadow scope (its *creation space*), the
/// shadow's colour, its radius and offset in creation-space device pixels, the
/// map from creation space to the current space (flattened outer effects), the
/// clip at the shadow scope's entry (which cuts the shadow image; clips pushed
/// inside shape the silhouette instead), and that clip's depth.
struct ShadowPaint {
    var leaf: [CapturedPrimitive]
    var color: Hsla
    var radius: Double
    var dx: Double
    var dy: Double
    var local: Affine2D
    var contentMask: MUIBounds
    var maskCornerRadii: MUICorners
    var entryDepth: Int

    /// The leaf's screen box, offset and grown by the blur, under `local`.
    var bounds: MUIBounds {
        guard let first = leaf.first else {
            return MUIBounds(origin: MUIPoint(x: 0, y: 0), size: MUISize(width: 0, height: 0))
        }
        let union = leaf.dropFirst().reduce(first.screenBounds) { $0.union($1.screenBounds) }
        let pad = Float(3 * radius)
        let grown = MUIBounds(origin: MUIPoint(x: union.origin.x + Float(dx) - pad, y: union.origin.y + Float(dy) - pad),
                              size: MUISize(width: union.size.width + 2 * pad, height: union.size.height + 2 * pad))
        return local.boundingBox(of: grown)
    }
}

/// A value key for a raster (`GX-K`): every number that decides a coverage
/// byte, as bit patterns, plus the outlines and the source textures by
/// identity (held by the entry, so an identifier cannot be reused while the
/// key lives).
struct RasterKey: Hashable {
    var words: [UInt64] = []
    var paths: [PathGeometry] = []
    var objects: [ObjectIdentifier] = []

    mutating func add(_ value: Float) { words.append(UInt64(value.bitPattern)) }
    mutating func add(_ value: Double) { words.append(value.bitPattern) }
    mutating func add(_ value: Int) { words.append(UInt64(bitPattern: Int64(value))) }
    mutating func add(_ value: UInt32) { words.append(UInt64(value)) }
    mutating func add(_ b: MUIBounds) { add(b.origin.x); add(b.origin.y); add(b.size.width); add(b.size.height) }
    mutating func add(_ c: MUICorners) { add(c.topLeft); add(c.topRight); add(c.bottomRight); add(c.bottomLeft) }
    mutating func add(_ e: MUIEdges) { add(e.top); add(e.right); add(e.bottom); add(e.left) }
    mutating func add(_ c: MUIHsla) { add(c.h); add(c.s); add(c.l); add(c.a) }
    mutating func add(_ c: Hsla) { add(c.h); add(c.s); add(c.l); add(c.a) }
    mutating func add(_ m: Affine2D) { add(m.a); add(m.b); add(m.c); add(m.d); add(m.tx); add(m.ty) }
    mutating func add(_ r: RasterRect) { add(r.x); add(r.y); add(r.width); add(r.height) }
}

/// The window's cache of CPU rasters (`GX-K`): coverage by value key, and the
/// tinted texture by (coverage key, colour), so a colour animation re-tints
/// without re-rasterizing and an unchanged path keeps one `ImageTexture`
/// identity (the renderers' texture caches upload it once, `TE-AF`). Entries a
/// frame did not touch are dropped at its end (the `AnimationStore`
/// precedent), so an animated path's old rasters do not accumulate. Owned by
/// the window's `AnimationStore`; a headless frame gets a fresh one.
final class RasterCache {
    private struct Coverage {
        let mask: AlphaMask
        let retained: [AnyObject]
    }

    private struct TintKey: Hashable {
        let key: RasterKey
        let color: [UInt32]
    }

    private var coverage: [RasterKey: Coverage] = [:]
    private var tinted: [TintKey: ImageTexture] = [:]
    private var touchedCoverage: Set<RasterKey> = []
    private var touchedTint: Set<TintKey> = []
    private var rasterizedThisFrame = 0
    private var blurredThisFrame = 0

    /// Device pixels the last completed frame rasterized (coverage misses) — a
    /// work counter, never time.
    private(set) var lastRasterizedPixels = 0
    /// Device pixels the last completed frame blurred (shadow misses).
    private(set) var lastBlurredPixels = 0

    /// Tinted textures held now.
    var textureCount: Int { tinted.count }

    func beginFrame() {
        rasterizedThisFrame = 0
        blurredThisFrame = 0
    }

    func endFrame() {
        if touchedCoverage.count != coverage.count { coverage = coverage.filter { touchedCoverage.contains($0.key) } }
        if touchedTint.count != tinted.count { tinted = tinted.filter { touchedTint.contains($0.key) } }
        touchedCoverage.removeAll(keepingCapacity: true)
        touchedTint.removeAll(keepingCapacity: true)
        lastRasterizedPixels = rasterizedThisFrame
        lastBlurredPixels = blurredThisFrame
    }

    func noteRasterized(_ pixels: Int) { rasterizedThisFrame += pixels }
    func noteBlurred(_ pixels: Int) { blurredThisFrame += pixels }

    /// The coverage for `key`, made by `make` on a miss.
    func coverage(for key: RasterKey, retaining: [AnyObject] = [], _ make: () -> AlphaMask) -> AlphaMask {
        touchedCoverage.insert(key)
        if let hit = coverage[key] { return hit.mask }
        let mask = make()
        coverage[key] = Coverage(mask: mask, retained: retaining)
        return mask
    }

    /// `mask` tinted by `color` (premultiplied, gamma space), for `key`.
    func texture(for key: RasterKey, color: Hsla, mask: AlphaMask) -> ImageTexture {
        let tint = TintKey(key: key, color: [color.h.bitPattern, color.s.bitPattern, color.l.bitPattern,
                                             color.a.bitPattern])
        touchedTint.insert(tint)
        if let hit = tinted[tint] { return hit }
        let texture = RasterCache.tint(mask, color: color)
        tinted[tint] = texture
        return texture
    }

    /// Premultiplied RGBA8 of `color` times each coverage byte, in integers.
    static func tint(_ mask: AlphaMask, color: Hsla) -> ImageTexture {
        let rgb = color.toRgba()
        func byte(_ v: Float) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        let r = byte(rgb.r), g = byte(rgb.g), b = byte(rgb.b), a = byte(color.a)
        var pixels = [UInt8](repeating: 0, count: mask.alpha.count * 4)
        for i in 0..<mask.alpha.count {
            let alpha = (Int(mask.alpha[i]) * a + 127) / 255
            pixels[i * 4] = UInt8((r * alpha + 127) / 255)
            pixels[i * 4 + 1] = UInt8((g * alpha + 127) / 255)
            pixels[i * 4 + 2] = UInt8((b * alpha + 127) / 255)
            pixels[i * 4 + 3] = UInt8(alpha)
        }
        return ImageTexture(width: mask.rect.width, height: mask.rect.height, premultipliedRGBA: pixels)
    }
}

// MARK: - Mask arithmetic

extension Affine2D {
    var pathAffine: PathAffine { PathAffine(a: a, b: b, c: c, d: d, tx: tx, ty: ty) }
}

enum RasterMath {
    /// The device rectangle `bounds` covers, rounded outward.
    static func enclosing(_ b: MUIBounds) -> RasterRect {
        RasterRect.enclosing(minX: Double(b.origin.x), minY: Double(b.origin.y),
                             maxX: Double(b.origin.x + b.size.width), maxY: Double(b.origin.y + b.size.height))
    }

    /// `a` multiplied by `b` per pixel, over the two rectangles' overlap
    /// (outside `b` the product is 0, so the result is trimmed to it).
    static func multiply(_ a: AlphaMask, _ b: AlphaMask) -> AlphaMask {
        let r = a.rect.intersection(b.rect)
        guard !r.isEmpty else { return AlphaMask(rect: RasterRect(x: a.rect.x, y: a.rect.y, width: 0, height: 0), alpha: []) }
        var out = [UInt8](repeating: 0, count: r.area)
        for y in 0..<r.height {
            for x in 0..<r.width {
                let p = Int(a.value(atX: r.x + x, y: r.y + y)), q = Int(b.value(atX: r.x + x, y: r.y + y))
                out[y * r.width + x] = UInt8((p * q + 127) / 255)
            }
        }
        return AlphaMask(rect: r, alpha: out)
    }

    /// `mask` scaled by `factor` (0…1).
    static func scale(_ mask: AlphaMask, by factor: Float) -> AlphaMask {
        guard factor < 1 else { return mask }
        let f = Int((max(factor, 0) * 255).rounded())
        return AlphaMask(rect: mask.rect, alpha: mask.alpha.map { UInt8((Int($0) * f + 127) / 255) })
    }

    /// `mask` restricted to `rect`.
    static func crop(_ mask: AlphaMask, to rect: RasterRect) -> AlphaMask {
        let r = mask.rect.intersection(rect)
        guard !r.isEmpty else { return AlphaMask(rect: RasterRect(x: rect.x, y: rect.y, width: 0, height: 0), alpha: []) }
        if r == mask.rect { return mask }
        var out = [UInt8](repeating: 0, count: r.area)
        for y in 0..<r.height {
            for x in 0..<r.width { out[y * r.width + x] = mask.value(atX: r.x + x, y: r.y + y) }
        }
        return AlphaMask(rect: r, alpha: out)
    }

    /// A rounded rectangle (or an ellipse) outline in local device pixels.
    static func roundedRect(_ b: MUIBounds, _ radii: MUICorners, ellipse: Bool = false) -> PathGeometry {
        let corners = Corners(topLeft: Pixels(radii.topLeft), topRight: Pixels(radii.topRight),
                              bottomRight: Pixels(radii.bottomRight), bottomLeft: Pixels(radii.bottomLeft))
        let rect = Bounds(origin: Point(x: Pixels(b.origin.x), y: Pixels(b.origin.y)),
                          size: Size(width: Pixels(b.size.width), height: Pixels(b.size.height)))
        let geometry: ShapeGeometry = ellipse ? .ellipse(rect)
            : .roundedRectangle(rect, cornerRadii: corners, style: .circular)
        return Path(geometry).storage
    }

    /// The coverage of a rounded-rect mask under `map`, inside `clip`.
    static func maskCoverage(_ b: MUIBounds, _ radii: MUICorners, map: Affine2D, clip: RasterRect,
                             cache: RasterCache) -> AlphaMask {
        var rasterizer = CoverageRasterizer()
        let mask = PathRaster.fill(roundedRect(b, radii), rule: .nonZero, transform: map.pathAffine, clip: clip,
                                   rasterizer: &rasterizer)
        cache.noteRasterized(rasterizer.lastRasterizedPixels)
        return mask
    }
}

/// Where a raster lands (`GX-B`, `GX-J`): the device rectangle to rasterize
/// in, the mask the image is drawn with (the GPU cuts it exactly, rounded
/// corners included), and a local mask to multiply into the coverage when the
/// primitive is transformed (its clip pushed inside the effect).
struct RasterPlacement {
    var clip: RasterRect
    var imageMask: MUIBounds
    var imageRadii: MUICorners
    var localMask: (bounds: MUIBounds, radii: MUICorners, map: Affine2D)?

    init(contentMask: MUIBounds, radii: MUICorners, transform: PrimitiveTransform?, target: RasterRect) {
        if let t = transform {
            imageMask = t.outerMask
            imageRadii = t.outerMaskRadii
            clip = RasterMath.enclosing(t.outerMask).intersection(target)
            if contentMask.size.width < PrimitiveTransform.unboundedThreshold {
                localMask = (contentMask, radii, t.affine)
                clip = clip.intersection(RasterMath.enclosing(t.affine.boundingBox(of: contentMask)))
            }
        } else {
            imageMask = contentMask
            imageRadii = radii
            clip = RasterMath.enclosing(contentMask).intersection(target)
        }
    }

    func keyed(_ key: inout RasterKey) {
        key.add(clip)
        if let localMask {
            key.add(localMask.bounds); key.add(localMask.radii); key.add(localMask.map)
        } else {
            key.add(-1)
        }
    }

    /// `mask` cut by the local mask, when there is one.
    func applyingLocalMask(_ mask: AlphaMask, cache: RasterCache) -> AlphaMask {
        guard let localMask, !mask.rect.isEmpty else { return mask }
        let coverage = RasterMath.maskCoverage(localMask.bounds, localMask.radii, map: localMask.map,
                                               clip: mask.rect, cache: cache)
        return RasterMath.multiply(mask, coverage)
    }

    /// The image quad over `mask`'s rectangle.
    func quad(over mask: AlphaMask) -> MUIImage {
        MUIImage(bounds: MUIBounds(origin: MUIPoint(x: Float(mask.rect.x), y: Float(mask.rect.y)),
                                   size: MUISize(width: Float(mask.rect.width), height: Float(mask.rect.height))),
                 contentMask: imageMask, maskCornerRadii: imageRadii, opacity: 1, texture: 0,
                 filter: ImageFilter.nearest.rawValue, order: 0)
    }
}

// MARK: - Paths

extension Frame {
    /// The device rectangle of the whole surface.
    var rasterTarget: RasterRect {
        RasterRect(x: 0, y: 0, width: Int((contentSize.width.value * scaleFactor).rounded(.up)),
                   height: Int((contentSize.height.value * scaleFactor).rounded(.up)))
    }

    /// A path's image (`GX-B`): rasterized in device pixels under its composed
    /// transform (`transform ∘ local`), inside the visible rectangle only, the
    /// colour multiplied in; `nil` when nothing is visible.
    func pathImage(_ paint: PathPaint, transform: PrimitiveTransform?) -> (MUIImage, ImageTexture)? {
        let placement = RasterPlacement(contentMask: paint.contentMask, radii: paint.maskCornerRadii,
                                        transform: transform, target: rasterTarget)
        guard !placement.clip.isEmpty, paint.color.a > 0 else { return nil }
        let full = (transform?.affine ?? .identity).concatenating(paint.local)
        var key = RasterKey()
        key.paths.append(paint.geometry)
        switch paint.mode {
        case let .fill(rule, antialiased):
            key.add(0); key.add(rule == .evenOdd ? 1 : 0); key.add(antialiased ? 1 : 0)
        case let .stroke(style):
            key.add(1); key.add(style.width); key.add(style.miterLimit); key.add(style.dashPhase)
            key.add(style.cap == .butt ? 0 : style.cap == .round ? 1 : 2)
            key.add(style.join == .miter ? 0 : style.join == .round ? 1 : 2)
            for d in style.dash { key.add(d) }
        }
        key.add(full)
        placement.keyed(&key)
        let cache = animationStore.rasters
        let mask = cache.coverage(for: key) {
            var rasterizer = CoverageRasterizer()
            let coverage: AlphaMask
            switch paint.mode {
            case let .fill(rule, antialiased):
                coverage = PathRaster.fill(paint.geometry, rule: rule, transform: full.pathAffine,
                                           clip: placement.clip, antialiased: antialiased, rasterizer: &rasterizer)
            case let .stroke(style):
                coverage = PathRaster.stroke(paint.geometry, style: style, transform: full.pathAffine,
                                             clip: placement.clip, rasterizer: &rasterizer)
            }
            cache.noteRasterized(rasterizer.lastRasterizedPixels)
            return placement.applyingLocalMask(coverage, cache: cache)
        }
        guard !mask.rect.isEmpty else { return nil }
        return (placement.quad(over: mask), cache.texture(for: key, color: paint.color, mask: mask))
    }
}
