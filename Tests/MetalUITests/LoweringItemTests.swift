import Foundation
import Metal
import Observation
import Testing
import MetalUICore
@testable import MetalUILayout
import MetalUIText
@testable import MetalUI

// Plan task 7, stage 2, lanes 1 and 2 (`docs/superpowers/specs/2026-09-17-engine-stage-2-design.md`
// §3, §4.1 and §6 lanes 1–2; rulings LR-AB, LR-AC, LR-AD, LR-AQ, LR-AR, LR-AW, and for
// lane 2 LR-AE, LR-AF, LR-AG, LR-AS, LR-AX): flex
// ITEM fields lowered by the parent under the proposal layout authority — the child
// records a `LoweredItem`, the lowered container wraps it (a greedy cross-axis item
// frame W for stretch, aliased as the element's rect; an unaliased alignment frame
// for a non-stretch `alignSelf`), and a record no lowered container consumes reports
// `<site>.<field>.unconsumed`.
//
// **Red before**: every test here was run on `cb2e708`'s lowering (stage 1), where
// stretch reports `alignItems.stretch` and every item field reports at the child's
// own site; each reads red there by a report or a literal mismatch, and compiles
// against stage-1 API only (record §21, lane 1). 1.12's agreeing arm is
// characterization (green on arrival). The mutation each must redden is named in its
// doc comment and in spec §6's lane-1 table; the record names what each reddened.
//
// **The harness root proposes its size** (divergence 53): an unsized container
// placed under it is offered 300×… and a greedy item in it fills that offer, where
// the legacy root offers fit-content. So an arm whose line must be the legacy
// line either declares the container's cross size or is itself stretched by a
// container that declares it; the arms where the fill IS the subject (1.6, 1.7,
// 1.9's X16 arm, 1.15) are divergence pins.
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

/// A fixed-size childless `Box`.
@MainActor
private func fixed(_ w: Float, _ h: Float) -> Box<EmptyGroup> {
    Box().width(px(w)).height(px(h))
}

/// The proposal frame's diagnostics for `make()` inside a `width`×`height` harness root.
@MainActor
private func report<C: ElementGroup>(width: Float = 300, height: Float = 200,
                                     @ElementBuilder _ make: @MainActor () -> C) -> [UnlowerableField] {
    LayoutDifferential.render(authority: .proposal, width: width, height: height, make).unlowerableFields
}

/// A `Stack` whose `alignItems` and `justifyItems` are `nil` — CSS `stretch` on
/// both axes — which no `Stack` initializer spells.
@MainActor
private func stretchingStack<C: ElementGroup>(@ElementBuilder _ content: () -> C) -> Stack<C> {
    var stack = Stack(content: content)
    stack.style.alignItems = nil
    stack.style.justifyItems = nil
    return stack
}

/// A legacy element placed where a **proposal** container expects proposal
/// content. Under the proposal authority a lowered legacy element registers only
/// native nodes (ruling LR-T), so the typed entry mints its ids through the
/// internal initializer — `ProposalNodeID.swift`'s hole 3, open to `@testable`
/// code — and the proposal container receives the element's records without
/// consuming them (ruling LR-AQ).
@MainActor
private struct LegacyUnderProposal<Content: ElementGroup>: ProposalElementGroup {
    var content: Content

    init(_ content: Content) { self.content = content }

    mutating func requestGroupLayout(under parent: GlobalElementID?, at cursor: inout Int,
                                     pass: inout LayoutPass) -> ([LayoutNodeID], Content.GroupLayout) {
        content.requestGroupLayout(under: parent, at: &cursor, pass: &pass)
    }

    mutating func requestProposalGroupLayout(under parent: GlobalElementID?, at cursor: inout Int,
                                             pass: inout LayoutPass) -> ([ProposalNodeID], Content.GroupLayout) {
        let (nodes, layout) = content.requestGroupLayout(under: parent, at: &cursor, pass: &pass)
        return (nodes.map { ProposalNodeID($0) }, layout)
    }

    mutating func prepaintGroup(layout: inout Content.GroupLayout,
                                pass: inout PrepaintPass) -> Content.GroupPrepaint {
        content.prepaintGroup(layout: &layout, pass: &pass)
    }

    mutating func paintGroup(layout: inout Content.GroupLayout, prepaint: inout Content.GroupPrepaint,
                             pass: inout PaintPass) {
        content.paintGroup(layout: &layout, prepaint: &prepaint, pass: &pass)
    }
}

/// A custom layout that places its one subview at its own origin at its proposal.
private struct AtOrigin: ProposalLayout {
    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
        subviews[0].sizeThatFits(proposal)
    }

    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize, subviews: PlacementSubviews) {
        subviews[0].place(at: Point(x: bounds.x, y: bounds.y), proposal: proposal)
    }
}

// MARK: - 1.1, 1.2 — stretch fills the line, and the content sits by its own alignment

/// **1.1** (`LR-AC`; stage-2 probe X1, X2). A child whose cross size is `auto` in a
/// container that stretches — `Row {…}.alignItems(.stretch)`, `Column
/// {…}.alignItems(.stretch)` and a `Box` (its default) — fills the line: under the
/// proposal authority a greedy cross-axis item frame W, aliased as the child's rect.
/// Each arm has two children (a fixed sibling S and the stretched child C), so the
/// one-child elision does not apply. Three children C: a childless `Box` with a
/// main size, a `Text`, and a one-child `Row` with `justifyContent(.center)`.
///
/// Two lines per parent: **declared** (the parent's own cross size, 70) and
/// **stretched** (the parent declares none and is itself stretched to 60 by a
/// two-child grandparent that declares it). *Not* a parent whose line is its
/// tallest sibling: under the harness root that parent is offered the root's
/// size (divergence 53) and its greedy W fills it — cause R, pinned by 1.7.
///
/// Row-like parents (`Row`, `Box`): S 30×40, C `Box().width(20)`; column parent:
/// S 40×30, C `Box().height(20)`. Every arm agrees in every observation, C's
/// cross size reads the line (70 or 60), and the `Row` child's box sits by its
/// `justifyContent` on its main axis where that axis is the stretched one: in the
/// column parent its 10×10 child is at x (70 − 10)/2 = 30, or (60 − 10)/2 = 25.
///
/// Mutations that must redden it: **M1a** W registered but not aliased; **M1b** W
/// greedy on the main axis instead of the cross.
@MainActor
@Test func aStretchedChildFillsTheLineOnItsCrossAxis() throws {
    enum Parent: CaseIterable { case row, column, box }
    enum Stretched: CaseIterable { case box, text, row }
    var arms = 0
    for parent in Parent.allCases {
        for stretched in Stretched.allCases {
            let isColumn = parent == .column
            // The stretched child, and how many element ids it records.
            func c() -> AnyElement {
                switch stretched {
                case .box: AnyElement(isColumn ? Box().height(px(20)).background(.accent)
                                               : Box().width(px(20)).background(.accent))
                case .text: AnyElement(Text("ab"))
                case .row: AnyElement(Row { fixed(10, 10) }.justifyContent(.center).background(.accent))
                }
            }
            let cIDs = stretched == .row ? 2 : 1
            func s() -> Box<EmptyGroup> { isColumn ? fixed(40, 30) : fixed(30, 40) }
            func container<Content: ElementGroup>(cross: Float?,
                                                  @ElementBuilder _ content: () -> Content) -> AnyElement {
                switch parent {
                case .row:
                    let r = Row(content: content).alignItems(.stretch)
                    return AnyElement(cross.map { r.height(px($0)) } ?? r)
                case .column:
                    let col = Column(content: content).alignItems(.stretch)
                    return AnyElement(cross.map { col.width(px($0)) } ?? col)
                case .box:
                    let b = Box(content: content)
                    return AnyElement(cross.map { b.height(px($0)) } ?? b)
                }
            }
            let name = "\(parent) parent, stretched \(stretched)"

            // Declared: the parent's cross size is 70.
            let declared = LayoutDifferential.compare(width: 300, height: 200) {
                container(cross: 70) { s(); c() }
            }
            try #require(declared.elements == 3 + cIDs, "\(name), declared: \(declared.elements)")
            expectCorpusAgreement(declared, "\(name), declared")
            let declaredC = try #require(declared.loweredBounds[child(containerID, 1)])
            #expect((isColumn ? declaredC.size.width : declaredC.size.height) == px(70), "\(name), declared: \(declaredC)")
            if stretched == .row && isColumn {
                #expect(declared.loweredBounds[child(child(containerID, 1), 0)]?.origin.x == px(30), "\(name), declared")
            }

            // Stretched: the parent declares nothing and a sized grandparent stretches it to 60.
            let stretchedParent = LayoutDifferential.compare(width: 300, height: 200) {
                container(cross: 60) {
                    container(cross: nil) { s(); c() }
                    fixed(10, 10)
                }
            }
            try #require(stretchedParent.elements == 5 + cIDs, "\(name), stretched: \(stretchedParent.elements)")
            expectCorpusAgreement(stretchedParent, "\(name), stretched by its parent")
            let p = child(containerID, 0)
            let stretchedC = try #require(stretchedParent.loweredBounds[child(p, 1)])
            #expect((isColumn ? stretchedC.size.width : stretchedC.size.height) == px(60), "\(name), stretched: \(stretchedC)")
            if stretched == .row && isColumn {
                #expect(stretchedParent.loweredBounds[child(child(p, 1), 0)]?.origin.x == px(25), "\(name), stretched")
            }
            arms += 2
        }
    }
    try #require(arms == 18)
}

/// **1.2** (`LR-AB` item 2: W is aligned by the child's own content alignment). In
/// a 200-wide `Column {…}.alignItems(.stretch)` beside a 20×10 sibling:
///
/// - a stretched `Column { 30×10; 50×10 }.alignItems(a)`: legacy 200 wide, its
///   children at x = f·(200 − 30) and f·(200 − 50) — 0/85/170 and 0/75/150 for
///   `.flexStart`/`.center`/`.flexEnd` (f 0, ½, 1);
/// - a stretched `Row { 30×10; 50×20 }.justifyContent(j)`: its children at
///   x = f·(200 − 80) and that + 30 — 0/60/120 and 30/90/150.
///
/// Distinct child widths (practices shape 1), so an alignment applied to the wrong
/// box moves a literal. Every arm agrees.
///
/// Mutation that must redden it: **M1c** W aligned `.topLeading` whatever the child.
@MainActor
@Test func aStretchedContainersContentSitsByItsOwnAlignment() throws {
    let c = child(containerID, 1)
    var arms = 0
    for (align, f) in [(AlignItems.flexStart, Float(0)), (.center, 0.5), (.flexEnd, 1)] {
        let r = LayoutDifferential.compare(width: 300, height: 200) {
            Column { fixed(20, 10); Column { fixed(30, 10); fixed(50, 10) }.alignItems(align) }
                .alignItems(.stretch).width(px(200))
        }
        try #require(r.elements == 6, "column \(align): \(r.elements)")
        expectCorpusAgreement(r, "stretched column \(align)")
        #expect([c, child(c, 0), child(c, 1)].map { r.loweredBounds[$0] }
                == [bounds(0, 10, 200, 20), bounds(170 * f, 10, 30, 10), bounds(150 * f, 20, 50, 10)],
                "stretched column \(align)")
        arms += 1
    }
    for (justify, f) in [(JustifyContent.flexStart, Float(0)), (.center, 0.5), (.flexEnd, 1)] {
        let r = LayoutDifferential.compare(width: 300, height: 200) {
            Column { fixed(20, 10); Row { fixed(30, 10); fixed(50, 20) }.justifyContent(justify) }
                .alignItems(.stretch).width(px(200))
        }
        try #require(r.elements == 6, "row \(justify): \(r.elements)")
        expectCorpusAgreement(r, "stretched row \(justify)")
        #expect([c, child(c, 0), child(c, 1)].map { r.loweredBounds[$0] }
                == [bounds(0, 10, 200, 20), bounds(120 * f, 15, 30, 10), bounds(120 * f + 30, 10, 50, 20)],
                "stretched row \(justify)")
        arms += 1
    }
    try #require(arms == 6)
}

