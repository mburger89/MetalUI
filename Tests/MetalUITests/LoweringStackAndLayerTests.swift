import Foundation
import Testing
import MetalUICore
import MetalUILayout
import MetalUIText
@testable import MetalUI

// Plan task 7, stage 1, lane 4 (`docs/superpowers/specs/2026-09-17-engine-replacement-design.md`
// §5.4 and §6 lane 4; rulings LR-G, LR-H, LR-Z): a `Stack` lowered onto a native
// overlay, and `ModifiedElement`'s layers — `.padding` through the container
// lowering, `.frame` onto one native frame read from the layer's animated `Style`
// plus its `FrameSpec` — under the proposal layout authority, compared with the
// legacy engine through the differential harness (`LayoutDifferential.swift`)
// until stage 9, which deleted the legacy engine: each test now asserts the one
// frame by literal (ruling `LR-FE` item 2; record §51, lane 1).
//
// **Red before**: on lane 3's tree a `Stack` reports `stack.noLowering` and every
// layer `modifierLayer.noLowering` (record §18, lane 4), and `.frame(idealWidth:)`
// traps at construction, so 4.6's proposal arm runs in a child process. The
// mutation each test must redden is named in its doc comment and in spec §6's
// lane-4 table; the record names what each actually reddened.
//
// Geometry is chosen so no centred offset falls on `x.5` (practices, fixture
// hazard): every free extent a centring divides is even.

private func px(_ v: Float) -> Pixels { Pixels(v) }

