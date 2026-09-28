import Testing
import MetalUICore
@testable import MetalUILayout

// Plan task 11 part 1, lane 2 (spec rows 2.1–2.6; ruling TE-K): every native
// node kind reports its text baselines as SwiftUI does, and a horizontal stack
// aligns by them. SwiftUI's numbers are `docs/probes/swiftui-text-semantics.swift`
// B1, B2 and X3, whose `Text` sizes and baselines the synthetic leaves below
// copy (at scale 2, SwiftUI's half-point widths): a 13 pt one-line text is
// 17.5 × 16 with both baselines 13, a 26 pt one 33.5 × 30 at 25, a two-line
// 13 pt one 17.5 × 32 at 13 and 29, and a colour 10 × 10 with none. A baseline
// is a distance from the node's own top edge; `nil` is "none", which a
// baseline alignment reads as the node's height (B1f, X3e).
//
// Runs on Linux and Windows CI (`MetalUILayoutTests`).

private func leaf(_ tree: LayoutTree, _ width: Double, _ height: Double,
                  first: Double? = nil, last: Double? = nil) -> LayoutNodeID {
    tree.newNativeLeaf { _ in
        LayoutMeasurement(size: SizeD(width: width, height: height), firstBaseline: first, lastBaseline: last ?? first)
    }
}

private func text13(_ tree: LayoutTree) -> LayoutNodeID { leaf(tree, 17.5, 16, first: 13) }
private func text26(_ tree: LayoutTree) -> LayoutNodeID { leaf(tree, 33.5, 30, first: 25) }
private func twoLines(_ tree: LayoutTree) -> LayoutNodeID { leaf(tree, 17.5, 32, first: 13, last: 29) }
private func colour(_ tree: LayoutTree, _ side: Double = 10) -> LayoutNodeID { leaf(tree, side, side) }

private let unspecified = ProposedSize(width: nil, height: nil)

/// Lays `build`'s root out at `unspecified` in bounds of its own answer and
/// returns the answer (size and both baselines).
private func measured(_ build: (LayoutTree) -> LayoutNodeID) -> LayoutMeasurement {
    let tree = LayoutTree(generation: 0)
    let root = build(tree)
    return tree.computeNativeLayout(root: root, proposal: unspecified, centredIn: LayoutRect(x: 0, y: 0, width: 400, height: 400))
}

private func baselines(_ m: LayoutMeasurement) -> [Double?] { [m.firstBaseline, m.lastBaseline] }

/// A custom layout answering its first child's size and, when `reports`, its
/// baselines — a custom node reports exactly what its `sizeThatFits` returns
/// (TE-K item 2 as amended by TE-X item 1): none unless it says so.
private struct BaselineReportingLayout: ProposalLayout {
    var reports: Bool
    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
        let child = subviews[0].sizeThatFits(proposal)
        return reports ? LayoutMeasurement(size: child.size, firstBaseline: child.firstBaseline,
                                           lastBaseline: child.lastBaseline)
                       : LayoutMeasurement(size: child.size)
    }
    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize, subviews: PlacementSubviews) {}
}

