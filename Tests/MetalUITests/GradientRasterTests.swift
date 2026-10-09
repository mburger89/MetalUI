import Testing
import Metal
import MetalUICore
import MetalUILayout
import MetalUIScene
@testable import MetalUI

// C10 lane 3 — the gradient raster (ruling `LK-J` items 4–6; spec
// `docs/superpowers/specs/2026-10-08-controls-looks-design.md` §3.3, §4.3).
// A gradient reaches the scene as ONE image: the strip (`W × 1` or `1 × H`,
// linear filter, the rect's own bounds and radii as its quad and mask) for an
// axis-aligned linear gradient on an untransformed rectangle wholly inside its
// clip, else a full raster (nearest, integer device bounds, coverage × colour).
// Work is read from `RasterCache.lastRasterizedPixels`, never time.

private func px(_ v: Float) -> Pixels { Pixels(v) }

private let vertical = LinearGradient(colors: [lkRed, lkBlue], startPoint: .top, endPoint: .bottom)
private let horizontal = LinearGradient(colors: [lkRed, lkBlue], startPoint: .leading, endPoint: .trailing)
private let diagonal = LinearGradient(colors: [lkRed, lkBlue], startPoint: .topLeading, endPoint: .bottomTrailing)

// MARK: - 3.11 (LK-J item 5)

/// **3.11** (`LK-J` item 5). An axis-aligned linear gradient on a rectangle
/// draws a one-pixel strip: a vertical 40 × 100 is a 1 × 100 texture over the
/// rect, linear-filtered, rasterizing 100 pixels (200 at scale 2); a
/// horizontal one is 40 × 1; a rounded rectangle keeps the strip with its
/// radii as the image's mask. Mutation: always the full raster.
@Test @MainActor func anAxisAlignedRectGradientDrawsAOnePixelStrip() throws {
    let tall = effectFrame(Rectangle().fill(vertical).frame(width: px(40), height: px(100)))
    let tallImages = gxImages(tall.finalizedScene())
    try #require(tallImages.count == 1, "one image")
    #expect(tallImages[0].texture.width == 1 && tallImages[0].texture.height == 100,
            "1 × 100: \(tallImages[0].texture.width) × \(tallImages[0].texture.height)")
    #expect(gxDescribe(tallImages[0].image.bounds) == "(80.0, 50.0, 40.0×100.0)",
            "over the rect: \(gxDescribe(tallImages[0].image.bounds))")
    #expect(tallImages[0].image.filter == ImageFilter.linear.rawValue, "stretched by the linear filter")
    #expect(tall.animationStore.rasters.lastRasterizedPixels == 100,
            "100 pixels: \(tall.animationStore.rasters.lastRasterizedPixels)")

    let retina = effectFrame(Rectangle().fill(vertical).frame(width: px(40), height: px(100)), scaleFactor: 2)
    let retinaImages = gxImages(retina.finalizedScene())
    try #require(retinaImages.count == 1, "one image at scale 2")
    #expect(retinaImages[0].texture.height == 200 && retina.animationStore.rasters.lastRasterizedPixels == 200,
            "200 device pixels at scale 2: \(retinaImages[0].texture.height)")

    let wide = gxImages(lkScene(Rectangle().fill(horizontal).frame(width: px(40), height: px(100)), side: 200))
    try #require(wide.count == 1, "one image")
    #expect(wide[0].texture.width == 40 && wide[0].texture.height == 1,
            "40 × 1: \(wide[0].texture.width) × \(wide[0].texture.height)")

    let rounded = gxImages(lkScene(RoundedRectangle(cornerRadius: px(8)).fill(vertical)
        .frame(width: px(40), height: px(100)), side: 200))
    try #require(rounded.count == 1, "one image")
    #expect(rounded[0].texture.width == 1 && rounded[0].image.maskCornerRadii.topLeft == 8
                && gxDescribe(rounded[0].image.contentMask) == "(80.0, 50.0, 40.0×100.0)",
            "a strip masked by the rect's radii: \(rounded[0].texture.width), \(rounded[0].image.maskCornerRadii)")
}

// MARK: - 3.12 (LK-J item 5)

/// **3.12** (`LK-J` item 5). A diagonal gradient, or one partly outside its
/// clip, rasterizes in full: a diagonal 40 × 40 is a 40 × 40 texture,
/// rasterizing 1600 pixels; a vertical 40 × 100 clipped to 40 × 50 is a 40 ×
/// 50 texture over the clip, 2000 pixels. Mutation: the strip for diagonals.
@Test @MainActor func aDiagonalOrClippedGradientRastersInFull() throws {
    let square = effectFrame(Rectangle().fill(diagonal).frame(width: px(40), height: px(40)))
    let images = gxImages(square.finalizedScene())
    try #require(images.count == 1, "one image")
    #expect(images[0].texture.width == 40 && images[0].texture.height == 40,
            "40 × 40: \(images[0].texture.width) × \(images[0].texture.height)")
    #expect(images[0].image.filter == ImageFilter.nearest.rawValue, "a full raster is drawn 1 : 1")
    #expect(square.animationStore.rasters.lastRasterizedPixels == 1600,
            "1600 pixels: \(square.animationStore.rasters.lastRasterizedPixels)")

    let clipped = effectFrame(Rectangle().fill(vertical).frame(width: px(40), height: px(100))
        .frame(width: px(40), height: px(50)).clipped())
    let cut = gxImages(clipped.finalizedScene())
    try #require(cut.count == 1, "one image")
    #expect(cut[0].texture.width == 40 && cut[0].texture.height == 50
                && gxDescribe(cut[0].image.bounds) == "(80.0, 75.0, 40.0×50.0)",
            "the visible 40 × 50: \(cut[0].texture.width) × \(cut[0].texture.height) \(gxDescribe(cut[0].image.bounds))")
    #expect(clipped.animationStore.rasters.lastRasterizedPixels == 2000,
            "2000 pixels: \(clipped.animationStore.rasters.lastRasterizedPixels)")
}