private func bounds(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> Bounds<Pixels> {
    Bounds(origin: Point(x: Pixels(x), y: Pixels(y)), size: Size(width: Pixels(w), height: Pixels(h)))
}

private let rootID = GlobalElementID.child(of: nil, at: 0, name: nil)
private let containerID = GlobalElementID.child(of: rootID, at: 0, name: nil)

private func child(_ parent: GlobalElementID, _ index: Int) -> GlobalElementID {
    GlobalElementID.child(of: parent, at: index, name: nil)
}

private func field(_ site: LoweringSite, _ name: String) -> UnlowerableField {
    UnlowerableField(site: site, field: name)
}

private let longString = "alpha bravo charlie delta echo foxtrot golf"

/// A fixed-size childless `Box` (lowered since lane 2).
@MainActor
private func fixed(_ w: Float, _ h: Float) -> Box<EmptyGroup> {
    Box().cssWidth(px(w)).cssHeight(px(h))
}

/// Two fixed boxes as ONE component, so a frame around it wraps two nodes.
private struct TwoBoxes: Component {
    var content: some ElementGroup {
        Box().cssWidth(Pixels(10)).cssHeight(Pixels(10))
        Box().cssWidth(Pixels(10)).cssHeight(Pixels(10))
    }
}

/// A component with no layout node, so a frame around it wraps zero nodes.
/// (`EmptyGroup().frame(…)` would resolve to the **proposal** frame — `EmptyGroup`
/// is a `ProposalElementGroup` — whose single-child precondition traps.)
private struct NoNodes: Component {
    var content: some ElementGroup { EmptyGroup() }
}

/// Nothing was reported. (Until stage 9 this was `expectFullAgreement`, which
/// also required every element, the scene, the hitboxes, the accessibility
/// records and the state slots to agree with the legacy engine's; that
/// comparison is the deleted concept, `LR-FE` item 2.)
@MainActor
private func expectNothingReported(_ r: LayoutDifferential.Report, _ arm: String,
                                   sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(r.unlowerable.isEmpty, "\(arm): \(r.unlowerable)", sourceLocation: sourceLocation)
}

private func lowered(_ r: LayoutDifferential.Report, _ ids: [GlobalElementID]) -> [Bounds<Pixels>?] {
    ids.map { r.bounds[$0] }
}

/// The proposal frame's diagnostics for `make()` inside a 100×100 harness root.
@MainActor
private func report<C: ElementGroup>(@ElementBuilder _ make: @MainActor () -> C) -> [UnlowerableField] {
    LayoutDifferential.render(width: 100, height: 100, make).unlowerableFields
}

// MARK: - 4.1, 4.2 — Stack

/// `Stack`'s nine alignments with their horizontal and vertical factors.
private let stackAlignments: [(Alignment, Float, Float)] = [
    (.topLeading, 0, 0), (.top, 0.5, 0), (.topTrailing, 1, 0),
    (.leading, 0, 0.5), (.center, 0.5, 0.5), (.trailing, 1, 0.5),
    (.bottomLeading, 0, 1), (.bottom, 0.5, 1), (.bottomTrailing, 1, 1),
]

/// **4.1.** A lowered `Stack` places fixed children at all nine alignments (ruling
/// LR-G: for fixed children the legacy stack's fit-content offer and the proposal
/// agreed, which the comparison held until stage 9). Children a 20×10 and b 10×30; horizontal factor h, vertical v:
///
/// - **unsized**: the stack is the union, 20×30; a at (0, 20v), b at (10h, 0);
/// - **sized 100×60 with `Style.padding`** top 4, right 6, bottom 8, left 10 (the
///   content box 84×48 at (10, 4)): a at (10 + 64h, 4 + 38v), b at (10 + 74h, 4 + 18v).
///
/// Further arms:
/// - **container fields a stack does not read** — `flexDirection(.column)`, a gap,
///   `justifyContent(.spaceBetween)` on a sized `.bottomTrailing` stack — report
///   nothing and place a at (80, 50), b at (90, 30) (`flexWrap` and `alignContent`
///   left the arm at stage 10 with their modifiers, `LR-FM` item 1);
/// - **reported** (the report is exactly this): a `Stack` with
///   `.alignItems(.baseline)` → `[alignItems.baseline]`; with `.margin(2)` →
///   `[margin.unconsumed]` (an item field its parent reads since stage 2, and the
///   harness root is a proposal overlay, ruling LR-AQ); hidden with a stretch →
///   `[display.none]` alone. **Stage 2, lane 1 moved the two stretch arms** — a
///   `Box` declaring `display: .stack` with `nil` alignments, and a `Stack` with
///   `.alignItems(.stretch)` — to `aStackStretchesByItsItemsAlignmentAndIgnoresTheirFlexFields`
///   (`LoweringItemTests.swift`), where they lower and agree.
///
/// Mutation that must redden it: **M4a**, the overlay's horizontal and vertical
/// factors swapped.
///
/// **Renamed at stage 9** from
/// `aLoweredStackPlacesFixedChildrenAtAllNineAlignmentsAsTheLegacyStackDoes`
/// (`LR-FE` item 6).
@MainActor
@Test func aLoweredStackPlacesFixedChildrenAtAllNineAlignments() throws {
    let a = child(containerID, 0), b = child(containerID, 1)
    var arms = 0
    for (alignment, h, v) in stackAlignments {
        let unsized = LayoutDifferential.report(width: 200, height: 200) {
            Stack(alignment: alignment) { fixed(20, 10); fixed(10, 30) }
        }
        try #require(unsized.elements == 4, "unsized \(alignment): \(unsized.elements)")
        expectNothingReported(unsized, "unsized \(alignment)")
        #expect(lowered(unsized, [containerID, a, b])
                == [bounds(0, 0, 20, 30), bounds(0, 20 * v, 20, 10), bounds(10 * h, 0, 10, 30)],
                "unsized \(alignment)")

        var stack = Stack(alignment: alignment) { fixed(20, 10); fixed(10, 30) }.cssWidth(px(100)).cssHeight(px(60))
        stack.style.padding = Edges(top: .pixels(px(4)), right: .pixels(px(6)),
                                    bottom: .pixels(px(8)), left: .pixels(px(10)))
        let padded = stack
        let sized = LayoutDifferential.report(width: 200, height: 200) { padded.background(.accent) }
        try #require(sized.elements == 4, "sized \(alignment): \(sized.elements)")
        expectNothingReported(sized, "sized \(alignment)")
        #expect(lowered(sized, [containerID, a, b])
                == [bounds(0, 0, 100, 60), bounds(10 + 64 * h, 4 + 38 * v, 20, 10),
                    bounds(10 + 74 * h, 4 + 18 * v, 10, 30)],
                "sized \(alignment)")
        arms += 2
    }
    try #require(arms == 18)

    var ignoring = Stack(alignment: .bottomTrailing) { fixed(20, 10); fixed(10, 30) }
        .cssWidth(px(100)).cssHeight(px(60))
        .gap(horizontal: px(7), vertical: px(9)).justifyContent(.spaceBetween)
    ignoring.style.flexDirection = .column
    let ignored = ignoring
    let ignoredReport = LayoutDifferential.report(width: 200, height: 200) { ignored }
    try #require(ignoredReport.elements == 4)
    expectNothingReported(ignoredReport, "container fields a stack does not read")
    #expect(lowered(ignoredReport, [a, b]) == [bounds(80, 50, 20, 10), bounds(90, 30, 10, 30)])

    let reported: [(String, [UnlowerableField], [UnlowerableField])] = [
        ("Stack alignItems baseline", report { Stack { fixed(20, 10); fixed(10, 30) }.alignItems(.baseline) },
         [field(.stack, "alignItems.baseline")]),
        ("Stack margin", report { Stack { fixed(20, 10); fixed(10, 30) }.margin(px(2)) },
         [field(.stack, "margin.unconsumed")]),
        ("hidden stretching Stack (lowered as if shown since stage 6b, LR-DH)",
         report { Stack { fixed(20, 10); fixed(10, 30) }.alignItems(.stretch).hidden() },
         []),
    ]
    try #require(reported.count == 3)
    for (name, entries, expected) in reported {
        #expect(entries == expected, "\(name): \(entries)")
    }
}