/// **2.1.** Per node kind (TE-K item 2): a `ZStack` of a 40 × 40 colour and a
/// 13 pt text reports 25 (B1k); an attachment keeps its primary's (X3g, X3h —
/// the colour's none, whatever its overlay); `fixedSize`, `layoutPriority` and
/// `aspectRatio` pass the child's through (X3f); a spacer and a scroll viewport
/// report none (X3: `ScrollView{Text}` is its height), a custom layout what
/// its `sizeThatFits` says (none unless it reports one; TE-X item 1); a
/// stack the min/max of its children's at their placed offsets — `VStack{13;
/// 26}` 13/41 (B1g), a centred `HStack{13; 26}` 20/25 (B1h) and `{26; 13}`
/// 20/25 (X3a), a text-less child skipped (`VStack{colour; 13}` 23, B1p;
/// `{13; colour}` 13, X3b), `HStack{colour}` none (B1f), bottom- and
/// top-aligned two-line rows 13/29 (X3c, X3d); a one-cell grid 13 (X3i);
/// padding and frame move it as before (B1i 21, B1j 30).
@Test func everyNodeKindReportsItsBaselineAsSwiftUIDoes() {
    #expect(baselines(measured { t in t.newNativeOverlay(children: [colour(t, 40), text13(t)]) }) == [25, 25])
    #expect(baselines(measured { t in t.newNativeOverlayAttachment(child: text13(t), overlay: colour(t, 30)) })
            == [13, 13])
    #expect(baselines(measured { t in t.newNativeOverlayAttachment(child: colour(t, 30), overlay: text13(t)) })
            == [nil, nil])
    #expect(baselines(measured { t in t.newNativeFixedSize(child: text13(t)) }) == [13, 13])
    #expect(baselines(measured { t in t.newNativeLayoutPriority(child: text13(t), priority: 1) }) == [13, 13])
    #expect(baselines(measured { t in t.newNativeAspectRatio(child: text13(t), ratio: 1, contentMode: .fit) })
            == [13, 13])
    #expect(baselines(measured { t in t.newNativeSpacer() }) == [nil, nil])
    #expect(baselines(measured { t in t.newNativeScrollViewport(child: text13(t), axis: .vertical) }) == [nil, nil])
    #expect(baselines(measured { t in
        t.newNativeLayout(BaselineReportingLayout(reports: false), children: [text13(t)])
    }) == [nil, nil])
    #expect(baselines(measured { t in
        t.newNativeLayout(BaselineReportingLayout(reports: true), children: [text13(t)])
    }) == [13, 13])

    #expect(baselines(measured { t in
        t.newNativeLinearStack(children: [text13(t), text26(t)], axis: .vertical)
    }) == [13, 41])
    #expect(baselines(measured { t in
        t.newNativeLinearStack(children: [text13(t), text26(t)], axis: .horizontal)
    }) == [20, 25])
    #expect(baselines(measured { t in
        t.newNativeLinearStack(children: [text26(t), text13(t)], axis: .horizontal)
    }) == [20, 25])
    #expect(baselines(measured { t in
        t.newNativeLinearStack(children: [colour(t), text13(t)], axis: .vertical)
    }) == [23, 23])
    #expect(baselines(measured { t in
        t.newNativeLinearStack(children: [text13(t), colour(t)], axis: .vertical)
    }) == [13, 13])
    #expect(baselines(measured { t in t.newNativeLinearStack(children: [colour(t)], axis: .horizontal) })
            == [nil, nil])
    #expect(baselines(measured { t in
        t.newNativeLinearStack(children: [text13(t), twoLines(t)], axis: .horizontal, alignment: .bottom)
    }) == [13, 29])
    #expect(baselines(measured { t in
        t.newNativeLinearStack(children: [twoLines(t), text13(t)], axis: .horizontal, alignment: .top)
    }) == [13, 29])
    #expect(baselines(measured { t in t.newNativeGrid(children: [text13(t)]) }) == [13, 13])
    #expect(baselines(measured { t in
        t.newNativePadding(child: text13(t), insets: Edges(all: 8))
    }) == [21, 21])
    #expect(baselines(measured { t in t.newNativeFrame(child: text13(t), height: 50) }) == [30, 30])
}

/// B2's four children in a spacing-0 horizontal stack: the 13 pt text, the
/// 26 pt one, the two-line one and the colour — at whole-point widths (18, 34,
/// 18, 10), so the stored rects, which layout rounds, keep every vertical
/// number B2 measured (B2's own widths are half points at scale 2).
private func b2(_ tree: LayoutTree, alignment: ProposalAlignment = .center,
                baseline: ProposalTextBaseline? = nil) -> (stack: LayoutNodeID, children: [LayoutNodeID]) {
    let children = [leaf(tree, 18, 16, first: 13), leaf(tree, 34, 30, first: 25),
                    leaf(tree, 18, 32, first: 13, last: 29), colour(tree)]
    return (tree.newNativeLinearStack(children: children, axis: .horizontal, alignment: alignment,
                                      baseline: baseline), children)
}

