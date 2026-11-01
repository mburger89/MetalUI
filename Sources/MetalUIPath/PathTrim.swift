// Arc length, trimming and outlines of a `PathGeometry` (ruling PG-A, PG-B,
// PG-C). Pure `+ − × ÷ sqrt` and comparisons, like the rest of this target,
// so a trimmed path and a stroked outline are the same bits on macOS, Linux
// and Windows (pinned by `trimmedPathIsBitIdenticalEverywhere`).

/// One measured segment of a subpath: a line, quadratic or cubic Bézier with
/// its arc length and, for a curve, the cumulative lengths that map a
/// distance back to the curve parameter.
private struct MeasuredSegment {
    enum Kind { case line, quad, cubic }
    var kind: Kind
    /// The control polygon: a line uses `p0, p3`, a quadratic `p0, p1, p3`,
    /// a cubic all four.
    var p0: PathPoint, p1: PathPoint, p2: PathPoint, p3: PathPoint
    var length: Double
    /// `chordSamples + 1` cumulative lengths ending at `length`; empty for a
    /// line.
    var table: [Double]

    /// Uniform parameter intervals per curve (pinned against a 1e-7
    /// flattening by `aCurvesLengthIsItsTrueArcLength`).
    static let chordSamples = 64

    init(line a: PathPoint, _ b: PathPoint) {
        kind = .line; p0 = a; p1 = a; p2 = b; p3 = b
        length = MeasuredSegment.distance(a, b); table = []
    }
    init(quad a: PathPoint, control c: PathPoint, _ b: PathPoint) {
        kind = .quad; p0 = a; p1 = c; p2 = c; p3 = b
        length = 0; table = []
        measure()
    }
    init(cubic a: PathPoint, _ c1: PathPoint, _ c2: PathPoint, _ b: PathPoint) {
        kind = .cubic; p0 = a; p1 = c1; p2 = c2; p3 = b
        length = 0; table = []
        measure()
    }

