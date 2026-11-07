import Testing
import Metal
import MetalUICore
import MetalUILayout
import MetalUIScene
@testable import MetalUI
@testable import MetalUIRender

// R4-5 PR C (ruling prefix `CM-`, record 220; probe `docs/probes/swiftui-clip-mask.swift`): a shape clip the per-primitive
// rounded-rect mask cannot express (an ellipse, a path, an even-odd or non-antialiased fill) paints into an offscreen group
// multiplied by the shape's coverage, and two crossing rounded clips intersect exactly (divergences 91 and 92 retired).
// Every test renders through the Metal renderer at 200 x 200, scale 1, over a transparent target, and reads the alpha channel
// (the coverage) or the colour at analytic pixels. The 100 x 60 box is centred: (50, 70)-(150, 130).

private func px(_ v: Float) -> Pixels { Pixels(v) }
private let pureBlue = Color(Hsla(h: 2.0 / 3.0, s: 1, l: 0.5, a: 1))
private let pureRed = Color(Hsla(h: 0, s: 1, l: 0.5, a: 1))

/// (r, g, b, a) of a BGRA offscreen render.
private func pixel(_ pixels: [UInt8], _ x: Int, _ y: Int, width: Int = 200) -> [Int] {
    let i = (y * width + x) * 4
    return [Int(pixels[i + 2]), Int(pixels[i + 1]), Int(pixels[i]), Int(pixels[i + 3])]
}

private func alpha(_ pixels: [UInt8], _ x: Int, _ y: Int) -> Int { pixel(pixels, x, y)[3] }

private let size200 = Size(width: DevicePixels(200), height: DevicePixels(200))

private struct Rendered {
    var pixels: [UInt8]
    var frame: Frame
    var scene: Scene
    var renderer: Renderer
}

/// `element` laid out and painted at 200 x 200 and drawn by `renderer` (a new one by default).
@MainActor private func render<E: Element>(_ element: E, renderer given: Renderer? = nil) throws -> Rendered {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let renderer = try given ?? Renderer(device: device)
    let frame = effectFrame(element)
    let scene = frame.finalizedScene()
    return Rendered(pixels: try renderer.renderOffscreen(scene, size: size200), frame: frame, scene: scene, renderer: renderer)
}

/// Two leaves (so a clip is a group and not the lone-rect shortcut): a red 50 x 60 beside a blue one.
@MainActor private func twoLeaves() -> some Element & ProposalElementGroup {
    HStack(spacing: px(0)) {
        pureRed.frame(width: px(50), height: px(60))
        pureBlue.frame(width: px(50), height: px(60))
    }
}

/// A 100 x 100 two-leaf block (red over blue halves), the unit the path and crossing tests clip.
@MainActor private func twoLeavesSquare(_ side: Float = 100) -> some Element & ProposalElementGroup {
    HStack(spacing: px(0)) {
        pureRed.frame(width: px(side / 2), height: px(side))
        pureBlue.frame(width: px(side / 2), height: px(side))
    }
}

/// The right triangle of `gxTriangle`, in the shape's own rect (`geometry(in:)` answers at the rect's origin).
private struct CMTriangle: Shape {
    func geometry(in rect: Bounds<Pixels>) -> ShapeGeometry {
        .path(gxTriangle(rect.size.width.value).offsetBy(dx: rect.origin.x, dy: rect.origin.y))
    }
}

/// `gxRing` (two same-direction squares: solid under nonzero, a ring under even-odd) as a nonzero shape.
private struct CMRing: Shape {
    func geometry(in rect: Bounds<Pixels>) -> ShapeGeometry {
        .path(gxRing.offsetBy(dx: rect.origin.x, dy: rect.origin.y))
    }
}

// MARK: - 1. an ellipse clip (CM0)

