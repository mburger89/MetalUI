import Testing
@testable import MetalUILayout

// The both-axes scroll viewport (Alloy gap G5, ruling `XS-B`; probe `docs/probes/swiftui-two-axis-scroll.swift` arms
// `L1a`, `L1b`, `L2a`, `L2b`, `L3`, `L1e`-`L1g`). The one-axis viewports are pinned elsewhere and must not move: the content is
// proposed `nil x nil`, the viewport answers its proposal on both axes (the content's answer where there is none) and the content
// sits at the viewport's origin at its own answer.

/// A leaf that records the proposal it got and answers `width x height` where the proposal leaves an axis open.
private final class Seen: @unchecked Sendable { var proposals: [ProposedSize] = [] }

private func viewport(horizontal: Bool, vertical: Bool, content: (Double, Double), proposal: (Double, Double),
                      seen: Seen = Seen()) -> (answer: SizeD, content: LayoutRect, tree: LayoutTree, seen: Seen) {
    let tree = LayoutTree(generation: 0)
    let leaf = tree.newNativeLeaf { p in
        seen.proposals.append(p)
        return LayoutMeasurement(size: SizeD(width: p.width ?? content.0, height: p.height ?? content.1))
    }
    let node = tree.newNativeScrollViewport(child: leaf, horizontal: horizontal, vertical: vertical)
    let answer = tree.computeNativeLayout(root: node, proposal: ProposedSize(width: proposal.0, height: proposal.1),
                                          in: LayoutRect(x: 0, y: 0, width: proposal.0, height: proposal.1))
    return (answer.size, tree.layout(leaf), tree, seen)
}

/// **X1** (`XS-B`, probe `L1a`, `L1b`, `L2a`, `L2b`). Both axes: a 500 x 500 content in 100 x 100 is proposed `nil x nil`, so it
/// answers 500 x 500, the viewport answers the proposal 100 x 100; small content (50 x 30) sits at (0, 0), NOT centred (probe
/// `L1b`, `L1e`-`L1g`: the pixels of an AppKit-backed scroller; `SCG2`'s (25, 35) was a layout-harness reading); 50 x 500 and
/// 500 x 50 in 300 x 300 keep their own size on the long axis and the short one at (0, 0).
/// **Mutation:** the both-axes arm proposing like a vertical viewport (`ProposedSize(width: parent.width, height: nil)`):
/// the 500 wide content is proposed 100 and answers 100 wide.
@Test func aTwoAxisViewportProposesNothingToItsContentAndAnswersTheProposalOnBothAxes() {
    let big = viewport(horizontal: true, vertical: true, content: (500, 500), proposal: (100, 100))
    #expect(big.seen.proposals == [ProposedSize(width: nil, height: nil)], "\(big.seen.proposals)")
    #expect(big.answer == SizeD(width: 100, height: 100))
    #expect(big.content == LayoutRect(x: 0, y: 0, width: 500, height: 500))
    let small = viewport(horizontal: true, vertical: true, content: (50, 30), proposal: (100, 100))
    #expect(small.answer == SizeD(width: 100, height: 100))
    #expect(small.content == LayoutRect(x: 0, y: 0, width: 50, height: 30), "not centred: probe L1b")
    let tall = viewport(horizontal: true, vertical: true, content: (50, 500), proposal: (300, 300))
    #expect(tall.answer == SizeD(width: 300, height: 300))
    #expect(tall.content == LayoutRect(x: 0, y: 0, width: 50, height: 500))
    let wide = viewport(horizontal: true, vertical: true, content: (500, 50), proposal: (300, 300))
    #expect(wide.content == LayoutRect(x: 0, y: 0, width: 500, height: 50))
}

/// An open proposal (`nil`) on an axis answers the content's size there, as for one axis.
@Test func aTwoAxisViewportWithNoProposalAnswersItsContentsSize() {
    let tree = LayoutTree(generation: 0)
    let leaf = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 70, height: 40)) }
    let node = tree.newNativeScrollViewport(child: leaf, horizontal: true, vertical: true)
    let answer = tree.computeNativeLayout(root: node, proposal: ProposedSize(width: nil, height: 25),
                                          in: LayoutRect(x: 0, y: 0, width: 70, height: 25))
    #expect(answer.size == SizeD(width: 70, height: 25))
}

/// **X1b** (`XS-B`, probe `L3`). `ScrollView([])`: nothing scrolls; the content is proposed the viewport's proposal and placed at
/// the viewport's size (probe `L3`: a 500 x 500 content read 300 x 300). **Mutation:** treating `[]` as both axes: the content is
/// proposed `nil x nil` and sized 500 x 500.
@Test func aViewportWithNoAxesSizesItsContentToTheViewport() {
    let none = viewport(horizontal: false, vertical: false, content: (500, 500), proposal: (300, 300))
    #expect(none.seen.proposals.allSatisfy { $0 == ProposedSize(width: 300, height: 300) }, "\(none.seen.proposals)")
    #expect(none.answer == SizeD(width: 300, height: 300))
    #expect(none.content == LayoutRect(x: 0, y: 0, width: 300, height: 300))
}

/// The one-axis spellings are one node: `horizontal:vertical:` with exactly one `true` measures and places like
/// `newNativeScrollViewport(child:axis:)` (stop condition 4: the one-axis path is byte-identical), the same work and the same
/// memo signature, and both axes are a third signature. **Mutation:** the both-axes tag written like the vertical one
/// (`h.mix(2)` -> `h.mix(1)` in `nodeSignature`): the signature of the two-axis viewport equals the vertical one's.
@Test @MainActor func theOneAxisSpellingsOfTheViewportAreTheNodeTheyAlwaysWereAndBothIsADistinctSignature() {
    func built(_ build: (LayoutTree, LayoutNodeID) -> LayoutNodeID) -> (work: NativeLayoutWork, key: LayoutSignature?) {
        let tree = LayoutTree(generation: 1)
        let leaf = keyed(tree, "k", width: 90, height: 90)
        let node = build(tree, leaf)
        _ = tree.computeNativeLayout(root: node, proposal: ProposedSize(width: 50, height: 50),
                                     in: LayoutRect(x: 0, y: 0, width: 50, height: 50))
        return (tree.lastNativeLayoutWork, tree.structuralSignature(of: node))
    }
    let vertical = built { $0.newNativeScrollViewport(child: $1, axis: .vertical) }
    let verticalSpelled = built { $0.newNativeScrollViewport(child: $1, horizontal: false, vertical: true) }
    let horizontal = built { $0.newNativeScrollViewport(child: $1, axis: .horizontal) }
    let horizontalSpelled = built { $0.newNativeScrollViewport(child: $1, horizontal: true, vertical: false) }
    let both = built { $0.newNativeScrollViewport(child: $1, horizontal: true, vertical: true) }
    #expect(vertical.work == verticalSpelled.work && vertical.key == verticalSpelled.key)
    #expect(horizontal.work == horizontalSpelled.work && horizontal.key == horizontalSpelled.key)
    #expect(vertical.key != nil && both.key != nil)
    #expect(vertical.key != horizontal.key && vertical.key != both.key && horizontal.key != both.key)
}

private func keyed(_ tree: LayoutTree, _ key: String, width: Double = 20, height: Double = 10) -> LayoutNodeID {
    tree.newNativeLeaf(key: key) { _ in LayoutMeasurement(size: SizeD(width: width, height: height)) }
}