    static func distance(_ a: PathPoint, _ b: PathPoint) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        return (dx * dx + dy * dy).squareRoot()
    }

    func point(at t: Double) -> PathPoint {
        let u = 1 - t
        switch kind {
        case .line:
            return PathPoint(p0.x + (p3.x - p0.x) * t, p0.y + (p3.y - p0.y) * t)
        case .quad:
            let a = u * u, b = 2 * u * t, c = t * t
            return PathPoint(a * p0.x + b * p1.x + c * p3.x, a * p0.y + b * p1.y + c * p3.y)
        case .cubic:
            let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
            return PathPoint(a * p0.x + b * p1.x + c * p2.x + d * p3.x,
                             a * p0.y + b * p1.y + c * p2.y + d * p3.y)
        }
    }

    /// The speed |B'(t)|.
    private func speed(at t: Double) -> Double {
        let u = 1 - t
        var dx: Double, dy: Double
        switch kind {
        case .line:
            dx = p3.x - p0.x; dy = p3.y - p0.y
        case .quad:
            dx = 2 * (u * (p1.x - p0.x) + t * (p3.x - p1.x))
            dy = 2 * (u * (p1.y - p0.y) + t * (p3.y - p1.y))
        case .cubic:
            let a = 3 * u * u, b = 6 * u * t, c = 3 * t * t
            dx = a * (p1.x - p0.x) + b * (p2.x - p1.x) + c * (p3.x - p2.x)
            dy = a * (p1.y - p0.y) + b * (p2.y - p1.y) + c * (p3.y - p2.y)
        }
        return (dx * dx + dy * dy).squareRoot()
    }

    /// The cumulative arc length at each of `chordSamples + 1` uniform
    /// parameters, each interval integrated by Simpson's rule on the exact
    /// speed — error O(h⁴) per interval, ~1e-12 relative for a smooth Bézier,
    /// so a distance maps back to its parameter without the chord sum's
    /// curvature-dependent bias.
    private mutating func measure() {
        let n = MeasuredSegment.chordSamples
        let h = 1 / Double(n)
        var cumulative = [Double](repeating: 0, count: n + 1)
        var previousSpeed = speed(at: 0)
        var total = 0.0
        for i in 1...n {
            let t = Double(i) * h
            let mid = speed(at: t - h / 2)
            let next = speed(at: t)
            total += h / 6 * (previousSpeed + 4 * mid + next)
            cumulative[i] = total
            previousSpeed = next
        }
        length = total
        table = total > 0 ? cumulative : []
    }

    /// The curve parameter at arc distance `d` from the start.
    func parameter(atDistance d: Double) -> Double {
        if d <= 0 { return 0 }
        if d >= length { return 1 }
        switch kind {
        case .line:
            return d / length
        case .quad, .cubic:
            guard !table.isEmpty else { return d / length }
            let n = MeasuredSegment.chordSamples
            var lo = 0, hi = n
            while hi - lo > 1 {
                let mid = (lo + hi) / 2
                if table[mid] <= d { lo = mid } else { hi = mid }
            }
            let span = table[hi] - table[lo]
            let linear = (Double(lo) + (span > 0 ? (d - table[lo]) / span : 0)) / Double(n)
            // The cumulative length is smooth in t, so interpolate t(s) through the four
            // nearest samples (Neville) rather than along one chord: a fraction between
            // samples lands within ~1e-9 of the true arc-length position, not ~1e-5.
            let first = min(max(lo - 1, 0), n - 3)
            var xs = [table[first], table[first + 1], table[first + 2], table[first + 3]]
            var ts = [Double(first) / Double(n), Double(first + 1) / Double(n),
                      Double(first + 2) / Double(n), Double(first + 3) / Double(n)]
            for k in 1..<4 where xs[k] <= xs[k - 1] { return linear }
            for level in 1..<4 {
                for i in 0..<(4 - level) {
                    ts[i] = ((d - xs[i + level]) * ts[i] + (xs[i] - d) * ts[i + 1]) / (xs[i] - xs[i + level])
                }
                _ = level
            }
            xs[0] = d
            return min(max(ts[0], 0), 1)
        }
    }

    /// The part of this segment between parameters `t0 < t1`, as a segment of
    /// the same kind (a trimmed curve stays a curve).
    func piece(from t0: Double, to t1: Double) -> MeasuredSegment {
        switch kind {
        case .line:
            let a = t0 <= 0 ? p0 : point(at: t0)
            let b = t1 >= 1 ? p3 : point(at: t1)
            return MeasuredSegment(line: a, b)
        case .quad:
            // Split at t1, then the left part at t0 / t1.
            let (left, _) = MeasuredSegment.splitQuad(p0, p1, p3, t1 >= 1 ? 1 : t1)
            let u = t1 >= 1 ? t0 : (t1 > 0 ? t0 / t1 : 0)
            let (_, right) = MeasuredSegment.splitQuad(left.0, left.1, left.2, t0 <= 0 ? 0 : u)
            return MeasuredSegment(quad: right.0, control: right.1, right.2)
        case .cubic:
            let (left, _) = MeasuredSegment.splitCubic(p0, p1, p2, p3, t1 >= 1 ? 1 : t1)
            let u = t1 >= 1 ? t0 : (t1 > 0 ? t0 / t1 : 0)
            let (_, right) = MeasuredSegment.splitCubic(left.0, left.1, left.2, left.3, t0 <= 0 ? 0 : u)
            return MeasuredSegment(cubic: right.0, right.1, right.2, right.3)
        }
    }

    private static func lerp(_ a: PathPoint, _ b: PathPoint, _ t: Double) -> PathPoint {
        PathPoint(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t)
    }
    private static func splitQuad(_ a: PathPoint, _ c: PathPoint, _ b: PathPoint, _ t: Double)
        -> ((PathPoint, PathPoint, PathPoint), (PathPoint, PathPoint, PathPoint)) {
        if t <= 0 { return ((a, a, a), (a, c, b)) }
        if t >= 1 { return ((a, c, b), (b, b, b)) }
        let ac = lerp(a, c, t), cb = lerp(c, b, t), m = lerp(ac, cb, t)
        return ((a, ac, m), (m, cb, b))
    }
    private static func splitCubic(_ a: PathPoint, _ c1: PathPoint, _ c2: PathPoint, _ b: PathPoint, _ t: Double)
        -> ((PathPoint, PathPoint, PathPoint, PathPoint), (PathPoint, PathPoint, PathPoint, PathPoint)) {
        if t <= 0 { return ((a, a, a, a), (a, c1, c2, b)) }
        if t >= 1 { return ((a, c1, c2, b), (b, b, b, b)) }
        let ab = lerp(a, c1, t), bc = lerp(c1, c2, t), cd = lerp(c2, b, t)
        let abc = lerp(ab, bc, t), bcd = lerp(bc, cd, t)
        let m = lerp(abc, bcd, t)
        return ((a, ab, abc, m), (m, bcd, cd, b))
    }
}