// MARK: - 1.3, 1.4 — the one-child elision, and W's own bounds

/// **1.3 — divergence pin** (`LR-AC`, stage-2 probe X9). `Column { M; 80×10 }
/// .alignItems(.stretch).width(200)` where M is a one-child **column** `Box` over
/// `Box().height(10)`: M is stretched to 200 on both sides (W). Inside M the child's
/// width is M's cross size, `auto`, and M's `stretch` is its default with exactly
/// one child and no declared cross size — the elision (stage 1's `LR-E` principle
/// 3): legacy stretches the child to **200**, lowered it keeps its own **0**, at
/// x 0 (M's content alignment is leading). **Corrected from the design's
/// spelling** (a row `Box`, whose child width is its main axis and so 0 on both
/// sides; record §21, lane 1).
///
/// The agreeing control: `Box { Text("x") }` alone (one child, no cross size: its
/// stretch is not shown by CSS either).
///
/// Mutation that must redden it: **M1d** the elision removed (the child reads 200).
@MainActor
@Test func aStretchedSingleChildContainerDoesNotStretchItsChild() throws {
    let r = LayoutDifferential.compare(width: 300, height: 200) {
        Column {
            Box { Box().height(px(10)).background(.accent) }.flexDirection(.column)
            fixed(80, 10)
        }
        .alignItems(.stretch).width(px(200))
    }
    try #require(r.elements == 5)
    #expect(r.unlowerable.isEmpty, "\(r.unlowerable)")
    let m = child(containerID, 0), inner = child(m, 0)
    #expect(r.legacyBounds[m] == bounds(0, 0, 200, 10))
    #expect(r.loweredBounds[m] == bounds(0, 0, 200, 10))
    try #require(r.legacyBounds[inner] != r.loweredBounds[inner])
    #expect(r.legacyBounds[inner] == bounds(0, 0, 200, 10))
    #expect(r.loweredBounds[inner] == bounds(0, 0, 0, 10))

    let control = LayoutDifferential.compare(width: 300, height: 200) { Box { Text("x") } }
    try #require(control.elements == 3)
    expectCorpusAgreement(control, "Box { Text }")
}

/// **1.4** (`LR-AG`; stage-2 probe X10). A stretched item is clamped by its own
/// `maxSize` and floored by its own `minSize` on the stretched axis — W carries
/// both. Children a `Box().width(20).maxHeight(25)`, b `Box().width(20).minHeight(60)`,
/// c `fixed(20, 10)`:
///
/// - in a `Row {…}.alignItems(.stretch).height(100)`: a 25, b 100, c 10, all at y 0;
/// - in the same row without a height, stretched to **40** by a sized two-child
///   grandparent: a 25, b **60** (its minimum beats the line and overflows the
///   row), c 10. The row itself is 40 on both sides while its content is 60 tall:
///   **W's minimum is 0 when none is declared** (`LR-AW`), CSS's stretched size,
///   where a bare `maxHeight: .infinity` frame never answers below its child (F3).
///
/// Every arm agrees. **Corrected from the design's literal** ("25 and 60" in a
/// 100-tall row, where CSS clamps the stretched 100 by the 60 minimum to 100;
/// record §21, lane 1).
///
/// Mutations that must redden it: **M1e** W drops `maxSize` (a reads 100 / 40);
/// **M1r** W's minimum left absent (the stretched arm's row reads 60).
@MainActor
@Test func aStretchedItemIsClampedByItsOwnMinimumAndMaximum() throws {
    @ElementBuilder func items() -> some ElementGroup {
        Box().width(px(20)).maxHeight(px(25)).background(.accent)
        Box().width(px(20)).minHeight(px(60)).background(.accent)
        fixed(20, 10)
    }
    let sized = LayoutDifferential.compare(width: 300, height: 200) {
        Row { items() }.alignItems(.stretch).height(px(100))
    }
    try #require(sized.elements == 5)
    expectCorpusAgreement(sized, "sized row")
    #expect([0, 1, 2].map { sized.loweredBounds[child(containerID, $0)] }
            == [bounds(0, 0, 20, 25), bounds(20, 0, 20, 100), bounds(40, 0, 20, 10)])

    let stretched = LayoutDifferential.compare(width: 300, height: 200) {
        Row { Row { items() }.alignItems(.stretch); fixed(10, 40) }.alignItems(.stretch).height(px(40))
    }
    try #require(stretched.elements == 7)
    expectCorpusAgreement(stretched, "row stretched to 40")
    let row = child(containerID, 0)
    #expect([row, child(row, 0), child(row, 1), child(row, 2)].map { stretched.loweredBounds[$0] }
            == [bounds(0, 0, 60, 40), bounds(0, 0, 20, 25), bounds(20, 0, 20, 60), bounds(40, 0, 20, 10)])
}

// MARK: - 1.5, 1.6 — alignSelf

/// **1.5** (`LR-AD`; stage-2 probe X5). A 300-wide `Column` (its centring default)
/// over a 40×10 with `.alignSelf(.flexStart)`, a 60×10 with `.flexEnd`, an 80×10
/// with `.stretch` (a declared width, so it sits at the start, as CSS's stretch of a
/// definite cross size does) and a 20×10 control with none: x 0, 240, 0 and 140,
/// at y 0, 10, 20, 30. Agrees.
///
/// Mutation that must redden it: **M1f** the alignment frame's factor always 0 (the
/// `.flexEnd` child reads x 0).
@MainActor
@Test func alignSelfPlacesOneChildOnTheCrossAxisOfADefiniteContainer() throws {
    let r = LayoutDifferential.compare(width: 400, height: 200) {
        Column {
            fixed(40, 10).alignSelf(.flexStart)
            fixed(60, 10).alignSelf(.flexEnd)
            fixed(80, 10).alignSelf(.stretch)
            fixed(20, 10)
        }
        .width(px(300))
    }
    try #require(r.elements == 6)
    expectCorpusAgreement(r, "alignSelf in a 300-wide column")
    #expect([0, 1, 2, 3].map { r.loweredBounds[child(containerID, $0)] }
            == [bounds(0, 0, 40, 10), bounds(240, 10, 60, 10), bounds(0, 20, 80, 10), bounds(140, 30, 20, 10)])
}

/// **1.6 — divergence pin** (`LR-AD`; stage-2 probe X7 against X6). `Row { Column {
/// a 100×10; b 20×10.alignSelf(.flexStart) } }` in a 300×100 harness root. The row
/// offers the column its whole 300 (a group of one); the lowered alignment frame
/// around b is greedy and fills it, so the column is **300** wide and centres a at
/// x 100. The legacy column is fit-content, **100**, a at x 0. b sits at x 0 on
/// both sides.
///
/// Mutation that must redden it: **M1g** the alignment frame not greedy (the
/// lowered column reads 100).
@MainActor
@Test func anAlignSelfWrapperFillsAnIndefiniteContainerWhereCSSHugs() throws {
    let r = LayoutDifferential.compare(width: 300, height: 100) {
        Row { Column { fixed(100, 10); fixed(20, 10).alignSelf(.flexStart) } }
    }
    try #require(r.elements == 5)
    #expect(r.unlowerable.isEmpty, "\(r.unlowerable)")
    let column = child(containerID, 0)
    try #require(r.legacyBounds[column] != r.loweredBounds[column])
    #expect([column, child(column, 0), child(column, 1)].map { r.legacyBounds[$0] }
            == [bounds(0, 0, 100, 20), bounds(0, 0, 100, 10), bounds(0, 10, 20, 10)])
    #expect([column, child(column, 0), child(column, 1)].map { r.loweredBounds[$0] }
            == [bounds(0, 0, 300, 20), bounds(100, 0, 100, 10), bounds(0, 10, 20, 10)])
}

// MARK: - 1.7, 1.8, 1.9 — fills, frame layers, stacks

/// **1.7 — divergence pin** (`LR-AC`; stage-2 probe X4 against X3). `Row { Column {
/// a 30×10; b Box().height(10) }.alignItems(.stretch) }` in a 200×100 harness root:
/// the row offers the column 200, b's greedy W fills it, and the lowered column is
/// **200** wide with b 200. The legacy column is fit-content: **30**, b stretched to
/// 30. (Spec §7's cause R in isolation.)
///
/// Mutation that must redden it: **M1h** stretch made to fill only in a parent with a
/// declared cross size (b reads 0, the column 30).
@MainActor
@Test func aStretchedItemInsideAHuggingItemFillsItsProposal() throws {
    let r = LayoutDifferential.compare(width: 200, height: 100) {
        Row { Column { fixed(30, 10); Box().height(px(10)).background(.accent) }.alignItems(.stretch) }
    }
    try #require(r.elements == 5)
    #expect(r.unlowerable.isEmpty, "\(r.unlowerable)")
    let column = child(containerID, 0)
    try #require(r.legacyBounds[column] != r.loweredBounds[column])
    #expect([column, child(column, 1)].map { r.legacyBounds[$0] } == [bounds(0, 0, 30, 20), bounds(0, 10, 30, 10)])
    #expect([column, child(column, 1)].map { r.loweredBounds[$0] } == [bounds(0, 0, 200, 20), bounds(0, 10, 200, 10)])
}

/// **1.8** (`MC-Q` finding 7; stage-2 probe X8/X9). A `.frame` layer with a `nil`
/// axis is an `auto` item on that axis and is stretched like any other, its
/// content placed by the frame's own alignment (centre):
///
/// - `Box { 10×10.frame(width: 30); 20×40 }.height(40)`: the layer (0, 0) 30×40, its
///   child at (10, 15);
/// - the column transpose, `Box { 10×10.frame(height: 30); 40×20 }` column, width 40:
///   the layer 40×30, its child at (15, 10);
/// - a frame declaring both axes, `.frame(width: 30, height: 20)` in the first shape,
///   is not stretched: the layer (0, 0) 30×20, its child at (10, 5).
///
/// Every arm agrees.
///
/// Mutation that must redden it: **M1i** frame-layer records skipped by the parent
/// (the first layer reads 30×10 at y 15).
@MainActor
@Test func aNilAxisFrameLayerUnderAStretchingContainerIsStretched() throws {
    let layer = child(containerID, 0)
    let nilHeight = LayoutDifferential.compare(width: 300, height: 200) {
        Box { fixed(10, 10).frame(width: px(30)).background(.accent); fixed(20, 40) }.height(px(40))
    }
    try #require(nilHeight.elements == 5)
    expectCorpusAgreement(nilHeight, "nil-height frame layer")
    #expect([layer, child(layer, 0)].map { nilHeight.loweredBounds[$0] } == [bounds(0, 0, 30, 40), bounds(10, 15, 10, 10)])

    let nilWidth = LayoutDifferential.compare(width: 300, height: 200) {
        Box { fixed(10, 10).frame(height: px(30)).background(.accent); fixed(40, 20) }
            .flexDirection(.column).width(px(40))
    }
    try #require(nilWidth.elements == 5)
    expectCorpusAgreement(nilWidth, "nil-width frame layer")
    #expect([layer, child(layer, 0)].map { nilWidth.loweredBounds[$0] } == [bounds(0, 0, 40, 30), bounds(15, 10, 10, 10)])

    let both = LayoutDifferential.compare(width: 300, height: 200) {
        Box { fixed(10, 10).frame(width: px(30), height: px(20)).background(.accent); fixed(20, 40) }.height(px(40))
    }
    try #require(both.elements == 5)
    expectCorpusAgreement(both, "frame layer declaring both axes")
    #expect([layer, child(layer, 0)].map { both.loweredBounds[$0] } == [bounds(0, 0, 30, 20), bounds(10, 5, 10, 10)])
}

