import Testing
@testable import MetalUIPath

// Round 3, item R3-8 — path operations in `MetalUIPath` (rulings `PG-A`…`PG-D`;
// SwiftUI's side is `docs/probes/swiftui-path-ops.swift`, arms C, TR, SP, AR,
// X). This target is portable, so these run on Linux and Windows CI: every
// number below is the same bytes there (`+ − × ÷ sqrt` and `PathMath` only).
//
// ORACLE: an independent arc-length measure — the same path flattened to a
// 1e-7 tolerance and summed chord by chord — so a length or a trimmed end
// point is checked against geometry, not against the implementation's own
// table.

private func p(_ x: Double, _ y: Double) -> PathPoint { PathPoint(x, y) }

private func line(_ a: PathPoint, _ b: PathPoint) -> PathGeometry {
    var g = PathGeometry(); g.move(to: a); g.addLine(to: b); return g
}

private func square(_ side: Double) -> PathGeometry {
    var g = PathGeometry(); g.addRect(x: 0, y: 0, width: side, height: side); return g
}

private func quarterCircle(radius: Double = 100) -> PathGeometry {
    var g = PathGeometry()
    g.addArc(center: p(0, 0), radius: radius, startAngle: 0, endAngle: 1.5707963267948966, clockwise: false)
    return g
}

/// The oracle's chord polyline of every subpath, closing edges included.
private func fine(_ g: PathGeometry) -> [[PathPoint]] {
    Flattener.flatten(g, tolerance: 1e-7).map { line in
        line.closed ? line.points + [line.points[0]] : line.points
    }
}

private func oracleLength(_ g: PathGeometry) -> Double {
    var sum = 0.0
    for points in fine(g) { for i in 1..<points.count { sum += hypot(points[i - 1], points[i]) } }
    return sum
}

/// The point `distance` along the oracle polyline of the whole path.
private func oraclePoint(_ g: PathGeometry, at distance: Double) -> PathPoint {
    var left = distance
    var last = p(0, 0)
    for points in fine(g) {
        for i in 1..<points.count {
            let d = hypot(points[i - 1], points[i])
            last = points[i]
            if left <= d {
                let t = d > 0 ? left / d : 0
                return p(points[i - 1].x + (points[i].x - points[i - 1].x) * t,
                         points[i - 1].y + (points[i].y - points[i - 1].y) * t)
            }
            left -= d
        }
    }
    return last
}

private func hypot(_ a: PathPoint, _ b: PathPoint) -> Double {
    let dx = b.x - a.x, dy = b.y - a.y
    return (dx * dx + dy * dy).squareRoot()
}

/// The points of `g` in element order, with `nil` for a close.
private func trace(_ g: PathGeometry) -> [String] {
    func f(_ v: Double) -> String {
        let r = (v * 1000).rounded() / 1000
        return r == r.rounded() ? String(Int(r)) : String(r)
    }
    return g.elements.map { e in
        switch e {
        case .move(let a): "M(\(f(a.x)),\(f(a.y)))"
        case .line(let a): "L(\(f(a.x)),\(f(a.y)))"
        case .quad(_, let a): "Q(\(f(a.x)),\(f(a.y)))"
        case .cubic(_, _, let a): "C(\(f(a.x)),\(f(a.y)))"
        case .close: "Z"
        }
    }
}

private func close(_ a: PathPoint, _ b: PathPoint, _ tolerance: Double) -> Bool {
    abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance
}

/// The nonzero winding number of `g` (every subpath closed) at (x, y).
private func winding(_ lines: [Polyline], _ x: Double, _ y: Double) -> Int {
    var w = 0
    for line in lines where line.points.count > 2 {
        let pts = line.points
        for i in 0..<pts.count {
            let a = pts[i], b = pts[(i + 1) % pts.count]
            let cross = (b.x - a.x) * (y - a.y) - (x - a.x) * (b.y - a.y)
            if a.y <= y {
                if b.y > y && cross > 0 { w += 1 }
            } else if b.y <= y && cross < 0 { w -= 1 }
        }
    }
    return w
}

