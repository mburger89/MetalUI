import Testing
import MetalUIScene
import MetalUIShaderTypes

// Liquid Glass, lane A, scene-side tests 1 and 11 (rulings `LG-B`, `LG-L`; spec
// `docs/superpowers/specs/2026-10-23-liquid-glass-design.md` §3, §5). The record is the one
// `.backdrop` primitive grown to 256 bytes; its flat arm draws one rect per member.

/// **1** (`LG-B`). `MUIBackdrop` is 256 bytes (sixteen `float4` lanes, so the SDL bridge uploads
/// the records as they are) and its first six lanes did not move: bounds 0, contentMask 16,
/// maskCornerRadii 32, cornerRadii 48, tint 64, order 80, shape 84, sigma 88, opacity 92; the
/// glass tail follows at 96. Red before: stride 96. Mutation: insert a field before `tint`.
@Test func aBackdropRecordIs256BytesAndItsFirstSixLanesDidNotMove() {
    #expect(MemoryLayout<MUIBackdrop>.stride == 256)
    #expect(MemoryLayout<MUIBackdrop>.size == 256)
    #expect(MemoryLayout<MUIBackdrop>.alignment == 4)
    #expect(MemoryLayout<MUIBackdrop>.offset(of: \.bounds) == 0)
    #expect(MemoryLayout<MUIBackdrop>.offset(of: \.contentMask) == 16)
    #expect(MemoryLayout<MUIBackdrop>.offset(of: \.maskCornerRadii) == 32)
    #expect(MemoryLayout<MUIBackdrop>.offset(of: \.cornerRadii) == 48)
    #expect(MemoryLayout<MUIBackdrop>.offset(of: \.tint) == 64)
    #expect(MemoryLayout<MUIBackdrop>.offset(of: \.order) == 80)
    #expect(MemoryLayout<MUIBackdrop>.offset(of: \.shape) == 84)
    #expect(MemoryLayout<MUIBackdrop>.offset(of: \.sigma) == 88)
    #expect(MemoryLayout<MUIBackdrop>.offset(of: \.opacity) == 92)
    // The tail: two look lanes, then four members of two lanes each.
    #expect(MemoryLayout<MUIBackdrop>.offset(of: \.glassFlags) == 96)
    #expect(MemoryLayout<MUIBackdrop>.offset(of: \.lensDepth) == 100)
    #expect(MemoryLayout<MUIBackdrop>.offset(of: \.band) == 104)
    #expect(MemoryLayout<MUIBackdrop>.offset(of: \.rimStrength) == 108)
    #expect(MemoryLayout<MUIBackdrop>.offset(of: \.blendK) == 112)
    #expect(MemoryLayout<MUIBackdrop>.offset(of: \.press) == 116)
    #expect(MemoryLayout<MUIBackdrop>.offset(of: \.pressLift) == 120)
    #expect(MemoryLayout<MUIBackdrop>.offset(of: \.member0) == 128)
    #expect(MemoryLayout<MUIBackdrop>.offset(of: \.member1) == 160)
    #expect(MemoryLayout<MUIBackdrop>.offset(of: \.member2) == 192)
    #expect(MemoryLayout<MUIBackdrop>.offset(of: \.member3) == 224)
    #expect(MemoryLayout<MUIGlassMember>.stride == 32)
    // The nine-argument spelling every material site uses leaves the tail zero.
    let box = MUIBounds(origin: MUIPoint(x: 0, y: 0), size: MUISize(width: 10, height: 10))
    let square = MUICorners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0)
    let material = MUIBackdrop(bounds: box, contentMask: box, maskCornerRadii: square, cornerRadii: square,
                               tint: MUIHsla(h: 0, s: 0, l: 1, a: 0.5), order: 3, shape: 1, sigma: 52, opacity: 0.5)
    #expect(material.glassFlags == 0 && material.lensDepth == 0 && material.band == 0 && material.rimStrength == 0
            && material.blendK == 0 && material.press == 0 && material.pressLift == 0
            && material.member0.bounds.size.width == 0 && material.member3.radii.topLeft == 0)
    #expect(material.order == 3 && material.shape == 1 && material.sigma == 52 && material.opacity == 0.5)
}