/// **1.9** (`LR-AC`; stage-2 probe X16 against X15). A stack parent stretches per
/// axis — `justifyItems` horizontally, `alignItems` vertically — and ignores its
/// children's flex fields, which it consumes (so none is `…unconsumed`):
///
/// - a 100×60 `Stack` with `nil` items over `Box().width(20)`, `Box().height(10)` and
///   `Box()`: (0, 0) 20×60, 100×10 and 100×60;
/// - a `.center` `Stack` over 40×40 and a 10×10 declaring `flexGrow(1)`,
///   `flexShrink(0)` and `alignSelf(.flexEnd)`: the small box at (15, 15), the
///   report empty;
/// - stage 1's 4.1 stretch arms, moved here: a `Box` with `display: .stack` and
///   `nil` items over 20×10 and 10×30 (both at (0, 0)); a `Stack` with
///   `.alignItems(.stretch)` over the same (a (0, 0), b (5, 0));
///
/// all agreeing; and the **divergence arm** (X16): `Row { Stack(nil items) { 30×10;
/// Box().height(10) } }` in a 200×100 root — legacy stack 30 wide (fit-content, b
/// stretched to 30), lowered **200** (the overlay proposes the row's offer and b's
/// greedy W fills it).
///
/// Mutations that must redden it: **M1j** the overlay lowers `alignSelf` (the small
/// box moves to the end); **M1j′** a stack parent's stretch not greedy (the X16
/// arm and the first arm).
@MainActor
@Test func aStackStretchesByItsItemsAlignmentAndIgnoresTheirFlexFields() throws {
    var arms = 0
    let sized = LayoutDifferential.compare(width: 300, height: 200) {
        stretchingStack {
            Box().width(px(20)).background(.accent)
            Box().height(px(10)).background(.accent)
            Box().background(.accent)
        }
        .width(px(100)).height(px(60))
    }
    try #require(sized.elements == 5)
    expectCorpusAgreement(sized, "stretching stack")
    #expect([0, 1, 2].map { sized.loweredBounds[child(containerID, $0)] }
            == [bounds(0, 0, 20, 60), bounds(0, 0, 100, 10), bounds(0, 0, 100, 60)])
    arms += 1

    let ignoring = LayoutDifferential.compare(width: 300, height: 200) {
        Stack(alignment: .center) {
            fixed(40, 40)
            fixed(10, 10).flexGrow(1).flexShrink(0).alignSelf(.flexEnd)
        }
    }
    try #require(ignoring.elements == 4)
    expectCorpusAgreement(ignoring, "a stack ignores its children's flex fields")
    #expect(ignoring.loweredBounds[child(containerID, 1)] == bounds(15, 15, 10, 10))
    arms += 1

    var stackStyle = Style()
    stackStyle.display = .stack
    let boxStack = LayoutDifferential.compare(width: 300, height: 200) {
        Box(style: stackStyle) { fixed(20, 10); fixed(10, 30) }
    }
    try #require(boxStack.elements == 4)
    expectCorpusAgreement(boxStack, "Box with display: .stack")
    #expect([0, 1].map { boxStack.loweredBounds[child(containerID, $0)] } == [bounds(0, 0, 20, 10), bounds(0, 0, 10, 30)])
    arms += 1

    let declaredStretch = LayoutDifferential.compare(width: 300, height: 200) {
        Stack { fixed(20, 10); fixed(10, 30) }.alignItems(.stretch)
    }
    try #require(declaredStretch.elements == 4)
    expectCorpusAgreement(declaredStretch, "Stack alignItems stretch")
    #expect([0, 1].map { declaredStretch.loweredBounds[child(containerID, $0)] }
            == [bounds(0, 0, 20, 10), bounds(5, 0, 10, 30)])
    arms += 1

    let fill = LayoutDifferential.compare(width: 200, height: 100) {
        Row { stretchingStack { fixed(30, 10); Box().height(px(10)).background(.accent) } }
    }
    try #require(fill.elements == 5)
    #expect(fill.unlowerable.isEmpty, "\(fill.unlowerable)")
    let stack = child(containerID, 0)
    try #require(fill.legacyBounds[stack] != fill.loweredBounds[stack])
    #expect([stack, child(stack, 1)].map { fill.legacyBounds[$0] } == [bounds(0, 0, 30, 10), bounds(0, 0, 30, 10)])
    #expect([stack, child(stack, 1)].map { fill.loweredBounds[$0] } == [bounds(0, 0, 200, 10), bounds(0, 0, 200, 10)])
    arms += 1
    try #require(arms == 5)
}

// MARK: - 1.10, 1.11, 1.12 — the alias, native work, the centring default

/// **1.10** (`LR-AB` item 3). The item frame **is** the element's rect for every
/// reader: in a 120-wide `Column {…}.alignItems(.stretch)`, a stretched `Box` with a
/// background, an `onClick` and an accessibility label (its rect is its
/// decoration, its hitbox and its accessibility frame) above a stretched
/// multi-line `Text` (its rect is its glyph origin, and its measured width the
/// width its glyphs wrap at). Agrees in every observation, the glyph scene
/// included, and the text wraps to more than one line. A second arm stretches
/// `Text("Wii il")` in a 4-wide column, below its widest glyph, where the width
/// paint wraps at is visible in the glyph scene (the first arm cannot see it).
///
/// Mutations that must redden it: **M1a** W not aliased; **M1k** the alias resolved
/// in `Frame.bounds(of:)` but not `PaintPass.measuredWidth(of:)`.
@MainActor
@Test func theBoundsAliasReachesDecorationHitboxesAccessibilityAndTextWrap() throws {
    let tree = { @MainActor in
        Column {
            Box().height(px(20)).background(.accent).onClick {}.accessibilityLabel("wide")
            Text(longString)
        }
        .alignItems(.stretch).width(px(120))
    }
    let legacy = LayoutDifferential.render(authority: .legacy, width: 300, height: 200) { tree() }
    try #require(legacy.scene.glyphs.count >= longString.count - 6)
    try #require(legacy.hitboxes.count == 1)
    let r = LayoutDifferential.compare(width: 300, height: 200) { tree() }
    try #require(r.elements == 4)
    expectCorpusAgreement(r, "stretched decorated box and text")
    #expect(r.loweredBounds[child(containerID, 0)] == bounds(0, 0, 120, 20))
    let text = try #require(r.loweredBounds[child(containerID, 1)])
    #expect(text.size.width == px(120) && text.size.height > px(20), "\(text)")

    // The measured-width half. At 120 the leaf's answer (its widest line) re-wraps
    // to the same lines as W's 120 — greedy breaking is unchanged by narrowing to
    // the widest line — so the arm above cannot see which width `Text.paint` asks.
    // Below a glyph's width it can: in a 4-wide stretched column the leaf answers
    // its widest glyph, wider than W, and wrapping there puts two narrow glyphs on
    // one line where 4 puts one per line (measured: M1k made this arm's scenes
    // differ at 4 and 6, not at 9; record §21, lane 1).
    let narrowTree = { @MainActor in
        Column { fixed(4, 10); Text("Wii il") }.alignItems(.stretch).width(px(4))
    }
    let narrowLegacy = LayoutDifferential.render(authority: .legacy, width: 300, height: 200) { narrowTree() }
    try #require(narrowLegacy.scene.glyphs.count == 5)
    let narrow = LayoutDifferential.compare(width: 300, height: 200) { narrowTree() }
    try #require(narrow.elements == 4)
    expectCorpusAgreement(narrow, "stretched text narrower than a glyph")
    #expect(narrow.loweredBounds[child(containerID, 1)]?.size.width == px(4))
}

/// **1.11** (`SA-M`'s method). `Column { Row { a; b }; Row { c; d }; Box { e } }
/// .alignItems(.stretch)` in a 200×100 harness root under the proposal authority:
/// a `Box().height(10)`, b `.height(20)`, c `.height(10)`, d `.height(30)` (auto
/// width, in centring rows, so 0 wide), e `Box().width(10)` (auto height). Literals
/// **derived by hand before the first run**, bookkeeping checked against a
/// transcription of the kernel's rules that reproduces 5.7's 118/94/4 (record §21,
/// lane 1).
///
/// **The registered tree (19 nodes).** Each leaf is a 0×0 leaf `L` in a frame `F`
/// declaring its one axis (10). Each row is a horizontal stack (`S1` over `Fa, Fb`,
/// `S2` over `Fc, Fd`, aligned `.leading`); `Box { e }` a horizontal stack `SB`
/// over `Fe` — one child with no declared cross size, so e's stretch is **elided**
/// (`LR-AC`) and `Fe` gets no W. The column is a vertical stack `SC` over the three
/// item frames `W1`, `W2` (`.leading`, a row's content alignment) and `W3`
/// (`.topLeading`), each `frame(minWidth: 0, maxWidth: ∞)`. The harness root is an
/// overlay `O` in a fixed 200×100 frame `R`. 10 + 3 + 3 + 1 + 2 = **19**.
///
/// **Measurement: 75 misses, 24 hits, 15 calls.** `R`, `O`, `SC` at (200, 100): 3
/// misses. `SC` (main 100, a group of three) probes each W at (200, ∞) and (200, 0),
/// then serves them in order — every flexibility is 0 — offering 100/3, 80/2 and 50.
/// - `W1` at (200, c), for c ∈ {∞, 0, 33.3}: `W1` and `S1` miss; `S1` (main 200, two
///   members) probes `Fa`, `Fb` at (∞, c) and (0, c) and offers `Fa` 100 and `Fb` 200:
///   6 frame misses, whose leaves are keyed without c — `La` at (∞, 10), (0, 10),
///   (100, 10), `Lb` likewise at 20 — so 6 leaf misses and 6 calls at c = ∞ and 6
///   leaf hits at each other c. **30 misses, 12 hits, 6 calls.**
/// - `W2` the same: **30, 12, 6.**
/// - `W3` at c ∈ {∞, 0, 50}: `W3`, `SB`, `Fe` at (200, c) and `Le` at (10, c) miss, a
///   call each: **12 misses, 3 calls.**
///
/// **Placement: 17 misses, 50 hits, 0 calls.** `R` re-asks `O` (1 hit) and places it
/// at its answer's 200×50; `O` measures `SC` at (200, 50) (1 miss), whose solve
/// probes the three Ws (6 hits), offers `W1` 50/3 and `W2` 15 (8 misses and 6 leaf
/// hits each, as above) and `W3` 0 (1 hit); placing `SC` re-runs that solve (9
/// hits); `W1` and `W2` each re-ask their stack (1), re-solve it (6) and re-ask two
/// leaves (2): 9 hits each; `W3` re-asks `SB`, `Fe` and `Le`: 3 hits.
///
/// **Totals: 92 misses, 74 hits, 15 calls.** Placement as derived: the column
/// (0, 0) 200×50, the rows 200×20 at y 0 and 200×30 at y 20 (their W rects), `Box
/// { e }` 200×0 at y 50 and e 10×0.
///
/// Mutation that must redden it: **M1l** W registered also for an elided single
/// child (20 nodes; every figure moves).
@MainActor
@Test func aStretchedBranchingTreeRegistersAHandDerivedAmountOfNativeWork() throws {
    let frame = LayoutDifferential.render(authority: .proposal, width: 200, height: 100) {
        Column {
            Row { Box().height(px(10)); Box().height(px(20)) }
            Row { Box().height(px(10)); Box().height(px(30)) }
            Box { Box().width(px(10)) }
        }
        .alignItems(.stretch)
    }
    #expect(frame.unlowerableFields.isEmpty, "\(frame.unlowerableFields)")
    #expect(frame.tree.nodeCount == 19, "nodeCount \(frame.tree.nodeCount)")
    let work = frame.tree.lastNativeLayoutWork
    #expect(work.cacheMisses == 92, "cacheMisses")
    #expect(work.cacheHits == 74, "cacheHits")
    #expect(work.measureCalls == 15, "measureCalls")
    let column = containerID
    #expect([column, child(column, 0), child(column, 1), child(column, 2), child(child(column, 2), 0)]
                .map { frame.elementBounds[$0] }
            == [bounds(0, 0, 200, 50), bounds(0, 0, 200, 20), bounds(0, 20, 200, 30), bounds(0, 50, 200, 0),
                bounds(0, 50, 10, 0)])
}

