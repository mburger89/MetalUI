import Testing
import MetalUICore
import MetalUILayout
import MetalUIScene
import MetalUIPath
@testable import MetalUI

// Round 3, item R3-8 — path operations on the public `Path`/`Shape` API
// (rulings `PG-A`…`PG-G`). SwiftUI's side is `docs/probes/swiftui-path-ops.swift`
// (arms TS, TR, SP, AR, UR, X, Y); the arc-length maths itself is pinned in
// `MetalUIPathTests/PathTrimTests.swift`, which runs on Linux and Windows too.

private func f(_ v: Double) -> String {
    let r = (v * 1000).rounded() / 1000
    return r == r.rounded() ? String(Int(r)) : String(r)
}

/// A path's elements as `M(x,y) L(x,y) C(x,y) Z`, curves by their end point.
@MainActor private func trace(_ path: Path) -> [String] {
    path.storage.elements.map { e in
        switch e {
        case .move(let a): "M(\(f(a.x)),\(f(a.y)))"
        case .line(let a): "L(\(f(a.x)),\(f(a.y)))"
        case .quad(_, let a): "Q(\(f(a.x)),\(f(a.y)))"
        case .cubic(_, _, let a): "C(\(f(a.x)),\(f(a.y)))"
        case .close: "Z"
        }
    }
}

@MainActor private func end(_ path: Path) -> (Double, Double)? {
    path.storage.currentPoint.map { ($0.x, $0.y) }
}

private func near(_ a: (Double, Double)?, _ x: Double, _ y: Double, _ tolerance: Double = 1e-3) -> Bool {
    guard let a else { return false }
    return abs(a.0 - x) <= tolerance && abs(a.1 - y) <= tolerance
}

@MainActor private let wide = gxRect(0, 0, 100, 60)
private let linear1 = Animation.linear(duration: 1)

// MARK: - Start points (PG-A, probe TS)

/// **PG-A 10** (TS, TS2, TS2c, X11–X13). A built-in's outline starts where
/// SwiftUI's does, so `trim` and dashes begin there: a rectangle top-left
/// running right; a rounded rectangle, capsule, circle and ellipse on the right
/// edge's midpoint running down. Pinned by the first element and by where
/// `trim(from: 0, to: 0.25)` ends in 100×60. Mutation **PGM16**: the rounded
/// rectangle's outline started at its top edge again (the pre-R3-8 order).
@Test @MainActor func aBuiltInShapesOutlineStartsWhereSwiftUIsDoes() {
    let cases: [(String, Path, String, (Double, Double))] = [
        ("Rectangle", Rectangle().path(in: wide), "M(0,0)", (80, 0)),
        ("RoundedRectangle", RoundedRectangle(cornerRadius: 20, style: .circular).path(in: wide), "M(100,30)", (50, 60)),
        ("Capsule", Capsule().path(in: wide), "M(100,30)", (50, 60)),
        ("Circle", Circle().path(in: wide), "M(80,30)", (50, 60)),
        ("Ellipse", Ellipse().path(in: wide), "M(100,30)", (50, 60)),
    ]
    for (name, path, start, quarter) in cases {
        #expect(trace(path).first == start, "\(name): \(trace(path))")
    }
    let trimmed: [(String, Path, (Double, Double))] = [
        ("Rectangle", Rectangle().trim(from: 0, to: 0.25).path(in: wide), (80, 0)),
        ("RoundedRectangle", RoundedRectangle(cornerRadius: 20, style: .circular).trim(from: 0, to: 0.25).path(in: wide), (50, 60)),
        ("Capsule", Capsule().trim(from: 0, to: 0.25).path(in: wide), (50, 60)),
        ("Circle", Circle().trim(from: 0, to: 0.25).path(in: wide), (50, 60)),
        ("Ellipse", Ellipse().trim(from: 0, to: 0.25).path(in: wide), (50, 60)),
    ]
    for (name, path, quarter) in trimmed {
        #expect(near(end(path), quarter.0, quarter.1, 1e-2), "\(name): \(String(describing: end(path)))")
    }
    #expect(near(end(Circle().trim(from: 0, to: 0.25).path(in: gxRect(0, 0, 100, 100))), 50, 100, 1e-2), "TS2b")
    #expect(near(end(Circle().trim(from: 0, to: 0.5).path(in: gxRect(0, 0, 100, 100))), 0, 50, 1e-2), "TS2")
    let rr = RoundedRectangle(cornerRadius: 10, style: .circular).trim(from: 0, to: 0.5).path(in: wide)
    #expect(near(end(rr), 0, 30, 1e-2), "X11 half-way round is the left edge's midpoint: \(String(describing: end(rr)))")
    #expect(trace(Rectangle().trim(from: 0.1, to: 0.2).path(in: wide)) == ["M(32,0)", "L(64,0)"], "X13")
}