/// **4.2.** A lowered `Stack` **offers its proposal** (ruling LR-G, divergence 53;
/// stack-algorithms probe A5: a greedy child of a `ZStack` at 100×80 fills 100×80).
/// `Column { Stack { Text(long) } }` sized 60 wide in the harness root: the
/// column's frame proposes 60, the overlay proposes 60 to the text, which answers
/// the shaper's widest line wrapped at 60 (`LR-F`), computed here from a fresh
/// `ShapingCache`, and that wrap's total height.
///
/// Until stage 9 the legacy stack offered fit-content (the text **60** wide) and
/// the disagreement was a `try #require`; the separating arm is now the `try
/// #require` that the widest line is narrower than 60. The report is empty.
///
/// Mutation that must redden it: **M4b**, each lowered stack child wrapped in a
/// native `fixedSize` (the text is measured unwrapped, one long line).
///
/// **Renamed at stage 9** from
/// `aLoweredStackOffersItsProposalWhereTheLegacyStackOffersFitContent` (`LR-FE`
/// item 6): the collapsed test no longer asserts the legacy half.
@MainActor
@Test func aLoweredStackOffersItsChildItsProposal() throws {
    let r = LayoutDifferential.report(width: 200, height: 300) {
        Column { Stack { Text(longString) } }.cssWidth(px(60))
    }
    // root, column, stack, text
    try #require(r.elements == 4)
    #expect(r.unlowerable.isEmpty, "\(r.unlowerable)")
    let text = child(child(containerID, 0), 0)
    let loweredText = try #require(r.bounds[text])
    let cache = ShapingCache()
    let shaped = cache.shaped(longString, font: cache.resolveFont(family: nil, size: 13),
                              wrappingAt: 60)
    try #require(Float(shaped.widestLine.rounded()) < 60, "the widest line must be narrower than 60: \(shaped.widestLine)")
    #expect(loweredText.size.width == Pixels(Float(shaped.widestLine.rounded())))
    #expect(loweredText.size.height == Pixels(Float(shaped.totalHeight.rounded())))
}

// MARK: - 4.3–4.5 — padding and frame layers

/// **4.3.** A lowered `.padding` layer insets its content by each edge (a padding
/// layer is a one-child container: `LR-E`'s single-child stretch with no declared
/// cross size, so nothing is reported).
///
/// - `fixed(20, 10).padding(4).padding(8)` with a background on each: outermost
///   layer (0, 0) 44×34, inner layer (8, 8) 28×18, the box (12, 12);
/// - asymmetric edges top 2, right 4, bottom 6, left 8 over the box: layer 32×18,
///   the box at (8, 2);
/// - `Text("Count 3").padding(4)` and the same asymmetric edges over it, with a
///   background: the text at (4, 4) and (8, 2), drawing its six glyphs (compared
///   with the legacy wrapper's until stage 9, a literal since).
///
/// Mutation that must redden it: **M4c**, the lowered padding's top and bottom
/// insets swapped (the asymmetric arms' content moves to y 6).
///
/// **Renamed at stage 9** from `aLoweredPaddingLayerAgreesWithTheLegacyWrapper`
/// (`LR-FE` item 6).
@MainActor
@Test func aLoweredPaddingLayerInsetsItsContentByEachEdge() throws {
    let inner = child(containerID, 0)
    let chain = LayoutDifferential.report(width: 200, height: 200) {
        fixed(20, 10).background(.accent).padding(px(4)).background(.surface)
            .padding(px(8)).background(.surfaceSecondary)
    }
    try #require(chain.elements == 4)
    expectNothingReported(chain, "padding(4).padding(8)")
    #expect(lowered(chain, [containerID, inner, child(inner, 0)])
            == [bounds(0, 0, 44, 34), bounds(8, 8, 28, 18), bounds(12, 12, 20, 10)])

    let edges = Edges<Length>(top: .pixels(px(2)), right: .pixels(px(4)),
                              bottom: .pixels(px(6)), left: .pixels(px(8)))
    let asymmetric = LayoutDifferential.report(width: 200, height: 200) {
        fixed(20, 10).padding(edges).background(.accent)
    }
    try #require(asymmetric.elements == 3)
    expectNothingReported(asymmetric, "asymmetric box")
    #expect(lowered(asymmetric, [containerID, child(containerID, 0)])
            == [bounds(0, 0, 32, 18), bounds(8, 2, 20, 10)])

    var arms = 0
    for (name, element, origin) in [("text padding(4)", Text("Count 3").padding(px(4)), (Float(4), Float(4))),
                                     ("text asymmetric", Text("Count 3").padding(edges), (Float(8), Float(2)))] {
        let decorated = element.background(.accent)
        let r = LayoutDifferential.report(width: 200, height: 200) { decorated }
        try #require(r.elements == 3, "\(name)")
        expectNothingReported(r, name)
        #expect(r.frame.scene.glyphs.count == 6, "\(name)")
        #expect(r.bounds[child(containerID, 0)]?.origin
                == Point(x: px(origin.0), y: px(origin.1)), "\(name)")
        arms += 1
    }
    try #require(arms == 2)
}

