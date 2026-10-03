/// One subpath as a polyline. `closed` is a `close` element's mark: a
/// stroke joins the last point to the first; a fill closes every polyline
/// either way (probe PA6: an open subpath fills as if closed).
package struct Polyline: Hashable, Sendable {
    package var points: [PathPoint]
    package var closed: Bool
    package init(points: [PathPoint], closed: Bool) { self.points = points; self.closed = closed }
}

/// Béziers to polylines by uniform subdivision, the segment count from
/// Wang's bound (ruling GX-B): `n = ⌈sqrt(k · M / tolerance)⌉`, `M` the
/// largest second difference of the control polygon, `k` 1/4 for a
/// quadratic and 3/4 for a cubic — `sqrt`, `×`, `÷` only.
package enum Flattener {
    /// 0.1 device pixels (ruling GX-B).
    package static let defaultTolerance = 0.1
    /// A segment cap per curve, so a pathological control polygon cannot ask
    /// for millions of points.
    package static let maxSegmentsPerCurve = 4096

    package static func segmentCount(secondDifference m: Double, factor: Double, tolerance: Double) -> Int {
        guard m > 0, tolerance > 0, m.isFinite else { return 1 }
        let n = (factor * m / tolerance).squareRoot().rounded(.up)
        guard n.isFinite else { return maxSegmentsPerCurve }
        return max(1, min(maxSegmentsPerCurve, Int(n)))
    }

    package static func flatten(_ geometry: PathGeometry, tolerance: Double = defaultTolerance) -> [Polyline] {
        var out: [Polyline] = []
        var current: [PathPoint] = []
        var pen = PathPoint(0, 0)
        func finish(closed: Bool) {
            if current.count > 1 || (closed && !current.isEmpty) { out.append(Polyline(points: current, closed: closed)) }
            current = []
        }
        func lineTo(_ p: PathPoint) {
            if current.isEmpty { current.append(pen) }
            if current.last != p { current.append(p) }
            pen = p
        }
        for element in geometry.elements {
            switch element {
            case .move(let p):
                finish(closed: false)
                current = [p]; pen = p
            case .line(let p):
                lineTo(p)
            case .quad(let c, let p):
                let p0 = pen
                let dx = p0.x - 2 * c.x + p.x, dy = p0.y - 2 * c.y + p.y
                let n = segmentCount(secondDifference: (dx * dx + dy * dy).squareRoot(), factor: 0.25,
                                     tolerance: tolerance)
                for i in 1...n {
                    if i == n { lineTo(p); break }
                    let t = Double(i) / Double(n), u = 1 - t
                    lineTo(PathPoint(u * u * p0.x + 2 * u * t * c.x + t * t * p.x,
                                     u * u * p0.y + 2 * u * t * c.y + t * t * p.y))
                }
            case .cubic(let c1, let c2, let p):
                let p0 = pen
                let ax = p0.x - 2 * c1.x + c2.x, ay = p0.y - 2 * c1.y + c2.y
                let bx = c1.x - 2 * c2.x + p.x, by = c1.y - 2 * c2.y + p.y
                let m = max((ax * ax + ay * ay).squareRoot(), (bx * bx + by * by).squareRoot())
                let n = segmentCount(secondDifference: m, factor: 0.75, tolerance: tolerance)
                for i in 1...n {
                    if i == n { lineTo(p); break }
                    let t = Double(i) / Double(n), u = 1 - t
                    let b0 = u * u * u, b1 = 3 * u * u * t, b2 = 3 * u * t * t, b3 = t * t * t
                    lineTo(PathPoint(b0 * p0.x + b1 * c1.x + b2 * c2.x + b3 * p.x,
                                     b0 * p0.y + b1 * c1.y + b2 * c2.y + b3 * p.y))
                }
            case .close:
                // The closing edge is implicit: drop a repeated start point.
                if current.count > 1, current.last == current.first { current.removeLast() }
                let start = current.first
                finish(closed: true)
                if let start { pen = start }
            }
        }
        finish(closed: false)
        return out
    }
}
