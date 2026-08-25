import MetalUICore
@_exported import MetalUIShaderTypes

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
    public init(
        bounds: Bounds<ScaledPixels>,
        contentMask: Bounds<ScaledPixels>,
        background: Hsla,
        borderColor: Hsla,
        cornerRadii: Corners<ScaledPixels>,
        borderWidths: Edges<ScaledPixels>,
        order: UInt32
    ) {
        self.init(bounds: MUIBounds(bounds),
                  contentMask: MUIBounds(contentMask),
                  background: MUIHsla(background),
                  borderColor: MUIHsla(borderColor),
                  cornerRadii: MUICorners(cornerRadii),
                  borderWidths: MUIEdges(borderWidths),
                  order: order,
                  _reserved: 0)
    }
}
