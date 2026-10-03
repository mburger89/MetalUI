import Testing
@testable import MetalUIPath

// Lane 1 (ruling GX-E): the stroker — caps, joins, the miter limit, dashes,
// closed and open subpaths — against probe arms ST1–ST10. **"Ink" here is a
// pixel at least half covered** (coverage ≥ 128): CoreGraphics antialiases by
// coverage samples, so a sliver narrower than about a quarter pixel (a
// miter's last pixel, a round cap's tangent point) leaves no ink in
// SwiftUI's bitmaps while an exact-area rasterizer gives it a few levels.
// A quarter is where both agree within the arms' ±1 (`GX-S` item 2: at half
// coverage the sharp miter of ST6, split down the middle between two pixel
// columns, loses two rows).

func stroke(_ build: (inout PathGeometry) -> Void, _ style: StrokeParameters,
            clip: RasterRect = RasterRect(x: -50, y: -50, width: 200, height: 200)) -> AlphaMask {
    var geometry = PathGeometry()
    build(&geometry)
    var rasterizer = CoverageRasterizer()
    return PathRaster.stroke(geometry, style: style, clip: clip, rasterizer: &rasterizer)
}

/// The box of pixels with coverage ≥ 64, or nil.
func inkBox(_ m: AlphaMask) -> (x0: Int, y0: Int, x1: Int, y1: Int)? {
    var x0 = Int.max, y0 = Int.max, x1 = Int.min, y1 = Int.min
    for y in m.rect.y..<m.rect.maxY {
        for x in m.rect.x..<m.rect.maxX where m.value(atX: x, y: y) >= 64 {
            x0 = min(x0, x); y0 = min(y0, y); x1 = max(x1, x); y1 = max(y1, y)
        }
    }
    return x0 <= x1 ? (x0, y0, x1, y1) : nil
}

func line(_ x0: Double, _ x1: Double, y: Double) -> (inout PathGeometry) -> Void {
    { $0.move(to: PathPoint(x0, y)); $0.addLine(to: PathPoint(x1, y)) }
}

func vShape(tipY: Double, half: Double) -> (inout PathGeometry) -> Void {
    { p in
        p.move(to: PathPoint(50 - half, 90)); p.addLine(to: PathPoint(50, tipY)); p.addLine(to: PathPoint(50 + half, 90))
    }
}

/// 1.20 (ST1–ST3) — a line 20…80 at y 50, width 10: butt ends at the
/// endpoints (x 20…79), square and round extend w/2 (15…84; SwiftUI's round
/// reads 14…85), and the square cap's corner (16, 46) is solid.
@Test func capsEndWhereSwiftUIsDo() throws {
    let butt = try #require(inkBox(stroke(line(20, 80, y: 50), StrokeParameters(width: 10, cap: .butt))))
    let square = stroke(line(20, 80, y: 50), StrokeParameters(width: 10, cap: .square))
    let squareBox = try #require(inkBox(square))
    let round = try #require(inkBox(stroke(line(20, 80, y: 50), StrokeParameters(width: 10, cap: .round))))
    #expect((butt.x0, butt.x1, butt.y0, butt.y1) == (20, 79, 45, 54))
    #expect(abs(squareBox.x0 - 15) <= 1 && abs(squareBox.x1 - 84) <= 1, "square \(squareBox)")
    #expect(square.value(atX: 16, y: 46) == 255)
    #expect(abs(round.x0 - 14) <= 1 && abs(round.x1 - 85) <= 1, "round \(round)")
}

/// 1.21 (ST5) — the V (20, 90)–(50, 20)–(80, 90) at width 10: the miter's
/// tip at y 7.3 (SwiftUI 7), the bevel's edge at 18.0 (18), the round
/// join's top at 15 (15), each ±1.
@Test func joinsReachSwiftUIsTips() throws {
    let v = vShape(tipY: 20, half: 30)
    let miter = try #require(inkBox(stroke(v, StrokeParameters(width: 10, join: .miter))))
    let bevel = try #require(inkBox(stroke(v, StrokeParameters(width: 10, join: .bevel))))
    let round = try #require(inkBox(stroke(v, StrokeParameters(width: 10, join: .round))))
    #expect(abs(miter.y0 - 7) <= 1, "miter \(miter.y0)")
    #expect(abs(bevel.y0 - 18) <= 1, "bevel \(bevel.y0)")
    #expect(abs(round.y0 - 15) <= 1, "round \(round.y0)")
}

