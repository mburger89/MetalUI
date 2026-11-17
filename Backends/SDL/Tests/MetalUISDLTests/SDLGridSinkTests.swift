import Foundation
import Testing
import MetalUICore
import MetalUIPlatform
@testable import MetalUIScene
import MetalUIShaderTypes
@testable import MetalUI
@testable import MetalUISDL
import SDLBridge

// Terminal phase 5.1 (`TRM-AU`, `TRM-AV`; record 347): the grid sink on the SDL GPU renderer. A rect is a glyph
// instance over the atlas's solid slot, so it rides the existing `ReplaySurfaceText` pass: no C, shader or
// fixture change. The target is read back through the composite of `SDLDrawTextTests` (a full-window surface quad
// over opaque black) from an offscreen `SDLWindowRenderer`. No test sleeps.

private let width = 96, height = 48
private let target = SurfaceTarget(id: SurfaceID(rawValue: 1), width: width, height: height)

private func box(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> MUIBounds {
    MUIBounds(origin: MUIPoint(x: x, y: y), size: MUISize(width: w, height: h))
}
private func corners(_ r: Float) -> MUICorners { MUICorners(topLeft: r, topRight: r, bottomRight: r, bottomLeft: r) }
private let red = MUIHsla(h: 0, s: 1, l: 0.5, a: 1), green = MUIHsla(h: 1.0 / 3, s: 1, l: 0.5, a: 1)
private let blue = MUIHsla(h: 2.0 / 3, s: 1, l: 0.5, a: 1), white = MUIHsla(h: 0, s: 0, l: 1, a: 1)
private let black = MUIHsla(h: 0, s: 0, l: 0, a: 1)

private func scene() -> Scene {
    var scene = Scene()
    let all = box(0, 0, Float(width), Float(height))
    scene.insert(MUIRect(bounds: all, contentMask: all, maskCornerRadii: corners(0),
                         background: black, borderColor: black, cornerRadii: corners(0),
                         borderWidths: MUIEdges(top: 0, right: 0, bottom: 0, left: 0), order: 0, shape: 0))
    scene.insert(MUIImage(bounds: all, contentMask: all, maskCornerRadii: corners(0), opacity: 1, texture: 0,
                          filter: MUIUInt(MUIImageFilterLinear.rawValue), order: 1), surface: target)
    scene.finalize()
    return scene
}

@MainActor private func offscreenRenderer() throws -> SDLWindowRenderer {
    #if os(macOS)
    armMainRunLoopExitCheck()
    #endif
    return try SDLWindowRenderer(offscreenWidth: width, height: height)
}

private func rgba(_ pixels: [UInt8], _ x: Int, _ y: Int) -> [Int] {
    let i = (y * width + x) * 4
    return [Int(pixels[i + 2]), Int(pixels[i + 1]), Int(pixels[i]), Int(pixels[i + 3])]
}

@MainActor private func draw(_ renderer: SDLWindowRenderer, atlas: GlyphAtlas, scale: Float = 1, value: Int = 0,
                             _ body: @escaping @MainActor (SurfaceTextSink) -> Void) throws {
    let request = SurfaceDrawRequest(target: target, scaleFactor: scale, time: 0, policy: .onDemand, value: value) { ctx in
        if ctx.isNewTarget { ctx.clear(red: 0, green: 0, blue: 0, alpha: 1) }
        body((ctx as! SDLGPUDrawContext).textSink!)
    }
    try #require(renderer.beginFrame() != nil)
    try #require(renderer.finishFrame(scene: scene(), atlas: atlas, surfaces: [request]))
}

/// **1** (`TRM-AU`). On SDL a solid rect reads back as the exact colour over exactly its pixels (the four sides
/// exact, large and 1-pixel rects), and adjacent cells leave no seam, at scale factors 1 and 2. Mutation:
/// `solidInset` 0 (the edges bleed into the slot's neighbours).
@MainActor @Test func anSDLSolidRectIsTheExactColourOverExactlyItsPixels() throws {
    for scale: Float in [1, 2] {
        let atlas = GlyphAtlas(width: 128, height: 128)
        let renderer = try offscreenRenderer()
        try draw(renderer, atlas: atlas, scale: scale) { sink in
            sink.fillRect(box(4, 5, 17, 9), color: red)
            sink.fillRect(box(26, 3, 1, 1), color: green)
            sink.fillRect(box(28, 10, 1, 12), color: blue)
            for column in 0..<4 { sink.fillRect(box(Float(40 + column * 8), 30, 8, 8), color: column % 2 == 0 ? white : red) }
        }
        let p = try renderer.readPixels(width: width, height: height)
        func expectRect(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ c: [Int]) {
            for yy in -1...h { for xx in -1...w {
                let inside = xx >= 0 && xx < w && yy >= 0 && yy < h
                let want = inside ? c : [0, 0, 0, 255]
                if rgba(p, x + xx, y + yy) != want {
                    Issue.record("scale \(scale): pixel \(x + xx),\(y + yy) is \(rgba(p, x + xx, y + yy)), want \(want)")
                    return
                }
            } }
        }
        expectRect(4, 5, 17, 9, [255, 0, 0, 255])
        expectRect(26, 3, 1, 1, [0, 255, 0, 255])
        expectRect(28, 10, 1, 12, [0, 0, 255, 255])
        for x in 40..<72 {
            let want = ((x - 40) / 8) % 2 == 0 ? [255, 255, 255, 255] : [255, 0, 0, 255]
            for y in 30..<38 where rgba(p, x, y) != want { Issue.record("seam at \(x),\(y): \(rgba(p, x, y))"); return }
        }
        #expect(renderer.lastTextPasses == 1, "one pass, the same one `drawText` uses")
    }
}

/// **2** (`TRM-AV`). A partial redraw on the retained target: the second draw (a new `value:` redraws the
/// surface, which is not new so it is not cleared) records only row 1; rows 0 and 2 keep their pixels exactly
/// and row 1 shows only the new content. Mutation: the text pass's load op `CLEAR`.
@MainActor @Test func anSDLPartialRowRedrawLeavesTheOtherRowsIntact() throws {
    let atlas = GlyphAtlas(width: 128, height: 128)
    let renderer = try offscreenRenderer()
    let colors = [red, green, blue]
    try draw(renderer, atlas: atlas) { sink in
        for row in 0..<3 { sink.fillRect(box(0, Float(row * 16), Float(width), 16), color: colors[row]) }
    }
    let first = try renderer.readPixels(width: width, height: height)
    try draw(renderer, atlas: atlas, value: 1) { sink in
        sink.fillRect(box(0, 16, Float(width), 16), color: white)
    }
    let second = try renderer.readPixels(width: width, height: height)
    func rows(_ p: [UInt8], _ r: Int) -> ArraySlice<UInt8> { p[(r * 16 * width * 4)..<((r + 1) * 16 * width * 4)] }
    #expect(rows(first, 0) == rows(second, 0) && rows(first, 2) == rows(second, 2), "rows 0 and 2 untouched")
    #expect(rgba(first, 5, 20) == [0, 255, 0, 255] && rgba(second, 5, 20) == [255, 255, 255, 255])
    #expect((16..<32).allSatisfy { y in (0..<width).allSatisfy { rgba(second, $0, y) == [255, 255, 255, 255] } },
            "no old green shows through the opaque redraw")
}
