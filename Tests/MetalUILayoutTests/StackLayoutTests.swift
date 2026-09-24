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

/// `stretch` fills the container on that axis for a child with no declared
/// size there — the CSS default this framework deliberately does NOT take for
/// `Stack`, kept reachable through `Style`.
///
/// **Auto-sized, not `sized(tree, 20, 10)`.** This test used to use a declared
/// 20x10 child and expect it stretched to 100x60 — that was wrong: fix round
/// 1 found (via a browser oracle probe while building Task 4's fixtures) that
/// CSS's `stretch` fills an axis only when the child's own size on it is
/// `auto`; a declared size falls back to `start` and keeps its own value.
/// `stretchDoesNotOverrideADeclaredChildSize` below pins that branch, and the
/// two are each other's negative control.
@Test func stretchFillsTheContainerOnThatAxis() {
    let tree = LayoutTree(generation: 0)
    // `Style()`'s default size is `.auto`/`.auto` — genuinely unresolved,
    // unlike `sized()`, so `positionStackItems` takes the stretch branch.
    let kid = tree.newNode(style: Style(), children: [])
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

/// The other half of the stretch rule: a child with a DECLARED size is not
/// stretched, even under `align: .stretch, justify: .stretch` — it keeps its
/// own 20x10 and sits at the start edge, matching WebKit
/// (the golden `stack_stretch_declared_size` pinned the same rule against the
/// oracle until stage 7a retired it, record §42). Verified as a negative
/// control, while that golden lived: reverting
/// `positionStackItems`'s `widthIsAuto`/`heightIsAuto` guard to unconditional
/// reddened exactly TWO tests — this one and
/// `StackFixtureTests.stackStretchDeclaredSizeMatchesWebKit` — and left
/// `stretchFillsTheContainerOnThatAxis` above green.
///
/// **"This test alone" is what this comment used to say, and the fixture's
/// comment said it too — of a different test.** Both could not be right; the
/// fix round's own ledger recorded the pair. Re-measured on the whole suite at
/// the milestone's final review: the two named above, and nothing else.
@Test func stretchDoesNotOverrideADeclaredChildSize() {
    let tree = LayoutTree(generation: 0)
    let kid = sized(tree, 20, 10)
    let node = stack(tree, [kid], align: .stretch, justify: .stretch)
    computeLayout(tree, root: node,
                  available: AvailableSpaceSize(width: .definite(100),
                                                height: .definite(60)))
    let r = tree.layout(kid)
    #expect(r.width == 20, "a declared size must not be overridden by stretch")
    #expect(r.height == 10, "a declared size must not be overridden by stretch")
    #expect(r.x == 0, "stretch falls back to the start edge for a declared size")
    #expect(r.y == 0, "stretch falls back to the start edge for a declared size")
}

/// Two children of DIFFERENT sizes, both centred: each is centred against the
/// CONTAINER, independently, so they land at different origins — 40 wide
/// centres at 30, 60 wide at 20. This is what distinguishes stacking from
/// sequencing. A sequencing container would place the second child after the
/// first rather than over it, and an implementation that instead centred each
/// child against the OTHER child (or that ignored size entirely and pinned
/// both to one shared origin) would also fail this — the two numbers per axis
/// are the whole assertion, and they must NOT match.
@Test func twoOverlappingChildrenAreCentredIndependentlyNotSequenced() {
    let tree = LayoutTree(generation: 0)
    let a = sized(tree, 40, 20)
    let b = sized(tree, 60, 30)
    let node = stack(tree, [a, b], align: .center, justify: .center)
    computeLayout(tree, root: node,
                  available: AvailableSpaceSize(width: .definite(100),
                                                height: .definite(100)))
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

// MARK: - Live clauses the milestone's final review found unreached (shape 9)
//
// Every test below was written from a mutation that stayed GREEN across the
// whole suite, and each mutation was first shown to change an observable number
// (the practices doc's "a mutation that reddens nothing is a broken instrument
// or it is the finding" discriminator). The clause each one covers, the exact
// mutation, and the reddened test are named in the test's own comment.

/// `maxSize` clamps a stack child's own DECLARED size — the other half of
/// `aStackChildsMinWidthClampsItsDeclaredSize`, and the half nothing reached.
///
/// **Mutation that was green across 529 tests:** `resolvedAxis`'s
/// `clamp(resolved, min: lower, max: upper)` with `max: nil`. Every stack test
/// in the suite declared a `minSize` or nothing at all, so the upper bound was
/// carried into `clamp` and never consulted. A wrong implementation this
/// catches: reading `maxSize` and dropping it on the declared path, which ships
/// `Stack { Box().width(200).maxWidth(60) }` at 200.
@Test func aStackChildsMaxWidthClampsItsDeclaredSize() {
    let tree = LayoutTree(generation: 0)
    var s = Style()
    s.size = Size(width: px(200), height: px(30))
    s.maxSize = Size(width: px(60), height: .auto)
    let kid = tree.newNode(style: s, children: [])
    let node = stack(tree, [kid])

    let ctx = LayoutContext(rootFontSize: 16)
    let measured = measureNode(ctx, tree, node, known: .unspecified,
                               available: AvailableSpaceSize(width: .maxContent,
                                                             height: .maxContent),
                               containingBlockWidth: nil)
    #expect(measured.width == 60, "max-width must clamp the declared 200 down to 60")
}

/// `maxSize` and `minSize` clamp a stack child's CONTENT-MEASURED size on both
/// axes — the three bounds `aStackChildsMinWidthClampsItsContentMeasuredSize`
/// leaves untouched.
///
/// **Mutation that was green across 529 tests:** dropping `max: maxWidthBound`
/// and `max: maxHeightBound` from the measured path, and dropping
/// `min: minHeight` with them. Only the measured *min-width* bound had a test,
/// so three of the four bounds on that line were carried and never read. A
/// wrong implementation this catches: clamping the axis that happens to have a
/// test and passing the other three through, which ships an auto-sized child
/// overflowing its own `maxHeight`.
///
/// Every bound moves a different number here — the child's content is 100x100,
/// the width is capped at 40, the height floored at 10 and then capped at 25 —
/// so no two of the three could be satisfied by one accident.
@Test func aStackChildsMaxAndMinClampItsContentMeasuredSizeOnBothAxes() {
    let tree = LayoutTree(generation: 0)
    let grandchild = sized(tree, 100, 100)
    var s = Style()
    // No declared size: both axes take the measured path.
    s.maxSize = Size(width: px(40), height: px(25))
    s.minSize = Size(width: .auto, height: px(10))
    let kid = tree.newNode(style: s, children: [grandchild])
    let node = stack(tree, [kid])

    let ctx = LayoutContext(rootFontSize: 16)
    let measured = measureNode(ctx, tree, node, known: .unspecified,
                               available: AvailableSpaceSize(width: .maxContent,
                                                             height: .maxContent),
                               containingBlockWidth: nil)
    #expect(measured.width == 40, "max-width clamps the measured 100 down to 40")
    #expect(measured.height == 25, "max-height clamps the measured 100 down to 25")
}

/// The measured min-HEIGHT bound alone, with nothing else to satisfy: a
/// childless leaf measures 0 and `minHeight` is the only thing that can raise
/// it. The negative control for the test above, whose child is large enough
/// that `min: minHeight` could be dropped without moving a number.
@Test func aStackChildsMinHeightClampsItsContentMeasuredSize() {
    let tree = LayoutTree(generation: 0)
    var s = Style()
    s.minSize = Size(width: .auto, height: px(35))
    let kid = tree.newNode(style: s, children: [])
    let node = stack(tree, [kid])

    let ctx = LayoutContext(rootFontSize: 16)
    let measured = measureNode(ctx, tree, node, known: .unspecified,
                               available: AvailableSpaceSize(width: .maxContent,
                                                             height: .maxContent),
                               containingBlockWidth: nil)
    #expect(measured.height == 35, "a childless leaf measures 0; min-height clamps it up to 35")
}

/// A child with a KNOWN width and an `auto` height is measured **at that
/// width**, not at max-content.
///
/// **Mutation that was green across 529 tests:** replacing `layOutStack`'s
/// `measureNode` arguments with `known: .unspecified` and
/// `available: AvailableSpaceSize(width: .maxContent, height: .maxContent)` —
/// throwing the resolved axis away when asking the child its other axis. Every
/// other stack test in the suite has children whose two axes are independent
/// (both declared, or both auto), so the mixed case was reached and could not
/// be seen: `size` on line 983 takes `knownWidth` back regardless, and only the
/// *height* moves.
///
/// The child here is a WRAPPING flex row of two 30x20 boxes, which is the one
/// content in this framework other than text whose height depends on the width
/// it is measured at: at the declared 50 the two wrap onto two lines (height
/// 40), at max-content they sit on one (height 20). A wrong implementation this
/// catches ships every auto-height child of a fixed-width stack item one line
/// too short.
@Test func aStackChildWithAKnownWidthIsMeasuredAtThatWidthNotMaxContent() {
    let tree = LayoutTree(generation: 0)
    let a = sized(tree, 30, 20)
    let b = sized(tree, 30, 20)
    var wrapper = Style()
    wrapper.flexDirection = .row
    wrapper.flexWrap = .wrap
    wrapper.size = Size(width: px(50), height: .auto)   // width known, height auto
    let kid = tree.newNode(style: wrapper, children: [a, b])
    let node = stack(tree, [kid])

    let ctx = LayoutContext(rootFontSize: 16)
    let measured = measureNode(ctx, tree, node, known: .unspecified,
                               available: AvailableSpaceSize(width: .maxContent,
                                                             height: .maxContent),
                               containingBlockWidth: nil)
    #expect(measured.width == 50, "the declared width is kept")
    #expect(measured.height == 40, "two lines at width 50 — one line (20) means the width was dropped")
}

/// A stack child's percentage padding resolves against the STACK's content
/// box while the child is being MEASURED — `layOutStack` passing
/// `containingBlockWidth: box.size.width` into `measureNode`.
///
/// **Mutation that was green across 529 tests:** `containingBlockWidth: nil`.
/// No stack test had a child with a percentage anything, so the argument was
/// passed and never read. This is CLAUDE.md's "percentage inset resolves
/// against the containing block's width" constraint — one of four listed as
/// easy to violate silently, and violated here in the direction that produces
/// zero rather than a wrong number.
///
/// The stack is 300 wide, so 10% is 30 a side and the child measures
/// `20 + 30 + 30 = 80`. Under `nil` the percentage resolves to nothing and the
/// child measures 20 — a whole padding box silently gone.
@Test func aStackChildsPercentagePaddingResolvesAgainstTheStackWhenMeasured() {
    let tree = LayoutTree(generation: 0)
    let grandchild = sized(tree, 20, 20)
    var s = Style()
    s.padding = Edges(all: .percent(0.1))
    let kid = tree.newNode(style: s, children: [grandchild])
    var stackStyle = Style()
    stackStyle.display = .stack
    stackStyle.alignItems = .flexStart
    stackStyle.justifyItems = .start
    stackStyle.size = Size(width: px(300), height: px(200))
    let node = tree.newNode(style: stackStyle, children: [kid])

    computeLayout(tree, root: node,
                  available: AvailableSpaceSize(width: .definite(800),
                                                height: .definite(600)))
    #expect(tree.layout(kid).width == 80, "20 content + 10% of the stack's 300 on each side")
}

/// A stack child's own percentage padding resolves against the STACK's content
/// box while the child is being PLACED — `positionStackItems` passing
/// `containingBlockWidth: containerSize.width` into `placeNode`.
///
/// **Mutation that was green across 529 tests:** passing the item's own
/// `size.width` instead of `containerSize.width` at that call. Nothing under a
/// stack had a percentage inset, so the two were never distinguishable. This is
/// CLAUDE.md's "a percentage inset resolves against the CONTAINING BLOCK's
/// width — not the box's own width" constraint, one of four listed as easy to
/// violate silently, and the mutation is precisely the mistake it names.
///
/// **The paired-but-different site from
/// `aStackChildsPercentagePaddingResolvesAgainstTheStackWhenMeasured` above,
/// and neither test can see the other's.** That one's child is auto-sized, so
/// `layOutStack` measures it and the basis comes from `measureNode`'s argument;
/// this one's child declares both axes, so `layOutStack` never measures it at
/// all and the basis reaches it only through `placeNode`. Verified: each
/// mutation reddens its own test and leaves the other green.
///
/// The stack's content box is 300 and the child is 100 wide, so the two
/// candidate bases give different numbers — 10% is 30 against the containing
/// block and 10 against the child's own width, and the leaf inside the child's
/// content box lands at `x = 30` rather than `x = 10`.
@Test func aStackChildsPercentagePaddingResolvesAgainstTheStackWhenPlaced() {
    let tree = LayoutTree(generation: 0)
    let leaf = sized(tree, 10, 10)
    var padded = Style()
    padded.padding = Edges(all: .percent(0.1))
    padded.size = Size(width: px(100), height: px(60))
    padded.alignItems = .flexStart
    let kid = tree.newNode(style: padded, children: [leaf])

    var stackStyle = Style()
    stackStyle.display = .stack
    stackStyle.alignItems = .flexStart
    stackStyle.justifyItems = .start
    stackStyle.size = Size(width: px(300), height: px(200))
    let node = tree.newNode(style: stackStyle, children: [kid])

    computeLayout(tree, root: node,
                  available: AvailableSpaceSize(width: .definite(800),
                                                height: .definite(600)))
    #expect(tree.layout(kid).x == 0, "the child itself is at the stack's start edge")
    #expect(tree.layout(leaf).x == 30,
            "10% of the stack's 300 content box, not of the child's own 100")
}

/// A `nil` `alignItems`/`justifyItems` on a stack reads as CSS's `stretch`.
///
/// **Mutation that was green across 529 tests:** `?? .flexEnd` and `?? .end` in
/// `positionStackItems`. Every stack test in the suite wrote both fields
/// explicitly, so the fallback was reached only through `stack()`'s own
/// defaults, which are `.center`/`.center`. A hand-built `Style` — the only way
/// to reach `display: .stack` outside `Stack.init` — leaves both `nil`, and a
/// wrong fallback silently pins every such child to one corner.
///
/// The child is unsized so the two candidates are maximally far apart: under
/// `stretch` it fills 100x60 at the origin, under any end-edge fallback it is a
/// 0x0 box at (100, 60).
@Test func aStacksNilAlignmentFieldsReadAsStretch() {
    let tree = LayoutTree(generation: 0)
    let kid = tree.newNode(style: Style(), children: [])
    let node = stack(tree, [kid], align: nil, justify: nil)
    computeLayout(tree, root: node,
                  available: AvailableSpaceSize(width: .definite(100),
                                                height: .definite(60)))
    let r = tree.layout(kid)
    #expect(r.width == 100, "nil alignItems must read as stretch, not an end edge")
    #expect(r.height == 60, "nil justifyItems must read as stretch, not an end edge")
    #expect(r.x == 0)
    #expect(r.y == 0)
}

/// `AlignItems.baseline` on a stack falls back to the START edge, exactly as it
/// does in `crossAxisOffset` — the engine cannot see an item's baseline at all,
/// because a `MeasureFunction` returns a `SizeD`.
///
/// **Mutation that was green across 529 tests:** `case .baseline: y =
/// containerSize.height - size.height`. Nothing set `.baseline` on a stack, so
/// the arm was live and unreached. `StyledElement.alignItems(_:)` takes the
/// whole enum, so `Stack { … }.alignItems(.baseline)` compiles today — this is
/// the pin on which of the two wrong-but-documented answers it gets, and it
/// must move in the same commit that implements real baseline alignment.
@Test func baselineOnAStackFallsBackToTheStartEdge() {
    let tree = LayoutTree(generation: 0)
    let kid = sized(tree, 20, 10)
    let node = stack(tree, [kid], align: .baseline, justify: .start)
    computeLayout(tree, root: node,
                  available: AvailableSpaceSize(width: .definite(100),
                                                height: .definite(60)))
    #expect(tree.layout(kid).y == 0, "baseline falls back to flexStart, not flexEnd")
}
