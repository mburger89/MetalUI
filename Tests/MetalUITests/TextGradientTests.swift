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

// MARK: - 5. concatenation

@MainActor private func interpolated(_ a: Text, _ b: Text) -> Text { Text("\(a)\(b)") }

/// **5 (`TG-C`, probe `TG5`).** The span is the union of the ink of every run that carries the same gradient: two runs that both
/// carry it are one group over both (equal to a rectangle over the union), a gradient run beside a plain-colour run is its own
/// box, and `g, green, g` is one group over all three. Mutation: one ink group per run (the opposite span).
@Test @MainActor func aConcatenatedGradientRunSpansTheRunsThatCarryIt() throws {
    let both = try render(interpolated(blocks(2).foregroundStyle(sweep), blocks(2).foregroundStyle(sweep)))
    try #require(both.frame.groupsMasked == 1, "two runs of one gradient are one group: \(both.frame.groupsMasked)")
    let union = try #require(inkBox(both.scene))
    let ref = try render(reference(sweep, union), renderer: both.renderer)
    for y in union.y..<(union.y + union.h) {
        for x in union.x..<(union.x + union.w) where pixel(both.pixels, x, y)[3] == 255 {
            let a = pixel(both.pixels, x, y), b = pixel(ref.pixels, x, y)
            #expect(zip(a, b).allSatisfy { abs($0 - $1) <= 1 }, "(\(x), \(y)): \(a) vs one rectangle over the union \(b)")
        }
    }

    let lone = try render(interpolated(blocks(2).foregroundStyle(pureRed), blocks(2).foregroundStyle(sweep)))
    try #require(lone.frame.groupsMasked == 1)
    let own = try #require(inkBox(lone.scene))
    #expect(own.x >= 78, "the group's box is the gradient run's alone: \(own)")
    let at = pixel(lone.pixels, own.x + 4, own.y + own.h / 2)
    #expect(at[0] > 200 && at[2] < 80, "the gradient run starts red at its own left edge: \(at)")

    let split = try render(Text("\(blocks(2).foregroundStyle(sweep))\(blocks(2).foregroundStyle(pureGreen))\(blocks(2).foregroundStyle(sweep))").font(size: 40))
    #expect(split.frame.groupsMasked == 1, "g, green, g shares one group: \(split.frame.groupsMasked)")
    let span = try #require(inkBox(split.scene))
    #expect(span.w > 200, "the group spans first to third run: \(span)")
}

// MARK: - 6. a colour below a gradient clears it

/// **6 (`TG-A`).** One storage: a colour written below a gradient (in the environment, or on the `Text` after its own gradient)
/// is that solid colour with no group. Mutations: the computed setter storing into a second field without clearing; resolution
/// order `environment ?? own`.
@Test @MainActor func aColourBelowAGradientClearsIt() throws {
    let env = try render(VStack(spacing: px(0)) { blocks(3).foregroundStyle(pureGreen) }.foregroundStyle(sweep))
    #expect(env.frame.groupsMasked == 0 && pixel(env.pixels, 40, 25) == [0, 255, 0, 255], "own colour over an environment gradient: \(pixel(env.pixels, 40, 25))")
    let below = try render(VStack(spacing: px(0)) { blocks(3) }.foregroundStyle(pureGreen).foregroundStyle(sweep))
    #expect(below.frame.groupsMasked == 0, "an environment colour below an environment gradient: \(below.frame.groupsMasked)")
    let own = try render(blocks(3).foregroundStyle(sweep).foregroundColor(pureGreen))
    #expect(own.frame.groupsMasked == 0 && pixel(own.pixels, 40, 25) == [0, 255, 0, 255], "a colour after the text's own gradient: \(pixel(own.pixels, 40, 25))")
    var values = EnvironmentValues()
    values.foregroundStorage = .gradient(.linear(sweep))
    values.foregroundStyle = .red
    #expect(values.foregroundStorage == .color(.red), "writing the colour replaced the gradient")
}

// MARK: - 7. a shadow