/// B2 laid out at `unspecified` in bounds of its own answer at (5, 7): the
/// answer, and each child's rect relative to the stack's origin.
private func layOutB2(alignment: ProposalAlignment = .center, baseline: ProposalTextBaseline? = nil)
    -> (answer: LayoutMeasurement, rects: [LayoutRect]) {
    let tree = LayoutTree(generation: 0)
    let (stack, children) = b2(tree, alignment: alignment, baseline: baseline)
    let answer = tree.computeNativeLayout(root: stack, proposal: unspecified, centredIn: LayoutRect(x: 0, y: 0, width: 0, height: 0))
    let origin = tree.layout(stack)
    let rects = children.map { child -> LayoutRect in
        let r = tree.layout(child)
        return LayoutRect(x: r.x - origin.x, y: r.y - origin.y, width: r.width, height: r.height)
    }
    return (answer, rects)
}

/// **2.2.** First-baseline alignment (B2): each child's first baseline — or,
/// with none, its height — sits on the largest (25), and the stack is that
/// plus the largest remainder below one (19): 44 tall (78.5 × 44 in B2, 80
/// here at whole-point widths), children at y 12, 0, 12 and 15.
@Test func anHStackAlignedByFirstTextBaselinePlacesAndSizesAsSwiftUI() {
    let (answer, rects) = layOutB2(baseline: .first)
    #expect(answer.size == SizeD(width: 80, height: 44))
    #expect(rects.map(\.y) == [12, 0, 12, 15])
    #expect(rects.map(\.x) == [0, 18, 52, 70])
    #expect(rects.map(\.height) == [16, 30, 32, 10])
}

/// **2.3.** Last-baseline alignment (B2): guides 13, 25, 29 and the colour's
/// 10; 29 + 5 = 34 tall, children at y 16, 4, 0 and 19.
@Test func anHStackAlignedByLastTextBaselinePlacesAndSizesAsSwiftUI() {
    let (answer, rects) = layOutB2(baseline: .last)
    #expect(answer.size == SizeD(width: 80, height: 34))
    #expect(rects.map(\.y) == [16, 4, 0, 19])
}

/// **2.4.** The control: the same baseline-reporting children under `.top`
/// and `.center` answer as they always did (B2's top and centre rows: 32 tall;
/// y 0, 0, 0, 0 and 8, 1, 0, 11), and `.bottom` by the same factor rule.
@Test func existingStackAlignmentsAnswerUnchanged() {
    let top = layOutB2(alignment: .top)
    #expect(top.answer.size == SizeD(width: 80, height: 32))
    #expect(top.rects.map(\.y) == [0, 0, 0, 0])
    let centre = layOutB2(alignment: .center)
    #expect(centre.answer.size == SizeD(width: 80, height: 32))
    #expect(centre.rects.map(\.y) == [8, 1, 0, 11])
    let bottom = layOutB2(alignment: .bottom)
    #expect(bottom.answer.size == SizeD(width: 80, height: 32))
    #expect(bottom.rects.map(\.y) == [16, 2, 0, 22])
}

/// **2.5.** A baseline-aligned stack's own baselines are the min and max of its
/// children's at their placed offsets (B2's stack rows): first-aligned 25/41,
/// last-aligned 13/29.
@Test func aBaselineAlignedStackReportsTheMinAndMaxOfItsChildren() {
    #expect(baselines(layOutB2(baseline: .first).answer) == [25, 41])
    #expect(baselines(layOutB2(baseline: .last).answer) == [13, 29])
}

/// **2.6** (exit test). A vertical stack given a text baseline traps: its
/// cross axis is horizontal, where a baseline means nothing, and no public
/// spelling reaches it (`VStack` takes a `HorizontalAlignment`; TE-K item 3).
@Test func aVerticalStackWithATextBaselineTraps() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        let child = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }
        _ = tree.newNativeLinearStack(children: [child], axis: .vertical, baseline: .first)
    }
    let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(stderr.contains("a vertical linear stack cannot align by a text baseline"),
            "aborted, but not at the baseline check:\n\(stderr)")
}

