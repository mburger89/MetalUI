import MetalUIScene
import MetalUIShaderTypes
import MetalUITerminal
import MetalUITestSupport
import MetalUITextSystem
import Testing
@testable import MetalUITerminalUI
#if os(macOS)
import MetalUIText
#endif

// Terminal phase 5.2 (`TRM-AZ`): the grapheme cache and the row painter, read through the sink's records.

private func ascii(_ s: String) -> ArraySlice<UInt8> { ArraySlice(Array(s.utf8)) }

private func screen(_ rows: Int = 24, cols: Int = 80) -> String {
    (0..<rows).map { r in String((0..<cols).map { c in Character(UnicodeScalar(UInt8(33 + (r * 7 + c) % 90))) }) }.joined(separator: "\r\n")
}

/// **1** (`TRM-AZ` item 2). A cluster is shaped once: asking again, or for the same ASCII byte in another cell,
/// reuses the entry (a counted `shapedClusters`); bold and italic are their own entries; a space is blank and
/// shapes nothing. Mutation: drop the cache write (shape on every call).
@Test @MainActor func aClusterIsShapedOnceAndStyleSelectsTheFace() {
    let (_, cache) = notoPainter()
    cache.prepare(for: GlyphAtlas(width: 128, height: 128))
    #expect(cache.drawing(for: ascii(" "), bold: false, italic: false) == .blank)
    #expect(cache.shapedClusters == 0)
    let a = cache.drawing(for: ascii("a"), bold: false, italic: false)
    #expect(cache.shapedClusters == 1)
    for _ in 0..<100 { #expect(cache.drawing(for: ascii("a"), bold: false, italic: false) == a) }
    #expect(cache.shapedClusters == 1, "100 more lookups shaped nothing")
    let bold = cache.drawing(for: ascii("a"), bold: true, italic: false)
    let italic = cache.drawing(for: ascii("a"), bold: false, italic: true)
    #expect(bold != a && italic != a && bold != italic && cache.shapedClusters == 3, "three faces, three entries")
    #expect(cache.fonts.count == 4)
    if case .glyphs(let i) = a { #expect(cache.glyphs(at: i).count == 1) } else { Issue.record("a is glyphs") }
}

/// **2** (`TRM-AZ` item 2). The cache is keyed on the atlas generation: after `reclaim()` the next frame's
/// `prepare` empties it (the atlas slots it was drawn against are gone), and shaping happens again exactly once
/// per cluster. Growth does not empty it. Mutation: ignore the generation.
@Test @MainActor func aNewAtlasGenerationEmptiesTheCache() {
    let (_, cache) = notoPainter()
    let atlas = GlyphAtlas(width: 128, height: 128, maximumExtent: 256)
    cache.prepare(for: atlas)
    _ = cache.drawing(for: ascii("a"), bold: false, italic: false)
    cache.prepare(for: atlas)
    #expect(cache.rebuilds == 0 && cache.shapedClusters == 1)
    atlas.reclaim()
    cache.prepare(for: atlas)
    #expect(cache.rebuilds == 1)
    _ = cache.drawing(for: ascii("a"), bold: false, italic: false)
    #expect(cache.shapedClusters == 2, "shaped again after the rebuild")
    _ = cache.drawing(for: ascii("a"), bold: false, italic: false)
    #expect(cache.shapedClusters == 2)
}

/// **3** (`TRM-AZ` item 2). Synthesised scalars never reach the text system, and a combining sequence is one
/// cluster of one entry, a wide character one entry of its own (two cells wide in the row). A synthesised scalar
/// followed by a combining mark is shaped by the font, not synthesised.
@Test @MainActor func syntheticScalarsSkipTheFontAndClustersAreOneEntry() {
    let (_, cache) = notoPainter()
    cache.prepare(for: GlyphAtlas(width: 128, height: 128))
    let line = cache.drawing(for: Array("─".utf8)[...], bold: false, italic: false)
    guard case .synthetic(let i) = line else { Issue.record("a box line is synthetic"); return }
    #expect(cache.shapedClusters == 0 && cache.syntheticBuilds == 1)
    #expect(cache.synthetic(at: i).rects?.isEmpty == false)
    _ = cache.drawing(for: Array("─".utf8)[...], bold: true, italic: true)
    #expect(cache.syntheticBuilds == 1, "style does not change a box line")
    let accented = cache.drawing(for: Array("e\u{301}".utf8)[...], bold: false, italic: false)
    guard case .glyphs(let j) = accented else { Issue.record("e + acute is glyphs"); return }
    #expect(cache.shapedClusters == 1 && cache.glyphs(at: j).count >= 1, "the cluster is shaped as one entry")
    _ = cache.drawing(for: Array("─\u{301}".utf8)[...], bold: false, italic: false)
    #expect(cache.shapedClusters == 2, "a mark on a box line makes it a font cluster")
    let wide = terminalRows("漢字", cols: 10, rows: 2)[0]
    var cells: [(Int, Int)] = []
    wide.forEachCell { column, width, _, _ in cells.append((column, width)) }
    #expect(cells.map(\.0) == [0, 2] && cells.map(\.1) == [2, 2], "each wide cell is visited once, two columns wide")
}

/// **4** (`TRM-AZ` item 6, the cost). After one warm-up draw, a full 80 x 24 screen of ASCII shapes no glyph
/// (counted), rasterizes none and drops none, and records the same instances again. Mutation: shape in
/// `drawing(for:)` on every call.
@Test @MainActor func aWarmScreenOfAsciiShapesNothing() {
    let (painter, cache) = notoPainter()
    let rows = terminalRows(screen())
    let atlas = GlyphAtlas(width: 1024, height: 1024)
    func frame() -> Int {
        let sink = makeSink(atlas)
        for (i, row) in rows.enumerated() { painter.draw(row, at: i, columns: 80, origin: (0, 0), into: sink) }
        return sink.glyphs.count
    }
    let first = frame()
    let shaped = cache.shapedClusters, packed = atlas.droppedGlyphs
    #expect(shaped > 0 && shaped <= 94, "at most one shape per distinct character: \(shaped)")
    let second = frame()
    #expect(cache.shapedClusters == shaped, "the warm frame shapes 0 new glyphs")
    #expect(second == first && atlas.droppedGlyphs == packed && atlas.droppedGlyphs == 0)
    #expect(second >= 24 + 80 * 24 - 24 * 2, "24 row backgrounds and about one instance per character: \(second)")
}

#if os(macOS)
/// **5** (`TRM-AZ` item 6, the cost). The cached ASCII lookup is allocation-free: 10 000 lookups of a warm
/// cache make no heap allocation on the calling thread (the thread-filtered counter, `PA-J`).
/// Release builds only: unoptimized code allocates in slice and iterator plumbing, and how much depends on the
/// toolchain (0 locally, about one per lookup on CI's macOS toolchain), so a debug run cannot pin the cache itself.
/// Run with `swift test -c release --filter aWarmAsciiLookupAllocatesNothing`.
#if !DEBUG
@Test @MainActor func aWarmAsciiLookupAllocatesNothing() throws {
    let (_, cache) = notoPainter()
    cache.prepare(for: GlyphAtlas(width: 128, height: 128))
    let bytes = (33..<120).map { ascii(String(UnicodeScalar(UInt8($0)))) }
    for b in bytes { _ = cache.drawing(for: b, bold: false, italic: false) }
    var total = 0
    let allocations = try #require(countAllocations {
        // Indexed: a debug build's `for ... in` over an array of slices allocates in the iterator itself.
        for _ in 0..<100 {
            for k in 0..<bytes.count {
                if case .glyphs(let i) = cache.drawing(for: bytes[k], bold: false, italic: false) { total += cache.glyphs(at: i).count }
            }
        }
    })
    #expect(total > 0)
    #expect(allocations == 0, "\(allocations) allocations over \(100 * bytes.count) lookups")
}
#endif

