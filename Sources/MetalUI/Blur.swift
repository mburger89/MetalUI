import MetalUICore
import MetalUILayout
import MetalUIPath
import MetalUIPrimitives

// C10 lane 3 — `.blur(radius:)` (ruling `LK-K`). Spec
// `docs/superpowers/specs/2026-10-08-controls-looks-design.md` §1, §3.3;
// SwiftUI's side is `docs/probes/swiftui-controls-looks.swift`, arms B1–B5.

// MARK: - The proposal vocabulary (one `LayoutModifier` layer, `LK-K`)

extension ProposalElementGroup {
    /// Blurs each leaf of this view — SwiftUI's `blur(radius:)`. **Per leaf**
    /// (probe B2: a blue square over a red one blurred together reads as each
    /// blurred alone), a text draw counting as one leaf; Gaussian with sigma
    /// equal to `radius` (B1, divergence 105's three-box approximation); the
    /// image grows by the blur's reach and a clip outside cuts it (B5).
    /// **Render only**: no layout change (B4), no hit region, nothing
    /// published. A GPU surface (`GPUSurface`, `MetalView`) inside is drawn
    /// unblurred (divergence 167). The radius animates; a radius ≤ 0 draws the
    /// content unchanged; a non-finite one traps. One layer, one identity
    /// level (`MC-C`).
    public func blur(radius: Pixels) -> ModifiedContent<ProposalBase, LayoutModifier> {
        precondition(radius.value.isFinite, "blur(radius:) needs a finite radius, got \(radius.value) (LK-K)")
        return _wrapLayout(.blur(radius: radius))
    }
}

// MARK: - The legacy vocabulary (`Decoration.renderEffects`, `LK-K`)

extension StyledElement {
    /// Blurs each leaf of this element — SwiftUI's `blur(radius:)`, returning
    /// `Self` (no identity level). It joins the element's render effects in
    /// written order and, like them, wraps the whole element: its background,
    /// content and border (divergence 108). See the proposal spelling for the
    /// rules.
    public func blur(radius: Pixels) -> Self {
        precondition(radius.value.isFinite, "blur(radius:) needs a finite radius, got \(radius.value) (LK-K)")
        return appendingRenderEffect(.blur(radius: radius))
    }
}

// MARK: - The paint scope

/// One leaf blurred, as a paint scope carries it (`LK-K`): the leaf's
/// primitives as they reached the blur scope (its creation space), the radius
/// in creation-space device pixels, the map from creation space to the
/// current space (flattened outer effects), the clip at the blur scope's
/// entry (which cuts the image; clips pushed inside shape the leaf), that
/// clip's depth, and an opacity outer scopes multiplied in.
struct BlurPaint {
    var leaf: [CapturedPrimitive]
    var radius: Double
    var local: Affine2D
    var contentMask: MUIBounds
    var maskCornerRadii: MUICorners
    var entryDepth: Int
    var alpha: Float = 1

    /// The leaf's screen box grown by the blur, under `local`.
    var bounds: MUIBounds {
        guard let first = leaf.first else {
            return MUIBounds(origin: MUIPoint(x: 0, y: 0), size: MUISize(width: 0, height: 0))
        }
        let union = leaf.dropFirst().reduce(first.screenBounds) { $0.union($1.screenBounds) }
        let pad = Float(3 * radius)
        let grown = MUIBounds(origin: MUIPoint(x: union.origin.x - pad, y: union.origin.y - pad),
                              size: MUISize(width: union.size.width + 2 * pad, height: union.size.height + 2 * pad))
        return local.boundingBox(of: grown)
    }
}

extension PaintPass {
    /// Runs `body` inside a blur scope (`LK-K`).
    func withBlur(radius: Pixels, _ body: () -> Void) {
        frame.paintWithBlur(radius: radius, body)
    }
}

