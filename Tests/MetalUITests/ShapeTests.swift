import Testing
import MetalUICore
import MetalUILayout
import MetalUIRender
@testable import MetalUI

// Plan task 11, part 2, lane 2: `Shape`, the built-in shapes, a bare shape's
// fill and backgrounds in a shape (spec
// `docs/superpowers/specs/2026-09-28-shapes-and-rendering-design.md` §8 lane 2,
// rulings `TE-AG`, `TE-AH`, `TE-AK`, `TE-AQ`). Every expected value is a
// probe reading (`docs/probes/swiftui-shapes-and-rendering.swift`, arm named
// on each test) or derived from one before the run. The helpers here are
// shared with `ShapeStrokeTests.swift` and `ClipShapeTests.swift`.

/// One emitted `MUIRect`, reduced to what these tests assert.
struct PaintedShape: Equatable, CustomStringConvertible {
    var rect: [Float]
    var radii: [Float]
    var border: [Float]
    var kind: UInt32
    var mask: [Float]
    var maskRadii: [Float]
    var background: Hsla
    var borderColor: Hsla

    init(_ r: MUIRect) {
        rect = [r.bounds.origin.x, r.bounds.origin.y, r.bounds.size.width, r.bounds.size.height]
        radii = [r.cornerRadii.topLeft, r.cornerRadii.topRight, r.cornerRadii.bottomRight,
                 r.cornerRadii.bottomLeft]
        border = [r.borderWidths.top, r.borderWidths.right, r.borderWidths.bottom, r.borderWidths.left]
        kind = r.shape
        mask = [r.contentMask.origin.x, r.contentMask.origin.y, r.contentMask.size.width,
                r.contentMask.size.height]
        maskRadii = [r.maskCornerRadii.topLeft, r.maskCornerRadii.topRight,
                     r.maskCornerRadii.bottomRight, r.maskCornerRadii.bottomLeft]
        background = Hsla(h: r.background.h, s: r.background.s, l: r.background.l, a: r.background.a)
        borderColor = Hsla(h: r.borderColor.h, s: r.borderColor.s, l: r.borderColor.l, a: r.borderColor.a)
    }

    var description: String {
        "rect \(rect) radii \(radii) border \(border) kind \(kind) mask \(mask) maskRadii \(maskRadii) "
            + "bg \(background) borderColor \(borderColor)"
    }
}

/// Renders `root` into a `width × height` frame (light theme, scale 1) and
/// returns its rects in emission order. A root is placed centred at its own
/// answer (`CN-J`), so a root that answers the frame's size sits at (0, 0).
@MainActor
func paintedShapes<E: Element>(_ width: Float, _ height: Float, _ root: E) -> [PaintedShape] {
    var root = root
    let frame = Frame(contentSize: Size(width: Pixels(width), height: Pixels(height)), scaleFactor: 1)
    frame.render(&root)
    return frame.finalizedScene().rects.map(PaintedShape.init)
}

/// The light theme's colour for `token`, as an emitted rect carries it.
func lightColour(_ token: ColorToken) -> Hsla { Theme.light[token] }

func shapeBounds(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> Bounds<Pixels> {
    Bounds(origin: Point(x: Pixels(x), y: Pixels(y)), size: Size(width: Pixels(w), height: Pixels(h)))
}

func proposal(_ width: Double?, _ height: Double?) -> ProposedSize {
    ProposedSize(width: width, height: height)
}

/// The five proposals of probe S1, in its order.
let s1Proposals = [proposal(nil, nil), proposal(100, 60), proposal(0, 0),
                   proposal(.infinity, .infinity), proposal(100, nil)]

/// A custom layout that measures its only subview at fixed proposals and
/// records the answers — the kernel measuring the shape's own leaf, probe S1's
/// recording `Layout`. It answers 0×0 and places nothing.
struct MeasuresShapeAt: ProposalLayout {
    let proposals: [ProposedSize]
    let answers: ShapeAnswerRecord

    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
        answers.sizes = proposals.map { subviews[0].sizeThatFits($0).size }
        return LayoutMeasurement(size: .zero)
    }

    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize, subviews: PlacementSubviews) {}
}

final class ShapeAnswerRecord: @unchecked Sendable {
    var sizes: [SizeD] = []
}

