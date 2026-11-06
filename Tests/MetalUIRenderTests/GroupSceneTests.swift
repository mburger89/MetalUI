import Testing
import Metal
import MetalUICore
import MetalUIShaderTypes
@testable import MetalUIRender

// R4-5 PR A, offscreen opacity groups (rulings `GO-D`, `GO-E`; record 218; probe
// `docs/probes/swiftui-group-opacity.swift`). Renderer level: a hand-built scene with one group quad over
// a white background, analytic pixels. The group is at (60, 50) so a post-NDC translation with a flipped
// sign on either axis moves the content off its pixels.

private let red = Hsla(h: 0, s: 1, l: 0.5, a: 1)
private let blue = Hsla(h: 2.0 / 3.0, s: 1, l: 0.5, a: 1)

private func box(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> Bounds<ScaledPixels> {
    Bounds(origin: Point(x: ScaledPixels(x), y: ScaledPixels(y)), size: Size(width: ScaledPixels(w), height: ScaledPixels(h)))
}

private func rect(_ x: Float, _ y: Float, _ w: Float, _ h: Float, _ color: Hsla, order: UInt32) -> MUIRect {
    MUIRect(bounds: box(x, y, w, h), contentMask: box(0, 0, 400, 400), background: color, borderColor: .transparent,
            cornerRadii: Corners(all: ScaledPixels(0)), borderWidths: Edges(all: ScaledPixels(0)), order: order)
}

private func pixel(_ pixels: [UInt8], _ x: Int, _ y: Int, width: Int = 200) -> [Int] {
    let i = (y * width + x) * 4
    return [Int(pixels[i + 2]), Int(pixels[i + 1]), Int(pixels[i]), Int(pixels[i + 3])]
}

private func near(_ a: [Int], _ b: [Int], _ tolerance: Int = 1) -> Bool {
    zip(a, b).allSatisfy { abs($0 - $1) <= tolerance }
}

/// The probe's overlap: blue (90, 80) 60 square, then red (60, 50) on top, as one finalized scene.
private func overlapScene(origin: (Float, Float) = (60, 50)) -> Scene {
    var inner = Scene()
    inner.insert(rect(origin.0 + 30, origin.1 + 30, 60, 60, blue, order: 0))
    inner.insert(rect(origin.0, origin.1, 60, 60, red, order: 1))
    inner.finalize()
    return inner
}

private func groupQuad(_ x: Float, _ y: Float, _ w: Float, _ h: Float, opacity: Float, order: UInt32) -> MUIImage {
    MUIImage(bounds: box(x, y, w, h), contentMask: box(x, y, w, h), opacity: opacity, filter: .nearest, order: order)
}

private func background() -> MUIRect { rect(0, 0, 200, 200, .white, order: 0) }

/// **GO-E.** The group renders into its own target and is drawn back at its opacity: the overlap reads the top colour
/// over white, (255, 128, 128), where a per-primitive fade reads (191, 64, 128) (the probe's GO0 pair). Mutations:
/// the projection's x negated, y negated, a `.load` rather than `.clear` pass, the quad drawn at opacity 1.
@Test @MainActor func aGroupCompositesItsOverlapAtTheGroupOpacity() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let renderer = try Renderer(device: device)
    var scene = Scene()
    scene.insert(background())
    scene.insert(groupQuad(59, 49, 92, 92, opacity: 0.5, order: 1), group: overlapScene())
    scene.finalize()
    let size = Size(width: DevicePixels(200), height: DevicePixels(200))
    let pixels = try renderer.renderOffscreen(scene, size: size)
    #expect(near(pixel(pixels, 100, 90), [255, 128, 128, 255]), "overlap composited: \(pixel(pixels, 100, 90))")
    #expect(near(pixel(pixels, 70, 60), [255, 128, 128, 255]), "red only: \(pixel(pixels, 70, 60))")
    #expect(near(pixel(pixels, 140, 130), [128, 128, 255, 255]), "blue only: \(pixel(pixels, 140, 130))")
    #expect(near(pixel(pixels, 20, 20), [255, 255, 255, 255]), "outside: \(pixel(pixels, 20, 20))")
    #expect(near(pixel(pixels, 55, 90), [255, 255, 255, 255]), "left of the box: \(pixel(pixels, 55, 90))")
    #expect(renderer.lastGroupPasses == 1, "passes: \(renderer.lastGroupPasses)")

    // The separating arm: the same two squares faded one by one (the per-primitive model).
    var plain = Scene()
    plain.insert(background())
    var faded = red; faded.a = 0.5
    var fadedBlue = blue; fadedBlue.a = 0.5
    plain.insert(rect(90, 80, 60, 60, fadedBlue, order: 1))
    plain.insert(rect(60, 50, 60, 60, faded, order: 2))
    plain.finalize()
    let flat = try renderer.renderOffscreen(plain, size: size)
    #expect(near(pixel(flat, 100, 90), [191, 64, 128, 255]), "per leaf: \(pixel(flat, 100, 90))")
    #expect(renderer.lastGroupPasses == 0, "no group, no pass")
}

