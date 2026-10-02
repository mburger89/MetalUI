import Testing
import Metal
import MetalUICore
import MetalUILayout
import MetalUIPlatform
import MetalUIScene
import MetalUIDemoContent
@testable import MetalUI

// Paths, shadows and transforms, lane 3 — shadows and the looks demo (rulings
// `GX-J`, `GX-Q`; spec
// `docs/superpowers/specs/2026-10-02-paths-shadows-transforms-design.md` §8,
// tests 3.15–3.24, 3.26–3.28). SwiftUI's side is
// `docs/probes/swiftui-paths-shadows-transforms.swift`, arms SH0–SH13, H5, X6,
// N4–N6.
//
// A shadow reaches the scene as one image per leaf (filter nearest, integer
// device bounds), inserted just before its leaf. Unless an arm says otherwise
// the shadow colour is `.textPrimary` (opaque), so a texel's alpha is the
// shadow's coverage; the content is a 40 × 40 square centred in the 200
// window, at (80, 80).

private func px(_ v: Float) -> Pixels { Pixels(v) }
private let linear1 = Animation.linear(duration: 1)

/// The 40 × 40 accent square.
@MainActor private func square(_ side: Float = 40) -> ModifiedContent<Color, LayoutModifier> {
    Color(.accent).frame(width: px(side), height: px(side))
}

/// The kinds of a finalized scene's draw runs, in draw order.
private func runKinds(_ scene: Scene) -> [PrimitiveKind] { scene.drawList.map(\.kind) }

// MARK: - 3.15 (SH5)

/// **3.15** (SH5). A shadow is drawn below EACH leaf: an overlapping `ZStack`
/// of two squares, shadowed as a whole, draws shadow, square, shadow, square —
/// so the top square's shadow falls on the one below. Mutation **M3n**: one
/// composited shadow.
@Test @MainActor func aShadowIsDrawnBelowEachLeaf() throws {
    let scene = effectFrame(ZStack {
        square(60)
        Color(.separator).frame(width: px(60), height: px(60)).offset(x: px(20), y: px(20))
    }.shadow(color: .textPrimary, radius: px(0), x: px(10), y: px(10))).finalizedScene()
    #expect(runKinds(scene) == [.image, .rect, .image, .rect], "per leaf: \(runKinds(scene))")
    let images = gxImages(scene)
    try #require(images.count == 2, "two shadows")
    #expect(images[1].image.bounds.origin.x == images[0].image.bounds.origin.x + 20,
            "the second follows its own leaf: \(gxDescribe(images[0].image.bounds)) \(gxDescribe(images[1].image.bounds))")
}

// MARK: - 3.16 (SH4, SH5e)

/// **3.16** (SH4, SH5e). A text casts ONE glyph-shaped shadow below its glyphs:
/// one image, drawn before the glyph run, whose inked texels cover under 40 %
/// of its area (a box would cover all of it). Mutation **M3o**: a shadow per
/// glyph.
@Test @MainActor func aTextCastsOneGlyphShapedShadowBelowItsGlyphs() throws {
    let scene = effectFrame(Text("Hi, there").font(size: 20)
        .shadow(color: .textPrimary, radius: px(0), x: px(2), y: px(2))).finalizedScene()
    let images = gxImages(scene)
    try #require(images.count == 1, "one shadow for the text: \(images.count)")
    #expect(runKinds(scene).first == .image && runKinds(scene).contains(.glyph), "below: \(runKinds(scene))")
    let texture = images[0].texture
    let inked = stride(from: 3, to: texture.pixels.count, by: 4).filter { texture.pixels[$0] > 0 }.count
    let fraction = Double(inked) / Double(texture.width * texture.height)
    #expect(fraction > 0.05 && fraction < 0.4, "glyph-shaped: \(fraction)")
}

// MARK: - 3.17 (SH3)