/// **1 (`CM-A`, probe `CM0`: ellipse exact, 0/255 edge gap).** A two-leaf block clipped to an ellipse draws as one group
/// through one mask pass: the box corner is clear, the interior is the content, and every pixel of the clipped block is within
/// 2/255 of the same block painted as `Ellipse().fill` (the analytic coverage of the existing ellipse primitive).
/// Mutation: the Metal mask pass skipped.
@Test @MainActor func anEllipseClipMasksItsCorners() throws {
    let r = try render(twoLeaves().clipShape(Ellipse()))
    #expect(alpha(r.pixels, 52, 72) == 0, "the box corner is clear: \(pixel(r.pixels, 52, 72))")
    #expect(pixel(r.pixels, 70, 100) == [255, 0, 0, 255], "left of the centre is red: \(pixel(r.pixels, 70, 100))")
    #expect(pixel(r.pixels, 130, 100) == [0, 0, 255, 255], "right is blue: \(pixel(r.pixels, 130, 100))")
    #expect(r.renderer.lastGroupPasses == 1 && r.renderer.lastMaskPasses == 1,
            "one group, one mask pass: \(r.renderer.lastGroupPasses) \(r.renderer.lastMaskPasses)")
    #expect(r.frame.groupsMasked == 1 && r.scene.groups.count == 1 && r.scene.groupMasks[0] != nil)
    // The edge row: the same ellipse drawn by the ellipse primitive, all red.
    let reference = try render(Ellipse().fill(pureRed).frame(width: px(100), height: px(60)), renderer: r.renderer)
    for y in [71, 80, 100, 129] {
        for x in 48...152 where pixel(reference.pixels, x, y)[0] == 255 || pixel(r.pixels, x, y)[3] > 0 {
            // Alpha only: the clipped block is two colours, the reference one.
            #expect(abs(alpha(r.pixels, x, y) - alpha(reference.pixels, x, y)) <= 2,
                    "edge coverage at (\(x), \(y)): \(alpha(r.pixels, x, y)) vs \(alpha(reference.pixels, x, y))")
        }
    }
}

// MARK: - 2 to 4. a path clip

/// **2 (`CM-A`, probe `CM1`).** A triangle path clip masks to its winding: a pixel inside the bounding box and outside the
/// triangle is clear, one inside is the content. Mutation: the path mask replaced by its bounding rect.
@Test @MainActor func aPathClipMasksToItsWinding() throws {
    let r = try render(twoLeavesSquare().clipShape(CMTriangle()))
    // The triangle fills the lower-left half of the (50, 50)-(150, 150) box.
    #expect(alpha(r.pixels, 130, 70) == 0, "inside the box, outside the triangle: \(pixel(r.pixels, 130, 70))")
    #expect(pixel(r.pixels, 70, 130) == [255, 0, 0, 255], "inside: \(pixel(r.pixels, 70, 130))")
    #expect(r.frame.groupsMasked == 1 && r.renderer.lastMaskPasses == 1)
}

/// **3 (`CM-A`, probe `CM1b`).** An even-odd path clip leaves its hole clear; the nonzero control fills it. Mutation: `style`
/// dropped (the nonzero reading).
@Test @MainActor func anEvenOddPathClipLeavesTheHoleClear() throws {
    let evenOdd = try render(twoLeavesSquare().clipShape(CMRing(), style: FillStyle(eoFill: true)))
    #expect(alpha(evenOdd.pixels, 100, 100) == 0, "the hole is clear: \(pixel(evenOdd.pixels, 100, 100))")
    #expect(pixel(evenOdd.pixels, 60, 60) == [255, 0, 0, 255], "the ring is the content: \(pixel(evenOdd.pixels, 60, 60))")
    let nonzero = try render(twoLeavesSquare().clipShape(CMRing()), renderer: evenOdd.renderer)
    #expect(alpha(nonzero.pixels, 100, 100) == 255, "nonzero fills the hole: \(pixel(nonzero.pixels, 100, 100))")
}

