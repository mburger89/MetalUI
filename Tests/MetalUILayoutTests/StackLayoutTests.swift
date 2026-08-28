import Testing
import MetalUICore
@testable import MetalUILayout

private func px(_ v: Double) -> MetalUICore.Dimension { .length(.pixels(Pixels(Float(v)))) }

private func sized(_ tree: LayoutTree, _ w: Double, _ h: Double) -> LayoutNodeID {
    var s = Style()
    s.size = Size(width: px(w), height: px(h))
    return tree.newNode(style: s, children: [])
}

private func stack(_ tree: LayoutTree, _ children: [LayoutNodeID],
                   align: AlignItems? = .center,
                   justify: JustifyItems? = .center) -> LayoutNodeID {
    var s = Style()
    s.display = .stack
    s.alignItems = align
    s.justifyItems = justify
    return tree.newNode(style: s, children: children)
}

/// A stack sizes to the LARGEST child on each axis, independently.
///
/// **Three children of three different sizes, and the winner differs per axis.**
/// A stack that returned its first child, its last child, or the child that won
/// the other axis would all give a different answer here. With uniform children
/// none of those could be told apart — the corpus-uniformity hazard that hid
/// divergence 6 for four milestones.
///
/// **`mid` is deliberately first, since it wins NEITHER axis.** A "return
/// `items.first`" bug used to pass this test's width assertion by coincidence
/// when `wide` (the width winner) was first, and putting `tall` (the height
/// winner) first instead only moves the coincidence to the other axis. `mid`
/// is the one child that cannot make a first-item bug pass either assertion —
/// found by mutation, fixed by reordering rather than by trusting either
/// original order.
@Test func aStackSizesToItsLargestChildOnEachAxisIndependently() {
    let tree = LayoutTree(generation: 0)
    let mid   = sized(tree, 50, 40)
    let wide  = sized(tree, 90, 10)   // widest, shortest
    let tall  = sized(tree, 20, 70)   // narrowest, tallest
    let node = stack(tree, [mid, wide, tall])

    let ctx = LayoutContext(rootFontSize: 16)
    let measured = measureNode(ctx, tree, node, known: .unspecified,
                               available: AvailableSpaceSize(width: .maxContent,
                                                             height: .maxContent),
                               containingBlockWidth: nil)
    #expect(measured.width == 90, "widest child is 90")
    #expect(measured.height == 70, "tallest child is 70 — a DIFFERENT child")
}

/// Every child keeps its own size; none is stretched, and none is flexed.
@Test func aStackDoesNotResizeItsChildren() {
    let tree = LayoutTree(generation: 0)
    let a = sized(tree, 90, 10)
    let b = sized(tree, 20, 70)
    let node = stack(tree, [a, b])

    computeLayout(tree, root: node,
                  available: AvailableSpaceSize(width: .definite(200),
                                                height: .definite(200)))
    #expect(tree.layout(a).width == 90)
    #expect(tree.layout(a).height == 10)
    #expect(tree.layout(b).width == 20)
    #expect(tree.layout(b).height == 70)
}

/// A stack ignores `flexGrow` — it is a flex-container property and there is no
/// main axis to grow along. Without this, a child with `flexGrow(1)` inside a
/// stack would silently take the container's whole width and nothing would say why.
@Test func aStackIgnoresFlexGrowOnItsChildren() {
    let tree = LayoutTree(generation: 0)
    var greedy = Style()
    greedy.size = Size(width: px(30), height: px(30))
    greedy.flexGrow = 1
    let a = tree.newNode(style: greedy, children: [])
    let node = stack(tree, [a])

    computeLayout(tree, root: node,
                  available: AvailableSpaceSize(width: .definite(300),
                                                height: .definite(300)))
    #expect(tree.layout(a).width == 30, "flexGrow must not stretch a stack child")
}

/// An empty stack is 0x0, like a childless Box.
@Test func anEmptyStackMeasuresZero() {
    let tree = LayoutTree(generation: 0)
    let node = stack(tree, [])
    let ctx = LayoutContext(rootFontSize: 16)
    let measured = measureNode(ctx, tree, node, known: .unspecified,
                               available: AvailableSpaceSize(width: .maxContent,
                                                             height: .maxContent),
                               containingBlockWidth: nil)
    #expect(measured.width == 0)
    #expect(measured.height == 0)
}

/// Padding and border are added back exactly as they are for a flex container —
/// the stack path shares `contentBox` and the `edges` bookkeeping.
@Test func aStacksPaddingIsAddedToItsMeasuredSize() {
    let tree = LayoutTree(generation: 0)
    let kid = sized(tree, 40, 20)
    var s = Style()
    s.display = .stack
    s.padding = Edges(all: .pixels(Pixels(7)))
    let node = tree.newNode(style: s, children: [kid])

    let ctx = LayoutContext(rootFontSize: 16)
    let measured = measureNode(ctx, tree, node, known: .unspecified,
                               available: AvailableSpaceSize(width: .maxContent,
                                                             height: .maxContent),
                               containingBlockWidth: nil)
    #expect(measured.width == 54, "40 + 7 + 7")
    #expect(measured.height == 34, "20 + 7 + 7")
}