/// The area `g` fills under the nonzero rule, by sampling cell centres of a
/// `step` grid over its bounds. The stroker's inner side runs through the
/// vertex (its pivot), so a closed outline's *signed* area is not the band's
/// — only a coverage measure is.
private func filledArea(_ g: PathGeometry, step: Double) -> Double {
    let b = bounds(g)
    let lines = Flattener.flatten(g, tolerance: 1e-3)
    var count = 0
    var y = b.minY + step / 2
    while y < b.maxY {
        var x = b.minX + step / 2
        while x < b.maxX {
            if winding(lines, x, y) != 0 { count += 1 }
            x += step
        }
        y += step
    }
    return Double(count) * step * step
}

private func bounds(_ g: PathGeometry) -> (minX: Double, minY: Double, maxX: Double, maxY: Double) {
    var b = (minX: Double.infinity, minY: Double.infinity, maxX: -Double.infinity, maxY: -Double.infinity)
    for line in Flattener.flatten(g, tolerance: 1e-4) {
        for q in line.points {
            b = (min(b.minX, q.x), min(b.minY, q.y), max(b.maxX, q.x), max(b.maxY, q.y))
        }
    }
    return b
}

// MARK: - Arc length (PG-A)

/// **PG-A 1** (probe C1, C2). A 3-4-5 line is 5 long and a square of side 10
/// is 40 — the closing edge counted (TR6b). Mutation **PGM1**: the closing
/// edge left out of a closed subpath's length.
@Test func theArcLengthOfStraightPathsIsExact() {
    #expect(line(p(0, 0), p(3, 4)).arcLength == 5)
    #expect(square(10).arcLength == 40)
    var open = PathGeometry()
    open.move(to: p(0, 0)); open.addLine(to: p(10, 0)); open.addLine(to: p(10, 10))
    #expect(open.arcLength == 20, "open: no closing edge")
    open.closeSubpath()
    #expect(abs(open.arcLength - (20 + 200.0.squareRoot())) < 1e-12, "closed: \(open.arcLength)")
}

/// **PG-A 2** (TR3). A cubic's length is its true arc length, against the
/// oracle's chord sum: the kappa quarter circle of radius 100, a skewed
/// cubic and a quadratic, each within a relative 1e-7. Mutation **PGM2**: Simpson's
/// midpoint term dropped (a trapezoid on the end speeds: the quarter circle
/// reads 0.4% long).
@Test func aCurvesLengthIsItsTrueArcLength() {
    var skew = PathGeometry()
    skew.move(to: p(0, 0)); skew.addCurve(to: p(100, 0), control1: p(0, 120), control2: p(100, -80))
    var quad = PathGeometry()
    quad.move(to: p(0, 100)); quad.addQuadCurve(to: p(100, 100), control: p(50, 0))
    for (name, g) in [("quarter", quarterCircle()), ("skew", skew), ("quad", quad)] {
        #expect(abs(g.arcLength - oracleLength(g)) < 1e-5 * g.arcLength / 100, "\(name): \(g.arcLength) vs \(oracleLength(g))")
    }
}

// MARK: - trimmed(from:to:) (PG-A)

/// **PG-A 3** (TR2, SEPARATING ARM). Fractions are arc length, not element
/// count: on a 10-long line then a 90-long one, 0…0.5 ends 40 into the second
/// (10, 40) — per-element would end at its midpoint. Mutation **PGM3**:
/// fractions applied per segment (`to × segmentLength`, restarted each).
@Test func fractionsAreArcLengthNotPerElement() {
    var g = PathGeometry()
    g.move(to: p(0, 0)); g.addLine(to: p(10, 0)); g.addLine(to: p(10, 90))
    let t = g.trimmed(from: 0, to: 0.5)
    #expect(trace(t) == ["M(0,0)", "L(10,0)", "L(10,40)"], "\(trace(t))")
    let u = g.trimmed(from: 0.05, to: 0.2)
    #expect(trace(u) == ["M(5,0)", "L(10,0)", "L(10,10)"], "\(trace(u))")
}

