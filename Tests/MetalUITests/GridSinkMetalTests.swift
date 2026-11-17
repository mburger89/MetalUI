import Testing
import Foundation
import Metal
import MetalUICore
import MetalUIPlatform
import MetalUIScene
import MetalUIShaderTypes
import MetalUIDemoContent
@testable import MetalUI
@testable import MetalUIRender

// Terminal phase 5.1 (`TRM-AU`...`TRM-AX`, record 347): the grid sink on Metal. A real `Window` over `FakePlatformWindow`
// (a real `MetalWindowRenderer` into a `.shared` texture the test reads back, as `DrawTextMetalTests` does). The
// surface's draw calls `fillRect` and `drawGlyph` on the frame's sink; the renderer runs its one load-op pass per
// surface. Colours are chosen with `h`, `s`, `l` that round-trip exactly (primaries, black, white, mid grey),
// so "exact" means equal bytes. No test sleeps.

@MainActor private final class Plan {
    var draw: @MainActor (SurfaceTextSink) -> Void = { _ in }
    var clears = true
    var calls = 0
}

private func hsla(_ h: Float, _ s: Float, _ l: Float, _ a: Float = 1) -> MUIHsla { MUIHsla(h: h, s: s, l: l, a: a) }
private let red = hsla(0, 1, 0.5), green = hsla(1.0 / 3, 1, 0.5), blue = hsla(2.0 / 3, 1, 0.5)
private let white = hsla(0, 0, 1), black = hsla(0, 0, 0)

private func box(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> MUIBounds {
    MUIBounds(origin: MUIPoint(x: x, y: y), size: MUISize(width: w, height: h))
}

/// A window whose one `.continuous` surface fills it and runs `plan.draw` on the frame's sink every frame.
@MainActor private func gridWindow(_ plan: Plan, side: Int = 32, scale: Float = 1) throws
    -> (Window, FakePlatformWindow) {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let extent = Pixels(Float(side) / scale)
    let (window, platform) = try makeFakeWindow(device: device, size: side) {
        GPUSurface(redraw: .continuous) { ctx in
            plan.calls += 1
            if plan.clears && ctx.isNewTarget { ctx.clear(red: 0, green: 0, blue: 0, alpha: 1) }
            guard let sink = (ctx as? any SurfaceTextSinkProviding)?.textSink else {
                Issue.record("the context has no sink"); return
            }
            plan.draw(sink)
        }
        .frame(width: extent, height: extent)
    }
    if scale != 1 {
        platform.scaleFactor = scale
        platform.fakeSurface.scaleFactor = scale
        platform.simulateResize(to: Size(width: extent, height: extent))
    }
    return (window, platform)
}

private func bgra(_ pixels: [UInt8], _ x: Int, _ y: Int, side: Int) -> [Int] {
    let i = (y * side + x) * 4
    return [Int(pixels[i + 2]), Int(pixels[i + 1]), Int(pixels[i]), Int(pixels[i + 3])]
}


/// A synthetic 6 x 6 glyph (a fully covered ring), so the tests need no font: `sprite(at:color:sink:)` packs it
/// in the sink's atlas and returns its record.
@MainActor private struct Synthetic {
    static let side = 6
    func sprite(at origin: (Float, Float), color: MUIHsla, sink: SurfaceTextSink) -> MUIGlyph {
        let key = GlyphKey(font: FontKey(resolvedPostScriptName: "Test.Ring", size: 6, variations: [],
                                         matrix: FontKey.Matrix(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)),
                           glyph: 1, size: 6, subpixelVariant: 0, scaleFactor: 1)
        var bytes = [UInt8](repeating: 0, count: Self.side * Self.side)
        for y in 0..<Self.side { for x in 0..<Self.side where x == 0 || y == 0 || x == Self.side - 1 || y == Self.side - 1 {
            bytes[y * Self.side + x] = 255
        } }
        let packed = sink.atlas.packed(for: key, rasterize: { GlyphImage(width: Self.side, height: Self.side, bytes: bytes) })!
        let size = Float(Self.side)
        return MUIGlyph(bounds: box(origin.0, origin.1, size, size),
                        atlasBounds: box(Float(packed.slot.x), Float(packed.slot.y), size, size),
                        contentMask: box(0, 0, 4096, 4096),
                        maskCornerRadii: MUICorners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0),
                        color: color, order: 0, transform: 0)
    }
}
@MainActor private func measuredGlyph() throws -> Synthetic { Synthetic() }

