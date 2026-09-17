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
// legacy engine through the differential harness (`LayoutDifferential.swift`).
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
    Box().width(px(w)).height(px(h))
}

/// Two fixed boxes as ONE component, so a frame around it wraps two nodes.
private struct TwoBoxes: Component {
    var content: some ElementGroup {
        Box().width(Pixels(10)).height(Pixels(10))
        Box().width(Pixels(10)).height(Pixels(10))
    }
}

/// A component with no layout node, so a frame around it wraps zero nodes.
/// (`EmptyGroup().frame(…)` would resolve to the **proposal** frame — `EmptyGroup`
/// is a `ProposalElementGroup` — whose single-child precondition traps.)
private struct NoNodes: Component {
    var content: some ElementGroup { EmptyGroup() }
}

/// Every whole-frame observation agrees and nothing was reported.
@MainActor
private func expectFullAgreement(_ r: LayoutDifferential.Report, _ arm: String,
                                 sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(r.unlowerable.isEmpty, "\(arm): \(r.unlowerable)", sourceLocation: sourceLocation)
    #expect(r.disagreeing.isEmpty, "\(arm): \(r.disagreeing)", sourceLocation: sourceLocation)
    #expect(r.legacyOnly.isEmpty && r.loweredOnly.isEmpty,
            "\(arm): legacyOnly \(r.legacyOnly) loweredOnly \(r.loweredOnly)", sourceLocation: sourceLocation)
    #expect(r.scenesEqual, "\(arm): scenes", sourceLocation: sourceLocation)
    #expect(r.hitboxesEqual, "\(arm): hitboxes", sourceLocation: sourceLocation)
    #expect(r.accessibilityEqual, "\(arm): accessibility", sourceLocation: sourceLocation)
    #expect(r.stateSlotsEqual, "\(arm): state slots", sourceLocation: sourceLocation)
}

private func lowered(_ r: LayoutDifferential.Report, _ ids: [GlobalElementID]) -> [Bounds<Pixels>?] {
    ids.map { r.loweredBounds[$0] }
}

/// The proposal frame's diagnostics for `make()` inside a 100×100 harness root.
@MainActor
private func report<C: ElementGroup>(@ElementBuilder _ make: @MainActor () -> C) -> [UnlowerableField] {
    LayoutDifferential.render(authority: .proposal, width: 100, height: 100, make).unlowerableFields
}

// MARK: - 4.1, 4.2 — Stack

/// `Stack`'s nine alignments with their horizontal and vertical factors.
private let stackAlignments: [(Alignment, Float, Float)] = [
    (.topLeading, 0, 0), (.top, 0.5, 0), (.topTrailing, 1, 0),
    (.leading, 0, 0.5), (.center, 0.5, 0.5), (.trailing, 1, 0.5),
    (.bottomLeading, 0, 1), (.bottom, 0.5, 1), (.bottomTrailing, 1, 1),
]