/// **7 (`TG-C`, probe `TG6`).** A hard shadow of a gradient text is the shadow colour: the pixels right of the glyphs are
/// opaque black, not gradient. Mutation: `needsGPU` ignoring marks (a CPU box shadow of the gradient's rect).
@Test @MainActor func aShadowOfGradientTextIsTheShadowColour() throws {
    let r = try render(blocks(4).foregroundStyle(sweep).shadow(color: .black, radius: px(0), x: px(8), y: px(0)))
    let plain = try render(blocks(4).foregroundStyle(sweep), renderer: r.renderer)
    let ink = try #require(inkBox(plain.scene))
    let right = pixel(r.pixels, ink.x + ink.w + 4, ink.y + ink.h / 2)
    #expect(right == [0, 0, 0, 255], "shadow-only pixel is black: \(right)")
    let above = pixel(r.pixels, ink.x + ink.w / 2, ink.y - 3)
    #expect(above[3] == 0, "no box shadow of the gradient rect above the glyphs: \(above)")
    let left = pixel(r.pixels, ink.x + 4, ink.y + ink.h / 2)
    #expect(left[0] > 150 && left[2] < 110, "the glyphs still read red at the left: \(left)")
}

// MARK: - 8. radial

/// **8 (`TG-C`, probe `TG8`).** A radial gradient text is centred on the ink: the pixel at the ink's centre is the first stop
/// and the gradient equals a rectangle's radial fill over the ink box. Mutation: `axis(in:)` given the layout box.
@Test @MainActor func aRadialGradientTextCentresOnItsInk() throws {
    let radial = RadialGradient(colors: [pureRed, pureBlue], center: .center, startRadius: px(0), endRadius: px(60))
    let r = try render(Text(" \u{2588}\u{2588}\u{2588}").font(size: 40).foregroundStyle(radial))
    let box = try #require(inkBox(r.scene))
    let ref = try render(reference(radial, box), renderer: r.renderer)
    var compared = 0
    for y in box.y..<(box.y + box.h) {
        for x in box.x..<(box.x + box.w) where pixel(r.pixels, x, y)[3] == 255 {
            let a = pixel(r.pixels, x, y), b = pixel(ref.pixels, x, y)
            #expect(zip(a, b).allSatisfy { abs($0 - $1) <= 1 }, "(\(x), \(y)): \(a) vs \(b)")
            compared += 1
        }
    }
    try #require(compared > 1000)
    let centre = pixel(r.pixels, box.x + box.w / 2, box.y + box.h / 2)
    #expect(centre[0] > 230 && centre[2] < 30, "the centre of the ink is the first stop: \(centre)")
}

// MARK: - 9, 10. a level over a gradient parent; the default fill of a shape

/// **9 (`HY-`, `TG-B`, probe `TG9`/`P14`).** `.secondary` over a gradient parent keeps the gradient at half alpha, on text (the
/// text's own level and a level written in the environment) and on a `Rectangle`. Mutation: the `HierarchicalShapeStyle`
/// gradient arm returns the representative colour.
@Test @MainActor func aLevelOverAGradientParentKeepsTheGradient() throws {
    func ends(_ r: Rendered, _ y: Int, _ x0: Int, _ x1: Int) -> ([Int], [Int]) { (pixel(r.pixels, x0, y), pixel(r.pixels, x1, y)) }
    let text = try render(VStack(spacing: px(0)) { blocks(4).foregroundStyle(.secondary) }.foregroundStyle(sweep))
    let box = try #require(inkBox(text.scene))
    let (l, rgt) = ends(text, box.y + box.h / 2, box.x + 4, box.x + box.w - 5)
    #expect(abs(l[3] - 128) <= 2 && abs(rgt[3] - 128) <= 2, "half alpha at both ends: \(l) \(rgt)")
    #expect(l[0] > rgt[0] + 40 && rgt[2] > l[2] + 40, "red at the left, blue at the right: \(l) \(rgt)")
    let shape = try render(VStack(spacing: px(0)) { Rectangle().frame(width: px(100), height: px(40)) }
        .foregroundStyle(.secondary).foregroundStyle(sweep))
    let (sl, sr) = ends(shape, 20, 4, 95)
    #expect(abs(sl[3] - 128) <= 2 && abs(sr[3] - 128) <= 2 && sl[0] > sr[0] + 40, "a Rectangle: \(sl) \(sr)")
}

