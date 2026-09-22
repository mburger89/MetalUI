import MetalUICore
import MetalUIText
@_exported import MetalUIShaderTypes
// Ruling PS-B: Scene, DrawRun and PrimitiveKind lived in this module until
// 2026-09-22; re-exported so `import MetalUIRender` still sees them.
@_exported import MetalUIScene

extension MUIPoint {
    init(_ p: Point<ScaledPixels>) { self.init(x: p.x.value, y: p.y.value) }
}

extension MUISize {
    init(_ s: Size<ScaledPixels>) { self.init(width: s.width.value, height: s.height.value) }
}

extension MUIBounds {
    init(_ b: Bounds<ScaledPixels>) { self.init(origin: MUIPoint(b.origin), size: MUISize(b.size)) }
}

extension MUIHsla {
    init(_ c: Hsla) { self.init(h: c.h, s: c.s, l: c.l, a: c.a) }
}

extension MUICorners {
    init(_ c: Corners<ScaledPixels>) {
        self.init(topLeft: c.topLeft.value, topRight: c.topRight.value,
                  bottomRight: c.bottomRight.value, bottomLeft: c.bottomLeft.value)
    }
}

extension MUIEdges {
    init(_ e: Edges<ScaledPixels>) {
        self.init(top: e.top.value, right: e.right.value,
                  bottom: e.bottom.value, left: e.left.value)
    }
}

extension MUIRect {
    /// Build a GPU rect from framework types. All geometry must already be scaled.
    ///
    /// `maskCornerRadii` defaults to a square clip — every call site written
    /// before this parameter existed means exactly that, and keeps compiling
    /// and behaving identically without mentioning it.
    public init(
        bounds: Bounds<ScaledPixels>,
        contentMask: Bounds<ScaledPixels>,
        maskCornerRadii: Corners<ScaledPixels> = Corners(all: ScaledPixels(0)),
        background: Hsla,
        borderColor: Hsla,
        cornerRadii: Corners<ScaledPixels>,
        borderWidths: Edges<ScaledPixels>,
        order: UInt32
    ) {
        self.init(bounds: MUIBounds(bounds),
                  contentMask: MUIBounds(contentMask),
                  maskCornerRadii: MUICorners(maskCornerRadii),
                  background: MUIHsla(background),
                  borderColor: MUIHsla(borderColor),
                  cornerRadii: MUICorners(cornerRadii),
                  borderWidths: MUIEdges(borderWidths),
                  order: order,
                  _reserved: 0)
    }
}

extension MUIGlyph {
    /// Build a GPU glyph sprite from framework types.
    ///
    /// **Two coordinate systems meet here, which is why they are two
    /// parameters.** `bounds` is the destination on the render target, in
    /// `ScaledPixels`; `slot` is the source in atlas texels, and it supplies the
    /// sprite's *size* as well as its origin — a sprite is a 1:1 blit, so a
    /// destination whose size disagreed with the slot's would resample the
    /// bitmap. The caller still passes the destination size explicitly because
    /// scaling is where this path goes next (spec §7.5), and a size taken from
    /// the slot by construction could not express it.
    /// `maskCornerRadii` defaults to a square clip — see `MUIRect`'s init.
    public init(bounds: Bounds<ScaledPixels>,
                slot: AtlasSlot,
                contentMask: Bounds<ScaledPixels>,
                maskCornerRadii: Corners<ScaledPixels> = Corners(all: ScaledPixels(0)),
                color: Hsla,
                order: UInt32) {
        self.init(bounds: MUIBounds(bounds),
                  atlasBounds: MUIBounds(
                      origin: MUIPoint(x: Float(slot.x), y: Float(slot.y)),
                      size: MUISize(width: Float(slot.width), height: Float(slot.height))),
                  contentMask: MUIBounds(contentMask),
                  maskCornerRadii: MUICorners(maskCornerRadii),
                  color: MUIHsla(color),
                  order: order,
                  _reserved: 0)
    }
}
