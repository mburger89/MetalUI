/// SwiftUI's `CGLineCap` cases.
package enum LineCapStyle: Hashable, Sendable { case butt, round, square }
/// SwiftUI's `CGLineJoin` cases.
package enum LineJoinStyle: Hashable, Sendable { case miter, round, bevel }

/// A stroke's style in the stroker's own space (ruling GX-E): SwiftUI's
/// defaults — width 1, butt, miter, limit 10, no dash.
package struct StrokeParameters: Hashable, Sendable {
    package var width: Double
    package var cap: LineCapStyle
    package var join: LineJoinStyle
    package var miterLimit: Double
    package var dash: [Double]
    package var dashPhase: Double
    package init(width: Double = 1, cap: LineCapStyle = .butt, join: LineJoinStyle = .miter,
                 miterLimit: Double = 10, dash: [Double] = [], dashPhase: Double = 0) {
        self.width = width; self.cap = cap; self.join = join; self.miterLimit = miterLimit
        self.dash = dash; self.dashPhase = dashPhase
    }
}

/// Polylines to the outline polygons of their stroke, to be filled nonzero
/// (ruling GX-E). Each subpath's outline is one polygon — its left offset
/// forward, the end cap, its other offset backward, the start cap — or, for
/// a closed subpath, two loops of opposite orientation (the band between
/// them is the stroke). The outer side of a join gets the join; the inner
/// side goes through the vertex itself (the pivot), which nonzero filling
/// turns into the right coverage without clipping the offsets against each
/// other. Every outline winds the same way, so overlapping pieces (dashes
/// crossing, a curve folding) union rather than cancel.
package enum Stroker {
    package static func stroke(_ lines: [Polyline], _ style: StrokeParameters,
                               tolerance: Double = Flattener.defaultTolerance) -> [Polyline] {
        guard style.width > 0, style.width.isFinite else { return [] }
        let h = style.width / 2
        // The angle step whose chord stays within `tolerance` of a circle of
        // radius h: h(1 − cos(θ/2)) ≈ hθ²/8.
        let step = max(0.01, min(0.7853981633974483, (8 * tolerance / h).squareRoot()))
        var pieces: [Polyline] = []
        for line in lines {
            let cleaned = deduplicated(line)
            if isDashed(style) {
                pieces += dashes(cleaned, pattern: style.dash, phase: style.dashPhase)
            } else {
                pieces.append(cleaned)
            }
        }
        var out: [Polyline] = []
        for piece in pieces {
            out += outline(piece, h: h, style: style, step: step)
        }
        return out
    }

    // MARK: Dashes

    package static func isDashed(_ style: StrokeParameters) -> Bool {
        guard !style.dash.isEmpty, style.dash.allSatisfy({ $0 >= 0 && $0.isFinite }) else { return false }
        return style.dash.reduce(0, +) > 0
    }

    /// The "on" intervals of `line`, walked by arc length from `phase`
    /// (probe ST7). An odd pattern repeats twice, as CoreGraphics' does.
    package static func dashes(_ line: Polyline, pattern raw: [Double], phase: Double) -> [Polyline] {
        let pattern = raw.count % 2 == 1 ? raw + raw : raw
        let total = pattern.reduce(0, +)
        var points = line.points
        if line.closed, let first = points.first, points.count > 1 { points.append(first) }
        guard points.count > 1 else { return [] }
        // Where in the pattern the walk starts.
        var offset = phase.truncatingRemainder(dividingBy: total)
        if offset < 0 { offset += total }
        var index = 0
        while offset >= pattern[index] {
            offset -= pattern[index]
            index = (index + 1) % pattern.count
            if pattern.allSatisfy({ $0 == 0 }) { break }
        }
        var remaining = pattern[index] - offset
        var on = index % 2 == 0
        var out: [Polyline] = []
        var current: [PathPoint] = on ? [points[0]] : []
        for i in 0..<(points.count - 1) {
            let a = points[i], b = points[i + 1]
            let dx = b.x - a.x, dy = b.y - a.y
            let length = (dx * dx + dy * dy).squareRoot()
            var travelled = 0.0
            while length - travelled > remaining {
                travelled += remaining
                let t = travelled / length
                let p = PathPoint(a.x + dx * t, a.y + dy * t)
                if on {
                    current.append(p)
                    out.append(Polyline(points: current, closed: false))
                    current = []
                } else {
                    current = [p]
                }
                on.toggle()
                index = (index + 1) % pattern.count
                remaining = pattern[index]
            }
            remaining -= length - travelled
            if on { current.append(b) }
        }
        if on, current.count > 1 { out.append(Polyline(points: current, closed: false)) }
        return out
    }

    // MARK: Outline

    private static func deduplicated(_ line: Polyline) -> Polyline {
        var points: [PathPoint] = []
        for p in line.points where points.last != p { points.append(p) }
        if line.closed, points.count > 1, points.first == points.last { points.removeLast() }
        return Polyline(points: points, closed: line.closed)
    }

    private static func unit(_ a: PathPoint, _ b: PathPoint) -> PathPoint {
        let dx = b.x - a.x, dy = b.y - a.y
        let l = (dx * dx + dy * dy).squareRoot()
        return PathPoint(dx / l, dy / l)
    }

    /// The left normal of direction d: (−d.y, d.x).
    private static func normal(_ d: PathPoint) -> PathPoint { PathPoint(-d.y, d.x) }

    private static func outline(_ line: Polyline, h: Double, style: StrokeParameters, step: Double) -> [Polyline] {
        var points = line.points
        if points.count == 1 || (points.count == 2 && line.closed && points[0] == points[1]) {
            return dot(points[0], h: h, cap: style.cap, step: step)
        }
        guard points.count > 1 else { return [] }
        if line.closed {
            var forward: [PathPoint] = []
            appendLoop(points, h: h, style: style, step: step, into: &forward)
            var backward: [PathPoint] = []
            appendLoop(points.reversed(), h: h, style: style, step: step, into: &backward)
            return [Polyline(points: forward, closed: true), Polyline(points: backward, closed: true)]
        }
        var out: [PathPoint] = []
        appendSide(points, h: h, style: style, step: step, into: &out)
        let endDirection = unit(points[points.count - 2], points[points.count - 1])
        appendCap(at: points[points.count - 1], direction: endDirection, h: h, cap: style.cap, step: step, into: &out)
        points.reverse()
        appendSide(points, h: h, style: style, step: step, into: &out)
        let startDirection = unit(points[points.count - 2], points[points.count - 1])
        appendCap(at: points[points.count - 1], direction: startDirection, h: h, cap: style.cap, step: step, into: &out)
        return [Polyline(points: out, closed: true)]
    }

    /// The left offset of an open polyline, its interior joins included,
    /// from the first point's offset to the last's.
    private static func appendSide(_ points: [PathPoint], h: Double, style: StrokeParameters, step: Double,
                                   into out: inout [PathPoint]) {
        let first = normal(unit(points[0], points[1]))
        out.append(PathPoint(points[0].x + h * first.x, points[0].y + h * first.y))
        if points.count > 2 {
            for i in 1..<(points.count - 1) {
                appendJoin(at: points[i], incoming: unit(points[i - 1], points[i]), outgoing: unit(points[i], points[i + 1]),
                           h: h, style: style, step: step, into: &out)
            }
        }
        let n = points.count
        let last = normal(unit(points[n - 2], points[n - 1]))
        out.append(PathPoint(points[n - 1].x + h * last.x, points[n - 1].y + h * last.y))
    }

    /// The left offset of a closed polyline, a join at every vertex.
    private static func appendLoop(_ points: [PathPoint], h: Double, style: StrokeParameters, step: Double,
                                   into out: inout [PathPoint]) {
        let n = points.count
        for i in 0..<n {
            let previous = points[(i + n - 1) % n], next = points[(i + 1) % n]
            appendJoin(at: points[i], incoming: unit(previous, points[i]), outgoing: unit(points[i], next),
                       h: h, style: style, step: step, into: &out)
        }
    }

    private static func appendJoin(at v: PathPoint, incoming din: PathPoint, outgoing dout: PathPoint,
                                   h: Double, style: StrokeParameters, step: Double, into out: inout [PathPoint]) {
        let n1 = normal(din), n2 = normal(dout)
        let a = PathPoint(v.x + h * n1.x, v.y + h * n1.y)
        let b = PathPoint(v.x + h * n2.x, v.y + h * n2.y)
        let cross = din.x * dout.y - din.y * dout.x
        let dot = din.x * dout.x + din.y * dout.y
        if cross == 0 && dot > 0 { out.append(a); return }          // straight on
        if cross > 0 {                                              // the left side is inside the turn
            out.append(a); out.append(v); out.append(b); return
        }
        switch style.join {
        case .bevel:
            out.append(a); out.append(b)
        case .miter:
            // miter length / width = 1 / sin(θ/2) = 1 / cos(α/2), α the turn.
            let cosHalf = ((1 + dot) / 2).squareRoot()
            if cosHalf > 0, 1 / cosHalf <= style.miterLimit {
                let sx = n1.x + n2.x, sy = n1.y + n2.y
                let sl = (sx * sx + sy * sy).squareRoot()
                let reach = h / cosHalf
                out.append(a)
                out.append(PathPoint(v.x + sx / sl * reach, v.y + sy / sl * reach))
                out.append(b)
            } else {
                out.append(a); out.append(b)
            }
        case .round:
            out.append(a)
            appendArc(around: v, from: n1, to: n2, fallback: din, h: h, step: step, into: &out)
            out.append(b)
        }
    }

    /// Points strictly between `from` and `to` (unit vectors) on the circle
    /// of radius h about `c`, the short way round; `fallback` is the
    /// direction a half turn passes through.
    private static func appendArc(around c: PathPoint, from n1: PathPoint, to n2: PathPoint, fallback: PathPoint,
                                  h: Double, step: Double, into out: inout [PathPoint]) {
        let cosAlpha = n1.x * n2.x + n1.y * n2.y
        var tx = n2.x - cosAlpha * n1.x, ty = n2.y - cosAlpha * n1.y
        let tl = (tx * tx + ty * ty).squareRoot()
        if tl > 1e-12 { tx /= tl; ty /= tl } else { tx = fallback.x; ty = fallback.y }
        var k = 1
        while true {
            let (s, co) = PathMath.sinCos(Double(k) * step)
            if Double(k) * step >= 3.141592653589793 || co <= cosAlpha { break }
            out.append(PathPoint(c.x + h * (n1.x * co + tx * s), c.y + h * (n1.y * co + ty * s)))
            k += 1
        }
    }

    /// The cap at `p`, from its left offset (already appended) to its right
    /// one (appended next by the caller): butt nothing, square w/2 out, round
    /// a half circle through `p + h·direction`.
    private static func appendCap(at p: PathPoint, direction d: PathPoint, h: Double, cap: LineCapStyle,
                                  step: Double, into out: inout [PathPoint]) {
        let n = normal(d)
        switch cap {
        case .butt:
            break
        case .square:
            out.append(PathPoint(p.x + h * (n.x + d.x), p.y + h * (n.y + d.y)))
            out.append(PathPoint(p.x + h * (d.x - n.x), p.y + h * (d.y - n.y)))
        case .round:
            let count = max(2, Int((3.141592653589793 / step).rounded(.up)))
            for k in 1..<count {
                let (s, c) = PathMath.sinCos(3.141592653589793 * Double(k) / Double(count))
                out.append(PathPoint(p.x + h * (n.x * c + d.x * s), p.y + h * (n.y * c + d.y * s)))
            }
        }
    }

    /// A zero-length subpath: a round cap draws a disc, a square cap a
    /// square (axis-aligned), a butt cap nothing.
    private static func dot(_ p: PathPoint, h: Double, cap: LineCapStyle, step: Double) -> [Polyline] {
        switch cap {
        case .butt:
            return []
        case .square:
            return [Polyline(points: [PathPoint(p.x - h, p.y - h), PathPoint(p.x + h, p.y - h),
                                      PathPoint(p.x + h, p.y + h), PathPoint(p.x - h, p.y + h)], closed: true)]
        case .round:
            let count = max(4, Int((6.283185307179586 / step).rounded(.up)))
            var points: [PathPoint] = []
            for k in 0..<count {
                let (s, c) = PathMath.sinCos(6.283185307179586 * Double(k) / Double(count))
                points.append(PathPoint(p.x + h * c, p.y + h * s))
            }
            return [Polyline(points: points, closed: true)]
        }
    }
}