/// A `display: none` child contributes nothing to a stack's measured size.
///
/// **Added by a mutation, not by the plan.** Deleting the
/// `where tree.style(kid).display != .none` filter in `layOutStack` reddened
/// no other test in the full suite — the filter was unguarded. This is the
/// hidden child made large enough that, if it were counted, it would win both
/// axes and be impossible to miss.
@Test func aNoneDisplayChildDoesNotContributeToAStacksSize() {
    let tree = LayoutTree(generation: 0)
    let visible = sized(tree, 20, 20)
    var hidden = Style()
    hidden.display = .none
    hidden.size = Size(width: px(200), height: px(200))
    let hiddenNode = tree.newNode(style: hidden, children: [])
    let node = stack(tree, [visible, hiddenNode])

    let ctx = LayoutContext(rootFontSize: 16)
    let measured = measureNode(ctx, tree, node, known: .unspecified,
                               available: AvailableSpaceSize(width: .maxContent,
                                                             height: .maxContent),
                               containingBlockWidth: nil)
    #expect(measured.width == 20, "the 200-wide none child must not win")
    #expect(measured.height == 20, "the 200-tall none child must not win")
}

/// An auto-sized stack child is measured from its own content — the branch
/// nothing else in this file reaches.
///
/// **Every other fixture uses `sized()`**, which sets an explicit width and
/// height, so `layOutStack`'s `if let knownWidth, let knownHeight` branch is
/// always taken and the content-measuring `else` branch — the one spec §3.2 is
/// actually about, "measured with the stack's own available space" — never
/// runs. This is that branch's only test: a default-styled container (size
/// `auto`/`auto`) whose own child is a fixed 60x25 measures 60x25 by content,
/// and the stack sizes to it. Verified to reach the branch by making it
/// temporarily return `SizeD(width: 0, height: 0)`: only this test reddens,
/// and the other five stay green — see the fix-round report for the exact
/// output.
@Test func aStackSizesAnAutoChildFromItsOwnContent() {
    let tree = LayoutTree(generation: 0)
    let grandchild = sized(tree, 60, 25)
    // `Style()`'s default size is `.auto`/`.auto` — no `sized()` call, so this
    // is genuinely unresolved rather than resolved-to-zero.
    let content = tree.newNode(style: Style(), children: [grandchild])
    let node = stack(tree, [content])

    let ctx = LayoutContext(rootFontSize: 16)
    let measured = measureNode(ctx, tree, node, known: .unspecified,
                               available: AvailableSpaceSize(width: .maxContent,
                                                             height: .maxContent),
                               containingBlockWidth: nil)
    #expect(measured.width == 60, "the stack sizes to the auto child's content width")
    #expect(measured.height == 25, "the stack sizes to the auto child's content height")
}

/// `minWidth` clamps a stack child's own declared size, the same as it clamps
/// every other node in this engine.
///
/// **A child declares `width: 10px` but `min-width: 40px`.** An unclamped
/// implementation sizes the stack to 10; the correct answer is 40.
/// `minSize`/`maxSize` are unreachable from the public API until Task 5 makes
/// `Stack` public — this sets `Style` directly, the same way every test in
/// this file reaches `display: .stack` itself, before there is a modifier for
/// it. Verified by removing the clamp: this test reddens (`measured.width` →
/// `10`) and nothing else does — see the fix-round report.
@Test func aStackChildsMinWidthClampsItsDeclaredSize() {
    let tree = LayoutTree(generation: 0)
    var s = Style()
    s.size = Size(width: px(10), height: px(30))
    s.minSize = Size(width: px(40), height: .auto)
    let kid = tree.newNode(style: s, children: [])
    let node = stack(tree, [kid])

    let ctx = LayoutContext(rootFontSize: 16)
    let measured = measureNode(ctx, tree, node, known: .unspecified,
                               available: AvailableSpaceSize(width: .maxContent,
                                                             height: .maxContent),
                               containingBlockWidth: nil)
    #expect(measured.width == 40, "min-width must clamp the declared 10 up to 40")
}

/// `minWidth` clamps a stack child's CONTENT-MEASURED size too, not only a
/// declared one.
///
/// **`aStackChildsMinWidthClampsItsDeclaredSize` above cannot see this branch
/// at all.** That test's child declares `width: 10px`, so `layOutStack` takes
/// `resolvedAxis`'s clamp and never reaches the second clamp at
/// `size = knownWidth ?? clamp(measured.width, ...)`. This child declares no
/// width — `.auto`, the default — so `layOutStack` measures it (a childless
/// leaf measures 0) and the *content-measured* clamp is the only thing that
/// can raise it to 40. Task 2's review found this branch reachable and
/// unexercised: removing only this clamp (leaving `resolvedAxis`'s intact)
/// passed the whole suite. Verified here: removing it reddens this test and
/// this test alone; removing `resolvedAxis`'s clamp instead reddens
/// `aStackChildsMinWidthClampsItsDeclaredSize` and leaves this one green — the
/// two tests are each other's negative control.
@Test func aStackChildsMinWidthClampsItsContentMeasuredSize() {
    let tree = LayoutTree(generation: 0)
    var s = Style()
    s.minSize = Size(width: px(40), height: .auto)
    let kid = tree.newNode(style: s, children: [])
    let node = stack(tree, [kid])

    let ctx = LayoutContext(rootFontSize: 16)
    let measured = measureNode(ctx, tree, node, known: .unspecified,
                               available: AvailableSpaceSize(width: .maxContent,
                                                             height: .maxContent),
                               containingBlockWidth: nil)
    #expect(measured.width == 40, "a childless leaf measures 0; min-width clamps it up to 40")
}

