import Testing
import MetalUICore
import MetalUILayout
import MetalUIRender
@testable import MetalUI

// Plan task 11, part 2, lane 2: clipping to a shape (ruling `TE-AJ`,
// `TE-AQ` items 3, 4, 12; probe group C of
// `docs/probes/swiftui-shapes-and-rendering.swift`). Helpers in
// `ShapeTests.swift`.

/// C0's overflowing content: a 100×60 base with a 160×20 bar centred over it,
/// so the bar reaches x −30…130 — outside every clip these tests push.
@MainActor
private func overflowing() -> some ProposalElement {
    Rectangle(width: Pixels(100), height: Pixels(60)).overlay {
        Color(.accent).frame(width: Pixels(160), height: Pixels(20))
    }
}

/// **2.15 — `clipShape` clips to the shape's geometry** (probes C2:
/// `clipShape(Circle())` on 100×60 inks x 20…80; C7: a capsule clip is the
/// capsule). The circle's mask is its centred 60×60 square with radius 30,
/// the capsule's the whole bounds with radius 30, on every rect inside —
/// and the bar still overflows its frame (C0), so the mask is what cuts it.
///
/// Mutation: **M2o** clip to the bounds, not the geometry.
@Test @MainActor func clipShapeClipsToTheShapesGeometry() throws {
    let circle = paintedShapes(100, 60, overflowing().clipShape(Circle()))
    try #require(circle.count == 2, "\(circle)")
    #expect(circle[1].rect == [-30, 20, 160, 20], "C0: the bar overflows its frame")
    for rect in circle {
        #expect(rect.mask == [20, 0, 60, 60] && rect.maskRadii == [30, 30, 30, 30], "C2: \(rect)")
    }
    let capsule = paintedShapes(100, 60, overflowing().clipShape(Capsule()))
    try #require(capsule.count == 2, "\(capsule)")
    for rect in capsule {
        #expect(rect.mask == [0, 0, 100, 60] && rect.maskRadii == [30, 30, 30, 30], "C7: \(rect)")
    }
}

/// **2.15b — the proposal `clipShape`'s PREPAINT half: a hitbox inside is cut
/// to the geometry's bounding rect** (`TE-AQ` item 4's rule, as the legacy
/// path's 2.18; MetalUI's existing rule for every clip, not a SwiftUI claim).
/// A `ProposalScrollView` registers its viewport as a scroll-region hitbox —
/// the one proposal element that registers a hitbox of its own — and fills its
/// 100×60 proposal: the control registers (0, 0, 100, 60); under
/// `.clipShape(Circle())` the region is the circle's square (20, 0, 60, 60).
/// Paint (2.15) and prepaint are separate halves of the modifier (`OM-AI`),
/// so each needs its own test.
///
/// Mutation: **X7** the `.clipShape` case in `LayoutModifier._prepaint` returns
/// `inside()` unclipped.
@Test @MainActor func aProposalClipShapeCutsTheHitboxesInsideIt() throws {
    @MainActor func hitboxes<E: Element>(_ root: E) -> [[Float]] {
        var root = root
        let frame = Frame(contentSize: Size(width: Pixels(100), height: Pixels(60)), scaleFactor: 1)
        frame.render(&root)
        return frame.hitboxes.map {
            [$0.bounds.origin.x.value, $0.bounds.origin.y.value,
             $0.bounds.size.width.value, $0.bounds.size.height.value]
        }
    }
    @MainActor func scroller() -> some ProposalElement {
        ProposalScrollView(.vertical) { Rectangle(width: Pixels(100), height: Pixels(200)) }
    }
    let control = hitboxes(scroller())
    try #require(control == [[0, 0, 100, 60]], "the control: the viewport's whole region: \(control)")
    let clipped = hitboxes(scroller().clipShape(Circle()))
    #expect(clipped == [[20, 0, 60, 60]], "cut to the circle's bounding rect: \(clipped)")
}

