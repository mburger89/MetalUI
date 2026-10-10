import MetalUICore
import MetalUILayout
import MetalUIPath
import MetalUIPrimitives

// Paths, shadows and transforms, lane 3 — shadows (rulings `GX-J`, `GX-Q`).
// Spec `docs/superpowers/specs/2026-10-02-paths-shadows-transforms-design.md`
// §4.3; SwiftUI's side is `docs/probes/swiftui-paths-shadows-transforms.swift`,
// arms SH0–SH13, H5, X6, N4–N6.

// MARK: - The proposal vocabulary (one `LayoutModifier` layer, `GX-J`)

extension ProposalElementGroup {
    /// Draws a shadow under each leaf of this view — SwiftUI's
    /// `shadow(color:radius:x:y:)`. **Per leaf** (SH5): every primitive drawn
    /// inside (a text draw counts as one) gets its own shadow immediately
    /// below it, so in an overlapping stack the top child's shadow falls on the
    /// child below; a nested shadow's image is itself a leaf (SH11). The blur is
    /// Gaussian with sigma equal to `radius` (SH3, divergence 105); the
    /// silhouette follows the content's alpha (SH6), a clip outside cuts the
    /// shadow and one inside shapes it (SH7, SH7b). The default colour is
    /// ``ColorToken/shadow`` (black at 0.33, SH2). **Render only**: no layout
    /// change (SH8), no hit region (H5), nothing published (X6). Colour,
    /// radius and offset animate. One layer, one identity level (`MC-C`).
    /// `color` is any `Color` since the colour work (`CR-E`).
    public func shadow(color: Color = .shadow, radius: Pixels, x: Pixels = Pixels(0),
                       y: Pixels = Pixels(0)) -> ModifiedContent<ProposalBase, LayoutModifier> {
        _wrapLayout(.shadow(color, radius: radius, x: x, y: y))
    }

    /// The `ColorToken` spelling of ``shadow(color:radius:x:y:)``, kept
    /// (`CR-E` item 1); disfavoured, so `shadow(radius:)` takes the `Color`
    /// default (probe `swift-colour-overloads.swift` O4).
    @_disfavoredOverload
    public func shadow(color: ColorToken = .shadow, radius: Pixels, x: Pixels = Pixels(0),
                       y: Pixels = Pixels(0)) -> ModifiedContent<ProposalBase, LayoutModifier> {
        shadow(color: Color(color), radius: radius, x: x, y: y)
    }
}

// MARK: - The legacy vocabulary (`Decoration.renderEffects`, `GX-J`)

extension StyledElement {
    /// Draws a shadow under each leaf of this element — SwiftUI's
    /// `shadow(color:radius:x:y:)`, returning `Self` (no identity level). It
    /// joins the element's render effects in written order and, like them,
    /// wraps the whole element: its background, content and border
    /// (divergence 108). A `Box`'s background and border are one primitive, so
    /// one shadow (divergence 104). See the proposal spelling for the rules.
    /// `color` is any `Color` since the colour work (`CR-E`).
    public func shadow(color: Color = .shadow, radius: Pixels, x: Pixels = Pixels(0),
                       y: Pixels = Pixels(0)) -> Self {
        appendingRenderEffect(.shadow(color, radius: radius, x: x, y: y))
    }

    /// The `ColorToken` spelling of ``shadow(color:radius:x:y:)``, kept
    /// (`CR-E` item 1).
    @_disfavoredOverload
    public func shadow(color: ColorToken = .shadow, radius: Pixels, x: Pixels = Pixels(0),
                       y: Pixels = Pixels(0)) -> Self {
        shadow(color: Color(color), radius: radius, x: x, y: y)
    }
}

// MARK: - The pass helpers

extension PaintPass {
    /// Runs `body` inside a shadow scope (`GX-J`).
    func withShadow(color: Hsla, radius: Pixels, x: Pixels, y: Pixels, _ body: () -> Void) {
        frame.paintWithShadow(color: color, radius: radius, x: x, y: y, body)
    }

    /// Fills `path` (window points) in `color` under `fill` (`GX-B`).
    func drawPath(_ path: Path, fill: FillStyle, color: Hsla) {
        frame.drawPath(path, mode: .fill(fill.rule, antialiased: fill.isAntialiased), color: color)
    }

    /// Strokes `path` (window points) in `color` under `stroke` (`GX-E`).
    func drawPath(_ path: Path, stroke: StrokeStyle, color: Hsla) {
        guard stroke.lineWidth.value > 0 else { return }
        frame.drawPath(path, mode: .stroke(stroke.parameters), color: color)
    }

