import Testing
import Metal
import MetalUICore
import MetalUILayout
import MetalUIPlatform
import MetalUIRender
@testable import MetalUI

// Divergence 15: a `ScrollView` nested inside a **scrolled** `ScrollView` gets
// a content mask in the wrong coordinate space, so its subtree is clipped away.
//
// This file exists to make that a red test the day somebody fixes it, and it is
// deliberately written to assert TODAY'S WRONG ANSWER — the same instrument
// `aListNotAtTheScrollersContentOriginWindowsAgainstTheWrongRows` uses for
// divergence 14, and for the same reason: a limitation nothing asserts is a
// limitation the next person rediscovers.

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

/// **Divergence 15, and this test asserts the WRONG answer on purpose.**
///
/// A `ScrollView` nested inside a **scrolled** `ScrollView` receives an empty
/// content mask, so nothing inside it is drawn at all — while its rows are laid
/// out correctly, painted at the right window positions, and its wheel routing
/// is exactly right.
///
/// **The mechanism is one missing term.** `Frame.pushClip` intersects the
/// incoming rect into `activeClip` without translating it by `activeOffset`
/// first, where `Frame.insertHitbox` — the routing side — does translate. So
/// the inner viewport's clip is computed in the engine's untranslated space
/// while `activeClip` is already in surface space, and the two are compared as
/// though they were the same thing. Here the inner viewport is stored at engine
/// y = 300 and paints at window y = 100 after the outer scrolls 200; the clip
/// intersects (0, 0) 200x200 with (0, 300) 200x100 and gets nothing.
///
/// **Routing was the same defect and was fixed** — ruling C1 of the
/// input-and-state milestone, pinned by
/// `aNestedScrollViewInsideAScrolledOneReceivesTheWheelWhereItPaints`. This is
/// its sibling on the paint side, found by the same probe and deliberately left
/// alone: it is a clip-space change whose blast radius is every clipped subtree
/// in the framework, and it was found inside a milestone whose entire test
/// surface is input rather than paint.
///
/// **Whoever fixes it gets a red test rather than a surprise** — the same
/// instrument `aListNotAtTheScrollersContentOriginWindowsAgainstTheWrongRows`
/// uses for divergence 14. Every `#expect` below says so in its own failure
/// message. Delete or invert this test; do not "repair" it.
///
/// The 300pt filler is what makes the mask **empty** rather than merely
/// misplaced, and the difference is worth having in the fixture: with a 150pt
/// filler (the geometry the routing pin uses) the outer has only 50pt of travel,
/// the intersection is still non-empty, and the inner shows a 50pt band of
/// itself in the wrong place — wrong, but a reader could mistake it for a
/// rounding problem. At 300 the outer has 200pt of travel and the failure is
/// total.
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

    for row in rows {
        #expect(row.contentMask.size.height == 0,
                """
                WRONG ON PURPOSE — divergence 15. This asserts today's defect: \
                a nested scroller's content mask is computed in the engine's \
                untranslated space, so it comes out empty and nothing inside \
                the inner ScrollView draws. If you are reading this because it \
                went red, you have probably fixed `Frame.pushClip` by adding \
                `+ activeOffset` to its incoming bounds — delete this test (and \
                CLAUDE.md's divergence 15) rather than repairing it.
                """)
        #expect(row.contentMask.origin.y == 300,
                "and the empty mask sits at the inner viewport's UNTRANSLATED y, which names the cause")
    }
}