/// **1** (`TRM-AU`). A solid rect reads back as the exact colour over exactly its pixels: the four sides
/// are exact (one pixel inside is the colour, one pixel outside is the backdrop), at scale 1 and 2, for a
/// 1-pixel and a large rect. Mutation: sample the whole slot (`solidInset` 0) instead of its inner square -
/// the linear filter reaches the neighbouring texels at the quad's edge.
@Test @MainActor func aSolidRectIsTheExactColourOverExactlyItsPixels() throws {
    for scale: Float in [1, 2] {
        let plan = Plan()
        // A neighbouring glyph in the atlas, so a bleed has something to read: any ink beside the slot.
        plan.draw = { sink in
            sink.fillRect(box(4, 5, 17, 9), color: red)       // large
            sink.fillRect(box(26, 3, 1, 1), color: green)      // one pixel
            sink.fillRect(box(28, 10, 1, 12), color: blue)     // a 1-wide column
        }
        let (window, platform) = try gridWindow(plan, scale: scale)
        window.drawFrameIfNeeded()
        let p = platform.fakeSurface.readPixels()
        func expectRect(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ c: [Int]) {
            for yy in -1...h { for xx in -1...w {
                let inside = xx >= 0 && xx < w && yy >= 0 && yy < h
                let want = inside ? c : [0, 0, 0, 255]
                let got = bgra(p, x + xx, y + yy, side: 32)
                if got != want { Issue.record("scale \(scale): pixel \(x + xx),\(y + yy) is \(got), want \(want)"); return }
            } }
        }
        expectRect(4, 5, 17, 9, [255, 0, 0, 255])
        expectRect(26, 3, 1, 1, [0, 255, 0, 255])
        expectRect(28, 10, 1, 12, [0, 0, 255, 255])
    }
}

/// **2** (`TRM-AU`). Rects meeting edge to edge leave no seam: two adjacent opaque cells of different colours
/// cover every pixel of the row, no gap and no overlap blend. Mutation: record each rect one pixel short (height - 1).
@Test @MainActor func adjacentCellBackgroundsLeaveNoSeam() throws {
    let plan = Plan()
    plan.draw = { sink in
        for column in 0..<4 { sink.fillRect(box(Float(column * 8), 0, 8, 8), color: column % 2 == 0 ? white : red) }
    }
    let (window, platform) = try gridWindow(plan)
    window.drawFrameIfNeeded()
    let p = platform.fakeSurface.readPixels()
    for x in 0..<32 {
        let want = (x / 8) % 2 == 0 ? [255, 255, 255, 255] : [255, 0, 0, 255]
        for y in 0..<8 where bgra(p, x, y, side: 32) != want {
            Issue.record("pixel \(x),\(y) is \(bgra(p, x, y, side: 32)), want \(want)"); return
        }
    }
}

/// **3** (`TRM-AU`). Call order is paint order: a glyph recorded after a background rect is drawn over it,
/// a rect recorded after a glyph covers it. Mutation: record the rects after the glyphs.
@Test @MainActor func aGlyphDrawsOverTheBackgroundRectRecordedBeforeIt() throws {
    let measured = try measuredGlyph()
    let plan = Plan()
    plan.draw = { sink in
        sink.fillRect(box(0, 0, 32, 32), color: blue)
        sink.append(measured.sprite(at: (4, 4), color: white, sink: sink))
    }
    let (window, platform) = try gridWindow(plan)
    window.drawFrameIfNeeded()
    let p = platform.fakeSurface.readPixels()
    let pixels = (0..<32).flatMap { y in (0..<32).map { x in bgra(p, x, y, side: 32) } }
    #expect(bgra(p, 30, 30, side: 32) == [0, 0, 255, 255], "the background shows away from the glyph")
    #expect(pixels.contains { $0 != [0, 0, 255, 255] && $0[2] >= 0 && $0[3] == 255 && $0[0] > 0 },
            "the glyph's ink is drawn over the background")
    // The same glyph, then the rect over it: the ink is gone.
    let over = Plan()
    over.draw = { sink in
        sink.append(measured.sprite(at: (4, 4), color: white, sink: sink))
        sink.fillRect(box(0, 0, 32, 32), color: blue)
    }
    let (w2, p2) = try gridWindow(over)
    w2.drawFrameIfNeeded()
    let q = p2.fakeSurface.readPixels()
    #expect((0..<32).allSatisfy { y in (0..<32).allSatisfy { x in bgra(q, x, y, side: 32) == [0, 0, 255, 255] } },
            "a rect recorded after the glyph covers it")
}

