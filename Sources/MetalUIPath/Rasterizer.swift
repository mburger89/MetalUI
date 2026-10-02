/// How winding becomes coverage (probe PA2).
package enum FillRule: Hashable, Sendable { case nonZero, evenOdd }

/// The exact-area scanline rasterizer (ruling GX-B): each edge deposits its
/// signed area and cover into the cells it crosses — the font-rasterizer
/// technique — and a running sum along each row gives the winding coverage
/// of every pixel exactly (up to `Double` rounding), so a pixel half covered
/// by an edge reads half whatever the edge's slope. Nonzero is `min(|w|, 1)`,
/// even-odd the triangle wave of `|w|`.
///
/// Only the **visible** rectangle is rasterized: the polygons' bounding box
/// ∩ `clip`. Edges left of it are moved onto its left edge (they still carry
/// their winding across the row); edges right of it are dropped (they reach
/// no visible pixel); rows above and below are skipped.
package struct CoverageRasterizer: Sendable {
    /// The pixels the last call rasterized — what performance tests count,
    /// never time.
    package private(set) var lastRasterizedPixels = 0

    package init() {}

    /// Every polyline filled as a closed polygon (an open one closes, PA6).
    package mutating func rasterize(_ polygons: [Polyline], rule: FillRule, clip: RasterRect,
                                    antialiased: Bool = true) -> AlphaMask {
        lastRasterizedPixels = 0
        var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity
        for polygon in polygons where polygon.points.count > 2 {
            for p in polygon.points {
                minX = min(minX, p.x); minY = min(minY, p.y); maxX = max(maxX, p.x); maxY = max(maxY, p.y)
            }
        }
        let rect = RasterRect.enclosing(minX: minX, minY: minY, maxX: maxX, maxY: maxY).intersection(clip)
        guard !rect.isEmpty else { return AlphaMask(rect: RasterRect(x: clip.x, y: clip.y, width: 0, height: 0), alpha: []) }
        lastRasterizedPixels = rect.area
        let w = rect.width, h = rect.height
        let stride = w + 2
        var cells = [Double](repeating: 0, count: stride * h)
        let ox = Double(rect.x), oy = Double(rect.y), wd = Double(w)
        for polygon in polygons where polygon.points.count > 2 {
            let points = polygon.points
            for i in 0..<points.count {
                let a = points[i], b = points[(i + 1) % points.count]
                clippedEdge(a.x - ox, a.y - oy, b.x - ox, b.y - oy, width: wd, height: h, stride: stride, into: &cells)
            }
        }
        var alpha = [UInt8](repeating: 0, count: w * h)
        for y in 0..<h {
            var sum = 0.0
            let row = y * stride
            for x in 0..<w {
                sum += cells[row + x]
                var winding = sum < 0 ? -sum : sum
                switch rule {
                case .nonZero:
                    if winding > 1 { winding = 1 }
                case .evenOdd:
                    winding = winding.truncatingRemainder(dividingBy: 2)
                    if winding > 1 { winding = 2 - winding }
                }
                if antialiased {
                    let scaled = winding * 255 + 0.5
                    alpha[y * w + x] = scaled >= 255 ? 255 : UInt8(scaled)
                } else {
                    alpha[y * w + x] = winding >= 0.5 ? 255 : 0
                }
            }
        }
        return AlphaMask(rect: rect, alpha: alpha)
    }

    /// The edge (x0, y0)→(x1, y1) in raster space, split where it crosses
    /// x = 0 and x = width: a part left of 0 is moved onto x = 0, a part
    /// right of the raster is dropped.
    private func clippedEdge(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double,
                             width: Double, height: Int, stride: Int, into cells: inout [Double]) {
        guard y0 != y1 else { return }
        // Split points, as parameters along the edge.
        var ts: [Double] = [0, 1]
        if (x0 < 0) != (x1 < 0), x0 != x1 { ts.append((0 - x0) / (x1 - x0)) }
        if (x0 < width) != (x1 < width), x0 != x1 { ts.append((width - x0) / (x1 - x0)) }
        ts.sort()
        for i in 0..<(ts.count - 1) {
            let ta = ts[i], tb = ts[i + 1]
            guard tb > ta else { continue }
            let ax = ta == 0 ? x0 : (ta == 1 ? x1 : x0 + (x1 - x0) * ta)
            let ay = ta == 0 ? y0 : (ta == 1 ? y1 : y0 + (y1 - y0) * ta)
            let bx = tb == 0 ? x0 : (tb == 1 ? x1 : x0 + (x1 - x0) * tb)
            let by = tb == 0 ? y0 : (tb == 1 ? y1 : y0 + (y1 - y0) * tb)
            let mid = (ax + bx) / 2
            if mid >= width { continue }
            if mid <= 0 {
                line(0, ay, 0, by, height: height, stride: stride, into: &cells)
            } else {
                line(min(max(ax, 0), width), ay, min(max(bx, 0), width), by,
                     height: height, stride: stride, into: &cells)
            }
        }
    }

    /// Deposits one edge, x within [0, width], into the cells of the rows it
    /// crosses, clipped to rows 0..<height.
    private func line(_ xa: Double, _ ya: Double, _ xb: Double, _ yb: Double,
                      height: Int, stride: Int, into cells: inout [Double]) {
        guard ya != yb else { return }
        let direction: Double = ya < yb ? 1 : -1
        let (x0, y0, x1, y1) = ya < yb ? (xa, ya, xb, yb) : (xb, yb, xa, ya)
        let h = Double(height)
        guard y1 > 0, y0 < h else { return }
        let dxdy = (x1 - x0) / (y1 - y0)
        var top = y0
        var x = x0
        if top < 0 { x = x0 + (0 - y0) * dxdy; top = 0 }
        let end = y1 < h ? y1 : h
        var row = Int(top.rounded(.down))
        while Double(row) < end {
            let rowTop = Double(row) > top ? Double(row) : top
            let rowBottom = Double(row + 1) < end ? Double(row + 1) : end
            let dy = rowBottom - rowTop
            // The last row ends exactly at the edge's end point.
            let xNext = rowBottom == y1 ? x1 : x + dxdy * dy
            deposit(row: row, from: x, to: xNext, height: dy * direction, stride: stride, into: &cells)
            x = xNext
            row += 1
        }
    }

    /// One row's share of an edge running from x `xa` to `xb` while covering
    /// `d` (signed) of the row's height: its area left of each cell boundary
    /// goes to the cell, the rest to the next one, so the running sum along
    /// the row is the exact covered fraction (font-rs's accumulation).
    private func deposit(row: Int, from xa: Double, to xb: Double, height d: Double, stride: Int,
                         into cells: inout [Double]) {
        let base = row * stride
        let lo = xa < xb ? xa : xb, hi = xa < xb ? xb : xa
        let loFloor = lo.rounded(.down), hiCeil = hi.rounded(.up)
        let i0 = Int(loFloor), i1 = Int(hiCeil)
        if i1 <= i0 + 1 {
            // Within one cell: the area right of the edge's mean x.
            let mean = 0.5 * (xa + xb) - loFloor
            cells[base + i0] += d - d * mean
            cells[base + i0 + 1] += d * mean
            return
        }
        let s = 1 / (hi - lo)
        let loFrac = lo - loFloor
        let a0 = 0.5 * s * (1 - loFrac) * (1 - loFrac)
        let hiFrac = hi - hiCeil + 1
        let am = 0.5 * s * hiFrac * hiFrac
        cells[base + i0] += d * a0
        if i1 == i0 + 2 {
            cells[base + i0 + 1] += d * (1 - a0 - am)
        } else {
            let a1 = s * (1.5 - loFrac)
            cells[base + i0 + 1] += d * (a1 - a0)
            if i0 + 2 < i1 - 1 {
                for i in (i0 + 2)..<(i1 - 1) { cells[base + i] += d * s }
            }
            let a2 = a1 + Double(i1 - i0 - 3) * s
            cells[base + i1 - 1] += d * (1 - a2 - am)
        }
        cells[base + i1] += d * am
    }
}

