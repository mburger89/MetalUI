import Testing
import MetalUICore
import MetalUILayout
import MetalUIPath
import MetalUIScene
@testable import MetalUI

// 3D render effects, the paint side (`PJ-G`, record 193): what a projective scope hands the scene. SwiftUI's side is
// `docs/probes/swiftui-projection-effects.swift`; the renderers' pixels are `ProjectivePrimitiveTests`
// (`MetalUIRenderTests`) and the parity frame 15 of `Experiments/SDLGPU`.

private func px(_ v: Float) -> Pixels { Pixels(v) }
private let yAxis: (x: Double, y: Double, z: Double) = (0, 1, 0)
private let linear1 = Animation.linear(duration: 1)

// MARK: - 18: the record

/// **R.** A projective effect writes one record whose lane 4 is `(g, h, i, det3)` of the device-pixel map: `det3 != 0`, the
/// bottom row of the map the effect computes. An affine effect's tail is all zero, which every shader reads as "no
/// perspective". Mutation: write `det3` for an affine record too (`PrimitiveTransform.record`).
@Test @MainActor func aProjectiveEffectIsOneRecordWithItsPerspectiveLane() throws {
    let scene = effectFrame(fxBar(100, 50).rotation3DEffect(.degrees(45), axis: yAxis)).finalizedScene()
    let rect = try #require(effectRects(scene).first)
    let record = try #require(effectRecord(rect, in: scene))
    try #require(scene.transforms.count == 1, "one record for the one effect")
    #expect(record.det3 != 0 && (record.g != 0 || record.h != 0), "a perspective: \(record)")
    let bounds = Bounds(origin: Point(x: Pixels(rect.bounds.origin.x), y: Pixels(rect.bounds.origin.y)),
                        size: Size(width: Pixels(rect.bounds.size.width), height: Pixels(rect.bounds.size.height)))
    let map = RenderEffectSpec.rotation3D(Rotation3DSpec(angle: .degrees(45), axisX: 0, axisY: 1, axisZ: 0, anchor: .center,
                                                         anchorZ: 0, perspective: 1)).map(in: bounds)
    #expect(abs(Double(record.g) - map.g) < 1e-6 && abs(Double(record.i) - map.i) < 1e-5, "the map's bottom row")
    #expect(abs(Double(record.det3) - map.det3) < 1e-3 * abs(map.det3), "the map's determinant")
}

@Test @MainActor func anAffineRecordsTailIsZero() throws {
    let scene = effectFrame(fxBar(100, 50).rotationEffect(.degrees(30))).finalizedScene()
    let rect = try #require(effectRects(scene).first)
    let record = try #require(effectRecord(rect, in: scene))
    #expect(record.g == 0 && record.h == 0 && record.i == 0 && record.det3 == 0, "\(record)")
}

// MARK: - 13: clips

/// **C1.** A clip inside a projective effect is projected with it (the rect's own content mask, local), and one outside stays
/// at the layout rectangle (the record's outer mask, screen). Mutation: no local clip base for a non-flattening scope
/// (`clipBase = clipDepth` dropped in `paintWithDeviceMap`).
@Test @MainActor func aClipInsideAProjectiveEffectProjectsAndOneOutsideStays() throws {
    // A bar that hangs over the right edge of the 200-point window (the 250-wide padded block is centred): its inside clip is cut by the
    // window in the bar's own (local) space, 125...200, and the record's outer mask is the whole window: the clip is projected
    // with the bar, not applied as a screen box.
    let inner = effectFrame(Color(.accent).frame(width: px(100), height: px(50))
        .clipped()
        .rotation3DEffect(.degrees(20), axis: yAxis, perspective: 0.5)
        .padding(Edges(top: px(0), right: px(0), bottom: px(0), left: px(150)))).finalizedScene()
    let rect = try #require(effectRects(inner).first)
    let t = try #require(effectRecord(rect, in: inner))
    #expect(rect.contentMask.origin.x == 125 && rect.contentMask.size.width == 75, "the clip is local to the bar: \(fxDescribe(rect.contentMask))")
    #expect(t.outerMask.size.width == 200, "the window, no screen cut from an inside clip: \(fxDescribe(t.outerMask))")
    let outer = effectFrame(Color(.accent).frame(width: px(100), height: px(50))
        .rotation3DEffect(.degrees(45), axis: yAxis).clipped()).finalizedScene()
    let rect2 = try #require(effectRects(outer).first)
    let t2 = try #require(effectRecord(rect2, in: outer))
    #expect(t2.outerMask.size.width < 150 && t2.outerMask.size.width >= 99, "the clip outside stays at the layout rect: \(fxDescribe(t2.outerMask))")
}

// MARK: - 19: no CPU work while a flip animates

private func star(_ side: Double) -> Path {
    Path { path in
        let unit: [(Double, Double)] = [(0, -1), (0.5878, 0.809), (-0.9511, -0.309), (0.9511, -0.309), (-0.5878, 0.809)]
        let c = side / 2
        path.move(to: Point(x: Pixels(Float(c + c * unit[0].0)), y: Pixels(Float(c + c * unit[0].1))))
        for p in unit.dropFirst() { path.addLine(to: Point(x: Pixels(Float(c + c * p.0)), y: Pixels(Float(c + c * p.1)))) }
        path.closeSubpath()
    }
}