/// **PG-A 11** (TR3). `Path.trimmedPath` reaches the arc-length trim:
/// a 10-then-90 polyline 0…0.5 ends (10, 40); the result is a `Path` again.
@Test @MainActor func pathTrimmedPathIsArcLength() {
    let path = Path { p in
        p.move(to: gxPoint(0, 0)); p.addLine(to: gxPoint(10, 0)); p.addLine(to: gxPoint(10, 90))
    }
    #expect(trace(path.trimmedPath(from: 0, to: 0.5)) == ["M(0,0)", "L(10,0)", "L(10,40)"])
    #expect(path.trimmedPath(from: 0.6, to: 0.4).isEmpty)
}

/// **PG-A 12.** A trimmed shape lays out as its base does: `Circle().trim` in
/// a 100×60 proposal is 60×60, as `Circle` is.
@Test @MainActor func aTrimmedShapeLaysOutAsItsBase() {
    let size = Circle().trim(from: 0, to: 0.5).sizeThatFits(ProposedSize(width: 100, height: 60))
    #expect(size.width == 60 && size.height == 60, "\(size)")
}

// MARK: - Animation (PG-F)

/// Samples the alpha of the one image `frame` drew, 0 where it drew none.
@MainActor private func alpha(_ frame: Frame, _ x: Int, _ y: Int) -> Int {
    let images = gxImages(frame.finalizedScene())
    return images.count == 1 ? gxAlpha(images[0], x, y) : -1
}

/// **PG-F 1** (N10). `trim(from: 0, to:)` animates under a transaction: a
/// 100-long line stroked 4 wide, `to` 0.2 then 1 under a one-second linear
/// animation, is drawn to x = 60 half-way (0.6), to x = 100 at the end; the
/// first frame and a change with no transaction snap. Mutation **PGM17**:
/// `animatedForPaint` returns `self` (the trim snaps to 1 at once).
@Test @MainActor func trimAnimatesItsEndFraction() {
    let line = Path { p in p.move(to: gxPoint(0, 10)); p.addLine(to: gxPoint(100, 10)) }
    func tree(_ to: Double) -> some Element {
        line.trim(from: 0, to: to).stroke(.accent, lineWidth: Pixels(4)).frame(width: Pixels(100), height: Pixels(20))
    }
    let h = TransitionHarness()
    let first = h.frame(0, nil, tree(0.2), side: 100)
    #expect(alpha(first, 15, 50) == 255 && alpha(first, 25, 50) == 0, "first sighting draws the declared 0.2")
    h.frame(0, linear1, tree(1), side: 100)
    let mid = h.frame(0.5, nil, tree(1), side: 100)
    #expect(alpha(mid, 55, 50) == 255 && alpha(mid, 65, 50) == 0, "half-way is 0.6: \(alpha(mid, 55, 50)) \(alpha(mid, 65, 50))")
    let done = h.frame(1.5, nil, tree(1), side: 100)
    #expect(alpha(done, 95, 50) == 255, "settled at 1")
    let snap = TransitionHarness()
    snap.frame(0, nil, tree(0.2), side: 100)
    let snapped = snap.frame(0.5, nil, tree(1), side: 100)
    #expect(alpha(snapped, 95, 50) == 255, "no transaction: snaps")
}

