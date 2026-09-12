import Testing
import Metal
import simd
import MetalUICore
import MetalUIShaderTypes
@testable import MetalUIRender

private func bgra(_ pixels: [UInt8], _ x: Int, _ y: Int, width: Int) -> (UInt8, UInt8, UInt8, UInt8) {
    let i = (y * width + x) * 4
    return (pixels[i + 2], pixels[i + 1], pixels[i], pixels[i + 3])  // r, g, b, a
}

/// The single most load-bearing constant in this repo.
///
/// Spec 7.8 composites in gamma-encoded sRGB. `bgra8Unorm` blends on the stored
/// gamma-encoded values; an `_sRGB` target makes the hardware decode to linear
/// before blending and re-encode after — which is linear compositing, the exact
/// opposite of the decision. The damage would surface a milestone later as wrong
/// text rendering (thin, washed light-on-dark; heavy dark-on-light).
///
/// **No *other* test in this repo catches a flip**, and the word "other" is
/// load-bearing — a rewrite of this comment dropped it and inverted the sentence
/// into "this test alone cannot catch a flip", which is plainly false, since the
/// line below names the constant. M0's original was precise; this restores it.
///
/// The distinction it draws is the one that matters: `renderOffscreen` reads the
/// same constant, so the offscreen target flips with it and every geometry and
/// colour assertion in this file passes either way. An assertion that names a
/// constant pins its *spelling*. `compositingIsGammaEncodedNotLinear` at the
/// foot of this file is the guard on the **behaviour** — it reads back a
/// translucent-over-opaque composite and separates 128 from 188.
@Test @MainActor func drawableFormatIsGammaEncodedNotSRGB() {
    #expect(Renderer.pixelFormat == .bgra8Unorm)
}

@Test @MainActor func rendererDrawsAFilledRectWhereExpected() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let renderer = try Renderer(device: device)

    var scene = Scene()
    scene.insert(MUIRect(
        bounds: Bounds(origin: Point(x: ScaledPixels(20), y: ScaledPixels(20)),
                       size: Size(width: ScaledPixels(60), height: ScaledPixels(60))),
        contentMask: Bounds(origin: Point(x: ScaledPixels(0), y: ScaledPixels(0)),
                            size: Size(width: ScaledPixels(100), height: ScaledPixels(100))),
        background: .white,
        borderColor: .white,
        cornerRadii: Corners(all: ScaledPixels(0)),
        borderWidths: Edges(all: ScaledPixels(0)),
        order: 0))
    scene.finalize()

    let pixels = try renderer.renderOffscreen(
        scene, size: Size(width: DevicePixels(100), height: DevicePixels(100)))

    let inside = bgra(pixels, 50, 50, width: 100)
    #expect(inside.0 > 200 && inside.1 > 200 && inside.2 > 200)   // white fill
    #expect(inside.3 > 200)                                        // opaque

    let outside = bgra(pixels, 5, 5, width: 100)
    #expect(outside.3 < 40)                                        // cleared, transparent

    // Probes straddling every edge. Centre-only probes cannot tell a correctly
    // placed rect from a displaced or resized one: both of those mutations pass
    // the two checks above. These pin origin and size on both axes.
    // The rect spans x and y in [20, 80); pixel centres sit at +0.5.
    #expect(bgra(pixels, 21, 50, width: 100).3 > 200)   // just inside left
    #expect(bgra(pixels, 18, 50, width: 100).3 < 40)    // just outside left
    #expect(bgra(pixels, 78, 50, width: 100).3 > 200)   // just inside right
    #expect(bgra(pixels, 82, 50, width: 100).3 < 40)    // just outside right
    #expect(bgra(pixels, 50, 21, width: 100).3 > 200)   // just inside top
    #expect(bgra(pixels, 50, 18, width: 100).3 < 40)    // just outside top
    #expect(bgra(pixels, 50, 78, width: 100).3 > 200)   // just inside bottom
    #expect(bgra(pixels, 50, 82, width: 100).3 < 40)    // just outside bottom
}

