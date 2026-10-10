import MetalUICore
import MetalUILayout
import MetalUIPath
import MetalUIPrimitives
import MetalUIScene

// C10 lane 3 — the gradient raster (ruling `LK-J` items 4–6). A gradient fill
// or stroke travels the paint scopes as a vector (`CapturedPrimitive.gradient`,
// the `.path` precedent, `GX-B`) and is rasterized at `Frame.insertIntoScene`
// in device pixels under its composed transform into ONE image over a
// `RasterCache` texture:
//
// - **the strip** (`LK-J` item 5): an axis-aligned linear gradient filling an
//   untransformed rectangle or rounded rectangle wholly inside its clip is a
//   `1 × H` or `W × 1` texture over the rect's own bounds (fractional), linear-
//   filtered, the rect's radii its mask — O(length) per miss, so a window
//   background resized every frame stays cheap;
// - **the full raster** for everything else: coverage (`PathRaster`) × the
//   table colour at each pixel centre mapped back into the outline's space
//   (nearest, integer device bounds, as a path's image).
//
// No shader line moves on either renderer (`TE-AD` by construction, `LK-S`).

/// A gradient as a paint scope carries it (`LK-J` item 4): the outline in
/// window points before the scroll translation, how it is painted, the
/// strip-eligible rectangle when the outline is a built-in rounded rectangle,
/// the gradient's axis in the outline's space, the resolved stops, the map
/// from the outline's space to (local) device pixels, the opacity, and the
/// mask it was emitted under — `PathPaint`'s shape.
struct GradientPaint {
    /// A rounded rectangle in the outline's space (points), for the strip.
    struct Strip: Hashable {
        var x: Double, y: Double, width: Double, height: Double
        var radii: [Double]   // topLeft, topRight, bottomRight, bottomLeft
    }

    var geometry: PathGeometry
    var mode: PathPaint.Mode
    var strip: Strip?
    var axis: GradientAxis
    var stops: GradientStops
    var local: Affine2D
    var opacity: Float
    var contentMask: MUIBounds
    var maskCornerRadii: MUICorners

    /// The outline's box under `local` (a stroke grown as a path's is).
    var bounds: MUIBounds {
        PathPaint(geometry: geometry, mode: mode, local: local, color: .black, contentMask: contentMask,
                  maskCornerRadii: maskCornerRadii).bounds
    }
}

// MARK: - The layers

extension PaintPass {
    /// Emits `fill` over `geometry` (`LK-J`): its stops resolved here, its
    /// axis over the geometry's bounding rectangle.
    func drawGradient(_ fill: GradientFill, geometry: ShapeGeometry, mode: PathPaint.Mode, path: Path,
                      strip: Bool) {
        let stops = GradientStops(fill.gradient, resolve: { resolve($0) })
        guard !stops.isEmpty else { return }
        frame.drawGradient(path, mode: mode, rect: geometry.rect,
                           radii: strip ? geometry.cornerRadii : nil,
                           axis: fill.axis(in: geometry.rect), stops: stops)
    }
}

/// One gradient fill layer (`LK-J`): a built-in rounded rectangle is offered
/// to the strip; an ellipse or a path is rasterized in full. `style`
/// overrides a path geometry's own fill style, as a colour fill's does.
@MainActor
func paintGradientFill(_ fill: GradientFill, _ geometry: ShapeGeometry, style: FillStyle?, pass: PaintPass) {
    if let (path, own) = geometry.pathAndStyle {
        let s = style ?? own
        pass.drawGradient(fill, geometry: geometry, mode: .fill(s.rule, antialiased: s.isAntialiased),
                          path: path, strip: false)
        return
    }
    let s = style ?? FillStyle()
    let roundedRect = geometry.primitiveShape == .roundedRectangle
    pass.drawGradient(fill, geometry: geometry, mode: .fill(s.rule, antialiased: s.isAntialiased),
                      path: Path(geometry), strip: roundedRect && s.isAntialiased)
}