/// **4 (`CM-A`, probe `CM1c`).** `antialiased: false` gives hard edges: every alpha of the clipped block is 0 or 255, and the
/// anti-aliased control has intermediate values. Mutation: the antialiased flag ignored.
@Test @MainActor func aNonAntialiasedClipHasHardEdges() throws {
    let hard = try render(twoLeaves().clipShape(Ellipse(), style: FillStyle(antialiased: false)))
    let soft = try render(twoLeaves().clipShape(Ellipse()), renderer: hard.renderer)
    func middling(_ pixels: [UInt8]) -> Int { stride(from: 3, to: pixels.count, by: 4).filter { 0 < pixels[$0] && pixels[$0] < 255 }.count }
    #expect(middling(soft.pixels) > 0, "set up: the anti-aliased clip has edge pixels")
    #expect(middling(hard.pixels) == 0, "hard edges: \(middling(hard.pixels)) partial pixels")
    #expect(alpha(hard.pixels, 100, 100) == 255 && alpha(hard.pixels, 52, 72) == 0)
}

// MARK: - 5, 6. crossing rounded clips (CM2, divergence 92 retired)

/// The probe's CM2b: a 100 x 100 two-leaf block clipped to a radius-30 rounded rectangle, placed by padding at (50, 50) inside a
/// 100 x 100 frame clipped the same way. Window coordinates: the outer box is (50, 50)-(150, 150), the inner (100, 100)-(200, 200),
/// no effect between, so the inner clip is pushed through `pushClip`.
@MainActor private func crossingByPadding() -> some Element & ProposalElementGroup {
    twoLeavesSquare().clipShape(RoundedRectangle(cornerRadius: px(30)))
        .padding(Edges(top: px(50), right: px(0), bottom: px(0), left: px(50)))
        .frame(width: px(100), height: px(100), alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: px(30)))
}

/// The probe's CM2: the same with an `.offset` between the clips, so the inner clip is pushed at a flattening effect's entry.
@MainActor private func crossingByOffset() -> some Element & ProposalElementGroup {
    // Four leaves, two of them inside the overlap, so a group per leaf would show as two groups.
    HStack(spacing: px(0)) {
        pureRed.frame(width: px(25), height: px(100))
        pureBlue.frame(width: px(25), height: px(100))
        pureRed.frame(width: px(25), height: px(100))
        pureBlue.frame(width: px(25), height: px(100))
    }.clipShape(RoundedRectangle(cornerRadius: px(30)))
        .offset(x: px(50), y: px(50))
        .frame(width: px(100), height: px(100), alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: px(30)))
}

/// **5 (`CM-B`, probes `CM2b`/`CM2c`: exact in SwiftUI, divergence 92 retired).** Two crossing rounded clips intersect exactly:
/// the inner block's top-left corner and the outer's bottom-right corner are both clear, where the square box (the old
/// answer) drew them; the overlap is the content. Mutations: **M1** `clipsCross` always false (the square box returns); **M2**
/// the crossing mask rect's `contentMask` set to the whole target (only the inner rounding survives).
@Test @MainActor func twoCrossingRoundedClipsIntersectExactly() throws {
    let r = try render(crossingByPadding())
    #expect(alpha(r.pixels, 102, 102) == 0, "the inner's own corner is clear: \(pixel(r.pixels, 102, 102))")
    #expect(alpha(r.pixels, 147, 147) == 0, "the outer's corner is clear: \(pixel(r.pixels, 147, 147))")
    #expect(alpha(r.pixels, 125, 125) == 255, "the overlap draws: \(pixel(r.pixels, 125, 125))")
    #expect(r.frame.groupsMasked == 1, "a crossing is one masked group for both leaves: \(r.frame.groupsMasked)")
    #expect(Frame.clipsCross(Bounds(origin: Point(x: px(0), y: px(0)), size: Size(width: px(100), height: px(60))),
                             radii: Corners(all: px(20)),
                             Bounds(origin: Point(x: px(50), y: px(0)), size: Size(width: px(100), height: px(60))),
                             radii: Corners(all: px(20))), "the 2.21 pair crosses")
    // The pushed clip itself is still the square box (hit testing and every primitive's own mask are unchanged).
    let box = Frame.intersect(Bounds(origin: Point(x: px(0), y: px(0)), size: Size(width: px(100), height: px(60))),
                              radii: Corners(all: px(20)),
                              Bounds(origin: Point(x: px(50), y: px(0)), size: Size(width: px(100), height: px(60))),
                              radii: Corners(all: px(20)))
    #expect(box.radii == Corners(all: px(0)), "the pushed clip is the square box: \(box)")
}