/// White and black are symmetric under a red/blue swap, so the rest of this
/// file would pass with the BGRA readback or `hsla_to_srgba` channels
/// transposed. This asserts an asymmetric colour, channel by channel.
@Test @MainActor func channelsAreNotTransposed() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let renderer = try Renderer(device: device)

    func fill(_ color: Hsla) throws -> (UInt8, UInt8, UInt8, UInt8) {
        var scene = Scene()
        scene.insert(MUIRect(
            bounds: Bounds(origin: Point(x: ScaledPixels(0), y: ScaledPixels(0)),
                           size: Size(width: ScaledPixels(100), height: ScaledPixels(100))),
            contentMask: Bounds(origin: Point(x: ScaledPixels(0), y: ScaledPixels(0)),
                                size: Size(width: ScaledPixels(100), height: ScaledPixels(100))),
            background: color, borderColor: color,
            cornerRadii: Corners(all: ScaledPixels(0)),
            borderWidths: Edges(all: ScaledPixels(0)),
            order: 0))
        scene.finalize()
        let pixels = try renderer.renderOffscreen(
            scene, size: Size(width: DevicePixels(100), height: DevicePixels(100)))
        return bgra(pixels, 50, 50, width: 100)
    }

    let red = try fill(.rgb(0xFF0000))
    #expect(red.0 > 200)   // r
    #expect(red.1 < 40)    // g
    #expect(red.2 < 40)    // b
    #expect(red.3 > 200)

    let blue = try fill(.rgb(0x0000FF))
    #expect(blue.0 < 40)   // r
    #expect(blue.1 < 40)   // g
    #expect(blue.2 > 200)  // b
    #expect(blue.3 > 200)
}

/// The `projection` on `SurfaceView` exists so a stereo backend can hand the
/// renderer per-eye matrices (spec 3.2). If the shader ignored it, both eyes
/// would render identically -- so this asserts the pixels actually move.
@Test @MainActor func projectionMatrixMovesTheRenderedRect() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let renderer = try Renderer(device: device)

    var scene = Scene()
    scene.insert(MUIRect(
        bounds: Bounds(origin: Point(x: ScaledPixels(20), y: ScaledPixels(20)),
                       size: Size(width: ScaledPixels(60), height: ScaledPixels(60))),
        contentMask: Bounds(origin: Point(x: ScaledPixels(0), y: ScaledPixels(0)),
                            size: Size(width: ScaledPixels(100), height: ScaledPixels(100))),
        background: .white, borderColor: .white,
        cornerRadii: Corners(all: ScaledPixels(0)),
        borderWidths: Edges(all: ScaledPixels(0)),
        order: 0))
    scene.finalize()

    let size = Size(width: DevicePixels(100), height: DevicePixels(100))

    // Identity: the rect covers x in [20, 80).
    let identity = try renderer.renderOffscreen(scene, size: size)
    #expect(bgra(identity, 30, 50, width: 100).3 > 200)
    #expect(bgra(identity, 90, 50, width: 100).3 < 40)

    // NDC spans [-1, 1] across 100px, so +0.4 in x translates by +20px.
    let translate = simd_float4x4(columns: (SIMD4<Float>(1, 0, 0, 0),
                                            SIMD4<Float>(0, 1, 0, 0),
                                            SIMD4<Float>(0, 0, 1, 0),
                                            SIMD4<Float>(0.4, 0, 0, 1)))
    let shifted = try renderer.renderOffscreen(scene, size: size, projection: translate)

    // Both probes flip: the rect now covers x in [40, 100).
    #expect(bgra(shifted, 30, 50, width: 100).3 < 40)
    #expect(bgra(shifted, 90, 50, width: 100).3 > 200)
}