/// One centred gradient stroke layer (`LK-J`): the outline stroked on the
/// CPU, coloured over the geometry's bounding rectangle. A width ≤ 0 draws
/// nothing.
@MainActor
func paintGradientStroke(_ fill: GradientFill, _ geometry: ShapeGeometry, style: StrokeStyle, pass: PaintPass) {
    guard style.lineWidth.value > 0 else { return }
    let path = geometry.pathAndStyle?.path ?? Path(geometry)
    pass.drawGradient(fill, geometry: geometry, mode: .stroke(style.parameters), path: path, strip: false)
}

// MARK: - Frame

extension Frame {
    /// Emits a gradient (`LK-J`): as ``drawPath(_:mode:color:)`` places a
    /// path — the active offset, clip, opacity and layer — a vector through
    /// the paint scopes, rasterized at `insertIntoScene`.
    func drawGradient(_ path: Path, mode: PathPaint.Mode, rect: Bounds<Pixels>, radii: Corners<Pixels>?,
                      axis: GradientAxis, stops: GradientStops) {
        guard !path.isEmpty, activeOpacity > 0 else { return }
        let s = Double(scaleFactor)
        let local = Affine2D(a: s, d: s, tx: Double(activeOffset.x.value) * s, ty: Double(activeOffset.y.value) * s)
        let strip = radii.map {
            GradientPaint.Strip(x: Double(rect.origin.x.value), y: Double(rect.origin.y.value),
                                width: Double(rect.size.width.value), height: Double(rect.size.height.value),
                                radii: [Double($0.topLeft.value), Double($0.topRight.value),
                                        Double($0.bottomRight.value), Double($0.bottomLeft.value)])
        }
        let paint = GradientPaint(geometry: path.storage, mode: mode, strip: strip, axis: axis, stops: stops,
                                  local: local, opacity: activeOpacity,
                                  contentMask: MUIBounds(activeClip.scaled(by: scaleFactor)),
                                  maskCornerRadii: MUICorners(activeClipRadii.scaled(by: scaleFactor)))
        let primitive = CapturedPrimitive(kind: .gradient(paint), layer: activeLayer, innerMask: false)
        if paintScopes.isEmpty {
            insertIntoScene(primitive)
        } else {
            insertThroughScopes(primitive)
        }
    }

    /// A gradient's image (`LK-J` items 4–5): the strip when it applies, else
    /// the full raster; `nil` when nothing is visible.
    func gradientImage(_ paint: GradientPaint, transform: PrimitiveTransform?) -> (MUIImage, ImageTexture)? {
        let placement = RasterPlacement(contentMask: paint.contentMask, radii: paint.maskCornerRadii,
                                        transform: transform, target: rasterTarget)
        guard !placement.clip.isEmpty, paint.opacity > 0, !paint.stops.isEmpty else { return nil }
        let full = (transform?.affine ?? .identity).concatenating(paint.local)
        let cache = animationStore.rasters
        if transform == nil, let strip = stripImage(paint, full: full, cache: cache) { return strip }
        var key = RasterKey()
        key.add(6)
        key.paths.append(paint.geometry)
        keyMode(paint.mode, into: &key)
        key.add(full)
        placement.keyed(&key)
        key.words += paint.stops.keyWords
        for w in paint.axis.words { key.add(w) }
        guard let (rect, texture) = cache.image(for: key, make: {
            let layer = gradientPixels(paint, full: full, clip: placement.clip, cache: cache)
            guard !layer.rect.isEmpty else { return nil }
            var cut = layer
            if let localMask = placement.localMask {
                cut = layer.multiplied(by: RasterMath.maskCoverage(localMask.bounds, localMask.radii,
                                                                    map: localMask.map, clip: layer.rect,
                                                                    cache: cache))
            }
            guard !cut.rect.isEmpty else { return nil }
            return (cut.rect, cut.texture)
        }) else { return nil }
        var quad = placement.quad(over: rect)
        quad.opacity = paint.opacity
        return (quad, texture)
    }