/// `content`'s answers at `proposals`, measured through the kernel.
@MainActor
func kernelAnswers<C: ProposalElementGroup>(_ content: C,
                                            at proposals: [ProposedSize] = s1Proposals) -> [SizeD] {
    let record = ShapeAnswerRecord()
    var root = ProposalLayoutContainer(MeasuresShapeAt(proposals: proposals, answers: record)) { content }
    let frame = Frame(contentSize: Size(width: Pixels(200), height: Pixels(200)), scaleFactor: 1)
    frame.render(&root)
    return record.sizes
}

private func size(_ w: Double, _ h: Double) -> SizeD { SizeD(width: w, height: h) }

// MARK: - 2.1–2.4 sizing and geometry

/// **2.1 — every built-in answers its proposal, a nil axis 10; a `Circle`
/// the square of the smaller side** (probe S1's 5 × 5 table, verbatim, through
/// the kernel). The `Circle` row is the separating one: at 100×60 it answers
/// 60×60 and at 100×nil 100×100, where every other shape answers 100×60 and
/// 100×10.
///
/// Mutation: **M2a** `Circle` keeps the default answer.
@Test @MainActor func everyBuiltInShapeAnswersItsProposalAndACircleTheSmallerSquare() throws {
    let inf = Double.infinity
    let proposalAnswers = [size(10, 10), size(100, 60), size(0, 0), size(inf, inf), size(100, 10)]
    let circleAnswers = [size(10, 10), size(60, 60), size(0, 0), size(inf, inf), size(100, 100)]
    try #require(proposalAnswers != circleAnswers, "the Circle row must separate")

    #expect(kernelAnswers(Rectangle()) == proposalAnswers, "S1 Rectangle")
    #expect(kernelAnswers(RoundedRectangle(cornerRadius: Pixels(12))) == proposalAnswers,
            "S1 RoundedRectangle")
    #expect(kernelAnswers(Circle()) == circleAnswers, "S1 Circle")
    #expect(kernelAnswers(Capsule()) == proposalAnswers, "S1 Capsule")
    #expect(kernelAnswers(Ellipse()) == proposalAnswers, "S1 Ellipse")
    #expect(kernelAnswers(Circle().fill(.accent)) == circleAnswers, "S1 Circle.fill")
    #expect(kernelAnswers(Circle().stroke(.accent)) == circleAnswers, "S1 Circle.stroke")
    // nil on the other axis takes this one's value (S1 100×nil → 100×100).
    #expect(kernelAnswers(Circle(), at: [proposal(nil, 40)]) == [size(40, 40)])
}

/// **CX.1 — a `Color` answers its proposal, a nil axis 10** (shapes-and-
/// rendering probe P2: `Color` nil×nil→10×10, 100×60→100×60, 0×0→0×0,
/// inf×inf→inf×inf, 100×nil→100×10). P2's own separating arm is the fixed
/// 40×20 view that answers 40×20 at all five; it is `#require`d here first, so
/// the instrument is shown to see a non-filling answer (closeout, `CX-A`).
///
/// Mutation: `Color.measurement`'s nil-axis ideal 10 → 20 (the nil×nil and
/// 100×nil arms).
@Test @MainActor func aColorAnswersItsProposalAndTenOnANilAxis() throws {
    let inf = Double.infinity
    let fixed = Array(repeating: size(40, 20), count: 5)
    try #require(kernelAnswers(Color(.accent).frame(width: Pixels(40), height: Pixels(20))) == fixed,
                 "P2 fixed 40x20")
    #expect(kernelAnswers(Color(.accent))
            == [size(10, 10), size(100, 60), size(0, 0), size(inf, inf), size(100, 10)], "P2 Color")
}

/// **CX.2 — `.fixedSize()` keeps a text on one line in a narrow stack**
/// (stage-2 probe F7 against its control F6: `HStack(spacing: 0) {
/// Text(long).fixedSize(); b50×10 }` at 100×nil answers 302×16, the text 252×16
/// on one line; without `.fixedSize()` (F6) the text wraps to 45 wide and the
/// stack answers 95×112). The text's one-line answer is read from the kernel at
/// nil×nil rather than written as 252, so the arm does not depend on the face's
/// exact advance (closeout, `CX-A`).
///
/// Mutation: `FixedSize` forwards its proposal's width unchanged (the F7 arm
/// reads the wrapped answer).
@Test @MainActor func aFixedSizeTextKeepsItsOneLineWidthInANarrowStack() throws {
    let long = "alpha bravo charlie delta echo foxtrot golf"
    let line = try #require(kernelAnswers(ProposalText(long), at: [proposal(nil, nil)]).first)
    try #require(line.width > 100, "the line must be wider than the stack's proposal")
    let fixed = kernelAnswers(HStack(spacing: Pixels(0)) {
        ProposalText(long).fixedSize()
        Color(.accent).frame(width: Pixels(50), height: Pixels(10))
    }, at: [proposal(100, nil)])
    #expect(fixed == [size(line.width + 50, max(line.height, 10))], "F7: \(fixed), line \(line)")
    let wrapped = try #require(kernelAnswers(HStack(spacing: Pixels(0)) {
        ProposalText(long)
        Color(.accent).frame(width: Pixels(50), height: Pixels(10))
    }, at: [proposal(100, nil)]).first)
    #expect(wrapped.width <= 100 && wrapped.height > line.height, "F6 control: \(wrapped)")
}

