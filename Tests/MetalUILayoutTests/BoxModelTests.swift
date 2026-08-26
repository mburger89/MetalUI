import Testing
import Foundation
import MetalUICore
@testable import MetalUILayout

private func px(_ v: Double) -> MetalUICore.Dimension { .length(.pixels(Pixels(Float(v)))) }
private func pxL(_ v: Double) -> Length { .pixels(Pixels(Float(v))) }

private func fixedChild(_ tree: LayoutTree, w: Double, h: Double) -> LayoutNodeID {
    var s = Style()
    s.size = Size(width: px(w), height: px(h))
    return tree.newNode(style: s, children: [])
}

/// A container's padding and border inset its children's *origin*.
///
/// Four different edge values, and padding differs from border: with
/// `padding: 20 8 4 16` and `border: 5 3 2 7` the content box starts at
/// (16 + 7, 20 + 5) = (23, 25). Uniform values would let a transposed axis or
/// a dropped edge pass.
///
/// **The name says "origin", not "and shrinks the content box", on purpose.**
/// Both children here have a fixed size, so neither their size nor their
/// packing position depends on whether the container's main-axis budget was
/// actually reduced: mutation-testing this task found that "inset the origin
/// but do NOT shrink the content box" leaves this exact test green. The
/// shrink half is covered elsewhere — `growDistributesTheContentBoxNotTheBorderBox`
/// (main axis) and `stretchFillsTheContentBoxNotTheBorderBox` (cross axis),
/// both below — and this test should be read together with those two, not as
/// a complete guard by itself.
@Test func paddingAndBorderInsetTheOriginOfEachChild() {
    let tree = LayoutTree()
    let a = fixedChild(tree, w: 50, h: 30)
    let b = fixedChild(tree, w: 60, h: 30)
    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(400), height: px(100))
    rootStyle.padding = Edges(top: pxL(20), right: pxL(8), bottom: pxL(4), left: pxL(16))
    rootStyle.border = Edges(top: pxL(5), right: pxL(3), bottom: pxL(2), left: pxL(7))
    let root = tree.newNode(style: rootStyle, children: [a, b])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    // The root's own border box is untouched — border-box sizing.
    #expect(tree.layout(root) == LayoutRect(x: 0, y: 0, width: 400, height: 100))
    // First child at the content-box origin, not (0, 0).
    #expect(tree.layout(a) == LayoutRect(x: 23, y: 25, width: 50, height: 30))
    // Second child packs after the first, still inside the content box.
    #expect(tree.layout(b) == LayoutRect(x: 73, y: 25, width: 60, height: 30))
}

/// The content box is what a stretched item fills, not the border box.
///
/// Cross-axis stretch must use the reduced extent: 100 tall with 20/4 padding
/// and 5/2 border leaves 69, not 100.
@Test func stretchFillsTheContentBoxNotTheBorderBox() {
    let tree = LayoutTree()
    var kidStyle = Style()
    kidStyle.size = Size(width: px(50), height: .auto)   // auto cross -> stretches
    let kid = tree.newNode(style: kidStyle, children: [])

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(400), height: px(100))
    rootStyle.padding = Edges(top: pxL(20), right: pxL(8), bottom: pxL(4), left: pxL(16))
    rootStyle.border = Edges(top: pxL(5), right: pxL(3), bottom: pxL(2), left: pxL(7))
    let root = tree.newNode(style: rootStyle, children: [kid])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    #expect(tree.layout(kid).height == 69)
    #expect(tree.layout(kid).y == 25)
}

/// A grow item's free space comes from the content box, so padding reduces what
/// it can grow into.
@Test func growDistributesTheContentBoxNotTheBorderBox() {
    let tree = LayoutTree()
    var s = Style()
    s.flexGrow = 1
    s.flexBasis = px(0)
    s.size = Size(width: .auto, height: px(20))
    let kid = tree.newNode(style: s, children: [])

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(400), height: px(100))
    rootStyle.padding = Edges(top: pxL(0), right: pxL(8), bottom: pxL(0), left: pxL(16))
    rootStyle.border = Edges(top: pxL(0), right: pxL(3), bottom: pxL(0), left: pxL(7))
    let root = tree.newNode(style: rootStyle, children: [kid])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    // 400 - (16 + 7 + 8 + 3) = 366
    #expect(tree.layout(kid).width == 366)
    #expect(tree.layout(kid).x == 23)
}

/// **Ruling BM-4** (see CLAUDE.md's "known divergences") — pins a deliberate
/// divergence from CSS, not a bug, and closes the mutation that deletes
/// `contentBox`'s `max(0, …)` guard.
///
/// CSS's real answer when padding + border exceeds the container's specified
/// size on an axis is to **grow the border box itself**, never to let the
/// content box go negative: `box-sizing: border-box` defines the used size as
/// `max(specified, padding + border)`. Measured against live WebKit for
/// `width: 100px; height: 80px; padding: 60px 50px; border-width: 10px` with
/// one auto-sized child: **WebKit renders the root at 120×140**, not 100×80.
/// Horizontal padding+border is 50 + 50 + 10 + 10 = 120, exceeding the
/// specified width of 100; vertical is 60 + 60 + 10 + 10 = 140, exceeding the
/// specified height of 80 — so WebKit grows the border box to fit them
/// exactly: 120 wide, 140 tall.
///
/// This engine does not grow the border box — implementing that belongs in
/// sizing (`resolveNodeSize`/`flexBaseSize`), which moves a node's *stored*
/// size and has reach far beyond `contentBox` (the freeze loop, every
/// ancestor). Out of scope for the box-model task. Instead `contentBox`
/// clamps the *content* box to zero and leaves the border box exactly as
/// specified, so the root here stays 100×80 — this test pins that choice.
///
/// Without `max(0, …)`, the content box's height goes negative (80 - 120 -
/// 20 = -60) and the stretched child inherits it *unclamped* — a negative
/// stored height — which is what actually reddens this test if the guard is
/// removed; the root's own rect does not move under that particular mutation,
/// since the guard lives downstream of it.
@Test func containerDoesNotGrowToFitOverconstrainedPaddingUnlikeWebKit() {
    let tree = LayoutTree()
    let a = tree.newNode(style: Style(), children: [])   // auto/auto: stretches on the cross

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(100), height: px(80))
    rootStyle.padding = Edges(top: pxL(60), right: pxL(50), bottom: pxL(60), left: pxL(50))
    rootStyle.border = Edges(top: pxL(10), right: pxL(10), bottom: pxL(10), left: pxL(10))
    let root = tree.newNode(style: rootStyle, children: [a])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    // WebKit: 120x140. We keep the specified border box, 100x80 — the pinned
    // divergence.
    #expect(tree.layout(root) == LayoutRect(x: 0, y: 0, width: 100, height: 80))
    // The child matches WebKit exactly (60, 70, 0, 0) even though the root
    // does not: its origin comes only from padding+border offsets, and its
    // clamped-to-zero content box happens to agree with WebKit's own here.
    #expect(tree.layout(a) == LayoutRect(x: 60, y: 70, width: 0, height: 0))
}
