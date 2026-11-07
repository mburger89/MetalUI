import MetalUICore
import MetalUILayout
import MetalUIPath
import MetalUIPrimitives

// R4-5 PR C — a shape clip as a masked group (ruling prefix `CM-`, record 220). A clip the per-primitive rounded-rect
// mask cannot express (an ellipse, a path, an even-odd or non-antialiased fill) paints its content into an offscreen
// group that is multiplied by the shape's coverage when it is drawn back; two crossing rounded clips do the same with
// the second rounded rect as the mask (divergence 92 retired). The bounding rect of the shape is still pushed as an
// ordinary clip, so hit testing, accessibility and every primitive's own mask are unchanged (`TE-AQ` item 4, `CM-E`).

/// The part of a shape clip a rounded-rect mask cannot draw (`CM-A`).
enum ClipMask {
    /// The ellipse inscribed in the rect (window points, before the paint offset).
    case ellipse(Bounds<Pixels>)
    /// A path in window points, filled under the style (its rule and its anti-aliasing).
    case path(Path, FillStyle)
}

/// What a shape clip pushes: the bounding rect and radii of the ordinary clip, and the mask when the shape is not that
/// rounded rectangle (`CM-A`).
struct ClipRegion {
    var bounds: Bounds<Pixels>
    var radii: Corners<Pixels>
    var mask: ClipMask?
}

extension ShapeGeometry {
    /// The clip this geometry pushes (`TE-AJ` items 1-2, `CM-A`): a rounded rectangle is today's clip with no mask; an
    /// ellipse is its bounding rect with an ellipse mask; a path is its bounding rect with a path mask. A fill style that
    /// is not the default (even-odd, or not anti-aliased) turns any geometry into a path mask, since a rounded-rect mask
    /// cannot draw either.
    func clip(style: FillStyle = FillStyle()) -> ClipRegion {
        let square = Corners(all: Pixels(0))
        switch kind {
        case let .roundedRectangle(radii, _):
            guard !style.isAntialiased else { return ClipRegion(bounds: rect, radii: radii, mask: nil) }
            return ClipRegion(bounds: rect, radii: square, mask: .path(Path(self), style))
        case .ellipse:
            guard !style.isAntialiased else { return ClipRegion(bounds: rect, radii: square, mask: .ellipse(rect)) }
            return ClipRegion(bounds: rect, radii: square, mask: .path(Path(self), style))
        case let .path(path, own):
            let merged = FillStyle(eoFill: style.isEOFilled || own.isEOFilled,
                                   antialiased: style.isAntialiased && own.isAntialiased)
            return ClipRegion(bounds: path.boundingRect, radii: square, mask: .path(path, merged))
        }
    }
}

