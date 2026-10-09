import Testing
import Metal
import MetalUICore
import MetalUILayout
import MetalUIScene
@testable import MetalUI

// C10 lane 3 — `.blur(radius:)` (ruling `LK-K`; spec
// `docs/superpowers/specs/2026-10-08-controls-looks-design.md` §3.3, §4.3).
// SwiftUI's side is `docs/probes/swiftui-controls-looks.swift`, arms B1–B5
// (ImageRenderer, scale 1, over white).
//
// A blurred leaf reaches the scene as ONE image (premultiplied colour, filter
// nearest, integer device bounds) in its leaf's place. The probe's 100 × 100
// canvas is a 100 window here, so its pixel (x, y) is device pixel (x, y).

private func px(_ v: Float) -> Pixels { Pixels(v) }
private let linear1 = Animation.linear(duration: 1)

/// A 40 × 40 square of `color` (a proposal `Color` view).
@MainActor private func square(_ color: Color, _ side: Float = 40) -> ModifiedContent<Color, LayoutModifier> {
    color.frame(width: px(side), height: px(side))
}

// MARK: - 3.17 (B2)

/// **3.17** (B2, B2c). Blur is per leaf: blue over red, blurred together,
/// reads as each blurred alone — at x 26 (207, 168, 216) and at x 30 (115, 52,
/// 192), green below red because the red square's blur shows under the
/// blue's. Two images. Mutation: composite the leaves first (one image, red ==
/// green at the edge).
@Test @MainActor func blurIsPerLeafB2() throws {
    let scene = lkScene(ZStack { square(lkRed); square(lkBlue) }.blur(radius: px(4)), side: 100)
    #expect(gxImages(scene).count == 2, "one image per leaf: \(gxImages(scene).count)")
    let edge = lkComposite(scene, 26.5, 50.5), inside = lkComposite(scene, 30.5, 50.5)
    #expect(lkNear(edge, [207, 168, 216], 8), "B2 x26 (207, 168, 216): \(edge)")
    #expect(lkNear(inside, [115, 52, 192], 8), "B2 x30 (115, 52, 192): \(inside)")
    #expect(edge[0] - edge[1] > 25, "the red leaf bleeds under the blue: \(edge)")
}

// MARK: - 3.18 (B1)

/// **3.18** (B1). Sigma is the radius: a black 40 × 40 blurred at radius 4
/// reads B1's profile along its middle row within divergence 105's ±8.
/// Mutation: sigma = radius / 2.
@Test @MainActor func blurSigmaIsTheRadiusB1() throws {
    let scene = lkScene(square(lkBlack).blur(radius: px(4)), side: 100)
    try #require(gxImages(scene).count == 1, "one image")
    let b1: [(Int, Int)] = [(20, 253), (22, 248), (24, 234), (26, 207), (28, 165), (30, 115), (32, 67), (34, 32),
                            (36, 13), (38, 4), (40, 1)]
    for (x, want) in b1 {
        let got = lkComposite(scene, Double(x) + 0.5, 50.5)[0]
        #expect(abs(got - want) <= 8, "x \(x): \(got) vs B1 \(want)")
    }
}

// MARK: - 3.19 (B4)

/// **3.19** (B4). A blur changes no layout, no hit region and no accessibility
/// record: with and without `.blur(radius: 6)` the hitboxes, the stack's other
/// child and the records are the same, and a window holding only blurs pushes
/// no effect scope. Mutation: the blur's reach added to the layout size.
@Test @MainActor func aBlurChangesNoLayoutHitOrAccessibilityB4() throws {
    func tree(_ blurred: Bool) -> some Element {
        VStack(spacing: 0) {
            if blurred {
                square(.accent).accessibilityLabel("square").onTapGesture {}.blur(radius: px(6))
            } else {
                square(.accent).accessibilityLabel("square").onTapGesture {}
            }
            Color(.separator).frame(width: px(40), height: px(10))
        }
    }
    let plain = effectFrame(tree(false), accessibility: true)
    let blurred = effectFrame(tree(true), accessibility: true)
    #expect(blurred.hitboxes.map { gxDescribe(MUIBounds($0.bounds.scaled(by: 1))) }
            == plain.hitboxes.map { gxDescribe(MUIBounds($0.bounds.scaled(by: 1))) }, "the same hitboxes")
    let separator = Theme.light[.separator]
    func separators(_ f: Frame) -> [String] {
        f.finalizedScene().rects.filter { $0.background.l == separator.l && $0.background.h == separator.h }
            .map { gxDescribe($0.bounds) }
    }
    #expect(separators(blurred) == separators(plain) && separators(plain).count == 1,
            "the same layout: \(separators(blurred)) vs \(separators(plain))")
    #expect(blurred.axEmissions.count == plain.axEmissions.count
            && zip(blurred.axEmissions, plain.axEmissions).allSatisfy { $0.geometry.frame == $1.geometry.frame },
            "the same accessibility records")
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, _) = try makeFakeWindow(device: device, size: 200) {
        Column {
            VStack { square(.accent).blur(radius: px(6)) }
            fxLegacyBar(40, 40).blur(radius: px(6))
        }
    }
    window.drawFrameIfNeeded()
    try #require(gxImages(window.lastScene).count == 2, "control: both blurs drew")
    #expect(window.lastEffectScopesPushed == 0, "no scope for a blur: \(window.lastEffectScopesPushed)")
}