    /// The strip (`LK-J` item 5), or `nil` when it does not apply: a linear
    /// gradient along exactly one axis, a fill, a rounded rectangle under a
    /// uniform positive scale plus translation, wholly inside its clip.
    private func stripImage(_ paint: GradientPaint, full: Affine2D, cache: RasterCache) -> (MUIImage, ImageTexture)? {
        guard case .fill(_, true) = paint.mode, let strip = paint.strip,
              case let .linear(sx, sy, ex, ey) = paint.axis, (sx == ex) != (sy == ey),
              full.isUniformPositiveScaleTranslation else { return nil }
        let x0 = full.a * strip.x + full.tx, y0 = full.d * strip.y + full.ty
        let w = full.a * strip.width, h = full.d * strip.height
        guard w > 0, h > 0 else { return nil }
        // Wholly inside the clip, away from its rounded corners.
        let m = paint.contentMask, mr = paint.maskCornerRadii
        let inset = Double(max(mr.topLeft, mr.topRight, mr.bottomRight, mr.bottomLeft))
        let epsilon = 1e-3
        guard x0 >= Double(m.origin.x) + inset - epsilon, y0 >= Double(m.origin.y) - epsilon,
              x0 + w <= Double(m.origin.x + m.size.width) - inset + epsilon,
              y0 + h <= Double(m.origin.y + m.size.height) + epsilon,
              (inset == 0 || (y0 >= Double(m.origin.y) + inset - epsilon
                              && y0 + h <= Double(m.origin.y + m.size.height) - inset + epsilon))
        else { return nil }
        let vertical = sx == ex
        let length = vertical ? h : w
        let count = max(1, Int((length - epsilon).rounded(.up)))
        let origin = vertical ? y0 : x0
        // The axis's ends in device pixels along the strip.
        let start = vertical ? full.d * sy + full.ty : full.a * sx + full.tx
        let end = vertical ? full.d * ey + full.ty : full.a * ex + full.tx
        var key = RasterKey()
        key.add(5); key.add(vertical ? 1 : 0); key.add(count)
        key.add(origin); key.add(length); key.add(start); key.add(end)
        key.words += paint.stops.keyWords
        let stops = paint.stops
        guard let (_, texture) = cache.image(for: key, make: {
            let table = cache.gradientTable(stops)
            var pixels = [UInt8](repeating: 0, count: count * 4)
            for i in 0..<count {
                let p = origin + (Double(i) + 0.5) * length / Double(count)
                let v = table[GradientTable.index((p - start) / (end - start))]
                pixels[i * 4] = UInt8(v & 0xFF); pixels[i * 4 + 1] = UInt8((v >> 8) & 0xFF)
                pixels[i * 4 + 2] = UInt8((v >> 16) & 0xFF); pixels[i * 4 + 3] = UInt8(v >> 24)
            }
            cache.noteRasterized(count)
            let texture = ImageTexture(width: vertical ? 1 : count, height: vertical ? count : 1,
                                       premultipliedRGBA: pixels)
            return (RasterRect(x: 0, y: 0, width: 0, height: 0), texture)
        }) else { return nil }
        let bounds = MUIBounds(origin: MUIPoint(x: Float(x0), y: Float(y0)), size: MUISize(width: Float(w), height: Float(h)))
        let s = Float(full.a)
        let r = strip.radii.map { Float($0) * s }
        let quad = MUIImage(bounds: bounds, contentMask: bounds,
                            maskCornerRadii: MUICorners(topLeft: r[0], topRight: r[1], bottomRight: r[2], bottomLeft: r[3]),
                            opacity: paint.opacity, texture: 0, filter: ImageFilter.linear.rawValue, order: 0)
        return (quad, texture)
    }

