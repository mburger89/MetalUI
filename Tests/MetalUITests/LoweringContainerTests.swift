import Foundation
import Metal
import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUI

// Plan task 7, stage 1, lane 3 (`docs/superpowers/specs/2026-09-17-engine-replacement-design.md`
// §5.4 and §6 lane 3; rulings LR-E, LR-I, LR-T): the lowering table's container
// half — a `Box` with children, and `Row`/`Column` (which wrap a `Box`), registered
// as a native linear stack → native padding → fixed native frame under the
// proposal layout authority, compared with the legacy engine through the
// differential harness (`LayoutDifferential.swift`) until stage 9, which deleted
// the legacy engine: each test now asserts the one frame's rects by the literals
// it always carried (ruling `LR-FE` item 2; record §51, lane 1).
//
// **Red before**: every test here read red on lane 2's tree, where a `Box` with
// children reports `box.noLowering` at site level (record §18, lane 3), except
// 3.7's legacy half, which pins the existing `SA-G` trap. The mutation each must
// redden is named in its doc comment and in spec §6's lane-3 table; the record
// names what each actually reddened.
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

/// A fixed-size childless `Box` (lowered since lane 2: a 0×0 leaf in a fixed frame).
@MainActor
private func fixed(_ w: Float, _ h: Float) -> Box<EmptyGroup> {
    Box().cssWidth(px(w)).cssHeight(px(h))
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

/// The lowered rects of `ids`, in order, for a literal comparison.
private func lowered(_ r: LayoutDifferential.Report, _ ids: [GlobalElementID]) -> [Bounds<Pixels>?] {
    ids.map { r.bounds[$0] }
}

// MARK: - 3.1, 3.2 — axis, gap, cross alignment

/// **3.1.** A `Row` and a `Column` over three fixed children of different cross
/// sizes — a 20×10, b 30×30, c 10×20 — at gap 0 and 10 and `alignItems` `.flexStart`,
/// `.center`, `.flexEnd` lay out at literal rects derived by hand. With factor f (0, ½, 1) and gap g:
///
/// - row: container (60 + 2g)×30; a (0, 20f), b (20 + g, 0), c (50 + 2g, 10f);
/// - column (widths are the cross sizes): container 30×(60 + 2g) with a 20×10,
///   b 30×30, c 10×20; a (10f, 0), b (0, 10 + g), c (20f, 40 + 2g).
///
/// Mutations that must redden it: **M3a**, the stack's cross `flexStart` ↔
/// `flexEnd` swapped; **M3b**, the stack spacing dropped (the gap-10 arms).
///
/// **Renamed at stage 9** from
/// `aLoweredRowAndColumnAgreeWithTheLegacyContainersOverFixedChildren` (`LR-FE`
/// item 6).
@MainActor
@Test func aLoweredRowAndColumnPlaceFixedChildrenByGapAndCrossAlignment() throws {
    let aligns: [(AlignItems, Float)] = [(.flexStart, 0), (.center, 0.5), (.flexEnd, 1)]
    var arms = 0
    for gap: Float in [0, 10] {
        for (align, f) in aligns {
            let row = LayoutDifferential.report(width: 200, height: 200) {
                Row(gap: px(gap)) { fixed(20, 10); fixed(30, 30); fixed(10, 20) }.alignItems(align)
            }
            try #require(row.elements == 5, "row gap \(gap) \(align): \(row.elements)")
            expectNothingReported(row, "row gap \(gap) \(align)")
            #expect(lowered(row, [containerID, child(containerID, 0), child(containerID, 1), child(containerID, 2)])
                    == [bounds(0, 0, 60 + 2 * gap, 30), bounds(0, 20 * f, 20, 10),
                        bounds(20 + gap, 0, 30, 30), bounds(50 + 2 * gap, 10 * f, 10, 20)],
                    "row gap \(gap) \(align)")

            let column = LayoutDifferential.report(width: 200, height: 200) {
                Column(gap: px(gap)) { fixed(20, 10); fixed(30, 30); fixed(10, 20) }.alignItems(align)
            }
            try #require(column.elements == 5, "column gap \(gap) \(align): \(column.elements)")
            expectNothingReported(column, "column gap \(gap) \(align)")
            #expect(lowered(column, [containerID, child(containerID, 0), child(containerID, 1), child(containerID, 2)])
                    == [bounds(0, 0, 30, 60 + 2 * gap), bounds(10 * f, 0, 20, 10),
                        bounds(0, 10 + gap, 30, 30), bounds(20 * f, 40 + 2 * gap, 10, 20)],
                    "column gap \(gap) \(align)")
            arms += 2
        }
    }
    try #require(arms == 12)
}

