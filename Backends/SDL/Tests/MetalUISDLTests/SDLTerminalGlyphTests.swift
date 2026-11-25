import Foundation
import Testing
import MetalUICore
import MetalUIPlatform
@testable import MetalUIScene
import MetalUIShaderTypes
import MetalUIPortableText
import MetalUITerminal
import MetalUITextSystem
@testable import MetalUITerminalUI
@testable import MetalUI
@testable import MetalUISDL
import SDLBridge

// Terminal phase 5.2 (`TRM-AZ`): a row of synthesised box-drawing glyphs through the row painter on the SDL GPU
// renderer, read back and compared pixel for pixel with the rectangles the painter was given (the CPU oracle
// `SyntheticGlyphs.rects`), so Metal (`TerminalGlyphMetalTests`) and SDL agree on the same exact pixels. The
// target is composited as in `SDLGridSinkTests`. No test sleeps.

private let fonts = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Tests/Fonts")
private let width = 96, height = 64
private let target = SurfaceTarget(id: SurfaceID(rawValue: 1), width: width, height: height)

private func box(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> MUIBounds {
    MUIBounds(origin: MUIPoint(x: x, y: y), size: MUISize(width: w, height: h))
}
private func corners(_ r: Float) -> MUICorners { MUICorners(topLeft: r, topRight: r, bottomRight: r, bottomLeft: r) }
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

private func grey(_ pixels: [UInt8], _ x: Int, _ y: Int) -> Int { Int(pixels[(y * width + x) * 4]) }

@MainActor private func render(_ input: String, columns: Int, scale: Float) throws -> (pixels: [UInt8], metrics: TerminalCellMetrics) {
    #if os(macOS)
    armMainRunLoopExitCheck()
    #endif
    let font = [UInt8](try Data(contentsOf: fonts.appendingPathComponent("NotoSans-Regular.ttf")))
    let system = PortableTextSystem(resolver: try PortableFontResolver(defaultFont: font))
    let cache = TerminalGlyphCache(system: system, family: nil, size: 14, scale: scale)
    let scheme = TerminalColorScheme(ansi: TerminalColorScheme.xterm.ansi, foreground: TerminalRGB(255, 255, 255),
                                     background: TerminalRGB(0, 0, 0))
    let painter = TerminalRowPainter(cache: cache, scheme: scheme)
    let emulator = TerminalEmulator(cols: columns, rows: 1)
    Array(input.utf8).withUnsafeBytes { emulator.feed($0) }
    let row = try #require(emulator.publishSnapshot().damagedRows.first?.row)
    let renderer = try SDLWindowRenderer(offscreenWidth: width, height: height)
    let atlas = GlyphAtlas(width: 256, height: 256)
    let request = SurfaceDrawRequest(target: target, scaleFactor: scale, time: 0, policy: .onDemand, value: 0) { ctx in
        if ctx.isNewTarget { ctx.clear(red: 0, green: 0, blue: 0, alpha: 1) }
        guard let sink = (ctx as? SDLGPUDrawContext)?.textSink else {
            preconditionFailure("an SDL surface request draws into an SDLGPUDrawContext with a text sink")
        }
        painter.draw(row, at: 0, columns: columns, origin: (8, 8), into: sink)
    }
    try #require(renderer.beginFrame() != nil)
    try #require(renderer.finishFrame(scene: scene(), atlas: atlas, surfaces: [request]))
    return (try renderer.readPixels(width: width, height: height), cache.metrics)
}

/// **1** (`TRM-AZ` items 3 and 4). A row of rectangle-drawn glyphs reads back as exactly the oracle's pixels on
/// SDL: every pixel of the row is full white where one of the glyph's rectangles covers it and black elsewhere,
/// at scale factors 1 and 2, and a horizontal line through three cells is one unbroken run. Mutation: end the
/// right arm one pixel short.
@MainActor @Test func anSDLBoxDrawingRowReadsBackAsTheOracleRects() throws {
    for (scale, text, columns) in [(Float(1), "─┼┃╋═╬", 6), (Float(2), "─┼═", 3)] {
        let (p, m) = try render(text, columns: columns, scale: scale)
        for (column, character) in text.enumerated() {
            let scalar = try #require(character.unicodeScalars.first)
            let rects = try #require(SyntheticGlyphs.rects(for: scalar.value,
                                                           cellWidth: m.cellWidth, cellHeight: m.cellHeight))
            for y in 0..<m.cellHeight {
                for x in 0..<m.cellWidth {
                    let lit = rects.contains { $0.x0 <= x && x < $0.x1 && $0.y0 <= y && y < $0.y1 }
                    let got = grey(p, 8 + column * m.cellWidth + x, 8 + y)
                    if got != (lit ? 255 : 0) {
                        Issue.record("scale \(scale), \(character): pixel \(x),\(y) is \(got), want \(lit ? 255 : 0)"); return
                    }
                }
            }
        }
        // Nothing outside the row.
        #expect(grey(p, 7, 8 + m.cellHeight / 2) == 0 && grey(p, 8 + columns * m.cellWidth, 8 + m.cellHeight / 2) == 0)
    }
    let (p, m) = try render("───", columns: 3, scale: 1)
    let t = SyntheticGlyphs.lightStroke(cellWidth: m.cellWidth)
    for x in 8..<8 + 3 * m.cellWidth { #expect(grey(p, x, 8 + (m.cellHeight - t) / 2) == 255, "gap at x \(x)") }
}

/// **2** (`TRM-AZ` item 3). A bitmap glyph (`╭`, an arc) reads back within two levels of the R8 coverage it was
/// drawn from, on SDL: the atlas upload and the 1:1 sprite blit keep the supersampled coverage.
@MainActor @Test func anSDLArcReadsBackAsItsCoverage() throws {
    let (p, m) = try render("╭", columns: 1, scale: 1)
    let image = try #require(SyntheticGlyphs.raster(for: 0x256D, cellWidth: m.cellWidth, cellHeight: m.cellHeight))
    for y in 0..<m.cellHeight {
        for x in 0..<m.cellWidth {
            let want = Int(image.bytes[y * m.cellWidth + x]), got = grey(p, 8 + x, 8 + y)
            if abs(got - want) > 2 { Issue.record("pixel \(x),\(y) is \(got), want \(want)"); return }
        }
    }
}