extension Frame {
    /// Paint inside a blur scope (`LK-K`): every leaf emitted in `body` is
    /// replaced by its blurred image, except a GPU surface (divergence 167).
    /// `radius` in points; a radius ≤ 0 opens no scope, so the leaves draw
    /// unchanged. The clip in force cuts the image; clips pushed inside shape
    /// the leaf. Pushes no effect scope (`effectScopesPushed` unmoved).
    func paintWithBlur(radius: Pixels, _ body: () -> Void) {
        let r = Double(radius.value)
        guard r > 0 else { return body() }
        let scope = PaintScope(kind: .blur, effect: .identity, entryClipDepth: clipDepth)
        scope.blur = PaintScope.Blur(radius: r * Double(scaleFactor),
                                     mask: MUIBounds(activeClip.scaled(by: scaleFactor)),
                                     radii: MUICorners(activeClipRadii.scaled(by: scaleFactor)))
        paintScopes.append(scope)
        body()
        paintScopes.removeLast()
    }

    /// `leaf` blurred under a blur scope, in the space it reached it in.
    func blurItem(of leaf: [CapturedPrimitive], _ blur: PaintScope.Blur, entryDepth: Int) -> CapturedPrimitive {
        let paint = BlurPaint(leaf: leaf, radius: blur.radius, local: .identity, contentMask: blur.mask,
                              maskCornerRadii: blur.radii, entryDepth: entryDepth)
        return CapturedPrimitive(kind: .blur(paint), layer: leaf.first?.layer ?? activeLayer, innerMask: false)
    }

    /// A blurred leaf's image (`LK-K`): the leaf in colour in device pixels
    /// under the composed transform, each premultiplied channel blurred with
    /// sigma = radius × `sqrt|det|`, cut by the clip at the blur's entry. Made
    /// and keyed in canonical coordinates, as a shadow's (`PF-A`, `PF-B`): the
    /// cached rectangle is canonical and placed at the integer device anchor.
    func blurImage(_ paint: BlurPaint, transform: PrimitiveTransform?) -> (MUIImage, ImageTexture)? {
        animationStore.rasters.onRaster?(.blur(paint), transform)
        let placement = RasterPlacement(contentMask: paint.contentMask, radii: paint.maskCornerRadii,
                                        transform: transform, target: rasterTarget)
        guard !placement.clip.isEmpty, paint.alpha > 0, !paint.leaf.isEmpty,
              let (rx, ry) = RasterAnchor.leafAnchor(paint.leaf) else { return nil }
        let full = (transform?.affine ?? .identity).concatenating(paint.local)
        let pad = BoxBlur.padding(sigma: paint.radius * full.linearScale) + 1
        let extent = RasterExtent.of(paint.leaf, map: full).rect(grownBy: pad)
        let anchor = RasterAnchor(rx: rx, ry: ry, full: full, extent: extent, placement: placement)
        var canonical = paint
        canonical.local = .identity
        if anchor.isCanonical { canonical.leaf = paint.leaf.map { $0.movedCanonically(-rx, -ry) } }
        let clip = anchor.canonical(placement.clip)
        var key = RasterKey()
        key.add(7)
        anchor.keyed(&key, clip: clip, placement: placement)
        key.add(paint.radius)
        var retained: [AnyObject] = []
        keyLeaf(canonical.leaf, into: &key, retained: &retained, colours: true)
        let cache = animationStore.rasters
        guard let (rect, texture) = cache.image(for: key, retaining: retained, make: {
            var layer = blurLayer(canonical, full: anchor.map, clip: clip, cache: cache).cropped(to: clip)
            if let localMask = placement.localMask, !layer.rect.isEmpty {
                layer = layer.multiplied(by: RasterMath.maskCoverage(localMask.bounds, localMask.radii,
                                                                     map: localMask.map, clip: layer.rect,
                                                                     cache: cache))
            }
            guard !layer.rect.isEmpty else { return nil }
            return (layer.rect, layer.texture)
        }) else { return nil }
        var quad = placement.quad(over: anchor.placed(rect))
        quad.opacity = paint.alpha
        return (quad, texture)
    }

