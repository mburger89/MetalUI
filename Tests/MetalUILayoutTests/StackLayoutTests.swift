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
