import Testing
import MetalUICore
@testable import MetalUILayout

private func px(_ v: Double) -> Dimension { .length(.pixels(Pixels(Float(v)))) }

/// A container reports the size its own children imply, with no layout written.
@Test func measuringARowContainerReturnsItsContentSize() {
    let tree = LayoutTree(generation: 0)
    var kid = Style()
    kid.size = Size(width: px(60), height: px(20))
    let a = tree.newNode(style: kid, children: [])
    let b = tree.newNode(style: kid, children: [])

    var row = Style()
    row.flexDirection = .row
    let container = tree.newNode(style: row, children: [a, b])

    let ctx = LayoutContext(rootFontSize: 16)
    let size = measureNode(ctx, tree, container,
                           known: .unspecified,
                           available: AvailableSpaceSize(width: .maxContent,
                                                         height: .maxContent),
                           containingBlockWidth: nil)
    #expect(size.width == 120)
    #expect(size.height == 20)
}

/// **The purity guard.** A `measureNode` that called `setLayout` would return
/// the correct size and pass every golden in the corpus; this is the only thing
/// that can see it. Asserts on the stored rects of *every* node, not just the
/// container's, because the recursion writes children first.
@Test func measuringWritesNoLayout() {
    let tree = LayoutTree(generation: 0)
    var kid = Style()
    kid.size = Size(width: px(60), height: px(20))
    let a = tree.newNode(style: kid, children: [])
    var row = Style()
    row.flexDirection = .row
    let container = tree.newNode(style: row, children: [a])

    let sentinel = LayoutRect(x: -1, y: -2, width: -3, height: -4)
    tree.setLayout(a, sentinel)
    tree.setLayout(container, sentinel)

    let ctx = LayoutContext(rootFontSize: 16)
    _ = measureNode(ctx, tree, container, known: .unspecified,
                    available: AvailableSpaceSize(width: .maxContent, height: .maxContent),
                    containingBlockWidth: nil)

    #expect(tree.layout(a) == sentinel)
    #expect(tree.layout(container) == sentinel)
}

/// A known size wins over the measured one — the `known` half of §5.5's contract.
@Test func aKnownSizeOverridesTheMeasuredOne() {
    let tree = LayoutTree(generation: 0)
    var kid = Style()
    kid.size = Size(width: px(60), height: px(20))
    let a = tree.newNode(style: kid, children: [])
    var row = Style()
    row.flexDirection = .row
    let container = tree.newNode(style: row, children: [a])

    let ctx = LayoutContext(rootFontSize: 16)
    let size = measureNode(ctx, tree, container,
                           known: OptionalSizeD(width: 200, height: nil),
                           available: AvailableSpaceSize(width: .definite(200),
                                                         height: .maxContent),
                           containingBlockWidth: nil)
    #expect(size.width == 200)
    #expect(size.height == 20)
}

/// A leaf with a measure function answers from it, so callers cannot tell a
/// leaf from a container. `newLeaf` has no production caller — this builds one.
@Test func measuringALeafUsesItsMeasureFunction() {
    let tree = LayoutTree(generation: 0)
    let leaf = tree.newLeaf(style: Style()) { _, available in
        if case .minContent = available.width { return SizeD(width: 30, height: 40) }
        return SizeD(width: 90, height: 20)
    }
    let ctx = LayoutContext(rootFontSize: 16)
    let wide = measureNode(ctx, tree, leaf, known: .unspecified,
                           available: AvailableSpaceSize(width: .maxContent, height: .maxContent),
                           containingBlockWidth: nil)
    let narrow = measureNode(ctx, tree, leaf, known: .unspecified,
                             available: AvailableSpaceSize(width: .minContent, height: .maxContent),
                             containingBlockWidth: nil)
    #expect(wide == SizeD(width: 90, height: 20))
    #expect(narrow == SizeD(width: 30, height: 40))
}

/// A container with no children measures 0, not a trap. Such a node no longer
/// reaches `layOutChildren` from `measureNode`: it is answered in closed form,
/// by its own padding and border (`LeafProbeShortcutTests.swift`). A flex
/// container whose children are all `display: none` or absolute still reaches
/// `layOutChildren`, and its `guard !items.isEmpty` is what produces the 0.
@Test func measuringAnEmptyContainerIsZeroNotATrap() {
    let tree = LayoutTree(generation: 0)
    let container = tree.newNode(style: Style(), children: [])
    let ctx = LayoutContext(rootFontSize: 16)
    let size = measureNode(ctx, tree, container, known: .unspecified,
                           available: AvailableSpaceSize(width: .maxContent, height: .maxContent),
                           containingBlockWidth: nil)
    #expect(size == SizeD.zero)
}

