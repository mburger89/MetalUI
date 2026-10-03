import Testing
@testable import MetalUIPath

// Lane 1 of paths, shadows and transforms (ruling GX-B): the exact-area
// coverage rasterizer. Every expected value is derived before the run from
// the geometry named above the test, or read off probe
// `swiftui-paths-shadows-transforms.swift` (arm named).

func fill(_ build: (inout PathGeometry) -> Void, rule: FillRule = .nonZero,
          clip: RasterRect = RasterRect(x: 0, y: 0, width: 200, height: 200),
          transform: PathAffine = .identity, tolerance: Double = Flattener.defaultTolerance) -> AlphaMask {
    var geometry = PathGeometry()
    build(&geometry)
    var rasterizer = CoverageRasterizer()
    return PathRaster.fill(geometry, rule: rule, transform: transform, clip: clip, tolerance: tolerance,
                           rasterizer: &rasterizer)
}

/// The coverage-weighted area, in pixels: Σ alpha / 255 (the probe's `darkArea`).
func area(_ m: AlphaMask) -> Double { m.alpha.reduce(0.0) { $0 + Double($1) } / 255 }

/// 1.13 — a 10×10 square at integer coordinates covers exactly its 100
/// pixels, each fully: the cover term carries an edge's winding across the
/// row (area alone would leave the interior empty).
@Test func aFilledSquareCoversExactlyItsPixels() {
    let m = fill { $0.addRect(x: 5, y: 5, width: 10, height: 10) }
    var full = 0, other = 0
    for y in 0..<20 {
        for x in 0..<20 {
            let v = m.value(atX: x, y: y)
            let inside = (5..<15).contains(x) && (5..<15).contains(y)
            if inside && v == 255 { full += 1 } else if v != 0 { other += 1 }
        }
    }
    #expect(full == 100 && other == 0, "full \(full), other \(other)")
}

/// 1.14 — an edge at x = 0.5 covers its column half: 127 or 128.
@Test func aHalfPixelEdgeCoversHalf() {
    let m = fill { $0.addRect(x: 0.5, y: 0, width: 10, height: 10) }
    let edge = m.value(atX: 0, y: 5)
    #expect(edge == 127 || edge == 128, "edge \(edge)")
    #expect(m.value(atX: 1, y: 5) == 255)
    let right = m.value(atX: 10, y: 5)
    #expect(right == 127 || right == 128, "right edge \(right)")
}

/// 1.15 (PA2) — two same-direction squares (0…100, 25…75): nonzero fills
/// the centre, even-odd empties it and keeps the ring.
@Test func nonZeroFillsASameDirectionRingAndEvenOddEmptiesIt() {
    let rings: (inout PathGeometry) -> Void = {
        $0.addRect(x: 0, y: 0, width: 100, height: 100); $0.addRect(x: 25, y: 25, width: 50, height: 50)
    }
    let nonZero = fill(rings, rule: .nonZero), evenOdd = fill(rings, rule: .evenOdd)
    #expect(nonZero.value(atX: 50, y: 50) == 255)
    #expect(evenOdd.value(atX: 50, y: 50) == 0)
    #expect(evenOdd.value(atX: 10, y: 50) == 255)
}

/// 1.16 (PA2) — the inner square reversed is a hole under both rules.
@Test func aReversedRingIsAHoleUnderBothRules() {
    let reversed: (inout PathGeometry) -> Void = { p in
        p.addRect(x: 0, y: 0, width: 100, height: 100)
        p.move(to: PathPoint(25, 25)); p.addLine(to: PathPoint(25, 75))
        p.addLine(to: PathPoint(75, 75)); p.addLine(to: PathPoint(75, 25)); p.closeSubpath()
    }
    for rule in [FillRule.nonZero, .evenOdd] {
        let m = fill(reversed, rule: rule)
        #expect(m.value(atX: 50, y: 50) == 0, "\(rule)")
        #expect(m.value(atX: 10, y: 50) == 255, "\(rule)")
    }
}

/// 1.17 (PA4) — the quadratic (0, 100)–(50, 0)–(100, 100), closed, covers
/// two thirds of its triangle's 5000: 3333.3 within 0.5 % (SwiftUI 3325.8).
/// One segment per curve would cover the whole triangle.
@Test func aQuadraticSegmentCoversItsArea() {
    let m = fill { p in
        p.move(to: PathPoint(0, 100)); p.addQuadCurve(to: PathPoint(100, 100), control: PathPoint(50, 0)); p.closeSubpath()
    }
    #expect(abs(area(m) - 3333.3) <= 3333.3 * 0.005, "area \(area(m))")
}

/// 1.18 (PA5) — the ellipse in 100×60 covers π·50·30 = 4712.4 within 0.3 %
/// (SwiftUI 4714.2). A wrong quarter-arc constant (0.5 for 0.5523) loses
/// about 1.7 %.
@Test func anEllipseCoversPiAB() {
    let m = fill { $0.addEllipse(x: 0, y: 0, width: 100, height: 60) }
    #expect(abs(area(m) - 4712.4) <= 4712.4 * 0.003, "area \(area(m))")
}

/// 1.19 (PA3) — a pie from (50, 50), radius 40, 0° to 90°: `clockwise:
/// false` sweeps through the below-right quadrant in y-down space ((70, 70)
/// covered, (70, 30) clear); `true` the other three quadrants.
@Test func clockwiseFalseSweepsThroughBelowRight() {
    func pie(_ clockwise: Bool) -> AlphaMask {
        fill { p in
            p.move(to: PathPoint(50, 50))
            p.addArc(center: PathPoint(50, 50), radius: 40, startAngle: 0, endAngle: Double.pi / 2, clockwise: clockwise)
            p.closeSubpath()
        }
    }
    let ccw = pie(false), cw = pie(true)
    #expect(ccw.value(atX: 70, y: 70) == 255 && ccw.value(atX: 70, y: 30) == 0)
    #expect(cw.value(atX: 70, y: 70) == 0 && cw.value(atX: 70, y: 30) == 255)
}

/// 1.29 — only the visible rectangle is rasterized: a 10 000 × 100 bar
/// clipped to 100 × 100 rasterizes at most 10 000 pixels (the clip ignored,
/// a million).
@Test func onlyTheVisibleRectangleIsRasterized() {
    var geometry = PathGeometry()
    geometry.addRect(x: -5000, y: 0, width: 10_000, height: 100)
    var rasterizer = CoverageRasterizer()
    let m = PathRaster.fill(geometry, rule: .nonZero, clip: RasterRect(x: 0, y: 0, width: 100, height: 100),
                            rasterizer: &rasterizer)
    #expect(rasterizer.lastRasterizedPixels > 0 && rasterizer.lastRasterizedPixels <= 10_000,
            "rasterized \(rasterizer.lastRasterizedPixels)")
    #expect(m.rect == RasterRect(x: 0, y: 0, width: 100, height: 100))
    #expect(m.alpha.allSatisfy { $0 == 255 })
}
