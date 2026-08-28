import Testing
import Metal
import MetalUICore
import MetalUILayout
import MetalUIPlatform
@testable import MetalUI

// A `Box(style:)` column, not the public `Column` element — `Column` centres
// its cross axis by ruling EP-8, and these fixtures need the plain engine
// default (`nil` alignItems, read as CSS's `stretch`) so a fixed-width child
// fills the frame predictably. See `Style.swift` and `Flex.swift` (which held
// `Column`/`Row` under the name `Stack.swift` until the stack-container
// milestone took that name for the `Stack` element).
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

/// A horizontal wheel event at a chosen window position — the counterpart
/// `wheel(at:deltaY:)` needs for a `.horizontal` `ScrollView`.
private func wheel(at position: Point<Pixels>, deltaX: Float,
                   isMomentum: Bool = false) -> InputEvent {
    .scrollWheel(ScrollEvent(position: position, delta: Point(x: Pixels(deltaX), y: Pixels(0)),
                            isMomentum: isMomentum))
}

private func rowStyle() -> Style {
    var s = Style()
    s.flexDirection = .row
    return s
}

private func fixedWidth(_ w: Float) -> Style {
    var s = rowStyle()
    s.size = Size(width: .length(.pixels(Pixels(w))), height: .auto)
    return s
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

/// **A `.horizontal` `ScrollView` scrolls on `delta.x` only — a vertical
/// wheel does not move it.** The fix for the axis bug this test exists to
/// catch: `Window.applyScroll` used to read `delta.y` unconditionally
/// regardless of the target region's axis, so a horizontal list responded to
/// vertical wheel motion and ignored horizontal motion entirely.
///
/// Both halves are asserted, and the second is the one that would have
/// caught the original bug: the first `#expect` alone (delta.x moves the
/// offset) also passes under the old always-`y` code whenever `delta.y`
/// happens to be 0, which is exactly the shape of event AppKit sends for a
/// horizontal trackpad swipe (`ScrollEvent(delta: Point(x: dx, y: 0))`) —
/// so without the second `#expect`, this test alone would not have reddened
/// against the bug the coordinator reported. `delta.y` here is deliberately
/// **nonzero** (-19) rather than 0, so a wrong implementation that still
/// reads `delta.y` at all has something to wrongly move.
///
/// What a wrong `applyScroll` this catches: reading `delta.y` instead of
/// `delta.x` for a horizontal region (mutation, verified in the report); a
/// fallback that lets a vertical wheel drive a horizontal list (the second
/// `#expect` would catch a nonzero result from the -19 sent on that axis);
/// or a `registerScrollRegion` that dropped `axis` and defaulted it to
/// `.vertical` regardless of what the `ScrollView` declared.
@Test @MainActor func aHorizontalScrollViewMovesOnDeltaXNotDeltaY() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 120) {
        ScrollView(.horizontal, elementID: ElementID("row")) {
            Box(style: rowStyle()) {
                Box(style: fixedWidth(40)); Box(style: fixedWidth(40))
                Box(style: fixedWidth(40)); Box(style: fixedWidth(40))
                Box(style: fixedWidth(40))
            }
        }
    }
    window.drawFrameIfNeeded()
    let region = try #require(window.lastScrollRegions.first)
    #expect(region.axis == .horizontal, "the region must carry the ScrollView's own axis")

    platformWindow.simulateInput(.scrollWheel(
        ScrollEvent(position: pt(60, 60), delta: Point(x: Pixels(0), y: Pixels(-19)))))
    #expect(window.stateTable.peek(region.id, as: ScrollState.self)?.offset == 0,
            "a vertical wheel delta must not move a horizontal region")

    platformWindow.simulateInput(wheel(at: pt(60, 60), deltaX: -37))
    #expect(window.stateTable.peek(region.id, as: ScrollState.self)?.offset == 37,
            "delta.x -37 must move a horizontal region's offset by +37")
}