/// **PG-F 2.** A bare trimmed shape (fill, no `ShapeView`) animates through the
/// same seam: `Rectangle().trim(from: 0, to:)` 0.5 → 1 half-way is 0.75, the
/// outline running to (30, 40) so the fill covers (60, 35) but not (10, 35).
/// Mutation **PGM18**: `Shape.paint` skipping `shapeForPaint`.
@Test @MainActor func aBareTrimmedShapeAnimatesToo() {
    func tree(_ to: Double) -> some Element {
        Rectangle().trim(from: 0, to: to).frame(width: Pixels(100), height: Pixels(40))
    }
    let h = TransitionHarness()
    let first = h.frame(0, nil, tree(0.5), side: 100)
    #expect(alpha(first, 60, 65) == 0, "0.5: the triangle above the diagonal")
    h.frame(0, linear1, tree(1), side: 100)
    let mid = h.frame(0.5, nil, tree(1), side: 100)
    #expect(alpha(mid, 60, 65) == 255 && alpha(mid, 10, 65) == 0,
            "0.75: \(alpha(mid, 60, 65)) \(alpha(mid, 10, 65))")
}

/// **PG-F 3.** Both fractions animate: `trim(from:to:)` 0.0/0.5 → 0.5/1 slides
/// a window. Half-way (0.25, 0.75) of a 100-long line leaves x 25…75.
@Test @MainActor func bothFractionsAnimate() {
    let line = Path { p in p.move(to: gxPoint(0, 10)); p.addLine(to: gxPoint(100, 10)) }
    func tree(_ a: Double, _ b: Double) -> some Element {
        line.trim(from: a, to: b).stroke(.accent, lineWidth: Pixels(4)).frame(width: Pixels(100), height: Pixels(20))
    }
    let h = TransitionHarness()
    h.frame(0, nil, tree(0, 0.5), side: 100)
    h.frame(0, linear1, tree(0.5, 1), side: 100)
    let mid = h.frame(0.5, nil, tree(0.5, 1), side: 100)
    #expect(alpha(mid, 20, 50) == 0 && alpha(mid, 30, 50) == 255 && alpha(mid, 70, 50) == 255
            && alpha(mid, 80, 50) == 0, "25…75")
}

// MARK: - strokedPath (PG-B)

/// **PG-B 5** (SP ring). A circle of radius 50 stroked 10 wide: (50, 2) and
/// (50, −2) are in the band, (50, 8), (50, 12) and the centre are not — the
/// probe's own samples. Mutation **PGM19**: `strokedPath` returning `self`.
@Test @MainActor func strokedPathFillsAndHitTestsAsTheStroke() {
    let ring = Path(ellipseIn: gxRect(0, 0, 100, 100)).strokedPath(StrokeStyle(lineWidth: Pixels(10)))
    #expect(ring.contains(gxPoint(50, 2)) && ring.contains(gxPoint(50, -2)))
    #expect(!ring.contains(gxPoint(50, 8)) && !ring.contains(gxPoint(50, 12)) && !ring.contains(gxPoint(50, 50)))
    let b = ring.boundingRect
    #expect(abs(b.origin.x.value + 5) < 0.02 && abs(b.size.width.value - 110) < 0.04, "bounds \(b)")
    let dashed = Path { p in p.move(to: gxPoint(0, 0)); p.addLine(to: gxPoint(20, 0)) }
        .strokedPath(StrokeStyle(lineWidth: Pixels(2), dash: [Pixels(4), Pixels(4)]))
    #expect(dashed.contains(gxPoint(2, 0)) && !dashed.contains(gxPoint(6, 0)), "SP dash")
    #expect(Path(gxRect(0, 0, 10, 10)).strokedPath(StrokeStyle(lineWidth: Pixels(0))).isEmpty, "SP w0")
}