/// **PG-A 4** (C1, TR3, TR3b, SEPARATING ARM). A trimmed curve's ends lie at the
/// right ARC LENGTH, not the right parameter: half-way along the kappa
/// quarter circle is the oracle's half-length point (70.71, 70.71) within
/// 1e-4, and 0.25…0.75 starts and ends at the oracle's quarter and
/// three-quarter points. The trimmed piece is still one cubic.
/// Mutation **PGM4**: distance mapped to parameter by `d / length` (a cubic's
/// parameter is not arc length: 0.5 lands 0.7 off).
@Test func aTrimmedCurveEndsAtTheRightArcLengthAndStaysACurve() throws {
    let g = quarterCircle()
    let total = oracleLength(g)
    let half = g.trimmed(from: 0, to: 0.5)
    let end = try #require(half.currentPoint)
    let expect = oraclePoint(g, at: total / 2)
    #expect(close(end, expect, 1e-4), "\(end) vs \(expect)")
    #expect(close(end, p(70.7107, 70.7107), 5e-2), "near the true circle's half-way: \(end)")
    let mid = g.trimmed(from: 0.25, to: 0.75)
    #expect(trace(mid).map { $0.first! } == ["M", "C"], "one move, one cubic: \(trace(mid))")
    guard case .move(let start) = mid.elements[0] else { Issue.record("no move"); return }
    #expect(close(start, oraclePoint(g, at: total * 0.25), 1e-4), "start \(start)")
    #expect(close(mid.currentPoint!, oraclePoint(g, at: total * 0.75), 1e-4), "end \(mid.currentPoint!)")
    var q = PathGeometry()
    q.move(to: p(0, 100)); q.addQuadCurve(to: p(100, 100), control: p(50, 0))
    let qt = q.trimmed(from: 0.2, to: 0.6)
    #expect(trace(qt).map { $0.first! } == ["M", "Q"], "a trimmed quad stays a quad: \(trace(qt))")
    #expect(close(qt.currentPoint!, oraclePoint(q, at: oracleLength(q) * 0.6), 1e-4), "\(qt.currentPoint!)")
}

/// **PG-A 5** (TR4). One fraction runs across every subpath end to end: two
/// subpaths 10 and 90 long, 0…0.5 is the first whole and 40 of the second;
/// 0.05…0.15 is the first's last 5 and the second's first 5.
/// Mutation **PGM5**: the fractions applied to each subpath alone.
@Test func aFractionRunsAcrossSubpaths() {
    var g = PathGeometry()
    g.move(to: p(0, 0)); g.addLine(to: p(10, 0))
    g.move(to: p(0, 5)); g.addLine(to: p(90, 5))
    #expect(trace(g.trimmed(from: 0, to: 0.5)) == ["M(0,0)", "L(10,0)", "M(0,5)", "L(40,5)"])
    #expect(trace(g.trimmed(from: 0.05, to: 0.15)) == ["M(5,0)", "L(10,0)", "M(0,5)", "L(5,5)"])
}

/// **PG-A 6** (TR5, TR5b, TR6b, TR6c). A closed square: 0.9…1 is the last 4 of
/// the closing edge, (0,4)→(0,0); 0…1 keeps the whole subpath with its close;
/// a closed triangle's closing edge is measured (0.9 lands (2.414, 2.414)).
/// Mutation **PGM6**: a subpath inside the range copied without its `close`.
@Test func aClosedSubpathCountsItsClosingEdgeAndKeepsItsCloseWhenWhole() {
    let sq = square(10)
    #expect(trace(sq.trimmed(from: 0.9, to: 1)) == ["M(0,4)", "L(0,0)"])
    #expect(trace(sq.trimmed(from: 0, to: 1)) == ["M(0,0)", "L(10,0)", "L(10,10)", "L(0,10)", "Z"])
    #expect(trace(sq.trimmed(from: 0.25, to: 0.5)) == ["M(10,0)", "L(10,10)"])
    var tri = PathGeometry()
    tri.move(to: p(0, 0)); tri.addLine(to: p(10, 0)); tri.addLine(to: p(10, 10)); tri.closeSubpath()
    #expect(trace(tri.trimmed(from: 0.9, to: 1)) == ["M(2.414,2.414)", "L(0,0)"])
    #expect(trace(tri.trimmed(from: 0, to: 1)) == ["M(0,0)", "L(10,0)", "L(10,10)", "Z"])
}