/// **3.2.** A container spaces its children by the gap on **its main axis**:
/// `gap(horizontal: 4, vertical: 20)` spaces a row's two 10×10 children by 4 and a
/// column's by 20 (asymmetric on purpose, practices shape 1). The gap is also
/// given in rem (0.25rem × 16 = 4 horizontal, 1.25rem × 16 = 20 vertical) through
/// `Style`, which must lay out the same way.
///
/// Mutation that must redden it: **M3c**, the gap's axes swapped.
@MainActor
@Test func aLoweredContainerSpacesItsChildrenByTheGapOnItsMainAxis() throws {
    let row = LayoutDifferential.report(width: 100, height: 100) {
        Row { fixed(10, 10); fixed(10, 10) }.gap(horizontal: px(4), vertical: px(20))
    }
    try #require(row.elements == 4)
    expectNothingReported(row, "row")
    #expect(lowered(row, [containerID, child(containerID, 1)])
            == [bounds(0, 0, 24, 10), bounds(14, 0, 10, 10)])

    let column = LayoutDifferential.report(width: 100, height: 100) {
        Column { fixed(10, 10); fixed(10, 10) }.gap(horizontal: px(4), vertical: px(20))
    }
    try #require(column.elements == 4)
    expectNothingReported(column, "column")
    #expect(lowered(column, [containerID, child(containerID, 1)])
            == [bounds(0, 0, 10, 40), bounds(0, 30, 10, 10)])

    var remRow = Style()
    remRow.flexDirection = .row
    remRow.alignItems = .flexStart
    remRow.gap = Axes(horizontal: .rems(Rems(0.25)), vertical: .rems(Rems(1.25)))
    let rem = LayoutDifferential.report(width: 100, height: 100) {
        Box(style: remRow) { fixed(10, 10); fixed(10, 10) }
    }
    try #require(rem.elements == 4)
    expectNothingReported(rem, "rem row")
    #expect(lowered(rem, [containerID, child(containerID, 1)])
            == [bounds(0, 0, 24, 10), bounds(14, 0, 10, 10)])
}

// MARK: - 3.3, 3.4 — a declared size, padding inside it

/// **3.3.** A container with a declared 100×60 size places its content by
/// `justifyContent` on the main axis and `alignItems` on the cross axis — 3 × 3
/// arms each for a `Row` and a `Column` over a 20×10 and a 30×20 child.
///
/// - row (content 50×20): with main factor j and cross factor a, the first child
///   at (50j, 50a), the second at (50j + 20, 40a);
/// - column (content 30×30): the first at (80a, 30j), the second at (70a, 30j + 10).
///
/// Mutation that must redden it: **M3d**, the size frame's main and cross
/// alignments swapped.
@MainActor
@Test func aLoweredSizedContainerPlacesItsContentByJustifyContentAndAlignItems() throws {
    let justifies: [(JustifyContent, Float)] = [(.flexStart, 0), (.center, 0.5), (.flexEnd, 1)]
    let aligns: [(AlignItems, Float)] = [(.flexStart, 0), (.center, 0.5), (.flexEnd, 1)]
    var arms = 0
    for (justify, j) in justifies {
        for (align, a) in aligns {
            let row = LayoutDifferential.report(width: 200, height: 200) {
                Row { fixed(20, 10); fixed(30, 20) }
                    .cssWidth(px(100)).cssHeight(px(60)).justifyContent(justify).alignItems(align)
            }
            try #require(row.elements == 4)
            expectNothingReported(row, "row \(justify) \(align)")
            #expect(lowered(row, [containerID, child(containerID, 0), child(containerID, 1)])
                    == [bounds(0, 0, 100, 60), bounds(50 * j, 50 * a, 20, 10),
                        bounds(50 * j + 20, 40 * a, 30, 20)],
                    "row \(justify) \(align)")

            let column = LayoutDifferential.report(width: 200, height: 200) {
                Column { fixed(20, 10); fixed(30, 20) }
                    .cssWidth(px(100)).cssHeight(px(60)).justifyContent(justify).alignItems(align)
            }
            try #require(column.elements == 4)
            expectNothingReported(column, "column \(justify) \(align)")
            #expect(lowered(column, [containerID, child(containerID, 0), child(containerID, 1)])
                    == [bounds(0, 0, 100, 60), bounds(80 * a, 30 * j, 20, 10),
                        bounds(70 * a, 30 * j + 10, 30, 20)],
                    "column \(justify) \(align)")
            arms += 2
        }
    }
    try #require(arms == 18)
}

/// A 36×36 button of the demo's counter chrome (`CounterPanel.button`): a centred
/// `Box` over a 22pt `Text`, decorated, hoverable, clickable and labelled.
@MainActor
private func chromeButton(_ label: String, _ axLabel: String) -> Box<Text> {
    Box(decoration: Decoration(background: .surfaceSecondary, cornerRadius: px(8))) {
        Text(label).font(size: 22)
    }
    .cssWidth(px(36)).cssHeight(px(36)).alignItems(.center).justifyContent(.center)
    .hoverBackground(.accent).onClick {}.accessibilityLabel(axLabel)
}