/// **4.1.** A lowered `Stack` places fixed children at all nine alignments as the
/// legacy stack does (ruling LR-G: for fixed children the fit-content offer and the
/// proposal agree). Children a 20×10 and b 10×30; horizontal factor h, vertical v:
///
/// - **unsized**: the stack is the union, 20×30; a at (0, 20v), b at (10h, 0);
/// - **sized 100×60 with `Style.padding`** top 4, right 6, bottom 8, left 10 (the
///   content box 84×48 at (10, 4)): a at (10 + 64h, 4 + 38v), b at (10 + 74h, 4 + 18v).
///
/// Further arms:
/// - **container fields a stack does not read** — `flexDirection(.column)`, a gap,
///   `justifyContent(.spaceBetween)`, `flexWrap`, `alignContent` on a sized
///   `.bottomTrailing` stack — report nothing and agree;
/// - **reported** (the report is exactly this): a `Box` declaring `display: .stack`
///   with its `nil` alignments → `[alignItems.stretch, justifyItems.stretch]` (lane
///   3's `noLowering` for it, amended as `LR-Y` requires); a `Stack` with
///   `.alignItems(.stretch)` → `[alignItems.stretch]`; with `.alignItems(.baseline)`
///   → `[alignItems.baseline]`; with `.margin(2)` → `[margin]`; hidden with a
///   stretch → `[display.none]` alone.
///
/// Mutation that must redden it: **M4a**, the overlay's horizontal and vertical
/// factors swapped.
@MainActor
@Test func aLoweredStackPlacesFixedChildrenAtAllNineAlignmentsAsTheLegacyStackDoes() throws {
    let a = child(containerID, 0), b = child(containerID, 1)
    var arms = 0
    for (alignment, h, v) in stackAlignments {
        let unsized = LayoutDifferential.compare(width: 200, height: 200) {
            Stack(alignment: alignment) { fixed(20, 10); fixed(10, 30) }
        }
        try #require(unsized.elements == 4, "unsized \(alignment): \(unsized.elements)")
        expectFullAgreement(unsized, "unsized \(alignment)")
        #expect(lowered(unsized, [containerID, a, b])
                == [bounds(0, 0, 20, 30), bounds(0, 20 * v, 20, 10), bounds(10 * h, 0, 10, 30)],
                "unsized \(alignment)")

        var stack = Stack(alignment: alignment) { fixed(20, 10); fixed(10, 30) }.width(px(100)).height(px(60))
        stack.style.padding = Edges(top: .pixels(px(4)), right: .pixels(px(6)),
                                    bottom: .pixels(px(8)), left: .pixels(px(10)))
        let padded = stack
        let sized = LayoutDifferential.compare(width: 200, height: 200) { padded.background(.accent) }
        try #require(sized.elements == 4, "sized \(alignment): \(sized.elements)")
        expectFullAgreement(sized, "sized \(alignment)")
        #expect(lowered(sized, [containerID, a, b])
                == [bounds(0, 0, 100, 60), bounds(10 + 64 * h, 4 + 38 * v, 20, 10),
                    bounds(10 + 74 * h, 4 + 18 * v, 10, 30)],
                "sized \(alignment)")
        arms += 2
    }
    try #require(arms == 18)

    var ignoring = Stack(alignment: .bottomTrailing) { fixed(20, 10); fixed(10, 30) }
        .width(px(100)).height(px(60))
        .gap(horizontal: px(7), vertical: px(9)).justifyContent(.spaceBetween)
        .flexWrap(.wrap).alignContent(.center)
    ignoring.style.flexDirection = .column
    let ignored = ignoring
    let ignoredReport = LayoutDifferential.compare(width: 200, height: 200) { ignored }
    try #require(ignoredReport.elements == 4)
    expectFullAgreement(ignoredReport, "container fields a stack does not read")
    #expect(lowered(ignoredReport, [a, b]) == [bounds(80, 50, 20, 10), bounds(90, 30, 10, 30)])

    var stackStyle = Style()
    stackStyle.display = .stack
    let reported: [(String, [UnlowerableField], [UnlowerableField])] = [
        ("Box with display: .stack", report { Box(style: stackStyle) { fixed(20, 10); fixed(10, 30) } },
         [field(.box, "alignItems.stretch"), field(.box, "justifyItems.stretch")]),
        ("Stack alignItems stretch", report { Stack { fixed(20, 10); fixed(10, 30) }.alignItems(.stretch) },
         [field(.stack, "alignItems.stretch")]),
        ("Stack alignItems baseline", report { Stack { fixed(20, 10); fixed(10, 30) }.alignItems(.baseline) },
         [field(.stack, "alignItems.baseline")]),
        ("Stack margin", report { Stack { fixed(20, 10); fixed(10, 30) }.margin(px(2)) },
         [field(.stack, "margin")]),
        ("hidden stretching Stack",
         report { Stack { fixed(20, 10); fixed(10, 30) }.alignItems(.stretch).hidden() },
         [field(.stack, "display.none")]),
    ]
    try #require(reported.count == 5)
    for (name, entries, expected) in reported {
        #expect(entries == expected, "\(name): \(entries)")
    }
}