/// **PG-A 7** (TR5c–TR5f, TR7). Fractions clamp to 0…1; `from >= to`, a NaN
/// and an empty path give an empty path. Mutation **PGM7**: a reversed range
/// swapped instead of emptied.
@Test func outOfRangeFractionsClampAndAnEmptyRangeIsEmpty() {
    let sq = square(10)
    #expect(sq.trimmed(from: 0.75, to: 0.25).isEmpty)
    #expect(sq.trimmed(from: 0.5, to: 0.5).isEmpty)
    #expect(sq.trimmed(from: .nan, to: 1).isEmpty)
    #expect(sq.trimmed(from: 0, to: .nan).isEmpty)
    #expect(PathGeometry().trimmed(from: 0, to: 0.5).isEmpty)
    #expect(trace(sq.trimmed(from: -0.5, to: 0.25)) == ["M(0,0)", "L(10,0)"])
    #expect(trace(sq.trimmed(from: 0, to: 1.5)) == trace(sq.trimmed(from: 0, to: 1)))
}

/// **PG-A 8** (X10). Trimming a trim composes: 0.2…0.7 of a 100-long line is
/// 20…70, and 0.5…1 of that is 45…70.
@Test func aTrimOfATrimComposes() {
    let t = line(p(0, 0), p(100, 0)).trimmed(from: 0.2, to: 0.7).trimmed(from: 0.5, to: 1)
    #expect(trace(t) == ["M(45,0)", "L(70,0)"])
}

/// **PG-A 9** (`GX-B`). Bit-identical everywhere: the trimmed quarter circle's
/// end point and its length are pinned to the bit, as `sinCos` is, so a
/// libm call or a fused multiply-add anywhere in the measure reddens this on
/// the platform that differs. Mutation **PGM9**: `.squareRoot()` of the chord
/// length replaced by an `x * x.squareRoot().reciprocal`-style spelling.
@Test func trimmedPathIsBitIdenticalEverywhere() throws {
    let g = quarterCircle()
    let end = try #require(g.trimmed(from: 0, to: 0.37).currentPoint)
    #expect(g.arcLength.bitPattern == PINNED_LENGTH_BITS, "length \(g.arcLength.bitPattern)")
    #expect(end.x.bitPattern == PINNED_X_BITS, "x \(end.x.bitPattern)")
    #expect(end.y.bitPattern == PINNED_Y_BITS, "y \(end.y.bitPattern)")
}

// MARK: - stroked (PG-B)

/// **PG-B 1** (SP butt, round, square). A 10-long line stroked 4 wide: a butt
/// outline is a 10×4 rectangle (area 40, bounds x0…10 y−2…2), a square cap
/// adds 2 each end (14×4, area 56), a round cap two half discs (40 + 4π
/// within the 0.01 flattening). Mutation **PGM10**: the cap style ignored.
@Test func aStrokedLineIsItsOutlinePolygon() {
    let style = { (cap: LineCapStyle) in StrokeParameters(width: 4, cap: cap) }
    let butt = line(p(0, 0), p(10, 0)).stroked(style(.butt), tolerance: 0.01)
    #expect(abs(filledArea(butt, step: 0.125) - 40) < 1e-9, "butt area \(filledArea(butt, step: 0.125))")
    let b = bounds(butt)
    #expect(b.minX == 0 && b.maxX == 10 && b.minY == -2 && b.maxY == 2, "\(b)")
    let square = line(p(0, 0), p(10, 0)).stroked(style(.square), tolerance: 0.01)
    #expect(abs(filledArea(square, step: 0.125) - 56) < 1e-9, "square area \(filledArea(square, step: 0.125))")
    let round = line(p(0, 0), p(10, 0)).stroked(style(.round), tolerance: 0.01)
    #expect(abs(filledArea(round, step: 0.125) - (40 + 4 * 3.141592653589793)) < 0.25,
            "round area \(filledArea(round, step: 0.125))")
    let rb = bounds(round)
    #expect(abs(rb.minX + 2) < 1e-3 && abs(rb.maxX - 12) < 1e-3, "\(rb)")
}

