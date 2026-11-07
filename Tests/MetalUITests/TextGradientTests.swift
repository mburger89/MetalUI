import Testing
import Metal
import MetalUICore
import MetalUILayout
import MetalUIScene
@testable import MetalUI
@testable import MetalUIRender

// R4-5 PR D (ruling prefix `TG-`, record 221; probe `docs/probes/swiftui-text-gradient.swift`): a gradient `foregroundStyle`
// on text paints the gradient across the glyphs' ink. The glyph run is the mask of one offscreen group and the gradient
// raster is its content (`CM-A`'s destination-in pass, no shader line moves). The span is the union of the ink of every run
// that carries the gradient, decorations included (probes `TG1`..`TG5`, `TG10`). Every test renders through the Metal
// renderer at 200 x 200, scale 1, over a transparent target; U+2588 FULL BLOCK at 40 pt is the glyph (a solid interior).

private func px(_ v: Float) -> Pixels { Pixels(v) }
private let pureRed = Color(Hsla(h: 0, s: 1, l: 0.5, a: 1))
private let pureBlue = Color(Hsla(h: 2.0 / 3.0, s: 1, l: 0.5, a: 1))
private let pureGreen = Color(Hsla(h: 1.0 / 3.0, s: 1, l: 0.5, a: 1))
private let sweep = LinearGradient(colors: [pureRed, pureBlue], startPoint: .leading, endPoint: .trailing)
private let size200 = Size(width: DevicePixels(200), height: DevicePixels(200))

/// (r, g, b, a) of a BGRA offscreen render.
private func pixel(_ pixels: [UInt8], _ x: Int, _ y: Int) -> [Int] {
    let i = (y * 200 + x) * 4
    return [Int(pixels[i + 2]), Int(pixels[i + 1]), Int(pixels[i]), Int(pixels[i + 3])]
}

private struct Rendered {
    var pixels: [UInt8]
    var frame: Frame
    var scene: Scene
    var renderer: Renderer
}

/// `content` at the top-left of a 200 x 200 frame, laid out, painted and drawn by `renderer` (a new one by default).
@MainActor private func render<E: Element>(_ content: E, renderer given: Renderer? = nil,
                                                                  harness: TransitionHarness? = nil,
                                                                  t: Double = 0) throws -> Rendered {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let renderer = try given ?? Renderer(device: device)
    let frame = (harness ?? TransitionHarness()).frame(t, nil, boxed(content), side: 200)
    renderer.upload(frame.glyphAtlas)
    let scene = frame.finalizedScene()
    return Rendered(pixels: try renderer.renderOffscreen(scene, size: size200), frame: frame, scene: scene, renderer: renderer)
}

@MainActor private func boxed<E: Element>(_ content: E) -> some Element & ProposalElementGroup {
    VStack(alignment: .leading, spacing: px(0)) { content }
        .frame(width: px(200), height: px(200), alignment: .topLeading)
}

@MainActor private func blocks(_ count: Int) -> Text {
    Text(String(repeating: "\u{2588}", count: count)).font(size: 40)
}

/// The union of the glyph quads of the first group's mask scene: the ink box `drawGradientInk` spans, in device pixels.
private func inkBox(_ scene: Scene) -> (x: Int, y: Int, w: Int, h: Int)? {
    guard let mask = scene.groupMasks.compactMap({ $0 }).first else { return nil }
    var x0 = Float.infinity, y0 = Float.infinity, x1 = -Float.infinity, y1 = -Float.infinity
    for g in mask.glyphs {
        x0 = min(x0, g.bounds.origin.x); y0 = min(y0, g.bounds.origin.y)
        x1 = max(x1, g.bounds.origin.x + g.bounds.size.width); y1 = max(y1, g.bounds.origin.y + g.bounds.size.height)
    }
    guard x1 > x0 else { return nil }
    return (Int(x0), Int(y0), Int(x1 - x0), Int(y1 - y0))
}

/// A `Rectangle` filled with `style` over the device box `box` (scale 1), in the same 200 x 200 frame.
@MainActor private func reference<S: ShapeStyle>(_ style: S, _ box: (x: Int, y: Int, w: Int, h: Int)) -> some Element & ProposalElementGroup {
    Rectangle().fill(style).frame(width: px(Float(box.w)), height: px(Float(box.h)))
        .padding(Edges(top: px(Float(box.y)), right: px(0), bottom: px(0), left: px(Float(box.x))))
}

// MARK: - 1. the gradient across the ink

/// **1 (`TG-C`, probes `TG0`..`TG3`).** `Text("████").foregroundStyle(g)` paints the gradient across the glyphs' ink: at every
/// pixel the glyphs cover fully its colour equals a `Rectangle` filled with the same gradient over the ink box (within 1/255),
/// and the left column differs from the right. Mutations: `Text.foregroundStyle<S>` back to `representativeColor` (both
/// columns the first stop); the rect source the layout box instead of the ink.
@Test @MainActor func aGradientTextPaintsTheGradientAcrossItsInk() throws {
    let text = try render(blocks(4).foregroundStyle(sweep))
    let box = try #require(inkBox(text.scene), "set up: a gradient text is one masked group with glyphs in its mask")
    let rect = try render(reference(sweep, box), renderer: text.renderer)
    var compared = 0
    for y in box.y..<(box.y + box.h) {
        for x in box.x..<(box.x + box.w) where pixel(text.pixels, x, y)[3] == 255 {
            let a = pixel(text.pixels, x, y), b = pixel(rect.pixels, x, y)
            #expect(zip(a, b).allSatisfy { abs($0 - $1) <= 1 }, "(\(x), \(y)): text \(a) rectangle \(b)")
            compared += 1
        }
    }
    try #require(compared > 1000, "set up: the interior was compared (\(compared) pixels)")
    let left = pixel(text.pixels, box.x + 4, box.y + box.h / 2), right = pixel(text.pixels, box.x + box.w - 5, box.y + box.h / 2)
    #expect(left[0] > 200 && left[2] < 50, "the left of the ink is red-ish: \(left)")
    #expect(right[2] > 200 && right[0] < 50, "the right of the ink is blue-ish: \(right)")
}