/// **1.12 — characterization** (EP-8, `LR-AC`). `Row` and `Column` centre by default
/// and so stretch nothing: `Row { Box().width(20); 20×40 }.height(100)` — the auto
/// child 20×0 at (0, 50), the fixed one at (20, 30) — and the transpose `Column {
/// Box().height(20); 40×20 }.width(100)` — the auto child 0×20 at (50, 0). No W is
/// registered: 8 native nodes each (the harness root's overlay and frame, the
/// stack and its size frame, two leaves in their frames). Agrees.
///
/// The report arm (scratch R2's S4): `Box().width(20).maxHeight(25)` in that `Row`
/// reports `box.maxSize` — a maximum on a non-greedy axis (`LR-AG`).
///
/// Mutation that must redden it: **M1o** stretch applied for `.center` (the auto
/// child fills 100; 9 nodes).
@MainActor
@Test func theCentringDefaultOfRowAndColumnStretchesNothing() throws {
    let row = LayoutDifferential.compare(width: 300, height: 200) {
        Row { Box().width(px(20)).background(.accent); fixed(20, 40) }.height(px(100))
    }
    try #require(row.elements == 4)
    expectCorpusAgreement(row, "centring row")
    #expect([0, 1].map { row.loweredBounds[child(containerID, $0)] } == [bounds(0, 50, 20, 0), bounds(20, 30, 20, 40)])
    let rowFrame = LayoutDifferential.render(authority: .proposal, width: 300, height: 200) {
        Row { Box().width(px(20)).background(.accent); fixed(20, 40) }.height(px(100))
    }
    #expect(rowFrame.tree.nodeCount == 8)

    let column = LayoutDifferential.compare(width: 300, height: 200) {
        Column { Box().height(px(20)).background(.accent); fixed(40, 20) }.width(px(100))
    }
    try #require(column.elements == 4)
    expectCorpusAgreement(column, "centring column")
    #expect(column.loweredBounds[child(containerID, 0)] == bounds(50, 0, 0, 20))
    let columnFrame = LayoutDifferential.render(authority: .proposal, width: 300, height: 200) {
        Column { Box().height(px(20)).background(.accent); fixed(40, 20) }.width(px(100))
    }
    #expect(columnFrame.tree.nodeCount == 8)

    #expect(report { Row { Box().width(px(20)).maxHeight(px(25)); fixed(20, 40) }.height(px(100)) }
            == [field(.box, "maxSize")])
}

// MARK: - 1.13, 1.14, 1.15 — records no lowered container consumes, and the free-space re-check

/// **1.13** (`LR-AQ`). An item field on a record **no lowered container consumes**
/// reports `<site>.<field>.unconsumed` when the root's registration returns.
///
/// - `Box().width(20).height(10).flexGrow(1)` directly under each proposal container
///   — `HStack`, `VStack`, `ZStack`, `ProposalFrame`, the `.padding` `ModifiedContent`,
///   the `.overlay` primary and overlay slots, a `ProposalLayoutContainer`, a
///   `ProposalScrollView` — reports exactly `[box.flexGrow.unconsumed]`;
/// - under `HStack`, one arm each: `.minWidth(5)` → `box.minSize.unconsumed`,
///   `.maxWidth(50)` → `box.maxSize.unconsumed`, `.alignSelf(.flexEnd)` →
///   `box.alignSelf.unconsumed`, `.flexShrink(0)` → `box.flexShrink.unconsumed`,
///   `.flexBasis(0)` → `box.flexBasis.unconsumed`, `.margin(3)` →
///   `box.margin.unconsumed`; a `Text` with `.flexGrow(1)` → `text.flexGrow.unconsumed`;
/// - a legacy `ScrollView` over the same child **consumes** the record and reports
///   nothing, since stage 3's lowering (`LR-BB`): its content node goes through
///   `lowerLegacyNode`, which consumes every child record it receives exactly as
///   a `Row` does. Until then the arm read `[scrollView.noLowering]`, the site
///   marking the record it received;
/// - the control `Row { same }` consumes the record: no `…unconsumed` entry, and
///   since lane 2 no entry at all (lane 1 reported `box.flexGrow` there);
/// - **the frame's root** (a `Frame` rendering the element itself, no harness):
///   `.maxWidth(600)` and `.minWidth(50)` always report (CSS applies them to a root);
///   `.flexGrow(1)`, `.flexShrink(0)`, `.flexBasis(0)` and `.alignSelf(.flexEnd)` each
///   first compare the legacy root with the field and without it — the legacy root
///   ignores it exactly when the two rects are equal — and assert **no report and an
///   unchanged lowered root** where it is ignored, the `…unconsumed` report
///   otherwise. The four comparisons are recorded as literals (all ignored, measured
///   on the first run; record §21, lane 1).
///
/// Mutations that must redden it: **M1m** the unconsumed check removed; **M1m′** the
/// `noLowering` sites do not mark (the `ScrollView` arm).
@MainActor
@Test func anItemFieldNoLoweredContainerConsumesIsReportedByName() throws {
    typealias Arm = (name: String, entries: [UnlowerableField], expected: [UnlowerableField])
    var arms: [Arm] = []
    func grow() -> Box<EmptyGroup> { fixed(20, 10).flexGrow(1) }
    let unconsumed = [field(.box, "flexGrow.unconsumed")]
    arms.append(("HStack", report { HStack { LegacyUnderProposal(grow()) } }, unconsumed))
    arms.append(("VStack", report { VStack { LegacyUnderProposal(grow()) } }, unconsumed))
    arms.append(("ZStack", report { ZStack { LegacyUnderProposal(grow()) } }, unconsumed))
    arms.append(("ProposalFrame", report { ProposalFrame(width: px(50), height: px(50)) { LegacyUnderProposal(grow()) } },
                 unconsumed))
    arms.append(("padding ModifiedContent", report { LegacyUnderProposal(grow()).padding(Edges(all: px(4))) }, unconsumed))
    arms.append(("overlay primary",
                 report { LegacyUnderProposal(grow()).overlay { Rectangle(width: px(5), height: px(5)) } }, unconsumed))
    arms.append(("overlay slot",
                 report { Rectangle(width: px(50), height: px(50)).overlay { LegacyUnderProposal(grow()) } }, unconsumed))
    arms.append(("ProposalLayoutContainer", report { ProposalLayoutContainer(AtOrigin()) { LegacyUnderProposal(grow()) } },
                 unconsumed))
    arms.append(("ProposalScrollView", report { ProposalScrollView(.vertical) { LegacyUnderProposal(grow()) } }, unconsumed))

    arms.append(("HStack minWidth", report { HStack { LegacyUnderProposal(fixed(20, 10).minWidth(px(5))) } },
                 [field(.box, "minSize.unconsumed")]))
    arms.append(("HStack maxWidth", report { HStack { LegacyUnderProposal(fixed(20, 10).maxWidth(px(50))) } },
                 [field(.box, "maxSize.unconsumed")]))
    arms.append(("HStack alignSelf", report { HStack { LegacyUnderProposal(fixed(20, 10).alignSelf(.flexEnd)) } },
                 [field(.box, "alignSelf.unconsumed")]))
    arms.append(("HStack flexShrink", report { HStack { LegacyUnderProposal(fixed(20, 10).flexShrink(0)) } },
                 [field(.box, "flexShrink.unconsumed")]))
    arms.append(("HStack flexBasis", report { HStack { LegacyUnderProposal(fixed(20, 10).flexBasis(px(0))) } },
                 [field(.box, "flexBasis.unconsumed")]))
    arms.append(("HStack margin", report { HStack { LegacyUnderProposal(fixed(20, 10).margin(px(3))) } },
                 [field(.box, "margin.unconsumed")]))
    arms.append(("HStack Text flexGrow", report { HStack { LegacyUnderProposal(Text("ab").flexGrow(1)) } },
                 [field(.text, "flexGrow.unconsumed")]))

    arms.append(("legacy ScrollView", report { ScrollView { grow() } }, []))
    arms.append(("control Row", report { Row { grow() } }, []))

    // The frame's root.
    func rootFrame<E: Element>(_ authority: LayoutAuthority, _ element: E) -> Frame {
        var root = element
        let frame = Frame(contentSize: Size(width: px(100), height: px(100)), scaleFactor: 1,
                          layoutAuthority: authority, reportsUnlowerableFields: authority == .proposal,
                          recordsElementBounds: true)
        frame.render(&root)
        return frame
    }
    let plain = fixed(20, 10)
    for (name, element, expected) in [("root maxWidth", plain.maxWidth(px(600)), "maxSize.unconsumed"),
                                      ("root minWidth", plain.minWidth(px(50)), "minSize.unconsumed")] {
        arms.append((name, rootFrame(.proposal, element).unlowerableFields, [field(.box, expected)]))
    }
    var ignoredByTheLegacyRoot: [String: Bool] = [:]
    for (name, element, fieldName) in [("flexGrow", plain.flexGrow(1), "flexGrow"),
                                       ("flexShrink", plain.flexShrink(0), "flexShrink"),
                                       ("flexBasis", plain.flexBasis(px(0)), "flexBasis"),
                                       ("alignSelf", plain.alignSelf(.flexEnd), "alignSelf")] {
        let legacyWith = rootFrame(.legacy, element).elementBounds[rootID]
        let legacyWithout = rootFrame(.legacy, plain).elementBounds[rootID]
        let ignored = legacyWith != nil && legacyWith == legacyWithout
        ignoredByTheLegacyRoot[name] = ignored
        let lowered = rootFrame(.proposal, element)
        if ignored {
            arms.append(("root \(name)", lowered.unlowerableFields, []))
            #expect(lowered.elementBounds[rootID] == rootFrame(.proposal, plain).elementBounds[rootID], "root \(name)")
        } else {
            arms.append(("root \(name)", lowered.unlowerableFields, [field(.box, "\(fieldName).unconsumed")]))
        }
    }
    #expect(ignoredByTheLegacyRoot == ["flexGrow": true, "flexShrink": true, "flexBasis": true, "alignSelf": true],
            "\(ignoredByTheLegacyRoot)")

    try #require(arms.count == 24)
    for arm in arms {
        #expect(arm.entries == arm.expected, "\(arm.name): \(arm.entries)")
    }
}