/// **4.2.** A lowered `Stack` **offers its proposal** where the legacy stack offers
/// fit-content (ruling LR-G, divergence 53; stack-algorithms probe A5: a greedy
/// child of a `ZStack` at 100×80 fills 100×80). `Column { Stack { Text(long) } }`
/// sized 60 wide in the harness root:
///
/// - legacy: the stack is a column item, fit-content against 60 → 60, and the text
///   inside it fit-content against 60 → **60**;
/// - lowered: the column's frame proposes 60, the overlay proposes 60 to the text,
///   which answers the shaper's widest line wrapped at 60 (`LR-F`), computed here
///   from a fresh `ShapingCache`.
///
/// The disagreement is a `try #require`. The report is empty.
///
/// Mutation that must redden it: **M4b**, each lowered stack child wrapped in a
/// native `fixedSize` (the text is measured unwrapped, one long line).
@MainActor
@Test func aLoweredStackOffersItsProposalWhereTheLegacyStackOffersFitContent() throws {
    let r = LayoutDifferential.compare(width: 200, height: 300) {
        Column { Stack { Text(longString) } }.width(px(60))
    }
    // root, column, stack, text
    try #require(r.elements == 4)
    #expect(r.unlowerable.isEmpty, "\(r.unlowerable)")
    let text = child(child(containerID, 0), 0)
    let legacy = try #require(r.legacyBounds[text])
    let loweredText = try #require(r.loweredBounds[text])
    let cache = ShapingCache()
    let widest = cache.shaped(longString, font: cache.resolveFont(family: nil, size: 13),
                              wrappingAt: 60).widestLine
    #expect(legacy.size.width == px(60))
    #expect(loweredText.size.width == Pixels(Float(widest.rounded())))
    #expect(legacy.size.height == loweredText.size.height)
    try #require(legacy.size.width != loweredText.size.width)
}

// MARK: - 4.3–4.5 — padding and frame layers