/// **3.17** (SH3). The blur matches SwiftUI's profile: a 40 × 40 square
/// shadowed with radius 10 (sigma 10) reads, along the row through its centre
/// past its right edge, within ±8 of SH3's alpha. Mutation **M3p**: sigma =
/// radius / 2.
@Test @MainActor func theShadowBlurMatchesSwiftUIsProfile() throws {
    let images = gxImages(effectFrame(square().shadow(color: .textPrimary, radius: px(10)))
        .finalizedScene())
    try #require(images.count == 1, "one shadow")
    let sh3: [(Int, Int)] = [(40, 132), (42, 152), (44, 170), (46, 188), (48, 203), (50, 217), (52, 228),
                             (54, 237), (56, 244), (58, 249), (60, 252), (62, 254), (64, 255), (66, 255)]
    for (x, red) in sh3 {
        let alpha = gxAlpha(images[0], 80 + x, 80 + 20)
        #expect(abs(alpha - (255 - red)) <= 8, "x \(x): \(alpha) vs SwiftUI's \(255 - red)")
    }
}

// MARK: - 3.18 (SH2, GX-Q)

/// **3.18** (SH2, `GX-Q`). The default shadow colour is `ColorToken.shadow`,
/// black at 0.33 in both themes: over white a radius-0 shadow reads 171 ± 1.
/// Mutation **M3q**: the default `.textPrimary`.
@Test @MainActor func theDefaultShadowColourIsTheShadowToken() throws {
    #expect(Theme.light[.shadow] == Theme.dark[.shadow] && Theme.light[.shadow] == Hsla.rgb(0, alpha: 0.33),
            "black at 0.33 in both themes")
    let images = gxImages(effectFrame(square().shadow(radius: px(0), x: px(10), y: px(10))).finalizedScene())
    try #require(images.count == 1, "one shadow")
    let origin = images[0].image.bounds.origin
    let texel = gxTexel(images[0].texture, 125 - Int(origin.x), 125 - Int(origin.y))   // shadow only
    let overWhite = 255 - texel[3] + texel[0]
    #expect(abs(overWhite - 171) <= 1, "171 over white: \(overWhite) from \(texel)")
}

// MARK: - 3.19 (SH6)

/// **3.19** (SH6). A shadow follows its content's alpha: under
/// `.opacity(0.5)` inside the shadow, the shadow-only texel's alpha halves
/// (255 → 128). Mutation **M3r**: the leaf's colour alpha ignored.
@Test @MainActor func aShadowFollowsItsContentsAlpha() throws {
    func shadowAlpha(_ element: some Element) throws -> Int {
        let images = gxImages(effectFrame(element).finalizedScene())
        try #require(images.count == 1, "one shadow")
        return gxAlpha(images[0], 125, 125)
    }
    let full = try shadowAlpha(square().shadow(color: .textPrimary, radius: px(0), x: px(10), y: px(10)))
    let half = try shadowAlpha(square().opacity(0.5).shadow(color: .textPrimary, radius: px(0), x: px(10), y: px(10)))
    #expect(full == 255 && abs(half - 128) <= 1, "full \(full), half \(half)")
}

// MARK: - 3.20 (SH7, SH7b)

/// **3.20** (SH7, SH7b). A clip outside the shadow cuts it (`.shadow` then
/// `.clipped()`: nothing outside the 40 × 40 box); a clip inside shapes the
/// silhouette (an 80 × 80 square clipped to 40 × 40, then shadowed: the shadow
/// is the clipped 40 × 40, offset). Mutation **M3s**: the silhouette ignores
/// the leaf's masks.
@Test @MainActor func aShadowIsCutByAnOuterClipAndShapedByAnInnerOne() throws {
    let outer = gxImages(effectFrame(square().shadow(color: .textPrimary, radius: px(0), x: px(10), y: px(10))
        .clipped()).finalizedScene())
    for entry in outer {
        let b = entry.image.bounds
        #expect(b.origin.x >= 80 && b.origin.y >= 80 && b.origin.x + b.size.width <= 120
                && b.origin.y + b.size.height <= 120, "cut to the box: \(gxDescribe(b))")
    }
    let inner = gxImages(effectFrame(Color(.accent).frame(width: px(80), height: px(80))
        .frame(width: px(40), height: px(40)).clipped()
        .shadow(color: .textPrimary, radius: px(0), x: px(10), y: px(10))).finalizedScene())
    try #require(inner.count == 1, "one shadow")
    #expect(gxDescribe(inner[0].image.bounds) == "(90.0, 90.0, 40.0×40.0)",
            "the clipped silhouette, offset: \(gxDescribe(inner[0].image.bounds))")
}