/// The pixels where `a` and `b` (same size) differ by more than `tolerance` in any channel.
private func differing(_ a: [UInt8], _ b: [UInt8], tolerance: Int = 1) -> Int {
    var n = 0
    for i in stride(from: 0, to: a.count, by: 4) where (0..<4).contains(where: { abs(Int(a[i + $0]) - Int(b[i + $0])) > tolerance }) { n += 1 }
    return n
}

// MARK: - 2. the coverage is the solid text's

/// **2 (`TG-C`).** A gradient text's alpha equals the same text in a plain colour at every pixel (within 1): the mask is the
/// glyph pass's own coverage, so the gradient text is no thinner or fatter than a solid one. Mutations: the mask pipeline's
/// destination factor `.one` (CM M24's spelling: the content is not multiplied); the ink glyphs carrying the first stop's alpha.
@Test @MainActor func aGradientTextsCoverageIsTheSolidTexts() throws {
    let gradient = try render(blocks(4).foregroundStyle(sweep))
    let solid = try render(blocks(4).foregroundStyle(pureRed), renderer: gradient.renderer)
    var covered = 0, worst = 0
    for i in stride(from: 3, to: gradient.pixels.count, by: 4) {
        worst = max(worst, abs(Int(gradient.pixels[i]) - Int(solid.pixels[i])))
        if solid.pixels[i] == 255 { covered += 1 }
    }
    try #require(covered > 4000, "set up: the solid text covers \(covered) pixels")
    #expect(worst <= 1, "the same coverage: worst alpha difference \(worst)")
}

// MARK: - 3. an opacity fades once

/// **3 (`TG-C`, probe `TG7`).** A faded gradient text fades once: the interior reads alpha .5 (not .25), and its colours are
/// the unfaded gradient's. Mutation: the ink glyphs' colour multiplied by `activeOpacity` (the fade applied to the mask as well).
@Test @MainActor func aFadedGradientTextFadesOnce() throws {
    let faded = try render(blocks(4).foregroundStyle(sweep).opacity(0.5))
    let full = try render(blocks(4).foregroundStyle(sweep), renderer: faded.renderer)
    let box = try #require(inkBox(full.scene))
    let mid = (box.x + box.w / 2, box.y + box.h / 2)
    let f = pixel(faded.pixels, mid.0, mid.1), u = pixel(full.pixels, mid.0, mid.1)
    #expect(abs(f[3] - 128) <= 1, "alpha .5 once: \(f)")
    // The target is premultiplied: undo the half alpha before comparing colours.
    let straight = f.prefix(3).map { f[3] == 0 ? 0 : $0 * 255 / f[3] }
    #expect(zip(straight, u.prefix(3)).allSatisfy { abs($0 - $1) <= 4 }, "the colour is the unfaded gradient's: \(f) vs \(u)")
}

// MARK: - 4. the span is the Text, not the container; a wrapped text is one span

/// **4 (`TG-C`, probes `TG4`, `TG2`).** A container's gradient spans each `Text` separately (the short text's right edge is blue,
/// not a third of the way), and a wrapped text is one span over both lines (the second, shorter line ends at the middle, where
/// per line it would be blue). Mutation: one rect per line box instead of the union.
@Test @MainActor func aGradientSpansEachTextNotTheContainer() throws {
    let r = try render(VStack(alignment: .leading, spacing: px(0)) { blocks(2); blocks(6) }.foregroundStyle(sweep))
    let masks = r.scene.groupMasks.compactMap { $0 }
    try #require(masks.count == 2, "one masked group per Text: \(masks.count)")
    // The short text's right edge: inside its own box the gradient has reached blue.
    let short = try #require(inkBox(r.scene))
    let edge = pixel(r.pixels, short.x + short.w - 6, short.y + short.h / 2)
    #expect(edge[2] > 200 && edge[0] < 60, "the short text ends blue: \(edge)")
}

@Test @MainActor func aWrappedGradientTextSpansBothLines() throws {
    let wrapped = Text("\u{2588}\u{2588}\u{2588}\u{2588} \u{2588}\u{2588}").font(size: 40).foregroundStyle(sweep)
    let r = try render(wrapped.frame(width: px(200)))
    let box = try #require(inkBox(r.scene), "set up: one masked group")
    try #require(r.scene.groupMasks.compactMap { $0 }.count == 1)
    try #require(box.h > 80, "set up: two lines: \(box)")
    // The second line is two blocks wide: its right edge is at the middle of the one span, not at blue.
    let rect = try render(reference(sweep, box), renderer: r.renderer)
    let lineTwo = pixel(r.pixels, box.x + 76, box.y + box.h - 14)
    try #require(lineTwo[3] == 255, "set up: line two is inked there: \(lineTwo)")
    #expect(lineTwo[2] < 230, "line two ends mid-gradient, not blue: \(lineTwo)")
    for y in [box.y + 10, box.y + box.h - 10] {
        for x in box.x + 2..<box.x + 78 where pixel(r.pixels, x, y)[3] == 255 {
            let a = pixel(r.pixels, x, y), b = pixel(rect.pixels, x, y)
            #expect(zip(a, b).allSatisfy { abs($0 - $1) <= 1 }, "(\(x), \(y)): \(a) vs the rectangle \(b)")
        }
    }
}