/// **4.3.** A lowered `.padding` layer agrees with the legacy wrapper (a padding
/// layer is a one-child container: `LR-E`'s single-child stretch with no declared
/// cross size, so nothing is reported).
///
/// - `fixed(20, 10).padding(4).padding(8)` with a background on each: outermost
///   layer (0, 0) 44×34, inner layer (8, 8) 28×18, the box (12, 12);
/// - asymmetric edges top 2, right 4, bottom 6, left 8 over the box: layer 32×18,
///   the box at (8, 2);
/// - `Text("Count 3").padding(4)` and the same asymmetric edges over it, with a
///   background: agreement, glyphs included, the text at (4, 4) and (8, 2).
///
/// Mutation that must redden it: **M4c**, the lowered padding's top and bottom
/// insets swapped (the asymmetric arms' content moves to y 6).
@MainActor
@Test func aLoweredPaddingLayerAgreesWithTheLegacyWrapper() throws {
    let inner = child(containerID, 0)
    let chain = LayoutDifferential.compare(width: 200, height: 200) {
        fixed(20, 10).background(.accent).padding(px(4)).background(.surface)
            .padding(px(8)).background(.surfaceSecondary)
    }
    try #require(chain.elements == 4)
    expectFullAgreement(chain, "padding(4).padding(8)")
    #expect(lowered(chain, [containerID, inner, child(inner, 0)])
            == [bounds(0, 0, 44, 34), bounds(8, 8, 28, 18), bounds(12, 12, 20, 10)])

    let edges = Edges<Length>(top: .pixels(px(2)), right: .pixels(px(4)),
                              bottom: .pixels(px(6)), left: .pixels(px(8)))
    let asymmetric = LayoutDifferential.compare(width: 200, height: 200) {
        fixed(20, 10).padding(edges).background(.accent)
    }
    try #require(asymmetric.elements == 3)
    expectFullAgreement(asymmetric, "asymmetric box")
    #expect(lowered(asymmetric, [containerID, child(containerID, 0)])
            == [bounds(0, 0, 32, 18), bounds(8, 2, 20, 10)])

    var arms = 0
    for (name, element, origin) in [("text padding(4)", Text("Count 3").padding(px(4)), (Float(4), Float(4))),
                                     ("text asymmetric", Text("Count 3").padding(edges), (Float(8), Float(2)))] {
        let decorated = element.background(.accent)
        let legacy = LayoutDifferential.render(authority: .legacy, width: 200, height: 200) { decorated }
        try #require(legacy.scene.glyphs.count >= 6, "\(name)")
        let r = LayoutDifferential.compare(width: 200, height: 200) { decorated }
        try #require(r.elements == 3, "\(name)")
        expectFullAgreement(r, name)
        #expect(r.loweredBounds[child(containerID, 0)]?.origin
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

/// **4.4.** A lowered fixed `.frame(width: 60, height: 40, alignment:)` agrees with
/// the legacy frame layer (a one-cell stack over one node, ruling `CN-N`) at all
/// nine alignments, over a child smaller than the frame (20×10: at (40h, 30v)) and
/// one larger (80×60: at (−20h, −20v), overflowing, probe arms A5/B9). A frame over
/// **no** node (`NoNodes().frame(width: 40, height: 40)`, a component with no
/// node) is 40×40 on both sides.
///
/// Mutation that must redden it: **M4d**, the lowered frame's alignment forced
/// `.center`.
@MainActor
@Test func aLoweredFixedFrameLayerAgreesWithTheLegacyFrameOverAFixedChild() throws {
    let content = child(containerID, 0)
    var arms = 0
    for (alignment, h, v) in frameAlignments {
        for (w, hgt, at) in [(Float(20), Float(10), (40 * h, 30 * v)), (Float(80), Float(60), (-20 * h, -20 * v))] {
            let r = LayoutDifferential.compare(width: 200, height: 200) {
                fixed(w, hgt).frame(width: px(60), height: px(40), alignment: alignment).background(.accent)
            }
            try #require(r.elements == 3, "\(alignment) \(w)")
            expectFullAgreement(r, "\(alignment) \(w)×\(hgt)")
            #expect(lowered(r, [containerID, content])
                    == [bounds(0, 0, 60, 40), bounds(at.0, at.1, w, hgt)], "\(alignment) \(w)×\(hgt)")
            arms += 1
        }
    }
    try #require(arms == 18)

    let empty = LayoutDifferential.compare(width: 200, height: 200) {
        NoNodes().frame(width: px(40), height: px(40)).background(.accent)
    }
    try #require(empty.elements == 2)
    expectFullAgreement(empty, "frame over no node")
    #expect(lowered(empty, [containerID]) == [bounds(0, 0, 40, 40)])
}

