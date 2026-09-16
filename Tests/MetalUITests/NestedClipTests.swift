import Testing
import Metal
import MetalUICore
import MetalUILayout
import MetalUIPlatform
import MetalUIRender
@testable import MetalUI

// Divergence 15 — **CLOSED by plan task 5, lane 2 (ruling `OM-U`)**. A
// `ScrollView` nested inside a **scrolled** `ScrollView` used to get a content
// mask in the wrong coordinate space, so its subtree was clipped away. This
// file asserted that wrong answer on purpose; it now asserts the right one,
// and the comment below records what the inversion was.
//
// **Why the fix was taken here rather than deferred again.** Lane 2 puts
// `pass.clipped(to: bounds, …)` behind a public `.clipped()` on every
// `Box`/`Stack`/`Text`/`ModifierLayer`, so `Frame.pushClip`'s missing
// `+ activeOffset` stops being "a `ScrollView` inside a scrolled `ScrollView`"
// and becomes "any element inside one": a `.clipped()` row in the demo's
// 500-row list would blank itself on the first scroll. Ruling `OM-U` records
// the severity change and record §04 records why the added term is a no-op
// wherever `activeOffset == 0`.

private func columnStyle() -> Style {
    var s = Style()
    s.flexDirection = .column
    return s
}

private func fixedHeight(_ h: Float) -> Style {
    var s = columnStyle()
    s.size = Size(width: .auto, height: .length(.pixels(Pixels(h))))
    return s
}

/// `fixedHeight` plus the `min-height: 0` that stops CSS Sizing §4.5's
/// automatic minimum floating the box back up to its content's height — the
/// half of §4.5 this engine implements (CLAUDE.md divergence 5), and the same
/// override `Sources/MetalUIDemo/main.swift` writes around its own scroll list.
private func boundedHeight(_ h: Float) -> Style {
    var s = fixedHeight(h)
    s.minSize.height = .length(.pixels(Pixels(0)))
    return s
}

private func pt(_ x: Float, _ y: Float) -> Point<Pixels> {
    Point(x: Pixels(x), y: Pixels(y))
}

private func wheel(at position: Point<Pixels>, deltaY: Float) -> InputEvent {
    .scrollWheel(ScrollEvent(position: position, delta: Point(x: Pixels(0), y: Pixels(deltaY)),
                            isMomentum: false))
}

/// **Divergence 15, INVERTED** (ruling `OM-U`): a `ScrollView` nested inside a
/// **scrolled** `ScrollView` now receives the content mask it paints at, rather
/// than an empty one.
///
/// **The name is kept deliberately.** It is cited by CLAUDE.md, by record §04
/// and by the outer-modifiers spec as the pin for this defect; renaming it
/// would leave four documents pointing at nothing while the test that replaced
/// it looked new. What changed is every expectation below, and the failure
/// messages say which answer they now assert.
///
/// **The mechanism was one missing term.** `Frame.pushClip` intersected the
/// incoming rect into `activeClip` without translating it by `activeOffset`
/// first, where `Frame.insertHitbox` — the routing side — does translate. So
/// the inner viewport's clip was computed in the engine's untranslated space
/// while `activeClip` was already in surface space, and the two were compared
/// as though they were the same thing. Here the inner viewport is stored at
/// engine y = 300 and paints at window y = 100 after the outer scrolls 200; the
/// clip intersected (0, 0) 200x200 with (0, 300) 200x100 and got nothing. With
/// the term added it intersects (0, 0) 200x200 with **(0, 100) 200x100** and
/// gets the viewport, which is where the rows are drawn.
///
/// **Routing was the same defect and was fixed first** — ruling IN-F of the
/// input-and-state milestone, pinned by
/// `aNestedScrollViewInsideAScrolledOneReceivesTheWheelWhereItPaints`. This was
/// its sibling on the paint side. The two halves now agree, which is the
/// property the routing assertion below is retained to state.
///
/// The 300pt filler is what made the old mask **empty** rather than merely
/// misplaced, and it is retained: with a 150pt filler (the geometry the routing
/// pin uses) the outer has only 50pt of travel and the old intersection was
/// still non-empty, so the fixture would have been able to read "nearly right"
/// as right. At 300 the outer has 200pt of travel and the before/after answers
/// are 0 and 100 — unconfusable.
@Test @MainActor func aNestedScrollViewInsideAScrolledOneGetsAnEmptyContentMask() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 200) {
        ScrollView(.vertical, elementID: ElementID("outer")) {
            Box(style: columnStyle()) {
                Box(style: fixedHeight(300))
                Box(style: boundedHeight(100)) {
                    ScrollView(.vertical, elementID: ElementID("inner")) {
                        Box(style: columnStyle()) {
                            Box(style: fixedHeight(50)).background(.accent)
                            Box(style: fixedHeight(50)).background(.surface)
                            Box(style: fixedHeight(50)).background(.separator)
                        }
                    }
                }
            }
        }
    }
    window.drawFrameIfNeeded()

    // Drive the outer scroller to its 200pt ceiling (400pt of content in a
    // 200pt viewport). (100, 20) is above the inner scroller at every offset
    // this passes through, so only the outer can take these.
    for _ in 0..<7 {
        platformWindow.simulateInput(wheel(at: pt(100, 20), deltaY: -37))
        window.drawFrameIfNeeded()
    }

    let regions = window.lastScrollRegions
    try #require(regions.count == 2, "outer and inner each register exactly one region")
    #expect(window.stateTable.peek(regions[0].id, as: ScrollState.self)?.offset == 200,
            "the outer is parked at its ceiling, which is what puts the inner into view")

    // The ROUTING half is right, and asserting it here is what makes this a
    // paint finding rather than a vague one: the inner's region is recorded
    // where it paints, because `insertHitbox` translates.
    #expect(regions[1].bounds.origin.y == Pixels(100)
                && regions[1].bounds.size.height == Pixels(100),
            "the inner's hit region is correct — this divergence is paint, not routing")

    let rows = window.lastScene.rects.filter { $0.bounds.size.height == 50 }
    try #require(rows.count == 3, "all three rows of the inner scroller are emitted")
    #expect(rows.map { $0.bounds.origin.y } == [100, 150, 200],
            "and each is emitted at the right WINDOW position — layout and translation are correct")

    // The instrument has to be able to read a mask that is NOT the viewport:
    // before the fix every one of these was (0, 300) 0x0, and the three
    // assertions below would each have failed on their own. Requiring the
    // masks to agree with the SCROLL REGION — a number produced by the other
    // half of the framework, `insertHitbox`, which always translated — is what
    // makes this a cross-check rather than two copies of one belief.
    let region = regions[1].bounds
    for row in rows {
        #expect(row.contentMask.size.height == 100,
                """
                divergence 15 CLOSED (OM-U): a nested scroller's content mask is \
                now intersected in surface space, so it is the inner viewport's \
                own 100pt height. Before the fix this read 0 and nothing inside \
                the inner ScrollView drew at all.
                """)
        #expect(row.contentMask.origin.y == 100,
                "and it sits at the inner viewport's TRANSLATED y — 100, not the engine's 300")
        #expect(row.contentMask.origin.y == region.origin.y.value
                    && row.contentMask.size.height == region.size.height.value,
                """
                and the paint half agrees with the routing half: the mask is \
                exactly the rect the wheel is routed to. These two were computed \
                in different coordinate spaces until OM-U.
                """)
    }
}