    /// The blurred leaf (before its opacity) in final device pixels, over at
    /// least `clip`: the leaf composited in colour under `full`, then a triple
    /// box blur of each premultiplied channel (divergence 105), in gamma space
    /// as the shadow's.
    func blurLayer(_ paint: BlurPaint, full: Affine2D, clip: RasterRect, cache: RasterCache) -> RGBALayer {
        let sigma = paint.radius * full.linearScale
        let pad = BoxBlur.padding(sigma: sigma)
        let reach = RasterRect(x: clip.x - pad, y: clip.y - pad, width: clip.width + 2 * pad,
                               height: clip.height + 2 * pad)
        var layer = RGBALayer.empty
        for q in paint.leaf { layer = layer.under(colourRaster(q, map: full, clip: reach, cache: cache)) }
        guard sigma > 0, !layer.rect.isEmpty else { return layer }
        let blurred = RGBALayer(channels: (0..<4).map { BoxBlur.blur(layer.channel($0), sigma: sigma) })
        cache.noteBlurred(blurred.rect.area)
        return blurred
    }

    /// One captured primitive in colour (premultiplied) in final device
    /// pixels — the shadow's `silhouette` with all four channels: `map` takes
    /// its creation space to the final one. A GPU surface reads nothing
    /// (divergence 167; a surface alone in a leaf never gets here).
    private func colourRaster(_ q: CapturedPrimitive, map: Affine2D, clip: RasterRect,
                              cache: RasterCache) -> RGBALayer {
        let m = map.concatenating(q.transform?.affine ?? .identity)
        var rasterizer = CoverageRasterizer()
        func fill(_ geometry: PathGeometry, _ rule: FillRule = .nonZero) -> AlphaMask {
            let mask = PathRaster.fill(geometry, rule: rule, transform: m.pathAffine, clip: clip, rasterizer: &rasterizer)
            cache.noteRasterized(rasterizer.lastRasterizedPixels)
            return mask
        }
        func hsla(_ c: MUIHsla) -> Hsla { Hsla(h: c.h, s: c.s, l: c.l, a: c.a) }
        func resampleRect(_ bounds: MUIBounds) -> RasterRect {
            RasterMath.enclosing(m.boundingBox(of: bounds)).intersection(clip)
        }
        var layer: RGBALayer
        let contentMask: (MUIBounds, MUICorners)
        switch q.kind {
        case let .rect(r):
            contentMask = (r.contentMask, r.maskCornerRadii)
            let ellipse = r.shapeKind == PrimitiveShape.ellipse.rawValue
            let outline = RasterMath.roundedRect(r.bounds, r.cornerRadii, ellipse: ellipse)
            layer = .empty
            if r.background.a > 0 { layer = RGBALayer(mask: fill(outline), color: hsla(r.background)) }
            let w = r.borderWidths
            let widest = max(w.top, w.right, w.bottom, w.left)
            if r.borderColor.a > 0, widest > 0 {
                var ring = outline
                let inner = MUIBounds(origin: MUIPoint(x: r.bounds.origin.x + w.left, y: r.bounds.origin.y + w.top),
                                      size: MUISize(width: max(0, r.bounds.size.width - w.left - w.right),
                                                    height: max(0, r.bounds.size.height - w.top - w.bottom)))
                let c = r.cornerRadii
                let innerRadii = MUICorners(topLeft: max(0, c.topLeft - widest), topRight: max(0, c.topRight - widest),
                                            bottomRight: max(0, c.bottomRight - widest),
                                            bottomLeft: max(0, c.bottomLeft - widest))
                if inner.size.width > 0, inner.size.height > 0 {
                    ring.append(RasterMath.roundedRect(inner, innerRadii, ellipse: ellipse))
                }
                layer = layer.under(RGBALayer(mask: fill(ring, .evenOdd), color: hsla(r.borderColor)))
            }
        case let .glyph(g):
            contentMask = (g.contentMask, g.maskCornerRadii)
            let sx = Int(g.atlasBounds.origin.x), sy = Int(g.atlasBounds.origin.y)
            let w = Int(g.atlasBounds.size.width), h = Int(g.atlasBounds.size.height)
            var source = [UInt8](repeating: 0, count: max(0, w * h))
            let atlasWidth = glyphAtlas.width
            for row in 0..<h {
                for col in 0..<w { source[row * w + col] = glyphAtlas.pixels[(sy + row) * atlasWidth + sx + col] }
            }
            let toDevice = m.concatenating(Affine2D(a: Double(g.bounds.size.width) / Double(max(w, 1)),
                                                    d: Double(g.bounds.size.height) / Double(max(h, 1)),
                                                    tx: Double(g.bounds.origin.x), ty: Double(g.bounds.origin.y)))
            let coverage = AlphaCompositor.resample(source: source, width: w, height: h, channels: 1,
                                                    transform: toDevice.pathAffine, into: resampleRect(g.bounds),
                                                    filter: .bilinear)
            layer = RGBALayer(mask: coverage, color: hsla(g.color))
        case let .image(i, texture):
            contentMask = (i.contentMask, i.maskCornerRadii)
            let toDevice = m.concatenating(Affine2D(a: Double(i.bounds.size.width) / Double(texture.width),
                                                    d: Double(i.bounds.size.height) / Double(texture.height),
                                                    tx: Double(i.bounds.origin.x), ty: Double(i.bounds.origin.y)))
            let rect = resampleRect(i.bounds)
            let filter: AlphaCompositor.Filter = i.filterKind == ImageFilter.nearest.rawValue ? .nearest : .bilinear
            let channels = (0..<4).map { c in
                AlphaCompositor.resample(source: stride(from: c, to: texture.pixels.count, by: 4).map { texture.pixels[$0] },
                                         width: texture.width, height: texture.height, channels: 1,
                                         transform: toDevice.pathAffine, into: rect, filter: filter)
            }
            layer = RGBALayer(channels: channels).scaled(by: i.opacity)
        case let .surface(s, _):
            contentMask = (s.contentMask, s.maskCornerRadii)
            layer = .empty
        case let .path(p):
            contentMask = (p.contentMask, p.maskCornerRadii)
            let transform = m.concatenating(p.local).pathAffine
            let coverage: AlphaMask
            switch p.mode {
            case let .fill(rule, antialiased):
                coverage = PathRaster.fill(p.geometry, rule: rule, transform: transform, clip: clip,
                                           antialiased: antialiased, rasterizer: &rasterizer)
            case let .stroke(style):
                coverage = PathRaster.stroke(p.geometry, style: style, transform: transform, clip: clip,
                                             rasterizer: &rasterizer)
            }
            cache.noteRasterized(rasterizer.lastRasterizedPixels)
            layer = RGBALayer(mask: coverage, color: p.color)
        case let .shadow(inner):
            contentMask = (inner.contentMask, inner.maskCornerRadii)
            let coverage = RasterMath.crop(shadowCoverage(inner, full: m.concatenating(inner.local), clip: clip,
                                                          cache: cache), to: clip)
            layer = RGBALayer(mask: coverage, color: inner.color)
        case let .gradient(g):
            contentMask = (g.contentMask, g.maskCornerRadii)
            layer = gradientPixels(g, full: m.concatenating(g.local), clip: clip, cache: cache).scaled(by: g.opacity)
        case let .blur(inner):
            contentMask = (inner.contentMask, inner.maskCornerRadii)
            layer = blurLayer(inner, full: m.concatenating(inner.local), clip: clip, cache: cache)
                .cropped(to: clip).scaled(by: inner.alpha)
        }
        guard !layer.rect.isEmpty else { return layer }
        if q.innerMask {
            layer = layer.multiplied(by: RasterMath.maskCoverage(contentMask.0, contentMask.1, map: m,
                                                                 clip: layer.rect, cache: cache))
        }
        if let t = q.transform, q.outerMaskInner {
            layer = layer.multiplied(by: RasterMath.maskCoverage(t.outerMask, t.outerMaskRadii, map: map,
                                                                 clip: layer.rect, cache: cache))
        }
        return layer
    }
}