    /// Emits one text draw's glyphs as one leaf (`GX-J`; SH4, SH5e): a shadow
    /// scope shadows the whole run once, not glyph by glyph.
    func drawGlyphs<S: Sequence>(_ glyphs: S, color: Hsla) where S.Element == TextGlyph {
        frame.beginLeafGroup()
        for glyph in glyphs { frame.draw(glyph, color: color) }
        frame.endLeafGroup()
    }
}

// MARK: - Rasterizing a shadow

extension Frame {
    /// A shadow's image (`GX-J`): the leaf's silhouette in device pixels under
    /// the composed transform, offset by the mapped offset, blurred with sigma
    /// = radius × `sqrt|det|`, cut by the clip at the shadow's entry, tinted.
    func shadowImage(_ paint: ShadowPaint, transform: PrimitiveTransform?) -> (MUIImage, ImageTexture)? {
        let placement = RasterPlacement(contentMask: paint.contentMask, radii: paint.maskCornerRadii,
                                        transform: transform, target: rasterTarget)
        guard !placement.clip.isEmpty, paint.color.a > 0, !paint.leaf.isEmpty else { return nil }
        let full = (transform?.affine ?? .identity).concatenating(paint.local)
        var key = RasterKey()
        key.add(2)
        key.add(full)
        placement.keyed(&key)
        var retained: [AnyObject] = []
        keyShadow(paint, into: &key, retained: &retained)
        let cache = animationStore.rasters
        let mask = cache.coverage(for: key, retaining: retained) {
            let blurred = shadowCoverage(paint, full: full, clip: placement.clip, cache: cache)
            return placement.applyingLocalMask(RasterMath.crop(blurred, to: placement.clip), cache: cache)
        }
        guard !mask.rect.isEmpty else { return nil }
        return (placement.quad(over: mask), cache.texture(for: key, color: paint.color, mask: mask))
    }

    /// Every number of `paint`'s leaf, for its cache key.
    private func keyShadow(_ paint: ShadowPaint, into key: inout RasterKey, retained: inout [AnyObject]) {
        key.add(paint.radius); key.add(paint.dx); key.add(paint.dy); key.add(paint.local)
        keyLeaf(paint.leaf, into: &key, retained: &retained)
    }

    /// Every number of a captured leaf, for a cache key — the shadow's and
    /// the blur's (`GX-J`, `LK-K`): one switch, so the two cannot drift.
    /// A shadow needs only alpha; a blur (`colours`) every colour.
    func keyLeaf(_ leaf: [CapturedPrimitive], into key: inout RasterKey, retained: inout [AnyObject],
                 colours: Bool = false) {
        key.add(leaf.count)
        for q in leaf {
            key.add(q.innerMask ? 1 : 0)
            key.add(q.outerMaskInner ? 1 : 0)
            if let t = q.transform {
                key.add(t.affine); key.add(t.outerMask); key.add(t.outerMaskRadii)
            } else {
                key.add(-1)
            }
            switch q.kind {
            case let .rect(r):
                key.add(10); key.add(r.bounds); key.add(r.contentMask); key.add(r.maskCornerRadii)
                key.add(r.cornerRadii); key.add(r.borderWidths); key.add(r.background.a); key.add(r.borderColor.a)
                key.add(r.shapeKind)
                if colours { key.add(r.background); key.add(r.borderColor) }
            case let .glyph(g):
                key.add(11); key.add(g.bounds); key.add(g.atlasBounds); key.add(g.contentMask)
                key.add(g.maskCornerRadii); key.add(g.color.a)
                if colours { key.add(g.color) }
            case let .image(i, texture):
                key.add(12); key.add(i.bounds); key.add(i.contentMask); key.add(i.maskCornerRadii)
                key.add(i.opacity); key.add(i.filterKind)
                key.objects.append(ObjectIdentifier(texture)); retained.append(texture)
            case let .surface(q, _):
                key.add(13); key.add(q.bounds); key.add(q.contentMask); key.add(q.maskCornerRadii); key.add(q.opacity)
            case let .path(p):
                key.add(14); key.paths.append(p.geometry); key.add(p.local); key.add(p.color.a)
                if colours { key.add(p.color) }
                key.add(p.contentMask); key.add(p.maskCornerRadii)
                switch p.mode {
                case let .fill(rule, antialiased):
                    key.add(rule == .evenOdd ? 1 : 0); key.add(antialiased ? 1 : 0)
                case let .stroke(style):
                    key.add(2); key.add(style.width); key.add(style.miterLimit); key.add(style.dashPhase)
                    key.add(style.cap == .butt ? 0 : style.cap == .round ? 1 : 2)
                    key.add(style.join == .miter ? 0 : style.join == .round ? 1 : 2)
                    for d in style.dash { key.add(d) }
                }
            case let .shadow(inner):
                key.add(15); key.add(inner.color.a); key.add(inner.contentMask); key.add(inner.maskCornerRadii)
                if colours { key.add(inner.color) }
                keyShadow(inner, into: &key, retained: &retained)
            case let .gradient(g):
                key.add(16); key.paths.append(g.geometry); keyMode(g.mode, into: &key); key.add(g.local)
                key.add(g.opacity); key.add(g.contentMask); key.add(g.maskCornerRadii)
                key.words += g.stops.keyWords
                for w in g.axis.words { key.add(w) }
            case let .blur(inner):
                key.add(17); key.add(inner.radius); key.add(inner.local); key.add(inner.alpha)
                key.add(inner.contentMask); key.add(inner.maskCornerRadii)
                keyLeaf(inner.leaf, into: &key, retained: &retained, colours: true)
            }
        }
    }