/// **6** (`TRM-AZ` item 2). Font fallback: a character Menlo lacks is placed in a fallback font through
/// CoreText's cascade (the placed key names another font), occupies two cells in the row, and has ink.
/// Mutation: place with the base font only.
@Test @MainActor func aWideCharacterFallsBackToAnotherFont() throws {
    let system = CoreTextTextSystem()
    let cache = TerminalGlyphCache(system: system, family: "Menlo", size: 13, scale: 2)
    let atlas = GlyphAtlas(width: 256, height: 256)
    cache.prepare(for: atlas)
    guard case .glyphs(let i) = cache.drawing(for: Array("漢".utf8)[...], bold: false, italic: false) else {
        Issue.record("漢 is glyphs"); return
    }
    let placed = try #require(cache.glyphs(at: i).first)
    #expect(placed.key.font.postScriptName != cache.fonts[0].postScriptName, "a fallback font, not Menlo")
    let image = system.rasterize(placed.key)
    #expect(!image.isEmpty && image.bytes.contains { $0 > 0 })
    #expect(image.width > cache.metrics.cellWidth, "wider than one cell, so it spans two: \(image.width) vs \(cache.metrics.cellWidth)")
    #expect(image.width <= 2 * cache.metrics.cellWidth + 2)
}
#endif

// MARK: The row painter

@MainActor private func solid(_ sink: SurfaceTextSink) -> [MUIGlyph] {
    guard let slot = sink.solidSlot else { return [] }
    return sink.glyphs.filter { Int($0.atlasBounds.origin.x) == slot.x + 1 && Int($0.atlasBounds.origin.y) == slot.y + 1 }
}
private func box(_ g: MUIGlyph) -> [Int] {
    [Int(g.bounds.origin.x), Int(g.bounds.origin.y), Int(g.bounds.size.width), Int(g.bounds.size.height)]
}