private let frameAlignments: [(ProposalAlignment, Float, Float)] = [
    (.topLeading, 0, 0), (.top, 0.5, 0), (.topTrailing, 1, 0),
    (.leading, 0, 0.5), (.center, 0.5, 0.5), (.trailing, 1, 0.5),
    (.bottomLeading, 0, 1), (.bottom, 0.5, 1), (.bottomTrailing, 1, 1),
]

/// **4.4.** A lowered fixed `.frame(width: 60, height: 40, alignment:)` places its
/// child as the legacy frame layer did (a one-cell stack over one node, ruling
/// `CN-N`; compared until stage 9) at all nine alignments, over a child smaller than the frame (20×10: at (40h, 30v)) and
/// one larger (80×60: at (−20h, −20v), overflowing, probe arms A5/B9). A frame over
/// **no** node (`NoNodes().frame(width: 40, height: 40)`, a component with no
/// node) is 40×40.
///
/// Mutation that must redden it: **M4d**, the lowered frame's alignment forced
/// `.center`.
///
/// **Renamed at stage 9** from
/// `aLoweredFixedFrameLayerAgreesWithTheLegacyFrameOverAFixedChild` (`LR-FE` item 6).
@MainActor
@Test func aLoweredFixedFrameLayerPlacesAFixedChildAtEachAlignment() throws {
    let content = child(containerID, 0)
    var arms = 0
    for (alignment, h, v) in frameAlignments {
        for (w, hgt, at) in [(Float(20), Float(10), (40 * h, 30 * v)), (Float(80), Float(60), (-20 * h, -20 * v))] {
            let r = LayoutDifferential.report(width: 200, height: 200) {
                fixed(w, hgt).frame(width: px(60), height: px(40), alignment: alignment).background(.accent)
            }
            try #require(r.elements == 3, "\(alignment) \(w)")
            expectNothingReported(r, "\(alignment) \(w)×\(hgt)")
            #expect(lowered(r, [containerID, content])
                    == [bounds(0, 0, 60, 40), bounds(at.0, at.1, w, hgt)], "\(alignment) \(w)×\(hgt)")
            arms += 1
        }
    }
    try #require(arms == 18)

    let empty = LayoutDifferential.report(width: 200, height: 200) {
        NoNodes().frame(width: px(40), height: px(40)).background(.accent)
    }
    try #require(empty.elements == 2)
    expectNothingReported(empty, "frame over no node")
    #expect(lowered(empty, [containerID]) == [bounds(0, 0, 40, 40)])
}

/// **4.5.** A lowered **flexible** frame takes SwiftUI's answer (ruling LR-H;
/// `FR-E`, divergence 35; `FR-O`). Each inside a 100-wide `Column` (centred) in the
/// harness root, over a 20×20 box:
///
/// - `.frame(minWidth: 40, maxWidth: 80)`: **80** at x 10 (frame probe D control:
///   80×20 at a 100 proposal). The box is at x 40;
/// - `.frame(maxWidth: .infinity)` alone: **100** at x 0. The box at x 40.
///
/// The reports are empty. Until stage 9 the legacy frame's clamp — 40 at x 30, and
/// 20 at x 40 (a single infinite maximum is inert, `FR-O`) — was asserted beside
/// these, each disagreement a `try #require`.
///
/// Mutation that must redden it: **M4e**, the flexible frame lowered as a CSS clamp
/// (a `fixedSize` child clamped to min/max: the lowered frame reads 40 and 20).
///
/// **Renamed at stage 9** from
/// `aLoweredFlexibleFrameLayerTakesSwiftUIsAnswerWhereTheLegacyFrameClamps`
/// (`LR-FE` item 6).
@MainActor
@Test func aLoweredFlexibleFrameLayerTakesSwiftUIsAnswer() throws {
    let frameID = child(containerID, 0)
    let box = child(frameID, 0)

    let bounded = LayoutDifferential.report(width: 200, height: 200) {
        Column { fixed(20, 20).frame(minWidth: px(40), maxWidth: px(80)) }.cssWidth(px(100))
    }
    try #require(bounded.elements == 4)
    #expect(bounded.unlowerable.isEmpty, "\(bounded.unlowerable)")
    #expect(bounded.bounds[frameID] == bounds(10, 0, 80, 20))
    #expect(bounded.bounds[box] == bounds(40, 0, 20, 20))

    let infinite = LayoutDifferential.report(width: 200, height: 200) {
        Column { fixed(20, 20).frame(maxWidth: px(.infinity)) }.cssWidth(px(100))
    }
    try #require(infinite.elements == 4)
    #expect(infinite.unlowerable.isEmpty, "\(infinite.unlowerable)")
    #expect(infinite.bounds[frameID] == bounds(0, 0, 100, 20))
    #expect(infinite.bounds[box] == bounds(40, 0, 20, 20))
}

// MARK: - 4.6, 4.7 — ideal, animation