/// What `measureNode` reports is the **border** box, so padding and border sit
/// outside the extent the children imply.
///
/// Every other test in this file has zero padding and zero border, so dropping
/// the edge term reddens nothing there — and the omission would be silent
/// rather than wrong-looking, because the `known` branch above *does* answer in
/// border-box units (`known` is handed straight to `layOutChildren` as the
/// container's border box). Mixing the two units in one return value is the
/// defect this pins.
///
/// Four distinct padding edges plus a border, so a transposed edge or a
/// horizontal/vertical swap cannot cancel out (taxonomy shape 1).
@Test func measuringAContainerReportsItsBorderBoxNotItsContentBox() {
    let tree = LayoutTree(generation: 0)
    var kid = Style()
    kid.size = Size(width: px(60), height: px(20))
    let a = tree.newNode(style: kid, children: [])

    var row = Style()
    row.flexDirection = .row
    row.padding = Edges(top: .pixels(Pixels(5)), right: .pixels(Pixels(7)),
                        bottom: .pixels(Pixels(9)), left: .pixels(Pixels(11)))
    row.border = Edges(all: .pixels(Pixels(2)))
    let container = tree.newNode(style: row, children: [a])

    let ctx = LayoutContext(rootFontSize: 16)
    let size = measureNode(ctx, tree, container, known: .unspecified,
                           available: AvailableSpaceSize(width: .maxContent,
                                                         height: .maxContent),
                           containingBlockWidth: nil)
    // 60 + (11 + 7) padding + (2 + 2) border = 82.
    // 20 + (5 + 9) padding + (2 + 2) border = 38.
    #expect(size.width == 82)
    #expect(size.height == 38)
}

/// The measured size of a **multi-line** container, with a different gap on
/// each axis and a different margin on each edge.
///
/// Everything else in this file is one line, gapless and marginless — the
/// degenerate case of `contentSize`, which is the only arithmetic in this task
/// that was written rather than moved. Review mutated both of its terms against
/// the six tests that existed then and **neither reddened anything**: dropping
/// the margins from the main total, and dropping `crossGap * (n - 1)` from the
/// cross total. Both redden here.
///
/// The numbers, so a failure is diagnosable rather than mysterious. The probe
/// width is definite at 200 and the height indefinite, so the main axis wraps
/// and the cross axis is measured from the items:
///
/// - each item's outer main extent is `3 + 60 + 5 = 68`;
/// - `68 + 10 + 68 = 146` fits in 200 and `+ 10 + 68 = 224` does not, so the
///   lines are `[a, b]` and `[c]`, and the widest is **146**;
/// - each item's outer cross extent is `2 + 20 + 4 = 26`, one line each way,
///   plus the 7px CROSS gap between them: **59**.
///
/// Every one of those constants is distinct from every other, so a
/// horizontal/vertical swap, a leading/trailing swap or a dropped term all land
/// somewhere other than (146, 59). No edge falls on an `x.5`.
@Test func measuringAWrappedContainerCountsGapsAndMargins() {
    let tree = LayoutTree(generation: 0)
    var kid = Style()
    kid.size = Size(width: px(60), height: px(20))
    kid.margin = Edges(top: px(2), right: px(5), bottom: px(4), left: px(3))
    let a = tree.newNode(style: kid, children: [])
    let b = tree.newNode(style: kid, children: [])
    let c = tree.newNode(style: kid, children: [])

    var row = Style()
    row.flexDirection = .row
    row.flexWrap = .wrap
    row.gap = Axes(horizontal: .pixels(Pixels(10)), vertical: .pixels(Pixels(7)))
    let container = tree.newNode(style: row, children: [a, b, c])

    let ctx = LayoutContext(rootFontSize: 16)
    let size = measureNode(ctx, tree, container, known: .unspecified,
                           available: AvailableSpaceSize(width: .definite(200),
                                                         height: .maxContent),
                           containingBlockWidth: nil)
    #expect(size.width == 146)
    #expect(size.height == 59)
}

// MARK: - An indefinite axis (ruling CS-D)
//
// Every test above sizes its children in pixels, uses no gap and no margins,
// and that is the one shape for which `.infinity` and "indefinite" agree. These
// three are the shapes for which they do not, and each of them **killed the
// test process** before ruling CS-D: `Fatal error: §9.7 freeze loop did not
// converge` at `ResolveFlexibleLengths.swift`, signal 5, no summary line and
// every other test's result destroyed with it (taxonomy shape 11).
//
// That is also why all three run in a subprocess. Their failure mode is a trap,
// not a wrong number, and ruling CS-C says a trap belongs behind
// `processExitsWith`. The `#expect`s inside each body still do the real work —
// a wrong number records an issue in the child, which exits non-zero, which
// reddens the parent — and the child's stderr is surfaced so the failure is
// readable rather than just an exit code.