extension Frame {
    /// The mask as a primitive in the space the content is emitted in now: the active offset and scale applied, no clip of
    /// its own (the content is already cut by the bounding clip, and the product with the shape is the same whichever
    /// side cuts first). A white ellipse rect, or a white path still a vector until it reaches a scene.
    func maskPrimitive(for mask: ClipMask) -> CapturedPrimitive {
        let white = MUIHsla(h: 0, s: 0, l: 1, a: 1)
        switch mask {
        case let .ellipse(rect):
            let translated = Bounds(
                origin: Point(x: Pixels(rect.origin.x.value + activeOffset.x.value),
                              y: Pixels(rect.origin.y.value + activeOffset.y.value)),
                size: rect.size)
            let scaled = MUIBounds(translated.scaled(by: scaleFactor))
            let zeroCorners = MUICorners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0)
            let r = MUIRect(bounds: scaled, contentMask: Self.unboundedMask, maskCornerRadii: zeroCorners,
                            background: white, borderColor: MUIHsla(h: 0, s: 0, l: 0, a: 0), cornerRadii: zeroCorners,
                            borderWidths: MUIEdges(top: 0, right: 0, bottom: 0, left: 0), order: 0,
                            shape: PrimitiveShape.ellipse.rawValue)
            return CapturedPrimitive(kind: .rect(r), layer: activeLayer, innerMask: false)
        case let .path(path, style):
            let s = Double(scaleFactor)
            let local = Affine2D(a: s, d: s, tx: Double(activeOffset.x.value) * s, ty: Double(activeOffset.y.value) * s)
            let paint = PathPaint(geometry: path.storage, mode: .fill(style.rule, antialiased: style.isAntialiased),
                                  local: local, color: Hsla(h: 0, s: 0, l: 1, a: 1), contentMask: Self.unboundedMask,
                                  maskCornerRadii: MUICorners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0))
            return CapturedPrimitive(kind: .path(paint), layer: activeLayer, innerMask: false)
        }
    }

    /// Paint inside a mask scope (`CM-A`): every leaf that reaches it (after the scopes inside it) is collected, as a
    /// composite scope collects, and when it closes the collection leaves marked with the mask, so `insertLeaves` renders it
    /// as one offscreen group multiplied by the shape. **Always pushed**: unlike an opacity group there is no reader to
    /// wait for. The mark carries alpha 1: an opacity outside a clip fades each leaf (probe `CM6`, `CM-C`). A scope holding
    /// a material or glass is not marked: its live backdrop cannot move into a group, so it keeps the bounding clip
    /// (divergence 224, `masksFlattenedBackdrop`).
    func paintWithMask(_ mask: ClipMask, _ body: () -> Void) {
        paintWithMask(primitive: maskPrimitive(for: mask), maskDepth: clipDepth, body)
    }

    /// ``paintWithMask(_:_:)`` for a mask primitive already built (`CM-A`).
    /// `maskDepth` is the clip depth the mask's own clip was read at (`GroupMark.maskDepth`).
    func paintWithMask(primitive: CapturedPrimitive, maskDepth: Int, _ body: () -> Void) {
        maskScopesPushed += 1
        let scope = PaintScope(kind: .composite, effect: .identity, entryClipDepth: clipDepth)
        scope.mask = primitive
        paintScopes.append(scope)
        body()
        paintScopes.removeLast()
        guard !scope.captures.isEmpty else { return }
        var captures = scope.captures
        if captures.contains(where: { if case .backdrop = $0.kind { true } else { false } }) {
            masksFlattenedBackdrop += 1
        } else {
            let mark = GroupMark(token: GroupToken(), alpha: 1, mask: [primitive], maskDepth: maskDepth)
            for i in captures.indices { captures[i].groups.insert(mark, at: 0) }
        }
        insertThroughScopes(leaf: captures, depths: scope.captureDepths)
    }

    /// `pushClip` around `body`, inside a mask scope when the pushed clip crosses the one in force (`CM-B`, divergence 92
    /// retired): both are rounded and neither contains the other, so ``intersect(_:radii:_:radii:)`` pushes their square
    /// box, and the content is multiplied by the pair's exact coverage as well. One mask rect: the new clip as its own
    /// outline, the clip in force as its content mask, so the coverage is the product of both rounded rects. The pushed clip
    /// stays the square box, so hit testing and every primitive's own mask are unchanged.
    func paintClipped(_ bounds: Bounds<Pixels>, offset: Point<Pixels>, radii: Corners<Pixels>, _ body: () -> Void) {
        func square(_ c: Corners<Pixels>) -> Bool {
            c.topLeft == Pixels(0) && c.topRight == Pixels(0) && c.bottomRight == Pixels(0) && c.bottomLeft == Pixels(0)
        }
        var crossing: CapturedPrimitive?
        if !(square(radii) && square(activeClipRadii)), !atFlatteningEntry {
            let translated = Bounds(
                origin: Point(x: Pixels(bounds.origin.x.value + activeOffset.x.value),
                              y: Pixels(bounds.origin.y.value + activeOffset.y.value)),
                size: bounds.size)
            if Self.clipsCross(activeClip, radii: activeClipRadii, translated, radii: radii) {
                let none = MUIHsla(h: 0, s: 0, l: 0, a: 0)
                let r = MUIRect(bounds: MUIBounds(translated.scaled(by: scaleFactor)),
                                contentMask: MUIBounds(activeClip.scaled(by: scaleFactor)),
                                maskCornerRadii: MUICorners(activeClipRadii.scaled(by: scaleFactor)),
                                background: MUIHsla(h: 0, s: 0, l: 1, a: 1), borderColor: none,
                                cornerRadii: MUICorners(radii.scaled(by: scaleFactor)),
                                borderWidths: MUIEdges(top: 0, right: 0, bottom: 0, left: 0), order: 0,
                                shape: PrimitiveShape.roundedRectangle.rawValue)
                crossing = CapturedPrimitive(kind: .rect(r), layer: activeLayer, innerMask: false)
            }
        }
        let readAt = clipDepth
        pushClip(bounds, offset: offset, radii: radii)
        defer { popClip() }
        if let crossing { paintWithMask(primitive: crossing, maskDepth: readAt, body) } else { body() }
    }

    /// The flags `processScopes` sets on `p`'s own mask, set on the masks its marks carry (`CM-A`): whether each mask's clip
    /// was pushed inside the scope that is about to map it, and its transform's outer mask.
    static func flagMarkMasks(_ p: inout CapturedPrimitive, _ entryDepth: Int) {
        for k in p.groups.indices where p.groups[k].isMasked {
            p.groups[k].mask[0].innerMask = p.groups[k].maskDepth > entryDepth
            p.groups[k].mask[0].outerMaskInner = p.groups[k].mask[0].transform.map { $0.outerDepth > entryDepth } ?? false
        }
    }

    /// One masked offscreen group (`CM-A`): `children` rendered into a scene of their own, `mask` into another, the box the
    /// overlap of their painted extents grown a pixel, and the pair drawn back as one quad the renderer multiplies by the
    /// mask's alpha. A lone plain rect that covers an ellipse mask is that ellipse instead (an exact shortcut); a group
    /// over the target limit is drawn per primitive under the bounding clip alone.
    func insertMaskedGroup(_ children: [CapturedPrimitive], mask: CapturedPrimitive) {
        if children.count == 1, children[0].groups.isEmpty, let baked = Self.bakingToEllipse(children[0], mask: mask) {
            masksBakedToEllipse += 1
            insertIntoScene(baked)
            return
        }
        var inner = collectingIntoFreshScene { insertLeaves(children) }
        var maskScene = collectingIntoFreshScene { insertIntoScene(mask) }
        guard let content = inner.paintedBounds(), let shape = maskScene.paintedBounds() else { return }
        let painted = (minX: max(content.minX, shape.minX), minY: max(content.minY, shape.minY),
                       maxX: min(content.maxX, shape.maxX), maxY: min(content.maxY, shape.maxY))
        guard painted.maxX > painted.minX, painted.maxY > painted.minY else { return }
        let limitX = Float(contentSize.width.value * scaleFactor), limitY = Float(contentSize.height.value * scaleFactor)
        func floorInt(_ v: Float) -> Float { let t = Float(Int(v)); return t > v ? t - 1 : t }
        func ceilInt(_ v: Float) -> Float { let t = Float(Int(v)); return t < v ? t + 1 : t }
        let x0 = max(floorInt(painted.minX - 1), 0), y0 = max(floorInt(painted.minY - 1), 0)
        let x1 = min(ceilInt(painted.maxX + 1), ceilInt(limitX)), y1 = min(ceilInt(painted.maxY + 1), ceilInt(limitY))
        guard x1 > x0, y1 > y0 else { return }
        if x1 - x0 > Float(Self.maxGroupTargetSide) || y1 - y0 > Float(Self.maxGroupTargetSide) {
            // Too large for one target: drawn per primitive under the bounding clip alone, as before this existed.
            masksFlattenedOversize += 1
            var flat = children
            for k in flat.indices { flat[k].bakeGroupAlpha() }
            insertLeaves(flat)
            return
        }
        inner.finalize()
        maskScene.finalize()
        let box = MUIBounds(origin: MUIPoint(x: x0, y: y0), size: MUISize(width: x1 - x0, height: y1 - y0))
        let quad = MUIImage(bounds: box, contentMask: box,
                            maskCornerRadii: MUICorners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0),
                            opacity: 1, texture: 0, filter: ImageFilter.nearest.rawValue, order: 0)
        groupsMasked += 1
        insertMaskedQuad(quad, group: inner, mask: maskScene, layer: children.first?.layer ?? activeLayer)
    }

    /// `content` as the ellipse `mask` draws it, when it is a plain untransformed rect with no rounding or border whose
    /// bounds hold the whole ellipse: the rect's fill under the ellipse's coverage is exactly the ellipse rect's.
    private static func bakingToEllipse(_ content: CapturedPrimitive, mask: CapturedPrimitive) -> CapturedPrimitive? {
        guard content.transform == nil, mask.transform == nil,
              case var .rect(r) = content.kind, case let .rect(m) = mask.kind,
              m.shape == PrimitiveShape.ellipse.rawValue, r.shape == PrimitiveShape.roundedRectangle.rawValue,
              r.cornerRadii.topLeft == 0, r.cornerRadii.topRight == 0,
              r.cornerRadii.bottomRight == 0, r.cornerRadii.bottomLeft == 0,
              r.borderWidths.top == 0, r.borderWidths.right == 0, r.borderWidths.bottom == 0, r.borderWidths.left == 0,
              r.bounds.origin.x <= m.bounds.origin.x, r.bounds.origin.y <= m.bounds.origin.y,
              r.bounds.origin.x + r.bounds.size.width >= m.bounds.origin.x + m.bounds.size.width,
              r.bounds.origin.y + r.bounds.size.height >= m.bounds.origin.y + m.bounds.size.height
        else { return nil }
        r.bounds = m.bounds
        r.shape = PrimitiveShape.ellipse.rawValue
        var baked = content
        baked.kind = .rect(r)
        return baked
    }
}