/// **1.14** (`LR-AR`, the stretch half). A W greedy on a child flex container's own
/// **main** axis gives an unsized `space-*` container free space that stage 1's
/// flex-start lowering does not distribute. `Column { Row { 20×10; 20×10 }
/// .justifyContent(j); 200×10 }.alignItems(.stretch).width(200)`:
///
/// - `.spaceBetween`, `.spaceAround`, `.spaceEvenly`: the report is exactly
///   `[box.justifyContent.<case>]`, at the inner `Row`'s site;
/// - controls `.center` and `.flexEnd` agree, the second child at x 100 and 180
///   (W carries the main factor).
///
/// Mutation that must redden it: **M1p** the re-check removed (the three reports read
/// empty).
@MainActor
@Test func aStretchedUnsizedSpaceDistributionContainerIsReported() throws {
    func tree(_ justify: JustifyContent) -> some ElementGroup {
        Column { Row { fixed(20, 10); fixed(20, 10) }.justifyContent(justify); fixed(200, 10) }
            .alignItems(.stretch).width(px(200))
    }
    var arms = 0
    for (justify, name) in [(JustifyContent.spaceBetween, "spaceBetween"), (.spaceAround, "spaceAround"),
                            (.spaceEvenly, "spaceEvenly")] {
        #expect(report { tree(justify) } == [field(.box, "justifyContent.\(name)")], "\(name)")
        arms += 1
    }
    let row = child(containerID, 0)
    for (justify, x) in [(JustifyContent.center, Float(100)), (.flexEnd, 180)] {
        let r = LayoutDifferential.compare(width: 300, height: 200) { tree(justify) }
        try #require(r.elements == 6, "\(justify)")
        expectCorpusAgreement(r, "\(justify)")
        #expect(r.loweredBounds[child(row, 1)] == bounds(x, 0, 20, 10), "\(justify)")
        arms += 1
    }
    try #require(arms == 5)
}

/// **1.15 — divergence pin** (`LR-AR`; scratch R2's S3, stage-2 probe X14 against
/// X13). `Column { 100×10; Box().width(20).height(10).alignSelf(.flexEnd).padding(8) }`
/// in a 300×100 harness root. The `.padding` layer is a one-child **row**, so the
/// child's `alignSelf` is vertical; it is declared, so it is lowered, not elided:
/// the lowered alignment frame fills the layer's offer — the layer **36×90**, the
/// child at (40, 82). Legacy: the layer 36×26 at (32, 10), the child at (40, 18),
/// `alignSelf` with no free space to show.
///
/// Mutation that must redden it: **M1q** `alignSelf` elided in a one-child container
/// (lowered reads as legacy).
@MainActor
@Test func anAlignSelfInsideAOneChildWrapperFillsTheWrapperWhereCSSIgnoresIt() throws {
    let r = LayoutDifferential.compare(width: 300, height: 100) {
        Column { fixed(100, 10); fixed(20, 10).alignSelf(.flexEnd).padding(px(8)) }
    }
    try #require(r.elements == 5)
    #expect(r.unlowerable.isEmpty, "\(r.unlowerable)")
    let layer = child(containerID, 1), inner = child(layer, 0)
    try #require(r.legacyBounds[layer] != r.loweredBounds[layer])
    #expect([layer, inner].map { r.legacyBounds[$0] } == [bounds(32, 10, 36, 26), bounds(40, 18, 20, 10)])
    #expect([layer, inner].map { r.loweredBounds[$0] } == [bounds(32, 10, 36, 90), bounds(40, 82, 20, 10)])
}

// MARK: - Stage 2, lane 2 — the main axis (spec §6 lane 2; rulings LR-AE, LR-AF, LR-AG, LR-AR, LR-AS)
//
// **Red before**: every test below was run on lane 1's lowering (`25fd9fb`), where
// `flexGrow`, `flexShrink`, `flexBasis` and a `minSize`/`maxSize` off a stretched
// axis are still reported by the parent at the child's site (record §21, lane 2).

/// A 13pt system-font shaping cache and font, the lowered and legacy `Text`'s
/// default (`LR-F`: a rect a text decides is derived from the cache, not a literal).
@MainActor
private func systemFont(_ size: Double = 13) -> (ShapingCache, ResolvedFont) {
    let cache = ShapingCache()
    return (cache, cache.resolveFont(family: nil, size: size))
}

/// **2.1** (`LR-AE`; stage-2 probe F1). A grower beside a rigid sibling takes the
/// remaining main space: under the proposal authority a greedy main-axis item frame
/// W, aliased as the grower's rect, served after the rigid sibling. Parents `Row(gap:
/// g) { 40×10; G }.width(300)` and the transpose `Column(gap: g) { 10×40; G
/// }.height(300)`, g ∈ {0, 12}, × growers G:
///
/// - a childless `Box` (a 10 cross size): main extent 260 − g at 40 + g;
/// - `Text("ab")`: the same main extent (its glyphs are one line at either width);
/// - `Row { 10×10; 20×10 }.justifyContent(.flexEnd)`: the same, its children at the
///   main end of the grown box — in the row parent at x 270 and 280 (W carries the
///   row's main factor); in the column parent the grown row is 30 wide and its
///   children sit on its vertical centre, y 40 + g + (260 − g − 10)/2 (W carries the
///   row's cross factor).
///
/// Every arm agrees in every observation.
///
/// Mutation that must redden it: **M2a** W greedy on the cross axis instead.
@MainActor
@Test func aGrowingChildTakesTheRemainingMainSpace() throws {
    enum Grower: CaseIterable { case box, text, row }
    var arms = 0
    for isRow in [true, false] {
        for gap: Float in [0, 12] {
            for grower in Grower.allCases {
                let name = "\(isRow ? "Row" : "Column") gap \(gap) \(grower)"
                func g() -> AnyElement {
                    switch grower {
                    case .box: AnyElement(isRow ? Box().height(px(10)).flexGrow(1).background(.accent)
                                                : Box().width(px(10)).flexGrow(1).background(.accent))
                    case .text: AnyElement(Text("ab").flexGrow(1))
                    case .row: AnyElement(Row { fixed(10, 10); fixed(20, 10) }.justifyContent(.flexEnd).flexGrow(1))
                    }
                }
                let r = LayoutDifferential.compare(width: 400, height: 400) {
                    isRow ? AnyElement(Row(gap: px(gap)) { fixed(40, 10); g() }.width(px(300)))
                          : AnyElement(Column(gap: px(gap)) { fixed(10, 40); g() }.height(px(300)))
                }
                try #require(r.elements == (grower == .row ? 6 : 4), "\(name): \(r.elements)")
                expectCorpusAgreement(r, name)
                let grown = try #require(r.loweredBounds[child(containerID, 1)])
                if isRow {
                    #expect(grown.origin.x == px(40 + gap) && grown.size.width == px(260 - gap), "\(name): \(grown)")
                } else {
                    #expect(grown.origin.y == px(40 + gap) && grown.size.height == px(260 - gap), "\(name): \(grown)")
                }
                if grower == .row {
                    let inner = child(containerID, 1)
                    let placed = [0, 1].map { r.loweredBounds[child(inner, $0)] }
                    if isRow {
                        #expect(placed == [bounds(270, 0, 10, 10), bounds(280, 0, 20, 10)], "\(name): \(placed)")
                    } else {
                        let y = 40 + gap + (260 - gap - 10) / 2
                        #expect(placed == [bounds(0, y, 10, 10), bounds(10, y, 20, 10)], "\(name): \(placed)")
                    }
                }
                arms += 1
            }
        }
    }
    try #require(arms == 12)
}

/// **2.2 — divergence pin** (`LR-AE`; stage-2 probes F2, F3 against control F0; F4,
/// F8). Two growers share the surplus **equally** under the proposal authority, where
/// CSS (`flex-basis: auto`) adds equal shares to their bases. `Row { a.flexGrow(1);
/// b.flexGrow(1) }.width(300)`, a and b fixed 10 tall:
///
/// - widths 100 and 20: legacy 190 / 110 (bases + 90 each), lowered **150 / 150**
///   (F2);
/// - widths 200 and 20: legacy 240 / 60, lowered **200 / 100** (F3: a greedy frame
///   with no minimum never answers below its child);
/// - both arms with `.flexBasis(0).minWidth(0)` on each: **150 / 150** on both
///   sides (CSS's zero basis with its minimum removed; F4/F8's minimum presence) —
///   the declared width stays on the element's own frame, inside W.
///
/// Mutation that must redden it: **M2b** W given a main minimum of 0 without a
/// declared minimum (the 200/20 arm reads 150/150).
@MainActor
@Test func growingSiblingsShareTheSurplusEquallyWhereCSSAddsItToTheirBases() throws {
    let a = child(containerID, 0), b = child(containerID, 1)
    for (wa, legacyA, loweredA) in [(Float(100), Float(190), Float(150)), (200, 240, 200)] {
        let r = LayoutDifferential.compare(width: 400, height: 100) {
            Row {
                Box().width(px(wa)).height(px(10)).flexGrow(1).background(.accent)
                Box().width(px(20)).height(px(10)).flexGrow(1).background(.accent)
            }
            .width(px(300))
        }
        try #require(r.elements == 4)
        #expect(r.unlowerable.isEmpty, "\(wa): \(r.unlowerable)")
        try #require(r.legacyBounds[a] != r.loweredBounds[a], "\(wa)")
        #expect([a, b].map { r.legacyBounds[$0] }
                == [bounds(0, 0, legacyA, 10), bounds(legacyA, 0, 300 - legacyA, 10)], "\(wa) legacy")
        #expect([a, b].map { r.loweredBounds[$0] }
                == [bounds(0, 0, loweredA, 10), bounds(loweredA, 0, 300 - loweredA, 10)], "\(wa) lowered")

        let zero = LayoutDifferential.compare(width: 400, height: 100) {
            Row {
                Box().width(px(wa)).height(px(10)).flexGrow(1).flexBasis(px(0)).minWidth(px(0)).background(.accent)
                Box().width(px(20)).height(px(10)).flexGrow(1).flexBasis(px(0)).minWidth(px(0)).background(.accent)
            }
            .width(px(300))
        }
        try #require(zero.elements == 4)
        expectCorpusAgreement(zero, "\(wa) zero basis, minimum 0")
        #expect([a, b].map { zero.loweredBounds[$0] } == [bounds(0, 0, 150, 10), bounds(150, 0, 150, 10)], "\(wa) zero")
    }
}

