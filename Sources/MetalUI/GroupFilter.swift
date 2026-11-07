import MetalUICore
import MetalUILayout
import MetalUIPath
import MetalUIPrimitives

// R4-5 PR B — a shadow or blur over a group texture (ruling prefix `GF-`, record 219). A shadow or blur scope lifts the
// opacity mark every leaf shares (model F: the shadow joins the leaf's opacity group), and a leaf the CPU cannot read
// (a GPU surface, a leaf under a projective effect, a leaf still holding a mark) goes through an offscreen group the
// renderers filter, instead of through the CPU rasterizer.

// MARK: - Lifting and routing (`GF-A`)

extension Frame {
    /// Removes, outermost first, every opacity mark that **all** of `leaf` shares (same token, same alpha) and returns
    /// them (`GF-A`). A blur is linear and a silhouette's alpha is linear in the group alpha, so a filter of the unfaded
    /// leaf faded afterwards is exact; the CPU raster never holds the alpha, so a fade of a shadowed group rasters
    /// nothing after its first frame.
    static func liftSharedMarks(_ leaf: inout [CapturedPrimitive]) -> [GroupMark] {
        var lifted: [GroupMark] = []
        while let first = leaf.first?.groups.first, !first.isMasked,
              leaf.allSatisfy({ $0.groups.first?.token === first.token && $0.groups[0].alpha == first.alpha }) {
            lifted.append(first)
            for i in leaf.indices { leaf[i].groups.removeFirst() }
        }
        return lifted
    }

    /// Whether the CPU rasterizers cannot read `leaf` and its filter goes through an offscreen group (`GF-A`): a GPU
    /// surface (divergence 167), a primitive under a projective record (1066), a primitive still inside an opacity
    /// group once the shared marks are lifted, or a nested shadow or blur that is itself one of these.
    static func needsGPU(_ leaf: [CapturedPrimitive]) -> Bool {
        for q in leaf {
            if !q.groups.isEmpty { return true }
            if let t = q.transform, !t.homography.isAffine { return true }
            switch q.kind {
            case .surface: return true
            case .shadow(let inner): if needsGPU(inner.leaf) { return true }
            case .blur(let inner): if needsGPU(inner.leaf) { return true }
            default: break
            }
        }
        return false
    }
}

// MARK: - The filtered group (`GF-B`)

extension CapturedPrimitive {
    /// The primitive's content mask replaced by `mask` with square corners (`GF-B` item 2).
    mutating func replaceContentMask(_ mask: MUIBounds) {
        let square = MUICorners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0)
        switch kind {
        case .rect(var r): r.contentMask = mask; r.maskCornerRadii = square; kind = .rect(r)
        case .glyph(var g): g.contentMask = mask; g.maskCornerRadii = square; kind = .glyph(g)
        case .image(var i, let texture): i.contentMask = mask; i.maskCornerRadii = square; kind = .image(i, texture: texture)
        case .surface(var q, let target): q.contentMask = mask; q.maskCornerRadii = square; kind = .surface(q, target: target)
        case .path(var p): p.contentMask = mask; p.maskCornerRadii = square; kind = .path(p)
        case .shadow(var s): s.contentMask = mask; s.maskCornerRadii = square; kind = .shadow(s)
        case .gradient(var g): g.contentMask = mask; g.maskCornerRadii = square; kind = .gradient(g)
        case .blur(var b): b.contentMask = mask; b.maskCornerRadii = square; kind = .blur(b)
        case .backdrop(var r): r.contentMask = mask; r.maskCornerRadii = square; kind = .backdrop(r)
        }
    }
}

extension Frame {
    /// A box's side in device pixels above which a filtered leaf is rastered on the CPU instead (`GF-G`).
    static let unboundedMask = MUIBounds(origin: MUIPoint(x: -1_000_000, y: -1_000_000),
                                         size: MUISize(width: 2_000_000, height: 2_000_000))