/// **2.16 — `.clipped()` and `.cornerRadius` clip on the proposal path**
/// (probes C3: `.clipped()` cuts the bar at the frame, square; C1:
/// `.cornerRadius(12)` clips, the corner pixel empty; C4: `cornerRadius(20)`
/// equals `clipShape(RoundedRectangle(cornerRadius: 20))`, 0 px). A 200×200
/// frame puts the 100×60 root at (50, 70), so an absent clip (the whole
/// surface) cannot pass for the frame's. Each spelling returns the proposal
/// `ModifiedContent` (the overload a proposal receiver reaches).
///
/// Mutation: **M2p** the proposal `cornerRadius` not clipping.
@Test @MainActor func clippedAndCornerRadiusClipOnTheProposalPath() throws {
    let unclipped = paintedShapes(200, 200, overflowing())
    try #require(unclipped.count == 2 && unclipped[1].mask == [0, 0, 200, 200],
                 "the control: no clip, the whole surface: \(unclipped)")

    let clipped = overflowing().clipped()
    let spelled = String(describing: type(of: clipped))
    #expect(spelled.hasPrefix("ModifiedContent<") && spelled.hasSuffix(", LayoutModifier>"),
            "the proposal overload: \(spelled)")
    for rect in paintedShapes(200, 200, clipped) {
        #expect(rect.mask == [50, 70, 100, 60] && rect.maskRadii == [0, 0, 0, 0], "C3: \(rect)")
    }

    let rounded = paintedShapes(200, 200, overflowing().cornerRadius(Pixels(12)))
    try #require(rounded.count == 2, "\(rounded)")
    for rect in rounded {
        #expect(rect.mask == [50, 70, 100, 60] && rect.maskRadii == [12, 12, 12, 12], "C1: \(rect)")
    }
    #expect(rounded == paintedShapes(200, 200, overflowing().clipShape(RoundedRectangle(cornerRadius: Pixels(12)))),
            "C4")
}

/// **2.17 — `clipShape` changes no layout** (probe C8: a `clipShape(Circle())`
/// content answers 100×60 at every proposal). The same tree with and without
/// the clip registers the same number of layout nodes and places every rect
/// alike.
///
/// Mutation: **M2q** `clipShape` wraps a frame.
@Test @MainActor func clipShapeChangesNoLayout() throws {
    @MainActor func layout<C: ProposalElementGroup>(_ first: C) -> (nodes: Int, rects: [[Float]]) {
        var root = HStack { first; Rectangle(width: Pixels(30), height: Pixels(30)) }
        let frame = Frame(contentSize: Size(width: Pixels(200), height: Pixels(200)), scaleFactor: 1)
        frame.render(&root)
        return (frame.tree.nodeCount, frame.finalizedScene().rects.map(PaintedShape.init).map(\.rect))
    }
    let plain = layout(Rectangle(width: Pixels(40), height: Pixels(20)))
    let clipped = layout(Rectangle(width: Pixels(40), height: Pixels(20)).clipShape(Circle()))
    #expect(clipped.nodes == plain.nodes, "no node of its own: \(clipped.nodes) vs \(plain.nodes)")
    #expect(clipped.rects == plain.rects, "\(clipped.rects) vs \(plain.rects)")
    let fixed = SizeD(width: 100, height: 60)
    #expect(kernelAnswers(Rectangle(width: Pixels(100), height: Pixels(60)).clipShape(Circle()))
                == Array(repeating: fixed, count: 5), "C8")
}