/// All nine alignments, each at a distinct position.
///
/// **The geometry is chosen so no two alignments coincide.** A 100x60 stack
/// holding one 20x10 child leaves 80 of horizontal slack and 50 of vertical:
/// start 0, centre 40, end 80 across; start 0, centre 25, end 50 down. Nine
/// distinct (x, y) pairs. A fixture where the child filled the container, or
/// where the slack were zero on an axis, could not tell centre from start —
/// which is the corpus-uniformity hazard this repo has been bitten by three times.
@Test func allNineAlignmentsPlaceTheChildAtNineDistinctPositions() throws {
    // (alignItems = block/vertical, justifyItems = inline/horizontal, x, y)
    let cases: [(AlignItems, JustifyItems, Double, Double)] = [
        (.flexStart, .start,  0,  0), (.flexStart, .center, 40,  0), (.flexStart, .end, 80,  0),
        (.center,    .start,  0, 25), (.center,    .center, 40, 25), (.center,    .end, 80, 25),
        (.flexEnd,   .start,  0, 50), (.flexEnd,   .center, 40, 50), (.flexEnd,   .end, 80, 50),
    ]
    var seen: Set<String> = []
    for (align, justify, x, y) in cases {
        let tree = LayoutTree(generation: 0)
        let kid = sized(tree, 20, 10)
        let node = stack(tree, [kid], align: align, justify: justify)
        computeLayout(tree, root: node,
                      available: AvailableSpaceSize(width: .definite(100),
                                                    height: .definite(60)))
        let r = tree.layout(kid)
        #expect(r.x == x, "\(align)/\(justify) x")
        #expect(r.y == y, "\(align)/\(justify) y")
        seen.insert("\(r.x),\(r.y)")
    }
    try #require(seen.count == 9, "all nine must be distinct, got \(seen.count): \(seen)")
}

/// `stretch` fills the container on that axis — the CSS default this framework
/// deliberately does NOT take for `Stack`, kept reachable through `Style`.
@Test func stretchFillsTheContainerOnThatAxis() {
    let tree = LayoutTree(generation: 0)
    let kid = sized(tree, 20, 10)
    let node = stack(tree, [kid], align: .stretch, justify: .stretch)
    computeLayout(tree, root: node,
                  available: AvailableSpaceSize(width: .definite(100),
                                                height: .definite(60)))
    let r = tree.layout(kid)
    #expect(r.width == 100)
    #expect(r.height == 60)
    #expect(r.x == 0)
    #expect(r.y == 0)
}

/// Children overlap: two children at the same alignment share an origin.
/// This is the property the container exists for, and nothing else asserts it.
@Test func twoChildrenAtTheSameAlignmentShareAnOrigin() {
    let tree = LayoutTree(generation: 0)
    let a = sized(tree, 40, 20)
    let b = sized(tree, 60, 30)
    let node = stack(tree, [a, b], align: .center, justify: .center)
    computeLayout(tree, root: node,
                  available: AvailableSpaceSize(width: .definite(100),
                                                height: .definite(100)))
    // Centred independently, so their origins differ by half the size difference
    // rather than being sequenced — 40 wide centres at 30, 60 wide at 20.
    #expect(tree.layout(a).x == 30)
    #expect(tree.layout(b).x == 20)
    #expect(tree.layout(a).y == 40)
    #expect(tree.layout(b).y == 35)
}

/// A stack's padding offsets its children, and alignment is measured inside the
/// CONTENT box — not the border box. Getting this wrong puts `.start` at the
/// padding edge on one axis and the border edge on the other, which reads as an
/// off-by-a-few rather than as a wrong box.
@Test func alignmentIsMeasuredInsideTheContentBox() {
    let tree = LayoutTree(generation: 0)
    let kid = sized(tree, 20, 10)
    var s = Style()
    s.display = .stack
    s.alignItems = .flexEnd
    s.justifyItems = .end
    s.padding = Edges(all: .pixels(Pixels(10)))
    let node = tree.newNode(style: s, children: [kid])
    computeLayout(tree, root: node,
                  available: AvailableSpaceSize(width: .definite(100),
                                                height: .definite(60)))
    let r = tree.layout(kid)
    #expect(r.x == 70, "100 - 10 padding - 20 wide")
    #expect(r.y == 40, "60 - 10 padding - 10 tall")
}