/// **6 (`CM-B`, probe `CM2`).** The same crossing with an offset between the clips, which reaches `cutToEntryClip`: exact as
/// well. Mutation: the `cutToEntryClip` crossing arm removed (the entry clip cuts to the square box).
@Test @MainActor func crossingClipsAcrossAnOffsetIntersectExactly() throws {
    let r = try render(crossingByOffset())
    #expect(alpha(r.pixels, 102, 102) == 0, "the inner's corner is clear: \(pixel(r.pixels, 102, 102))")
    #expect(alpha(r.pixels, 147, 147) == 0, "the outer's corner is clear: \(pixel(r.pixels, 147, 147))")
    #expect(alpha(r.pixels, 125, 125) == 255, "the overlap draws: \(pixel(r.pixels, 125, 125))")
    // One group per leaf: every fill is its own leaf through `processScopes`, so the scope's crossing token merges only the
    // primitives of one leaf array (a text draw's glyphs). Carried in record 220 section 4; each group's box is its leaf's.
    #expect(r.frame.groupsMasked == 2, "a masked group per leaf in the overlap: \(r.frame.groupsMasked)")
}

/// **6b (`CM-B`).** A crossing pair inside an offset moves with it: the mask's `contentMask` (the outer clip) was pushed inside
/// the offset, so the offset maps it (the mark's `innerMask` flag set by `processScopes`). Shifted 20 right, the inner corner and
/// the outer corner are clear at their shifted places and a point inside the shifted overlap but outside the unshifted outer clip
/// draws. Mutation: `processScopes` does not flag the marks' masks.
@Test @MainActor func aCrossingPairInsideAnOffsetMovesWithIt() throws {
    let r = try render(crossingByPadding().offset(x: px(20), y: px(0)))
    #expect(alpha(r.pixels, 122, 102) == 0, "the inner's corner, shifted: \(pixel(r.pixels, 122, 102))")
    #expect(alpha(r.pixels, 167, 147) == 0, "the outer's corner, shifted: \(pixel(r.pixels, 167, 147))")
    #expect(alpha(r.pixels, 165, 125) == 255, "inside the shifted overlap, outside the unshifted outer: \(pixel(r.pixels, 165, 125))")
}

/// **5b (`CM-B`).** Two rounded clips whose square box never reaches a corner cut are exact as they are and take no group: a
/// 140 x 30 rounded strip crossing a 100 x 100 rounded panel from side to side, clear of both of its corners and of the panel's.
/// The control, one end of the strip inside the panel, does take one. Mutation: the corner-cut test removed (`clipsCross` is
/// the bare fallback test: the strip becomes a group).
@Test @MainActor func aPairWhoseBoxMissesEveryCornerCutTakesNoGroup() throws {
    func bounds(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> Bounds<Pixels> {
        Bounds(origin: Point(x: px(x), y: px(y)), size: Size(width: px(w), height: px(h)))
    }
    let panel = bounds(50, 50, 100, 100), r20 = Corners(all: px(20)), r6 = Corners(all: px(6))
    #expect(!Frame.clipsCross(panel, radii: r20, bounds(30, 85, 140, 30), radii: r6), "the strip spans the panel clear of the corners")
    #expect(Frame.clipsCross(panel, radii: r20, bounds(60, 85, 140, 30), radii: r6), "one end inside: the strip's corner is inside the panel")
    let strip = effectFrame(pureRed.frame(width: px(140), height: px(30)).clipShape(RoundedRectangle(cornerRadius: px(6)))
        .frame(width: px(100), height: px(100)).clipShape(RoundedRectangle(cornerRadius: px(20))))
    #expect(strip.groupsMasked == 0 && strip.maskScopesPushed == 0, "no group: \(strip.groupsMasked) \(strip.maskScopesPushed)")
}

// MARK: - 7. what takes no group

/// **7 (`CM-A`, probe `CM7`).** A circle, a capsule, a rounded rectangle and a capsule-then-circle (C6) are the per-primitive
/// rounded mask: no mask scope, no group. Mutation: `paintWithMask` opened for every `clipShape`.
@Test @MainActor func aCircleCapsuleOrContainedClipTakesNoGroup() throws {
    let frames: [(String, Frame)] = [
        ("circle", effectFrame(twoLeaves().clipShape(Circle()))),
        ("capsule", effectFrame(twoLeaves().clipShape(Capsule()))),
        ("rounded", effectFrame(twoLeaves().clipShape(RoundedRectangle(cornerRadius: px(12))))),
        ("c6", effectFrame(twoLeaves().clipShape(Circle()).clipShape(Capsule()))),
    ]
    for (name, frame) in frames {
        let scene = frame.finalizedScene()
        #expect(frame.groupsMasked == 0 && frame.maskScopesPushed == 0 && scene.groups.isEmpty,
                "\(name): \(frame.groupsMasked) groups, \(frame.maskScopesPushed) scopes")
    }
}