// MARK: - 3.13, 3.14 (GX-K)

/// **3.13** (`GX-K`). An unchanged gradient keeps its texture identity across
/// frames — the strip and the full raster both — and costs no raster work on
/// the second. Mutation: no cache entry for gradients.
@Test @MainActor func anUnchangedGradientKeepsItsTextureIdentity() throws {
    for g in [vertical, diagonal] {
        let h = TransitionHarness()
        let tree = Rectangle().fill(g).frame(width: px(40), height: px(40))
        let first = gxImages(h.frame(0, nil, tree, side: 200).finalizedScene())
        let second = h.frame(1, nil, tree, side: 200)
        let again = gxImages(second.finalizedScene())
        try #require(first.count == 1 && again.count == 1, "one image each")
        #expect(first[0].texture === again[0].texture, "one texture identity")
        #expect(second.animationStore.rasters.lastRasterizedPixels == 0, "no work on a hit")
    }
}

/// **3.14** (`GX-K`). A changed stop makes a new texture with the new colour:
/// the cache key carries the resolved stops. Mutation: drop the stops from the
/// key (a stale raster).
@Test @MainActor func aChangedStopMakesANewTexture() throws {
    for (start, end) in [(UnitPoint.top, UnitPoint.bottom), (.topLeading, .bottomTrailing)] {
        let h = TransitionHarness()
        func tree(_ first: Color) -> some Element {
            Rectangle().fill(LinearGradient(colors: [first, lkBlue], startPoint: start, endPoint: end))
                .frame(width: px(40), height: px(40))
        }
        let red = h.frame(0, nil, tree(lkRed), side: 200).finalizedScene()
        let green = h.frame(1, nil, tree(lkGreen), side: 200).finalizedScene()
        try #require(gxImages(red).count == 1 && gxImages(green).count == 1, "one image each")
        #expect(gxImages(red)[0].texture !== gxImages(green)[0].texture, "a new texture")
        let corner = lkComposite(green, 80.5, 80.5)
        #expect(corner[1] > 200 && corner[0] < 40, "the new first colour, not a stale red: \(corner)")
    }
}

// MARK: - 3.15 (LK-J item 2, GX-G)

/// **3.15** (`LK-J` item 2). A gradient under a rotation follows the
/// transform: a top→bottom red→blue square turned 90° clockwise runs right →
/// left on screen (red on the right). Mutation: colour by device position,
/// ignoring the composed map.
@Test @MainActor func aGradientUnderARotationFollowsTheTransform() throws {
    let scene = lkScene(Rectangle().fill(vertical).frame(width: px(40), height: px(40))
        .rotationEffect(.degrees(90)), side: 200)
    try #require(gxImages(scene).count == 1, "one image")
    let left = lkComposite(scene, 81.5, 100.5), right = lkComposite(scene, 118.5, 100.5)
    #expect(right[0] > 200 && right[2] < 60, "red on the right: \(right)")
    #expect(left[2] > 200 && left[0] < 60, "blue on the left: \(left)")
}

// MARK: - 3.16 (LK-J, GX-J)

/// **3.16** (`LK-J`, `GX-J` SH6). A shadow sees a gradient leaf's alpha: a
/// clear → black leading→trailing square shadowed straight down casts a shadow
/// transparent on the left and opaque on the right. Mutation: the silhouette
/// from the bounding rect.
@Test @MainActor func aShadowSeesAGradientLeafsAlpha() throws {
    let g = LinearGradient(colors: [lkBlack.opacity(0), lkBlack], startPoint: .leading, endPoint: .trailing)
    let scene = lkScene(Rectangle().fill(g).frame(width: px(40), height: px(40))
        .shadow(color: .textPrimary, radius: px(0), x: px(0), y: px(50)), side: 200)
    let images = gxImages(scene)
    try #require(images.count == 2, "the shadow and the gradient: \(images.count)")
    let shadow = images[0]
    #expect(gxAlpha(shadow, 80, 140) < 10, "clear on the left: \(gxAlpha(shadow, 80, 140))")
    #expect(gxAlpha(shadow, 119, 140) > 240, "opaque on the right: \(gxAlpha(shadow, 119, 140))")
}