// MARK: - 3.21 (SH8, H5, X6)

/// **3.21** (SH8, H5, X6). A shadow never hits, changes no layout and
/// publishes nothing: with and without `.shadow(radius: 10, x: 10, y: 10)` the
/// hitboxes, the painted square and the accessibility records are the same.
/// Mutation **M3t**: the shadow's bounds registered as a hitbox.
@Test @MainActor func aShadowNeverHitsChangesNoLayoutAndPublishesNothing() throws {
    func tree(_ shadowed: Bool) -> some Element {
        VStack(spacing: 0) {
            if shadowed {
                square().accessibilityLabel("square").onTapGesture {}
                    .shadow(radius: px(10), x: px(10), y: px(10))
            } else {
                square().accessibilityLabel("square").onTapGesture {}
            }
            Color(.separator).frame(width: px(40), height: px(10))
        }
    }
    let plain = effectFrame(tree(false), accessibility: true)
    let shadowed = effectFrame(tree(true), accessibility: true)
    #expect(shadowed.hitboxes.map { gxDescribe(MUIBounds($0.bounds.scaled(by: 1))) }
            == plain.hitboxes.map { gxDescribe(MUIBounds($0.bounds.scaled(by: 1))) },
            "the same hitboxes")
    #expect(shadowed.finalizedScene().rects.map { gxDescribe($0.bounds) }
            == plain.finalizedScene().rects.map { gxDescribe($0.bounds) }, "the same layout")
    #expect(shadowed.axEmissions.count == plain.axEmissions.count
            && zip(shadowed.axEmissions, plain.axEmissions).allSatisfy { $0.geometry.frame == $1.geometry.frame },
            "the same accessibility records")
}

// MARK: - 3.22 (SH11)

/// **3.22** (SH11). A second shadow shadows the first: an inner shadow at
/// (0, 40) and an outer one at (40, 0) draw three images, one of them the
/// outer shadow of the inner shadow, at (40, 40) from the square. Mutation
/// **M3u**: shadow images are not leaves.
@Test @MainActor func aSecondShadowShadowsTheFirst() throws {
    let images = gxImages(effectFrame(square()
        .shadow(color: .separator, radius: px(0), x: px(0), y: px(40))
        .shadow(color: .textPrimary, radius: px(0), x: px(40), y: px(0))).finalizedScene())
    #expect(images.count == 3, "three shadows: \(images.map { gxDescribe($0.image.bounds) })")
    #expect(images.contains { $0.image.bounds.origin.x == 120 && $0.image.bounds.origin.y == 120 },
            "the shadow of the shadow at (120, 120): \(images.map { gxDescribe($0.image.bounds) })")
}

// MARK: - 3.23 (T10, T14)

