import MetalUIScene
import Testing
@testable import MetalUITerminalUI

// Terminal phase 5.2 (`TRM-AZ`): the synthesised glyphs' geometry. Portable and exact: a rectangle set is read as
// a coverage grid, so "no gap" and "no overlap" are counted pixels. The pixels on a GPU are `GridSinkMetalTests`'s
// and `TerminalGlyphMetalTests`'s.

/// The coverage grid of `value` laid over `cells` neighbouring cells, solid rectangles added (an overlap counts 2).
private func grid(_ value: UInt32, cells: Int = 1, cw: Int, ch: Int) -> [[Int]] {
    var g = [[Int]](repeating: [Int](repeating: 0, count: cw * cells), count: ch)
    for cell in 0..<cells {
        for r in SyntheticGlyphs.rects(for: value, cellWidth: cw, cellHeight: ch) ?? [] where r.coverage == 255 {
            for y in r.y0..<r.y1 { for x in r.x0..<r.x1 { g[y][cell * cw + x] += 1 } }
        }
    }
    return g
}

/// The cell sizes of a 13 x 19 grid at scale 1 and 2, and two others (odd and small).
private let sizes: [(Int, Int)] = [(8, 16), (16, 32), (13, 19), (26, 38), (7, 15)]

/// **1** (`TRM-AZ` item 3). The arm table has one row per scalar of U+2500-257F, and every scalar of the three
/// rectangle ranges and the braille block answers a rectangle set inside its cell (or none, for a blank braille).
@Test func everySynthesisedScalarStaysInsideItsCell() throws {
    #expect(SyntheticGlyphs.arms.count == 128, "one arm row per box-drawing scalar")
    for (cw, ch) in sizes {
        for value in UInt32(0x2500)...0x28FF where SyntheticGlyphs.kind(of: value) == .rects {
            let rects = try #require(SyntheticGlyphs.rects(for: value, cellWidth: cw, cellHeight: ch))
            for r in rects {
                #expect(r.x0 >= 0 && r.y0 >= 0 && r.x1 <= cw && r.y1 <= ch && !r.isEmpty, "U+\(String(value, radix: 16)) at \(cw)x\(ch)")
            }
            if value < 0x2800 || value > 0x2800 { #expect(!rects.isEmpty || value == 0x2800, "U+\(String(value, radix: 16)) draws something") }
        }
    }
    #expect(SyntheticGlyphs.kind(of: 0x41) == nil && SyntheticGlyphs.kind(of: 0xE0A0) == nil, "letters and icons stay with the font")
}

/// **2** (`TRM-AZ` item 4). A horizontal light line through three adjacent cells is one unbroken run: every
/// column of the three cells is covered on the line's rows exactly once, no gap and no overlap, and no pixel off
/// the line is. At scale 1 (8 x 16) and 2 (16 x 32) and odd sizes. Mutation: end the right arm one pixel short
/// (`start = cw / 2 + 1`), or let both arms cover the centre column.
@Test func aHorizontalLineThroughThreeCellsHasNoGapAndNoOverlap() {
    for (cw, ch) in sizes {
        let g = grid(0x2500, cells: 3, cw: cw, ch: ch)
        let t = SyntheticGlyphs.lightStroke(cellWidth: cw)
        let lineRows = (ch - t) / 2..<(ch - t) / 2 + t
        for y in 0..<ch {
            for x in 0..<3 * cw {
                let want = lineRows.contains(y) ? 1 : 0
                if g[y][x] != want { Issue.record("\(cw)x\(ch): pixel \(x),\(y) covered \(g[y][x]) times, want \(want)"); return }
            }
        }
    }
}

/// **3** (`TRM-AZ` item 4). The same for a vertical line through three cells stacked, and a heavy and a double
/// line (the heavy is twice the light, the double two light strokes a light stroke apart).
@Test func verticalHeavyAndDoubleLinesAreSeamlessAndScaleWithTheCell() throws {
    for (cw, ch) in sizes {
        let t = SyntheticGlyphs.lightStroke(cellWidth: cw)
        // Vertical: cells stacked are the one cell's column coverage at y = 0 and y = ch - 1 being equal.
        for value: UInt32 in [0x2502, 0x2503, 0x2551] {
            let g = grid(value, cw: cw, ch: ch)
            #expect(g[0] == g[ch - 1], "U+\(String(value, radix: 16)): the top and bottom rows match, so stacked cells join (\(cw)x\(ch))")
            #expect(g.allSatisfy { $0 == g[0] }, "the line is the same on every row")
            #expect(g[0].allSatisfy { $0 <= 1 }, "no overlap")
        }
        let light = grid(0x2502, cw: cw, ch: ch)[0].reduce(0, +)
        let heavy = grid(0x2503, cw: cw, ch: ch)[0].reduce(0, +)
        let double = grid(0x2551, cw: cw, ch: ch)[0]
        #expect(light == t && heavy == 2 * t, "\(cw)x\(ch): light \(light), heavy \(heavy), t \(t)")
        #expect(double.reduce(0, +) == 2 * t)
        let first = try #require(double.firstIndex(of: 1))
        #expect(double[first + t] == 0 && (first + 2 * t < cw ? double[first + 2 * t] == 1 : true), "a gap of one light stroke")
    }
}

/// **4** (`TRM-AZ` item 4). Neighbouring box-drawing cells join: for every pair of scalars where the first has a
/// right arm of weight w and the second a left arm of weight w, the rows covered by the first at its last column
/// equal the rows covered by the second at its first column (and the same for down and up arms). This is the
/// property the line test is one case of, over the whole block. Mutation: draw a double arm's outer stroke one
/// pixel in.
@Test func everyArmMeetsItsNeighbourAtTheCellEdge() {
    let (cw, ch) = (8, 16)
    let scalars = (UInt32(0x2500)...0x257F).filter { !(0x2504...0x250B).contains($0) && !(0x254C...0x254F).contains($0) && !(0x256D...0x2573).contains($0) }
    func columns(_ v: UInt32, x: Int) -> [Int] { grid(v, cw: cw, ch: ch).map { $0[x] } }
    func rows(_ v: UInt32, y: Int) -> [Int] { grid(v, cw: cw, ch: ch)[y] }
    for a in scalars {
        let armsA = Array(SyntheticGlyphs.arms[Int(a - 0x2500)].utf8).map { Int($0) - 48 }
        for b in scalars {
            let armsB = Array(SyntheticGlyphs.arms[Int(b - 0x2500)].utf8).map { Int($0) - 48 }
            if armsA[1] > 0, armsA[1] == armsB[0] {
                if columns(a, x: cw - 1) != columns(b, x: 0) {
                    Issue.record("U+\(String(a, radix: 16)) right arm does not meet U+\(String(b, radix: 16)) left arm"); return
                }
            }
            if armsA[3] > 0, armsA[3] == armsB[2] {
                if rows(a, y: ch - 1) != rows(b, y: 0) {
                    Issue.record("U+\(String(a, radix: 16)) down arm does not meet U+\(String(b, radix: 16)) up arm"); return
                }
            }
        }
    }
}

/// **5** (`TRM-AZ` item 3). Blocks: the upper and lower halves partition the cell at every height (no row twice,
/// none missing), so do the left and right halves at every width, the four quadrant glyphs are the four
/// quarters, `█` is the whole cell, and the eighths grow by at least one pixel each.
@Test func blocksPartitionTheCell() {
    for (cw, ch) in sizes {
        let upper = grid(0x2580, cw: cw, ch: ch), lower = grid(0x2584, cw: cw, ch: ch)
        let left = grid(0x258C, cw: cw, ch: ch), right = grid(0x2590, cw: cw, ch: ch)
        for y in 0..<ch { for x in 0..<cw {
            #expect(upper[y][x] + lower[y][x] == 1 && left[y][x] + right[y][x] == 1, "\(cw)x\(ch) at \(x),\(y)")
        } }
        let quarters = [0x2598, 0x259D, 0x2596, 0x2597].map { grid(UInt32($0), cw: cw, ch: ch) }
        for y in 0..<ch { for x in 0..<cw { #expect(quarters.reduce(0) { $0 + $1[y][x] } == 1) } }
        #expect(grid(0x2588, cw: cw, ch: ch).allSatisfy { $0.allSatisfy { $0 == 1 } }, "the full block")
        let heights = (1...8).map { n in grid(UInt32(0x2580 + n), cw: cw, ch: ch).filter { $0[0] == 1 }.count }
        #expect(heights.last == ch && heights == heights.sorted() && Set(heights).count == heights.count || ch < 16,
                "the lower eighths grow: \(heights)")
        // ▙ ▛ ▜ ▟ ▚ ▞ are unions of quadrants.
        let nine = grid(0x2599, cw: cw, ch: ch), nineWant = zip(quarters[0], quarters[2]).map { zip($0, $1).map(+) }
        #expect(zip(nine, zip(nineWant, quarters[3])).allSatisfy { row, pair in zip(row, zip(pair.0, pair.1)).allSatisfy { $0 == $1.0 + $1.1 } })
    }
}

/// **6** (`TRM-AZ` item 3). The shades are the whole cell at 25, 50 and 75 percent coverage (a coverage on one
/// rectangle, so the sink blends it over the background).
@Test func theShadesAreOneCellRectAtTheirCoverage() throws {
    for (value, coverage) in [(0x2591, 64), (0x2592, 128), (0x2593, 191)] as [(UInt32, UInt8)] {
        let rects = try #require(SyntheticGlyphs.rects(for: value, cellWidth: 8, cellHeight: 16))
        #expect(rects == [CellRect(0, 0, 8, 16, coverage: coverage)])
    }
}

/// **7** (`TRM-AZ` item 3). Braille: the blank pattern draws nothing, the full pattern eight dots, a dot is where
/// its bit says (bit 0 top left, bit 3 top right, bit 6 and 7 the bottom row), dots never overlap, and the dot
/// grid is symmetric in the cell. Mutation: swap the bits of dots 3 and 7.
@Test func brailleDotsAreWhereTheirBitsSay() throws {
    for (cw, ch) in sizes {
        #expect(SyntheticGlyphs.rects(for: 0x2800, cellWidth: cw, cellHeight: ch)?.isEmpty == true)
        let full = try #require(SyntheticGlyphs.rects(for: 0x28FF, cellWidth: cw, cellHeight: ch))
        #expect(full.count == 8)
        let overlap = grid(0x28FF, cw: cw, ch: ch).flatMap { $0 }.max() ?? 0
        #expect(overlap == 1, "dots do not overlap (\(cw)x\(ch))")
        func dot(_ bits: UInt32) throws -> CellRect { try #require(SyntheticGlyphs.rects(for: 0x2800 + bits, cellWidth: cw, cellHeight: ch)?.first) }
        let topLeft = try dot(0x01), topRight = try dot(0x08), bottomLeft = try dot(0x40), bottomRight = try dot(0x80)
        let second = try dot(0x02), third = try dot(0x04)
        #expect(topLeft.x1 <= topRight.x0 && topLeft.y0 == topRight.y0)
        #expect(bottomLeft.y0 > third.y0 && third.y0 > second.y0 && second.y0 > topLeft.y0)
        #expect(bottomLeft.x0 == topLeft.x0 && bottomRight.x0 == topRight.x0)
        #expect(topLeft.x0 + topRight.x1 >= cw - 1 - 1 && topLeft.x0 + topRight.x1 <= cw + 1, "centred horizontally")
        #expect(topLeft.y0 + bottomLeft.y1 >= ch - 2 && topLeft.y0 + bottomLeft.y1 <= ch + 2, "centred vertically")
    }
}

/// The R8 coverage of a bitmap glyph.
private func image(_ value: UInt32, cw: Int, ch: Int) throws -> [[Int]] {
    let img = try #require(SyntheticGlyphs.raster(for: value, cellWidth: cw, cellHeight: ch))
    #expect(img.width == cw && img.height == ch)
    return (0..<ch).map { y in (0..<cw).map { x in Int(img.bytes[y * cw + x]) } }
}

/// **8** (`TRM-AZ` item 3). An arc meets its neighbours' lines: `╭` (right and down) is full coverage on the
/// vertical line's columns on its last row and on the horizontal line's rows on its last column; `╮`, `╯` and `╰`
/// likewise on their edges. Mutation: centre the arc on `cw / 2` instead of the line's centre.
@Test func arcsMeetTheLinesTheyJoin() throws {
    for (cw, ch) in sizes {
        let t = SyntheticGlyphs.lightStroke(cellWidth: cw)
        let vCols = (cw - t) / 2..<(cw - t) / 2 + t, hRows = (ch - t) / 2..<(ch - t) / 2 + t
        let tl = try image(0x2570, cw: cw, ch: ch), tr = try image(0x256F, cw: cw, ch: ch)
        let br = try image(0x256E, cw: cw, ch: ch), bl = try image(0x256D, cw: cw, ch: ch)
        for x in vCols {
            #expect(bl[ch - 1][x] >= 240 && br[ch - 1][x] >= 240, "down arms reach the bottom edge on the line's columns (\(cw)x\(ch))")
            #expect(tl[0][x] >= 240 && tr[0][x] >= 240, "up arms reach the top edge")
        }
        for y in hRows {
            #expect(bl[y][cw - 1] >= 240 && tl[y][cw - 1] >= 240, "right arms reach the right edge on the line's rows")
            #expect(br[y][0] >= 240 && tr[y][0] >= 240, "left arms reach the left edge")
        }
        #expect(bl[0][0] == 0 && bl[ch - 1][0] == 0, "the corner away from the curve is empty")
        // Mirror symmetry: ╭ flipped left-right is ╮ (the line centres are symmetric only for an even width,
        // so compare the stroke's total ink instead).
        let ink = { (g: [[Int]]) in g.flatMap { $0 }.reduce(0, +) }
        #expect(abs(ink(bl) - ink(br)) * 20 <= ink(bl) && abs(ink(tl) - ink(tr)) * 20 <= ink(tl))
    }
}

/// **9** (`TRM-AZ` item 3). Powerline arrows: `E0B0` is a triangle of half the cell's area, full on the left
/// column at the middle row and empty at its corners, symmetric top to bottom; `E0B2` is its mirror; the chevron
/// `E0B1` is the outline of the same shape (a thin stroke, far less ink); the half circle `E0B4` covers about
/// half an ellipse (pi / 4 of the cell). Mutation: draw the apex at the cell's top.
@Test func powerlineTrianglesCoverTheirShape() throws {
    for (cw, ch) in [(8, 16), (16, 32), (13, 19)] {
        let area = Double(cw * ch)
        func ink(_ g: [[Int]]) -> Double { Double(g.flatMap { $0 }.reduce(0, +)) / 255 }
        let tri = try image(0xE0B0, cw: cw, ch: ch)
        #expect(abs(ink(tri) - area / 2) / area < 0.02, "half the cell: \(ink(tri)) of \(area)")
        #expect(tri[ch / 2][0] >= 250 && tri[0][cw - 1] == 0 && tri[ch - 1][cw - 1] == 0)
        for y in 0..<ch { for x in 0..<cw { #expect(abs(tri[y][x] - tri[ch - 1 - y][x]) <= 40, "symmetric at \(x),\(y)") } }
        for y in 0..<ch { for x in 1..<cw { #expect(tri[y][x] <= tri[y][x - 1] + 1, "coverage never grows rightwards") } }
        let mirror = try image(0xE0B2, cw: cw, ch: ch)
        for y in 0..<ch { for x in 0..<cw { #expect(abs(mirror[y][x] - tri[y][cw - 1 - x]) <= 40) } }
        #expect(ink(try image(0xE0B1, cw: cw, ch: ch)) < ink(tri) / 2, "the chevron is only an outline")
        let half = ink(try image(0xE0B4, cw: cw, ch: ch))
        #expect(abs(half - area * 0.7853981) / area < 0.03, "a half ellipse: \(half)")
        let lowerLeft = try image(0xE0B8, cw: cw, ch: ch)
        #expect(abs(ink(lowerLeft) - area / 2) / area < 0.02 && lowerLeft[ch - 1][0] == 255 && lowerLeft[0][cw - 1] == 0)
    }
}

/// **10** (`TRM-AZ` item 3). A diagonal: `╲` runs corner to corner (ink on both end corners, none on the other
/// two), `╱` is its mirror and `╳` their union.
@Test func diagonalsRunCornerToCorner() throws {
    let (cw, ch) = (16, 32)
    let back = try image(0x2572, cw: cw, ch: ch), forward = try image(0x2571, cw: cw, ch: ch), cross = try image(0x2573, cw: cw, ch: ch)
    #expect(back[0][0] > 60 && back[ch - 1][cw - 1] > 60 && back[0][cw - 1] == 0 && back[ch - 1][0] == 0)
    #expect(forward[0][cw - 1] > 60 && forward[ch - 1][0] > 60 && forward[0][0] == 0 && forward[ch - 1][cw - 1] == 0)
    for y in 0..<ch { for x in 0..<cw { #expect(cross[y][x] == max(back[y][x], forward[y][x]) || cross[y][x] >= max(back[y][x], forward[y][x])) } }
}