/// **GO-E.** A group inside a group renders post-order into two targets (two passes), and the second frame makes no
/// texture (the pool hands back what the first released). Mutation: the pool keyed by width only.
@Test @MainActor func nestedGroupsTakeTwoPassesAndASteadyFrameMakesNoTexture() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let renderer = try Renderer(device: device)
    var middle = Scene()
    middle.insert(rect(100, 100, 30, 30, blue, order: 0))
    middle.insert(groupQuad(59, 49, 92, 92, opacity: 0.5, order: 1), group: overlapScene())
    middle.finalize()
    var scene = Scene()
    scene.insert(background())
    scene.insert(groupQuad(50, 40, 120, 120, opacity: 0.5, order: 1), group: middle)
    scene.finalize()
    let size = Size(width: DevicePixels(200), height: DevicePixels(200))
    let first = try renderer.renderOffscreen(scene, size: size)
    #expect(renderer.lastGroupPasses == 2, "passes: \(renderer.lastGroupPasses)")
    #expect(renderer.lastGroupTexturesMade == 2, "first frame makes both targets: \(renderer.lastGroupTexturesMade)")
    // The red-only region: red 0.5 inside, 0.5 outside: (255, 191, 191).
    #expect(near(pixel(first, 70, 60), [255, 191, 191, 255], 2), "twice faded: \(pixel(first, 70, 60))")
    let second = try renderer.renderOffscreen(scene, size: size)
    #expect(renderer.lastGroupTexturesMade == 0, "steady: \(renderer.lastGroupTexturesMade)")
    #expect(first == second, "same pixels")
}

/// **GO-E.** A group whose target cannot be allocated draws nothing and is counted, the rest of the frame draws
/// (the `BB-I` precedent).
@Test @MainActor func aGroupWithoutATargetDrawsNothing() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let renderer = try Renderer(device: device)
    var scene = Scene()
    scene.insert(background())
    scene.insert(groupQuad(59, 49, 92, 92, opacity: 0.5, order: 1), group: overlapScene())
    scene.finalize()
    renderer.groupPoolFailsAllocation = true
    let pixels = try renderer.renderOffscreen(scene, size: Size(width: DevicePixels(200), height: DevicePixels(200)))
    #expect(near(pixel(pixels, 100, 90), [255, 255, 255, 255]), "background only: \(pixel(pixels, 100, 90))")
    #expect(renderer.lastGroupAllocationFailures == 1 && renderer.lastGroupPasses == 0)
}

/// **GO-D.** Scene structure: a group is its own run, counts in `isEmpty`, `highestLayer` and `clear()`.
@Test func aSceneHoldingOnlyAGroupIsNotEmptyAndClearsIt() {
    var scene = Scene()
    scene.insert(groupQuad(0, 0, 10, 10, opacity: 0.5, order: 0), group: overlapScene(), layer: 3)
    scene.insert(groupQuad(0, 0, 10, 10, opacity: 0.5, order: 1), group: overlapScene(), layer: 3)
    #expect(!scene.isEmpty && scene.highestLayer == 3)
    scene.finalize()
    #expect(scene.drawList.map(\.kind) == [.group, .group], "one group a run: \(scene.drawList)")
    #expect(scene.groups.map(\.texture) == [0, 1])
    scene.clear()
    #expect(scene.isEmpty && scene.groups.isEmpty && scene.groupScenes.isEmpty)
}

/// **GO-E.** Two groups of one width and two heights each keep a target of their own size across frames: the pool is
/// keyed by width and height. Mutation (finding of record 218: the nested test's targets differ in both, so it stayed
/// green): the pool keyed by width only — the second frame hands the tall group the short group's texture and its
/// bottom rows are lost.
@Test @MainActor func twoGroupsOfOneWidthKeepTheirOwnHeights() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let renderer = try Renderer(device: device)
    var tall = Scene()
    tall.insert(rect(20, 20, 92, 92, red, order: 0))
    tall.finalize()
    var short = Scene()
    short.insert(rect(120, 20, 92, 40, blue, order: 0))
    short.finalize()
    var scene = Scene()
    scene.insert(background())
    scene.insert(groupQuad(20, 20, 92, 92, opacity: 0.5, order: 1), group: tall)
    scene.insert(groupQuad(120, 20, 92, 40, opacity: 0.5, order: 2), group: short)
    scene.finalize()
    let size = Size(width: DevicePixels(240), height: DevicePixels(200))
    let first = try renderer.renderOffscreen(scene, size: size)
    let second = try renderer.renderOffscreen(scene, size: size)
    #expect(renderer.lastGroupTexturesMade == 0, "steady: \(renderer.lastGroupTexturesMade)")
    // Bottom rows of the tall group (y 100): only a 92-high target has them.
    #expect(near(pixel(first, 60, 105, width: 240), [255, 128, 128, 255]), "first: \(pixel(first, 60, 105, width: 240))")
    #expect(near(pixel(second, 60, 105, width: 240), [255, 128, 128, 255]), "second: \(pixel(second, 60, 105, width: 240))")
    #expect(first == second, "the same frame twice")
}