/// **A.** A path and a shadow inside a 3D effect are rasterised in their creation space and drawn with the projective record, so
/// turning the card does no CPU raster after the first frame: frames 2-5 rasterize 0 pixels and make 0 textures. Mutation:
/// rasterize under the effect's affine part (`pathImage`'s `outer`).
@Test @MainActor func anAnimatingFlipRasterizesNothingAfterTheFirstFrame() throws {
    func tree(_ angle: Double) -> some Element {
        HStack(spacing: px(10)) {
            star(60).fill(.accent).frame(width: px(60), height: px(60))
            Color(.surface).frame(width: px(40), height: px(30))
                .shadow(color: .textPrimary, radius: px(3), x: px(2), y: px(2))
        }
        .rotation3DEffect(.degrees(angle), axis: yAxis)
    }
    let h = TransitionHarness()
    h.frame(0, nil, tree(10), side: 200)
    let rasters = h.store.rasters
    try #require(rasters.lastRasterizedPixels > 0, "frame 1 rasterized: \(rasters.lastRasterizedPixels)")
    var misses: [String] = []
    for (i, angle) in [20.0, 30, 40, 50].enumerated() {
        let frame = h.frame(Double(i + 1), nil, tree(angle), side: 200)
        if rasters.lastRasterizedPixels != 0 || rasters.lastTexturesMade != 0 {
            misses.append("angle \(angle): \(rasters.lastRasterizedPixels) px, \(rasters.lastTexturesMade) textures")
        }
        let images = gxImages(frame.finalizedScene())
        try #require(images.count >= 2, "the path and the shadow still draw: \(images.count)")
        #expect(frame.finalizedScene().transforms.allSatisfy { $0.det3 != 0 }, "drawn with the projective record")
    }
    #expect(misses.isEmpty, "\(misses)")
}

// MARK: - 21, 22: what a projective effect cannot carry

// D1066 (a shadow or blur outside a projective effect casts or blurs nothing) is `aProjectiveLeafCastsAShadowOffscreen` and
// `aProjectiveLeafUnderBlurIsBlurred` since GF-A (GroupFilterTests.swift): divergence 1066 is retired.

/// **D1067.** A material under a projective effect draws its flat tint, not a backdrop record; under an affine effect it is a
/// backdrop. Mutation: skip the degrade in `processScopes`.
@Test @MainActor func aMaterialUnderAProjectiveEffectDrawsItsFlatTint() throws {
    func backdrops<E: Element>(_ element: E) -> (backdrops: Int, rects: Int) {
        let scene = effectFrame(element).finalizedScene()
        return (scene.backdrops.count, scene.rects.count)
    }
    let plain = backdrops(Color.clear.frame(width: px(60), height: px(40)).background(.regularMaterial)
        .rotationEffect(.degrees(20)))
    let projected = backdrops(Color.clear.frame(width: px(60), height: px(40)).background(.regularMaterial)
        .rotation3DEffect(.degrees(40), axis: yAxis))
    #expect(plain.backdrops == 1, "control: a backdrop under the affine effect")
    #expect(projected.backdrops == 0 && projected.rects >= 1, "divergence 1067: a flat tint rect, no backdrop (\(projected))")
}

// MARK: - 20 (paint half): a corner behind the eye drops the primitive

/// **E.** A primitive with a corner on or behind the eye is dropped at the scope (the SDL rasteriser leaves depth clipping off),
/// and an effect whose rectangle has such a corner paints nothing at all. Mutation: drop the `isInFront` guards in
/// `RenderEffect.apply`.
@Test @MainActor func aPrimitiveBehindTheEyeIsNotEmitted() throws {
    // The effect's own 60 x 20 rectangle is in front of the eye, but the 300-wide bar it holds has corners behind it
    // (divergence 1069): the bar is dropped, per primitive.
    let overflow = effectFrame(Color(.accent).frame(width: px(300), height: px(20)).frame(width: px(60), height: px(20))
        .rotation3DEffect(.degrees(60), axis: yAxis, perspective: 2)).finalizedScene()
    #expect(effectRects(overflow).isEmpty && overflow.transforms.isEmpty, "the overflowing bar is dropped: \(overflow.rects.count)")
    var behind = ProjectionTransform(); behind.m13 = -0.02   // w = 1 - 0.02 x: zero at x = 50
    let scene = effectFrame(fxBar(100, 50).projectionEffect(behind)).finalizedScene()
    #expect(effectRects(scene).isEmpty && scene.transforms.isEmpty, "nothing drawn: \(scene.rects.count) rects")
    var front = ProjectionTransform(); front.m13 = 0.002
    let drawn = effectFrame(fxBar(100, 50).projectionEffect(front)).finalizedScene()
    #expect(effectRects(drawn).count == 1, "control: a map in front of the eye draws")
}
