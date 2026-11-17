import Testing
import Foundation
import Metal
import MetalUICore
import MetalUIPlatform
import MetalUIScene
import MetalUIShaderTypes
import MetalUIText
import MetalUITerminal
import MetalUITextSystem
@testable import MetalUI
@testable import MetalUIRender
@testable import MetalUITerminalUI

// Terminal phase 5.2 (`TRM-AZ`): synthesised glyphs and the row painter on Metal. A real `Window` over
// `FakePlatformWindow` (the shape of `GridSinkMetalTests`), a `TerminalRowPainter` over Menlo through CoreText
// recording into the frame's sink, the target read back. The scheme draws white on black so a pixel's value is
// its coverage. No test sleeps.

@MainActor private final class Plan {
    var draw: @MainActor (SurfaceTextSink) -> Void = { _ in }
}

private let side = 128

@MainActor private func window(_ plan: Plan, scale: Float) throws -> (Window, FakePlatformWindow) {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let extent = Pixels(Float(side) / scale)
    let (window, platform) = try makeFakeWindow(device: device, size: side) {
        GPUSurface(redraw: .continuous) { ctx in
            if ctx.isNewTarget { ctx.clear(red: 0, green: 0, blue: 0, alpha: 1) }
            guard let sink = (ctx as? any SurfaceTextSinkProviding)?.textSink else { Issue.record("no sink"); return }
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

private let whiteOnBlack = TerminalColorScheme(
    ansi: TerminalColorScheme.xterm.ansi, foreground: TerminalRGB(255, 255, 255), background: TerminalRGB(0, 0, 0))

/// The grey of the pixel at `x`, `y` (blue channel of BGRA; the scheme is grey, so every channel agrees).
private func grey(_ p: [UInt8], _ x: Int, _ y: Int) -> Int { Int(p[(y * side + x) * 4]) }

@MainActor private func render(_ input: String, columns: Int, rows: Int, scale: Float, origin: (Int, Int) = (8, 8))
    throws -> (pixels: [UInt8], metrics: TerminalCellMetrics) {
    let system = CoreTextTextSystem()
    let cache = TerminalGlyphCache(system: system, family: "Menlo", size: 13, scale: scale)
    let painter = TerminalRowPainter(cache: cache, scheme: whiteOnBlack)
    let lines = terminalRowsForPixels(input, columns: columns, rows: rows)
    let plan = Plan()
    plan.draw = { sink in
        for (i, row) in lines.enumerated() { painter.draw(row, at: i, columns: columns, origin: origin, into: sink) }
    }
    let (win, platform) = try window(plan, scale: scale)
    win.drawFrameIfNeeded()
    return (platform.fakeSurface.readPixels(), cache.metrics)
}

@MainActor private func terminalRowsForPixels(_ input: String, columns: Int, rows: Int) -> [TerminalRow] {
    let emulator = TerminalEmulator(cols: columns, rows: rows)
    Array(input.utf8).withUnsafeBytes { emulator.feed($0) }
    return emulator.publishSnapshot().damagedRows.sorted { $0.index < $1.index }.map(\.row)
}

/// **1** (`TRM-AZ` item 4). A horizontal line through three adjacent cells is lit on every pixel of the three
/// cells' width on exactly the stroke's rows, and on no pixel above, below, before or after, at scale 1 and 2
/// (`───`, light stroke 1 and 2 pixels). Mutation: end the right arm one pixel short (a one-pixel gap at each cell
/// joint) or let both halves cover the centre column (still lit: the gap mutation is the red one).
@Test @MainActor func aHorizontalLineThroughThreeCellsReadsBackWithoutAGap() throws {
    for scale: Float in [1, 2] {
        let (p, m) = try render("───", columns: 3, rows: 1, scale: scale)
        let t = SyntheticGlyphs.lightStroke(cellWidth: m.cellWidth)
        let rows = (m.cellHeight - t) / 2..<(m.cellHeight - t) / 2 + t
        for y in 0..<side {
            for x in 0..<side {
                let inside = (8..<8 + 3 * m.cellWidth).contains(x) && rows.contains(y - 8)
                let value = grey(p, x, y)
                if inside ? value != 255 : value != 0 {
                    Issue.record("scale \(scale): pixel \(x),\(y) is \(value), want \(inside ? 255 : 0) (cell \(m.cellWidth)x\(m.cellHeight))")
                    return
                }
            }
        }
    }
}

/// **2** (`TRM-AZ` item 3). The shades read back as 25, 50, 75 and 100 percent over the whole of each cell (the
/// coverage is the rectangle's alpha over the opaque black background), and `▀` over `▄` fill their halves with
/// no seam row. Mutation: shade coverages 32, 96, 160.
@Test @MainActor func shadesAndHalvesReadBackAtTheirCoverage() throws {
    let (p, m) = try render("░▒▓█\r\n▀▄", columns: 4, rows: 2, scale: 1)
    for (i, want) in [64, 128, 191, 255].enumerated() {
        for (dx, dy) in [(0, 0), (m.cellWidth - 1, m.cellHeight - 1), (m.cellWidth / 2, m.cellHeight / 2)] {
            let got = grey(p, 8 + i * m.cellWidth + dx, 8 + dy)
            #expect(abs(got - want) <= 2, "shade \(i): \(got) vs \(want) at \(dx),\(dy)")
        }
    }
    let half = m.cellHeight / 2
    for y in 0..<m.cellHeight {
        #expect(grey(p, 8 + 3, 8 + m.cellHeight + y) == (y < half ? 255 : 0), "▀ row \(y)")
        #expect(grey(p, 8 + m.cellWidth + 3, 8 + m.cellHeight + y) == (y < half ? 0 : 255), "▄ row \(y)")
    }
}

/// **3** (`TRM-AZ` item 3). A Powerline triangle `` reads back with the coverage of the bitmap it was drawn
/// from: half the cell's area in total (within 2 percent), full at the left of the middle row, empty at the
/// right corners. At both scales.
@Test @MainActor func aPowerlineTriangleCoversHalfTheCell() throws {
    for scale: Float in [1, 2] {
        let (p, m) = try render("\u{E0B0}", columns: 1, rows: 1, scale: scale)
        var sum = 0
        for y in 0..<m.cellHeight { for x in 0..<m.cellWidth { sum += grey(p, 8 + x, 8 + y) } }
        let area = Double(m.cellWidth * m.cellHeight)
        #expect(abs(Double(sum) / 255 - area / 2) / area < 0.02, "scale \(scale): \(Double(sum) / 255) of \(area)")
        #expect(grey(p, 8, 8 + m.cellHeight / 2) >= 250)
        #expect(grey(p, 8 + m.cellWidth - 1, 8) == 0 && grey(p, 8 + m.cellWidth - 1, 8 + m.cellHeight - 1) == 0)
        #expect(grey(p, 8 + m.cellWidth, 8 + m.cellHeight / 2) == 0, "nothing past the cell")
    }
}

/// **4** (`TRM-AZ` item 4). A rounded box `╭─╮` / `│ │` / `╰─╯` is a closed loop on the pixels: following the
/// top line from the left arc's last column to the right arc's first, the left column from top to bottom and so
/// on, every pixel of the stroke is lit with no break where arcs meet lines, at scale 1 and 2. Mutation: arcs
/// centred on `cw / 2`.
@Test @MainActor func aRoundedBoxIsAClosedLoopOfPixels() throws {
    for scale: Float in [1, 2] {
        let (p, m) = try render("╭─╮\r\n│ │\r\n╰─╯", columns: 3, rows: 3, scale: scale)
        let t = SyntheticGlyphs.lightStroke(cellWidth: m.cellWidth)
        let cw = m.cellWidth, ch = m.cellHeight
        let hy = 8 + (ch - t) / 2, vx = 8 + (cw - t) / 2          // the top line's first row, the left line's first column
        func lit(_ x: Int, _ y: Int) -> Bool { grey(p, x, y) >= 240 }
        // Top and bottom lines: the whole middle cell plus the last column of the left arc and the first of the right one.
        for x in (8 + cw - 1)...(8 + 2 * cw) {
            #expect(lit(x, hy) && lit(x, hy + 2 * ch), "scale \(scale): the top/bottom line has a gap at x \(x)")
        }
        // Left and right lines: the whole middle cell plus the last row of the upper arc and the first of the lower one.
        for y in (8 + ch - 1)...(8 + 2 * ch) {
            #expect(lit(vx, y) && lit(vx + 2 * cw, y), "scale \(scale): the side line has a gap at y \(y)")
        }
        #expect(!lit(8 + cw + cw / 2, 8 + ch + ch / 2), "the inside of the box is empty")
    }
}
