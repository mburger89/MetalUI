import Testing
import MetalUICore
import MetalUILayout
import MetalUIRender
@testable import MetalUI

// Plan task 11, part 2, lane 2: fill, stroke and strokeBorder (ruling
// `TE-AI`; probe groups F and K of
// `docs/probes/swiftui-shapes-and-rendering.swift`). Helpers in
// `ShapeTests.swift`. Every frame here is the shape's own size, so the shape
// sits at (0, 0) and a stroke's outset bounds read directly.

/// **2.7 — a stroke draws over the fill** (probe F4: `fill(red).stroke(blue,
/// 10)` — blue ink over (−5, −5, 110, 70), red inside; K1: a rectangle's
/// stroke is centred with a square outer corner). Two rects: the fill first,
/// then the stroke — its bounds outset by 5, border 10, a clear background.
///
/// Mutation: **M2g** the layers painted reversed.
@Test @MainActor func aStrokeDrawsOverTheFill() throws {
    let rects = paintedShapes(100, 60, Rectangle().fill(.accent).stroke(.textPrimary, lineWidth: Pixels(10)))
    try #require(rects.count == 2, "\(rects)")
    #expect(rects[0].rect == [0, 0, 100, 60] && rects[0].background == lightColour(.accent)
                && rects[0].border == [0, 0, 0, 0], "the fill first: \(rects[0])")
    #expect(rects[1].rect == [-5, -5, 110, 70] && rects[1].border == [10, 10, 10, 10]
                && rects[1].background.a == 0 && rects[1].borderColor == lightColour(.textPrimary)
                && rects[1].radii == [0, 0, 0, 0], "the stroke over it (F4, K1): \(rects[1])")
}

/// **2.8 — a strokeBorder is inside the edge** (probe K2: solid 0…100 × 0…60,
/// (9, 9) the stroke, (10, 10) empty).
///
/// Mutation: **M2h** `strokeBorder` outset.
@Test @MainActor func aStrokeBorderIsInsideTheEdge() throws {
    let rects = paintedShapes(100, 60, Rectangle().strokeBorder(.accent, lineWidth: Pixels(10)))
    try #require(rects.count == 1, "\(rects)")
    #expect(rects[0].rect == [0, 0, 100, 60] && rects[0].border == [10, 10, 10, 10]
                && rects[0].background.a == 0 && rects[0].borderColor == lightColour(.accent),
            "K2: \(rects[0])")
}

/// **2.9 — a stroke rounds its outer edge by half the width, only over a
/// curve** (probes K6: `RR(20).stroke(10)` equals `RR(25).strokeBorder(10)`
/// grown by 5, 0 px; K7: `Circle(60).stroke(10)` equals a 70 circle's
/// strokeBorder, 0 px; K12: `RR(3).stroke(10)` has a round outer corner, so
/// radius 8; K1: a rectangle's stays square).
///
/// Mutation: **M2i** `r + w/2` even at r = 0.
@Test @MainActor func aStrokeRoundsItsOuterEdgeByHalfTheWidthOnlyOverACurve() throws {
    func stroke<S: Shape>(_ shape: S, _ w: Float, _ h: Float) throws -> PaintedShape {
        let rects = paintedShapes(w, h, shape.stroke(.accent, lineWidth: Pixels(10)))
        try #require(rects.count == 1, "\(rects)")
        return rects[0]
    }
    let rr20 = try stroke(RoundedRectangle(cornerRadius: Pixels(20)), 100, 60)
    #expect(rr20.rect == [-5, -5, 110, 70] && rr20.radii == [25, 25, 25, 25], "K6: \(rr20)")
    let circle = try stroke(Circle(), 60, 60)
    #expect(circle.rect == [-5, -5, 70, 70] && circle.radii == [35, 35, 35, 35], "K7: \(circle)")
    let rr3 = try stroke(RoundedRectangle(cornerRadius: Pixels(3)), 100, 60)
    #expect(rr3.radii == [8, 8, 8, 8], "K12: \(rr3)")
    let rectangle = try stroke(Rectangle(), 100, 60)
    #expect(rectangle.radii == [0, 0, 0, 0], "K1: \(rectangle)")
}