/// 1.22 (ST6) — the sharp V (40, 90)–(50, 10)–(60, 90) at width 4 has a
/// miter ratio of 8.06: limit 10 mitres (SwiftUI's ink to y −4), limit 4
/// bevels (y 9), ±1.
@Test func theMiterLimitFallsBackToABevel() throws {
    let v = vShape(tipY: 10, half: 10)
    let ten = try #require(inkBox(stroke(v, StrokeParameters(width: 4, miterLimit: 10))))
    let four = try #require(inkBox(stroke(v, StrokeParameters(width: 4, miterLimit: 4))))
    #expect(abs(ten.y0 - -4) <= 1, "limit 10 \(ten.y0)")
    #expect(abs(four.y0 - 9) <= 1, "limit 4 \(four.y0)")
}

/// The runs of ink along row `y` from `from` to `to`, as "[a…b]".
func runs(_ m: AlphaMask, y: Int, from: Int, to: Int) -> String {
    var out: [String] = [], start: Int?
    for x in from...to {
        let on = m.value(atX: x, y: y) >= 64
        if on, start == nil { start = x }
        if !on, let s = start { out.append("[\(s)…\(x - 1)]"); start = nil }
    }
    if let s = start { out.append("[\(s)…\(to)]") }
    return out.joined(separator: " ")
}

/// 1.23 (ST7) — dashes walk the arc length from the phase: SwiftUI's rows
/// on a width-4 line 0…100. The first two exactly; in the third every dash
/// starts exactly and every 10-unit dash ends exactly, while SwiftUI's
/// 2-unit dashes ([15, 17) read `[15…17]`) ink one sliver pixel past their
/// end that an exact-area rasterizer leaves empty (`[15…16]`) — `GX-S`
/// item 3: within ±1 at those four ends.
@Test func dashesWalkTheArcLengthFromThePhase() throws {
    let l = line(0, 100, y: 50)
    #expect(runs(stroke(l, StrokeParameters(width: 4, dash: [10, 10])), y: 50, from: 0, to: 99)
            == "[0…9] [20…29] [40…49] [60…69] [80…89]")
    #expect(runs(stroke(l, StrokeParameters(width: 4, dash: [10, 10], dashPhase: 5)), y: 50, from: 0, to: 99)
            == "[0…4] [15…24] [35…44] [55…64] [75…84] [95…99]")
    let swiftUI = [(0, 9), (15, 17), (22, 31), (37, 39), (44, 53), (59, 61), (66, 75), (81, 83), (88, 97)]
    let drawn = runs(stroke(l, StrokeParameters(width: 4, dash: [10, 5, 2, 5])), y: 50, from: 0, to: 99)
        .split(separator: " ").map { run -> (Int, Int) in
            let bounds = run.dropFirst().dropLast().split(separator: "…").map { Int($0)! }
            return (bounds[0], bounds[1])
        }
    try #require(drawn.count == swiftUI.count, "runs \(drawn)")
    for (d, s) in zip(drawn, swiftUI) {
        #expect(d.0 == s.0 && (s.1 - s.0 == 9 ? d.1 == s.1 : abs(d.1 - s.1) <= 1), "\(d) vs \(s)")
    }
}

/// 1.24 (ST8) — the square (20, 20, 60, 60) at width 10: closed, its start
/// corner is joined (mitred: (16, 16) solid); drawn open with four lines
/// back to the start, both ends are butt-capped and (16, 16) stays clear.
@Test func aClosedSubpathJoinsAtItsStartAndAnOpenOneCaps() {
    let closed = stroke({ $0.addRect(x: 20, y: 20, width: 60, height: 60) }, StrokeParameters(width: 10))
    let open = stroke({ p in
        p.move(to: PathPoint(20, 20)); p.addLine(to: PathPoint(80, 20)); p.addLine(to: PathPoint(80, 80))
        p.addLine(to: PathPoint(20, 80)); p.addLine(to: PathPoint(20, 20))
    }, StrokeParameters(width: 10))
    #expect(closed.value(atX: 16, y: 16) == 255)
    #expect(open.value(atX: 16, y: 16) == 0)
}

/// 1.25 (ST10) — a width of 0 or −3 strokes nothing.
@Test func aNonPositiveWidthStrokesNothing() {
    for width in [0.0, -3.0] {
        let m = stroke(line(20, 80, y: 50), StrokeParameters(width: width))
        #expect(m.alpha.allSatisfy { $0 == 0 }, "width \(width)")
    }
}