/// A subpath with its measured segments (a closed subpath's closing edge is
/// the last one).
private struct MeasuredSubpath {
    var start: PathPoint
    var segments: [MeasuredSegment] = []
    var closed = false
    /// The source elements, `move` to `close`, copied when a trim keeps the
    /// whole subpath.
    var elements: [PathGeometry.Element] = []
    var length: Double { var sum = 0.0; for s in segments { sum += s.length }; return sum }
}

extension PathGeometry {
    private func measuredSubpaths() -> [MeasuredSubpath] {
        var out: [MeasuredSubpath] = []
        var current: MeasuredSubpath?
        var pen = PathPoint(0, 0)
        func finish(closing: Bool) {
            guard var sub = current else { return }
            if closing {
                if sub.start != pen { sub.segments.append(MeasuredSegment(line: pen, sub.start)) }
                sub.closed = true
                sub.elements.append(.close)
                pen = sub.start
            }
            if !sub.segments.isEmpty { out.append(sub) }
            current = nil
        }
        func ensure() {
            if current == nil {
                current = MeasuredSubpath(start: pen, elements: [.move(pen)])
            }
        }
        for element in elements {
            switch element {
            case .move(let p):
                finish(closing: false)
                pen = p
                current = MeasuredSubpath(start: p, elements: [element])
            case .line(let p):
                ensure()
                current?.segments.append(MeasuredSegment(line: pen, p)); current?.elements.append(element); pen = p
            case .quad(let c, let p):
                ensure()
                current?.segments.append(MeasuredSegment(quad: pen, control: c, p)); current?.elements.append(element); pen = p
            case .cubic(let c1, let c2, let p):
                ensure()
                current?.segments.append(MeasuredSegment(cubic: pen, c1, c2, p)); current?.elements.append(element); pen = p
            case .close:
                finish(closing: true)
            }
        }
        finish(closing: false)
        return out
    }

    /// The path's arc length: the sum over every subpath of its segments'
    /// lengths, a closed subpath's closing edge included (SwiftUI's
    /// `trimmedPath` measures the same, probe TR6b).
    package var arcLength: Double {
        var sum = 0.0
        for sub in measuredSubpaths() { sum += sub.length }
        return sum
    }

    /// The part of the path between fractions `start` and `end` of its total
    /// arc length (SwiftUI's `trimmedPath(from:to:)`, ruling PG-A).
    ///
    /// Fractions are clamped to `0…1`; `start >= end` (or a NaN) is empty.
    /// Subpaths are laid end to end in order, so one fraction runs across all
    /// of them. A subpath inside the range whole keeps its elements, `close`
    /// included; one cut by either end becomes an open subpath of lines and
    /// curves (a trimmed Bézier stays a Bézier of the same degree).
    package func trimmed(from start: Double, to end: Double) -> PathGeometry {
        guard !start.isNaN, !end.isNaN else { return PathGeometry() }
        let lo = min(max(start, 0), 1), hi = min(max(end, 0), 1)
        guard lo < hi else { return PathGeometry() }
        let subpaths = measuredSubpaths()
        var total = 0.0
        var lengths: [Double] = []
        for sub in subpaths { let l = sub.length; lengths.append(l); total += l }
        guard total > 0 else { return PathGeometry() }
        let a = lo * total, b = hi * total
        var out = PathGeometry()
        var offset = 0.0
        for (index, sub) in subpaths.enumerated() {
            let s0 = offset, s1 = offset + lengths[index]
            offset = s1
            if s1 <= a || s0 >= b { continue }
            if a <= s0 && b >= s1 {
                for element in sub.elements {
                    switch element {
                    case .move(let p): out.move(to: p)
                    case .line(let p): out.addLine(to: p)
                    case .quad(let c, let p): out.addQuadCurve(to: p, control: c)
                    case .cubic(let c1, let c2, let p): out.addCurve(to: p, control1: c1, control2: c2)
                    case .close: out.closeSubpath()
                    }
                }
                continue
            }
            let from = max(a, s0) - s0, to = min(b, s1) - s0
            var c0 = 0.0
            var started = false
            for seg in sub.segments {
                let c1 = c0 + seg.length
                defer { c0 = c1 }
                if c1 <= from || c0 >= to { continue }
                let t0 = from <= c0 ? 0 : seg.parameter(atDistance: from - c0)
                let t1 = to >= c1 ? 1 : seg.parameter(atDistance: to - c0)
                guard t1 > t0 else { continue }
                let part = (t0 <= 0 && t1 >= 1) ? seg : seg.piece(from: t0, to: t1)
                if !started { out.move(to: part.p0); started = true }
                switch part.kind {
                case .line: out.addLine(to: part.p3)
                case .quad: out.addQuadCurve(to: part.p3, control: part.p1)
                case .cubic: out.addCurve(to: part.p3, control1: part.p1, control2: part.p2)
                }
            }
        }
        return out
    }