/// **SA-M unmoved** (spec §8 lane 2): baselines come from answers already in
/// hand, so a branching tree does the same measurement work — calls, hits and
/// misses — whether its horizontal stacks align by a baseline or by a factor,
/// and whether its leaves report baselines or not.
@Test func baselineAlignmentAddsNoMeasurementWork() {
    func work(baseline: ProposalTextBaseline?, reporting: Bool) -> NativeLayoutWork {
        let tree = LayoutTree(generation: 0)
        func item(_ h: Double) -> LayoutNodeID {
            reporting ? leaf(tree, 20, h, first: h - 3, last: h - 3) : leaf(tree, 20, h)
        }
        func row() -> LayoutNodeID {
            tree.newNativeLinearStack(children: [item(16), tree.newNativeSpacer(), item(30)], axis: .horizontal,
                                      spacing: nil, alignment: .top, baseline: baseline)
        }
        let column = tree.newNativeLinearStack(children: [row(), row(), tree.newNativePadding(
            child: row(), insets: Edges(all: 2))], axis: .vertical)
        _ = tree.computeNativeLayout(root: column, proposal: ProposedSize(width: 200, height: nil),
                                     in: LayoutRect(x: 0, y: 0, width: 200, height: 200))
        return tree.lastNativeLayoutWork
    }
    let plain = work(baseline: nil, reporting: false)
    #expect(plain.measureCalls > 0 && plain.cacheHits > 0)
    #expect(work(baseline: nil, reporting: true) == plain)
    #expect(work(baseline: .first, reporting: true) == plain)
    #expect(work(baseline: .last, reporting: false) == plain)
}

/// **2.1b** (exit test, `.success`; ruling TE-X item 6). An infinite answer
/// never turns a baseline into NaN: a greedy frame around a 13 pt text inside
/// a horizontal stack, itself one of two children of a vertical stack, is
/// probed at an infinite height (the vertical stack's flexibility probe, CN-B;
/// CN-F: the greedy frame answers ∞, its baseline 13 + ∞ × ½ = ∞). The
/// horizontal stack's offsets `(∞ − ∞) × factor` and a baseline guide's
/// remainder `∞ − ∞` are NaN, and checkpoint 2 (SA-J) traps a NaN baseline or
/// size — so a non-finite guide, offset or baseline is left out of the
/// combination instead — at the infinite probe the row reports no baseline.
/// Under a factor alignment, and under both baselines.
@Test func anInfiniteAnswerNeverMakesABaselineNaN() async {
    await #expect(processExitsWith: .success) {
        for (baseline, nested) in [(nil, false), (ProposalTextBaseline.first, false), (.last, false),
                                   (nil, true), (.first, true)] {
            let tree = LayoutTree(generation: 0)
            let text = tree.newNativeLeaf { _ in
                LayoutMeasurement(size: SizeD(width: 17.5, height: 16), firstBaseline: 13, lastBaseline: 13)
            }
            // One greedy frame (the stack's `(∞ − ∞) × ½` offset is NaN), or
            // two (the outer frame's own shift is NaN too).
            let inner = tree.newNativeFrame(child: text, maxHeight: .infinity)
            let greedy = nested ? tree.newNativeFrame(child: inner, maxHeight: .infinity) : inner
            let other = tree.newNativeLeaf { _ in
                LayoutMeasurement(size: SizeD(width: 10, height: 10), firstBaseline: 8, lastBaseline: 8)
            }
            let row = tree.newNativeLinearStack(children: [greedy, other], axis: .horizontal, baseline: baseline)
            let column = tree.newNativeLinearStack(children: [row, tree.newNativeLeaf { _ in
                LayoutMeasurement(size: SizeD(width: 20, height: 20))
            }], axis: .vertical)
            _ = tree.computeNativeLayout(root: column, proposal: ProposedSize(width: 100, height: 300),
                                         in: LayoutRect(x: 0, y: 0, width: 100, height: 300))
            // At the probe's own infinite height every placed baseline in the
            // row is infinite or NaN, so none is combined: the row reports none.
            let probed = tree.measureNativeLayout(root: row, proposal: ProposedSize(width: 100, height: .infinity))
            precondition(probed.firstBaseline == nil && probed.lastBaseline == nil,
                         "an infinite answer's baseline was combined: \(probed)")
        }
    }
}