/// **4** (`TRM-AV`). Damaged rows: the second frame records only row 1 (an opaque background rect, then its
/// glyph) on the retained target; rows 0 and 2 keep the first frame's pixels byte for byte and row 1 shows
/// the new content with none of the old. Mutation: the renderer clears the target before the grid pass.
@Test @MainActor func aPartialRowRedrawLeavesTheOtherRowsIntact() throws {
    let measured = try measuredGlyph()
    let plan = Plan()
    var frame = 0
    let rowColors = [red, green, blue]
    plan.draw = { sink in
        frame += 1
        for row in 0..<3 where frame == 1 || row == 1 {
            let color = frame == 1 ? rowColors[row] : white
            sink.fillRect(box(0, Float(row * 10), 32, 10), color: color)
            sink.append(measured.sprite(at: (3, Float(row * 10) + 1), color: black, sink: sink))
        }
    }
    let (window, platform) = try gridWindow(plan)
    window.drawFrameIfNeeded()
    let first = platform.fakeSurface.readPixels()
    window.drawFrameIfNeeded()
    let second = platform.fakeSurface.readPixels()
    try #require(frame == 2, "set up: the surface drew twice")
    func row(_ p: [UInt8], _ r: Int) -> [UInt8] {
        (r * 10..<r * 10 + 10).flatMap { y in Array(p[(y * 32 * 4)..<((y + 1) * 32 * 4)]) }
    }
    #expect(row(first, 0) == row(second, 0), "row 0 is untouched")
    #expect(row(first, 2) == row(second, 2), "row 2 is untouched")
    #expect(row(first, 1) != row(second, 1), "row 1 changed")
    let r1 = (10..<20).flatMap { y in (0..<32).map { x in bgra(second, x, y, side: 32) } }
    #expect(!r1.contains([0, 255, 0, 255]), "no pixel of the old green row shows through the opaque redraw")
    #expect(bgra(second, 31, 19, side: 32) == [255, 255, 255, 255], "the new background")
}

/// **5** (`TRM-AV`). Cost: a surface recording rects and glyphs costs the same element requests as the one
/// recording only glyphs, frame for frame (the sink is renderer-side; no element is made).
@Test @MainActor func aGridSurfaceCostsTheElementRequestsOfATextSurface() throws {
    let measured = try measuredGlyph()
    func requests(_ draw: @escaping @MainActor (SurfaceTextSink) -> Void) throws -> [Int] {
        let plan = Plan()
        plan.draw = draw
        let (window, _) = try gridWindow(plan)
        var seen: [Int] = []
        window.testingOnFrameAdopted { seen.append($0.elementRequests) }
        for _ in 0..<3 { window.drawFrameIfNeeded() }
        return seen
    }
    let text = try requests { sink in sink.append(measured.sprite(at: (3, 3), color: white, sink: sink)) }
    let grid = try requests { sink in
        sink.fillRect(box(0, 0, 32, 32), color: blue)
        sink.append(measured.sprite(at: (3, 3), color: white, sink: sink))
    }
    #expect(!text.isEmpty && text.allSatisfy { $0 > 0 }, "set up: frames were built and counted: \(text)")
    #expect(grid == text, "grid \(grid) vs text \(text)")
}