/// **2.10 — a strokeBorder wider than twice the radius has a square outer
/// corner** (probe K11: `RR(3).strokeBorder(10)` reads (0, 0) fully red where
/// the RR(3) fill leaves it nearly white; 3228 outer-edge pixels differ from
/// the fill's). A radius at least half the width is kept (RR(20) → 20).
///
/// Mutation: **M2j** the radius kept.
@Test @MainActor func aStrokeBorderWiderThanTwiceTheRadiusHasASquareOuterCorner() throws {
    let rr3 = paintedShapes(100, 60, RoundedRectangle(cornerRadius: Pixels(3))
        .strokeBorder(.accent, lineWidth: Pixels(10)))
    try #require(rr3.count == 1, "\(rr3)")
    #expect(rr3[0].radii == [0, 0, 0, 0], "K11: \(rr3[0])")
    let rr20 = paintedShapes(100, 60, RoundedRectangle(cornerRadius: Pixels(20))
        .strokeBorder(.accent, lineWidth: Pixels(10)))
    try #require(rr20.count == 1, "\(rr20)")
    #expect(rr20[0].radii == [20, 20, 20, 20] && rr20[0].rect == [0, 0, 100, 60], "\(rr20[0])")
}

/// **2.11 — a stroke of zero or negative width draws nothing** (probe K9:
/// `stroke(0)` and `stroke(-4)` ink none). The width-1 arm is the control.
///
/// Mutation: **M2k** the guard dropped.
@Test @MainActor func aStrokeOfZeroOrNegativeWidthDrawsNothing() throws {
    try #require(paintedShapes(100, 60, Rectangle().stroke(.accent, lineWidth: Pixels(1))).count == 1,
                 "the control: a width-1 stroke draws")
    for width: Float in [0, -4] {
        #expect(paintedShapes(100, 60, Rectangle().stroke(.accent, lineWidth: Pixels(width))).isEmpty,
                "K9 stroke(\(width))")
        #expect(paintedShapes(100, 60, Rectangle().strokeBorder(.accent, lineWidth: Pixels(width))).isEmpty,
                "strokeBorder(\(width))")
        #expect(paintedShapes(100, 60, Circle().stroke(.accent, lineWidth: Pixels(width))).isEmpty)
    }
}

/// **2.12 — a stroke changes no layout, and its width defaults to one point**
/// (probes K5: `stroke(10)` and `strokeBorder` answer S1's rectangle row; K3:
/// the default stroke's ink is (−1, −1, 102, 62) at anti-aliasing, a 1 pt band
/// centred on the edge — (−0.5, −0.5, 101, 61) with border 1).
///
/// Mutation: **M2l** the default width 0.
@Test @MainActor func aStrokeChangesNoLayoutAndDefaultsToOnePoint() throws {
    let plain = kernelAnswers(Rectangle())
    #expect(kernelAnswers(Rectangle().stroke(.accent, lineWidth: Pixels(10))) == plain, "K5 stroke")
    #expect(kernelAnswers(Rectangle().strokeBorder(.accent, lineWidth: Pixels(10))) == plain, "K5 border")
    let stroke = paintedShapes(100, 60, Rectangle().stroke(.accent))
    try #require(stroke.count == 1, "K3: the default stroke draws: \(stroke)")
    #expect(stroke[0].rect == [-0.5, -0.5, 101, 61] && stroke[0].border == [1, 1, 1, 1], "K3: \(stroke[0])")
    let border = paintedShapes(100, 60, Rectangle().strokeBorder(.accent))
    try #require(border.count == 1, "\(border)")
    #expect(border[0].border == [1, 1, 1, 1] && border[0].rect == [0, 0, 100, 60])
}

/// **2.13 — an ellipse's stroke is the ellipse band over the outset bounds**
/// (probe K8: `Ellipse().strokeBorder(10)` is the inset ellipse's stroke, not
/// a concentric hole — the shader's band, `TE-AE`; lane 1's
/// `anEllipseBorderIsTheStrokeOfTheInsetEllipse` pins the pixels). Here: the
/// strokeBorder is kind 1 over the bounds with border 10, the stroke kind 1
/// over the bounds outset by 5.
///
/// Mutation: **M2m** the ellipse stroke not outset.
@Test @MainActor func anEllipseStrokeIsTheEllipseBandOverTheOutsetBounds() throws {
    let ellipse = PrimitiveShape.ellipse.rawValue
    let border = paintedShapes(100, 60, Ellipse().strokeBorder(.accent, lineWidth: Pixels(10)))
    try #require(border.count == 1, "\(border)")
    #expect(border[0].rect == [0, 0, 100, 60] && border[0].border == [10, 10, 10, 10]
                && border[0].kind == ellipse, "K8 strokeBorder: \(border[0])")
    let stroke = paintedShapes(100, 60, Ellipse().stroke(.accent, lineWidth: Pixels(10)))
    try #require(stroke.count == 1, "\(stroke)")
    #expect(stroke[0].rect == [-5, -5, 110, 70] && stroke[0].border == [10, 10, 10, 10]
                && stroke[0].kind == ellipse, "stroke: \(stroke[0])")
}