/// A custom layout that proposes nil×nil to its one subview, answers that
/// subview's answer, and places it at its own origin at nil×nil.
private struct NilProposal: ProposalLayout {
    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
        subviews[0].sizeThatFits(.unspecified)
    }

    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize, subviews: PlacementSubviews) {
        subviews[0].place(at: Point(x: bounds.x, y: bounds.y), proposal: .unspecified)
    }
}

/// A root that measures and places its content at a **nil×nil** proposal (a
/// native `NilProposal` layout).
@MainActor
private struct NilProposalRoot<Content: ElementGroup>: Element {
    var content: Content

    init(@ElementBuilder content: () -> Content) { self.content = content() }

    struct Layout { var content: Content.GroupLayout }

    mutating func requestLayout(_ id: GlobalElementID,
                                pass: inout LayoutPass) -> (LayoutNodeID, Layout) {
        var cursor = 0
        let (children, contentLayout) = content.requestGroupLayout(under: id, at: &cursor, pass: &pass)
        let node = pass.frame.requestNativeLayout(NilProposal(), children: children)
        return (node, Layout(content: contentLayout))
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                           layout: inout Layout, pass: inout PrepaintPass) -> Content.GroupPrepaint {
        content.prepaintGroup(layout: &layout.content, pass: &pass)
    }

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                        layout: inout Layout, prepaint: inout Content.GroupPrepaint,
                        pass: inout PaintPass) {
        content.paintGroup(layout: &layout.content, prepaint: &prepaint, pass: &pass)
    }
}

/// `make()` under a `NilProposalRoot`, with diagnostics and the bounds log on.
@MainActor
private func renderAtNilProposal<C: ElementGroup>(@ElementBuilder _ make: () -> C) -> Frame {
    var root = NilProposalRoot(content: make)
    let frame = Frame(contentSize: Size(width: Pixels(200), height: Pixels(200)), scaleFactor: 1,
                      reportsUnlowerableFields: true,
                      recordsElementBounds: true)
    frame.render(&root)
    return frame
}

/// **4.6.** An ideal frame **lowers** (ruling LR-H). Until stage 9 it also still
/// trapped when laid out by the legacy engine (`FR-D`'s trap moved from
/// construction to legacy registration, `LR-H`); those two exit-test arms went
/// with the legacy engine, and the test was **renamed** from
/// `anIdealFrameLowersUnderTheProposalAuthorityAndStillTrapsUnderTheLegacyOne`
/// (`LR-FE` item 6).
///
/// - in a child process (on lane 3's tree construction traps, which
///   in-process would end the run): measured at a **nil** proposal (`NilProposal`,
///   a custom layout — nothing the stage-1 lowering registers proposes nil: a
///   lowered `Row` proposes its own finite proposal, where the frame answers its
///   child, frame probe C control), `.frame(idealWidth: 80)` over a 20×20 box
///   answers **80×20** (frame probe C1: `frame(idealWidth: 80)` at a nil proposal
///   is 80×20), and `.frame(idealHeight: 80)` answers 20×80. A native root is
///   stored centred in the 200×200 window at its own answer (`CN-J`), so the frames
///   read (60, 90) 80×20 and (90, 60) 20×80, each with the box centred at (90, 90).
///   The child prints both frame rects and both reports.
///
/// Mutation that must redden it: **M4f**, the ideal dropped from the lowering (the
/// frames read 20×20).
@Test func anIdealFrameLowersAtANilProposal() async throws {
    let proposal = await #expect(processExitsWith: .success,
                                 observing: [\.standardOutputContent, \.standardErrorContent]) {
        await MainActor.run {
            let frameID = containerID
            let wide = renderAtNilProposal { fixed(20, 20).frame(idealWidth: px(80)) }
            let tall = renderAtNilProposal { fixed(20, 20).frame(idealHeight: px(80)) }
            let line = "IDEAL width \(String(describing: wide.elementBounds[frameID])) "
                + "box \(String(describing: wide.elementBounds[child(frameID, 0)])) "
                + "report \(wide.unlowerableFields) | "
                + "height \(String(describing: tall.elementBounds[frameID])) "
                + "box \(String(describing: tall.elementBounds[child(frameID, 0)])) "
                + "report \(tall.unlowerableFields)\n"
            FileHandle.standardOutput.write(Data(line.utf8))
        }
    }
    let out = String(decoding: proposal?.standardOutputContent ?? [], as: UTF8.self)
    let err = String(decoding: proposal?.standardErrorContent ?? [], as: UTF8.self)
    let expected = "IDEAL width \(String(describing: Optional(bounds(60, 90, 80, 20)))) "
        + "box \(String(describing: Optional(bounds(90, 90, 20, 20)))) report [] | "
        + "height \(String(describing: Optional(bounds(90, 60, 20, 80)))) "
        + "box \(String(describing: Optional(bounds(90, 90, 20, 20)))) report []\n"
    #expect(out.contains(expected), "stdout \(out)\nexpected \(expected)\nstderr \(err)")
}

