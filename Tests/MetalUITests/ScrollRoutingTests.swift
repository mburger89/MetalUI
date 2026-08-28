import Testing
import Metal
import MetalUICore
import MetalUILayout
import MetalUIPlatform
@testable import MetalUI

// A `Box(style:)` column, not the public `Column` element — `Column` centres
// its cross axis by ruling EP-8, and these fixtures need the plain engine
// default (`nil` alignItems, read as CSS's `stretch`) so a fixed-width child
// fills the frame predictably. See `Style.swift` and `Stack.swift`.
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

private func pt(_ x: Float, _ y: Float) -> Point<Pixels> {
    Point(x: Pixels(x), y: Pixels(y))
}

/// A vertical wheel event at a chosen window position.
private func wheel(at position: Point<Pixels>, deltaY: Float,
                   isMomentum: Bool = false) -> InputEvent {
    .scrollWheel(ScrollEvent(position: position, delta: Point(x: Pixels(0), y: Pixels(deltaY)),
                            isMomentum: isMomentum))
}

/// A wheel event inside a region moves that region's offset.
///
/// **-37, not a round number.** `Box(style: fixedHeight(40))` appears five
/// times in this fixture — 40, 80, 120, 200 are all numbers this scene
/// produces somewhere (row height, viewport height, content height), so a
/// delta or an expected offset that happened to equal one of those would
/// still pass a wrong implementation that read the wrong quantity. -37 and
/// its negation, 37, appear nowhere else in the geometry.
///
/// What a wrong `applyScroll` this catches: one that never calls
/// `stateTable.withState` at all (offset stays the freshly-initialised 0,
/// caught by the second `#expect`), one that adds the delta instead of
/// subtracting it (offset would read -37), or one that ignores `delta.y`
/// and hardcodes a step (offset would read some other constant, not 37).
@Test @MainActor func aWheelEventInsideARegionScrollsIt() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 120) {
        ScrollView(.vertical, elementID: ElementID("list")) {
            Box(style: columnStyle()) {
                Box(style: fixedHeight(40)); Box(style: fixedHeight(40))
                Box(style: fixedHeight(40)); Box(style: fixedHeight(40))
                Box(style: fixedHeight(40))
            }
        }
    }
    window.drawFrameIfNeeded()
    let region = try #require(window.lastScrollRegions.first,
                              "the ScrollView must have registered a region")
    #expect(window.stateTable.peek(region.id, as: ScrollState.self)?.offset == 0,
            "the offset before any wheel event")

    platformWindow.simulateInput(wheel(at: pt(60, 60), deltaY: -37))

    #expect(window.stateTable.peek(region.id, as: ScrollState.self)?.offset == 37,
            "delta.y -37 must move the offset by +37 (natural scrolling negates it)")
}

/// A wheel event outside every region moves nothing.
///
/// What a wrong `applyScroll` this catches: one that routes to the first (or
/// only) registered region unconditionally rather than checking
/// `contains` — a hit test that is a no-op would leave this test as the only
/// one distinguishing "always route" from "route on hit", since the first
/// test above never proves the position was checked at all.
@Test @MainActor func aWheelEventOutsideEveryRegionScrollsNothing() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 120) {
        ScrollView(.vertical, elementID: ElementID("list")) {
            Box(style: columnStyle()) {
                Box(style: fixedHeight(40)); Box(style: fixedHeight(40))
                Box(style: fixedHeight(40)); Box(style: fixedHeight(40))
                Box(style: fixedHeight(40))
            }
        }
    }
    window.drawFrameIfNeeded()
    let region = try #require(window.lastScrollRegions.first)

    // The window is 120x120; this point is nowhere near it.
    platformWindow.simulateInput(wheel(at: pt(900, 900), deltaY: -37))

    #expect(window.stateTable.peek(region.id, as: ScrollState.self)?.offset == 0,
            "a point outside every registered region must move nothing")
}

/// **Reverse order: the topmost (last-registered) region wins.** Same rule
/// §8.1 states for hitboxes, arriving early because scroll needs it. Two
/// overlapping regions at the same point must not both scroll.
///
/// The overlap here is a nested `ScrollView`: an "inner" list sits as the
/// sole content of an "outer" one, so `outer`'s registered viewport
/// (0,0,120,120) and `inner`'s (0,0,120,60) share every point in `inner`'s
/// rect. `outer` registers first (prepaint touches a container before
/// descending into it), so a walk that picks the FIRST match instead of the
/// LAST would scroll `outer` here — the mutation this test exists to catch,
/// and it is measured in the report rather than asserted about.
///
/// What a wrong `applyScroll` this catches, beyond the ordering mutation
/// itself: any implementation that routes to every containing region at once
/// (both offsets would move) rather than exactly one.
@Test @MainActor func theTopmostOverlappingRegionWinsAndTheOtherDoesNotMove() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 120) {
        ScrollView(.vertical, elementID: ElementID("outer")) {
            Box(style: columnStyle()) {
                ScrollView(.vertical, elementID: ElementID("inner")) {
                    Box(style: columnStyle()) {
                        Box(style: fixedHeight(20)); Box(style: fixedHeight(20))
                        Box(style: fixedHeight(20))
                    }
                }
            }
        }
    }
    window.drawFrameIfNeeded()
    try #require(window.lastScrollRegions.count == 2,
                "outer and inner must each register exactly one region")
    let outer = window.lastScrollRegions[0]
    let inner = window.lastScrollRegions[1]
    #expect(outer.bounds.size.height == Pixels(120), "outer fills the 120-tall frame")
    #expect(inner.bounds.size.height == Pixels(60), "inner shrinks to its own 3x20 content")

    // (60, 30) sits inside both outer's (0,0,120,120) and inner's (0,0,120,60).
    platformWindow.simulateInput(wheel(at: pt(60, 30), deltaY: -37))

    #expect(window.stateTable.peek(inner.id, as: ScrollState.self)?.offset == 37,
            "inner is the topmost (last-registered) region and must receive the event")
    #expect(window.stateTable.peek(outer.id, as: ScrollState.self)?.offset == 0,
            "outer must not also move")
}