// MARK: - 3.20 (B5)

/// **3.20** (B5). A clip outside the blur cuts it: `.blur(radius: 4)` then
/// `.clipped()` draws nothing outside the 40 × 40 box (x 26 and 28 read white)
/// and the blur inside it (x 30 reads 115). Mutation: the clip applied inside
/// the blur (the image spreads past the box).
@Test @MainActor func aClipOutsideTheBlurCutsItB5() throws {
    let scene = lkScene(square(lkBlack).blur(radius: px(4)).clipped(), side: 100)
    let images = gxImages(scene)
    try #require(images.count == 1, "one image")
    #expect(gxDescribe(images[0].image.bounds) == "(30.0, 30.0, 40.0×40.0)",
            "cut to the box: \(gxDescribe(images[0].image.bounds))")
    for (x, want) in [(26, 255), (28, 255), (30, 115), (32, 67), (34, 32)] {
        let got = lkComposite(scene, Double(x) + 0.5, 50.5)[0]
        #expect(abs(got - want) <= 8, "x \(x): \(got) vs B5 \(want)")
    }
}

// MARK: - 3.21 (LK-K item 2)

/// **3.21** (`LK-K` item 2). A text run blurs as one leaf: `Text` under a blur
/// is one image and no glyph reaches the scene. Mutation: glyph by glyph.
@Test @MainActor func aTextRunBlursAsOneLeaf() throws {
    let scene = lkScene(Text("Hi, there").font(size: 20).blur(radius: px(2)), side: 200)
    #expect(gxImages(scene).count == 1, "one image for the run: \(gxImages(scene).count)")
    #expect(scene.glyphs.isEmpty, "no glyph drawn sharp: \(scene.glyphs.count)")
}

// MARK: - 3.22 (LK-K item 5, divergence 167)

/// **3.22** (`LK-K` item 5, divergence 167). A GPU surface under a blur is
/// drawn unblurred: its quad still reaches the scene (one surface), beside the
/// blurred colour leaf (one image). Mutation: drop the surface.
@Test @MainActor func aSurfaceLeafUnderBlurIsDrawnUnblurred() throws {
    let scene = lkScene(VStack(spacing: 0) {
        GPUSurface(value: 1) { _ in }.frame(width: px(40), height: px(40))
        square(lkBlack)
    }.blur(radius: px(4)), side: 200)
    #expect(scene.surfaces.count == 1, "the surface, unblurred: \(scene.surfaces.count)")
    #expect(gxImages(scene).count == 1, "the colour leaf, blurred: \(gxImages(scene).count)")
    if let surface = scene.surfaces.first {
        #expect(gxDescribe(surface.bounds) == "(80.0, 60.0, 40.0×40.0)", "in place: \(gxDescribe(surface.bounds))")
    }
}

// MARK: - 3.23 (LK-K item 6)

/// **3.23** (`LK-K` item 6). The radius animates: 0 → 8 under a one-second
/// linear transaction draws, half-way, the image a resting radius 4 draws.
/// Mutation: snap (radius 8 at once).
@Test @MainActor func theBlurRadiusAnimates() throws {
    let h = TransitionHarness()
    h.frame(0, nil, VStack { square(lkBlack).blur(radius: px(0)) }, side: 200)
    h.frame(0, linear1, VStack { square(lkBlack).blur(radius: px(8)) }, side: 200)
    let midway = gxImages(h.frame(0.5, nil, VStack { square(lkBlack).blur(radius: px(8)) }, side: 200)
        .finalizedScene())
    let four = gxImages(lkScene(VStack { square(lkBlack).blur(radius: px(4)) }, side: 200))
    try #require(midway.count == 1 && four.count == 1, "one image each")
    #expect(gxDescribe(midway[0].image.bounds) == gxDescribe(four[0].image.bounds)
                && midway[0].texture.pixels == four[0].texture.pixels,
            "radius 4 half-way: \(gxDescribe(midway[0].image.bounds)) vs \(gxDescribe(four[0].image.bounds))")
}