/// **4.7.** A frame layer lowers from its **animated** `Style` for what `Style`
/// carries, and the check reads its **declared** style, so an animation never trips
/// it (ruling LR-H). `fixed(10, 10).frame(width: 40)` animating to `.frame(width:
/// 80)` under `withAnimation(.linear(duration: 1))`, derived by hand (and held
/// under both authorities until stage 9): the frame that starts the transaction reads the frame 40×10 with the
/// box at x 15; half-way, 60×10 with the box at x 25; the report is empty on every
/// frame.
///
/// Mutations that must redden it: **M4g**, the frame lowered from `FrameSpec` alone
/// (the lowered frame reads 80 on the start and half-way frames); **M4g′**, the
/// check compares the **animated** style (the half-way frame reports
/// `modifierLayer.style`).
@MainActor
@Test func aFrameLayerLowersFromItsAnimatedStyleForWhatStyleCarries() throws {
    let box = child(containerID, 0)
    let table = StateTable()
    func rects(width: Float, timestamp: Double, animating: Bool) -> [Bounds<Pixels>?] {
        let element = fixed(10, 10).frame(width: px(width))
        var root = DifferentialRoot(width: 200, height: 100) { element }
        let frame = Frame(contentSize: Size(width: Pixels(200), height: Pixels(100)), scaleFactor: 1,
                          stateTable: table, timestamp: timestamp,
                          transaction: animating ? .linear(duration: 1) : nil,
                          reportsUnlowerableFields: true,
                          recordsElementBounds: true)
        frame.render(&root)
        #expect(frame.unlowerableFields.isEmpty, "t \(timestamp): \(frame.unlowerableFields)")
        return [containerID, box].map { frame.elementBounds[$0] }
    }
    #expect(rects(width: 40, timestamp: 0, animating: false)
            == [bounds(0, 0, 40, 10), bounds(15, 0, 10, 10)], "baseline")
    #expect(rects(width: 80, timestamp: 0, animating: true)
            == [bounds(0, 0, 40, 10), bounds(15, 0, 10, 10)], "transaction start")
    #expect(rects(width: 80, timestamp: 0.5, animating: false)
            == [bounds(0, 0, 60, 10), bounds(25, 0, 10, 10)], "half-way")
}

// MARK: - 4.8, 4.9 — what a frame layer reports

/// **4.8.** A `Self`-returning sizing or item modifier written after `.frame` lands
/// on the frame layer, makes its declared style differ from `lowered(frameSpec
/// .style(), childCount:)`, and is reported `modifierLayer.style` (ruling LR-H):
/// `.frame(width: 40).width(60)`, `.frame(width: 40).minWidth(10)`,
/// `.frame(maxWidth: 80).flexGrow(1)`, and on an **inner** layer
/// `.frame(width: 40).alignItems(.flexEnd).padding(4)`. Control:
/// `.frame(width: 40).background(.accent)` reports nothing and lays out 40×10 with
/// the box at x 15 (a `Decoration` is not `Style`).
///
/// Mutation that must redden it: **M4h**, the comparison made against
/// `frameSpec.style()` without `lowered(_:childCount:)` (the control, a one-node
/// frame whose declared style is `display: .stack`, reports).
@MainActor
@Test func aSizingModifierWrittenAfterAFrameIsReportedOnTheFrameLayer() throws {
    let style = field(.modifierLayer, "style")
    let arms: [(String, [UnlowerableField], [UnlowerableField])] = [
        ("width after frame", report { fixed(10, 10).frame(width: px(40)).cssWidth(px(60)) }, [style]),
        ("minWidth after frame", report { fixed(10, 10).frame(width: px(40)).cssMinWidth(px(10)) }, [style]),
        ("flexGrow after flexible frame", report { fixed(10, 10).frame(maxWidth: px(80)).flexGrow(1) }, [style]),
        ("alignItems after frame, inner layer",
         report { fixed(10, 10).frame(width: px(40)).alignItems(.flexEnd).padding(px(4)) }, [style]),
    ]
    try #require(arms.count == 4)
    for (name, entries, expected) in arms {
        #expect(entries == expected, "\(name): \(entries)")
    }

    let control = LayoutDifferential.report(width: 200, height: 200) {
        fixed(10, 10).frame(width: px(40)).background(.accent)
    }
    try #require(control.elements == 3)
    expectNothingReported(control, "background after frame")
    #expect(lowered(control, [containerID, child(containerID, 0)])
            == [bounds(0, 0, 40, 10), bounds(15, 0, 10, 10)])
}

