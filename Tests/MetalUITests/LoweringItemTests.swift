import Foundation
import Testing
import MetalUICore
@testable import MetalUILayout
import MetalUIText
@testable import MetalUI

// Plan task 7, stage 2, lane 1 (`docs/superpowers/specs/2026-09-17-engine-stage-2-design.md`
// §3, §4.1 and §6 lane 1; rulings LR-AB, LR-AC, LR-AD, LR-AQ, LR-AR, LR-AW): flex
// ITEM fields lowered by the parent under the proposal layout authority — the child
// records a `LoweredItem`, the lowered container wraps it (a greedy cross-axis item
// frame W for stretch, aliased as the element's rect; an unaliased alignment frame
// for a non-stretch `alignSelf`), and a record no lowered container consumes reports
// `<site>.<field>.unconsumed`.
//
// **Red before**: every test here was run on `cb2e708`'s lowering (stage 1), where
// stretch reports `alignItems.stretch` and every item field reports at the child's
// own site; each reads red there by a report or a literal mismatch, and compiles
// against stage-1 API only (record §19, lane 1). 1.12's agreeing arm is
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
/// sides; record §19, lane 1).
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
/// record §19, lane 1).
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
    // differ at 4 and 6, not at 9; record §19, lane 1).
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
/// transcription of the kernel's rules that reproduces 5.7's 118/94/4 (record §19,
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
/// - a legacy `ScrollView` over the same child reports only `scrollView.noLowering`
///   (the site marks the record it receives);
/// - the control `Row { same }` consumes the record: no `…unconsumed` entry (lane 1
///   still reports `box.flexGrow` there, at the child's site; lane 2 lowers it);
/// - **the frame's root** (a `Frame` rendering the element itself, no harness):
///   `.maxWidth(600)` and `.minWidth(50)` always report (CSS applies them to a root);
///   `.flexGrow(1)`, `.flexShrink(0)`, `.flexBasis(0)` and `.alignSelf(.flexEnd)` each
///   first compare the legacy root with the field and without it — the legacy root
///   ignores it exactly when the two rects are equal — and assert **no report and an
///   unchanged lowered root** where it is ignored, the `…unconsumed` report
///   otherwise. The four comparisons are recorded as literals (all ignored, measured
///   on the first run; record §19, lane 1).
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

    arms.append(("legacy ScrollView", report { ScrollView { grow() } }, [field(.scrollView, "noLowering")]))
    arms.append(("control Row", report { Row { grow() } }, [field(.box, "flexGrow")]))

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