/// `flex-grow` does not apply on an axis with no definite size: free space is
/// indefinite, so §9.7 has nothing to distribute and the item keeps the size
/// §9.7.2 would freeze it at — its **hypothetical** main size, which is its
/// flex base size clamped by its own min/max, not the raw base.
///
/// **The `min-width` is what makes those two different numbers**, and without
/// it this test cannot see the distinction its own branch is written around:
/// with a plain 60px child, base and hypothetical are both 60, and mutating the
/// indefinite branch from `hypotheticalMainSize` to `baseSize` reddened **0 of
/// 322** (taxonomy shape 1 — uniform values on both sides of the assertion).
/// Base 60, floored to 90 by `min-width`, so the mutation now lands on 60 and
/// this expects 90. §9.9.1.1's own wording for this clamp is "clamped by the
/// max main size floored by the min main size".
///
/// The grow half stays visible too: 90 is the floor, not a ceiling, so an item
/// that *had* grown would report more than 90 rather than the same 90 — which
/// is why this uses `min-width` and not `max-width`.
@Test func aGrowingItemUnderMaxContentKeepsItsHypotheticalMainSize() async {
    let result = await #expect(processExitsWith: .success,
                               observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        var kid = Style()
        kid.size = Size(width: .length(.pixels(Pixels(60))),
                        height: .length(.pixels(Pixels(20))))
        kid.minSize = Size(width: .length(.pixels(Pixels(90))), height: .auto)
        kid.flexGrow = 1
        let a = tree.newNode(style: kid, children: [])
        var row = Style()
        row.flexDirection = .row
        let container = tree.newNode(style: row, children: [a])

        let size = measureNode(LayoutContext(rootFontSize: 16), tree, container,
                               known: .unspecified,
                               available: AvailableSpaceSize(width: .maxContent,
                                                             height: .maxContent),
                               containingBlockWidth: nil)
        #expect(size == SizeD(width: 90, height: 20))
    }
    let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(stderr.isEmpty, "the child wrote:\n\(stderr)")
}

/// A percentage size against an indefinite basis is unresolvable, so the item
/// falls through §9.2's cascade to its content size — 0, with no measure
/// function. The 40px sibling is there so the answer is not uniformly zero:
/// dropping the percentage child entirely gives the same 40, and dropping the
/// *indefiniteness* gives a nonzero contribution instead.
@Test func aPercentageSizedItemUnderMaxContentContributesNothing() async {
    let result = await #expect(processExitsWith: .success,
                               observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        var fixed = Style()
        fixed.size = Size(width: .length(.pixels(Pixels(40))),
                          height: .length(.pixels(Pixels(20))))
        let a = tree.newNode(style: fixed, children: [])
        var half = Style()
        half.size = Size(width: .length(.percent(0.5)),
                         height: .length(.pixels(Pixels(20))))
        let b = tree.newNode(style: half, children: [])
        var row = Style()
        row.flexDirection = .row
        let container = tree.newNode(style: row, children: [a, b])

        let size = measureNode(LayoutContext(rootFontSize: 16), tree, container,
                               known: .unspecified,
                               available: AvailableSpaceSize(width: .maxContent,
                                                             height: .maxContent),
                               containingBlockWidth: nil)
        #expect(size == SizeD(width: 40, height: 20))
    }
    let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(stderr.isEmpty, "the child wrote:\n\(stderr)")
}

/// A percentage `gap` against an indefinite basis resolves to 0 — CSS's rule
/// for an unresolvable percentage. Under `.infinity` it was an *infinite* gap —
/// `inf * 0.1` is `inf` — and the line's budget `containerMain - totalGap` was
/// then `inf - inf`, i.e. NaN. That is the case that made the **container**,
/// not the item, the thing that could not be measured: the two children here
/// are ordinary fixed boxes.
@Test func aPercentageGapUnderMaxContentResolvesToZero() async {
    let result = await #expect(processExitsWith: .success,
                               observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        var kid = Style()
        kid.size = Size(width: .length(.pixels(Pixels(60))),
                        height: .length(.pixels(Pixels(20))))
        let a = tree.newNode(style: kid, children: [])
        let b = tree.newNode(style: kid, children: [])
        var row = Style()
        row.flexDirection = .row
        row.gap = Axes(horizontal: .percent(0.1), vertical: .percent(0.2))
        let container = tree.newNode(style: row, children: [a, b])

        let size = measureNode(LayoutContext(rootFontSize: 16), tree, container,
                               known: .unspecified,
                               available: AvailableSpaceSize(width: .maxContent,
                                                             height: .maxContent),
                               containingBlockWidth: nil)
        #expect(size == SizeD(width: 120, height: 20))
    }
    let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(stderr.isEmpty, "the child wrote:\n\(stderr)")
}