// MARK: - 8, 9. the mask follows the content

/// **8 (`CM-A`, probe `CM4`).** An ellipse clip under a rotation turns its mask with the content: a 100 x 60 ellipse turned a
/// quarter is 60 x 100, so a pixel above the centre is inside and one to the left outside, the reverse of the unrotated
/// ellipse. Mutation: `RenderEffect.apply`'s non-flattening branch skips the marks' masks.
@Test @MainActor func anEllipseClipUnderARotationTurnsItsMask() throws {
    let r = try render(twoLeaves().clipShape(Ellipse()).rotationEffect(.degrees(90)))
    #expect(alpha(r.pixels, 100, 56) == 255, "above the centre, inside the turned ellipse: \(pixel(r.pixels, 100, 56))")
    #expect(alpha(r.pixels, 62, 100) == 0, "left of the centre, outside it: \(pixel(r.pixels, 62, 100))")
    #expect(r.renderer.lastMaskPasses == 1)
}

/// **9 (`CM-A`).** An ellipse clip inside an offset (a flattening effect) moves its mask: the 100 x 60 ellipse's box moved
/// (30, 20) clears the old box corner and draws at the new centre. Mutation: the flattening branch skips the masks.
@Test @MainActor func anEllipseClipInsideAnOffsetMovesItsMask() throws {
    let r = try render(twoLeaves().clipShape(Ellipse()).offset(x: px(30), y: px(20)))
    // The ellipse is now centred at (130, 120), box (80, 90)-(180, 150).
    #expect(pixel(r.pixels, 100, 120)[3] == 255, "inside the moved ellipse: \(pixel(r.pixels, 100, 120))")
    #expect(alpha(r.pixels, 82, 92) == 0, "the moved box's corner is clear: \(pixel(r.pixels, 82, 92))")
    #expect(alpha(r.pixels, 175, 145) == 0, "outside the moved ellipse's lower right: \(pixel(r.pixels, 175, 145))")
    #expect(alpha(r.pixels, 150, 120) == 255, "the moved ellipse reaches past the old box: \(pixel(r.pixels, 150, 120))")
}

// MARK: - 10, 11. shadow and blur (CM3, CM5)

/// **10 (`CM-A`, probe `CM3`).** The shadow of an ellipse-clipped view is the ellipse's: a pixel past the ellipse's right tip,
/// inside the shifted ellipse, is inked, and the box corner plus the offset, which a square silhouette would ink, is clear.
/// Mutation: `liftSharedMarks` lifts masked marks (the shadow is cast by the unmasked block).
@Test @MainActor func aShadowOfAnEllipseClipIsElliptical() throws {
    let r = try render(twoLeaves().clipShape(Ellipse()).shadow(color: .textPrimary, radius: px(0), x: px(10), y: px(10)))
    // Shifted ellipse: centre (110, 110), radii (50, 30). (155, 110) is inside it, outside the content ellipse.
    #expect(alpha(r.pixels, 155, 110) > 200, "the elliptical shadow: \(pixel(r.pixels, 155, 110))")
    #expect(alpha(r.pixels, 158, 138) == 0, "a square silhouette's corner stays clear: \(pixel(r.pixels, 158, 138))")
    #expect(r.frame.filterGroups >= 1, "the shadow went through a filtered group: \(r.frame.filterGroups)")
}