/// **3.4.** `Style.padding` on a container sits **inside** its declared size
/// (CSS border-box; stage-1 probe B1, B3).
///
/// - **The counter chrome** (the demo's `CounterPanel.chrome`, B3): a row, gap 12,
///   padding 12, centred, over two 36×36 buttons and a 140×36 readout, each a
///   centred `Box` over a 22pt `Text`. Unsized: 12 + 36 + 12 + 140 + 12 + 36 + 12 =
///   260 wide, 12 + 36 + 12 = 60 tall; children at x 12, 60, 212, y 12. Glyphs,
///   hitboxes and accessibility records were compared with the legacy engine's
///   until stage 9; since then they are literals, derived by hand: 8 glyphs
///   (`-`, `Count 0` less its space, `+`); exactly two hitboxes, the two
///   clickable buttons' at their rects; and the buttons' accessibility records
///   at the same rects.
/// - **A sized padded column**: 100×80, padding top 10, right 20, bottom 30, left
///   40 (distinct per edge), `.flexStart` both ways, over a 20×10: the child at
///   (40, 10). And the same centred both ways: the content box is 40×40 at (40, 10),
///   so the child is at (40 + 10, 10 + 15) = (50, 25).
///
/// Mutation that must redden it: **M3e**, padding registered outside the size
/// frame (the sized column reads 160×120).
@MainActor
@Test func aLoweredContainerPaddingSitsInsideItsDeclaredSize() throws {
    let chrome = LayoutDifferential.report(width: 400, height: 100) {
        Box(style: {
            var row = Style()
            row.flexDirection = .row
            row.gap = Axes(both: .pixels(px(12)))
            row.padding = Edges(all: .pixels(px(12)))
            row.alignItems = .center
            return row
        }(), decoration: Decoration(background: .surface, cornerRadius: px(12))) {
            chromeButton("-", "Decrement")
            Box { Text("Count 0").font(size: 22) }
                .cssWidth(px(140)).cssHeight(px(36)).alignItems(.center).justifyContent(.center)
            chromeButton("+", "Increment")
        }
    }
    // root, chrome, three boxes, three texts
    try #require(chrome.elements == 8)
    expectNothingReported(chrome, "counter chrome")
    #expect(lowered(chrome, [containerID, child(containerID, 0), child(containerID, 1), child(containerID, 2)])
            == [bounds(0, 0, 260, 60), bounds(12, 12, 36, 36), bounds(60, 12, 140, 36),
                bounds(212, 12, 36, 36)])
    let decrement = child(containerID, 0), increment = child(containerID, 2)
    #expect(chrome.frame.scene.glyphs.count == 8, "\(chrome.frame.scene.glyphs.count)")
    #expect(chrome.frame.hitboxes.count == 2, "\(chrome.hitboxRects)")
    #expect(chrome.hitboxRects == [decrement: bounds(12, 12, 36, 36), increment: bounds(212, 12, 36, 36)])
    #expect(chrome.accessibilityFrames[decrement] == bounds(12, 12, 36, 36))
    #expect(chrome.accessibilityFrames[increment] == bounds(212, 12, 36, 36))

    for (align, justify, at) in [(AlignItems.flexStart, JustifyContent.flexStart, (Float(40), Float(10))),
                                 (AlignItems.center, JustifyContent.center, (Float(50), Float(25)))] {
        var column = Style()
        column.flexDirection = .column
        column.alignItems = align
        column.justifyContent = justify
        column.size = Size(width: .length(.pixels(px(100))), height: .length(.pixels(px(80))))
        column.padding = Edges(top: .pixels(px(10)), right: .pixels(px(20)),
                               bottom: .pixels(px(30)), left: .pixels(px(40)))
        let sized = LayoutDifferential.report(width: 200, height: 200) {
            Box(style: column) { fixed(20, 10) }.background(.accent)
        }
        try #require(sized.elements == 3)
        expectNothingReported(sized, "sized padded column \(align)")
        #expect(lowered(sized, [containerID, child(containerID, 0)])
                == [bounds(0, 0, 100, 80), bounds(at.0, at.1, 20, 10)], "sized padded column \(align)")
    }
}

// MARK: - 3.5 — CSS-only behaviour, lowered only where CSS cannot show it