/// **2.18 — a legacy `clipShape` clips its children and its hitboxes**
/// (`TE-AJ` item 2). A 40×40 `Box` over a 60×60 clickable child, the fixture
/// of `clippedAlsoClipsTheHitboxesInsideIt`: under `.clipShape(Capsule())` the
/// child's mask is the box with radius 20, and its hitbox is cut to the
/// clip's bounding rect — 40 tall, where the control (no clip) registers 60.
/// That the hitbox is square, not the capsule, is MetalUI's existing rule for
/// every clip (`TE-AQ` item 4), not a SwiftUI claim. The receiver is a `Box`,
/// not a `ProposalElementGroup`, so it reaches the `StyledElement` overload,
/// which returns `Self`.
///
/// Mutation: **M2r** the prepaint half omitted (only the hitbox arm reddens).
@Test @MainActor func aLegacyClipShapeClipsItsChildrenAndItsHitboxes() throws {
    // Both branches of the ternary have one type: the overload returns `Self`.
    @MainActor func box(clipped: Bool) -> some Element {
        let inner = Box {
            Box().cssWidth(Pixels(60)).cssHeight(Pixels(60)).flexShrink(0)
                .background(.surface).onClick {}
        }.cssWidth(Pixels(40)).cssHeight(Pixels(40))
        let chosen = clipped ? inner.clipShape(Capsule()) : inner
        return Row { chosen }.alignItems(.flexStart).cssWidth(Pixels(200)).cssHeight(Pixels(200))
    }
    @MainActor func render(clipped: Bool) -> (rects: [PaintedShape], hitHeights: [Float]) {
        var root = box(clipped: clipped)
        let frame = Frame(contentSize: Size(width: Pixels(200), height: Pixels(200)), scaleFactor: 1)
        frame.render(&root)
        return (frame.finalizedScene().rects.map(PaintedShape.init),
                frame.hitboxes.map(\.bounds.size.height.value))
    }
    let control = render(clipped: false)
    try #require(control.rects.count == 1 && control.hitHeights == [60],
                 "the control: the child paints and hits its whole 60: \(control)")
    let clipped = render(clipped: true)
    try #require(clipped.rects.count == 1, "\(clipped.rects)")
    #expect(clipped.rects[0].mask == [0, 0, 40, 40] && clipped.rects[0].maskRadii == [20, 20, 20, 20],
            "the child is cut to the capsule: \(clipped.rects[0])")
    #expect(clipped.hitHeights == [40], "the hitbox is cut to the clip's rect: \(clipped.hitHeights)")
}

/// **2.18b — a legacy `clipShape` wins over `.clipped()`** (`TE-AS` item 4):
/// with both set, the mask is the shape's region, in either spelling order —
/// the geometry of every built-in lies inside the box, so the shape alone is
/// the intersection. A 40×40 `Box`: `.clipped()` alone masks (0, 0, 40, 40)
/// radius 0 (the control); with `.clipShape(Circle())` too, radius 20.
///
/// Mutation: **X1** `Decoration.clipRegion(in:)` reads `clipsContent` first.
@Test @MainActor func aLegacyClipShapeWinsOverClipped() throws {
    @MainActor func child() -> some Element {
        Box().cssWidth(Pixels(60)).cssHeight(Pixels(60)).flexShrink(0).background(.surface)
    }
    @MainActor func maskRadii<E: Element>(_ box: E) throws -> [Float] {
        let rects = paintedShapes(200, 200, Row { box }.alignItems(.flexStart)
            .cssWidth(Pixels(200)).cssHeight(Pixels(200)))
        try #require(rects.count == 1 && rects[0].mask == [0, 0, 40, 40], "\(rects)")
        return rects[0].maskRadii
    }
    let square = try maskRadii(Box { child() }.cssWidth(Pixels(40)).cssHeight(Pixels(40)).clipped())
    try #require(square == [0, 0, 0, 0], "the control: clipped() alone is square: \(square)")
    let after = try maskRadii(Box { child() }.cssWidth(Pixels(40)).cssHeight(Pixels(40))
        .clipped().clipShape(Circle()))
    #expect(after == [20, 20, 20, 20], "clipShape written after clipped(): \(after)")
    let before = try maskRadii(Box { child() }.cssWidth(Pixels(40)).cssHeight(Pixels(40))
        .clipShape(Circle()).clipped())
    #expect(before == [20, 20, 20, 20], "clipShape written before clipped(): \(before)")
}