/// **11 (`CM-A`, probe `CM5`).** `.blur(6).clipShape(Ellipse())` cuts the blurred content at a sharp elliptical edge (the
/// alpha steps across the tip), `.clipShape(Ellipse()).blur(6)` blurs the edge (spill outside the tip). Mutation: the same lift
/// in the blur arm.
@Test @MainActor func aBlurInsideAnEllipseClipIsCutSharp() throws {
    let sharp = try render(twoLeaves().blur(radius: px(6)).clipShape(Ellipse()))
    let soft = try render(twoLeaves().clipShape(Ellipse()).blur(radius: px(6)), renderer: sharp.renderer)
    #expect(alpha(sharp.pixels, 48, 100) == 0 && alpha(sharp.pixels, 52, 100) > 60,
            "a step at the tip: \(alpha(sharp.pixels, 48, 100)) then \(alpha(sharp.pixels, 52, 100))")
    #expect(alpha(soft.pixels, 46, 100) > 10, "the blurred edge spills past the tip: \(alpha(soft.pixels, 46, 100))")
}

// MARK: - 12 to 14. what the group cannot hold

/// **12 (divergence 224).** A material inside a shape clip keeps its live backdrop: no group, the content under the bounding
/// clip, counted. Mutation: the backdrop guard removed (the backdrop is masked into a group).
@Test @MainActor func aMaterialInsideAShapeClipClipsToItsBox() throws {
    let frame = effectFrame(ZStack {
        pureRed.frame(width: px(100), height: px(60))
        Color.clear.frame(width: px(40), height: px(40)).background(.regularMaterial)
    }.clipShape(Ellipse()))
    let scene = frame.finalizedScene()
    #expect(frame.masksFlattenedBackdrop == 1, "counted: \(frame.masksFlattenedBackdrop)")
    #expect(scene.groups.isEmpty && scene.backdrops.count == 1, "no group, the backdrop stays: \(scene.groups.count) \(scene.backdrops.count)")
}

/// **13.** A masked group whose box exceeds 8192 is drawn per primitive under the bounding clip, counted. Mutation: the 8192
/// check removed.
@Test @MainActor func anOversizeMaskedGroupClipsToItsBox() throws {
    let frame = effectFrame(VStack(spacing: px(0)) {
        pureRed.frame(width: px(9000), height: px(10))
        pureBlue.frame(width: px(9000), height: px(10))
    }.clipShape(Ellipse()), side: 10_000)
    let scene = frame.finalizedScene()
    #expect(frame.masksFlattenedOversize == 1 && scene.groups.isEmpty, "flattened: \(frame.masksFlattenedOversize)")
    #expect(scene.rects.count == 2, "both drawn per primitive: \(scene.rects.count)")
}

/// **14.** A `Deferred` inside an ellipse clip is not masked: it paints at the root, outside the group. Mutation: no barrier for
/// a mask scope.
@Test @MainActor func aDeferredInsideAnEllipseClipIsNotMasked() throws {
    let frame = effectFrame(ZStack {
        Column {
            pureRed.frame(width: px(60), height: px(20))
            pureBlue.frame(width: px(60), height: px(20))
            Deferred { Color(.accent).frame(width: px(50), height: px(30)) }
        }.frame(width: px(160), height: px(100)).clipShape(Ellipse())
    })
    let scene = frame.finalizedScene()
    try #require(scene.groups.count == 1, "the in-flow bars group: \(scene.groups.count)")
    #expect(scene.groupScenes[0].rects.count == 2, "two bars in the group: \(scene.groupScenes[0].rects.count)")
    #expect(scene.rects.contains { $0.bounds.size.width == 50 && $0.bounds.size.height == 30 }, "the presentation is outside the group")
}

// MARK: - 15, 16. the pass