/// **2.2 — a `Circle` draws centred in its frame** (probe S2: x 20…80 in
/// 100×60; the tall 40×90 at y 25…65). The geometry arms are the separating
/// ones — a circle's element rect is already its own square in a proposal
/// parent, so the rendered arm alone could not see where the geometry puts it.
///
/// Mutation: **M2b** the circle at the frame's origin.
@Test @MainActor func aCircleDrawsCentredInItsFrame() throws {
    let wide = Circle().geometry(in: shapeBounds(0, 0, 100, 60))
    #expect(wide.rect == shapeBounds(20, 0, 60, 60), "S2 wide: \(wide)")
    #expect(wide.cornerRadii == Corners(all: Pixels(30)))
    let tall = Circle().geometry(in: shapeBounds(0, 0, 40, 90))
    #expect(tall.rect == shapeBounds(0, 25, 40, 40), "S2 tall: \(tall)")
    #expect(tall.cornerRadii == Corners(all: Pixels(20)))

    let rendered = paintedShapes(100, 60, Circle())
    try #require(rendered.count == 1, "\(rendered)")
    #expect(rendered[0].rect == [20, 0, 60, 60] && rendered[0].radii == [30, 30, 30, 30],
            "\(rendered[0])")
}

/// **2.3 — a corner radius clamps to half the shorter side, a negative one is
/// 0, and a capsule's radius is half the shorter side** (probes S4:
/// RR(50) on 100×60 equals a capsule, 0 px; S5: RR(−5) equals a rectangle;
/// S6: a 40×90 capsule).
///
/// Mutation: **M2c** no clamp.
@Test @MainActor func aCornerRadiusClampsToHalfTheShorterSideAndANegativeOneIsZero() {
    let frame = shapeBounds(0, 0, 100, 60)
    #expect(RoundedRectangle(cornerRadius: Pixels(50)).geometry(in: frame).cornerRadii
                == Corners(all: Pixels(30)), "S4")
    #expect(RoundedRectangle(cornerRadius: Pixels(-5)).geometry(in: frame).cornerRadii
                == Corners(all: Pixels(0)), "S5")
    #expect(RoundedRectangle(cornerRadius: Pixels(12)).geometry(in: frame).cornerRadii
                == Corners(all: Pixels(12)), "an in-range radius is kept")
    #expect(Capsule().geometry(in: shapeBounds(0, 0, 40, 90)).cornerRadii == Corners(all: Pixels(20)),
            "S6")
    #expect(Capsule().geometry(in: frame).cornerRadii == Corners(all: Pixels(30)))
    // The clamp is in the geometry, so an outside shape's over-large radius
    // is clamped too.
    #expect(ShapeGeometry.roundedRectangle(frame, cornerRadii: Corners(all: Pixels(99))).cornerRadii
                == Corners(all: Pixels(30)))
}

/// **2.4 — an `Ellipse` emits the renderer's ellipse kind** over its whole
/// frame (probe S2's ellipse fills 100×60; `TE-AE`); a rounded rectangle emits
/// kind 0.
///
/// Mutation: **M2d** `Ellipse` as a rounded rectangle.
@Test @MainActor func anEllipseEmitsTheEllipseKind() throws {
    let ellipse = paintedShapes(100, 60, Ellipse())
    try #require(ellipse.count == 1, "\(ellipse)")
    #expect(ellipse[0].kind == PrimitiveShape.ellipse.rawValue && ellipse[0].rect == [0, 0, 100, 60],
            "\(ellipse[0])")
    let capsule = paintedShapes(100, 60, Capsule())
    try #require(capsule.count == 1)
    #expect(capsule[0].kind == PrimitiveShape.roundedRectangle.rawValue)
}