/// **PG-B 6** (X8, X9). A closed rectangle 20×10 stroked 4: the band is solid at
/// (10, 0) and (10, 1.9), clear at (10, 2.1) and the centre; a trimmed line
/// stroked with round caps spans x 18…72 (0.2…0.7 of 100, ±2).
@Test @MainActor func strokedPathOfAClosedRectAndOfATrim() {
    let frame = Path(gxRect(0, 0, 20, 10)).strokedPath(StrokeStyle(lineWidth: Pixels(4)))
    #expect(frame.contains(gxPoint(10, 0)) && frame.contains(gxPoint(10, 1.9)) && frame.contains(gxPoint(-1.9, -1.9)))
    #expect(!frame.contains(gxPoint(10, 2.1)) && !frame.contains(gxPoint(10, 5)))
    let line = Path { p in p.move(to: gxPoint(0, 0)); p.addLine(to: gxPoint(100, 0)) }
    let capped = line.trimmedPath(from: 0.2, to: 0.7).strokedPath(StrokeStyle(lineWidth: Pixels(4), lineCap: .round))
    let b = capped.boundingRect
    #expect(abs(b.origin.x.value - 18) < 0.02 && abs(b.size.width.value - 54) < 0.04, "X9 \(b)")
}

// MARK: - Transforms and relative arcs (PG-D, PG-E)

/// **PG-E 1** (AR7, AR8). `CGAffineTransform`'s order: translate(5, 7) then
/// `rotated(by: 90°)` maps a 10×20 rectangle to (5,7) (5,17) (−15,17) (−15,7);
/// `applying` moves control points too; `concatenating` applies the receiver
/// first. Mutation **PGM20**: `rotated` applied after the receiver.
@Test @MainActor func transform2DAppliesInCoreGraphicsOrder() {
    let t = Transform2D(translationX: 5, y: 7).rotated(by: .degrees(90))
    let moved = Path(gxRect(0, 0, 10, 20)).applying(t)
    #expect(trace(moved) == ["M(5,7)", "L(5,17)", "L(-15,17)", "L(-15,7)", "Z"], "\(trace(moved))")
    let both = Transform2D(scaleX: 2, y: 1).concatenating(Transform2D(translationX: 10, y: 0))
    #expect(both.affine.apply(PathPoint(3, 4)) == PathPoint(16, 4), "scale first, then translate")
    let inverse = t.inverted()
    let back = inverse.affine.apply(t.affine.apply(PathPoint(3, 4)))
    #expect(abs(back.x - 3) < 1e-12 && abs(back.y - 4) < 1e-12)
    let curve = Path { p in p.move(to: gxPoint(0, 0)); p.addQuadCurve(to: gxPoint(10, 0), control: gxPoint(5, 10)) }
    guard case .quad(let control, _) = curve.applying(Transform2D(scaleX: 1, y: 2)).storage.elements[1] else {
        Issue.record("not a quad"); return
    }
    #expect(control == PathPoint(5, 20), "the control point is mapped")
    #expect(trace(Path(gxRect(0, 0, 10, 20)).offsetBy(dx: 3, dy: 4)) == ["M(3,4)", "L(13,4)", "L(13,24)", "L(3,24)", "Z"])
}

