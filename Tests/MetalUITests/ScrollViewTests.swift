import CoreText
import Foundation
import Testing
import MetalUICore
import MetalUILayout
import MetalUIRender
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
private func laidOut<E: Element>(_ element: inout E, width: Double, height: Double,
                                 authority: LayoutAuthority = Frame.defaultLayoutAuthority)
    -> (Frame, LayoutNodeID, E.LayoutState) {
    // Plan task 7, stage 3, lane 3 (`LR-BI`): `reportsUnlowerableFields` stays
    // off, so this helper fails the way a production frame does.
    let frame = Frame(contentSize: Size(width: Pixels(Float(width)), height: Pixels(Float(height))),
                      scaleFactor: 1, layoutAuthority: authority)
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
@Test(arguments: AuthorityCoverage.authorities) @MainActor
func theContentNodeOverflowsTheViewport(_ authority: LayoutAuthority) throws {
    AuthorityCoverage.record(#function, authority)
    var view = ScrollView(.vertical) {
        Column {
            Box(style: fixedHeight(40)); Box(style: fixedHeight(40))
            Box(style: fixedHeight(40)); Box(style: fixedHeight(40))
            Box(style: fixedHeight(40))
        }
    }
    let (frame, root, layout) = laidOut(&view, width: 200, height: 100,
                                        authority: authority)
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
    #expect(ScrollChrome.clamp(offset: -30, content: 200, viewport: 100) == 0)
    #expect(ScrollChrome.clamp(offset: 500, content: 200, viewport: 100) == 100)
    #expect(ScrollChrome.clamp(offset: 40, content: 200, viewport: 100) == 40)
}

/// Content shorter than the viewport is not scrollable at all — a negative
/// range must clamp to zero rather than to a negative maximum. Catches a
/// `clamp` that computes `content - viewport` (here, -40) as the ceiling
/// without flooring it at 0, which would clamp 25 down to -40 instead of up
/// to 0.
@Test @MainActor func contentShorterThanTheViewportDoesNotScroll() {
    #expect(ScrollChrome.clamp(offset: 25, content: 60, viewport: 100) == 0)
}

/// Clamping happens on READ, not on write. The wheel handler has no layout to
/// validate against, and the layout that would is a frame away — this asserts
/// that a wildly out-of-range stored value (as if content shrank drastically
/// between frames) still comes back clamped rather than passed through.
@Test @MainActor func aStoredOffsetPastTheEndIsClampedWhenItIsRead() {
    #expect(ScrollChrome.clamp(offset: 9_999, content: 200, viewport: 100) == 100)
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
@Test(arguments: AuthorityCoverage.authorities) @MainActor
func aScrollViewOfTextDoesNotShrinkItsContentToTheViewport(_ authority: LayoutAuthority) throws {
    AuthorityCoverage.record(#function, authority)
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
    let (frame, root, layout) = laidOut(&view, width: 200, height: 100,
                                        authority: authority)
    let viewportWidth = Double(frame.bounds(of: root).size.width.value)
    let contentWidth = Double(frame.bounds(of: layout.contentNode).size.width.value)

    #expect(contentWidth > viewportWidth,
            "the content node must overflow its 200pt viewport; \(contentWidth) == the viewport means the freeze loop shrank it and there is nothing left to scroll")
    #expect(abs(contentWidth - expected) < 0.5,
            "two unshrunk labels side by side must measure CoreText's summed advance \(expected), got \(contentWidth)")
}

// MARK: - Rounded clip corners (ruling CL-A's follow-on)

/// **Integration guard, not a shader guard.** `ClipTests.swift` proves
/// `mask_coverage` cuts a rounded corner correctly given a `MUIRect`/`MUIGlyph`
/// that already carries non-zero `maskCornerRadii` — it says nothing about
/// whether `ScrollView.cornerRadius(_:)` actually REACHES that field through
/// `Frame`'s clip stack. A mutation that drops the radius anywhere on that
/// path — `ScrollView.paint` forwarding a literal zero to `clipped(...)`
/// instead of `cornerRadius`, or `Frame.fill`/`draw` not reading
/// `activeClipRadii` — would leave every GPU corner test green (they build
/// their `MUIRect`/`MUIGlyph` by hand) while this element silently painted a
/// square clip in production. So this reads the radius back off the SCENE a
/// full `Frame.render` produces, with no GPU involved.
///
/// Three rows, each its own `Box` with a background, so each emits its own
/// `MUIRect` inside the clipped block — proving the radius reaches every
/// primitive the clip covers, not just the first.
@Test(arguments: AuthorityCoverage.authorities) @MainActor
func aScrollViewsCornerRadiusReachesEveryPrimitiveItClips(_ authority: LayoutAuthority) throws {
    AuthorityCoverage.record(#function, authority)
    // `.width(Pixels(50))` as well as the height: the legacy engine stretched
    // these rows to the 50pt viewport, the kernel viewport's cross answer is its
    // content's (`CN-M`), and a row that declares neither is 0 wide under the
    // proposal authority (ruling `LR-BN`). 50 is the number the stretch already
    // produced, so no legacy literal below moves.
    var view = ScrollView(.vertical) {
        Box(decoration: Decoration(background: .surface)).width(Pixels(50)).height(Pixels(20))
        Box(decoration: Decoration(background: .surface)).width(Pixels(50)).height(Pixels(20))
        Box(decoration: Decoration(background: .surface)).width(Pixels(50)).height(Pixels(20))
    }
    .cornerRadius(Pixels(14))

    // A fresh scroll (age 0), seeded explicitly. Since `ScrollState.lastScrollTime`
    // defaults to `-.infinity` (never scrolled), a default state paints no
    // indicator at all; this test used to get its fourth rect only from the
    // old age-0 default, which was the first-frame flash review item B-11
    // removed.
    let table = StateTable()
    table.withState(GlobalElementID.child(of: nil, at: 0, name: nil), initial: ScrollState()) {
        $0.lastScrollTime = 0
    }
    let frame = Frame(contentSize: Size(width: Pixels(50), height: Pixels(30)), scaleFactor: 1,
                      stateTable: table, layoutAuthority: authority)
    frame.render(&view)
    let scene = frame.finalizedScene()

    // Four rects: the three rows, painted INSIDE the clipped block, plus the
    // scroll indicator — content overflows a 30pt viewport with three 20pt
    // rows, so the indicator draws too. The indicator paints OUTSIDE the
    // clipped block, in viewport space, and it DOES carry the viewport's
    // corner radius, through its own `offsetBy: .zero` clip. An earlier
    // version of this comment said it must not, which stopped being true with
    // the rounded-corner clip fix. The loop below checks the rows, and the
    // indicator's own radius is pinned after it, rather than being assumed
    // away by `dropLast()`.
    try #require(scene.rects.count == 4,
                "three rows plus the scroll indicator must all paint")
    for rect in scene.rects.dropLast() {
        #expect(rect.maskCornerRadii.topLeft == 14)
        #expect(rect.maskCornerRadii.topRight == 14)
        #expect(rect.maskCornerRadii.bottomRight == 14)
        #expect(rect.maskCornerRadii.bottomLeft == 14)
    }
    let indicator = try #require(scene.rects.last)
    #expect(indicator.maskCornerRadii.topLeft == 14,
            "the indicator's own viewport-space clip carries the scroller's corner radius")
}

/// The zero-default half of the same guard: a `ScrollView` with no
/// `cornerRadius(_:)` call must still emit a SQUARE clip — every call site
/// written before this milestone, which is the overwhelming majority of them.
/// Without this, a mutation that hardcoded a NON-zero radius regardless of
/// `cornerRadius` would pass the test above and every existing clip test
/// (none of which reads `maskCornerRadii` back) while rounding every
/// `ScrollView` in the corpus that never asked for it.
@Test(arguments: AuthorityCoverage.authorities) @MainActor
func aScrollViewWithNoCornerRadiusClipsSquare(_ authority: LayoutAuthority) throws {
    AuthorityCoverage.record(#function, authority)
    var view = ScrollView(.vertical) {
        Box(decoration: Decoration(background: .surface)).width(Pixels(50)).height(Pixels(20))
        Box(decoration: Decoration(background: .surface)).width(Pixels(50)).height(Pixels(20))
    }

    let frame = Frame(contentSize: Size(width: Pixels(50), height: Pixels(30)), scaleFactor: 1,
                      layoutAuthority: authority)
    frame.render(&view)
    let scene = frame.finalizedScene()

    try #require(!scene.rects.isEmpty)
    for rect in scene.rects {
        #expect(rect.maskCornerRadii.topLeft == 0)
        #expect(rect.maskCornerRadii.topRight == 0)
        #expect(rect.maskCornerRadii.bottomRight == 0)
        #expect(rect.maskCornerRadii.bottomLeft == 0)
    }
}