/// **4.5.** A lowered **flexible** frame takes SwiftUI's answer where the legacy
/// frame clamps (ruling LR-H; `FR-E`, divergence 35; `FR-O`). Each inside a
/// 100-wide `Column` (centred) in the harness root, over a 20×20 box:
///
/// - `.frame(minWidth: 40, maxWidth: 80)`: legacy 40 wide at x 30 (a CSS clamp of
///   the child's 20); lowered **80** at x 10 (frame probe D control: 80×20 at a
///   100 proposal). The box is at x 40 on both sides;
/// - `.frame(maxWidth: .infinity)` alone: legacy 20 at x 40 (a single infinite
///   maximum is inert, `FR-O`); lowered **100** at x 0. The box at x 40 on both.
///
/// Each disagreement is a `try #require`; the reports are empty.
///
/// Mutation that must redden it: **M4e**, the flexible frame lowered as a CSS clamp
/// (a `fixedSize` child clamped to min/max: the lowered frame reads 40 and 20).
@MainActor
@Test func aLoweredFlexibleFrameLayerTakesSwiftUIsAnswerWhereTheLegacyFrameClamps() throws {
    let frameID = child(containerID, 0)
    let box = child(frameID, 0)

    let bounded = LayoutDifferential.compare(width: 200, height: 200) {
        Column { fixed(20, 20).frame(minWidth: px(40), maxWidth: px(80)) }.width(px(100))
    }
    try #require(bounded.elements == 4)
    #expect(bounded.unlowerable.isEmpty, "\(bounded.unlowerable)")
    try #require(bounded.legacyBounds[frameID] != bounded.loweredBounds[frameID])
    #expect(bounded.legacyBounds[frameID] == bounds(30, 0, 40, 20))
    #expect(bounded.loweredBounds[frameID] == bounds(10, 0, 80, 20))
    #expect(bounded.legacyBounds[box] == bounds(40, 0, 20, 20))
    #expect(bounded.loweredBounds[box] == bounds(40, 0, 20, 20))

    let infinite = LayoutDifferential.compare(width: 200, height: 200) {
        Column { fixed(20, 20).frame(maxWidth: px(.infinity)) }.width(px(100))
    }
    try #require(infinite.elements == 4)
    #expect(infinite.unlowerable.isEmpty, "\(infinite.unlowerable)")
    try #require(infinite.legacyBounds[frameID] != infinite.loweredBounds[frameID])
    #expect(infinite.legacyBounds[frameID] == bounds(40, 0, 20, 20))
    #expect(infinite.loweredBounds[frameID] == bounds(0, 0, 100, 20))
    #expect(infinite.legacyBounds[box] == bounds(40, 0, 20, 20))
    #expect(infinite.loweredBounds[box] == bounds(40, 0, 20, 20))
}

// MARK: - 4.6, 4.7 — ideal, animation

@MainActor
private func idealRow() -> some ElementGroup {
    Row { fixed(20, 20).frame(idealWidth: px(80)) }
}

@MainActor
private func idealColumn() -> some ElementGroup {
    Column { fixed(20, 20).frame(idealHeight: px(80)) }
}

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

/// A root that measures and places its content at a **nil×nil** proposal under
/// the proposal authority (a native `NilProposal` layout); it registers nothing
/// under the legacy one, where only the ideal trap is exercised.
@MainActor
private struct NilProposalRoot<Content: ElementGroup>: Element {
    var content: Content

    init(@ElementBuilder content: () -> Content) { self.content = content() }

    struct Layout { var content: Content.GroupLayout }

