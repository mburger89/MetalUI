import Testing
import Metal
import MetalUICore
import MetalUIShaderTypes
@testable import MetalUIRender

/// A rect clipped to the left half of its own box.
///
/// **The expected values are built from the CLIP, not from the primitive.**
/// Reading the mask back off the `MUIRect` to decide what to assert would be
/// taxonomy shape 12 — the oracle being the code under test — which produced
/// four defects in M2. The x boundary here is a literal.
private func clippedRect(mask: MUIBounds) -> MUIRect {
    MUIRect(bounds: MUIBounds(origin: MUIPoint(x: 10, y: 10),
                              size: MUISize(width: 40, height: 40)),
            contentMask: mask,
            background: MUIHsla(h: 0, s: 0, l: 1, a: 1),   // white
            borderColor: MUIHsla(h: 0, s: 0, l: 0, a: 0),
            cornerRadii: MUICorners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0),
            borderWidths: MUIEdges(top: 0, right: 0, bottom: 0, left: 0),
            order: 0, _reserved: 0)
}

@Test @MainActor func aRectIsPaintedOnlyInsideItsContentMask() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let renderer = try Renderer(device: device)
    let side = 64
    let size = Size(width: DevicePixels(Int32(side)), height: DevicePixels(Int32(side)))

    // The rect spans x 10..<50. Clip it to x 10..<30.
    var scene = Scene()
    scene.insert(clippedRect(mask: MUIBounds(origin: MUIPoint(x: 0, y: 0),
                                             size: MUISize(width: 30, height: 64))))
    scene.finalize()
    let pixels = try renderer.renderOffscreen(scene, size: size)

    func alphaAt(_ x: Int, _ y: Int) -> UInt8 { pixels[((y * side) + x) * 4 + 3] }

    // Well inside the clip: painted.
    #expect(alphaAt(15, 25) > 200, "x=15 is inside both the rect and the clip")
    #expect(alphaAt(25, 25) > 200, "x=25 is inside both")
    // Well outside the clip but inside the rect: not painted.
    #expect(alphaAt(35, 25) < 20, "x=35 is inside the rect and outside the clip")
    #expect(alphaAt(45, 25) < 20, "x=45 is inside the rect and outside the clip")
    // Outside the rect entirely: not painted, clip or no clip.
    #expect(alphaAt(5, 25) < 20)
}

/// The differential: the identical rect with a full-surface mask paints all the
/// way across. Without this, the test above passes on a shader that paints
/// nothing beyond x=30 for an unrelated reason.
@Test @MainActor func theSameRectWithAFullMaskPaintsItsWholeWidth() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let renderer = try Renderer(device: device)
    let side = 64
    let size = Size(width: DevicePixels(Int32(side)), height: DevicePixels(Int32(side)))

    var scene = Scene()
    scene.insert(clippedRect(mask: MUIBounds(origin: MUIPoint(x: 0, y: 0),
                                             size: MUISize(width: 64, height: 64))))
    scene.finalize()
    let pixels = try renderer.renderOffscreen(scene, size: size)
    func alphaAt(_ x: Int, _ y: Int) -> UInt8 { pixels[((y * side) + x) * 4 + 3] }

    #expect(alphaAt(35, 25) > 200, "unclipped, x=35 must be painted")
    #expect(alphaAt(45, 25) > 200, "unclipped, x=45 must be painted")
}

/// The clip edge is antialiased rather than a hard step. A half-pixel boundary
/// must produce a partially covered pixel, the same way the rect's own edge
/// does — a hard cutoff jags visibly on fractional boundaries.
@Test @MainActor func theClipEdgeIsAntialiasedLikeTheRectsOwnEdge() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let renderer = try Renderer(device: device)
    let side = 64
    let size = Size(width: DevicePixels(Int32(side)), height: DevicePixels(Int32(side)))

    var scene = Scene()
    scene.insert(clippedRect(mask: MUIBounds(origin: MUIPoint(x: 0, y: 0),
                                             size: MUISize(width: 30.5, height: 64))))
    scene.finalize()
    let pixels = try renderer.renderOffscreen(scene, size: size)
    func alphaAt(_ x: Int, _ y: Int) -> UInt8 { pixels[((y * side) + x) * 4 + 3] }

    let edge = alphaAt(30, 25)
    #expect(edge > 20 && edge < 235,
            "the pixel straddling a 30.5 boundary must be partially covered, got \(edge)")
}