/// **3.5.** `stretch` and `space-*` distribution lower only where there is no free
/// space for them to distribute (ruling LR-E principle 3); everything else in the
/// container table's "otherwise" column is reported by name.
///
/// Lowerable (compared with the legacy engine until stage 9; literal rects since):
/// - a single-child `Box` (default `alignItems`, CSS `stretch`) with no declared
///   cross size, over a 20×10: container 20×10;
/// - the same over a `Row` of two fixed children (an auto cross size the stretch
///   could reach): container 30×20, the row stretched to its own 20;
/// - a `Row` of 20×10 and 30×10 with `.spaceBetween` and no main size: 50×10.
///
/// Reported (the report is exactly the one entry, in order):
/// - two-child stretch row (`Box { 20×10; Box().width(20) }`): `alignItems.stretch`
///   — the legacy engine stretches the second child to 10 tall;
/// - single-child stretch with a declared cross size (`.height(30)`):
///   `alignItems.stretch`;
/// - `.baseline`: `alignItems.baseline`;
/// - `.wrap`: `flexWrap`; an `alignContent`: `alignContent`;
/// - a main-axis gap in percent: `gap.percent` (a cross-axis percent gap is read by
///   nothing on a single line and is not reported);
/// - every-node rows on a container: `margin` (`…unconsumed` under the harness root
///   since stage 2); `border.percent` (stage 2's lane 4 replaced this arm's
///   `padding.floor`, which now lowers — spec 4.3);
/// - a hidden container reports `display.none` alone, even with a reverse direction;
/// - a `Box` container declaring `display: .stack` reported `noLowering` in lane 3 —
///   added after mutation M3l (the check deleted, so the stack lowered as a flex
///   row) left the suite green; since lane 4 it lowers as an overlay, and with its
///   `nil` alignments reports `[alignItems.stretch, justifyItems.stretch]` (ruling
///   LR-Y's amendment, spec 4.1).
///
/// Mutation that must redden it: **M3f**, stretch always lowerable (the two-child
/// arm reports nothing and disagrees); each reported row's check deleted reddens
/// its own arm (record §18, lane 3, M3i–M3r).
///
/// **Amended in stage 2, lane 1** (rulings LR-AB, LR-AC, LR-AQ). Stretch is no
/// longer a container row: each child it reaches is wrapped in a greedy item frame.
/// The two-child arm (now declaring a 30pt cross size, so the harness root's
/// proposal is not what the stretch fills) and the sized single-child arm agree —
/// the auto child 20×30 on both sides — and so does a `Box` declaring `display:
/// .stack` (its `nil` items stretch per child, 1.9). A container's `margin` is an
/// item field its parent reads: under the harness root it reports
/// `margin.unconsumed`. M3f's premise (stretch reported) is gone, and stretch's own
/// mutations are lane 1's (M1a–M1d).
///
/// **Amended and renamed in stage 2, lane 5** (ruling LR-AJ), from
/// `stretchAndSpaceDistributionLowerOnlyWhereTheLegacyEngineCannotShowThem`: its
/// other half lowered too, so nothing named in the old name is reported any more and
/// the name would have been a lie. What is left is the container table's inventory —
/// every container field either lowers and agrees, or is reported by name — so the
/// five `space-*` and reverse arms stay here. **After the lane's verification** they
/// go through `LayoutDifferential.compare` rather than a proposal-only render, so
/// their rects, hitboxes, accessibility and state slots are compared here as well as
/// their reports: `LoweringDistributionTests.swift` (5.1, 5.2, 5.5) pins the same
/// mechanisms in depth at other shapes, but every reverse arm there declares a main
/// size or is grown by its parent, so an unsized, ungrown reverse container was
/// pinned by nothing. The hidden
/// reverse container still reports `display.none` alone, which is the arm that shows
/// `display: none` is checked before the direction.
///
/// **Stage 9** (record §51, lane 1; `LR-FE` item 2): the comparison is gone, so
/// lane 5's five arms — whose rects only the agreement carried — gain literals,
/// derived by hand before the run: sized `spaceBetween` 100×10, a (0, 0), b (70, 0);
/// sized `spaceAround` (a column, centred cross) 30×100, free 80 shared 40 per item
/// half each side, a (5, 20) 20×10, b (0, 70) 30×10; sized `spaceEvenly` 100×10,
/// free 50 in three gaps of 16⅔, a at 16⅔ and b at 53⅓, rounded to (17, 0) and
/// (53, 0); unsized `rowReverse` 50×10, a (30, 0), b (0, 0); unsized
/// `columnReverse` (centred) 30×20, b (0, 0), a (5, 10). **Renamed** from
/// `everyContainerFieldEitherLowersAndAgreesOrIsReportedByName` (`LR-FE` item 6).
@MainActor
@Test func everyContainerFieldEitherLowersOrIsReportedByName() throws {
    let single = LayoutDifferential.report(width: 100, height: 100) { Box { fixed(20, 10) } }
    try #require(single.elements == 3)
    expectNothingReported(single, "single-child stretch")
    #expect(lowered(single, [containerID, child(containerID, 0)])
            == [bounds(0, 0, 20, 10), bounds(0, 0, 20, 10)])

    let singleRow = LayoutDifferential.report(width: 100, height: 100) {
        Box { Row { fixed(10, 20); fixed(20, 10) } }
    }
    try #require(singleRow.elements == 5)
    expectNothingReported(singleRow, "single-child stretch over a row")
    #expect(lowered(singleRow, [containerID, child(containerID, 0)])
            == [bounds(0, 0, 30, 20), bounds(0, 0, 30, 20)])

    let unsizedSpace = LayoutDifferential.report(width: 100, height: 100) {
        Row { fixed(20, 10); fixed(30, 10) }.justifyContent(.spaceBetween)
    }
    try #require(unsizedSpace.elements == 4)
    expectNothingReported(unsizedSpace, "unsized spaceBetween")
    #expect(lowered(unsizedSpace, [containerID, child(containerID, 1)])
            == [bounds(0, 0, 50, 10), bounds(20, 0, 30, 10)])

    // Stage 2, lane 1: the two-child stretch lowers (a greedy item frame, aliased) and
    // agrees, the auto-height child stretched to the declared 30 on both sides.
    let twoChild = LayoutDifferential.report(width: 100, height: 100) {
        Box { fixed(20, 10); Box().cssWidth(px(20)).background(.accent) }.cssHeight(px(30))
    }
    try #require(twoChild.elements == 4)
    expectNothingReported(twoChild, "two-child stretch")
    #expect(lowered(twoChild, [child(containerID, 0), child(containerID, 1)])
            == [bounds(0, 0, 20, 10), bounds(20, 0, 20, 30)])
    let sizedSingle = LayoutDifferential.report(width: 100, height: 100) {
        Box { Box().cssWidth(px(20)).background(.accent) }.cssHeight(px(30))
    }
    try #require(sizedSingle.elements == 3)
    expectNothingReported(sizedSingle, "sized single-child stretch")
    #expect(lowered(sizedSingle, [child(containerID, 0)]) == [bounds(0, 0, 20, 30)])

    func percentGap(_ axes: Axes<Length>) -> Style {
        var s = Style()
        s.gap = axes
        s.alignItems = .flexStart
        return s
    }
    // Stage 2, lane 4: a declared size below the padding sum no longer reports (the
    // fixed frame wins, spec 4.3), so this arm carries the every-node row lane 4 adds
    // instead — a percentage border, which has no containing block here (`LR-AI`).
    func percentBorder() -> Style {
        var s = Style()
        s.alignItems = .flexStart
        s.border = Edges(top: .pixels(px(0)), right: .percent(0.1),
                         bottom: .pixels(px(0)), left: .pixels(px(0)))
        return s
    }
    typealias Arm = (name: String, entries: [UnlowerableField], expected: [UnlowerableField])
    func report<C: ElementGroup>(@ElementBuilder _ make: @MainActor () -> C) -> [UnlowerableField] {
        LayoutDifferential.render(width: 100, height: 100, make).unlowerableFields
    }
    // Lane 5's five arms went through `LayoutDifferential.compare`, not `report`, so
    // the **agrees** half of this test's old name was checked for them too (added
    // after the lane's verification, which found it was not): the two unsized
    // reverse arms are a shape `LoweringDistributionTests.swift` does not carry —
    // every reverse arm there declares a main size or is grown by its parent. Since
    // stage 9 their rects are literals (doc above).
    let pair = [containerID, child(containerID, 0), child(containerID, 1)]
    let sizedBetween = LayoutDifferential.report(width: 100, height: 100) {
        Row { fixed(20, 10); fixed(30, 10) }.cssWidth(px(100)).justifyContent(.spaceBetween)
    }
    expectNothingReported(sizedBetween, "sized spaceBetween")
    #expect(lowered(sizedBetween, pair) == [bounds(0, 0, 100, 10), bounds(0, 0, 20, 10), bounds(70, 0, 30, 10)])
    let sizedAround = LayoutDifferential.report(width: 100, height: 100) {
        Column { fixed(20, 10); fixed(30, 10) }.cssHeight(px(100)).justifyContent(.spaceAround)
    }
    expectNothingReported(sizedAround, "sized spaceAround")
    #expect(lowered(sizedAround, pair) == [bounds(0, 0, 30, 100), bounds(5, 20, 20, 10), bounds(0, 70, 30, 10)])
    let sizedEvenly = LayoutDifferential.report(width: 100, height: 100) {
        Row { fixed(20, 10); fixed(30, 10) }.cssWidth(px(100)).justifyContent(.spaceEvenly)
    }
    expectNothingReported(sizedEvenly, "sized spaceEvenly")
    #expect(lowered(sizedEvenly, pair) == [bounds(0, 0, 100, 10), bounds(17, 0, 20, 10), bounds(53, 0, 30, 10)])
    let rowReverse = LayoutDifferential.report(width: 100, height: 100) {
        Box { fixed(20, 10); fixed(30, 10) }.flexDirection(.rowReverse).alignItems(.flexStart)
    }
    expectNothingReported(rowReverse, "unsized rowReverse")
    #expect(lowered(rowReverse, pair) == [bounds(0, 0, 50, 10), bounds(30, 0, 20, 10), bounds(0, 0, 30, 10)])
    let columnReverse = LayoutDifferential.report(width: 100, height: 100) {
        Box { fixed(20, 10); fixed(30, 10) }.flexDirection(.columnReverse).alignItems(.center)
    }
    expectNothingReported(columnReverse, "unsized columnReverse")
    #expect(lowered(columnReverse, pair) == [bounds(0, 0, 30, 20), bounds(5, 10, 20, 10), bounds(0, 0, 30, 10)])
    let arms: [Arm] = [
        ("two-child stretch (lowered since stage 2)", twoChild.unlowerable, []),
        ("sized single-child stretch (lowered since stage 2)", sizedSingle.unlowerable, []),
        ("sized spaceBetween (lowered since lane 5)", sizedBetween.unlowerable, []),
        ("sized spaceAround (lowered since lane 5)", sizedAround.unlowerable, []),
        ("sized spaceEvenly (lowered since lane 5)", sizedEvenly.unlowerable, []),
        ("rowReverse (lowered since lane 5)", rowReverse.unlowerable, []),
        ("columnReverse (lowered since lane 5)", columnReverse.unlowerable, []),
        ("baseline", report { Row { fixed(20, 10); fixed(30, 10) }.alignItems(.baseline) },
         [field(.box, "alignItems.baseline")]),
        ("wrap", report { Row { fixed(20, 10); fixed(30, 10) }.flexWrap(.wrap) }, [field(.box, "flexWrap")]),
        ("alignContent", report { Row { fixed(20, 10); fixed(30, 10) }.alignContent(.center) },
         [field(.box, "alignContent")]),
        ("row main-axis gap percent",
         report { Box(style: percentGap(Axes(horizontal: .percent(0.1), vertical: .pixels(px(4))))) {
             fixed(20, 10); fixed(30, 10)
         } }, [field(.box, "gap.percent")]),
        ("row cross-axis gap percent (not read)",
         report { Box(style: percentGap(Axes(horizontal: .pixels(px(4)), vertical: .percent(0.1)))) {
             fixed(20, 10); fixed(30, 10)
         } }, []),
        ("margin on a container (an item field: unconsumed under the harness root since stage 2)",
         report { Row { fixed(20, 10) }.margin(px(3)) }, [field(.box, "margin.unconsumed")]),
        ("border percent on a container", report { Box(style: percentBorder()) { fixed(20, 10) } },
         [field(.box, "border.percent")]),
        ("display: .stack on a Box container (lowered as an overlay since lane 4, its stretch since stage 2)",
         report { Box(style: { var s = Style(); s.display = .stack; return s }()) {
             fixed(20, 10); fixed(30, 10)
         } }, []),
        ("hidden reverse container (lowered as if shown since stage 6b, LR-DH)",
         report { Box { fixed(20, 10); fixed(30, 10) }.flexDirection(.rowReverse).hidden() },
         []),
    ]
    try #require(arms.count == 16)
    for arm in arms {
        #expect(arm.entries == arm.expected, "\(arm.name): \(arm.entries)")
    }
}