    /// `paint`'s premultiplied colour in device pixels under `full`, inside
    /// `clip`: coverage × the table colour at each pixel centre, mapped back
    /// into the outline's space (`LK-J` item 2). Before its opacity and mask.
    func gradientPixels(_ paint: GradientPaint, full: Affine2D, clip: RasterRect, cache: RasterCache) -> RGBALayer {
        var rasterizer = CoverageRasterizer()
        let coverage: AlphaMask
        switch paint.mode {
        case let .fill(rule, antialiased):
            coverage = PathRaster.fill(paint.geometry, rule: rule, transform: full.pathAffine, clip: clip,
                                       antialiased: antialiased, rasterizer: &rasterizer)
        case let .stroke(style):
            coverage = PathRaster.stroke(paint.geometry, style: style, transform: full.pathAffine, clip: clip,
                                         rasterizer: &rasterizer)
        }
        cache.noteRasterized(rasterizer.lastRasterizedPixels)
        guard let inverse = full.inverted, !coverage.rect.isEmpty else { return .empty }
        let table = cache.gradientTable(paint.stops)
        let r = coverage.rect
        var pixels = [UInt8](repeating: 0, count: r.area * 4)
        for y in 0..<r.height {
            for x in 0..<r.width {
                let c = Int(coverage.alpha[y * r.width + x])
                guard c > 0 else { continue }
                let p = inverse.apply(Double(r.x + x) + 0.5, Double(r.y + y) + 0.5)
                let v = table[GradientTable.index(paint.axis.parameter(x: p.x, y: p.y))]
                let i = (y * r.width + x) * 4
                pixels[i] = UInt8((Int(v & 0xFF) * c + 127) / 255)
                pixels[i + 1] = UInt8((Int((v >> 8) & 0xFF) * c + 127) / 255)
                pixels[i + 2] = UInt8((Int((v >> 16) & 0xFF) * c + 127) / 255)
                pixels[i + 3] = UInt8((Int(v >> 24) * c + 127) / 255)
            }
        }
        return RGBALayer(rect: r, pixels: pixels)
    }

    func keyMode(_ mode: PathPaint.Mode, into key: inout RasterKey) {
        switch mode {
        case let .fill(rule, antialiased):
            key.add(0); key.add(rule == .evenOdd ? 1 : 0); key.add(antialiased ? 1 : 0)
        case let .stroke(style):
            key.add(1); key.add(style.width); key.add(style.miterLimit); key.add(style.dashPhase)
            key.add(style.cap == .butt ? 0 : style.cap == .round ? 1 : 2)
            key.add(style.join == .miter ? 0 : style.join == .round ? 1 : 2)
            for d in style.dash { key.add(d) }
        }
    }
}

// MARK: - Four-channel layers (gradients, `LK-K`'s blur)

/// Premultiplied RGBA8 over a device rectangle — what a gradient raster and
/// a blurred leaf are made of (`LK-J`, `LK-K`).
struct RGBALayer {
    var rect: RasterRect
    var pixels: [UInt8]

    static let empty = RGBALayer(rect: RasterRect(x: 0, y: 0, width: 0, height: 0), pixels: [])

    /// `mask` tinted by `color` (gamma, straight alpha).
    init(mask: AlphaMask, color: Hsla) {
        let texture = RasterCache.tint(mask, color: color)
        self.init(rect: mask.rect, pixels: texture.pixels)
    }

    init(rect: RasterRect, pixels: [UInt8]) {
        self.rect = rect
        self.pixels = pixels
    }

