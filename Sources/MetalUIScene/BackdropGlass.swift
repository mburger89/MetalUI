import MetalUIShaderTypes

// The Liquid Glass tail of `MUIBackdrop` (ruling `LG-B`): the nine-argument spelling every
// material site writes, and the flat arm's rects.

extension MUIBackdrop {
    /// A material's record: the six original lanes, with the glass tail zero
    /// (`glassFlags == 0`, so a renderer takes the material arithmetic byte for
    /// byte, ruling `LG-B`). The spelling `MUIBackdrop` had when it was 96 bytes.
    public init(bounds: MUIBounds, contentMask: MUIBounds, maskCornerRadii: MUICorners, cornerRadii: MUICorners,
                tint: MUIHsla, order: MUIUInt, shape: MUIUInt, sigma: Float, opacity: Float) {
        self.init()
        self.bounds = bounds
        self.contentMask = contentMask
        self.maskCornerRadii = maskCornerRadii
        self.cornerRadii = cornerRadii
        self.tint = tint
        self.order = order
        self.shape = shape
        self.sigma = sigma
        self.opacity = opacity
    }

    /// Whether `glassFlags` bit 0 marks the record a glass.
    package var isGlass: Bool { glassFlags & 1 != 0 }

    /// The members a glass blob folds: bits 3...5 of `glassFlags` read as `1...4`
    /// (a material and a one-member glass read the record itself).
    package var glassMemberCount: Int {
        isGlass ? min(max(Int((glassFlags >> 3) & 7), 1), 4) : 1
    }

    /// The record's flat arm as rects (rulings `BB-I`, `LG-L`): `c · o · T` over
    /// the sharp backdrop, **one rect per member** of a blob. A material or a
    /// one-member glass is one rect of the record's own bounds, radii and shape
    /// (today's flat tint pixel for pixel); a member's rect is its slot scaled by
    /// the record's bounds (radii by the shorter side), its shape bit read from
    /// `glassFlags` and its transform bits from `shape`. The lens, the rim and the
    /// merge are lost, the base tint stays.
    package var flatTintRects: [MUIRect] {
        var color = tint
        color.a *= opacity
        let clear = MUIHsla(h: 0, s: 0, l: 0, a: 0)
        let noBorder = MUIEdges(top: 0, right: 0, bottom: 0, left: 0)
        let count = glassMemberCount
        guard count > 1 else {
            return [MUIRect(bounds: bounds, contentMask: contentMask, maskCornerRadii: maskCornerRadii,
                            background: color, borderColor: clear, cornerRadii: cornerRadii,
                            borderWidths: noBorder, order: order, shape: shape)]
        }
        let width = bounds.size.width, height = bounds.size.height
        let shorter = min(width, height)
        let slots = [member0, member1, member2, member3]
        return (0..<count).map { k in
            let m = slots[k]
            let box = MUIBounds(
                origin: MUIPoint(x: bounds.origin.x + m.bounds.origin.x * width,
                                 y: bounds.origin.y + m.bounds.origin.y * height),
                size: MUISize(width: m.bounds.size.width * width, height: m.bounds.size.height * height))
            let radii = MUICorners(topLeft: m.radii.topLeft * shorter, topRight: m.radii.topRight * shorter,
                                   bottomRight: m.radii.bottomRight * shorter, bottomLeft: m.radii.bottomLeft * shorter)
            let ellipse: MUIUInt = (glassFlags >> MUIUInt(6 + k)) & 1
            return MUIRect(bounds: box, contentMask: contentMask, maskCornerRadii: maskCornerRadii,
                           background: color, borderColor: clear, cornerRadii: radii,
                           borderWidths: noBorder, order: order, shape: (shape & ~0xFF) | ellipse)
        }
    }
}
