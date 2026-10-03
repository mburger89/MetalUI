import Testing
@testable import MetalUIPath

// Lane 1 (ruling GX-B, GX-R item 2): `PathMath.sinCos` and the whole
// pipeline are bit-identical on every platform. Both literals below were
// recorded on macOS arm64 and are compared exactly on Linux and Windows CI —
// a tolerance could not see the platform drift this target exists to
// prevent.

/// 24 angles: the quadrant boundaries, both signs, small, large and 1e6.
let sinCosAngles: [Double] = [
    0, 1e-9, 0.5, 1, 2, 3, 5, 10, 100, 1e6,
    Double.pi / 6, Double.pi / 4, Double.pi / 2, Double.pi, 3 * Double.pi / 2, 2 * Double.pi,
    -Double.pi / 2, -Double.pi, -0.3, -1, -7.5, -100, 0.7853981633974483, 1.5707963267948966 + 1e-7,
]

/// (sin, cos) bit patterns recorded on macOS arm64 from this implementation.
let sinCosBitPatterns: [(UInt64, UInt64)] = [
    (0x0, 0x3ff0000000000000),
    (0x3e112e0be826d695, 0x3ff0000000000000),
    (0x3fdeaee8744b05f0, 0x3fec1528065b7d50),
    (0x3feaed548f090cee, 0x3fe14a280fb5068c),
    (0x3fed18f6ead1b445, 0xbfdaa22657537205),
    (0x3fc210386db6d55b, 0xbfefae04be85e5d2),
    (0xbfeeaf81f5e09933, 0x3fd22785706b4ada),
    (0xbfe1689ef5f34f53, 0xbfead9ac890c6b1f),
    (0xbfe03425b78c4db8, 0x3feb981dbf665fdf),
    (0xbfd6664b2568d867, 0x3fedf9df9906d32c),
    (0x3fdfffffffffffff, 0x3febb67ae8584cab),
    (0x3fe6a09e667f3bcc, 0x3fe6a09e667f3bcd),
    (0x3ff0000000000000, 0x3c91a62633100000),
    (0x3ca1a62633100000, 0xbff0000000000000),
    (0xbff0000000000000, 0xbcaa79394ca00000),
    (0xbcb1a62633100000, 0x3ff0000000000000),
    (0xbff0000000000000, 0x3c91a62633100000),
    (0xbca1a62633100000, 0xbff0000000000000),
    (0xbfd2e9cd95baba33, 0x3fee921dd42f09ba),
    (0xbfeaed548f090cee, 0x3fe14a280fb5068c),
    (0xbfee041886fcae30, 0x3fd62f45e66f5c2f),
    (0x3fe03425b78c4db8, 0x3feb981dbf665fdf),
    (0x3fe6a09e667f3bcc, 0x3fe6a09e667f3bcd),
    (0x3fefffffffffffd3, 0xbe7ad7f29ab9675a),
]

/// 1.27 — `sinCos` returns the recorded bit patterns exactly, and is exactly
/// odd in `sin` and even in `cos` (Cody–Waite reduction by π/2 and fixed
/// polynomials, basic operations only).
@Test func sinCosMatchesTheReferenceTable() throws {
    try #require(sinCosAngles.count == 24)
    try #require(sinCosBitPatterns.count == 24, "table not recorded")
    for (i, x) in sinCosAngles.enumerated() {
        let (s, c) = PathMath.sinCos(x)
        #expect(s.bitPattern == sinCosBitPatterns[i].0 && c.bitPattern == sinCosBitPatterns[i].1,
                "angle \(x): (\(s), \(c)) = (0x\(String(s.bitPattern, radix: 16)), 0x\(String(c.bitPattern, radix: 16)))")
        let (ns, nc) = PathMath.sinCos(-x)
        #expect(ns.bitPattern == (-s).bitPattern && nc.bitPattern == c.bitPattern, "symmetry at \(x)")
        #expect(abs(s * s + c * c - 1) < 1e-15, "unit at \(x)")
    }
    // A quarter turn is a quadrant: sin(π/2) is 1, cos(π) is −1.
    #expect(PathMath.sinCos(Double.pi / 2).sin == 1)
    #expect(PathMath.sinCos(Double.pi).cos == -1)
    #expect(abs(PathMath.sinCos(1).sin - 0.8414709848078965) < 2e-16)
}

/// FNV-1a over a buffer.
func fnv1a(_ bytes: [UInt8]) -> UInt64 {
    var h: UInt64 = 0xcbf2_9ce4_8422_2325
    for b in bytes { h ^= UInt64(b); h = h &* 0x0000_0100_0000_01b3 }
    return h
}