    mutating func requestLayout(_ id: GlobalElementID,
                                pass: inout LayoutPass) -> (LayoutNodeID, Layout) {
        var cursor = 0
        let (children, contentLayout) = content.requestGroupLayout(under: id, at: &cursor, pass: &pass)
        let node = pass.lowersToProposal
            ? pass.frame.requestNativeLayout(NilProposal(), children: children)
            : pass.frame.requestNode(style: Style(), children: children)
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

/// `make()` under a `NilProposalRoot`, under the proposal authority with
/// diagnostics and the bounds log on.
@MainActor
private func renderAtNilProposal<C: ElementGroup>(@ElementBuilder _ make: () -> C) -> Frame {
    var root = NilProposalRoot(content: make)
    let frame = Frame(contentSize: Size(width: Pixels(200), height: Pixels(200)), scaleFactor: 1,
                      layoutAuthority: .proposal, reportsUnlowerableFields: true,
                      recordsElementBounds: true)
    frame.render(&root)
    return frame
}

/// **4.6.** An ideal frame **lowers** under the proposal authority and **still
/// traps** when laid out by the legacy engine (ruling LR-H, `FR-D`'s trap moved
/// from construction to legacy registration).
///
/// - proposal arm, in a child process (on lane 3's tree construction traps, which
///   in-process would end the run): measured at a **nil** proposal (`NilProposal`,
///   a custom layout — nothing the stage-1 lowering registers proposes nil: a
///   lowered `Row` proposes its own finite proposal, where the frame answers its
///   child, frame probe C control), `.frame(idealWidth: 80)` over a 20×20 box
///   answers **80×20** (frame probe C1: `frame(idealWidth: 80)` at a nil proposal
///   is 80×20), and `.frame(idealHeight: 80)` answers 20×80. A native root is
///   stored centred in the 200×200 window at its own answer (`CN-J`), so the frames
///   read (60, 90) 80×20 and (90, 60) 20×80, each with the box centred at (90, 90).
///   The child prints both frame rects and both reports;
/// - legacy arms (exit tests): rendering `Row { … .frame(idealWidth: 80) }` or its
///   `Column`/`idealHeight` twin in the harness root under the legacy authority
///   fails, and stderr names `idealWidth` / `idealHeight`.
///
/// Mutation that must redden it: **M4f**, the ideal dropped from the lowering (the
/// frames read 20×20).
@Test func anIdealFrameLowersUnderTheProposalAuthorityAndStillTrapsUnderTheLegacyOne() async throws {
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

    let width = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        await MainActor.run {
            _ = LayoutDifferential.render(authority: .legacy, width: 200, height: 200) { idealRow() }
        }
    }
    let widthErr = String(decoding: width?.standardErrorContent ?? [], as: UTF8.self)
    #expect(widthErr.contains("idealWidth has no legacy (CSS) lowering"), "\(widthErr)")

    let height = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        await MainActor.run {
            _ = LayoutDifferential.render(authority: .legacy, width: 200, height: 200) { idealColumn() }
        }
    }
    let heightErr = String(decoding: height?.standardErrorContent ?? [], as: UTF8.self)
    #expect(heightErr.contains("idealHeight has no legacy (CSS) lowering"), "\(heightErr)")
}

/// **4.7.** A frame layer lowers from its **animated** `Style` for what `Style`
/// carries, and the check reads its **declared** style, so an animation never trips
/// it (ruling LR-H). `fixed(10, 10).frame(width: 40)` animating to `.frame(width:
/// 80)` under `withAnimation(.linear(duration: 1))`, derived by hand, under both
/// authorities: the frame that starts the transaction reads the frame 40×10 with the
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
    var arms = 0
    for authority in [LayoutAuthority.legacy, .proposal] {
        let table = StateTable()
        func rects(width: Float, timestamp: Double, animating: Bool) -> [Bounds<Pixels>?] {
            let element = fixed(10, 10).frame(width: px(width))
            var root = DifferentialRoot(width: 200, height: 100) { element }
            let frame = Frame(contentSize: Size(width: Pixels(200), height: Pixels(100)), scaleFactor: 1,
                              stateTable: table, timestamp: timestamp,
                              transaction: animating ? .linear(duration: 1) : nil,
                              layoutAuthority: authority,
                              reportsUnlowerableFields: authority == .proposal,
                              recordsElementBounds: true)
            frame.render(&root)
            #expect(frame.unlowerableFields.isEmpty, "\(authority) t \(timestamp): \(frame.unlowerableFields)")
            return [containerID, box].map { frame.elementBounds[$0] }
        }
        #expect(rects(width: 40, timestamp: 0, animating: false)
                == [bounds(0, 0, 40, 10), bounds(15, 0, 10, 10)], "\(authority) baseline")
        #expect(rects(width: 80, timestamp: 0, animating: true)
                == [bounds(0, 0, 40, 10), bounds(15, 0, 10, 10)], "\(authority) transaction start")
        #expect(rects(width: 80, timestamp: 0.5, animating: false)
                == [bounds(0, 0, 60, 10), bounds(25, 0, 10, 10)], "\(authority) half-way")
        arms += 1
    }
    try #require(arms == 2)
}