/// **15.** A steady masked frame makes no texture: the second frame runs the same one group pass and one mask pass, the pool
/// hands back what the first released, and a path mask makes no raster. Mutation: the mask scratch not released.
@Test @MainActor func aSteadyMaskedFrameMakesNoTexture() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let renderer = try Renderer(device: device)
    let h = TransitionHarness()
    func draw(_ t: Double) throws -> [UInt8] {
        let frame = h.frame(t, nil, twoLeavesSquare().clipShape(CMTriangle()), side: 200)
        return try renderer.renderOffscreen(frame.finalizedScene(), size: size200)
    }
    let first = try draw(0)
    #expect(renderer.lastGroupPasses == 1 && renderer.lastMaskPasses == 1)
    #expect(renderer.lastGroupTexturesMade == 2, "the first frame makes the target and the mask scratch: \(renderer.lastGroupTexturesMade)")
    try #require(h.store.rasters.lastTexturesMade > 0, "set up: the first frame rastered the path mask")
    let second = try draw(1)
    #expect(renderer.lastGroupPasses == 1 && renderer.lastMaskPasses == 1, "same passes: \(renderer.lastGroupPasses) \(renderer.lastMaskPasses)")
    #expect(renderer.lastGroupTexturesMade == 0, "steady: \(renderer.lastGroupTexturesMade) textures")
    #expect(h.store.rasters.lastTexturesMade == 0, "the path mask is a cache hit: \(h.store.rasters.lastTexturesMade)")
    #expect(first == second, "the same pixels")
}

/// **16.** A mask target that cannot be allocated draws the group unmasked, by name: the bounding clip still cuts it, the box
/// corner shows, and the failure is counted. Mutation: the fallback draws nothing.
@Test @MainActor func aMaskAllocationFailureDrawsTheGroupUnmaskedByName() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let renderer = try Renderer(device: device)
    renderer.maskPoolFailsAllocation = true
    let r = try render(twoLeaves().clipShape(Ellipse()), renderer: renderer)
    #expect(r.renderer.lastMaskAllocationFailures == 1 && r.renderer.lastMaskPasses == 0)
    #expect(pixel(r.pixels, 52, 72) == [255, 0, 0, 255], "unmasked: the corner of the box shows: \(pixel(r.pixels, 52, 72))")
}

// MARK: - 18. the lone fill

/// **18.** A lone fill clipped to an ellipse is an ellipse rect: no group, one rect of the ellipse shape, and the pixels equal
/// the two-leaf group's. Mutation: the shortcut's containment condition flipped.
@Test @MainActor func aLoneFillClippedToAnEllipseIsAnEllipseRect() throws {
    let lone = try render(pureRed.frame(width: px(100), height: px(60)).clipShape(Ellipse()))
    #expect(lone.frame.groupsMasked == 0 && lone.frame.masksBakedToEllipse == 1 && lone.scene.groups.isEmpty,
            "baked: \(lone.frame.groupsMasked) groups, \(lone.frame.masksBakedToEllipse) baked")
    try #require(lone.scene.rects.count == 1, "\(lone.scene.rects.count) rects")
    #expect(lone.scene.rects[0].shapeKind == PrimitiveShape.ellipse.rawValue, "an ellipse rect")
    let pair = try render(HStack(spacing: px(0)) {
        pureRed.frame(width: px(50), height: px(60))
        pureRed.frame(width: px(50), height: px(60))
    }.clipShape(Ellipse()), renderer: lone.renderer)
    var worst = 0
    for i in 0..<(200 * 200 * 4) { worst = max(worst, abs(Int(lone.pixels[i]) - Int(pair.pixels[i]))) }
    #expect(worst <= 2, "the same pixels as the group, within 2/255: \(worst)")
    // A leaf larger than the clip box holds the whole ellipse: the shortcut applies. One smaller does not: it is a group.
    let larger = effectFrame(pureRed.frame(width: px(140), height: px(100)).frame(width: px(100), height: px(60)).clipShape(Ellipse()))
    #expect(larger.masksBakedToEllipse == 1 && larger.groupsMasked == 0, "larger: \(larger.masksBakedToEllipse) baked, \(larger.groupsMasked) groups")
    let smaller = effectFrame(pureRed.frame(width: px(60), height: px(30)).frame(width: px(100), height: px(60)).clipShape(Ellipse()))
    _ = smaller.finalizedScene()
    #expect(smaller.masksBakedToEllipse == 0 && smaller.groupsMasked == 1, "smaller: \(smaller.masksBakedToEllipse) baked, \(smaller.groupsMasked) groups")
}