// MARK: - 2.5, 2.6 the fill

/// **2.5 — a bare shape fills with the foreground style** (probes F1: a bare
/// `Rectangle()` paints the text colour; F2: a container's
/// `.foregroundStyle(blue)` reaches a `Circle`; F5: `.foregroundColor`),
/// `.textPrimary` by default (part 1's resolution, `TE-D`). The fixed
/// `Rectangle(width:height:)` keeps its stored `.surface` (`TE-AQ` item 2).
///
/// **T-row note**: until this lane a bare `Rectangle()` painted `.surface`;
/// no retained test asserted that colour (the census, record §61 §4).
///
/// Mutation: **M2e** the default `.surface`.
@Test @MainActor func aBareShapeFillsWithTheForegroundStyle() throws {
    try #require(lightColour(.textPrimary) != lightColour(.surface)
                    && lightColour(.accent) != lightColour(.textPrimary),
                 "the three tokens must differ, or the arms cannot")
    // Wrapped in a `ZStack`: an environment scope is a group, not a root.
    func colour<G: ProposalElementGroup>(_ content: G) throws -> Hsla {
        let rects = paintedShapes(100, 60, ZStack { content })
        try #require(rects.count == 1, "\(rects)")
        return rects[0].background
    }
    #expect(try colour(Rectangle()) == lightColour(.textPrimary), "F1")
    #expect(try colour(Rectangle().foregroundStyle(.accent)) == lightColour(.accent))
    #expect(try colour(ZStack { Circle() }.foregroundStyle(.accent)) == lightColour(.accent), "F2")
    #expect(try colour(Circle()) == lightColour(.textPrimary))
    #expect(try colour(Rectangle().foregroundColor(.accent)) == lightColour(.accent), "F5")
    #expect(try colour(Circle().fill()) == lightColour(.textPrimary), "fill() is the foreground style")
    #expect(try colour(ZStack { Ellipse().fill() }.foregroundStyle(.accent)) == lightColour(.accent))
    #expect(try colour(Rectangle(width: Pixels(10), height: Pixels(10)).foregroundStyle(.accent))
                == lightColour(.surface), "the fixed form's stored default")
    #expect(Rectangle().color == nil && Rectangle(width: Pixels(1), height: Pixels(1)).color == .surface)
}

/// **2.6 — `.fill` wins over the foreground style** (probe F3).
///
/// Mutation: **M2f** the environment read first.
@Test @MainActor func aFillWinsOverTheForegroundStyle() throws {
    let rects = paintedShapes(100, 60, ZStack { ZStack { Circle().fill(.accent) }.foregroundStyle(.separator) })
    try #require(rects.count == 1, "\(rects)")
    try #require(lightColour(.accent) != lightColour(.separator))
    #expect(rects[0].background == lightColour(.accent), "F3: \(rects[0])")
}

// MARK: - 2.14 divergence 90

/// **2.14 — divergence 90's pin: `.continuous` is the default and is drawn
/// circular.** SwiftUI's default style is `.continuous` and differs from
/// `.circular` by 196 px at r 20 on 100×60 (probe S3); MetalUI keeps the
/// spelling and the default, and draws both alike — the renderer's rounded
/// rect is circular (`TE-AG` item 2).
///
/// Mutation: **M2n** the default `.circular`.
@Test @MainActor func theContinuousStyleIsTheDefaultAndIsDrawnCircular() {
    #expect(RoundedRectangle(cornerRadius: Pixels(20)).style == .continuous, "S3's default")
    #expect(Capsule().style == .continuous, "S3's capsule default")
    #expect(paintedShapes(100, 60, RoundedRectangle(cornerRadius: Pixels(20)))
                == paintedShapes(100, 60, RoundedRectangle(cornerRadius: Pixels(20), style: .circular)),
            "divergence 90: continuous drawn circular")
    #expect(paintedShapes(100, 60, Capsule()) == paintedShapes(100, 60, Capsule(style: .circular)))
}

// MARK: - 2.22, 2.23 backgrounds and overlays in a shape