/// **4.9, rewritten by stage 6b's lane 1** (`LR-DH`; it was
/// `aHiddenFrameLayerIsReportedAsDisplayNone`). `hidden()` after a frame sets
/// `display: none` on the frame layer, which `ModifierLayer.lowered` keeps; under the
/// proposal authority the layer now **lowers as if shown**: its display is read as
/// the one an unhidden frame layer registers (`display: .stack` over one node, a flex
/// row over two) before the style comparison, so a hidden frame layer reports
/// nothing — over one node, over two (a two-member component), and on an inner layer
/// — and is laid out exactly where the shown one is. The comparison still runs:
/// **a sizing modifier written after it is still reported `modifierLayer.style`**,
/// which is what tells "the display is normalized, then compared" from "a hidden
/// layer skips its checks". Until the lane each hidden arm reported `display.none`
/// alone (ruling LR-J).
///
/// Mutation that must redden it: the display left un-normalized in
/// `legacyFrameLayerDiagnostics` (every hidden one-node arm reads
/// `modifierLayer.style`: `display: .none` ≠ the `.stack` a shown one-node frame
/// registers).
@MainActor
@Test func aHiddenFrameLayerLowersAsIfShown() throws {
    let style = field(.modifierLayer, "style")
    let arms: [(String, [UnlowerableField], [UnlowerableField])] = [
        ("one node", report { fixed(10, 10).frame(width: px(40)).hidden() }, []),
        ("two nodes", report { TwoBoxes().frame(width: px(40)).hidden() }, []),
        ("with a width after it", report { fixed(10, 10).frame(width: px(40)).hidden().cssWidth(px(60)) }, [style]),
        ("inner layer", report { fixed(10, 10).frame(width: px(40)).hidden().padding(px(4)) }, []),
        ("two nodes, not hidden", report { TwoBoxes().frame(width: px(40)) }, []),
    ]
    try #require(arms.count == 5)
    for (name, entries, expected) in arms {
        #expect(entries == expected, "\(name): \(entries)")
    }
    let shown = LayoutDifferential.report(width: 200, height: 200) { fixed(10, 10).frame(width: px(40)) }
    let hidden = LayoutDifferential.report(width: 200, height: 200) { fixed(10, 10).frame(width: px(40)).hidden() }
    try #require(hidden.unlowerable.isEmpty, "\(hidden.unlowerable)")
    let ids = [containerID, child(containerID, 0)]
    try #require(lowered(shown, ids) == [bounds(0, 0, 40, 10), bounds(15, 0, 10, 10)])
    #expect(lowered(hidden, ids) == lowered(shown, ids), "a hidden frame layer is laid out where the shown one is")
}

// MARK: - 4.10–4.12 — verifier round (animated Stack and frame bounds, frame over no node)

/// Renders `make(end)` animating from `make(start)` under
/// `withAnimation(.linear(duration: 1))` on one `StateTable` in a 200×100 harness
/// root, and returns `ids`' bounds on the frame before the
/// transaction, the frame that starts it (t = 0) and half-way (t = 0.5). Every
/// frame's report must be empty.
@MainActor
private func animatedRects<E: ElementGroup>(_ ids: [GlobalElementID],
                                            start: E, end: E,
                                            sourceLocation: SourceLocation = #_sourceLocation)
    -> [[Bounds<Pixels>?]] {
    let table = StateTable()
    func rects(_ element: E, timestamp: Double, animating: Bool) -> [Bounds<Pixels>?] {
        var root = DifferentialRoot(width: 200, height: 100) { element }
        let frame = Frame(contentSize: Size(width: Pixels(200), height: Pixels(100)), scaleFactor: 1,
                          stateTable: table, timestamp: timestamp,
                          transaction: animating ? .linear(duration: 1) : nil,
                          reportsUnlowerableFields: true,
                          recordsElementBounds: true)
        frame.render(&root)
        #expect(frame.unlowerableFields.isEmpty, "t \(timestamp): \(frame.unlowerableFields)",
                sourceLocation: sourceLocation)
        return ids.map { frame.elementBounds[$0] }
    }
    return [rects(start, timestamp: 0, animating: false),
            rects(end, timestamp: 0, animating: true),
            rects(end, timestamp: 0.5, animating: false)]
}

/// **4.10.** A lowered `Stack` lays out its **animated** size and padding, not its
/// declared ones (the `Stack` branch of `lowerLegacyNode` has its own
/// `paddedAndSized` call; 3.8 pins only the linear-stack branch's). A
/// `.topLeading` `Stack` over one 10×10 box, height 20, animates width 40 → 120 and
/// `Style.padding` 0 → 8 under `withAnimation(.linear(duration: 1))`. Derived by
/// hand (and held under both authorities until stage 9; padding inside the declared
/// size, `LR-E`):
///
/// - before and at the transaction's start: stack (0, 0) 40×20, box (0, 0);
/// - half-way: width 80, padding 4 — stack (0, 0) 80×20, box (4, 4).
///
/// Mutation that must redden it: **V4**, the `Stack` branch sizes and pads from
/// `declared` (the lowered stack reads 120 wide with the box at (8, 8) on every
/// animated frame).
@MainActor
@Test func aLoweredStackLaysOutItsAnimatedWidthAndPadding() throws {
    func stack(width: Float, padding: Float) -> Stack<Box<EmptyGroup>> {
        var s = Stack(alignment: .topLeading) { fixed(10, 10) }.cssWidth(px(width)).cssHeight(px(20))
        s.style.padding = Edges(all: .pixels(px(padding)))
        return s
    }
    let box = child(containerID, 0)
    let r = animatedRects([containerID, box],
                          start: stack(width: 40, padding: 0), end: stack(width: 120, padding: 8))
    try #require(r.count == 3)
    #expect(r[0] == [bounds(0, 0, 40, 20), bounds(0, 0, 10, 10)], "baseline")
    #expect(r[1] == [bounds(0, 0, 40, 20), bounds(0, 0, 10, 10)], "transaction start")
    #expect(r[2] == [bounds(0, 0, 80, 20), bounds(4, 4, 10, 10)], "half-way")
}