@Test @MainActor func cornerRadiusRoundsTheCorners() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let renderer = try Renderer(device: device)

    var scene = Scene()
    scene.insert(MUIRect(
        bounds: Bounds(origin: Point(x: ScaledPixels(0), y: ScaledPixels(0)),
                       size: Size(width: ScaledPixels(100), height: ScaledPixels(100))),
        contentMask: Bounds(origin: Point(x: ScaledPixels(0), y: ScaledPixels(0)),
                            size: Size(width: ScaledPixels(100), height: ScaledPixels(100))),
        background: .white, borderColor: .white,
        cornerRadii: Corners(all: ScaledPixels(30)),
        borderWidths: Edges(all: ScaledPixels(0)),
        order: 0))
    scene.finalize()

    let pixels = try renderer.renderOffscreen(
        scene, size: Size(width: DevicePixels(100), height: DevicePixels(100)))

    // The extreme corner is outside a 30pt radius; the centre is inside.
    #expect(bgra(pixels, 1, 1, width: 100).3 < 40)
    #expect(bgra(pixels, 50, 50, width: 100).3 > 200)
}

/// A zero-width border's COLOUR must not change a single pixel.
///
/// **This is the only shape that can see `rect_fragment`'s double-application
/// of edge coverage, and the reason no existing test sees it is that both
/// pixel tests above set `borderColor` equal to the background** —
/// `cornerRadiusRoundsTheCorners` uses `.white`/`.white` and
/// `aRectIsDrawnWhereItIntersectsItsMask` uses `color`/`color` — under which
/// `mix(borderColor, background, innerAlpha)` is a no-op for every value of
/// `innerAlpha`. `cornerRadiusRoundsTheCorners` additionally probes only (1,1)
/// and (50,50), which are fully outside and fully inside the shape; no
/// partial-coverage fragment exists at either.
///
/// With `borderWidths` all zero, `innerAlpha` is bit-identical to `outerAlpha`,
/// so the `borderColor == background` arm yields `(C, 1)` and composites once,
/// while the `.transparent` arm yields `(C*c, c)` and is then premultiplied and
/// scaled by `outerAlpha` a second time — emitting `C*c³` against an alpha of
/// `c²`. RGB therefore decays faster than alpha and the corner loses *colour*,
/// not merely opacity: a grey fringe on a light ground.
///
/// **The two arms are measured to disagree before the fix** (the point of
/// shape 15), which is why this asserts agreement between two rendered arms
/// rather than against a hardcoded antialiasing constant. `> 20 && < 235`-style
/// bands, as used by the clip-edge test, are far too loose to separate the two.
@Test @MainActor func aZeroWidthBordersColorChangesNoPixel() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let renderer = try Renderer(device: device)

    func render(borderColor: Hsla) throws -> [UInt8] {
        let full = Bounds(origin: Point(x: ScaledPixels(0), y: ScaledPixels(0)),
                          size: Size(width: ScaledPixels(100), height: ScaledPixels(100)))
        var scene = Scene()
        scene.insert(MUIRect(
            bounds: full, contentMask: full,
            background: .white, borderColor: borderColor,
            cornerRadii: Corners(all: ScaledPixels(30)),
            borderWidths: Edges(all: ScaledPixels(0)),
            order: 0))
        scene.finalize()
        return try renderer.renderOffscreen(
            scene, size: Size(width: DevicePixels(100), height: DevicePixels(100)))
    }

    let transparentBorder = try render(borderColor: .transparent)
    let matchingBorder    = try render(borderColor: .white)

    // Walk the top-left corner's diagonal, which is where partial coverage
    // lives for a 30pt radius. Require that at least one probe is genuinely
    // partial, or the comparison proves nothing.
    var sawPartial = false
    for d in 4...20 {
        let a = bgra(transparentBorder, d, d, width: 100)
        let b = bgra(matchingBorder, d, d, width: 100)
        if b.3 > 10 && b.3 < 245 { sawPartial = true }
        #expect(Int(a.3) == Int(b.3),
                "alpha differs at (\(d),\(d)): transparent-border \(a.3) vs matching-border \(b.3)")
        #expect(Int(a.0) == Int(b.0),
                "red differs at (\(d),\(d)): transparent-border \(a.0) vs matching-border \(b.0)")
    }
    #expect(sawPartial, "no partially covered pixel on the probed diagonal — the test proves nothing")
}

