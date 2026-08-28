import Testing
import MetalUICore
@testable import MetalUILayout

/// **The differential that names the mechanism.** `ScrollView`'s content node
/// sets `flexShrink: 0` as a belt to CSS Sizing §4.5's automatic minimum, which
/// is what actually keeps it from collapsing (CLAUDE.md, `Sources/MetalUI/
/// ScrollView.swift`). With an explicit `min-height: 0` the automatic minimum
/// is gone, and then `flexShrink: 0` is the only thing left keeping the content
/// from collapsing to the viewport. Measured against the engine 2026-08-28:
/// without both, content = 100 and there is nothing to scroll.
///
/// This is what stops the doc comment on `ScrollView` reverting to the wrong
/// mechanism — the required mutation (Task 6's brief) removes
/// `contentStyle.flexShrink = 0` from `ScrollView.requestLayout` and expects
/// exactly this test to redden while `theContentNodeOverflowsTheViewport`
/// (`ScrollViewTests.swift`, which leaves `min-height: auto`) stays green. That
/// split is the proof the two mechanisms are distinct rather than the same one
/// reported twice.
@Test @MainActor func aContentNodeWithAnExplicitZeroMinimumStillOverflows() throws {
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