/// **10 (`TG-C`, probe `TG14`/`P14c`).** A bare shape's default fill under a gradient `foregroundStyle` is that gradient (equal to
/// `fill`). Mutation: `paintShapeFill` ignoring `foregroundStorage`.
@Test @MainActor func aShapesDefaultFillTakesAGradientForegroundStyle() throws {
    let a = try render(VStack(spacing: px(0)) { Rectangle().frame(width: px(100), height: px(40)) }.foregroundStyle(sweep))
    let b = try render(VStack(spacing: px(0)) { Rectangle().fill(sweep).frame(width: px(100), height: px(40)) }, renderer: a.renderer)
    #expect(differing(a.pixels, b.pixels) == 0, "equal to the explicit fill")
    #expect(pixel(a.pixels, 4, 20)[2] < pixel(a.pixels, 95, 20)[2], "and a gradient, not a colour")
}

// MARK: - 11, 12, 13. one group; steady; oversize

/// **11 (`TG-C`).** A gradient text is one masked group whose mask scene holds every glyph and whose root holds none; a colour
/// text is none. Mutation: the plain glyphs emitted as well.
@Test @MainActor func aGradientTextIsOneMaskedGroupAndAColourTextIsNone() throws {
    let g = try render(blocks(4).foregroundStyle(sweep))
    #expect(g.frame.groupsMasked == 1 && g.scene.glyphs.isEmpty, "root glyphs \(g.scene.glyphs.count)")
    #expect(g.scene.groupMasks.compactMap { $0 }.first?.glyphs.count == 4, "four mask glyphs")
    #expect(g.scene.groupScenes.first?.glyphs.isEmpty == true, "the content holds none")
    let c = try render(blocks(4).foregroundStyle(pureRed), renderer: g.renderer)
    #expect(c.frame.groupsMasked == 0 && c.scene.glyphs.count == 4 && c.scene.groups.isEmpty)
}

/// **12 (`TG-C`).** A steady gradient text frame makes no texture and rasters nothing: the second frame runs one group pass and
/// one mask pass, the pool hands back what the first released, and the gradient is a cache hit. Mutation: a per-frame value
/// (the group token) in the gradient's raster key; the mask scratch not released (CM M15).
@Test @MainActor func aSteadyGradientTextFrameMakesNoTextureAndRastersNothing() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let renderer = try Renderer(device: device)
    let h = TransitionHarness()
    func draw(_ t: Double) throws -> [UInt8] {
        let frame = h.frame(t, nil, boxed(blocks(4).foregroundStyle(sweep)), side: 200)
        renderer.upload(frame.glyphAtlas)
        return try renderer.renderOffscreen(frame.finalizedScene(), size: size200)
    }
    let first = try draw(0)
    try #require(h.store.rasters.lastTexturesMade > 0, "set up: the first frame rastered the gradient")
    let second = try draw(1)
    #expect(renderer.lastGroupPasses == 1 && renderer.lastMaskPasses == 1, "\(renderer.lastGroupPasses) \(renderer.lastMaskPasses)")
    #expect(renderer.lastGroupTexturesMade == 0, "no new target: \(renderer.lastGroupTexturesMade)")
    #expect(h.store.rasters.lastTexturesMade == 0, "no raster: \(h.store.rasters.lastTexturesMade)")
    #expect(first == second)
}

/// **13 (`TG-E`).** A gradient text whose group is over 8192 device pixels draws its ink in the first stop, by name: no group, no
/// image, glyphs in the root scene at the first stop's colour. Mutation: the oversize branch inserting the children (a gradient box).
@Test @MainActor func anOversizeGradientTextDrawsItsInkByName() throws {
    let h = TransitionHarness()
    let wide = Text(String(repeating: "\u{2588}", count: 60)).font(size: 8).foregroundStyle(sweep)
    let frame = h.frame(0, nil, VStack(alignment: .leading, spacing: px(0)) { wide }
        .frame(width: px(300), height: px(300), alignment: .topLeading), side: 300, scaleFactor: 40)
    let scene = frame.finalizedScene()
    #expect(frame.masksFlattenedOversize == 1 && frame.groupsMasked == 0, "\(frame.masksFlattenedOversize) \(frame.groupsMasked)")
    #expect(scene.groups.isEmpty && scene.images.isEmpty, "no group and no gradient box")
    #expect(scene.glyphs.count == 60, "the ink: \(scene.glyphs.count)")
    let first = pureRed.resolved(theme: Theme.light, scheme: .light)
    #expect(scene.glyphs.allSatisfy { abs($0.color.h - first.h) < 0.01 && $0.color.a > 0.99 }, "the first stop's colour")
}

