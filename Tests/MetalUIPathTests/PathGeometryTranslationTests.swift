import Testing
@testable import MetalUIPath

// C13 / PERF-a, lane 1 — `PathGeometry.translated(dx:dy:)` (ruling `PF-A` item
// 1: a path's canonical outline; spec
// `docs/superpowers/specs/2026-10-09-shadow-cache-design.md` test L1.12).

/// An outline with every element kind: a move, lines, a quad, a cubic, an
/// ellipse and a rounded rect (cubics at kappa), closed subpaths.
private func everyElement(at x: Double, _ y: Double) -> PathGeometry {
    var g = PathGeometry()
    g.move(to: PathPoint(x + 1, y + 2))
    g.addLine(to: PathPoint(x + 31.5, y + 2))
    g.addQuadCurve(to: PathPoint(x + 31.5, y + 20.25), control: PathPoint(x + 40, y + 9))
    g.addCurve(to: PathPoint(x + 1, y + 20.25), control1: PathPoint(x + 20, y + 30), control2: PathPoint(x + 5, y + 28))
    g.closeSubpath()
    g.addEllipse(x: x + 3, y: y + 40, width: 21, height: 13)
    g.addRoundedRect(x: x + 30, y: y + 40, width: 25, height: 17, rx: 5, ry: 5)
    return g
}

/// Every point of `g`, in element order.
private func points(_ g: PathGeometry) -> [PathPoint] {
    g.elements.flatMap { element -> [PathPoint] in
        switch element {
        case .move(let p), .line(let p): [p]
        case .quad(let c, let p): [c, p]
        case .cubic(let c1, let c2, let p): [c1, c2, p]
        case .close: []
        }
    }
}

/// **L1.12** (`PF-A` item 1). A translation adds `(dx, dy)` to every point,
/// keeps every element kind and close in place, and on an integer or dyadic
/// offset that keeps each coordinate on its own grid (toward zero, or within
/// its binade) is exact: translating back restores the same bits, and the
/// translated outline rasterizes to the same bytes over the shifted
/// rectangle. Mutation: a translation that skips control points (the quad's
/// and cubics' controls stay put — every check below but the end points
/// reddens).
@Test func aTranslatedPathMovesEveryPointExactly() throws {
    let g = everyElement(at: 100, 60)
    for (dx, dy) in [(Double(-97), Double(13)), (0.5, -0.25), (-100, -60), (-3, -2)] {
        let t = g.translated(dx: dx, dy: dy)
        try #require(t.elements.count == g.elements.count, "same element count")
        for (a, b) in zip(g.elements, t.elements) {
            switch (a, b) {
            case (.move, .move), (.line, .line), (.quad, .quad), (.cubic, .cubic), (.close, .close): break
            default: Issue.record("element kinds differ: \(a) vs \(b)")
            }
        }
        let moved = zip(points(g), points(t)).filter { $1.x != $0.x + dx || $1.y != $0.y + dy }
        #expect(moved.isEmpty, "(\(dx), \(dy)): \(moved.count) points not moved by the offset")
        #expect(t.translated(dx: -dx, dy: -dy) == g, "(\(dx), \(dy)): translating back restores the bits")
        #expect(t.currentPoint.map { PathPoint($0.x - dx, $0.y - dy) } == g.currentPoint, "current point moved")
    }
    // The raster is shift-invariant on whole pixels.
    var rasterizer = CoverageRasterizer()
    let clip = RasterRect(x: -500, y: -500, width: 3000, height: 3000)
    let base = PathRaster.fill(g, rule: .nonZero, clip: clip, rasterizer: &rasterizer)
    let shifted = PathRaster.fill(g.translated(dx: -97, dy: 13), rule: .nonZero, clip: clip, rasterizer: &rasterizer)
    #expect(shifted.rect == RasterRect(x: base.rect.x - 97, y: base.rect.y + 13, width: base.rect.width,
                                       height: base.rect.height), "the rectangle moves: \(shifted.rect) \(base.rect)")
    #expect(shifted.alpha == base.alpha, "the same coverage bytes")
}
