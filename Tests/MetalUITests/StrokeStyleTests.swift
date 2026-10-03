import Testing
import MetalUICore
import MetalUILayout
import MetalUIScene
@testable import MetalUI

// Paths, shadows and transforms, lane 3 — fill and stroke styles (ruling
// `GX-E`; spec `docs/superpowers/specs/2026-10-02-paths-shadows-transforms-design.md`
// §8, tests 3.7–3.8). SwiftUI's side is
// `docs/probes/swiftui-paths-shadows-transforms.swift`, arms PA2, ST1–ST10.
// The stroker's own geometry (caps, joins, the miter limit, dashes) is pinned
// in `MetalUIPathTests` (1.20–1.25); these arms pin what `MetalUI` routes to it.

// MARK: - 3.7 (PA2)

/// **3.7** (PA2). `.fill(_:style:)` reaches the rasterizer: a ring of two
/// same-direction squares filled even-odd is empty at its centre and solid in
/// its band; filled nonzero (the default) it is solid at its centre. Mutation
/// **M3g**: `ShapeView` drops the `FillStyle`.
@Test @MainActor func evenOddFillStyleEmptiesTheRing() throws {
    let ring = Path { p in
        p.addRect(gxRect(0, 0, 100, 100))
        p.addRect(gxRect(25, 25, 50, 50))
    }
    func alphas(_ style: FillStyle?) throws -> (centre: Int, band: Int) {
        let view = style.map { ring.fill(.accent, style: $0) } ?? ring.fill(.accent)
        let images = gxImages(effectFrame(view.frame(width: Pixels(100), height: Pixels(100))).finalizedScene())
        try #require(images.count == 1, "one image")
        return (gxAlpha(images[0], 100, 100), gxAlpha(images[0], 60, 60))
    }
    let evenOdd = try alphas(FillStyle(eoFill: true))
    let nonZero = try alphas(nil)
    #expect(evenOdd.centre == 0 && evenOdd.band == 255, "even-odd: \(evenOdd)")
    #expect(nonZero.centre == 255 && nonZero.band == 255, "nonzero: \(nonZero)")
    // A built-in filled without antialiasing goes through the CPU rasterizer
    // (`paintShapeFill`'s branch): one image whose alphas are only 0 and 255.
    // Mutation **MV8**: the non-antialiased branch disabled.
    let aliased = gxImages(effectFrame(Circle().fill(.accent, style: FillStyle(antialiased: false))
        .frame(width: Pixels(40), height: Pixels(40))).finalizedScene())
    try #require(aliased.count == 1, "one image: \(aliased.count)")
    let alphas = Set(stride(from: 3, to: aliased[0].texture.pixels.count, by: 4).map { aliased[0].texture.pixels[$0] })
    #expect(alphas == [0, 255], "only 0 and 255: \(alphas.sorted())")
}

// MARK: - 3.8 (GX-E)

/// **3.8** (`GX-E`). A round-joined `Rectangle().stroke` goes through the
/// stroker (one image, no rect); a plain `stroke(lineWidth: 10)` keeps the
/// SDF band (one `MUIRect` with border 10, no image). A dashed stroke goes
/// through the stroker too. Mutation **M3h**: every stroke rasterized.
@Test @MainActor func aJoinOrDashGoesThroughTheStrokerAndAPlainWidthKeepsTheBand() {
    let rounded = effectFrame(Rectangle()
        .stroke(.accent, style: StrokeStyle(lineWidth: Pixels(10), lineJoin: .round))
        .frame(width: Pixels(80), height: Pixels(60))).finalizedScene()
    #expect(rounded.images.count == 1 && rounded.rects.isEmpty,
            "round join: \(rounded.images.count) images, \(rounded.rects.count) rects")
    let dashed = effectFrame(Rectangle()
        .stroke(.accent, style: StrokeStyle(lineWidth: Pixels(4), dash: [Pixels(10), Pixels(5)]))
        .frame(width: Pixels(80), height: Pixels(60))).finalizedScene()
    #expect(dashed.images.count == 1 && dashed.rects.isEmpty,
            "dashed: \(dashed.images.count) images, \(dashed.rects.count) rects")
    let plain = effectFrame(Rectangle().stroke(.accent, lineWidth: Pixels(10))
        .frame(width: Pixels(80), height: Pixels(60))).finalizedScene()
    #expect(plain.rects.count == 1 && plain.images.isEmpty && plain.rects.first?.borderWidths.top == 10,
            "plain width: \(plain.rects.count) rects, \(plain.images.count) images")
    let plainStyle = effectFrame(Rectangle().stroke(.accent, style: StrokeStyle(lineWidth: Pixels(10), lineCap: .round))
        .frame(width: Pixels(80), height: Pixels(60))).finalizedScene()
    #expect(plainStyle.rects.count == 1 && plainStyle.images.isEmpty,
            "a cap alone keeps the band (a closed outline has no ends)")
}