/// **PG-E 2** (AR5, AR6, AR9). `transform:` on the add-methods: `addRect`
/// translated (1, 2) is (1,2) → (11,22); a +90° relative arc translated (10, 20)
/// spans x 60…110 y 70…120 and starts at (110, 70); an `addArc` scaled (2, 1)
/// ends at (100, 100); an `addEllipse`, `addRoundedRect` and `addPath` take it
/// too, and the arc's connecting line is drawn from the untransformed current
/// point. Mutation **PGM21**: the transform parameter ignored by one method
/// (each of the six reddens its own line).
@Test @MainActor func addMethodsTakeATransform() {
    var rect = Path()
    rect.addRect(gxRect(0, 0, 10, 20), transform: Transform2D(translationX: 1, y: 2))
    #expect(trace(rect) == ["M(1,2)", "L(11,2)", "L(11,22)", "L(1,22)", "Z"])
    var arc = Path()
    arc.addRelativeArc(center: gxPoint(50, 50), radius: Pixels(50), startAngle: .degrees(0), delta: .degrees(90),
                       transform: Transform2D(translationX: 10, y: 20))
    #expect(trace(arc).first == "M(110,70)" && near(end(arc), 60, 120), "\(trace(arc))")
    var abs0 = Path()
    abs0.addArc(center: gxPoint(50, 50), radius: Pixels(50), startAngle: .degrees(0), endAngle: .degrees(90),
                clockwise: false, transform: Transform2D(scaleX: 2, y: 1))
    #expect(near(end(abs0), 100, 100), "AR6 \(String(describing: end(abs0)))")
    var ellipse = Path()
    ellipse.addEllipse(in: gxRect(0, 0, 10, 10), transform: Transform2D(translationX: 5, y: 0))
    #expect(trace(ellipse).first == "M(15,5)", "\(trace(ellipse))")
    var rounded = Path()
    rounded.addRoundedRect(in: gxRect(0, 0, 10, 10), cornerSize: Size(width: Pixels(2), height: Pixels(2)),
                           transform: Transform2D(translationX: 0, y: 3))
    #expect(rounded.boundingRect.origin.y.value == 3, "\(rounded.boundingRect)")
    var composed = Path()
    composed.addPath(Path(gxRect(0, 0, 4, 4)), transform: Transform2D(scaleX: 2, y: 2))
    #expect(trace(composed) == ["M(0,0)", "L(8,0)", "L(8,8)", "L(0,8)", "Z"])
    var rects = Path()
    rects.addRects([gxRect(0, 0, 1, 1), gxRect(2, 0, 1, 1)], transform: Transform2D(translationX: 0, y: 1))
    #expect(trace(rects).filter { $0.hasPrefix("M") } == ["M(0,1)", "M(2,1)"])
    var joined = Path()
    joined.move(to: gxPoint(0, 0))
    joined.addRelativeArc(center: gxPoint(50, 50), radius: Pixels(50), startAngle: .degrees(0), delta: .degrees(90),
                          transform: Transform2D(translationX: 10, y: 20))
    #expect(Array(trace(joined).prefix(2)) == ["M(0,0)", "L(110,70)"], "\(trace(joined))")
    var tangent = Path()
    tangent.move(to: gxPoint(10, 10))
    tangent.addArc(tangent1End: gxPoint(10, 20), tangent2End: gxPoint(30, 20), radius: Pixels(5),
                   transform: Transform2D(translationX: 100, y: 0))
    // Core Graphics' rule: the tangent points are mapped, the current point (10, 10) is not,
    // so the arc runs from (10, 10) toward (110, 20) and (130, 20), ending on that second line.
    #expect(near(end(tangent), 110.249, 20, 1e-2), "\(String(describing: end(tangent)))")
}