/// **2.18c — a legacy `clipShape`'s box compares by its concrete shape**
/// (`TE-AS` item 4: `ClipShapeBox`'s `==` opens the existential). Two
/// decorations differing only in the clip shape are unequal — a different
/// type, or the same type with a different value — and equal ones are equal.
///
/// Mutation: **X3** `ClipShapeBox.==` returns `true`.
@Test @MainActor func aLegacyClipShapeComparesByItsConcreteShape() {
    func decoration(_ shape: some Shape & Hashable) -> Decoration {
        var d = Decoration()
        d.clipShape = ClipShapeBox(shape)
        return d
    }
    #expect(decoration(Circle()) == decoration(Circle()))
    #expect(decoration(RoundedRectangle(cornerRadius: Pixels(4)))
                == decoration(RoundedRectangle(cornerRadius: Pixels(4))))
    #expect(decoration(Circle()) != decoration(Capsule()), "a different type")
    #expect(decoration(RoundedRectangle(cornerRadius: Pixels(4)))
                != decoration(RoundedRectangle(cornerRadius: Pixels(8))), "the same type, another value")
    #expect(decoration(Circle()) != Decoration(), "a clip against none")
}

/// **2.19 (exit) — `clipShape` of an ellipse traps naming divergence 91**
/// (`TE-AJ` item 4). SwiftUI clips to the ellipse (probe C5); every primitive's
/// mask here is a rounded rectangle, so the explicit form of "not supportable
/// yet" is a trap at the clip — a custom `Shape` can return an ellipse at run
/// time, so the check cannot be in the type. Both vocabularies.
///
/// Mutation: **M2s** the trap removed (both children exit 0).
@Test func clipShapeOfAnEllipseTrapsNamingDivergence91() async {
    let proposal = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        await MainActor.run {
            var root = Rectangle(width: Pixels(100), height: Pixels(60)).clipShape(Ellipse())
            Frame(contentSize: Size(width: Pixels(100), height: Pixels(60)), scaleFactor: 1).render(&root)
        }
    }
    let proposalStderr = String(decoding: proposal?.standardErrorContent ?? [], as: UTF8.self)
    #expect(proposalStderr.contains("divergence 91"), "proposal: \(proposalStderr)")

    let legacy = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        await MainActor.run {
            var root = Box {
                Box().cssWidth(Pixels(10)).cssHeight(Pixels(10)).background(.surface)
            }.cssWidth(Pixels(100)).cssHeight(Pixels(60)).clipShape(Ellipse())
            Frame(contentSize: Size(width: Pixels(100), height: Pixels(60)), scaleFactor: 1).render(&root)
        }
    }
    let legacyStderr = String(decoding: legacy?.standardErrorContent ?? [], as: UTF8.self)
    #expect(legacyStderr.contains("divergence 91"), "legacy: \(legacyStderr)")
}