/// Every byte the corpus produces, rects included.
func corpusBytes() -> [UInt8] {
    var out: [UInt8] = []
    func add(_ m: AlphaMask) {
        for v in [m.rect.x, m.rect.y, m.rect.width, m.rect.height] {
            withUnsafeBytes(of: Int64(v).littleEndian) { out += $0 }
        }
        out += m.alpha
    }
    let clip = RasterRect(x: -50, y: -50, width: 250, height: 250)
    // Curves.
    add(fill({ p in p.move(to: PathPoint(0, 100)); p.addQuadCurve(to: PathPoint(100, 100), control: PathPoint(50, 0)); p.closeSubpath() }, clip: clip))
    add(fill({ p in p.move(to: PathPoint(0, 100)); p.addCurve(to: PathPoint(100, 100), control1: PathPoint(0, 0), control2: PathPoint(100, 0)); p.closeSubpath() }, clip: clip))
    add(fill({ $0.addEllipse(x: 3.3, y: 7.7, width: 91.1, height: 57.9) }, clip: clip))
    add(fill({ $0.addRoundedRect(x: 10.5, y: 10.25, width: 80, height: 50, rx: 17, ry: 9) }, clip: clip))
    // Arcs at seven angles, both directions.
    for (i, end) in [0.3, 1.0, 1.7, 2.5, 3.3, 4.6, 6.0].enumerated() {
        add(fill({ p in
            p.move(to: PathPoint(60, 60))
            p.addArc(center: PathPoint(60, 60), radius: 45.5, startAngle: 0.1 * Double(i), endAngle: end, clockwise: i % 2 == 0)
            p.closeSubpath()
        }, clip: clip))
    }
    add(fill({ p in
        p.move(to: PathPoint(10, 90)); p.addArc(tangent1End: PathPoint(50, 10), tangent2End: PathPoint(90, 90), radius: 20)
        p.addLine(to: PathPoint(90, 90)); p.closeSubpath()
    }, clip: clip))
    // The strokes of 1.20–1.25.
    for cap in [LineCapStyle.butt, .square, .round] { add(stroke(line(20.3, 80.6, y: 50.2), StrokeParameters(width: 10, cap: cap))) }
    for join in [LineJoinStyle.miter, .bevel, .round] { add(stroke(vShape(tipY: 20, half: 30), StrokeParameters(width: 10, join: join))) }
    add(stroke(vShape(tipY: 10, half: 10), StrokeParameters(width: 4, miterLimit: 10)))
    add(stroke(vShape(tipY: 10, half: 10), StrokeParameters(width: 4, miterLimit: 4)))
    add(stroke(line(0, 100, y: 50), StrokeParameters(width: 4, dash: [10, 5, 2, 5], dashPhase: 3)))
    add(stroke({ $0.addEllipse(x: 10, y: 10, width: 80, height: 50) }, StrokeParameters(width: 6, cap: .round, join: .round, dash: [12, 6])))
    // An even-odd star, rotated.
    let star: (inout PathGeometry) -> Void = { p in
        let pts = [(50.0, 5.0), (79.4, 95.5), (2.4, 39.5), (97.6, 39.5), (20.6, 95.5)]
        p.move(to: PathPoint(pts[0].0, pts[0].1))
        for q in pts.dropFirst() { p.addLine(to: PathPoint(q.0, q.1)) }
        p.closeSubpath()
    }
    add(fill(star, rule: .evenOdd, clip: clip))
    add(fill(star, rule: .nonZero, clip: clip, transform: PathAffine.rotation(0.4).concatenating(.translation(-50, -50))))
    // A blur.
    add(BoxBlur.blur(fill({ $0.addRect(x: 0, y: 0, width: 40, height: 40) }, clip: clip), sigma: 7.3))
    return out
}

/// Recorded on macOS arm64 from this implementation.
let corpusHash: UInt64 = 0xbfbd_ad23_fe78_65b4

/// 1.26 — the corpus (curves, arcs at seven angles, the strokes above, an
/// even-odd star, a blur) hashes to the literal recorded on macOS; Linux and
/// Windows CI run this same test. A flattening tolerance of 0.2 for 0.1 moves
/// curve segment counts and so coverage bytes.
@Test func theRasterizerIsBitIdenticalEverywhere() {
    let bytes = corpusBytes()
    #expect(bytes.count > 100_000)
    #expect(fnv1a(bytes) == corpusHash, "corpus hash 0x\(String(fnv1a(bytes), radix: 16))")
}