// MARK: - 4.8, 4.9 — what a frame layer reports

/// **4.8.** A `Self`-returning sizing or item modifier written after `.frame` lands
/// on the frame layer, makes its declared style differ from `lowered(frameSpec
/// .style(), childCount:)`, and is reported `modifierLayer.style` (ruling LR-H):
/// `.frame(width: 40).width(60)`, `.frame(width: 40).minWidth(10)`,
/// `.frame(maxWidth: 80).flexGrow(1)`, and on an **inner** layer
/// `.frame(width: 40).alignItems(.flexEnd).padding(4)`. Control:
/// `.frame(width: 40).background(.accent)` reports nothing and agrees (a
/// `Decoration` is not `Style`).
///
/// Mutation that must redden it: **M4h**, the comparison made against
/// `frameSpec.style()` without `lowered(_:childCount:)` (the control, a one-node
/// frame whose declared style is `display: .stack`, reports).
@MainActor
@Test func aSizingModifierWrittenAfterAFrameIsReportedOnTheFrameLayer() throws {
    let style = field(.modifierLayer, "style")
    let arms: [(String, [UnlowerableField], [UnlowerableField])] = [
        ("width after frame", report { fixed(10, 10).frame(width: px(40)).width(px(60)) }, [style]),
        ("minWidth after frame", report { fixed(10, 10).frame(width: px(40)).minWidth(px(10)) }, [style]),
        ("flexGrow after flexible frame", report { fixed(10, 10).frame(maxWidth: px(80)).flexGrow(1) }, [style]),
        ("alignItems after frame, inner layer",
         report { fixed(10, 10).frame(width: px(40)).alignItems(.flexEnd).padding(px(4)) }, [style]),
    ]
    try #require(arms.count == 4)
    for (name, entries, expected) in arms {
        #expect(entries == expected, "\(name): \(entries)")
    }

    let control = LayoutDifferential.compare(width: 200, height: 200) {
        fixed(10, 10).frame(width: px(40)).background(.accent)
    }
    try #require(control.elements == 3)
    expectFullAgreement(control, "background after frame")
    #expect(lowered(control, [containerID, child(containerID, 0)])
            == [bounds(0, 0, 40, 10), bounds(15, 0, 10, 10)])
}

/// **4.9.** `hidden()` after a frame sets `display: none` on the frame layer, which
/// `ModifierLayer.lowered` keeps; it is reported `display.none` **before** the style
/// comparison, alone (ruling LR-J): over one node, over two (a two-member component),
/// with a sizing modifier also written after it, and on an inner layer. A frame over
/// two nodes that is not hidden reports `frame.multipleNodes` (ruling LR-Z; stage 3
/// owns a frame over a multi-member component).
///
/// Mutation that must redden it: **M4i**, the `display.none` check moved after the
/// comparison (the entries read `modifierLayer.style`).
@MainActor
@Test func aHiddenFrameLayerIsReportedAsDisplayNone() throws {
    let hidden = field(.modifierLayer, "display.none")
    let arms: [(String, [UnlowerableField], [UnlowerableField])] = [
        ("one node", report { fixed(10, 10).frame(width: px(40)).hidden() }, [hidden]),
        ("two nodes", report { TwoBoxes().frame(width: px(40)).hidden() }, [hidden]),
        ("with a width after it", report { fixed(10, 10).frame(width: px(40)).hidden().width(px(60)) }, [hidden]),
        ("inner layer", report { fixed(10, 10).frame(width: px(40)).hidden().padding(px(4)) }, [hidden]),
        ("two nodes, not hidden", report { TwoBoxes().frame(width: px(40)) },
         [field(.modifierLayer, "frame.multipleNodes")]),
    ]
    try #require(arms.count == 5)
    for (name, entries, expected) in arms {
        #expect(entries == expected, "\(name): \(entries)")
    }
}