// MARK: - 14 (translation), 16, 17, 18

/// **16 (`TG-D`).** A gradient text under a rotation turns every glyph of its mask with the content: after a quarter turn the
/// gradient runs top to bottom and the coverage equals the solid text turned the same. Mutation: `RenderEffect.apply` mapping
/// only the first element of a mask.
@Test @MainActor func aGradientTextUnderARotationTurnsEveryGlyphMask() throws {
    let turned = try render(blocks(3).foregroundStyle(sweep).rotationEffect(.degrees(90)))
    let solid = try render(blocks(3).foregroundStyle(pureRed).rotationEffect(.degrees(90)), renderer: turned.renderer)
    var worst = 0
    for i in stride(from: 3, to: turned.pixels.count, by: 4) { worst = max(worst, abs(Int(turned.pixels[i]) - Int(solid.pixels[i]))) }
    #expect(worst <= 2, "the solid text's coverage, turned: \(worst)")
    let rows = (0..<200).filter { y in (0..<200).contains { pixel(turned.pixels, $0, y)[3] == 255 } }
    let top = try #require(rows.first), bottom = try #require(rows.last)
    let x = (0..<200).first { pixel(turned.pixels, $0, (top + bottom) / 2)[3] == 255 } ?? 0
    let up = pixel(turned.pixels, x + 6, top + 6), down = pixel(turned.pixels, x + 6, bottom - 6)
    #expect(up[0] > 180 && down[2] > 180, "red at the top, blue at the bottom: \(up) \(down)")
    // The mask holds every glyph, mapped (a record each): all three carry a transform index.
    let mask = try #require(turned.scene.groupMasks.compactMap { $0 }.first)
    #expect(mask.glyphs.count == 3 && mask.glyphs.allSatisfy { $0.transform != 0 }, "every mask glyph is turned")
}

/// **16b (`TG-D`).** A gradient text inside crossing rounded clips across an offset: both corners are cut, the overlap draws.
/// (Green under a first-element-only `cutToEntryClip`: the ink elements' own cut is invisible next to the content's clip; see the
/// record.)
@Test @MainActor func aGradientTextCrossingAFlatteningEntryClipIsCutByBothClips() throws {
    let inner = VStack(alignment: .leading, spacing: px(0)) { blocks(2).foregroundStyle(sweep) }
        .frame(width: px(100), height: px(100), alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: px(30)))
        .offset(x: px(50), y: px(50))
        .frame(width: px(100), height: px(100), alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: px(30)))
    let r = try render(inner)
    #expect(pixel(r.pixels, 52, 55)[3] == 0, "the inner's corner is clear: \(pixel(r.pixels, 52, 55))")
    #expect(pixel(r.pixels, 98, 98)[3] == 0, "the outer's corner is clear: \(pixel(r.pixels, 98, 98))")
    #expect(pixel(r.pixels, 80, 80)[3] == 255, "the overlap draws: \(pixel(r.pixels, 80, 80))")
}

@MainActor private func ghostUnit(_ shown: Bool) -> some Element {
    Column {
        Stack {
            Box().frame(width: px(200), height: px(100))
            if shown { blocks(3).foregroundStyle(sweep) }
        }
    }
}

/// **17 (`TG-D`).** A removed gradient text fades its ghost still masked, by every glyph: the half-way scene is one masked group
/// whose mask scene holds all three glyphs and whose content is faded. Mutation: the ghost reads only the first mask primitive.
@Test @MainActor func aRemovedGradientTextFadesItsGhostMasked() throws {
    let h = TransitionHarness()
    let rest = h.frame(0, nil, ghostUnit(true)).finalizedScene()
    try #require(rest.groups.count == 1 && rest.groupMasks[0] != nil, "set up: a masked group at rest")
    h.frame(0, Animation.linear(duration: 1), ghostUnit(false))
    let mid = h.frame(0.5, nil, ghostUnit(false)).finalizedScene()
    try #require(mid.groups.count == 1, "the ghost is one group: \(mid.groups.count)")
    #expect(mid.groupMasks[0]?.glyphs.count == 3, "masked by all three glyphs: \(mid.groupMasks[0]?.glyphs.count ?? -1)")
    #expect(mid.groupScenes[0].images.allSatisfy { $0.opacity < 1 }, "faded")
}

