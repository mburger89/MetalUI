import CoreText
import Foundation
import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUIText
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
/// **For THIS fixture the mechanism is §4.5's automatic minimum, and that is
/// the whole reason this test cannot see `flexShrink`.** Fixed-height `Box`es
/// have the same min-content and max-content size, so the freeze loop has
/// nothing to shrink and `contentStyle.flexShrink = 0` is invisible here —
/// deleting that line leaves this test green. The case where it is
/// load-bearing needs content whose intrinsic sizes differ and is pinned by
/// `aScrollViewOfTextDoesNotShrinkItsContentToTheViewport` below; the engine
/// mechanism is pinned independently of `ScrollView` by
/// `flexShrinkHoldsAContentNodeOpenOnceItsAutomaticMinimumIsRemoved`
/// (`Tests/MetalUILayoutTests/ScrollLayoutTests.swift`).
///
/// What a wrong `requestLayout` (e.g. one that resolved the content node's
/// height instead of letting it overflow) catches here: the content height
/// would read 100, matching the viewport, and the second `#expect` reddens.
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

/// **`flexShrink: 0` on the content node, pinned through `ScrollView` itself.**
///
/// The content node's automatic minimum floors it at its **min-content** size;
/// its flex base size is **max-content**. Where those two differ — which is
/// every content containing text, and no content built from fixed-size `Box`es
/// — the freeze loop shrinks the node from the latter towards the former, and
/// `contentStyle.flexShrink = 0` is the only thing that stops it. The four-row
/// probe in `ScrollView.swift`'s doc comment used fixed-height `Box`es, whose
/// min-content and max-content are the same number, so it could not
/// distinguish this case at all.
///
/// What a wrong implementation this catches, measured: **delete
/// `contentStyle.flexShrink = 0` and the content node measures exactly 200 —
/// the viewport's own width — so there is nothing to scroll and the indicator
/// is suppressed entirely.** Both `#expect`s below redden.
///
/// **The oracle is CoreText, not this engine** (taxonomy shape 12): the
/// expected width is `CTLineGetTypographicBounds` on each label's own
/// single-line `CTLine`, summed. Nothing in `MetalUIText` or `MetalUILayout`
/// contributes to the expectation.
@Test @MainActor func aScrollViewOfTextDoesNotShrinkItsContentToTheViewport() throws {
    let a = "The quick brown fox jumps over the lazy dog"
    let b = "Pack my box with five dozen liquor jugs"
    let ctFont = FontResolver.resolve(family: nil, size: 13).ctFont
    let key = NSAttributedString.Key(kCTFontAttributeName as String)
    func advance(_ s: String) -> Double {
        let attributed = NSAttributedString(string: s, attributes: [key: ctFont])
        return CTLineGetTypographicBounds(CTLineCreateWithAttributedString(attributed), nil, nil, nil)
    }
    let expected = advance(a) + advance(b)
    try #require(expected > 400,
                 "the fixture must overflow a 200pt viewport by a wide margin, got \(expected)")

    var view = ScrollView(.horizontal) { Text(a); Text(b) }
    let (frame, root, layout) = laidOut(&view, width: 200, height: 100)
    let viewportWidth = Double(frame.bounds(of: root).size.width.value)
    let contentWidth = Double(frame.bounds(of: layout.contentNode).size.width.value)

    #expect(contentWidth > viewportWidth,
            "the content node must overflow its 200pt viewport; \(contentWidth) == the viewport means the freeze loop shrank it and there is nothing left to scroll")
    #expect(abs(contentWidth - expected) < 0.5,
            "two unshrunk labels side by side must measure CoreText's summed advance \(expected), got \(contentWidth)")
}