private func box(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> MUIBounds {
    MUIBounds(origin: MUIPoint(x: x, y: y), size: MUISize(width: w, height: h))
}
private let square = MUICorners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0)

private func record(members: Int) -> MUIBackdrop {
    var r = MUIBackdrop(bounds: box(10, 20, 100, 40), contentMask: box(0, 0, 500, 500), maskCornerRadii: square,
                        cornerRadii: MUICorners(topLeft: 3, topRight: 3, bottomRight: 3, bottomLeft: 3),
                        tint: MUIHsla(h: 0.5, s: 0.4, l: 0.6, a: 0.5), order: 7, shape: 1 << 8, sigma: 52, opacity: 0.5)
    r.glassFlags = 1 | UInt32(members) << 3 | 1 << 7        // glass, count, member 1 an ellipse
    let slots = [MUIGlassMember(bounds: box(0, 0, 0.3, 1), radii: MUICorners(topLeft: 0.5, topRight: 0.5, bottomRight: 0.5, bottomLeft: 0.5)),
                 MUIGlassMember(bounds: box(0.4, 0.25, 0.2, 0.5), radii: square),
                 MUIGlassMember(bounds: box(0.7, 0, 0.3, 1), radii: MUICorners(topLeft: 0.25, topRight: 0, bottomRight: 0.25, bottomLeft: 0))]
    r.member0 = slots[0]; r.member1 = slots[1]; r.member2 = slots[2]
    return r
}

/// **11** (`LG-L`). The flat arm draws one rect per member: a member's rect is its slot scaled by the
/// record's bounds (origin and size as fractions, radii as a fraction of the shorter side), its
/// shape bit from the flags and its transform bits from the record's `shape`, tinted `T` with
/// alpha times opacity; a one-member record is `flatTintRect` unchanged. Mutation: return
/// member 0 only.
@Test func theFlatArmDrawsOneRectPerMember() throws {
    let blob = record(members: 3)
    let rects = blob.flatTintRects
    try #require(rects.count == 3)
    #expect(rects[0].bounds.origin.x == 10 && rects[0].bounds.origin.y == 20
            && rects[0].bounds.size.width == 30 && rects[0].bounds.size.height == 40)
    #expect(rects[0].cornerRadii.topLeft == 20 && rects[0].shape == 1 << 8, "radii are a fraction of the shorter side; the transform bits ride along")
    #expect(rects[1].bounds.origin.x == 50 && rects[1].bounds.origin.y == 30
            && rects[1].bounds.size.width == 20 && rects[1].bounds.size.height == 20)
    #expect(rects[1].shape == 1 | 1 << 8, "member 1 is an ellipse")
    #expect(rects[2].bounds.origin.x == 80 && rects[2].cornerRadii.topLeft == 10 && rects[2].cornerRadii.topRight == 0)
    for r in rects {
        #expect(r.background.a == 0.25 && r.background.h == 0.5 && r.order == 7, "tint alpha times opacity")
        #expect(r.contentMask.size.width == 500)
    }
    // One member (or none): `flatTintRect`, the record's own bounds, radii and shape.
    let single = record(members: 1)
    let one = single.flatTintRects
    try #require(one.count == 1)
    #expect(one[0].bounds.size.width == 100 && one[0].cornerRadii.topLeft == 3 && one[0].shape == 1 << 8)
    #expect(one[0].background.a == 0.25)
    var material = single
    material.glassFlags = 0
    #expect(material.flatTintRects.count == 1 && material.flatTintRects[0].bounds.size.width == 100, "a material is one rect")
    // More than four members are four.
    var many = blob
    many.glassFlags = 1 | 7 << 3
    #expect(many.flatTintRects.count == 4)
}