@Test @MainActor func borderPaintsADistinctColorAtTheEdge() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let renderer = try Renderer(device: device)

    var scene = Scene()
    scene.insert(MUIRect(
        bounds: Bounds(origin: Point(x: ScaledPixels(0), y: ScaledPixels(0)),
                       size: Size(width: ScaledPixels(100), height: ScaledPixels(100))),
        contentMask: Bounds(origin: Point(x: ScaledPixels(0), y: ScaledPixels(0)),
                            size: Size(width: ScaledPixels(100), height: ScaledPixels(100))),
        background: .black,
        borderColor: .white,
        cornerRadii: Corners(all: ScaledPixels(0)),
        borderWidths: Edges(all: ScaledPixels(10)),
        order: 0))
    scene.finalize()

    let pixels = try renderer.renderOffscreen(
        scene, size: Size(width: DevicePixels(100), height: DevicePixels(100)))

    let onBorder = bgra(pixels, 5, 50, width: 100)
    #expect(onBorder.0 > 200)                       // white border

    let inField = bgra(pixels, 50, 50, width: 100)
    #expect(inField.0 < 40 && inField.3 > 200)      // black fill, still opaque
}

/// A full covering rect, for scenes that only care about what colour arrives.
@MainActor
private func coverRect(_ color: Hsla, side: Float) -> MUIRect {
    let full = Bounds(origin: Point(x: ScaledPixels(0), y: ScaledPixels(0)),
                      size: Size(width: ScaledPixels(side), height: ScaledPixels(side)))
    return MUIRect(bounds: full, contentMask: full,
                   background: color, borderColor: color,
                   cornerRadii: Corners(all: ScaledPixels(0)),
                   borderWidths: Edges(all: ScaledPixels(0)),
                   order: 0)
}

/// The inline-argument ceiling that `Renderer.encode` used to sit under.
///
/// **400 is not a round number, it is a measured one.** This test was written
/// at 50 first — past the 4 KB / "roughly 39 rects" figure the M0 note in
/// `Renderer.encode` gave — and reverting the `MTLBuffer` to `setVertexBytes`
/// left it green, because that figure was wrong. Sweeping the count under the
/// reverted encoder: 314 rects (32,656 bytes) render correctly, 315 abort the
/// process with a Metal API-validation failure. A guard below the real ceiling
/// is a test that cannot fail for the thing it is named after, so this one
/// draws 400.
///
/// It therefore fails **loudly** rather than red if the buffer ever goes back:
/// the whole test process aborts. That is the honest shape of the failure, and
/// preferable to picking a number that keeps the suite tidy and checks nothing.
@Test @MainActor func manyRectsAllReachTheGPU() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let renderer = try Renderer(device: device)

    var scene = Scene()
    // 400 * 104 bytes = 41,600 — past the 32,7xx boundary measured above.
    for _ in 0..<399 { scene.insert(coverRect(.rgb(0x0000FF), side: 64)) }
    scene.insert(coverRect(.rgb(0xFF0000), side: 64))
    scene.finalize()
    #expect(scene.rects.count == 400)

    let pixels = try renderer.renderOffscreen(
        scene, size: Size(width: DevicePixels(64), height: DevicePixels(64)))

    // Painter's order: the last rect wins. Red, not blue, and not the cleared
    // transparent black a dropped tail would leave under the 399 blues.
    let centre = bgra(pixels, 32, 32, width: 64)
    #expect(centre.0 > 200, "the 400th rect never reached the GPU")
    #expect(centre.1 < 40)
    #expect(centre.2 < 40, "the last rect drawn is blue, so the tail of the scene was dropped")
    #expect(centre.3 > 200)
}