// MARK: - 3.6 — overflow

/// **3.6.** A fixed-size child in a container too small for it: CSS shrinks it
/// (`flexShrink` 1, divergence 55), SwiftUI's stack does not compress a fixed child
/// and overflows (stack-algorithms probe **G9**: `HStack(spacing: 0) { a fixed 80;
/// b fixed 80 }` at 100×50 answers 160×20, a at x 0, b at x 80; **X13**, the
/// nil-proposal control, 160×20). `Row { 80×20; 80×20 }.width(100)`: legacy children
/// 50 wide at x 0 and 50; lowered 80 wide at x 0 and 80, the row itself 100×20 on
/// both sides. Not a diagnostic (ruling LR-I): the report is empty.
///
/// Mutation that must redden it: **M3g**, the size frame aligned `.center` (the
/// lowered children at x −30 and 50).
///
/// **Renamed at stage 9** from `aLoweredRowOverflowsWhereTheLegacyRowShrinksItsChildren`
/// (`LR-FE` item 6); the legacy half (50-wide children, and the `#require` that
/// the two sides differ) went with the legacy engine.
@MainActor
@Test func aLoweredRowLetsItsFixedChildrenOverflowItsDeclaredWidth() throws {
    let r = LayoutDifferential.report(width: 200, height: 100) {
        Row { fixed(80, 20); fixed(80, 20) }.cssWidth(px(100))
    }
    try #require(r.elements == 4)
    #expect(r.unlowerable.isEmpty, "\(r.unlowerable)")
    let a = child(containerID, 0), b = child(containerID, 1)
    #expect(r.bounds[containerID] == bounds(0, 0, 100, 20))
    #expect(r.bounds[a] == bounds(0, 0, 80, 20))
    #expect(r.bounds[b] == bounds(80, 0, 80, 20))
}