    /// The texel at device (x, y), zeros outside.
    func texel(atX x: Int, y: Int) -> (Int, Int, Int, Int) {
        guard x >= rect.x, y >= rect.y, x < rect.maxX, y < rect.maxY else { return (0, 0, 0, 0) }
        let i = ((y - rect.y) * rect.width + (x - rect.x)) * 4
        return (Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2]), Int(pixels[i + 3]))
    }

    /// Every channel times `mask` (0 outside it), trimmed to the overlap.
    func multiplied(by mask: AlphaMask) -> RGBALayer {
        let r = rect.intersection(mask.rect)
        guard !r.isEmpty else { return .empty }
        var out = [UInt8](repeating: 0, count: r.area * 4)
        for y in 0..<r.height {
            for x in 0..<r.width {
                let m = Int(mask.value(atX: r.x + x, y: r.y + y))
                let t = texel(atX: r.x + x, y: r.y + y)
                let i = (y * r.width + x) * 4
                out[i] = UInt8((t.0 * m + 127) / 255); out[i + 1] = UInt8((t.1 * m + 127) / 255)
                out[i + 2] = UInt8((t.2 * m + 127) / 255); out[i + 3] = UInt8((t.3 * m + 127) / 255)
            }
        }
        return RGBALayer(rect: r, pixels: out)
    }

    /// Every channel times `factor` (0…1).
    func scaled(by factor: Float) -> RGBALayer {
        guard factor < 1 else { return self }
        let f = Int((max(factor, 0) * 255).rounded())
        return RGBALayer(rect: rect, pixels: pixels.map { UInt8((Int($0) * f + 127) / 255) })
    }

    /// `top` composited over this layer (source-over, premultiplied), over the
    /// union of the two rectangles.
    func under(_ top: RGBALayer) -> RGBALayer {
        if rect.isEmpty { return top }
        if top.rect.isEmpty { return self }
        let r = rect.union(top.rect)
        var out = [UInt8](repeating: 0, count: r.area * 4)
        for y in r.y..<r.maxY {
            for x in r.x..<r.maxX {
                let b = texel(atX: x, y: y), t = top.texel(atX: x, y: y)
                let k = 255 - t.3
                let i = ((y - r.y) * r.width + (x - r.x)) * 4
                out[i] = UInt8(min(255, t.0 + (b.0 * k + 127) / 255))
                out[i + 1] = UInt8(min(255, t.1 + (b.1 * k + 127) / 255))
                out[i + 2] = UInt8(min(255, t.2 + (b.2 * k + 127) / 255))
                out[i + 3] = UInt8(min(255, t.3 + (b.3 * k + 127) / 255))
            }
        }
        return RGBALayer(rect: r, pixels: out)
    }

    /// One channel as a mask (0 red … 3 alpha).
    func channel(_ c: Int) -> AlphaMask {
        AlphaMask(rect: rect, alpha: stride(from: c, to: pixels.count, by: 4).map { pixels[$0] })
    }

    /// Four masks over one rectangle recombined, each colour clamped to the
    /// alpha (premultiplied).
    init(channels: [AlphaMask]) {
        let r = channels[3].rect
        var out = [UInt8](repeating: 0, count: r.area * 4)
        for i in 0..<r.area {
            let a = channels[3].alpha[i]
            out[i * 4] = min(channels[0].alpha[i], a); out[i * 4 + 1] = min(channels[1].alpha[i], a)
            out[i * 4 + 2] = min(channels[2].alpha[i], a); out[i * 4 + 3] = a
        }
        self.init(rect: r, pixels: out)
    }

    /// Cut to `clip`.
    func cropped(to clip: RasterRect) -> RGBALayer {
        let r = rect.intersection(clip)
        guard !r.isEmpty else { return .empty }
        if r == rect { return self }
        var out = [UInt8](repeating: 0, count: r.area * 4)
        for y in 0..<r.height {
            let source = ((r.y - rect.y + y) * rect.width + (r.x - rect.x)) * 4
            for k in 0..<(r.width * 4) { out[y * r.width * 4 + k] = pixels[source + k] }
        }
        return RGBALayer(rect: r, pixels: out)
    }

    var texture: ImageTexture { ImageTexture(width: rect.width, height: rect.height, premultipliedRGBA: pixels) }
}