    /// One shadow or blur rendered through an offscreen group the renderer filters (`GF-B`). `shadow` or `blur` is the
    /// paint; `primitive` the item that carried it (its transform record and layer).
    func insertFilteredGroup(shadow: ShadowPaint?, blur: BlurPaint?, _ primitive: CapturedPrimitive) {
        let leaf: [CapturedPrimitive], local: Affine2D, radius: Double
        let contentMask: MUIBounds, radii: MUICorners
        var alpha: Float = 1
        var offset: (dx: Double, dy: Double) = (0, 0)
        if let shadow {
            leaf = shadow.leaf; local = shadow.local; radius = shadow.radius
            contentMask = shadow.contentMask; radii = shadow.maskCornerRadii
            offset = (shadow.dx, shadow.dy)
            guard shadow.color.a > 0 else { return }
        } else if let blur {
            leaf = blur.leaf; local = blur.local; radius = blur.radius
            contentMask = blur.contentMask; radii = blur.maskCornerRadii
            alpha = blur.alpha
        } else {
            return
        }
        guard alpha > 0, !leaf.isEmpty else { return }
        let transform = primitive.transform
        let projective = transform.map { !$0.homography.isAffine } ?? false
        // Space (`GF-B` item 1): an affine record is applied here and the quad drawn plain; a projective one is
        // left to the quad, and the group renders in the creation space (`PJ-G`, `PJ-L`).
        let outer: Affine2D = projective ? .identity : (transform?.affine ?? .identity)
        let full = outer.concatenating(local)
        let placement = RasterPlacement(contentMask: contentMask, radii: radii, transform: transform, target: rasterTarget)
        guard !placement.clip.isEmpty else { return }
        let sigma = radius * full.linearScale
        let pad = Int((3 * sigma).rounded(.up)) + 1
        // The offset is a vector, mapped by the linear part only; it moves the content, not the quad.
        let ox = full.a * offset.dx + full.c * offset.dy, oy = full.b * offset.dx + full.d * offset.dy
        let grow = pad + Int(max(abs(ox), abs(oy)).rounded(.up))
        let reach = RasterRect(x: placement.clip.x - grow, y: placement.clip.y - grow,
                               width: placement.clip.width + 2 * grow, height: placement.clip.height + 2 * grow)
        let reachBounds = MUIBounds(origin: MUIPoint(x: Float(reach.x), y: Float(reach.y)),
                                    size: MUISize(width: Float(reach.width), height: Float(reach.height)))
        let moved = Affine2D.translation(x: ox, y: oy).concatenating(full)
        let flat = moved.isUniformPositiveScaleTranslation
        let effect = RenderEffect(alpha: 1, affine: moved)
        let entry = OuterMask(bounds: reachBounds, radii: MUICorners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0),
                              depth: 0)
        var mapped: [CapturedPrimitive] = []
        mapped.reserveCapacity(leaf.count)
        for original in leaf {
            var q = original
            // A mask at or outside the scope is the entry clip, which cuts after the filter (B5): the group is not cut
            // by it, only by the reach (`GF-B` item 2). A mask pushed inside the scope shapes the leaf.
            if q.transform == nil {
                if !q.innerMask { q.replaceContentMask(flat ? reachBounds : Self.unboundedMask) }
            } else if !q.outerMaskInner, var t = q.transform {
                t.outerMask = reachBounds
                t.outerMaskRadii = MUICorners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0)
                q.transform = t
            }
            if let m = effect.apply(to: q, flattens: flat, outer: flat ? nil : entry) { mapped.append(m) }
        }
        guard !mapped.isEmpty else { return }
        var inner = collectingIntoFreshScene { insertLeaves(mapped) }
        guard let painted = inner.paintedBounds() else { return }

        // The box (`GF-B` item 4): the painted box grown by the reach of three sigma and a pixel, cut by the reach,
        // floored and ceiled without libm, then widened so both sides are whole multiples of 2^L: the quad's linear
        // read then lands on `BB-R`'s texel coordinate `(p + 1/2) / 2^L - 1/2` with no new shader.
        func floorInt(_ v: Float) -> Float { let t = Float(Int(v)); return t > v ? t - 1 : t }
        func ceilInt(_ v: Float) -> Float { let t = Float(Int(v)); return t < v ? t + 1 : t }
        let growBox = Float(pad)
        let bx0 = max(floorInt(max(painted.minX - growBox, reachBounds.origin.x)), Float(reach.x))
        let by0 = max(floorInt(max(painted.minY - growBox, reachBounds.origin.y)), Float(reach.y))
        let bx1 = min(ceilInt(min(painted.maxX + growBox, Float(reach.maxX))), Float(reach.maxX))
        let by1 = min(ceilInt(min(painted.maxY + growBox, Float(reach.maxY))), Float(reach.maxY))
        guard bx1 > bx0, by1 > by0 else { return }
        let levels = sigma > 0 ? BackdropBlurReference.levels(sigma: Float(sigma), maxLevel: 6) : 0
        let multiple = 1 << levels
        func widened(_ extent: Float) -> Int { ((Int(extent) + multiple - 1) / multiple) * multiple }
        let width = widened(bx1 - bx0), height = widened(by1 - by0)
        if width > Self.maxGroupTargetSide || height > Self.maxGroupTargetSide {
            // Too large for one target: the CPU raster as before this existed (`GF-G`).
            filtersFlattenedOversize += 1
            insertFilterOnTheCPU(shadow: shadow, blur: blur, primitive)
            return
        }
        inner.finalize()
        var quad = placement.quad(over: RasterRect(x: Int(bx0), y: Int(by0), width: width, height: height))
        quad.opacity = alpha
        if let localMask = placement.localMask {
            // The entry clip in the group's space: exact under a flattening map, its bounding box otherwise.
            let m = localMask.map
            let cutBy: (MUIBounds, MUICorners)
            if m.isUniformPositiveScaleTranslation {
                let s = Float(m.a)
                cutBy = (MUIBounds(origin: MUIPoint(x: s * localMask.bounds.origin.x + Float(m.tx),
                                                     y: s * localMask.bounds.origin.y + Float(m.ty)),
                                    size: MUISize(width: s * localMask.bounds.size.width, height: s * localMask.bounds.size.height)),
                          MUICorners(topLeft: s * localMask.radii.topLeft, topRight: s * localMask.radii.topRight,
                                     bottomRight: s * localMask.radii.bottomRight, bottomLeft: s * localMask.radii.bottomLeft))
            } else {
                cutBy = (m.boundingBox(of: localMask.bounds), MUICorners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0))
            }
            func px(_ b: MUIBounds) -> Bounds<Pixels> {
                Bounds(origin: Point(x: Pixels(b.origin.x), y: Pixels(b.origin.y)),
                       size: Size(width: Pixels(b.size.width), height: Pixels(b.size.height)))
            }
            func corners(_ c: MUICorners) -> Corners<Pixels> {
                Corners(topLeft: Pixels(c.topLeft), topRight: Pixels(c.topRight),
                        bottomRight: Pixels(c.bottomRight), bottomLeft: Pixels(c.bottomLeft))
            }
            let (b, r) = Frame.intersect(px(quad.contentMask), radii: corners(quad.maskCornerRadii), px(cutBy.0), radii: corners(cutBy.1))
            quad.contentMask = MUIBounds(origin: MUIPoint(x: b.origin.x.value, y: b.origin.y.value),
                                         size: MUISize(width: b.size.width.value, height: b.size.height.value))
            quad.maskCornerRadii = MUICorners(topLeft: r.topLeft.value, topRight: r.topRight.value,
                                              bottomRight: r.bottomRight.value, bottomLeft: r.bottomLeft.value)
        }
        // A level-0 group is drawn texel for texel; a downsampled one is read linearly (`BB-R`).
        quad.filter = (levels == 0 && !projective ? ImageFilter.nearest : ImageFilter.linear).rawValue
        let filter: Scene.GroupFilter
        if let shadow {
            let rgb = shadow.color.toRgba()
            let a = min(max(shadow.color.a, 0), 1)
            filter = Scene.GroupFilter(kind: .shadow, sigma: Float(sigma),
                                       tint: SIMD4<Float>(rgb.r * a, rgb.g * a, rgb.b * a, a))
        } else {
            filter = Scene.GroupFilter(kind: .blur, sigma: Float(sigma), tint: SIMD4<Float>(0, 0, 0, 0))
        }
        filterGroups += 1
        insertGroupQuad(quad, group: inner, layer: primitive.layer, transform: projective ? transform?.record : nil,
                        filter: filter)
    }

    /// What `insertIntoScene` did with a shadow or blur before the GPU path (`GF-G`): the CPU raster of what it can
    /// read, marks baked into the colours. An oversize filtered leaf takes this, and so keeps drawing what it could.
    private func insertFilterOnTheCPU(shadow: ShadowPaint?, blur: BlurPaint?, _ primitive: CapturedPrimitive) {
        func readable(_ leaf: [CapturedPrimitive], surfaces: Bool) -> [CapturedPrimitive] {
            leaf.compactMap { q in
                if !(q.transform?.homography.isAffine ?? true) { return nil }
                if !surfaces, case .surface = q.kind { return nil }
                return q.bakedGroupAlpha
            }
        }
        if var paint = shadow {
            paint.leaf = readable(paint.leaf, surfaces: true)
            guard !paint.leaf.isEmpty, let (quad, texture) = shadowImage(paint, transform: primitive.transform) else { return }
            insertRaster(quad, texture: texture, primitive)
        } else if var paint = blur {
            paint.leaf = readable(paint.leaf, surfaces: false)
            guard !paint.leaf.isEmpty, let (quad, texture) = blurImage(paint, transform: primitive.transform) else { return }
            insertRaster(quad, texture: texture, primitive)
        }
    }
}