/// **18 (`TG-D`).** A drag preview of a gradient text keeps every glyph of its mask, each cut by the preview's mask. Mutation:
/// `CapturedPrimitive.replayed` handling only the first mask element (the others keep their unbounded content mask).
@Test @MainActor func aDragPreviewOfGradientTextKeepsEveryGlyphMask() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platform) = try makeFakeWindow(device: device, size: 400, startsDisplayLink: true) {
        Row {
            blocks(3).foregroundStyle(sweep).draggable("s")
            Box().frame(width: px(100), height: px(100))
        }
    }
    defer { withExtendedLifetime(window) {} }
    platform.simulateResize(to: Size(width: px(400), height: px(200)))
    window.drawFrameIfNeeded()
    func pt(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: px(x), y: px(y)) }
    platform.simulateInput(.mouseDown(MouseEvent(position: pt(40, 20))))
    platform.simulateInput(.mouseDragged(MouseEvent(position: pt(41, 20))))
    platform.simulateInput(.mouseDragged(MouseEvent(position: pt(90, 20))))
    window.drawFrameIfNeeded()
    let scene = window.lastScene
    try #require(scene.groups.count == 2, "the source and its preview: \(scene.groups.count)")
    let preview = try #require(scene.groupMasks[1], "the preview is masked")
    #expect(preview.glyphs.count == 3, "all glyphs: \(preview.glyphs.count)")
    #expect(preview.glyphs.allSatisfy { $0.contentMask.size.width < 10_000 }, "each cut by the preview's mask: \(preview.glyphs.map { $0.contentMask.size.width })")
    platform.simulateInput(.mouseUp(MouseEvent(position: pt(90, 20))))
}

// MARK: - 19. a decoration is part of the ink

/// **19 (`TG-C`, probe `TG10`).** An underline that names no colour of its own follows the gradient: upper half blocks leave the
/// underline row clear of the glyphs, and it reads red at the left and blue at the right, in the same one group. An underline with
/// its own colour stays that colour. Mutation: the underline drawn in the representative colour.
@Test @MainActor func aGradientUnderlineIsPartOfTheInk() throws {
    let text = Text(String(repeating: "\u{2580}", count: 4)).font(size: 40)
    let r = try render(text.underline().foregroundStyle(sweep))
    #expect(r.frame.groupsMasked == 1, "glyphs and line are one group: \(r.frame.groupsMasked)")
    let rows = (0..<200).filter { y in (0..<200).contains { pixel(r.pixels, $0, y)[3] == 255 } }
    let line = try #require(rows.last, "the underline is the last full row")
    let xs = (0..<200).filter { pixel(r.pixels, $0, line)[3] == 255 }
    let l = pixel(r.pixels, xs.first! + 4, line), rt = pixel(r.pixels, xs.last! - 4, line)
    #expect(l[0] > rt[0] + 80 && rt[2] > l[2] + 80, "the line varies along the gradient: \(l) \(rt)")
    let own = try render(text.underline(color: pureGreen).foregroundStyle(sweep), renderer: r.renderer)
    let g = pixel(own.pixels, xs.first! + 4, line)
    #expect(g == [0, 255, 0, 255], "an own colour stays: \(g)")
}

// MARK: - 20. the residue of 975

/// **20 (divergence 975, pinned wrong on purpose).** A material as a text's `foregroundStyle` is still its flat tint, with no
/// group. Replaces `aGradientForegroundStylePaintsItsFirstStop`'s text half.
@Test @MainActor func aMaterialForegroundStyleOnTextStaysItsFlatTint() throws {
    let r = try render(blocks(3).foregroundStyle(Material.regularMaterial))
    let tint = Material.regularMaterial.color
    #expect(r.frame.groupsMasked == 0 && r.scene.glyphs.count == 3, "plain glyphs: \(r.frame.groupsMasked)")
    #expect(r.scene.glyphs.allSatisfy { abs($0.color.l - tint.resolved(theme: Theme.light, scheme: .light).l) < 0.01 }, "the flat tint")
}