/// **PG-B 2** (SP ring, X8). A closed outline strokes to a band: a circle of
/// radius 50 stroked 10 wide has area π(55² − 45²) = 1000π within 0.2%, as
/// two loops of opposite orientation, so a point at the centre is outside
/// (winding 0) and one on the band inside. A rectangle 20×10 stroked 4 is
/// 24×14 outside less 16×6 inside = 240. Mutation **PGM11**: a closed
/// subpath stroked as an open one (one loop: the area is the whole disc).
@Test func aClosedPathStrokesToABand() {
    var ring = PathGeometry()
    ring.addEllipse(x: 0, y: 0, width: 100, height: 100)
    let band = ring.stroked(StrokeParameters(width: 10), tolerance: 0.01)
    let area = filledArea(band, step: 0.5)
    #expect(abs(area - 1000 * 3.141592653589793) / (1000 * 3.141592653589793) < 5e-3, "ring area \(area)")
    let lines = Flattener.flatten(band, tolerance: 1e-3)
    #expect(winding(lines, 50, 50) == 0 && winding(lines, 50, 2) != 0 && winding(lines, 50, -2) != 0
            && winding(lines, 50, 8) == 0 && winding(lines, 50, -6) == 0, "the probe's SP ring samples")
    #expect(band.elements.filter { if case .move = $0 { true } else { false } }.count == 2, "two loops")
    var rect = PathGeometry()
    rect.addRect(x: 0, y: 0, width: 20, height: 10)
    let frame = rect.stroked(StrokeParameters(width: 4), tolerance: 0.01)
    #expect(abs(filledArea(frame, step: 0.125) - 240) < 1e-6, "frame area \(filledArea(frame, step: 0.125))")
}

/// **PG-B 3** (SP dash). A [4, 4] dash on a 20-long line 2 wide is three dashes
/// 0…4, 8…12, 16…20: area 24. A width of 0 or less is an empty path (SP w0,
/// divergence 946). Mutation **PGM12**: the dash pattern ignored.
@Test func aDashedStrokeIsOnePolygonPerDashAndAZeroWidthIsEmpty() {
    let dashed = line(p(0, 0), p(20, 0)).stroked(StrokeParameters(width: 2, dash: [4, 4]), tolerance: 0.01)
    #expect(abs(filledArea(dashed, step: 0.125) - 24) < 1e-9, "dashed area \(filledArea(dashed, step: 0.125))")
    #expect(dashed.elements.filter { if case .close = $0 { true } else { false } }.count == 3, "three dashes")
    #expect(line(p(0, 0), p(20, 0)).stroked(StrokeParameters(width: 0), tolerance: 0.01).isEmpty)
    #expect(line(p(0, 0), p(20, 0)).stroked(StrokeParameters(width: -3), tolerance: 0.01).isEmpty)
}

/// **PG-B 4** (SP V, probe V). Joins: a V stroked 4 wide has its miter tip at
/// (10, 12.828) as CoreGraphics' `strokedPath` does (14.243 tall with the
/// butt ends' 1.414 overhang), the bevel's corners at y 11.414 (12.828 tall)
/// and the round join's arc at y 12 (13.414, within the flattening); the
/// miter is the tallest. Mutation
/// **PGM13**: the join style ignored.
@Test func joinsReachTheProbesExtents() {
    var v = PathGeometry()
    v.move(to: p(0, 0)); v.addLine(to: p(10, 10)); v.addLine(to: p(20, 0))
    func height(_ join: LineJoinStyle) -> Double {
        let b = bounds(v.stroked(StrokeParameters(width: 4, join: join), tolerance: 0.01))
        return b.maxY - b.minY
    }
    #expect(abs(height(.miter) - 14.2426) < 1e-3, "miter \(height(.miter))")
    #expect(abs(height(.bevel) - 12.828) < 1e-3, "bevel \(height(.bevel))")
    #expect(abs(height(.round) - 13.414) < 2e-2, "round \(height(.round))")
}

// MARK: - addRelativeArc (PG-D)