/// **PG-D 4** (AR1–AR4). The public relative arc: +90° from (100, 50) to (50, 100);
/// −90° ends (50, 0); 450° ends (50, 100). Equals `addArc(clockwise: false)`.
@Test @MainActor func pathAddRelativeArcSweepsBySignedDelta() {
    func arc(_ degrees: Double) -> Path {
        var p = Path()
        p.addRelativeArc(center: gxPoint(50, 50), radius: Pixels(50), startAngle: .degrees(0), delta: .degrees(degrees))
        return p
    }
    #expect(near(end(arc(90)), 50, 100) && near(end(arc(-90)), 50, 0) && near(end(arc(450)), 50, 100))
    var absolute = Path()
    absolute.addArc(center: gxPoint(50, 50), radius: Pixels(50), startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
    #expect(arc(90) == absolute)
}

// MARK: - UnevenRoundedRectangle (PG-G)

/// **PG-G 1** (Y1–Y7, UR3). SwiftUI's radius fitting: 45/45 on a side of 60
/// become 30/30; 20/50 become 20/40; 70/70 on 100 become 50/50; one 80 on a
/// 60-high rect becomes 60; all 40 become 30; a negative radius is 0; a lone
/// 45 stays 45 though the rectangle is 60 high. Mutation **PGM22**: radii
/// clamped to half the shorter side (as the SDF would) — the lone 45 becomes 30.
@Test @MainActor func radiiFitByTheSwiftUIRule() {
    func fit(_ tl: Float, _ bl: Float, _ br: Float, _ tr: Float) -> [Double] {
        let c = RectangleCornerRadii(topLeading: Pixels(tl), bottomLeading: Pixels(bl),
                                     bottomTrailing: Pixels(br), topTrailing: Pixels(tr)).fitted(width: 100, height: 60)
        return [c.topLeft, c.bottomLeft, c.bottomRight, c.topRight]
    }
    #expect(fit(45, 45, 0, 0) == [30, 30, 0, 0], "Y1")
    #expect(fit(50, 50, 0, 0) == [30, 30, 0, 0], "Y2")
    #expect(fit(80, 0, 0, 0) == [60, 0, 0, 0], "Y3")
    #expect(fit(70, 0, 0, 70) == [50, 0, 0, 50], "Y4")
    #expect(fit(20, 50, 0, 0) == [20, 40, 0, 0], "Y5")
    #expect(fit(40, 40, 40, 40) == [30, 30, 30, 30], "Y7")
    #expect(fit(45, 0, 0, 0) == [45, 0, 0, 0], "X2")
    #expect(fit(-5, 0, 10, 10) == [0, 0, 10, 10], "UR3")
    #expect(fit(30, 10, 20, 0) == [30, 10, 20, 0], "UR1 untouched")
}

/// **PG-G 2** (X3, X2, UR1, UR3). The outline is SwiftUI's with the probe's
/// order: 30/10/20/0 circular is `M(100,20) L(100,40) C(80,60) L(10,60) C(0,50)
/// L(0,30) C(30,0) L(100,0) Z` (the probe's zero-radius corner is a degenerate
/// curve, here no element); a lone 45 is `M(100,30) L(100,60) L(0,60) L(0,45)
/// C(45,0) L(100,0) Z`; the start is half-way down the right edge between the
/// top-right and bottom-right corners. Mutation **PGM23**: the start taken as
/// the edge's midpoint ignoring the radii.
@Test @MainActor func anUnevenOutlineIsSwiftUIs() {
    let shape = UnevenRoundedRectangle(topLeadingRadius: 30, bottomLeadingRadius: 10, bottomTrailingRadius: 20,
                                       topTrailingRadius: 0, style: .circular)
    #expect(trace(shape.path(in: wide)) == ["M(100,20)", "L(100,40)", "C(80,60)", "L(10,60)", "C(0,50)",
                                            "L(0,30)", "C(30,0)", "L(100,0)", "Z"], "\(trace(shape.path(in: wide)))")
    let lone = UnevenRoundedRectangle(topLeadingRadius: 45, style: .circular)
    #expect(trace(lone.path(in: wide)) == ["M(100,30)", "L(100,60)", "L(0,60)", "L(0,45)", "C(45,0)", "L(100,0)", "Z"],
            "\(trace(lone.path(in: wide)))")
    let negative = UnevenRoundedRectangle(topLeadingRadius: -5, bottomTrailingRadius: 10, topTrailingRadius: 10)
    #expect(trace(negative.path(in: wide)).first == "M(100,30)", "UR3 starts mid-edge")
    #expect(trace(shape.trim(from: 0, to: 1).path(in: wide)) == trace(shape.path(in: wide)),
            "a whole-range trim keeps the outline and its close")
}