// MARK: - 20. a ghost

/// An unannotated `if` unit holding a two-leaf ellipse clip: its removal fades by the default ghost (`XF-H`).
@MainActor private func clippedUnit(_ shown: Bool) -> some Element {
    Column {
        Stack {
            Box().frame(width: px(200), height: px(100))
            if shown { twoLeaves().clipShape(Ellipse()) }
        }
    }
}

/// **20 (`CM-A`).** A removed ellipse clip fades its ghost still masked: the previous scene's group quad is expanded back into
/// captured primitives under a masked mark, and at half way the scene holds one masked group. Mutation: `capturedGroup`'s
/// masked arm drops the mask.
@Test @MainActor func aRemovedEllipseClipFadesItsGhostMasked() throws {
    let h = TransitionHarness()
    let rest = h.frame(0, nil, clippedUnit(true)).finalizedScene()
    try #require(rest.groups.count == 1 && rest.groupMasks[0] != nil, "set up: the unit is a masked group at rest")
    h.frame(0, Animation.linear(duration: 1), clippedUnit(false))
    let mid = h.frame(0.5, nil, clippedUnit(false)).finalizedScene()
    try #require(mid.groups.count == 1, "the ghost is one group: \(mid.groups.count)")
    #expect(mid.groupMasks[0] != nil, "still masked")
    #expect(mid.groupScenes[0].rects.allSatisfy { $0.background.a < 1 }, "faded by its leaves (an opacity outside a clip is per leaf)")
}

// MARK: - 21. hit testing

/// **21 (`CM-E`, `TE-AQ` item 4).** An ellipse clip still clips hitboxes to the bounding rect: the tapped element's hitbox is the
/// whole 100 x 60 box and a point at the box corner finds it. Mutation: the clip routes prepaint through the mask (the hitbox
/// shrinks).
@Test @MainActor func anEllipseClipStillClipsHitboxesToItsBoundingRect() throws {
    let frame = effectFrame(pureRed.frame(width: px(100), height: px(60)).onTapGesture {}.clipShape(Ellipse()))
    let boxes = frame.hitboxes.filter { $0.handlers.gestures.count > 0 }
    try #require(boxes.count == 1, "\(boxes.count) tappable hitboxes")
    #expect(boxes[0].bounds == Bounds(origin: Point(x: px(50), y: px(70)), size: Size(width: px(100), height: px(60))),
            "the bounding rect: \(boxes[0].bounds)")
    #expect(frame.topmostHitbox(at: Point(x: px(52), y: px(72))) != nil, "the box corner hits")
}

// MARK: - 22. an opacity outside a clip (CM6)

/// **22 (`CM-C`, probe `CM6`: per leaf).** An opacity outside an ellipse clip fades each leaf, as an opacity on a container
/// does: the overlap of two clipped leaves reads the same as the unclipped pair under the same opacity, and the masked group
/// is drawn at opacity 1. Mutation: the mask scope composites the opacity (mark alpha = entry opacity), the other branch.
@Test @MainActor func anOpacityOutsideAShapeClipIsPerLeaf() throws {
    func pair() -> some Element & ProposalElementGroup {
        ZStack(alignment: .topLeading) {
            pureRed.frame(width: px(60), height: px(60))
            pureBlue.frame(width: px(60), height: px(60)).offset(x: px(20), y: px(20))
        }
    }
    let clipped = try render(pair().clipShape(Ellipse()).opacity(0.5))
    let plain = try render(pair().opacity(0.5), renderer: clipped.renderer)
    try #require(clipped.scene.groups.count == 1, "set up: \(clipped.scene.groups.count) groups")
    #expect(clipped.scene.groups[0].opacity == 1, "the group is not faded: \(clipped.scene.groups[0].opacity)")
    // (100, 100) is in the overlap and inside the circle inscribed in the 60 x 60 box at (70, 70).
    let a = pixel(clipped.pixels, 100, 100), b = pixel(plain.pixels, 100, 100)
    #expect(zip(a, b).allSatisfy { abs($0 - $1) <= 1 }, "per leaf, like the plain opacity: \(a) vs \(b)")
}