/// Scrolling past either end does not bank an offset the user must unwind
/// before the view moves again.
///
/// **The defect this pins was reported from a running demo as "scrolling
/// stopped working intermittently", and the intermittency was the tell.**
/// `Window.applyScroll` writes `offset -= delta` with no bound, and
/// `ScrollView.resolvedOffset` used to clamp what it *read* while leaving what
/// was *stored* alone. Scrolling hard against an end therefore banked an
/// arbitrarily large excess that was invisible — the view sat at the end
/// looking correct — and every reversing event then spent itself paying that
/// excess down instead of moving anything. Measured on this exact fixture with
/// one frame per event, before the fix: twenty -37 events stored **740**
/// against 80pt of travel, and seventeen of the twenty events that followed in
/// the opposite direction moved the view by nothing at all. How long the dead
/// band lasted was a function of how far past the end the user had already
/// scrolled, which is why it read as intermittent rather than as a stuck view.
///
/// **One frame per event, deliberately**, because that is both the regime the
/// running app is in — `Window` dirties on every wheel event and the display
/// link renders each one — and the regime in which the fix has to hold. The
/// write-back in `resolvedOffset` bounds the stored value to one frame's worth
/// of events, not to zero; driving a whole batch between two frames would
/// measure the looser bound and let a weaker implementation through.
///
/// **Both ends, because the clamp is two terms and each is separately
/// removable.** `min(…)` bounds the bottom and `max(0, …)` bounds the top; the
/// second half of this test is the only thing that distinguishes them, and
/// scrolling up at the top of a list is the more common way to reach the bug.
///
/// **Asserted on the painted thumb as well as on the stored value**, because
/// the stored value alone cannot show the symptom: under the old code the
/// stored number was wrong while everything painted looked right until the
/// direction reversed. The arithmetic is hand-derived rather than recomputed
/// from the implementation's own formula — viewport 120 over content 200 gives
/// a thumb of 120 × (120/200) = 72 and a track of 120 - 72 = 48, so an offset
/// of 51 out of a scrollable 80 puts the thumb's top at (51/80) × 48 = 30.6.
/// The old code would have read a clamped 80 here and parked the thumb at 48,
/// flush with the end of its track.
@Test @MainActor func scrollingPastTheEndDoesNotBankAnOffsetTheUserMustUnwind() throws {
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
    func stored() -> Double? {
        window.stateTable.peek(region.id, as: ScrollState.self)?.offset
    }
    func scroll(_ deltaY: Float) {
        platformWindow.simulateInput(wheel(at: pt(60, 60), deltaY: deltaY))
        window.drawFrameIfNeeded()
    }

    // 5 × 40 of content in a 120pt viewport: 80pt of travel. Six -37 events
    // sum to 222, six times further than the list can actually go.
    for _ in 0..<6 { scroll(-37) }
    #expect(stored() == 80,
            "the stored offset must sit at the 80pt ceiling, not at the 222 the six deltas sum to")

    // One event back the other way must move the view immediately, by its own
    // full amount — not spend itself unwinding a banked 142.
    scroll(29)
    #expect(stored() == 51,
            "80 - 29 = 51; under a read-only clamp this reads 193 and paints as 80")
    let thumb = try #require(window.lastScene.rects.last)
    #expect(abs(Double(thumb.bounds.origin.y) - 30.6) < 0.05,
            "the thumb must have left the end of its track: (51/80) × 48 = 30.6, not the 48 a still-clamped 193 would give")

    // The top end. Five more +29 events reach 0 after the second and would
    // carry the stored value to -94 without the `max(0, …)` term.
    for _ in 0..<5 { scroll(29) }
    #expect(stored() == 0,
            "the stored offset must sit at 0, not at the -94 the five deltas would carry it to")
    scroll(-37)
    #expect(stored() == 37,
            "one -37 from a floored 0 must move the full 37; from a banked -94 it would read -57 and paint as 0")
}