/// **PG-G 3** (UR1b). Hit testing follows the corners: with 30/10/20/0 on
/// 100×60, (1, 1) is outside the 30-radius corner, (99, 1) inside the square
/// one, (1, 59) outside the 10-radius corner, (99, 59) outside the 20-radius one.
@Test @MainActor func anUnevenRectangleContainsByItsCorners() {
    let geometry = UnevenRoundedRectangle(topLeadingRadius: 30, bottomLeadingRadius: 10, bottomTrailingRadius: 20,
                                          topTrailingRadius: 0).geometry(in: wide)
    #expect(!geometry.contains(gxPoint(1, 1)) && geometry.contains(gxPoint(99, 1)))
    #expect(!geometry.contains(gxPoint(1, 59)) && !geometry.contains(gxPoint(99, 59)) && geometry.contains(gxPoint(50, 30)))
    let path = UnevenRoundedRectangle(topLeadingRadius: 30, bottomLeadingRadius: 10, bottomTrailingRadius: 20,
                                      topTrailingRadius: 0).path(in: wide)
    #expect(!path.contains(gxPoint(1, 1)) && path.contains(gxPoint(99, 1)) && !path.contains(gxPoint(99, 59)))
}

/// **PG-G 4.** The renderer's per-corner rectangle draws an uneven rectangle
/// when every fitted radius is at most half the shorter side: one rect with the
/// four radii, no image, for fill and strokeBorder; a radius past it is a path
/// (one image, no rect). Mutation **PGM24**: every uneven rectangle taken as
/// a path (the first expectation reddens), or none (the second).
@Test @MainActor func anUnevenRectangleUsesTheSDFWhenItCanAndAPathWhenItMust() throws {
    let small = UnevenRoundedRectangle(topLeadingRadius: 30, bottomLeadingRadius: 10, bottomTrailingRadius: 20,
                                       topTrailingRadius: 0)
    let fill = effectFrame(small.fill(.accent).frame(width: Pixels(100), height: Pixels(60))).finalizedScene()
    try #require(fill.rects.count == 1 && fill.images.isEmpty, "\(fill.rects.count) rects, \(fill.images.count) images")
    let radii = fill.rects[0].cornerRadii
    #expect(radii.topLeft == 30 && radii.bottomLeft == 10 && radii.bottomRight == 20 && radii.topRight == 0, "\(radii)")
    let border = effectFrame(small.strokeBorder(.accent, lineWidth: Pixels(2)).frame(width: Pixels(100), height: Pixels(60)))
        .finalizedScene()
    #expect(border.rects.count == 1 && border.images.isEmpty, "strokeBorder: the band")
    let big = UnevenRoundedRectangle(topLeadingRadius: 45)
    let path = effectFrame(big.fill(.accent).frame(width: Pixels(100), height: Pixels(60))).finalizedScene()
    #expect(path.rects.isEmpty && path.images.count == 1, "a 45 radius on a 60-high rect is a path")
    let stroked = effectFrame(big.stroke(.accent, lineWidth: Pixels(2)).frame(width: Pixels(100), height: Pixels(60)))
        .finalizedScene()
    #expect(stroked.images.count == 1, "its stroke is a path stroke")
}

/// **PG-G 5.** An uneven rectangle with small radii is a legacy-clip shape like
/// `RoundedRectangle` (a rounded-rectangle geometry); its radii carry through.
@Test @MainActor func anUnevenRectangleIsARoundedRectangleGeometryWhenSmall() {
    let geometry = UnevenRoundedRectangle(topLeadingRadius: 12, bottomTrailingRadius: 6).geometry(in: wide)
    let region = geometry.clipRegion
    #expect(region.radii.topLeft == 12 && region.radii.bottomRight == 6 && region.radii.topRight == 0)
    #expect(UnevenRoundedRectangle(cornerRadii: RectangleCornerRadii(topLeading: 1))
        == UnevenRoundedRectangle(topLeadingRadius: 1))
}
