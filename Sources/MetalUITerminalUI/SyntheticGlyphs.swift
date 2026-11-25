import Foundation
import MetalUIScene

/// A rectangle inside a cell, in device pixels from the cell's top-left, with a coverage (255 is solid).
package struct CellRect: Equatable, Sendable {
    package var x0: Int
    package var y0: Int
    package var x1: Int
    package var y1: Int
    /// 255 for solid; a shade is less (`░` 64, `▒` 128, `▓` 191).
    package var coverage: UInt8

    package init(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, coverage: UInt8 = 255) {
        self.x0 = x0
        self.y0 = y0
        self.x1 = x1
        self.y1 = y1
        self.coverage = coverage
    }

    package var isEmpty: Bool { x1 <= x0 || y1 <= y0 }
}

/// Glyphs a terminal draws itself, to the cell size (`TRM-AZ`), so they meet their neighbours with no gap or
/// overlap whatever the font: box drawing U+2500-257F, blocks U+2580-259F, braille U+2800-28FF and Powerline
/// U+E0B0-E0BF.
///
/// **Exact shapes are rectangles** (lines, dashes, blocks, shades, quadrants, braille dots): the grid sink fills
/// them at whole device pixels with no atlas entry, so a horizontal line through three cells is one pixel run
/// with no seam (`TRM-AU`). **Curved and slanted shapes are bitmaps** the size of the cell (the arcs `╭╮╯╰`, the
/// diagonals `╱╲╳`, the Powerline triangles, chevrons and half circles), supersampled 4 x 4 into R8 coverage and
/// packed into the atlas under a key that names the cell size. U+E0A0-E0A3 and E0C0-E0D4 are icon glyphs of a
/// patched font and stay with the font.
///
/// **Weights scale with the cell.** The light stroke is `max(1, round(cellWidth / 8))` pixels, the heavy stroke
/// twice that, and a double line is two light strokes a light stroke apart; a stroke sits centred on the cell
/// (`(extent - weight) / 2`, rounded down), so every cell of one size puts its line on the same pixels.
package enum SyntheticGlyphs {
    /// How a scalar is drawn.
    package enum Kind: Equatable, Sendable {
        /// As ``rects(for:cellWidth:cellHeight:)``.
        case rects
        /// As ``raster(for:cellWidth:cellHeight:)``.
        case raster
    }

    /// How the terminal draws `value` itself, or `nil` when the font does.
    package static func kind(of value: UInt32) -> Kind? {
        switch value {
        case 0x2500...0x256C, 0x2574...0x259F, 0x2800...0x28FF: .rects
        case 0x256D...0x2573, 0xE0B0...0xE0BF: .raster
        default: nil
        }
    }

    /// The light stroke of a cell `cellWidth` wide.
    package static func lightStroke(cellWidth: Int) -> Int { max(1, Int((Double(cellWidth) / 8).rounded())) }

    // MARK: Rectangles

    /// The rectangles of `value` in a `cellWidth` x `cellHeight` cell, or `nil` for a scalar not drawn as rectangles.
    package static func rects(for value: UInt32, cellWidth cw: Int, cellHeight ch: Int) -> [CellRect]? {
        guard cw > 0, ch > 0, kind(of: value) == .rects else { return nil }
        var out: [CellRect]
        switch value {
        case 0x2500...0x257F: out = boxRects(value, cw: cw, ch: ch)
        case 0x2580...0x259F: out = blockRects(value, cw: cw, ch: ch)
        default: out = brailleRects(value, cw: cw, ch: ch)
        }
        out = out.compactMap { r in
            let c = CellRect(max(0, r.x0), max(0, r.y0), min(cw, r.x1), min(ch, r.y1), coverage: r.coverage)
            return c.isEmpty ? nil : c
        }
        return coalesced(out)
    }

    /// Merges rectangles of one coverage that share a whole edge, until none do.
    static func coalesced(_ input: [CellRect]) -> [CellRect] {
        var rects = input
        var changed = true
        while changed {
            changed = false
            outer: for i in 0..<rects.count {
                for j in (i + 1)..<rects.count where rects[i].coverage == rects[j].coverage {
                    let a = rects[i], b = rects[j]
                    var merged: CellRect?
                    if a.y0 == b.y0, a.y1 == b.y1, a.x1 >= b.x0, b.x1 >= a.x0 {
                        merged = CellRect(min(a.x0, b.x0), a.y0, max(a.x1, b.x1), a.y1, coverage: a.coverage)
                    } else if a.x0 == b.x0, a.x1 == b.x1, a.y1 >= b.y0, b.y1 >= a.y0 {
                        merged = CellRect(a.x0, min(a.y0, b.y0), a.x1, max(a.y1, b.y1), coverage: a.coverage)
                    }
                    if let merged {
                        rects[i] = merged
                        rects.remove(at: j)
                        changed = true
                        break outer
                    }
                }
            }
        }
        return rects
    }

    // MARK: Box drawing

    /// The arm weights (left, right, up, down; 0 none, 1 light, 2 heavy, 3 double) of U+2500...257F, four digits
    /// per scalar; `0000` for the dashes (drawn apart) and the arcs and diagonals (drawn as bitmaps).
    static let arms: [String] = [
        "1100", "2200", "0011", "0022", "0000", "0000", "0000", "0000", "0000", "0000", "0000", "0000",
        "0101", "0201", "0102", "0202", "1001", "2001", "1002", "2002", "0110", "0210", "0120", "0220",
        "1010", "2010", "1020", "2020", "0111", "0211", "0121", "0112", "0122", "0221", "0212", "0222",
        "1011", "2011", "1021", "1012", "1022", "2021", "2012", "2022", "1101", "2101", "1201", "2201",
        "1102", "2102", "1202", "2202", "1110", "2110", "1210", "2210", "1120", "2120", "1220", "2220",
        "1111", "2111", "1211", "2211", "1121", "1112", "1122", "2121", "1221", "2112", "1212", "2221",
        "2212", "2122", "1222", "2222", "0000", "0000", "0000", "0000",
        "3300", "0033", "0301", "0103", "0303", "3001", "1003", "3003", "0310", "0130", "0330", "3010",
        "1030", "3030", "0311", "0133", "0333", "3011", "1033", "3033", "3301", "1103", "3303", "3310",
        "1130", "3330", "3311", "1133", "3333", "0000", "0000", "0000", "0000", "0000", "0000", "0000",
        "1000", "0010", "0100", "0001", "2000", "0020", "0200", "0002", "1200", "0012", "2100", "0021"
    ]

    private static func boxRects(_ value: UInt32, cw: Int, ch: Int) -> [CellRect] {
        let t = lightStroke(cellWidth: cw)
        let heavy = 2 * t
        // Dashes: segment count and direction, by scalar.
        switch value {
        case 0x2504, 0x2505: return dashes(horizontal: true, count: 3, weight: value == 0x2504 ? t : heavy, cw: cw, ch: ch)
        case 0x2506, 0x2507: return dashes(horizontal: false, count: 3, weight: value == 0x2506 ? t : heavy, cw: cw, ch: ch)
        case 0x2508, 0x2509: return dashes(horizontal: true, count: 4, weight: value == 0x2508 ? t : heavy, cw: cw, ch: ch)
        case 0x250A, 0x250B: return dashes(horizontal: false, count: 4, weight: value == 0x250A ? t : heavy, cw: cw, ch: ch)
        case 0x254C, 0x254D: return dashes(horizontal: true, count: 2, weight: value == 0x254C ? t : heavy, cw: cw, ch: ch)
        case 0x254E, 0x254F: return dashes(horizontal: false, count: 2, weight: value == 0x254E ? t : heavy, cw: cw, ch: ch)
        default: break
        }
        let digits = Array(arms[Int(value - 0x2500)].utf8).map { Int($0) - 48 }
        let (wL, wR, wU, wD) = (digits[0], digits[1], digits[2], digits[3])
        guard wL + wR + wU + wD > 0 else { return [] }

        /// The stroke spans of weight `w` across an axis `extent` pixels long.
        func spans(_ w: Int, _ extent: Int) -> [(Int, Int)] {
            switch w {
            case 1: let lo = (extent - t) / 2; return [(lo, lo + t)]
            case 2: let lo = (extent - heavy) / 2; return [(lo, lo + heavy)]
            case 3: let lo = max(0, (extent - 3 * t) / 2); return [(lo, lo + t), (lo + 2 * t, lo + 3 * t)]
            default: return []
            }
        }
        let wV = max(wU, wD), wH = max(wL, wR)
        let hasV = wV > 0, hasH = wH > 0
        let vs = spans(wV, cw), hs = spans(wH, ch)    // widest vertical (x spans) and horizontal (y spans)
        // Read only under `hasV` / `hasH`, where `spans` answers one or two strokes (weights are 0...3).
        let vFirst = vs.first ?? (0, 0), vLast = vs.last ?? (0, 0), hFirst = hs.first ?? (0, 0), hLast = hs.last ?? (0, 0)
        var out: [CellRect] = []

        // Horizontal arms: where each stroke stops short of (or runs into) the vertical.
        for (k, (y0, y1)) in spans(wL, ch).enumerated() {
            var end = cw / 2
            if hasV {
                if wL == 3, wV == 3 {
                    if wU > 0, wD > 0 { end = vFirst.1 }
                    else if wU > 0 { end = k == 0 ? vFirst.1 : vLast.1 }
                    else { end = k == 0 ? vLast.1 : vFirst.1 }
                } else if wV == 3 { end = wR > 0 ? vLast.1 : vFirst.1 }
                else { end = vFirst.1 }
            }
            out.append(CellRect(0, y0, end, y1))
        }
        for (k, (y0, y1)) in spans(wR, ch).enumerated() {
            var start = cw / 2
            if hasV {
                if wR == 3, wV == 3 {
                    if wU > 0, wD > 0 { start = vLast.0 }
                    else if wU > 0 { start = k == 0 ? vLast.0 : vFirst.0 }
                    else { start = k == 0 ? vFirst.0 : vLast.0 }
                } else if wV == 3 { start = wL > 0 ? vFirst.0 : vLast.0 }
                else { start = vFirst.0 }
            }
            out.append(CellRect(start, y0, cw, y1))
        }
        // Vertical arms.
        for (k, (x0, x1)) in spans(wU, cw).enumerated() {
            var end = ch / 2
            if hasH {
                if wU == 3, wH == 3 {
                    if wL > 0, wR > 0 { end = wD > 0 ? hFirst.1 : hLast.1 }
                    else if wL > 0 { end = k == 0 ? hFirst.1 : hLast.1 }
                    else { end = k == 0 ? hLast.1 : hFirst.1 }
                } else if wH == 3 { end = wD > 0 ? hLast.1 : hFirst.1 }
                else { end = hFirst.1 }
            }
            out.append(CellRect(x0, 0, x1, end))
        }
        for (k, (x0, x1)) in spans(wD, cw).enumerated() {
            var start = ch / 2
            if hasH {
                if wD == 3, wH == 3 {
                    if wL > 0, wR > 0 { start = wU > 0 ? hLast.0 : hFirst.0 }
                    else if wL > 0 { start = k == 0 ? hLast.0 : hFirst.0 }
                    else { start = k == 0 ? hFirst.0 : hLast.0 }
                } else if wH == 3 { start = wU > 0 ? hFirst.0 : hLast.0 }
                else { start = hLast.0 }
            }
            out.append(CellRect(x0, start, x1, ch))
        }
        return out
    }

    /// `count` dashes of `weight` along the centre line, each with a quarter of the period of gap at either end,
    /// so the pattern is periodic across neighbouring cells.
    private static func dashes(horizontal: Bool, count: Int, weight: Int, cw: Int, ch: Int) -> [CellRect] {
        let along = horizontal ? cw : ch, across = horizontal ? ch : cw
        let lo = (across - weight) / 2
        let period = Double(along) / Double(count)
        var out: [CellRect] = []
        for i in 0..<count {
            let a = Int((Double(i) * period + period / 4).rounded())
            let b = max(a + 1, Int((Double(i + 1) * period - period / 4).rounded()))
            out.append(horizontal ? CellRect(a, lo, b, lo + weight) : CellRect(lo, a, lo + weight, b))
        }
        return out
    }

    // MARK: Blocks and shades

    private static func blockRects(_ value: UInt32, cw: Int, ch: Int) -> [CellRect] {
        let hx = cw / 2, hy = ch / 2
        /// The top of a lower block of `n` eighths (a half is the floor split, so `▀` and `▄` partition the cell).
        func lowerTop(_ n: Int) -> Int { n == 4 ? hy : ch - max(1, (ch * n + 4) / 8) }
        func leftWidth(_ n: Int) -> Int { n == 4 ? hx : max(1, (cw * n + 4) / 8) }
        let ul = CellRect(0, 0, hx, hy), ur = CellRect(hx, 0, cw, hy)
        let ll = CellRect(0, hy, hx, ch), lr = CellRect(hx, hy, cw, ch)
        switch value {
        case 0x2580: return [CellRect(0, 0, cw, hy)]
        case 0x2581...0x2588: return [CellRect(0, lowerTop(Int(value - 0x2580)), cw, ch)]
        case 0x2589...0x258F: return [CellRect(0, 0, leftWidth(8 - Int(value - 0x2588)), ch)]
        case 0x2590: return [CellRect(hx, 0, cw, ch)]
        case 0x2591: return [CellRect(0, 0, cw, ch, coverage: 64)]
        case 0x2592: return [CellRect(0, 0, cw, ch, coverage: 128)]
        case 0x2593: return [CellRect(0, 0, cw, ch, coverage: 191)]
        case 0x2594: return [CellRect(0, 0, cw, max(1, (ch + 4) / 8))]
        case 0x2595: return [CellRect(cw - max(1, (cw + 4) / 8), 0, cw, ch)]
        case 0x2596: return [ll]
        case 0x2597: return [lr]
        case 0x2598: return [ul]
        case 0x2599: return [ul, ll, lr]
        case 0x259A: return [ul, lr]
        case 0x259B: return [ul, ur, ll]
        case 0x259C: return [ul, ur, lr]
        case 0x259D: return [ur]
        case 0x259E: return [ur, ll]
        default: return [ur, ll, lr]       // 259F
        }
    }

    // MARK: Braille

    /// Each set dot of U+2800+bits is a square of `max(1, min(cw / 4, ch / 8))` pixels centred in its 2 x 4 slot.
    private static func brailleRects(_ value: UInt32, cw: Int, ch: Int) -> [CellRect] {
        let bits = Int(value - 0x2800)
        let slots: [(Int, Int)] = [(0, 0), (0, 1), (0, 2), (1, 0), (1, 1), (1, 2), (0, 3), (1, 3)]
        let d = max(1, min(cw / 4, ch / 8))
        var out: [CellRect] = []
        for (bit, slot) in slots.enumerated() where bits & (1 << bit) != 0 {
            let cx = Double(cw) * Double(1 + 2 * slot.0) / 4, cy = Double(ch) * Double(1 + 2 * slot.1) / 8
            let x0 = min(max(0, Int((cx - Double(d) / 2).rounded())), max(0, cw - d))
            let y0 = min(max(0, Int((cy - Double(d) / 2).rounded())), max(0, ch - d))
            out.append(CellRect(x0, y0, x0 + d, y0 + d))
        }
        return out
    }

    // MARK: Bitmaps

    /// The cell-sized R8 coverage of `value`, or `nil` for a scalar not drawn as a bitmap.
    package static func raster(for value: UInt32, cellWidth cw: Int, cellHeight ch: Int) -> GlyphImage? {
        guard cw > 0, ch > 0, kind(of: value) == .raster else { return nil }
        let t = Double(lightStroke(cellWidth: cw))
        let w = Double(cw), h = Double(ch)
        // The centre lines box drawing puts a light stroke on, so an arc meets the neighbour's line exactly.
        let cxLine = Double((cw - Int(t)) / 2) + t / 2, cyLine = Double((ch - Int(t)) / 2) + t / 2
        func arc(centreX: Double, centreY: Double, rx: Double, ry: Double) -> (Double, Double) -> Bool {
            let scale = min(rx, ry)
            return { x, y in abs(hypot((x - centreX) / rx, (y - centreY) / ry) - 1) * scale <= t / 2 }
        }
        func stroke(_ a: (Double, Double), _ b: (Double, Double)) -> (Double, Double) -> Bool {
            { x, y in distance(x, y, a, b) <= t / 2 }
        }
        func triangle(_ a: (Double, Double), _ b: (Double, Double), _ c: (Double, Double)) -> (Double, Double) -> Bool {
            { x, y in inside(x, y, a, b, c) }
        }
        let shape: (Double, Double) -> Bool
        switch value {
        case 0x256D: shape = arc(centreX: w, centreY: h, rx: w - cxLine, ry: h - cyLine)
        case 0x256E: shape = arc(centreX: 0, centreY: h, rx: cxLine, ry: h - cyLine)
        case 0x256F: shape = arc(centreX: 0, centreY: 0, rx: cxLine, ry: cyLine)
        case 0x2570: shape = arc(centreX: w, centreY: 0, rx: w - cxLine, ry: cyLine)
        case 0x2571: shape = stroke((w, 0), (0, h))
        case 0x2572: shape = stroke((0, 0), (w, h))
        case 0x2573:
            let a = stroke((w, 0), (0, h)), b = stroke((0, 0), (w, h))
            shape = { a($0, $1) || b($0, $1) }
        case 0xE0B0: shape = triangle((0, 0), (w, h / 2), (0, h))
        case 0xE0B1:
            let a = stroke((0, 0), (w, h / 2)), b = stroke((w, h / 2), (0, h))
            shape = { a($0, $1) || b($0, $1) }
        case 0xE0B2: shape = triangle((w, 0), (0, h / 2), (w, h))
        case 0xE0B3:
            let a = stroke((w, 0), (0, h / 2)), b = stroke((0, h / 2), (w, h))
            shape = { a($0, $1) || b($0, $1) }
        case 0xE0B4: shape = { x, y in x >= 0 && ((x / w) * (x / w) + ((y - h / 2) / (h / 2)) * ((y - h / 2) / (h / 2))) <= 1 }
        case 0xE0B5: shape = { x, y in
            x >= 0 && abs(hypot(x / w, (y - h / 2) / (h / 2)) - 1) * min(w, h / 2) <= t / 2 }
        case 0xE0B6: shape = { x, y in
            let u = (w - x) / w, v = (y - h / 2) / (h / 2); return u * u + v * v <= 1 }
        case 0xE0B7: shape = { x, y in
            abs(hypot((w - x) / w, (y - h / 2) / (h / 2)) - 1) * min(w, h / 2) <= t / 2 }
        case 0xE0B8: shape = triangle((0, 0), (0, h), (w, h))
        case 0xE0B9: shape = stroke((0, 0), (w, h))
        case 0xE0BA: shape = triangle((w, 0), (w, h), (0, h))
        case 0xE0BB: shape = stroke((w, 0), (0, h))
        case 0xE0BC: shape = triangle((0, 0), (w, 0), (0, h))
        case 0xE0BD: shape = stroke((w, 0), (0, h))
        case 0xE0BE: shape = triangle((0, 0), (w, 0), (w, h))
        default: shape = stroke((0, 0), (w, h))      // E0BF
        }
        return image(cw, ch, shape)
    }

    private static func image(_ cw: Int, _ ch: Int, _ inside: (Double, Double) -> Bool) -> GlyphImage {
        let n = 4
        var bytes = [UInt8](repeating: 0, count: cw * ch)
        for py in 0..<ch {
            for px in 0..<cw {
                var hits = 0
                for sy in 0..<n {
                    for sx in 0..<n
                    where inside(Double(px) + (Double(sx) + 0.5) / Double(n), Double(py) + (Double(sy) + 0.5) / Double(n)) {
                        hits += 1
                    }
                }
                bytes[py * cw + px] = UInt8((hits * 255 + n * n / 2) / (n * n))
            }
        }
        return GlyphImage(width: cw, height: ch, bytes: bytes)
    }

    private static func distance(_ x: Double, _ y: Double, _ a: (Double, Double), _ b: (Double, Double)) -> Double {
        let dx = b.0 - a.0, dy = b.1 - a.1
        let along = max(0, min(1, ((x - a.0) * dx + (y - a.1) * dy) / (dx * dx + dy * dy)))
        return hypot(x - (a.0 + along * dx), y - (a.1 + along * dy))
    }

    private static func inside(_ x: Double, _ y: Double, _ a: (Double, Double), _ b: (Double, Double),
                               _ c: (Double, Double)) -> Bool {
        func side(_ p: (Double, Double), _ q: (Double, Double)) -> Double { (q.0 - p.0) * (y - p.1) - (q.1 - p.1) * (x - p.0) }
        let (d1, d2, d3) = (side(a, b), side(b, c), side(c, a))
        return !((d1 < 0 || d2 < 0 || d3 < 0) && (d1 > 0 || d2 > 0 || d3 > 0))
    }
}