/// The real guard for `Renderer.pixelFormat`, and the reason
/// `drawableFormatIsGammaEncodedNotSRGB` above is no longer alone.
///
/// Spec §7.8 composites in **gamma-encoded** sRGB. Blend 50%-alpha white over
/// opaque black: on `bgra8Unorm` the hardware blends the stored gamma-encoded
/// values, giving 0.5 → **128**. On `bgra8Unorm_srgb` it decodes both to linear
/// first and re-encodes after, giving 0.5 linear → **188**. Nothing else in the
/// suite can tell the two apart, because `renderOffscreen` reads the same
/// constant and both sides flip together.
///
/// **The claim that this was not implementable in M0 was wrong**, and the
/// correction matters more than the test: it said "the scene has no
/// translucent-over-opaque path to drive", but `Scene.insert` has always taken
/// as many rects as you hand it and `Hsla` has always had an alpha. What was
/// missing was not a mechanism — it was two lines of test. That is the practices
/// doc's shape 10: a prediction about measurement, dressed as a fact about the
/// code, which told everyone not to look.
@Test @MainActor func compositingIsGammaEncodedNotLinear() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let renderer = try Renderer(device: device)

    var scene = Scene()
    scene.insert(coverRect(.black, side: 64))
    scene.insert(coverRect(Hsla(h: 0, s: 0, l: 1, a: 0.5), side: 64))
    scene.finalize()

    let pixels = try renderer.renderOffscreen(
        scene, size: Size(width: DevicePixels(64), height: DevicePixels(64)))
    let centre = bgra(pixels, 32, 32, width: 64)

    // Wide enough to absorb rounding, narrow enough to exclude 188.
    #expect(centre.0 >= 120 && centre.0 <= 136,
            "50% white over black composited to \(centre.0); gamma sRGB gives ~128 and linear (an _sRGB target) gives ~188")
    #expect(centre.1 == centre.0)
    #expect(centre.2 == centre.0)
    #expect(centre.3 > 200, "the black underneath is opaque, so the result must be")
}

// MARK: - The unfinalized-scene guard

private func whiteRect() -> MUIRect {
    MUIRect(bounds: MUIBounds(origin: MUIPoint(x: 4, y: 4),
                              size: MUISize(width: 8, height: 8)),
            contentMask: MUIBounds(origin: MUIPoint(x: 0, y: 0),
                                   size: MUISize(width: 32, height: 32)),
            maskCornerRadii: MUICorners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0),
            background: MUIHsla(h: 0, s: 0, l: 1, a: 1),
            borderColor: MUIHsla(h: 0, s: 0, l: 0, a: 0),
            cornerRadii: MUICorners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0),
            borderWidths: MUIEdges(top: 0, right: 0, bottom: 0, left: 0),
            order: 0, _reserved: 0)
}

/// `encode` traps on a non-empty scene whose `finalize()` was never called.
///
/// **The failure it replaces was silent.** `encode` guards on `scene.isEmpty`
/// and then iterates `scene.drawList`, which `finalize()` is what builds — so
/// an unfinalized scene holding primitives encoded zero draw calls and painted
/// **0 pixels, with no error anywhere**. Before the draw list existed, a
/// forgotten `finalize()` meant unsorted primitives; since Task 1 it means a
/// blank frame. `encode` is public; production is safe only because `Window`
/// goes through `Frame.finalizedScene()`.
///
/// What a wrong implementation this catches: deleting the `precondition` (or
/// weakening it to `scene.isEmpty`, which is already false here) — the process
/// would then exit cleanly, having drawn nothing.
@Test @MainActor func encodingAnUnfinalizedSceneTraps() async throws {
    try #require(MTLCreateSystemDefaultDevice() != nil,
                 "no Metal device; run on macOS hardware")
    await #expect(processExitsWith: .failure) {
        let renderer = try await Renderer(device: MTLCreateSystemDefaultDevice()!)
        var scene = Scene()
        scene.insert(whiteRect())
        // No `scene.finalize()`.
        _ = try await renderer.renderOffscreen(
            scene, size: Size(width: DevicePixels(32), height: DevicePixels(32)))
    }
}

/// The positive control (ruling CS-C). Without it the test above passes
/// against an `encode` that traps unconditionally — on every scene, finalized
/// or not, which would take down every frame this framework ever draws.
@Test @MainActor func encodingAFinalizedSceneDoesNotTrap() async throws {
    try #require(MTLCreateSystemDefaultDevice() != nil,
                 "no Metal device; run on macOS hardware")
    await #expect(processExitsWith: .success) {
        let renderer = try await Renderer(device: MTLCreateSystemDefaultDevice()!)
        var scene = Scene()
        scene.insert(whiteRect())
        scene.finalize()
        _ = try await renderer.renderOffscreen(
            scene, size: Size(width: DevicePixels(32), height: DevicePixels(32)))
    }
}