/// **3.23** (T10, T14). A shadow inside a rotation or a scale has its offset
/// transformed: x 10 under a 90° turn falls 10 BELOW the turned bar; under
/// `scaleEffect(2)` it falls 20 to the right. Mutation **M3v**: the offset not
/// mapped.
@Test @MainActor func aShadowInsideARotationOrScaleHasItsOffsetTransformed() throws {
    let turned = gxImages(effectFrame(Color(.accent).frame(width: px(40), height: px(20))
        .shadow(color: .textPrimary, radius: px(0), x: px(10), y: px(0))
        .rotationEffect(.degrees(90))).finalizedScene())
    try #require(turned.count == 1, "one shadow")
    let t = turned[0].image.bounds
    // The bar turned about (100, 100): x 90…110, y 80…120; its shadow + (0, 10).
    #expect(abs(t.origin.x - 90) <= 1 && abs(t.origin.y - 90) <= 1 && abs(t.size.height - 40) <= 2,
            "below the turned bar: \(gxDescribe(t))")
    let scaled = gxImages(effectFrame(square(20).shadow(color: .textPrimary, radius: px(0), x: px(10), y: px(0))
        .scaleEffect(2)).finalizedScene())
    try #require(scaled.count == 1, "one shadow")
    // The square scaled about (100, 100): 80…120; its shadow + (20, 0).
    #expect(gxDescribe(scaled[0].image.bounds) == "(100.0, 80.0, 40.0×40.0)",
            "20 to the right: \(gxDescribe(scaled[0].image.bounds))")
}

// MARK: - 3.24 (N4–N6)

/// **3.24** (N4–N6). Colour, radius and offset animate: half-way through
/// radius 0 → 10, x 0 → 20 and `.textPrimary` → `.accent`, the shadow image
/// is offset 10 and padded by about 3 × 5 (sigma 5, not 10), and its centre
/// texel's colour lies between the two tokens'. Mutation **M3w**: the radius
/// snaps.
@Test @MainActor func shadowColourRadiusAndOffsetAnimate() throws {
    let h = TransitionHarness()
    func tree(_ on: Bool) -> some Element {
        square().shadow(color: on ? .accent : .textPrimary, radius: px(on ? 10 : 0), x: px(on ? 20 : 0), y: px(0))
    }
    h.frame(0, nil, tree(false), side: 200)
    h.frame(0, linear1, tree(true), side: 200)
    let images = gxImages(h.frame(0.5, nil, tree(true), side: 200).finalizedScene())
    try #require(images.count == 1, "one shadow")
    let b = images[0].image.bounds
    let pad = (b.size.width - 40) / 2
    #expect(pad >= 13 && pad <= 17, "sigma 5's padding, not 10's 30: \(pad) in \(gxDescribe(b))")
    #expect(abs(b.origin.x + pad - 90) <= 0.5, "offset 10: \(gxDescribe(b))")
    let texel = gxTexel(images[0].texture, Int(110 - b.origin.x), Int(100 - b.origin.y))
    let from = Theme.light[.textPrimary].toRgba(), to = Theme.light[.accent].toRgba()
    let blue = Double(texel[2]) / max(1, Double(texel[3]))
    #expect(blue > Double(from.b) + 0.05 && blue < Double(to.b) - 0.05,
            "blue between \(from.b) and \(to.b): \(blue) from \(texel)")
}

// MARK: - 3.26 (GX-J)

/// **3.26** (`GX-J`). A legacy shadow returns `Self` and shadows the whole
/// element: a bar's shadow is drawn before its background rect, and a box
/// holding a text casts two shadows (its background and its glyphs).
/// Mutation **M3y**: the legacy shadow ignored.
@Test @MainActor func aLegacyShadowReturnsSelfAndShadowsTheWholeElement() throws {
    let bar: ModifiedElement<Box<EmptyGroup>> = fxLegacyBar(40, 40)
        .shadow(color: .textPrimary, radius: px(0), x: px(10), y: px(10))
    let scene = effectFrame(bar).finalizedScene()
    #expect(runKinds(scene) == [.image, .rect], "shadow then the bar: \(runKinds(scene))")
    let images = gxImages(scene)
    try #require(images.count == 1 && scene.rects.count == 1, "one shadow, one bar")
    #expect(images[0].image.bounds.origin.x == scene.rects[0].bounds.origin.x + 10, "offset 10")
    let boxed = gxImages(effectFrame(Box { Text("Hi") }.frame(width: px(60), height: px(30)).background(.accent)
        .shadow(color: .textPrimary, radius: px(0), x: px(2), y: px(2))).finalizedScene())
    #expect(boxed.count == 2, "the background and the text: \(boxed.count)")
}