// MARK: - 3.7 — mixed trees (LR-T)

/// The mixed tree of ruling LR-T: a legacy `Column` over a legacy `Box`, a proposal
/// `HStack` and a framed `ProposalScrollView`.
@MainActor
private func mixedTree() -> some ElementGroup {
    Column(gap: px(4)) {
        fixed(30, 10)
        HStack(spacing: px(0)) {
            Rectangle(width: px(20), height: px(20), color: .accent)
            Rectangle(width: px(20), height: px(20), color: .accent)
        }
        ProposalScrollView(.vertical, elementID: ElementID("mixed-scroller")) {
            VStack(spacing: px(0)) {
                Rectangle(width: px(100), height: px(400), color: .accent)
            }
        }
        .frame(width: px(100), height: px(100))
    }
}

/// **3.7** (ruling LR-T). A proposal element inside a lowered legacy container is a
/// single-authority tree and lays out.
///
/// Proposal arm, inside the 300×300 harness root: the report is empty; the
/// `Column` (centred, gap 4) is max(30, 40, 100) = 100 wide and 10 + 4 + 20 + 4 +
/// 100 = 138 tall; the `Box` at ((100 − 30)/2, 0) = (35, 0); the `HStack` at
/// ((100 − 40)/2, 14) = (30, 14), 40×20; the framed scroller at (0, 38), 100×100;
/// exactly one scroll region, at (0, 38) 100×100. Through a real `Window`, a wheel
/// event of −37 at (50, 80) moves that region's
/// `ScrollState` offset to 37.
///
/// **Stage 9**: its legacy arm (an exit test: under the legacy authority the same
/// tree trapped in `newNode`, `SA-G`) went with the legacy authority, and the test
/// was **renamed** from
/// `aProposalElementInsideALoweredContainerLaysOutUnderTheProposalAuthorityAndTrapsUnderTheLegacyOne`
/// (`LR-FE` item 6).
///
/// The report's emptiness is a `try #require`: the `Window` renders without
/// diagnostics, so a report would trap there and truncate the suite.
///
/// Mutation that must redden it: **M3h**, the container branch reports
/// `box.nativeChild` for a native child (the proposal arm's empty report).
@MainActor
@Test func aProposalElementInsideALoweredContainerLaysOut() throws {
    let frame = LayoutDifferential.render(width: 300, height: 300) { mixedTree() }
    // `#require`, not `#expect`: the window below renders WITHOUT diagnostics, so
    // any report here would trap there and end the run with no summary line
    // (practices shape 13 — measured on this test's own red run).
    try #require(frame.unlowerableFields.isEmpty, "\(frame.unlowerableFields)")
    let column = containerID
    #expect(frame.elementBounds[column] == bounds(0, 0, 100, 138))
    #expect(frame.elementBounds[child(column, 0)] == bounds(35, 0, 30, 10))
    #expect(frame.elementBounds[child(column, 1)] == bounds(30, 14, 40, 20))
    #expect(frame.elementBounds[child(column, 2)] == bounds(0, 38, 100, 100))
    let regions = frame.scrollRegions
    try #require(regions.count == 1)
    #expect(regions[0].bounds == bounds(0, 38, 100, 100))

    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 300) {
        DifferentialRoot(width: 300, height: 300) { mixedTree() }
    }
    window.drawFrameIfNeeded()
    let region = try #require(window.lastScrollRegions.first)
    #expect(window.lastScrollRegions.count == 1)
    #expect(region.bounds == bounds(0, 38, 100, 100))
    platformWindow.simulateInput(.scrollWheel(ScrollEvent(
        position: Point(x: px(50), y: px(80)),
        delta: Point(x: px(0), y: px(-37))
    )))
    #expect(window.stateTable.peek(region.id, as: ScrollState.self)?.offset == 37)
}