/// **2.3** (`LR-AE`). Unequal **declared** grow factors among siblings have no
/// SwiftUI spelling: `Row { a.flexGrow(1); b.flexGrow(2) }` reports
/// `box.flexGrow.weights` exactly once, at the parent's site, and nothing else;
/// equal factors lower whatever their value — `(2, 2)` and `(0.5, 0.5)` agree at
/// 150/150 (CSS's factor sum is not below 1 in either).
///
/// Mutation that must redden it: **M2c** the weights check removed (the report
/// reads empty).
@MainActor
@Test func unequalGrowWeightsAreReportedOnTheParent() throws {
    func row(_ fa: Float, _ fb: Float) -> some ElementGroup {
        Row { Box().height(px(10)).flexGrow(fa); Box().height(px(10)).flexGrow(fb) }.width(px(300))
    }
    #expect(report { row(1, 2) } == [field(.box, "flexGrow.weights")])
    for (fa, fb) in [(Float(2), Float(2)), (0.5, 0.5)] {
        let r = LayoutDifferential.compare(width: 400, height: 100) { row(fa, fb) }
        try #require(r.elements == 4)
        expectCorpusAgreement(r, "(\(fa), \(fb))")
        #expect([0, 1].map { r.loweredBounds[child(containerID, $0)] } == [bounds(0, 0, 150, 10), bounds(150, 0, 150, 10)])
    }
}

/// **2.4** (`LR-AE` as amended; stage-2 probes F4, F9, F10). A zero basis on a
/// grower with no declared main size lowers exactly as `auto`: W's main minimum
/// comes only from a declared `minSize`, so a grower takes its share **down to its
/// content** and no further (CSS's automatic minimum for rigid content).
///
/// - at 300, `Row { Row { 40×10; 40×10 }.flexGrow(1).flexBasis(0); Box().height(10)
///   .flexGrow(1).flexBasis(0) }`: 150 / 150; agrees;
/// - at 150, the inner row over 100×10 and 100×10: **200** (overflowing) and 0 at x
///   200 (F10); agrees;
/// - **divergence arm** (F9): `Text("alphabravocharlie").flexGrow(1).flexBasis(0)`
///   beside a zero-basis `Box` at 100: lowered the text is **50** wide (broken
///   inside its word) and as tall as the shaping cache wraps it at 50; legacy it is
///   the word's min-content wide and one line tall;
/// - **report arms**: `Box().width(200).flexGrow(1).flexBasis(0)` (a sized
///   zero-basis grower with no minimum: CSS floors it at min(size, content)),
///   `flexBasis(0)` without grow, `flexBasis(40)` and `flexBasis(fraction: 0.5)`
///   each report exactly `box.flexBasis`;
/// - **divergence arm** (F4, a sized container): `Row { Row { 40×10; g }.width(200)
///   .flexGrow(1).flexBasis(0).minWidth(0); Box().height(10).flexGrow(1)
///   .flexBasis(0) }.width(300)`, g `Box().height(10).flexGrow(1)`: the item rect
///   agrees (150), but the lowered row lays its content out at its declared 200
///   inside it — g is **160** wide, its right edge 50 past the item's — where legacy
///   lays it out in 150 (g 110). **Corrected from the design's arm** (children
///   `a40; b40` under `.justifyContent(.flexEnd)`): rigid children sit at
///   f·(150 − 200) + f·(200 − 80) = f·(150 − 80) inside W under any one factor f,
///   exactly where CSS puts them, so that arm cannot show the divergence; a grower
///   inside can (record §21, lane 2).
///
/// Mutations that must redden it: **M2d** a non-zero length basis lowered as `auto`
/// (the `flexBasis(40)` arm reads empty); **M2d′** a zero basis given W's minimum 0
/// with no declared minimum (the F10 arm answers 75 / 75); **M2d″** a sized
/// zero-basis grower lowered instead of reported.
@MainActor
@Test func aZeroBasisGrowerTakesItsShareDownToItsContent() throws {
    let inner = child(containerID, 0), sibling = child(containerID, 1)
    let share = LayoutDifferential.compare(width: 400, height: 100) {
        Row {
            Row { fixed(40, 10); fixed(40, 10) }.flexGrow(1).flexBasis(px(0))
            Box().height(px(10)).flexGrow(1).flexBasis(px(0)).background(.accent)
        }
        .width(px(300))
    }
    try #require(share.elements == 6)
    expectCorpusAgreement(share, "zero-basis share")
    #expect([inner, sibling].map { share.loweredBounds[$0] } == [bounds(0, 0, 150, 10), bounds(150, 0, 150, 10)])

    let content = LayoutDifferential.compare(width: 400, height: 100) {
        Row {
            Row { fixed(100, 10); fixed(100, 10) }.flexGrow(1).flexBasis(px(0))
            Box().height(px(10)).flexGrow(1).flexBasis(px(0)).background(.accent)
        }
        .width(px(150))
    }
    try #require(content.elements == 6)
    expectCorpusAgreement(content, "zero-basis grower over rigid content (F10)")
    #expect([inner, sibling].map { content.loweredBounds[$0] } == [bounds(0, 0, 200, 10), bounds(200, 0, 0, 10)])

    let word = "alphabravocharlie"
    let text = LayoutDifferential.compare(width: 400, height: 200) {
        Row {
            Text(word).flexGrow(1).flexBasis(px(0))
            Box().height(px(10)).flexGrow(1).flexBasis(px(0))
        }
        .width(px(100))
    }
    try #require(text.elements == 4)
    #expect(text.unlowerable.isEmpty, "\(text.unlowerable)")
    let (cache, font) = systemFont()
    let legacyText = try #require(text.legacyBounds[inner])
    let loweredText = try #require(text.loweredBounds[inner])
    try #require(legacyText != loweredText)
    #expect(legacyText.size == Size(width: Pixels(Float(cache.minContentWidth(word, font: font).rounded())),
                                    height: px(16)), "legacy \(legacyText)")
    let at50 = proposalTextMeasurement(word, font: font, cache: cache, proposal: ProposedSize(width: 50, height: nil))
    try #require(at50.size.height > 16)
    #expect(loweredText.size == Size(width: px(50), height: Pixels(Float(at50.size.height.rounded()))),
            "lowered \(loweredText)")

    #expect(report { Row { Box().width(px(200)).height(px(10)).flexGrow(1).flexBasis(px(0)); fixed(10, 10) } }
            == [field(.box, "flexBasis")], "sized zero-basis grower")
    #expect(report { Row { Box().height(px(10)).flexBasis(px(0)); fixed(10, 10) } } == [field(.box, "flexBasis")],
            "zero basis without grow")
    #expect(report { Row { Box().height(px(10)).flexBasis(px(40)); fixed(10, 10) } } == [field(.box, "flexBasis")],
            "flexBasis(40)")
    #expect(report { Row { Box().height(px(10)).flexBasis(fraction: 0.5); fixed(10, 10) } } == [field(.box, "flexBasis")],
            "flexBasis(fraction:)")

    let sized = LayoutDifferential.compare(width: 400, height: 100) {
        Row {
            Row { fixed(40, 10); Box().height(px(10)).flexGrow(1).background(.accent) }
                .width(px(200)).flexGrow(1).flexBasis(px(0)).minWidth(px(0))
            Box().height(px(10)).flexGrow(1).flexBasis(px(0))
        }
        .width(px(300))
    }
    try #require(sized.elements == 6)
    #expect(sized.unlowerable.isEmpty, "\(sized.unlowerable)")
    let g = child(inner, 1)
    #expect([inner, sibling].map { sized.legacyBounds[$0] } == [bounds(0, 0, 150, 10), bounds(150, 0, 150, 10)])
    #expect([inner, sibling].map { sized.loweredBounds[$0] } == [bounds(0, 0, 150, 10), bounds(150, 0, 150, 10)])
    try #require(sized.legacyBounds[g] != sized.loweredBounds[g])
    #expect(sized.legacyBounds[g] == bounds(40, 0, 110, 10))
    #expect(sized.loweredBounds[g] == bounds(40, 0, 160, 10))
}

/// **2.5** (`LR-AF`; stage-2 probe F7 against control F6). `flexShrink(0)` on an
/// `auto` main size lowers to `fixedSize` on the parent's main axis: the item keeps
/// its natural main size and overflows.
///
/// - `Row { Text(long).flexShrink(0); Box().width(50).height(10).flexShrink(0)
///   }.width(100)`: the text one line, its shaped width, the box after it;
/// - the transpose, `Column { Text(long).flexShrink(0); Box().width(10).height(50)
///   .flexShrink(0) }.alignItems(.stretch).width(100).height(20)`: the text 100 wide
///   and as tall as the cache wraps it at 100, the box below it.
///
/// Both agree. **Corrected from the design's arm**, whose sibling `Box().width(50)`
/// kept the default shrink: CSS shrinks that childless box to **0** (its automatic
/// minimum is its content's, 0; measured legacy 0×10 at x 252) where the lowered
/// row keeps a declared 50 rigid — divergence 55, pinned by 2.6 and 2.9, not this
/// test's subject (record §21, lane 2). The column declares `.alignItems(.stretch)`
/// so the text's width is the line on both sides (a centred lowered text hugs its
/// widest line, `LR-F`).
///
/// Mutation that must redden it: **M2e** `fixedSize` on the cross axis (the row's
/// text wraps at 100).
@MainActor
@Test func aZeroShrinkKeepsItsNaturalMainSizeAndOverflows() throws {
    let (cache, font) = systemFont()
    let row = LayoutDifferential.compare(width: 400, height: 200) {
        Row { Text(longString).flexShrink(0); Box().width(px(50)).height(px(10)).flexShrink(0).background(.accent) }
            .width(px(100))
    }
    try #require(row.elements == 4)
    expectCorpusAgreement(row, "row")
    let oneLine = Float(cache.shaped(longString, font: font, wrappingAt: nil).widestLine.rounded())
    try #require(oneLine > 100)
    #expect(row.loweredBounds[child(containerID, 0)]?.size == Size(width: Pixels(oneLine), height: px(16)))
    #expect(row.loweredBounds[child(containerID, 1)]?.origin.x == Pixels(oneLine))

    let column = LayoutDifferential.compare(width: 400, height: 200) {
        Column { Text(longString).flexShrink(0); Box().width(px(10)).height(px(50)).flexShrink(0).background(.accent) }
            .alignItems(.stretch).width(px(100)).height(px(20))
    }
    try #require(column.elements == 4)
    expectCorpusAgreement(column, "column")
    let tall = Float(cache.shaped(longString, font: font, wrappingAt: 100).totalHeight.rounded())
    try #require(tall > 20)
    #expect(column.loweredBounds[child(containerID, 0)] == bounds(0, 0, 100, tall))
    #expect(column.loweredBounds[child(containerID, 1)]?.origin.y == Pixels(tall))
}