/// Paths to coverage: flatten (and stroke), then rasterize (ruling GX-B).
package enum PathRaster {
    /// `geometry` under `transform`, filled by `rule` inside `clip`, in
    /// device pixels. The transform maps the control points before
    /// flattening, so the curve is flattened at the device tolerance.
    package static func fill(_ geometry: PathGeometry, rule: FillRule, transform: PathAffine = .identity,
                             clip: RasterRect, antialiased: Bool = true,
                             tolerance: Double = Flattener.defaultTolerance,
                             rasterizer: inout CoverageRasterizer) -> AlphaMask {
        let lines = Flattener.flatten(geometry.applying(transform), tolerance: tolerance)
        return rasterizer.rasterize(lines, rule: rule, clip: clip, antialiased: antialiased)
    }

    /// `geometry` stroked with `style` in its own space, then mapped by
    /// `transform` and filled nonzero — so a non-uniform scale widens the
    /// stroke as it would SwiftUI's. Flattening and the stroker's round
    /// pieces use the device tolerance divided by the transform's scale.
    package static func stroke(_ geometry: PathGeometry, style: StrokeParameters, transform: PathAffine = .identity,
                               clip: RasterRect, tolerance: Double = Flattener.defaultTolerance,
                               rasterizer: inout CoverageRasterizer) -> AlphaMask {
        let scale = transform.linearScale
        let localTolerance = scale > 1e-9 ? tolerance / scale : tolerance
        let lines = Flattener.flatten(geometry, tolerance: localTolerance)
        let outlines = Stroker.stroke(lines, style, tolerance: localTolerance).map { outline in
            Polyline(points: outline.points.map { transform.apply($0) }, closed: true)
        }
        return rasterizer.rasterize(outlines, rule: .nonZero, clip: clip)
    }
}
