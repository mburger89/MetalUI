import Testing
import MetalUICore
@testable import MetalUILayout

/// **An engine fact, not a `ScrollView` guard — no production type currently
/// relies on this.** It builds a `LayoutTree` by hand, with `flexShrink: 0`
/// and an explicit `min-height: 0` set directly on the content node; it does
/// not go through `ScrollView` or any other element in `Sources/MetalUI`.
///
/// What it pins: once CSS Sizing §4.5's automatic minimum is removed by an
/// explicit `min-height: 0`, `flexShrink: 0` is what keeps a node open against
/// the freeze loop's shrink — without it, content collapses to the viewport's
/// 100 and there is nothing left to scroll. That is a real and correctly
/// implemented engine mechanism.
///
/// **It was first written as a `ScrollView`-specific differential, and it is
/// not one.** `ScrollView`'s content node never carries an explicit
/// `min-height: 0` — it has no modifier surface to set one, conforming to
/// `Element` rather than `StyledElement` — so the *row* this test exercises
/// is unreachable through that type today. That says nothing about whether
/// `ScrollView` needs `flexShrink: 0`, and for a while it was wrongly read as
/// saying so: `ScrollView.requestLayout` does carry the override, it is
/// load-bearing for any content whose min-content and max-content sizes
/// differ, and `aScrollViewOfTextDoesNotShrinkItsContentToTheViewport`
/// (`Tests/MetalUITests/ScrollViewTests.swift`) is the test through that type
/// which this one is not. Kept here as the engine-level pin for the *other*
/// half of the mechanism — holding a node open once an explicit zero minimum
/// has removed the automatic one — which no element in `Sources/MetalUI`
/// reaches yet.
@Test @MainActor func flexShrinkHoldsAContentNodeOpenOnceItsAutomaticMinimumIsRemoved() throws {
    let tree = LayoutTree(generation: 0)
    var row = Style()
    row.size = Size(width: .auto, height: .length(.pixels(Pixels(40))))
    let rows = (0..<5).map { _ in tree.newNode(style: row, children: []) }

    var content = Style()
    content.flexDirection = .column
    content.flexShrink = 0
    content.minSize = Size(width: .auto, height: .length(.pixels(Pixels(0))))
    let contentNode = tree.newNode(style: content, children: rows)

    var viewport = Style()
    viewport.flexDirection = .column
    viewport.size = Size(width: .length(.pixels(Pixels(200))),
                         height: .length(.pixels(Pixels(100))))
    let viewportNode = tree.newNode(style: viewport, children: [contentNode])

    computeLayout(tree, root: viewportNode,
                  available: AvailableSpaceSize(width: .definite(200), height: .definite(100)))
    #expect(tree.layout(contentNode).height == 200,
            "flexShrink: 0 must hold the content open once the automatic minimum is gone")
}