/// Momentum deltas are applied identically to direct ones — the OS does the
/// physics and we accumulate. Building our own inertia now means building it
/// twice, once more for iOS and programmatic scrolling.
///
/// What a wrong `applyScroll` this catches: one that reads `isMomentum` at
/// all — ignoring momentum events (offset stays 0) or scaling them
/// differently from a direct delta (offset reads something other than the 37
/// the first test already established for the identical geometry and delta).
@Test @MainActor func momentumDeltasScrollLikeDirectOnes() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 120) {
        ScrollView(.vertical, elementID: ElementID("list")) {
            Box(style: columnStyle()) {
                Box(style: fixedHeight(40)); Box(style: fixedHeight(40))
                Box(style: fixedHeight(40)); Box(style: fixedHeight(40))
                Box(style: fixedHeight(40))
            }
        }
    }
    window.drawFrameIfNeeded()
    let region = try #require(window.lastScrollRegions.first)

    platformWindow.simulateInput(wheel(at: pt(60, 60), deltaY: -37, isMomentum: true))

    #expect(window.stateTable.peek(region.id, as: ScrollState.self)?.offset == 37,
            "a momentum delta of -37 must move the offset by +37, exactly like a direct one")
}

/// **Closes a coverage gap the four tests above do not: a nested region the
/// ancestor's clip excludes must not receive wheel events, even at a point
/// squarely inside the nested region's OWN (unclipped) rect.**
///
/// `outer` is a 120-tall viewport whose content is a 150-tall filler followed
/// by `inner`, a nested `ScrollView`. In the engine's absolute layout space
/// (unaffected by scroll — `Frame.bounds(of:)`'s doc explains why) `inner`'s
/// own rect starts at y=150, entirely below `outer`'s (0,0,120,120) viewport
/// window. `registerScrollRegion` intersects `inner`'s rect with the active
/// clip at registration time, which is `outer`'s viewport — so `inner`'s
/// registered region is clamped to zero height and can never contain a point.
///
/// A point at (60, 180) is inside `inner`'s RAW rect (y: 150..210) and
/// outside `outer`'s (y: 0..120) — the one point that tells the two
/// implementations apart. Storing raw bounds instead of clipped ones (the
/// required mutation 3) makes this point match `inner`'s raw region and wheel
/// it; storing clipped bounds, as required, makes it match nothing.
///
/// This is the differential CLAUDE.md's fixture-hygiene rule asks for: it was
/// generated by running mutation 3 against this exact test (see the report)
/// before being committed, not derived by hand.
@Test @MainActor func aNestedRegionClippedOutOfViewByItsParentDoesNotReceiveWheelEvents() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 120) {
        ScrollView(.vertical, elementID: ElementID("outer")) {
            Box(style: columnStyle()) {
                Box(style: fixedHeight(150))
                ScrollView(.vertical, elementID: ElementID("inner")) {
                    Box(style: columnStyle()) {
                        Box(style: fixedHeight(20)); Box(style: fixedHeight(20))
                        Box(style: fixedHeight(20))
                    }
                }
            }
        }
    }
    window.drawFrameIfNeeded()
    try #require(window.lastScrollRegions.count == 2)
    let outer = window.lastScrollRegions[0]
    let inner = window.lastScrollRegions[1]
    // The clip has already done its work by the time this frame's regions are
    // captured: `inner`'s registered rect is clamped to zero height, not
    // merely offset — `Frame.intersect` clamps a non-overlapping axis to 0
    // rather than letting it go negative.
    #expect(inner.bounds.size.height == Pixels(0),
            "inner's clipped registration must be empty: it is entirely below outer's viewport")

    platformWindow.simulateInput(wheel(at: pt(60, 180), deltaY: -37))

    #expect(window.stateTable.peek(inner.id, as: ScrollState.self)?.offset == 0,
            "a point inside inner's RAW (unclipped) rect but outside outer's viewport must not scroll inner")
    #expect(window.stateTable.peek(outer.id, as: ScrollState.self)?.offset == 0,
            "the same point is also outside outer's own (0,0,120,120) region")
}