/// **7** (`TRM-AZ` item 6). A row of default text is one opaque background rect over the whole width, then its
/// glyphs, one per visible character (spaces draw none), in that order, masked to the row; a row of cells
/// with other backgrounds merges equal neighbours into runs. Mutation: one rect per cell.
@Test @MainActor func aRowIsMergedBackgroundsThenGlyphs() {
    let (painter, cache) = notoPainter()
    let cw = cache.metrics.cellWidth, ch = cache.metrics.cellHeight
    let sink = makeSink()
    let rows = terminalRows("ab cd\r\n\u{1b}[41mxy\u{1b}[44mzz\u{1b}[0m!", cols: 8, rows: 2)
    painter.draw(rows[0], at: 0, columns: 8, origin: (10, 20), into: sink)
    var rects = solid(sink)
    #expect(rects.count == 1 && box(rects[0]) == [10, 20, 8 * cw, ch], "one background over the row: \(rects.map(box))")
    #expect(sink.glyphs.count == 1 + 4, "background, then a b c d")
    #expect(sink.glyphs[0].atlasBounds.size.width == 2, "the background is first (the solid square)")
    let mask = sink.glyphs[1].contentMask
    #expect(Int(mask.origin.x) == 10 && Int(mask.origin.y) == 20 && Int(mask.size.width) == 8 * cw && Int(mask.size.height) == ch)
    sink.beginSurface(SurfaceID(rawValue: 1))
    let before = sink.glyphs.count
    painter.draw(rows[1], at: 1, columns: 8, origin: (10, 20), into: sink)
    rects = Array(solid(sink).dropFirst(1))
    #expect(rects.map(box) == [[10, 20 + ch, 2 * cw, ch], [10 + 2 * cw, 20 + ch, 2 * cw, ch], [10 + 4 * cw, 20 + ch, 4 * cw, ch]],
            "red x2, blue x2 (z z), then the default to the edge: \(rects.map(box))")
    #expect(sink.glyphs.count - before == 3 + 5, "three runs and five glyphs x y z z !")
}

/// **8** (`TRM-AZ` item 5, `TRM-C` item 7). Hidden cells draw their background but no glyph; inverse puts the
/// foreground in the background; the glyph is tinted with the resolved foreground. Mutation: draw hidden glyphs.
@Test @MainActor func hiddenInverseAndTheGlyphTint() throws {
    let (painter, _) = notoPainter()
    let sink = makeSink()
    let rows = terminalRows("\u{1b}[8mhidden\u{1b}[0m \u{1b}[7;31mX\u{1b}[0m", cols: 12, rows: 1)
    painter.draw(rows[0], at: 0, columns: 12, origin: (0, 0), into: sink)
    let backgrounds = solid(sink)
    #expect(backgrounds.count == 3, "default over the hidden word and gap, one red cell, the default to the edge: \(backgrounds.map(box))")
    let red = TerminalColorScheme.xterm.ansi[1]
    #expect(abs(backgrounds[1].color.l - red.hsla().l) < 1e-5 && abs(backgrounds[1].color.s - red.hsla().s) < 1e-5,
            "inverse: the red foreground is the background")
    let sprites = sink.glyphs.filter { $0.atlasBounds.size.width > 2 }
    #expect(sprites.count == 1, "only X draws, the hidden word and the blank do not")
    #expect(abs(sprites[0].color.l - TerminalColorScheme.xterm.background.hsla().l) < 1e-5, "its tint is the (inverted) default background")
}

/// **9** (`TRM-AZ` item 6). Decorations: a run of underlined cells is one rect at the metrics' underline row, a
/// double underline two, a strikethrough one at the strike row, dotted and dashed are periodic across the run,
/// and a different underline colour splits the run. Mutation: a rect per cell.
@Test @MainActor func underlinesAndStrikethroughsMergeIntoRuns() {
    let (painter, cache) = notoPainter()
    let m = cache.metrics
    func decorations(_ input: String) -> [[Int]] {
        let sink = makeSink()
        let row = terminalRows(input, cols: 6, rows: 1)[0]
        painter.draw(row, at: 0, columns: 6, origin: (0, 0), into: sink)
        return solid(sink).dropFirst(1).map(box)
    }
    let under = decorations("\u{1b}[4mabc\u{1b}[0m")
    #expect(under.suffix(1).map { $0 } == [[0, m.underlineTop, 3 * m.cellWidth, m.underlineThickness]], "\(under)")
    #expect(decorations("\u{1b}[4mabc\u{1b}[4:2mdef").filter { $0[1] >= m.underlineTop - 1 }.count >= 3, "single then double")
    #expect(decorations("\u{1b}[9mab\u{1b}[0m").last == [0, m.strikeTop, 2 * m.cellWidth, m.underlineThickness])
    let split = decorations("\u{1b}[4;58;2;255;0;0mab\u{1b}[58;2;0;255;0mcd")
    #expect(split.count >= 2 && split[split.count - 1][0] == 2 * m.cellWidth && split[split.count - 2][0] == 0, "two colours, two runs: \(split)")
    let dotted = decorations("\u{1b}[4:4mabcdef")
    #expect(dotted.count > 3 && dotted.allSatisfy { $0[3] == m.underlineThickness }, "dots of one thickness: \(dotted.count)")
}