/// **2.20 — a rounded clip contained in a rounded clip keeps its radii**
/// (`TE-AJ` item 5; probe C6: a capsule clip then a circle clip equals the
/// circle alone, 0 px). Rendered: a capsule (0, 0, 100, 60) r 30 around a
/// circle (20, 0, 60, 60) r 30 — the circle touches the capsule's top edge, so
/// neither existing case applies, and until this lane the answer was the
/// square box (radii 0) — now 30; and the mirror, the circle outside the
/// capsule, keeps the circle's. Unit arms on `Frame.intersect` for both
/// cases, and for case 2's unchanged answer.
///
/// Mutation: **M2t** the containment case removed.
@Test @MainActor func aRoundedClipContainedInARoundedClipKeepsItsRadii() throws {
    let nested = paintedShapes(100, 60, overflowing().clipShape(Circle()).clipShape(Capsule()))
    try #require(nested.count == 2, "\(nested)")
    for rect in nested {
        #expect(rect.mask == [20, 0, 60, 60] && rect.maskRadii == [30, 30, 30, 30], "C6: \(rect)")
    }
    let mirror = paintedShapes(100, 60, overflowing().clipShape(Capsule()).clipShape(Circle()))
    try #require(mirror.count == 2, "\(mirror)")
    for rect in mirror {
        #expect(rect.mask == [20, 0, 60, 60] && rect.maskRadii == [30, 30, 30, 30], "mirror: \(rect)")
    }

    let capsule = shapeBounds(0, 0, 100, 60), circle = shapeBounds(20, 0, 60, 60)
    let r30 = Corners(all: Pixels(30))
    let inner = Frame.intersect(capsule, radii: r30, circle, radii: r30)
    #expect(inner.bounds == circle && inner.radii == r30, "the inner case: \(inner)")
    let outer = Frame.intersect(circle, radii: r30, capsule, radii: Corners(all: Pixels(30)))
    #expect(outer.bounds == circle && outer.radii == r30, "the mirror case: \(outer)")
    // Case 2 unchanged: strictly inside the box, the inner radii, whatever
    // the outer's corner does (its documented inexactness, kept).
    let tucked = Frame.intersect(capsule, radii: r30, shapeBounds(1, 1, 10, 10),
                                 radii: Corners(all: Pixels(2)))
    #expect(tucked.radii == Corners(all: Pixels(2)), "case 2 keeps its answer: \(tucked)")
    // The container's radius is chosen by quadrant: a radius-5 inner rect in
    // the bottom-right corner of a 100×100 outer (touching its right and bottom
    // edges, so neither earlier case applies) lies inside when that corner is
    // square and outside when it is rounded by 40, whatever the other corners.
    func corners(_ tl: Float, _ tr: Float, _ br: Float, _ bl: Float) -> Corners<Pixels> {
        Corners(topLeft: Pixels(tl), topRight: Pixels(tr), bottomRight: Pixels(br), bottomLeft: Pixels(bl))
    }
    let box = shapeBounds(0, 0, 100, 100), corner = shapeBounds(60, 60, 40, 40)
    let r5 = Corners(all: Pixels(5))
    let squareThere = Frame.intersect(box, radii: corners(40, 0, 0, 0), corner, radii: r5)
    #expect(squareThere.radii == r5, "the bottom-right corner is square: contained: \(squareThere)")
    let roundedThere = Frame.intersect(box, radii: corners(0, 0, 40, 0), corner, radii: r5)
    #expect(roundedThere.radii == Corners(all: Pixels(0)),
            "the bottom-right corner is rounded: not contained, the square box: \(roundedThere)")
}

/// **2.21 — divergence 92's pin: two rounded clips that cross intersect as the
/// square box.** The true region needs a curve per overlapping corner; one
/// mask per primitive cannot carry it (`TE-AJ` item 5). Rounded rects
/// (0, 0, 100, 60) and (50, 0, 100, 60), radius 20: the box (50, 0, 50, 60),
/// radii 0, in either order.
///
/// Mutation: **M2u** return the inner radii unconditionally.
@Test @MainActor func twoCrossingRoundedClipsIntersectAsTheSquareBox() throws {
    let r20 = Corners(all: Pixels(20))
    let crossed = Frame.intersect(shapeBounds(0, 0, 100, 60), radii: r20, shapeBounds(50, 0, 100, 60),
                                  radii: r20)
    #expect(crossed.bounds == shapeBounds(50, 0, 50, 60) && crossed.radii == Corners(all: Pixels(0)),
            "divergence 92: \(crossed)")
    // The mirror order crosses the same way.
    let mirrored = Frame.intersect(shapeBounds(50, 0, 100, 60), radii: r20, shapeBounds(0, 0, 100, 60),
                                   radii: r20)
    #expect(mirrored.bounds == shapeBounds(50, 0, 50, 60) && mirrored.radii == Corners(all: Pixels(0)),
            "\(mirrored)")
}