    /// The outline of the stroke of this path under `style`, as closed
    /// polygons to be filled nonzero (the same outlines the rasterizer fills,
    /// ruling GX-E): curves flattened to `tolerance`, round joins and caps
    /// as polylines. A width ≤ 0 gives an empty path.
    package func stroked(_ style: StrokeParameters, tolerance: Double) -> PathGeometry {
        let lines = Flattener.flatten(self, tolerance: tolerance)
        var out = PathGeometry()
        for polygon in Stroker.stroke(lines, style, tolerance: tolerance) where polygon.points.count >= 3 {
            out.move(to: polygon.points[0])
            for p in polygon.points.dropFirst() { out.addLine(to: p) }
            out.closeSubpath()
        }
        return out
    }

    /// SwiftUI's `addArc` with a signed sweep: a line (or a move, on an empty
    /// path) to `startAngle`'s point on the circle, then `delta` radians of
    /// arc as cubics of at most 90° (ruling PG-D). A positive `delta` runs
    /// the positive angle direction, visually clockwise in y-down space; a
    /// sweep past a turn keeps going (probe AR4, X5: 450° ends at 90°, 1000°
    /// at 280°) where `addArc(center:…clockwise:)` caps at one turn.
    package mutating func addRelativeArc(center: PathPoint, radius: Double, startAngle: Double, delta: Double) {
        let (s0, c0) = PathMath.sinCos(startAngle)
        let start = PathPoint(center.x + radius * c0, center.y + radius * s0)
        if currentPoint == nil { move(to: start) } else { addLine(to: start) }
        guard radius > 0, delta != 0, delta.isFinite else { return }
        let quarter = 1.5707963267948966
        let magnitude = delta < 0 ? -delta : delta
        var count = Int((magnitude / quarter).rounded(.up))
        if count < 1 { count = 1 }
        let step = delta / Double(count)
        let (sq, cq) = PathMath.sinCos(step / 4)
        let k = 4.0 / 3.0 * (sq / cq)
        var a0 = startAngle
        var p0 = start, sin0 = s0, cos0 = c0
        for i in 1...count {
            let a1 = i == count ? startAngle + delta : a0 + step
            let (sin1, cos1) = PathMath.sinCos(a1)
            let p3 = PathPoint(center.x + radius * cos1, center.y + radius * sin1)
            let p1 = PathPoint(p0.x - k * radius * sin0, p0.y + k * radius * cos0)
            let p2 = PathPoint(p3.x + k * radius * sin1, p3.y - k * radius * cos1)
            addCurve(to: p3, control1: p1, control2: p2)
            a0 = a1; p0 = p3; sin0 = sin1; cos0 = cos1
        }
    }

    /// This geometry without its first `move` (the rest follows the pen already
    /// at that point).
    package func droppingLeadingMove() -> PathGeometry {
        var out = PathGeometry()
        var skipped = false
        for element in elements {
            if !skipped, case .move = element { skipped = true; continue }
            switch element {
            case .move(let p): out.move(to: p)
            case .line(let p): out.addLine(to: p)
            case .quad(let c, let p): out.addQuadCurve(to: p, control: c)
            case .cubic(let c1, let c2, let p): out.addCurve(to: p, control1: c1, control2: c2)
            case .close: out.closeSubpath()
            }
        }
        return out
    }

    /// Appends `other` mapped by `t`. With `joining`, the first `move` of
    /// `other` becomes a line from the current point when there is one (an
    /// arc's connecting line).
    package mutating func append(_ other: PathGeometry, transformedBy t: PathAffine, joining: Bool = false) {
        var first = true
        for element in other.applying(t).elements {
            defer { first = false }
            switch element {
            case .move(let p):
                if first && joining { addLine(to: p) } else { move(to: p) }
            case .line(let p): addLine(to: p)
            case .quad(let c, let p): addQuadCurve(to: p, control: c)
            case .cubic(let c1, let c2, let p): addCurve(to: p, control1: c1, control2: c2)
            case .close: closeSubpath()
            }
        }
    }
}