/// **2.22 — a shape background or overlay takes the content's size**, through
/// the existing `.background { }`/`.overlay { }` of both vocabularies (probes
/// O1: a capsule behind an 80×40 content is 80×40; O3: a centred 60×60 circle
/// stroked 4 on a 100×60 content, its band 64×64 at (18, −2); O5: a shape
/// background changes no layout). The `.topLeading` arm is derived from S1
/// and the overlay's alignment: the circle's own 60×60 at the corner, its band
/// at (−2, −2) — the arm that sees a circle answering its proposal, where the
/// centred one cannot (its geometry centres itself either way).
///
/// Mutation: **M2v** `Circle` answers the proposal (the `.topLeading` band
/// moves to (18, −2)).
@Test @MainActor func aShapeBackgroundOrOverlayTakesTheContentsSize() throws {
    let proposalO1 = paintedShapes(80, 40, Rectangle(width: Pixels(80), height: Pixels(40))
        .background { Capsule().fill(.accent) })
    try #require(proposalO1.count == 2, "\(proposalO1)")
    #expect(proposalO1[0].rect == [0, 0, 80, 40] && proposalO1[0].radii == [20, 20, 20, 20]
                && proposalO1[0].background == lightColour(.accent), "O1 proposal: \(proposalO1[0])")

    let legacyO1 = paintedShapes(80, 40, Box().cssWidth(Pixels(80)).cssHeight(Pixels(40))
        .background { Capsule().fill(.accent) })
    try #require(legacyO1.count == 1, "the legacy box paints nothing of its own: \(legacyO1)")
    #expect(legacyO1[0].rect == [0, 0, 80, 40] && legacyO1[0].radii == [20, 20, 20, 20],
            "O1 legacy: \(legacyO1[0])")

    let centred = paintedShapes(100, 60, Rectangle(width: Pixels(100), height: Pixels(60))
        .overlay { Circle().stroke(.accent, lineWidth: Pixels(4)) })
    try #require(centred.count == 2, "\(centred)")
    #expect(centred[1].rect == [18, -2, 64, 64] && centred[1].radii == [32, 32, 32, 32]
                && centred[1].border == [4, 4, 4, 4], "O3: \(centred[1])")

    let corner = paintedShapes(100, 60, Rectangle(width: Pixels(100), height: Pixels(60))
        .overlay(alignment: .topLeading) { Circle().stroke(.accent, lineWidth: Pixels(4)) })
    try #require(corner.count == 2, "\(corner)")
    #expect(corner[1].rect == [-2, -2, 64, 64], "the circle's own square at the corner: \(corner[1])")

    let legacyO3 = paintedShapes(100, 60, Box().cssWidth(Pixels(100)).cssHeight(Pixels(60))
        .overlay { Circle().stroke(.accent, lineWidth: Pixels(4)) })
    try #require(legacyO3.count == 1, "\(legacyO3)")
    #expect(legacyO3[0].rect == [18, -2, 64, 64], "O3 legacy: \(legacyO3[0])")

    let fixed = size(60, 20)
    #expect(kernelAnswers(Rectangle(width: Pixels(60), height: Pixels(20))
                .background { Capsule().fill(.accent) }) == Array(repeating: fixed, count: 5), "O5")
}

/// **2.23 — `background(_:in:)` is the filled shape, and `background(in:)`
/// fills the `.background` token** (probe O2: `background(blue, in:
/// Capsule())` equals O1, 0 px; O6: `background(in:)`'s default style paints
/// — white over a red canvas — so MetalUI fills its canvas token, `TE-AQ`
/// item 5).
///
/// Mutation: **M2w** the default token `.surface`.
@Test @MainActor func backgroundInAShapeIsTheFilledShapeAndDefaultsToTheBackgroundToken() throws {
    let spelled = paintedShapes(80, 40, Rectangle(width: Pixels(80), height: Pixels(40))
        .background { Capsule().fill(.accent) })
    let shorthand = paintedShapes(80, 40, Rectangle(width: Pixels(80), height: Pixels(40))
        .background(.accent, in: Capsule()))
    try #require(spelled.count == 2)
    #expect(shorthand == spelled, "O2: \(shorthand) vs \(spelled)")

    try #require(lightColour(.background) != lightColour(.surface),
                 "the default token must differ from the fixed rectangle's, or the arm cannot")
    let defaulted = paintedShapes(80, 40, Rectangle(width: Pixels(80), height: Pixels(40))
        .background(in: RoundedRectangle(cornerRadius: Pixels(8))))
    try #require(defaulted.count == 2, "\(defaulted)")
    #expect(defaulted[0].background == lightColour(.background) && defaulted[0].radii == [8, 8, 8, 8],
            "O6: \(defaulted[0])")
}