/// **4.11.** A frame layer's **minima and finite maxima** lower from its animated
/// `Style` (`minSize`, `maxSize`), per axis and per bound (4.7 pins only a fixed
/// width). Each animates 40 → 80 under `withAnimation(.linear(duration: 1))` in the
/// 200×100 harness root; derived by hand, the frame reads 40 before and at the
/// transaction's start and 60 half-way on the animated axis (under both
/// authorities until stage 9):
///
/// - `.frame(minWidth:)` over a 10×10 box: 40×10, 40×10, 60×10;
/// - `.frame(minHeight:)` over a 10×10 box: 10×40, 10×40, 10×60;
/// - `.frame(maxWidth:)` over a 100×10 box (larger than the maximum, so the legacy
///   clamp and the lowered greedy maximum agree, `FR-E`): 40×10, 40×10, 60×10;
/// - `.frame(maxHeight:)` over a 10×100 box: 10×40, 10×40, 10×60.
///
/// Mutations that must redden it: **V2** (`minWidth`), **V2h** (`minHeight`),
/// **V2x** (`maxWidth`), **V2y** (`maxHeight`) — each bound read from `FrameSpec`
/// instead of the animated style (that arm's lowered frame reads 80 at the start
/// and half-way).
@MainActor
@Test func aFrameLayerLowersItsMinimaAndFiniteMaximaFromItsAnimatedStyle() throws {
    typealias Framed = ModifiedElement<Box<EmptyGroup>>
    let arms: [(String, Framed, Framed, [Bounds<Pixels>])] = [
        ("minWidth", fixed(10, 10).frame(minWidth: px(40)), fixed(10, 10).frame(minWidth: px(80)),
         [bounds(0, 0, 40, 10), bounds(0, 0, 40, 10), bounds(0, 0, 60, 10)]),
        ("minHeight", fixed(10, 10).frame(minHeight: px(40)), fixed(10, 10).frame(minHeight: px(80)),
         [bounds(0, 0, 10, 40), bounds(0, 0, 10, 40), bounds(0, 0, 10, 60)]),
        ("maxWidth", fixed(100, 10).frame(maxWidth: px(40)), fixed(100, 10).frame(maxWidth: px(80)),
         [bounds(0, 0, 40, 10), bounds(0, 0, 40, 10), bounds(0, 0, 60, 10)]),
        ("maxHeight", fixed(10, 100).frame(maxHeight: px(40)), fixed(10, 100).frame(maxHeight: px(80)),
         [bounds(0, 0, 10, 40), bounds(0, 0, 10, 40), bounds(0, 0, 10, 60)]),
    ]
    var ran = 0
    for (name, start, end, expected) in arms {
        let r = animatedRects([containerID], start: start, end: end)
        try #require(r.count == 3)
        #expect(r.map { $0[0] } == expected, "\(name): \(r)")
        ran += 1
    }
    try #require(ran == 4)
}

/// **4.12.** A frame over **no** node that is not fixed on both axes shows the
/// stand-in leaf's size (4.4's arm is fixed on both, where it cannot): ruling
/// LR-Z's agreement "for a fixed or min-only frame". `NoNodes().frame(width: 40)`
/// is 40×0 and `NoNodes().frame(minWidth: 40)` is 40×0 (on both sides until
/// stage 9).
///
/// Mutation that must redden it: **V6**, the stand-in leaf answers 10×10 (the
/// lowered frames read 40×10).
@MainActor
@Test func aFrameOverNoNodeFixedOnOneAxisOrMinOnlyIsZeroOnTheOther() throws {
    let arms: [(String, LayoutDifferential.Report)] = [
        ("width only", LayoutDifferential.report(width: 200, height: 200) {
            NoNodes().frame(width: px(40)).background(.accent)
        }),
        ("minWidth only", LayoutDifferential.report(width: 200, height: 200) {
            NoNodes().frame(minWidth: px(40)).background(.accent)
        }),
    ]
    try #require(arms.count == 2)
    for (name, r) in arms {
        try #require(r.elements == 2, "\(name): \(r.elements)")
        expectNothingReported(r, name)
        #expect(lowered(r, [containerID]) == [bounds(0, 0, 40, 0)], "\(name)")
    }
}