/// **2.6 — divergence pin** (`LR-AF`, divergence 55; stack-algorithms probe G9).
/// Every positive `flexShrink` lowers to nothing, whatever its weight: SwiftUI has
/// no shrink, and two rigid 80s in a 100 row overflow. `Row { Box().width(80)
/// .flexShrink(s₁); Box().width(80).flexShrink(s₂) }.width(100)`, 10 tall:
///
/// - (1, 1): legacy 50 / 50, lowered 80 / 80 from x 0;
/// - (1, 3): legacy **65 / 35** (CSS scales each shrink by its base: 60 × 80/320 and
///   60 × 240/320), lowered 80 / 80.
///
/// Mutation that must redden it: **M2f** a shrink other than 1 reported (the (1, 3)
/// arm reports).
@MainActor
@Test func aPositiveShrinkLowersAsSwiftUIsCompressionWhateverItsWeight() throws {
    let a = child(containerID, 0), b = child(containerID, 1)
    for (weight, legacyA) in [(Float(1), Float(50)), (3, 65)] {
        let r = LayoutDifferential.compare(width: 300, height: 100) {
            Row {
                Box().width(px(80)).height(px(10)).flexShrink(1).background(.accent)
                Box().width(px(80)).height(px(10)).flexShrink(weight).background(.accent)
            }
            .width(px(100))
        }
        try #require(r.elements == 4)
        #expect(r.unlowerable.isEmpty, "\(weight): \(r.unlowerable)")
        try #require(r.legacyBounds[a] != r.loweredBounds[a])
        #expect([a, b].map { r.legacyBounds[$0] }
                == [bounds(0, 0, legacyA, 10), bounds(legacyA, 0, 100 - legacyA, 10)], "\(weight) legacy")
        #expect([a, b].map { r.loweredBounds[$0] } == [bounds(0, 0, 80, 10), bounds(80, 0, 80, 10)], "\(weight) lowered")
    }
}

/// **2.7** (`LR-AG`; stage-2 probes F4, F8). A declared minimum on an `auto` axis is
/// W's minimum, aliased; on a declared size it folds into the element's own frame:
///
/// - `Row { Box().height(10).minWidth(50); 20×10 }.width(300)`: 50 wide, the fixed
///   box at x 50 (W non-greedy, a floor);
/// - the demo scroller's shape, `Column { 420×20; Box { Box().height(400) }
///   .width(420).flexGrow(1).flexBasis(0).minHeight(0) }.height(300)`: the box takes
///   its **280** share below its 400 content (the minimum's presence), its child
///   overflowing at y 20;
/// - `Row { Box().width(40).minWidth(60).height(10); 20×10 }.width(300)`: the static
///   fold, **60**.
///
/// Every arm agrees.
///
/// Mutations that must redden it: **M2g** W drops the minimum (the scroller box
/// answers 400, the first box 0); **M2h** the static fold skipped (60 → 40).
@MainActor
@Test func aMinimumFloorsAnItemAndLetsAGrowerGoBelowItsContent() throws {
    let floor = LayoutDifferential.compare(width: 400, height: 100) {
        Row { Box().height(px(10)).minWidth(px(50)).background(.accent); fixed(20, 10) }.width(px(300))
    }
    try #require(floor.elements == 4)
    expectCorpusAgreement(floor, "minWidth floor")
    #expect([0, 1].map { floor.loweredBounds[child(containerID, $0)] } == [bounds(0, 0, 50, 10), bounds(50, 0, 20, 10)])

    let scroller = LayoutDifferential.compare(width: 500, height: 400) {
        Column {
            fixed(420, 20)
            Box { Box().height(px(400)).background(.accent) }
                .width(px(420)).flexGrow(1).flexBasis(px(0)).minHeight(px(0)).background(.surface)
        }
        .height(px(300))
    }
    try #require(scroller.elements == 5)
    expectCorpusAgreement(scroller, "the demo scroller's shape")
    let box = child(containerID, 1)
    #expect([box, child(box, 0)].map { scroller.loweredBounds[$0] } == [bounds(0, 20, 420, 280), bounds(0, 20, 0, 400)])

    let fold = LayoutDifferential.compare(width: 400, height: 100) {
        Row { Box().width(px(40)).minWidth(px(60)).height(px(10)).background(.accent); fixed(20, 10) }.width(px(300))
    }
    try #require(fold.elements == 4)
    expectCorpusAgreement(fold, "static fold")
    #expect([0, 1].map { fold.loweredBounds[child(containerID, $0)] } == [bounds(0, 0, 60, 10), bounds(60, 0, 20, 10)])
}

/// **2.8** (`LR-AG`; stage-2 probe X10, frame probe D4). A maximum lowers only where
/// SwiftUI's greedy maximum answers CSS's clamp:
///
/// - on a grower, `Row { Box().height(10).flexGrow(1).maxWidth(80); 20×10 }.width(300)`:
///   **80**, the fixed box at x 80 (W's maximum);
/// - on a declared size, `Box().width(120).maxWidth(80)` in the same row: **80**
///   (the static fold);
/// - on a hugging axis, `Row { Text(long).maxWidth(80); 20×10 }`: reports exactly
///   `text.maxSize` (stage 8).
///
/// Mutation that must redden it: **M2i** a non-greedy maximum lowered onto W (the
/// report arm reads empty).
@MainActor
@Test func aMaximumLowersOnAGreedyOrSizedAxisAndIsReportedElsewhere() throws {
    let grower = LayoutDifferential.compare(width: 400, height: 100) {
        Row { Box().height(px(10)).flexGrow(1).maxWidth(px(80)).background(.accent); fixed(20, 10) }.width(px(300))
    }
    try #require(grower.elements == 4)
    expectCorpusAgreement(grower, "maximum on a grower")
    #expect([0, 1].map { grower.loweredBounds[child(containerID, $0)] } == [bounds(0, 0, 80, 10), bounds(80, 0, 20, 10)])

    let sized = LayoutDifferential.compare(width: 400, height: 100) {
        Row { Box().width(px(120)).height(px(10)).maxWidth(px(80)).background(.accent); fixed(20, 10) }.width(px(300))
    }
    try #require(sized.elements == 4)
    expectCorpusAgreement(sized, "maximum on a declared size")
    #expect(sized.loweredBounds[child(containerID, 0)] == bounds(0, 0, 80, 10))

    #expect(report { Row { Text(longString).maxWidth(px(80)); fixed(20, 10) } } == [field(.text, "maxSize")])
}

/// **2.9 — divergence pin** (`LR-AF`, divergence 55; stage-2 probe F5, stack-algorithms
/// G9 and G4r). The demo body row's shape at 920×560, inside a stretched 888-wide
/// column: a sidebar `Column(gap: 10) { Text("Library"); four 26-tall bars }
/// .alignItems(.stretch).flexGrow(1).padding(14).width(196)` beside a main pane
/// `Column(gap: 12) { Text(the demo's paragraph); 420×20 }.alignItems(.stretch)
/// .flexGrow(1).padding(16).flexGrow(1)`, row gap 12. Legacy CSS shrinks the
/// declared 196 to **88** (the main pane's base is its paragraph's one-line width,
/// measured 2026-09-17 on this shape as on the demo), the main pane at x 100;
/// lowered the declared 196 is rigid and served first — **196**, the main pane at x
/// 208, **680** wide.
///
/// Mutation that must redden it: **M2j** a declared main size lowered as a greedy
/// `frame(maxWidth: size)` with no minimum.
@MainActor
@Test func theDemosBodyRowKeepsTheSidebarAtItsDeclaredWidthWhereCSSShrinksIt() throws {
    let r = LayoutDifferential.compare(width: 920, height: 560) {
        Column {
            Row(gap: px(12)) {
                Column(gap: px(10)) {
                    Text("Library")
                    Box().height(px(26)).background(.accent)
                    Box().height(px(26)).background(.surfaceSecondary)
                    Box().height(px(26)).background(.surfaceSecondary)
                    Box().height(px(26)).background(.surfaceSecondary)
                }
                .alignItems(.stretch).flexGrow(1).padding(px(14)).width(px(196)).background(.surface)
                Column(gap: px(12)) { Text(demoParagraph); fixed(420, 20) }
                    .alignItems(.stretch).flexGrow(1).padding(px(16)).flexGrow(1).background(.surface)
            }
            .alignItems(.stretch)
            fixed(888, 1)
        }
        .alignItems(.stretch).width(px(888))
    }
    #expect(r.unlowerable.isEmpty, "\(r.unlowerable)")
    let row = child(containerID, 0), sidebar = child(row, 0), main = child(row, 1)
    let legacySidebar = try #require(r.legacyBounds[sidebar])
    let loweredSidebar = try #require(r.loweredBounds[sidebar])
    try #require(legacySidebar.size.width != loweredSidebar.size.width)
    #expect(legacySidebar.size.width == px(88) && r.legacyBounds[main]?.origin.x == px(100)
            && r.legacyBounds[main]?.size.width == px(788), "legacy \(legacySidebar) \(String(describing: r.legacyBounds[main]))")
    #expect(loweredSidebar.size.width == px(196) && r.loweredBounds[main]?.origin.x == px(208)
            && r.loweredBounds[main]?.size.width == px(680), "lowered \(loweredSidebar) \(String(describing: r.loweredBounds[main]))")
}

/// The demo's paragraph (`demoContent()`, `DemoContent.swift`), copied: it is a
/// literal inside the demo's builder, not a symbol. 2.15 derives the demo's text
/// rects from it, so a copy that drifted from the demo reddens 2.15.
let demoParagraph = """
     CoreText shapes this paragraph, a shelf packer places \
     each glyph in an R8 atlas exactly once, and the fragment \
     shader tints the coverage it samples with the theme's \
     text colour. Drag the window's edge and watch the line \
     breaks move: layout asks this leaf to measure itself at \
     the width it was offered, and paint re-shapes at the \
     width layout settled on.
     """

/// **2.10 — divergence pin** (`LR-AC`, cause R's isolating pin; stage-2 probe X18
/// against X17). `Column { 30×20; Box().width(30).height(10).flexGrow(1) }` in a
/// 200×200 harness root: the root offers the column 200 tall, and the grower's
/// greedy W fills it — lowered column **30×200**, the grower 30×180 at y 20. Legacy
/// the column is fit-content, **30×30**, and the grower keeps its 10 (no free space).
///
/// Mutation that must redden it: **M2k** W not greedy when the parent declares no main
/// size.
@MainActor
@Test func aGrowerOnAHuggingContainersMainAxisFillsItsProposal() throws {
    let r = LayoutDifferential.compare(width: 200, height: 200) {
        Column { fixed(30, 20); Box().width(px(30)).height(px(10)).flexGrow(1).background(.accent) }
    }
    try #require(r.elements == 4)
    #expect(r.unlowerable.isEmpty, "\(r.unlowerable)")
    let grower = child(containerID, 1)
    try #require(r.legacyBounds[containerID] != r.loweredBounds[containerID])
    #expect([containerID, grower].map { r.legacyBounds[$0] } == [bounds(0, 0, 30, 30), bounds(0, 20, 30, 10)])
    #expect([containerID, grower].map { r.loweredBounds[$0] } == [bounds(0, 0, 30, 200), bounds(0, 20, 30, 180)])
}