// MARK: - 3.8, 3.9 — verifier round (animation, report order)

/// **3.8.** A lowered container lays out its **animated** style, not its declared
/// one (lane 2's 2.3c pinned this for a leaf; the container branch has its own
/// call). A row `Box` (`alignItems` `.flexStart`) over two 10×10 children animates
/// width 40 → 120, padding 0 → 8 and main-axis gap 0 → 20 under
/// `withAnimation(.linear(duration: 1))`. Derived by hand (and held under both
/// authorities until stage 9 deleted the legacy one):
///
/// - the frame that starts the transaction: container (0, 0) 40×10, a (0, 0),
///   b (10, 0);
/// - half-way (t = 0.5): width 80, padding 4, gap 10 — container (0, 0) 80×18,
///   a (4, 4), b (4 + 10 + 10, 4) = (24, 4).
///
/// Mutation that must redden it: **V1**, the container branch lays out `declared`
/// (size frame, padding and `declared.gap`): the lowered container reads 120 wide
/// and b at x 36 on both frames.
@MainActor
@Test func aLoweredContainerLaysOutItsAnimatedWidthPaddingAndGap() throws {
    func containerStyle(width: Float, padding: Float, gap: Float) -> Style {
        var s = Style()
        s.flexDirection = .row
        s.alignItems = .flexStart
        s.size = Size(width: .length(.pixels(px(width))), height: .auto)
        s.padding = Edges(all: .pixels(px(padding)))
        s.gap = Axes(horizontal: .pixels(px(gap)), vertical: .pixels(px(0)))
        return s
    }
    let a = child(containerID, 0), b = child(containerID, 1)
    let table = StateTable()
    func rects(_ s: Style, timestamp: Double, animating: Bool) -> [Bounds<Pixels>?] {
        let box = Box(style: s) { fixed(10, 10); fixed(10, 10) }
        var root = DifferentialRoot(width: 200, height: 100) { box }
        let frame = Frame(contentSize: Size(width: Pixels(200), height: Pixels(100)), scaleFactor: 1,
                          stateTable: table, timestamp: timestamp,
                          transaction: animating ? .linear(duration: 1) : nil,
                          reportsUnlowerableFields: true,
                          recordsElementBounds: true)
        frame.render(&root)
        #expect(frame.unlowerableFields.isEmpty, "\(frame.unlowerableFields)")
        return [containerID, a, b].map { frame.elementBounds[$0] }
    }
    let start = containerStyle(width: 40, padding: 0, gap: 0)
    let end = containerStyle(width: 120, padding: 8, gap: 20)
    #expect(rects(start, timestamp: 0, animating: false)
            == [bounds(0, 0, 40, 10), bounds(0, 0, 10, 10), bounds(10, 0, 10, 10)], "baseline")
    #expect(rects(end, timestamp: 0, animating: true)
            == [bounds(0, 0, 40, 10), bounds(0, 0, 10, 10), bounds(10, 0, 10, 10)],
            "transaction start")
    #expect(rects(end, timestamp: 0.5, animating: false)
            == [bounds(0, 0, 80, 18), bounds(4, 4, 10, 10), bounds(24, 4, 10, 10)], "half-way")
}

