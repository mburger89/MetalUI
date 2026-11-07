import Testing
import Metal
import MetalUICore
import MetalUIShaderTypes
@testable import MetalUIRender

// R4-5 PR C, masked groups (ruling `CM-A`; record 220). Renderer level: a hand-built scene with one group quad whose mask scene
// is an ellipse rect, over a white background, analytic pixels. The group is at (60, 50) so a projection that differs between
// the group's content and its mask moves one off the other.

private let red = Hsla(h: 0, s: 1, l: 0.5, a: 1)

private func box(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> Bounds<ScaledPixels> {
    Bounds(origin: Point(x: ScaledPixels(x), y: ScaledPixels(y)), size: Size(width: ScaledPixels(w), height: ScaledPixels(h)))
}

private func rect(_ x: Float, _ y: Float, _ w: Float, _ h: Float, _ color: Hsla, order: UInt32, ellipse: Bool = false) -> MUIRect {
    MUIRect(bounds: box(x, y, w, h), contentMask: box(0, 0, 400, 400), background: color, borderColor: .transparent,
            cornerRadii: Corners(all: ScaledPixels(0)), borderWidths: Edges(all: ScaledPixels(0)), order: order,
            shape: ellipse ? .ellipse : .roundedRectangle)
}

private func pixel(_ pixels: [UInt8], _ x: Int, _ y: Int, width: Int = 200) -> [Int] {
    let i = (y * width + x) * 4
    return [Int(pixels[i + 2]), Int(pixels[i + 1]), Int(pixels[i]), Int(pixels[i + 3])]
}

private func groupQuad(_ x: Float, _ y: Float, _ w: Float, _ h: Float, order: UInt32) -> MUIImage {
    MUIImage(bounds: box(x, y, w, h), contentMask: box(x, y, w, h), opacity: 1, filter: .nearest, order: order)
}

/// A finalized scene of one red 80 x 80 square at (60, 50).
private func squareScene() -> Scene {
    var inner = Scene()
    inner.insert(rect(60, 50, 80, 80, red, order: 0))
    inner.finalize()
    return inner
}

/// A finalized mask scene: the ellipse inscribed in the same square.
private func ellipseMask(id: Float = 80) -> Scene {
    var mask = Scene()
    mask.insert(rect(60, 50, id, id, .white, order: 0, ellipse: true))
    mask.finalize()
    return mask
}

private func maskedScene() -> Scene {
    var scene = Scene()
    scene.insert(rect(0, 0, 200, 200, .white, order: 0))
    scene.insert(groupQuad(59, 49, 82, 82, order: 1), group: squareScene(), mask: ellipseMask())
    scene.finalize()
    return scene
}

/// **CM-A (Metal).** The group's target is multiplied by the mask's alpha: the square's corner (inside the square, outside the
/// ellipse) shows the white background, the centre shows the red, and one group pass and one mask pass ran. The group sits at
/// (60, 50), so a mask drawn with another projection than the content's lands elsewhere. Mutations: the mask pass skipped (the
/// corner is red); the mask drawn with the identity projection (the centre is white).
@Test @MainActor func aMaskedGroupMultipliesItsTargetByTheMasksAlpha() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let renderer = try Renderer(device: device)
    let pixels = try renderer.renderOffscreen(maskedScene(), size: Size(width: DevicePixels(200), height: DevicePixels(200)))
    #expect(pixel(pixels, 100, 90) == [255, 0, 0, 255], "the centre is red: \(pixel(pixels, 100, 90))")
    #expect(pixel(pixels, 62, 52) == [255, 255, 255, 255], "the square's corner is masked away: \(pixel(pixels, 62, 52))")
    #expect(pixel(pixels, 20, 20) == [255, 255, 255, 255], "outside: \(pixel(pixels, 20, 20))")
    #expect(renderer.lastGroupPasses == 1 && renderer.lastMaskPasses == 1, "\(renderer.lastGroupPasses) \(renderer.lastMaskPasses)")
}

/// **CM-A.** The mask is the shape's alpha, not its colour: the same scene with a half-transparent mask halves the group. The
/// destination-in blend scales every channel (the group's colour is premultiplied). Mutation: the blend's destination factor
/// `one` (the mask does nothing).
@Test @MainActor func aMaskScalesAllFourChannelsByItsAlpha() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let renderer = try Renderer(device: device)
    var half = Scene()
    var maskRect = rect(60, 50, 80, 80, .white, order: 0)
    maskRect.background.a = 0.5
    half.insert(maskRect)
    half.finalize()
    var scene = Scene()
    scene.insert(groupQuad(59, 49, 82, 82, order: 1), group: squareScene(), mask: half)
    scene.finalize()
    let pixels = try renderer.renderOffscreen(scene, size: Size(width: DevicePixels(200), height: DevicePixels(200)))
    let p = pixel(pixels, 100, 90)
    #expect(abs(p[0] - 128) <= 1 && p[1] == 0 && p[2] == 0 && abs(p[3] - 128) <= 1, "half red over nothing: \(p)")
}

/// **CM-A (Scene).** `finalize` keeps each group's mask with its group when it sorts them: three groups inserted out of layer
/// order, each with a mask scene of its own width, come out with their own masks; the clear drops them.
/// Mutation: `groupMasks` not permuted by `finalize`.
@Test func finalizeKeepsEachGroupsMask() {
    var scene = Scene()
    // Inserted in the order 2, 0, 1 by layer; the mask's width names the group.
    scene.insert(groupQuad(0, 0, 10, 10, order: 0), group: squareScene(), layer: 2, mask: ellipseMask(id: 12))
    scene.insert(groupQuad(0, 0, 10, 10, order: 0), group: squareScene(), layer: 0, mask: ellipseMask(id: 10))
    scene.insert(groupQuad(0, 0, 10, 10, order: 0), group: squareScene(), layer: 1)
    scene.finalize()
    #expect(scene.groupMasks.count == 3)
    #expect(scene.groupMasks[0]?.rects.first?.bounds.size.width == 10, "layer 0 keeps its mask")
    #expect(scene.groupMasks[1] == nil, "layer 1 has none")
    #expect(scene.groupMasks[2]?.rects.first?.bounds.size.width == 12, "layer 2 keeps its mask")
    scene.clear()
    #expect(scene.groupMasks.isEmpty && scene.groups.isEmpty)
}
