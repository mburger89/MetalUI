import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUI

private func px(_ v: Float) -> Pixels { Pixels(v) }

private func fixedHeight(_ h: Float) -> Style {
    var s = Style()
    s.size = Size(width: .auto, height: .length(.pixels(Pixels(h))))
    return s
}

/// Lays `element` out in a `width × height` frame and hands back the frame, the
/// root node and the root's own `LayoutState`, so a test can read any node's
/// resolved rect. Mirrors `TextMeasureTests.laidOut`.
///
/// **Not `Frame.render`, and not the brief's `renderProbe`.** `Frame.render`
/// discards the layout state it builds, so a caller outside the element has no
/// way back to `ScrollView.Layout.contentNode` — the one node this file exists
/// to measure. `Frame.lastScrollProbe`, which an earlier draft of this test
/// invented to work around that, does not exist and was not added; this helper
/// is the same "run layout only" idiom `TextMeasureTests.laidOut` already uses,
/// generalised to hand back the returned `LayoutState` instead of discarding it.
@MainActor
private func laidOut<E: Element>(_ element: inout E, width: Double, height: Double)
    -> (Frame, LayoutNodeID, E.LayoutState) {
    let frame = Frame(contentSize: Size(width: Pixels(Float(width)), height: Pixels(Float(height))),
                      scaleFactor: 1)
    var pass = LayoutPass(frame: frame)
    let (root, layout) = element.requestLayout(GlobalElementID.child(of: nil, at: 0, name: nil),
                                               pass: &pass)
    frame.computeRootLayout(root: root)
    return (frame, root, layout)
}

/// The content node overflows the viewport, which is what there is to scroll.
///
/// **The mechanism is §4.5's automatic minimum, not `flexShrink`** — measured,
/// and the differential is `aContentNodeWithAnExplicitZeroMinimumStillOverflows`
/// in `Tests/MetalUILayoutTests/ScrollLayoutTests.swift`. Getting this backwards
/// produces a `ScrollView` whose content silently equals its viewport and which
/// therefore never scrolls. What a wrong `requestLayout` (e.g. one that resolved
/// the content node's height instead of letting it overflow) catches here: the
/// content height would read 100, matching the viewport, and the second
/// `#expect` reddens.
@MainActor
@Test func theContentNodeOverflowsTheViewport() throws {
    var view = ScrollView(.vertical) {
        Column {
            Box(style: fixedHeight(40)); Box(style: fixedHeight(40))
            Box(style: fixedHeight(40)); Box(style: fixedHeight(40))
            Box(style: fixedHeight(40))
        }
    }
    let (frame, root, layout) = laidOut(&view, width: 200, height: 100)
    #expect(frame.bounds(of: root).size.height == px(100))
    #expect(frame.bounds(of: layout.contentNode).size.height == px(200),
            "five 40pt rows must measure 200, not the viewport's 100")
}

/// The offset clamps to `0 ... content - viewport` and never goes negative.
/// Catches a `clamp` that forgot the lower bound (a raw negative offset would
/// scroll the content past its start) or that used `content - viewport`
/// unclamped as the upper bound (a `min` with no `max(0, …)` around it would
/// give a negative ceiling instead of 0 for row three's case below).
@Test @MainActor func theOffsetClampsToTheScrollableRange() {
    #expect(ScrollView<EmptyGroup>.clamp(offset: -30, content: 200, viewport: 100) == 0)
    #expect(ScrollView<EmptyGroup>.clamp(offset: 500, content: 200, viewport: 100) == 100)
    #expect(ScrollView<EmptyGroup>.clamp(offset: 40, content: 200, viewport: 100) == 40)
}

/// Content shorter than the viewport is not scrollable at all — a negative
/// range must clamp to zero rather than to a negative maximum. Catches a
/// `clamp` that computes `content - viewport` (here, -40) as the ceiling
/// without flooring it at 0, which would clamp 25 down to -40 instead of up
/// to 0.
@Test @MainActor func contentShorterThanTheViewportDoesNotScroll() {
    #expect(ScrollView<EmptyGroup>.clamp(offset: 25, content: 60, viewport: 100) == 0)
}

/// Clamping happens on READ, not on write. The wheel handler has no layout to
/// validate against, and the layout that would is a frame away — this asserts
/// that a wildly out-of-range stored value (as if content shrank drastically
/// between frames) still comes back clamped rather than passed through.
@Test @MainActor func aStoredOffsetPastTheEndIsClampedWhenItIsRead() {
    #expect(ScrollView<EmptyGroup>.clamp(offset: 9_999, content: 200, viewport: 100) == 100)
}