// MARK: - 3.27 (divergence 104)

/// **3.27** (divergence 104). A `MetalView` surface's shadow is its quad: its
/// pixels live on the GPU, so the silhouette is the whole 50 × 30 quad, solid,
/// offset (10, 10). Mutation **M3z**: the surface skipped.
@Test @MainActor func aMetalViewsShadowIsItsQuad() throws {
    let scene = effectFrame(GPUSurface(redraw: .onDemand) { _ in }.frame(width: px(50), height: px(30))
        .shadow(color: .textPrimary, radius: px(0), x: px(10), y: px(10))).finalizedScene()
    let images = gxImages(scene)
    try #require(images.count == 1 && scene.surfaces.count == 1, "one shadow, one quad")
    let quad = scene.surfaces[0].bounds
    #expect(images[0].image.bounds.origin.x == quad.origin.x + 10 && images[0].image.bounds.origin.y == quad.origin.y + 10
            && images[0].image.bounds.size.width == 50 && images[0].image.bounds.size.height == 30,
            "the quad, offset: \(gxDescribe(images[0].image.bounds)) for \(gxDescribe(quad))")
    #expect(gxTexel(images[0].texture, 25, 15)[3] == 255, "solid")
}

// MARK: - 3.28 (the looks demo)

/// **3.28** (spec §7). `looksDemoContent()` through a fake window shows the
/// paths-shadows-transforms section: at least two path images (coloured), at
/// least three shadow images (black), at least two transform records, and the
/// square's tap turns it 45° once the animation lands. Mutation **M3aa**: the
/// section left out of the composer.
@Test @MainActor func theLooksDemoShowsPathsShadowsAndTransforms() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platform) = try makeFakeWindow(device: device, size: 1400, startsDisplayLink: true) {
        looksDemoContent()
    }
    platform.simulateTick(timestamp: 100)
    let scene = window.lastScene
    let rasters = gxImages(scene).filter { $0.image.filterKind == ImageFilter.nearest.rawValue
        && !($0.texture.width == 4 && $0.texture.height == 4) }
    func isBlack(_ t: ImageTexture) -> Bool {
        stride(from: 0, to: t.pixels.count, by: 4).allSatisfy { t.pixels[$0] == 0 && t.pixels[$0 + 2] == 0 }
    }
    let shadows = rasters.filter { isBlack($0.texture) }.count
    let paths = rasters.count - shadows
    #expect(paths >= 2, "path images: \(paths)")
    #expect(shadows >= 3, "shadow images: \(shadows)")
    #expect(scene.transforms.count >= 2, "transform records: \(scene.transforms.count)")

    // The rotating square: the 60 × 60 tap target. Its centre is fixed under
    // any turn about its centre.
    let target = try #require(window.lastHitboxes.first {
        $0.handlers.gestures != nil && $0.bounds.size.width == px(60) && $0.bounds.size.height == px(60)
    }, "the square's tap registered")
    let centre = gxPoint(target.bounds.origin.x.value + 30, target.bounds.origin.y.value + 30)
    platform.simulateInput(.mouseDown(MouseEvent(position: centre)))
    platform.simulateInput(.mouseUp(MouseEvent(position: centre)))
    for tick in 1...30 { platform.simulateTick(timestamp: 100 + Double(tick) * 0.05) }
    let landed = window.lastScene
    let square = try #require(landed.rects.first { rect in
        rect.transformIndex > 0 && rect.bounds.size.width == 60 && rect.bounds.size.height == 60
    }, "the square carries a record after the tap")
    let record = landed.transforms[Int(square.transformIndex) - 1]
    #expect(abs(Double(record.a) - 0.5.squareRoot()) < 1e-3 && abs(Double(record.b) - 0.5.squareRoot()) < 1e-3,
            "turned 45°: a \(record.a) b \(record.b)")
}