    /// The blurred silhouette (before tinting) in final device pixels, over at
    /// least `clip`: the leaf drawn under `full` moved by the mapped offset,
    /// then a triple box blur of sigma `radius × sqrt|det(full)|`.
    func shadowCoverage(_ paint: ShadowPaint, full: Affine2D, clip: RasterRect, cache: RasterCache) -> AlphaMask {
        let sigma = paint.radius * full.linearScale
        let pad = BoxBlur.padding(sigma: sigma)
        let reach = RasterRect(x: clip.x - pad, y: clip.y - pad, width: clip.width + 2 * pad,
                               height: clip.height + 2 * pad)
        // The offset is a vector: mapped by the linear part only (T10, T14).
        let ox = full.a * paint.dx + full.c * paint.dy, oy = full.b * paint.dx + full.d * paint.dy
        let moved = Affine2D.translation(x: ox, y: oy).concatenating(full)
        var union = AlphaMask.empty
        for q in paint.leaf {
            union = AlphaCompositor.union(union, silhouette(q, map: moved, clip: reach, cache: cache))
        }
        guard sigma > 0, !union.rect.isEmpty else { return union }
        let blurred = BoxBlur.blur(union, sigma: sigma)
        cache.noteBlurred(blurred.rect.area)
        return blurred
    }