/// **2.11 — divergence pin** (`LR-AR`; scratch R2's S2, stage-2 probe X12 against
/// X11). `Row { 40×10; Box().width(30).height(10).flexGrow(1).padding(8) }.width(200)`:
/// the grow sits inside a one-child `.padding` layer, is declared, and so is lowered,
/// not elided — the lowered layer fills the row's leftover, **160×26**, the child
/// **144** wide at (48, 8). Legacy the layer hugs, 46×26 at (40, 0), the child 30 wide.
///
/// Mutation that must redden it: **M2l** grow elided in a one-child container (lowered
/// reads as legacy).
@MainActor
@Test func aGrowInsideAOneChildPaddingFillsTheWrapperWhereCSSLeavesItUngrown() throws {
    let r = LayoutDifferential.compare(width: 300, height: 100) {
        Row { fixed(40, 10); Box().width(px(30)).height(px(10)).flexGrow(1).background(.accent).padding(px(8)) }
            .width(px(200))
    }
    try #require(r.elements == 5)
    #expect(r.unlowerable.isEmpty, "\(r.unlowerable)")
    let layer = child(containerID, 1), inner = child(layer, 0)
    try #require(r.legacyBounds[layer] != r.loweredBounds[layer])
    #expect([layer, inner].map { r.legacyBounds[$0] } == [bounds(40, 0, 46, 26), bounds(48, 8, 30, 10)])
    #expect([layer, inner].map { r.loweredBounds[$0] } == [bounds(40, 0, 160, 26), bounds(48, 8, 144, 10)])
}

/// **2.12** (`LR-AR`, the grow half; scratch R2's S1). A W greedy on a child flex
/// container's own main axis because it **grows** gives an unsized `space-*`
/// container free space: `Row { Row { 20×10; 20×10 }.justifyContent(j).flexGrow(1);
/// 40×10 }.width(300)` with `.spaceBetween` reports exactly
/// `box.justifyContent.spaceBetween` at the inner row's site; controls `.flexEnd`
/// (b at x 240) and `.center` (a at 110, b at 130) agree. A **minimum** leaves free
/// space too: `Row { Row { 20×10; 20×10 }.justifyContent(.spaceBetween).minWidth(200);
/// 40×10 }.width(300)` reports the same entry (legacy distributes inside the 200, b
/// at 180; W's floor would place it at 20 — lane 2's extension of `LR-AR`, record §21).
///
/// Mutations that must redden it: **M2m** the grow half of the re-check removed (the
/// report reads empty); **M2m′** the re-check limited to a greedy W (the minimum arm
/// reads empty).
@MainActor
@Test func aGrownUnsizedSpaceDistributionContainerIsReported() throws {
    func tree(_ justify: JustifyContent) -> some ElementGroup {
        Row { Row { fixed(20, 10); fixed(20, 10) }.justifyContent(justify).flexGrow(1); fixed(40, 10) }.width(px(300))
    }
    #expect(report { tree(.spaceBetween) } == [field(.box, "justifyContent.spaceBetween")])
    #expect(report {
        Row { Row { fixed(20, 10); fixed(20, 10) }.justifyContent(.spaceBetween).minWidth(px(200)); fixed(40, 10) }
            .width(px(300))
    } == [field(.box, "justifyContent.spaceBetween")], "a minimum")
    let inner = child(containerID, 0)
    for (justify, a) in [(JustifyContent.flexEnd, Float(220)), (.center, 110)] {
        let r = LayoutDifferential.compare(width: 400, height: 100) { tree(justify) }
        try #require(r.elements == 6, "\(justify)")
        expectCorpusAgreement(r, "\(justify)")
        #expect([0, 1].map { r.loweredBounds[child(inner, $0)] } == [bounds(a, 0, 20, 10), bounds(a + 20, 0, 20, 10)],
                "\(justify)")
    }
}

// MARK: 2.13 — animated item fields

/// 2.13's arm B, at file scope: an exit test's body captures nothing.
@MainActor
@ElementBuilder
private func animatedWeightsArm(_ on: Bool) -> some ElementGroup {
    Row {
        Box().height(Pixels(10)).flexGrow(on ? 2 : 0).background(.accent)
        Box().height(Pixels(10)).flexGrow(2).background(.accent)
    }
    .width(Pixels(300))
}

@Observable
private final class ItemAnimationModel {
    var on = false
}

/// One authority's widths of `ids` across an animation of `model.on` false → true:
/// ticks at t = 100 (before), `withAnimation(.linear(duration: 1))`, then 100 (the
/// frame that starts the transaction), 100.25, 100.5 and 101.5 (settled), through a
/// fake `Window` driven by `simulateTick` (no sleep). One window per authority, in
/// turn, each with its own model: `withAnimation`'s parked transaction is consumed by
/// exactly one frame build, so two live windows cannot share one (CLAUDE.md,
/// Animation; the reason this is not `WindowPair`, whose one `make` closure both
/// windows read).
@MainActor
private func animatedWidths<C: ElementGroup>(_ authority: LayoutAuthority, ids: [GlobalElementID],
                                              @ElementBuilder _ make: @escaping @MainActor (Bool) -> C) throws -> [[Float]] {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let model = ItemAnimationModel()
    let (window, platform) = try makeFakeWindow(device: device, size: 400, startsDisplayLink: true) {
        DifferentialRoot(width: 400, height: 400) { make(model.on) }
    }
    window.layoutAuthority = authority
    window.recordsElementBounds = true
    func read() -> [Float] { ids.map { window.lastElementBounds[$0]?.size.width.value ?? -1 } }
    platform.simulateTick(timestamp: 100)
    var series = [read()]
    withAnimation(.linear(duration: 1)) { model.on = true }
    for t in [100, 100.25, 100.5, 101.5] {
        platform.simulateTick(timestamp: t)
        series.append(read())
    }
    return series
}

/// **2.13** (`LR-AS`). An animated item field: **structure** (which wrappers exist,
/// the weights check) reads the declared style and snaps; **values** (W's minimum
/// and maximum) read the animated one and interpolate. Widths at t = 100 before the
/// change, then 100, 100.25, 100.5 and 101.5 of a 1 s linear `withAnimation`:
///
/// - **Arm A — divergence** (no SwiftUI claim: SwiftUI has no `flexGrow`). `Row {
///   40×10; Box().height(10).flexGrow(0 → 1) }.width(300)`: legacy **0, 0, 65, 130,
///   260** (CSS grows a lone item by its factor's share when the factors sum below
///   1); lowered **0, 260, 260, 260, 260** — W exists from the frame the change is
///   declared.
/// - **Arm B — divergence**, in a child process. `Row { a.flexGrow(0 → 2); b.flexGrow(2)
///   }.width(300)`: lowered 150 / 150 at every tick after the change and no report
///   at any (the weights check reads the declared (2, 2)); legacy 0 / 300, 0 / 300,
///   60 / 240, 100 / 200, 150 / 150. **Corrected from the design's `(1 → 2, 2)`**:
///   its start state (1, 2) reports `flexGrow.weights` and would trap the proposal
///   window before the animation begins; (0 → 2, 2) starts with one grower and is
///   unequal mid-flight all the same (record §21, lane 2). The child process is the
///   guard against M2o, whose mid-flight report traps a production window and would
///   otherwise end the run with no summary line (practices shape 13).
/// - **Arm C — agrees.** `Row { 260×10; Box().height(10).flexGrow(1).minWidth(40 →
///   80) }.width(300)`: 40, 40, 50, 60, 80 on both sides. **Corrected from the
///   design's "hugging row"**: under the harness root a hugging row is offered the
///   root's width and a grower fills it (cause R), so the row declares 300 and the
///   rigid sibling leaves the grower 40 (record §21, lane 2).
///
/// Every state is pre-flighted through `LayoutDifferential.compare` first (`LR-AA`).
///
/// Mutations that must redden it: **M2n** W's existence read from the animated style
/// with a threshold of 0.5 (arm A's lowered 100.25 tick hugs); **M2o** the weights check
/// reads the animated style (arm B's child traps mid-flight); **M2p** W's minimum read
/// from the declared style (arm C's lowered widths jump to 80).
@MainActor
@Test func anAnimatedItemFieldSnapsItsStructureAndInterpolatesItsValues() async throws {
    let row = child(rootID, 0)
    // Arm A.
    @ElementBuilder func armA(_ on: Bool) -> some ElementGroup {
        Row { fixed(40, 10); Box().height(px(10)).flexGrow(on ? 1 : 0).background(.accent) }.width(px(300))
    }
    for on in [false, true] {
        try #require(LayoutDifferential.compare(width: 400, height: 400) { armA(on) }.unlowerable.isEmpty, "A \(on)")
    }
    let aLegacy = try animatedWidths(.legacy, ids: [child(row, 1)]) { armA($0) }
    let aLowered = try animatedWidths(.proposal, ids: [child(row, 1)]) { armA($0) }
    #expect(aLegacy == [[0], [0], [65], [130], [260]], "A legacy \(aLegacy)")
    #expect(aLowered == [[0], [260], [260], [260], [260]], "A lowered \(aLowered)")

    // Arm C.
    @ElementBuilder func armC(_ on: Bool) -> some ElementGroup {
        Row { fixed(260, 10); Box().height(px(10)).flexGrow(1).minWidth(px(on ? 80 : 40)).background(.accent) }
            .width(px(300))
    }
    for on in [false, true] {
        try #require(LayoutDifferential.compare(width: 400, height: 400) { armC(on) }.unlowerable.isEmpty, "C \(on)")
    }
    let cLegacy = try animatedWidths(.legacy, ids: [child(row, 1)]) { armC($0) }
    let cLowered = try animatedWidths(.proposal, ids: [child(row, 1)]) { armC($0) }
    #expect(cLegacy == [[40], [40], [50], [60], [80]], "C legacy \(cLegacy)")
    #expect(cLowered == cLegacy, "C lowered \(cLowered)")

    // Arm B, in a child process.
    let result = await #expect(processExitsWith: .success,
                               observing: [\.standardOutputContent, \.standardErrorContent]) {
        await MainActor.run {
            let rowID = GlobalElementID.child(of: GlobalElementID.child(of: nil, at: 0, name: nil), at: 0, name: nil)
            let ids = [GlobalElementID.child(of: rowID, at: 0, name: nil), GlobalElementID.child(of: rowID, at: 1, name: nil)]
            var preflight: [String] = []
            for on in [false, true] {
                preflight.append("\(LayoutDifferential.compare(width: 400, height: 400) { animatedWeightsArm(on) }.unlowerable)")
            }
            let legacy = (try? animatedWidths(.legacy, ids: ids) { animatedWeightsArm($0) }) ?? []
            let lowered = (try? animatedWidths(.proposal, ids: ids) { animatedWeightsArm($0) }) ?? []
            let line = "LANE2-2.13B preflight=\(preflight) legacy=\(legacy) lowered=\(lowered)\n"
            FileHandle.standardOutput.write(Data(line.utf8))
        }
    }
    let out = String(decoding: result?.standardOutputContent ?? [], as: UTF8.self)
    let err = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    let expected = "LANE2-2.13B preflight=[\"[]\", \"[]\"] "
        + "legacy=[[0.0, 300.0], [0.0, 300.0], [60.0, 240.0], [100.0, 200.0], [150.0, 150.0]] "
        + "lowered=[[0.0, 300.0], [150.0, 150.0], [150.0, 150.0], [150.0, 150.0], [150.0, 150.0]]\n"
    #expect(out.contains(expected), "stdout:\n\(out)\nstderr:\n\(err)")
}