/// **PG-D 1** (AR1–AR3). `addRelativeArc(0, +90°)` about (50, 50) r 50 runs from
/// (100, 50) to (50, 100), the positive angle direction, and equals
/// `addArc(0…90°, clockwise: false)` to the bit; −90° ends at (50, 0).
/// Mutation **PGM14**: a negative delta swept the positive way.
@Test func aRelativeArcSweepsBySignedDelta() throws {
    let quarter = 1.5707963267948966
    var rel = PathGeometry()
    rel.addRelativeArc(center: p(50, 50), radius: 50, startAngle: 0, delta: quarter)
    var abs0 = PathGeometry()
    abs0.addArc(center: p(50, 50), radius: 50, startAngle: 0, endAngle: quarter, clockwise: false)
    #expect(rel == abs0, "the same elements as addArc")
    let end = try #require(rel.currentPoint)
    #expect(close(end, p(50, 100), 1e-9), "\(end)")
    var neg = PathGeometry()
    neg.addRelativeArc(center: p(50, 50), radius: 50, startAngle: 0, delta: -quarter)
    #expect(close(neg.currentPoint!, p(50, 0), 1e-9), "\(neg.currentPoint!)")
    #expect(trace(neg).first == "M(100,50)")
}

/// **PG-D 2** (AR4, X5, X6, X7, X4). A sweep past a turn keeps going: 450° ends at
/// 90° ((50, 100)), 1000° at 280° (58.68, 0.76), −450° at (50, 0); the
/// full path is 450° of cubics, five of them. A zero delta is only the
/// start point; after an existing point the arc starts with a line.
/// Mutation **PGM15**: the sweep capped at one turn (as `addArc` caps it).
@Test func aRelativeArcPastATurnKeepsGoing() throws {
    let rad = { (degrees: Double) in degrees * 3.141592653589793 / 180 }
    var big = PathGeometry()
    big.addRelativeArc(center: p(50, 50), radius: 50, startAngle: 0, delta: rad(450))
    #expect(close(big.currentPoint!, p(50, 100), 1e-9), "\(big.currentPoint!)")
    #expect(big.elements.filter { if case .cubic = $0 { true } else { false } }.count == 5)
    var thousand = PathGeometry()
    thousand.addRelativeArc(center: p(50, 50), radius: 50, startAngle: 0, delta: rad(1000))
    #expect(close(thousand.currentPoint!, p(58.682, 0.760), 1e-3), "\(thousand.currentPoint!)")
    var neg = PathGeometry()
    neg.addRelativeArc(center: p(50, 50), radius: 50, startAngle: 0, delta: rad(-450))
    #expect(close(neg.currentPoint!, p(50, 0), 1e-9), "\(neg.currentPoint!)")
    var zero = PathGeometry()
    zero.addRelativeArc(center: p(50, 50), radius: 50, startAngle: rad(30), delta: 0)
    #expect(trace(zero) == ["M(93.301,75)"], "\(trace(zero))")
    var after = PathGeometry()
    after.move(to: p(0, 0))
    after.addRelativeArc(center: p(50, 50), radius: 50, startAngle: 0, delta: rad(90))
    #expect(trace(after) == ["M(0,0)", "L(100,50)", "C(50,100)"], "\(trace(after))")
}

/// **PG-D 3** (AR5, AR6, AR9). `append(_:transformedBy:joining:)` maps every
/// point and, joining, turns the first move into a line from the current
/// point: a +90° arc translated (10, 20) starts at (110, 70); scaled (2, 1) it
/// ends at (100, 100).
@Test func aTransformedAppendMapsPointsAndJoins() {
    var arc = PathGeometry()
    arc.addRelativeArc(center: p(50, 50), radius: 50, startAngle: 0, delta: 1.5707963267948966)
    var moved = PathGeometry()
    moved.append(arc, transformedBy: .translation(10, 20))
    #expect(trace(moved).first == "M(110,70)", "\(trace(moved))")
    #expect(close(moved.currentPoint!, p(60, 120), 1e-9))
    var scaled = PathGeometry()
    scaled.move(to: p(0, 0))
    scaled.append(arc, transformedBy: .scale(2, 1), joining: true)
    #expect(Array(trace(scaled).prefix(2)) == ["M(0,0)", "L(200,50)"], "\(trace(scaled))")
    #expect(close(scaled.currentPoint!, p(100, 100), 1e-9))
}

private let PINNED_LENGTH_BITS: UInt64 = 4639731540171258189
private let PINNED_X_BITS: UInt64 = 4635582627234803792
private let PINNED_Y_BITS: UInt64 = 4632924252101402590