    /// One captured primitive's coverage in final device pixels: `map` takes
    /// its creation space to the final one; its own transform maps its local
    /// geometry into creation space. Times its colour's alpha (SH6); cut by its
    /// own mask when that was pushed inside the shadow (SH7b).
    private func silhouette(_ q: CapturedPrimitive, map: Affine2D, clip: RasterRect,
                            cache: RasterCache) -> AlphaMask {
        let m = map.concatenating(q.transform?.affine ?? .identity)
        var rasterizer = CoverageRasterizer()
        func fill(_ geometry: PathGeometry, _ rule: FillRule = .nonZero, _ transform: Affine2D) -> AlphaMask {
            let mask = PathRaster.fill(geometry, rule: rule, transform: transform.pathAffine, clip: clip,
                                       rasterizer: &rasterizer)
            cache.noteRasterized(rasterizer.lastRasterizedPixels)
            return mask
        }
        func resampleRect(_ bounds: MUIBounds) -> RasterRect {
            RasterMath.enclosing(m.boundingBox(of: bounds)).intersection(clip)
        }
        var mask: AlphaMask
        let contentMask: (MUIBounds, MUICorners)
        switch q.kind {
        case let .rect(r):
            contentMask = (r.contentMask, r.maskCornerRadii)
            let ellipse = r.shapeKind == PrimitiveShape.ellipse.rawValue
            mask = .empty
            if r.background.a > 0 {
                mask = RasterMath.scale(fill(RasterMath.roundedRect(r.bounds, r.cornerRadii, ellipse: ellipse), .nonZero, m),
                                        by: r.background.a)
            }
            let w = r.borderWidths
            if r.borderColor.a > 0, max(w.top, w.right, w.bottom, w.left) > 0 {
                var ring = RasterMath.roundedRect(r.bounds, r.cornerRadii, ellipse: ellipse)
                let inner = MUIBounds(origin: MUIPoint(x: r.bounds.origin.x + w.left, y: r.bounds.origin.y + w.top),
                                      size: MUISize(width: max(0, r.bounds.size.width - w.left - w.right),
                                                    height: max(0, r.bounds.size.height - w.top - w.bottom)))
                let widest = max(w.top, w.right, w.bottom, w.left)
                let c = r.cornerRadii
                let innerRadii = MUICorners(topLeft: max(0, c.topLeft - widest), topRight: max(0, c.topRight - widest),
                                            bottomRight: max(0, c.bottomRight - widest),
                                            bottomLeft: max(0, c.bottomLeft - widest))
                if inner.size.width > 0, inner.size.height > 0 {
                    ring.append(RasterMath.roundedRect(inner, innerRadii, ellipse: ellipse))
                }
                mask = AlphaCompositor.union(mask, RasterMath.scale(fill(ring, .evenOdd, m), by: r.borderColor.a))
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
            mask = AlphaCompositor.resample(source: source, width: w, height: h, channels: 1,
                                            transform: toDevice.pathAffine, into: resampleRect(g.bounds),
                                            filter: .bilinear)
            mask = RasterMath.scale(mask, by: g.color.a)
        case let .image(i, texture):
            contentMask = (i.contentMask, i.maskCornerRadii)
            let toDevice = m.concatenating(Affine2D(a: Double(i.bounds.size.width) / Double(texture.width),
                                                    d: Double(i.bounds.size.height) / Double(texture.height),
                                                    tx: Double(i.bounds.origin.x), ty: Double(i.bounds.origin.y)))
            mask = AlphaCompositor.resample(source: texture.pixels, width: texture.width, height: texture.height,
                                            channels: 4, transform: toDevice.pathAffine,
                                            into: resampleRect(i.bounds),
                                            filter: i.filterKind == ImageFilter.nearest.rawValue ? .nearest : .bilinear)
            mask = RasterMath.scale(mask, by: i.opacity)
        case let .surface(s, _):
            // A surface's pixels live on the GPU: its silhouette is its quad
            // (divergence 104).
            contentMask = (s.contentMask, s.maskCornerRadii)
            mask = RasterMath.scale(fill(RasterMath.roundedRect(s.bounds, MUICorners(topLeft: 0, topRight: 0,
                                                                                    bottomRight: 0, bottomLeft: 0)),
                                         .nonZero, m), by: s.opacity)
        case let .path(p):
            contentMask = (p.contentMask, p.maskCornerRadii)
            let transform = m.concatenating(p.local).pathAffine
            switch p.mode {
            case let .fill(rule, antialiased):
                mask = PathRaster.fill(p.geometry, rule: rule, transform: transform, clip: clip,
                                       antialiased: antialiased, rasterizer: &rasterizer)
            case let .stroke(style):
                mask = PathRaster.stroke(p.geometry, style: style, transform: transform, clip: clip,
                                         rasterizer: &rasterizer)
            }
            cache.noteRasterized(rasterizer.lastRasterizedPixels)
            mask = RasterMath.scale(mask, by: p.color.a)
        case let .shadow(inner):
            // A nested shadow is itself a leaf (SH11).
            contentMask = (inner.contentMask, inner.maskCornerRadii)
            mask = RasterMath.crop(shadowCoverage(inner, full: m.concatenating(inner.local), clip: clip, cache: cache),
                                   to: clip)
            mask = RasterMath.scale(mask, by: inner.color.a)
        case let .gradient(g):
            // A gradient's silhouette is its coverage times its colours' alpha
            // (`LK-J`; SH6).
            contentMask = (g.contentMask, g.maskCornerRadii)
            mask = RasterMath.scale(gradientPixels(g, full: m.concatenating(g.local), clip: clip, cache: cache)
                .channel(3), by: g.opacity)
        case let .blur(inner):
            // A blurred leaf's silhouette is its blurred alpha.
            contentMask = (inner.contentMask, inner.maskCornerRadii)
            mask = RasterMath.scale(blurLayer(inner, full: m.concatenating(inner.local), clip: clip, cache: cache)
                .channel(3), by: inner.alpha)
        }
        guard !mask.rect.isEmpty else { return mask }
        if q.innerMask {
            mask = RasterMath.multiply(mask, RasterMath.maskCoverage(contentMask.0, contentMask.1, map: m,
                                                                     clip: mask.rect, cache: cache))
        }
        if let t = q.transform, q.outerMaskInner {
            mask = RasterMath.multiply(mask, RasterMath.maskCoverage(t.outerMask, t.outerMaskRadii, map: map,
                                                                     clip: mask.rect, cache: cache))
        }
        return mask
    }
}

/// The animation-store key of a legacy shadow's colour track (`GX-J`): a store
/// key, never a `StateTable` slot (the reserved names stay seven).
@MainActor
func legacyShadowColourKey(for id: GlobalElementID, index: Int) -> GlobalElementID {
    .child(of: id, at: 0, name: ElementID("$anim-effects.shadow\(index)"))
}