/// A container declaring two container rows (`gap.percent`, `flexWrap`) and two
/// every-node rows (`position`, `inset`). **Re-spelled in stage 2, lane 1** from
/// `margin` and `flexGrow`, item fields its parent reads since then (ruling LR-AB;
/// under the harness root they report `…unconsumed` after the root returns, LR-AQ),
/// and **again in lane 5**, which lowered `reverse` (ruling LR-AJ): a percentage
/// main-axis gap took its place as the first container row.
@MainActor
private func fourFieldContainer() -> some ElementGroup {
    var style = Style()
    style.alignItems = .flexStart
    style.gap = Axes(horizontal: .percent(0.1), vertical: .pixels(px(4)))
    style.flexWrap = .wrap
    style.position = .relative
    style.inset = Edges(all: .length(.pixels(px(3))))
    return Box(style: style) { fixed(20, 10); fixed(30, 10) }
}

/// **3.9.** `LR-Y`'s report order: a container's rows in §5.4's table order, then
/// the every-node rows in theirs — `[gap.percent, flexWrap, position, inset]` — and
/// in production (diagnostics off) the trap names the **first**, `box.gap.percent`.
///
/// Mutation that must redden it: **V2**, `legacyLeafDiagnostics(…) + fields` (the
/// report reads `[position, inset, gap.percent, flexWrap]` and the trap names
/// `box.position`).
@MainActor
@Test func aContainersReportListsItsContainerRowsBeforeItsEveryNodeRowsAndTrapsOnTheFirst() async throws {
    let entries = LayoutDifferential.render(width: 100, height: 100) {
        fourFieldContainer()
    }.unlowerableFields
    #expect(entries == [field(.box, "gap.percent"), field(.box, "flexWrap"),
                        field(.box, "position"), field(.box, "inset")], "\(entries)")

    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        await MainActor.run {
            var root = DifferentialRoot(width: 100, height: 100) { fourFieldContainer() }
            Frame(contentSize: Size(width: Pixels(100), height: Pixels(100)), scaleFactor: 1).render(&root)
        }
    }
    let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(stderr.contains("box.gap.percent has no proposal lowering"),
            "aborted, but not at the first unlowerable field:\n\(stderr)")
    #expect(!stderr.contains("box.position"), "the trap must name the first field:\n\(stderr)")
}