// MARK: - 3.24 (LK-K item 6)

/// **3.24** (`LK-K` item 6). A radius of 0 draws the leaf unchanged: the same
/// rect, no image. Mutation: blur anyway (an image in the rect's place).
@Test @MainActor func aBlurOfRadiusZeroDrawsTheLeafUnchanged() throws {
    let plain = lkScene(square(lkBlack), side: 200)
    let zero = lkScene(square(lkBlack).blur(radius: px(0)), side: 200)
    #expect(gxImages(zero).isEmpty, "no image: \(gxImages(zero).count)")
    #expect(zero.rects.map { gxDescribe($0.bounds) } == plain.rects.map { gxDescribe($0.bounds) }
            && zero.rects.count == 1, "the rect, unchanged")
}

/// **3.25** (`LK-K` item 6). A non-finite radius traps naming the modifier, on
/// both vocabularies. Mutation: clamp it.
@Test func aNonFiniteBlurRadiusTraps() async {
    let proposal = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        await MainActor.run { _ = Color.black.frame(width: Pixels(4), height: Pixels(4)).blur(radius: Pixels(.nan)) }
    }
    let proposalError = String(decoding: proposal?.standardErrorContent ?? [], as: UTF8.self)
    #expect(proposalError.contains("blur(radius:)"), "the proposal spelling names the modifier")
    let legacy = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        await MainActor.run { _ = Box().blur(radius: Pixels(.infinity)) }
    }
    let legacyError = String(decoding: legacy?.standardErrorContent ?? [], as: UTF8.self)
    #expect(legacyError.contains("blur(radius:)"), "the legacy spelling names the modifier")
}

// MARK: - 3.26 (LK-K item 1, GX-H)

/// **3.26** (`LK-K` item 1). A legacy blur joins the render effects in written
/// order: blur then `scaleEffect(2)` scales the blur (sigma 8 on screen, an
/// image 80 + 2 × 24 wide), `scaleEffect(2)` then blur blurs the scaled leaf
/// (sigma 4, 80 + 2 × 12). Mutation: append the blur at the front.
@Test @MainActor func theLegacyBlurJoinsRenderEffectsInWrittenOrder() throws {
    let scaledBlur = gxImages(lkScene(fxLegacyBar(40, 40).blur(radius: px(4)).scaleEffect(2), side: 300))
    let blurredScale = gxImages(lkScene(fxLegacyBar(40, 40).scaleEffect(2).blur(radius: px(4)), side: 300))
    try #require(scaledBlur.count == 1 && blurredScale.count == 1, "one image each")
    #expect(scaledBlur[0].image.bounds.size.width == 128, "sigma 8: \(gxDescribe(scaledBlur[0].image.bounds))")
    #expect(blurredScale[0].image.bounds.size.width == 104, "sigma 4: \(gxDescribe(blurredScale[0].image.bounds))")
}

// MARK: - 3.27 (MC-C)

/// **3.27** (`MC-A`/`MC-C`). The proposal blur is one identity level: the
/// content's ids under `.blur` equal those under a one-layer `.padding(0)`
/// chain and differ from the bare content's. Mutation: two layers.
@Test @MainActor func theLayoutModifierBlurCaseIsOneIdentityLevel() throws {
    func tapIDs(_ e: some ProposalElementGroup) -> [GlobalElementID] {
        effectFrame(VStack { e }).hitboxes.filter { $0.handlers.gestures.count > 0 }.map(\.id)
    }
    let bare = tapIDs(fxBar(40, 20).onTapGesture {})
    let padded = tapIDs(fxBar(40, 20).onTapGesture {}.padding(Edges(all: px(0))))
    let blurred = tapIDs(fxBar(40, 20).onTapGesture {}.blur(radius: px(3)))
    try #require(bare.count == 1 && padded.count == 1 && bare != padded, "the arms disagree: \(bare) \(padded)")
    #expect(blurred == padded, "one level: \(blurred) vs \(padded)")
}
