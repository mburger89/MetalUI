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
@Test(arguments: ScrollAuthorityCoverage.authorities) @MainActor
func aWheelEventInsideARegionScrollsIt(_ authority: LayoutAuthority) throws {
    ScrollAuthorityCoverage.record(#function, authority)
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 120, layoutAuthority: authority) {
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
@Test(arguments: ScrollAuthorityCoverage.authorities) @MainActor
func aWheelEventOutsideEveryRegionScrollsNothing(_ authority: LayoutAuthority) throws {
    ScrollAuthorityCoverage.record(#function, authority)
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 120, layoutAuthority: authority) {
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
@Test(arguments: ScrollAuthorityCoverage.authorities) @MainActor
func theTopmostOverlappingRegionWinsAndTheOtherDoesNotMove(_ authority: LayoutAuthority) throws {
    ScrollAuthorityCoverage.record(#function, authority)
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 120, layoutAuthority: authority) {
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
@Test(arguments: ScrollAuthorityCoverage.authorities) @MainActor
func momentumDeltasScrollLikeDirectOnes(_ authority: LayoutAuthority) throws {
    ScrollAuthorityCoverage.record(#function, authority)
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 120, layoutAuthority: authority) {
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
@Test(arguments: ScrollAuthorityCoverage.authorities) @MainActor
func aNestedRegionClippedOutOfViewByItsParentDoesNotReceiveWheelEvents(_ authority: LayoutAuthority) throws {
    ScrollAuthorityCoverage.record(#function, authority)
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 120, layoutAuthority: authority) {
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
@Test(arguments: ScrollAuthorityCoverage.authorities) @MainActor
func aHorizontalScrollViewMovesOnDeltaXNotDeltaY(_ authority: LayoutAuthority) throws {
    ScrollAuthorityCoverage.record(#function, authority)
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 120, layoutAuthority: authority) {
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
/// `ScrollChrome.resolvedOffset` used to clamp what it *read* while leaving what
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
/// write-back in `ScrollChrome.resolvedOffset` bounds the stored value to one frame's worth
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
@Test(arguments: ScrollAuthorityCoverage.authorities) @MainActor
func scrollingPastTheEndDoesNotBankAnOffsetTheUserMustUnwind(_ authority: LayoutAuthority) throws {
    ScrollAuthorityCoverage.record(#function, authority)
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 120, layoutAuthority: authority) {
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

/// A `Box` whose children all occupy the same cell and stretch to its extent —
/// `display: .stack` with the engine's own `nil` alignment on both axes, which
/// reads as CSS's `stretch`. The public `Stack` element centres instead
/// (`Alignment.center`), which leaves an `auto`-sized `ScrollView` viewport at
/// zero width and gives these fixtures nothing to overlap.
private func stackStyle() -> Style {
    var s = Style()
    s.display = .stack
    return s
}

/// **A `Deferred` scroller takes the wheel from an overlapping sibling it
/// paints over, even though the sibling registered later.**
///
/// This is the composition `PrepaintPass.deferred`'s own doc comment names as
/// the thing that pass exists to prevent: "a tooltip that paints above its
/// siblings while receiving wheel events as though it were beneath them is
/// worse than one that does neither." The hoist was dead code until the
/// registration carried its layer — deleting `pushLayer`/`popLayer` from
/// `PrepaintPass.deferred` passed the whole suite.
///
/// **The deferred scroller is declared FIRST, which is what makes the two
/// orderings disagree.** Prepaint registers in declaration order, so the
/// modal's region is index 0 and the background's is index 1; a walk that
/// picks the last match — the rule for regions within one layer, and the only
/// rule there used to be — hands the event to the background, which is
/// underneath. Measured before the fix, on exactly this fixture: the
/// background's offset moved to 37 and the modal's stayed at 0. Declaring the
/// deferred one second would put registration order and paint order in
/// agreement and the test could not tell the two rules apart.
///
/// The layers are asserted as well as the offsets, because they are the
/// premise: layer 1 over layer 0 is what `Scene.finalize()` sorts by, so
/// asserting them is what says the modal really is the one on top rather than
/// merely the one this test expects to win.
@Test(arguments: ScrollAuthorityCoverage.authorities) @MainActor
func aDeferredScrollViewTakesTheWheelFromAnOverlappingSiblingBeneathIt(_ authority: LayoutAuthority) throws {
    ScrollAuthorityCoverage.record(#function, authority)
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 200, layoutAuthority: authority) {
        Box(style: stackStyle()) {
            Deferred {
                ScrollView(.vertical, elementID: ElementID("modal")) {
                    Box(style: columnStyle()) {
                        Box(style: fixedHeight(150)); Box(style: fixedHeight(150))
                    }
                }
            }
            ScrollView(.vertical, elementID: ElementID("background")) {
                Box(style: columnStyle()) {
                    Box(style: fixedHeight(150)); Box(style: fixedHeight(150))
                }
            }
        }
    }
    window.drawFrameIfNeeded()
    try #require(window.lastScrollRegions.count == 2,
                 "the modal and the background must each register exactly one region")
    let modal = window.lastScrollRegions[0]
    let background = window.lastScrollRegions[1]
    #expect(modal.layer == Frame.rootLayer,
            "the deferred subtree registers at the hoisted layer")
    #expect(background.layer == 0, "its sibling registers at the ordinary one")
    #expect(modal.bounds.size.width == 200 && modal.bounds.size.height == 200
                && background.bounds.size == modal.bounds.size,
            "the two regions genuinely overlap — they are the same 200x200 rect")

    platformWindow.simulateInput(wheel(at: pt(100, 100), deltaY: -37))

    #expect(window.stateTable.peek(modal.id, as: ScrollState.self)?.offset == 37,
            "the hoisted region wins on layer despite having registered FIRST")
    #expect(window.stateTable.peek(background.id, as: ScrollState.self)?.offset == 0,
            "the region it paints over must not also move")
}

/// **Within one layer the last-registered region still wins** — the tie rule
/// `theTopmostOverlappingRegionWinsAndTheOtherDoesNotMove` pins at layer 0,
/// asserted again at the hoisted layer so that adding the layer key did not
/// quietly become the *only* key.
///
/// Both scrollers are wrapped in their own `Deferred`, so both register at
/// `Frame.rootLayer` and the layer comparison cannot separate them; the
/// registration index is all that is left, and the second-declared one must
/// win. An implementation that ordered by layer alone, or that returned the
/// first maximal candidate instead of the last, would scroll `first` here.
@Test(arguments: ScrollAuthorityCoverage.authorities) @MainActor
func withinOneLayerTheLastRegisteredRegionStillWins(_ authority: LayoutAuthority) throws {
    ScrollAuthorityCoverage.record(#function, authority)
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 200, layoutAuthority: authority) {
        Box(style: stackStyle()) {
            Deferred {
                ScrollView(.vertical, elementID: ElementID("first")) {
                    Box(style: columnStyle()) {
                        Box(style: fixedHeight(150)); Box(style: fixedHeight(150))
                    }
                }
            }
            Deferred {
                ScrollView(.vertical, elementID: ElementID("second")) {
                    Box(style: columnStyle()) {
                        Box(style: fixedHeight(150)); Box(style: fixedHeight(150))
                    }
                }
            }
        }
    }
    window.drawFrameIfNeeded()
    try #require(window.lastScrollRegions.count == 2)
    let first = window.lastScrollRegions[0]
    let second = window.lastScrollRegions[1]
    #expect(first.layer == second.layer && first.layer == Frame.rootLayer,
            "both are hoisted, so the layer key cannot separate them")

    platformWindow.simulateInput(wheel(at: pt(100, 100), deltaY: -37))

    #expect(window.stateTable.peek(second.id, as: ScrollState.self)?.offset == 37,
            "the later registration wins the tie, exactly as at layer 0")
    #expect(window.stateTable.peek(first.id, as: ScrollState.self)?.offset == 0)
}

/// A leaf element that records `pass.scrollContext` during `requestLayout`
/// into a shared box, exactly the pattern `FrameClockTests.TimestampRecorder`
/// uses for `pass.timestamp` — a side channel out of a phase that returns
/// nothing else a test could read.
///
/// **A probe LEAF, on both authorities** (plan task 7, stage 3, lane 3, ruling
/// `LR-BI`). It used to register through the public legacy `requestNode`, which
/// is `customElement.requestNode` under the proposal authority — a site stage
/// **6a** owns, so every scenario holding one would have trapped. It now takes
/// `ProbeLeaf`'s shape (`LayoutDifferential.swift`): a native leaf under the
/// proposal authority, a legacy leaf under the legacy one, answering the same
/// `width`×`height` on both.
///
/// **Declared sizes, not a `Style`.** The five call sites' styles carried a pixel
/// length on one axis and `.auto` on the other; here that is one pair of
/// `Double`s, so the two arms cannot drift. The cross axis is stretched by the
/// parent under the legacy authority and is the leaf's own answer under the
/// proposal one; no scenario reads it (`LR-BN`).
private struct ScrollContextRecorder: Element, StyledElement {
    @MainActor final class Seen {
        var values: [ScrollContext?] = []
    }

    var style = Style()
    var decoration = Decoration()
    var elementID: ElementID?
    // `StyledElement`'s fourth requirement. This probe registers no click
    // target — nothing calls `registerHandlers` — so it stays at the empty set.
    var handlers: Handlers = Handlers()
    var width: Double = 0
    var height: Double = 0
    let seen: Seen

    func requestLayout(_ id: GlobalElementID,
                       pass: inout LayoutPass) -> (LayoutNodeID, LayoutNodeID) {
        seen.values.append(pass.scrollContext)
        let w = width, h = height
        let node = pass.lowersToProposal
            ? pass.frame.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: w, height: h)) }
            : pass.requestLeaf(style: style) { _, _ in SizeD(width: w, height: h) }
        return (node, node)
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                  layout: inout LayoutNodeID, pass: inout PrepaintPass) {}

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
               layout: inout LayoutNodeID, prepaint: inout Void, pass: inout PaintPass) {}
}

/// The offset a `ScrollView`'s content sees during `requestLayout` is the
/// CURRENT raw stored offset; the viewport extent it sees is LAST frame's.
///
/// **Frame 1** runs before any scroll and before any `prepaint` has ever
/// stored a `viewportExtent`, so the recorder sees `(0, 0, .vertical)` —
/// asserted so the second frame's `120` is legible as "prepaint wrote this",
/// not as some unrelated default the recorder happened to read.
///
/// **Frame 2** follows one wheel event of `-37` (natural scrolling adds `37`
/// to the stored offset — see `aWheelEventInsideARegionScrollsIt`) with no
/// intervening render. `Window.applyScroll` writes the raw offset and dirties
/// the window; it does not run layout. So this frame's `requestLayout` reads
/// `37` — the scroll from *before* this frame, visible with no lag — paired
/// with `120`, the viewport extent frame 1's `prepaint` stored, which is the
/// only viewport extent that has ever existed to read.
///
/// What a wrong implementation this catches: this fixture's `37` cannot by
/// itself distinguish a raw offset from a clamped one — content is 200pt
/// tall against a 120pt viewport, so the clamp (`0...80`) is inert at 37 and
/// a `ScrollView` that published the CLAMPED value would still read `37`
/// here. **That means this test does NOT prove `scrollContext.offset` is raw
/// rather than clamped — `rawOffsetPublishedDuringRequestLayoutCanExceedTheClampedRange`
/// below is the one that does**, by driving the offset past the clamped
/// ceiling before the frame that reads it. This test's own job is narrower:
/// that the two published fields are wired to the right SOURCES at all (a
/// swapped `offset`/`viewportExtent`, or a `nil` reaching a nested recorder
/// that IS inside the `ScrollView`).
@Test(arguments: ScrollAuthorityCoverage.authorities) @MainActor
func scrollViewPublishesTheCurrentOffsetAndLastFramesViewportDuringRequestLayout(_ authority: LayoutAuthority) throws {
    ScrollAuthorityCoverage.record(#function, authority)
    let device = try #require(MTLCreateSystemDefaultDevice())
    let seen = ScrollContextRecorder.Seen()
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 120, layoutAuthority: authority) {
        ScrollView(.vertical, elementID: ElementID("list")) {
            ScrollContextRecorder(width: 120, height: 200, seen: seen)
        }
    }

    window.drawFrameIfNeeded()
    try #require(seen.values.count == 1, "requestLayout must run exactly once per frame")
    let first = try #require(seen.values[0], "the recorder is inside the ScrollView and must see a context")
    #expect(first.offset == 0,
            "before any scroll, the raw offset is ScrollState's default")
    #expect(first.viewportExtent == 0,
            "before any prepaint has ever run for this element, there is no stored viewport extent yet")
    #expect(first.axis == .vertical)

    platformWindow.simulateInput(wheel(at: pt(60, 60), deltaY: -37))
    window.drawFrameIfNeeded()

    try #require(seen.values.count == 2, "one requestLayout per frame, across two frames")
    let second = try #require(seen.values[1])
    #expect(second.offset == 37,
            "the raw offset is CURRENT — the scroll that happened before this frame is visible with no lag")
    #expect(second.viewportExtent == 120,
            "the viewport extent is ONE FRAME STALE — 120 is what frame 1's prepaint stored, the only value that has ever existed")
    #expect(second.axis == .vertical)
}

/// **The differential `scrollViewPublishesTheCurrentOffsetAndLastFramesViewportDuringRequestLayout`
/// above cannot provide**: an offset published during `requestLayout` that
/// exceeds what a CLAMPED read of the same state would ever give.
///
/// Same fixture as `scrollingPastTheEndDoesNotBankAnOffsetTheUserMustUnwind`
/// — 5 × 40pt rows in a 120pt viewport, 80pt of travel — but driven
/// differently on purpose: five `-37` wheel events fire with **no render
/// between them**. `Window.applyScroll` writes `offset -= delta.y` with no
/// bound and does not run layout, so nothing clamps the five events against
/// each other; only the render that follows does. The raw stored offset
/// reaching frame 2's `requestLayout` is genuinely `5 × 37 = 185` —
/// overscrolled by more than twice the 80pt ceiling — and `ScrollChrome.resolvedOffset`
/// only bounds it to 80 in THAT SAME frame's own `prepaint`, which runs
/// after `requestLayout` has already read and published the unclamped value.
///
/// What a wrong implementation this catches, measured: publishing
/// `min(rawOffset, max(0, lastViewportExtent))` instead of the true raw
/// value — a plausible-looking "bound it by at least the viewport" half-
/// measure — still reddens nothing under
/// `scrollViewPublishesTheCurrentOffsetAndLastFramesViewportDuringRequestLayout`
/// (37 is under 120 either way) but gives 120 here against this test's 185.
@Test(arguments: ScrollAuthorityCoverage.authorities) @MainActor
func rawOffsetPublishedDuringRequestLayoutCanExceedTheClampedRange(_ authority: LayoutAuthority) throws {
    ScrollAuthorityCoverage.record(#function, authority)
    let device = try #require(MTLCreateSystemDefaultDevice())
    let seen = ScrollContextRecorder.Seen()
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 120, layoutAuthority: authority) {
        ScrollView(.vertical, elementID: ElementID("list")) {
            Box(style: columnStyle()) {
                Box(style: fixedHeight(40)); Box(style: fixedHeight(40))
                Box(style: fixedHeight(40)); Box(style: fixedHeight(40))
                Box(style: fixedHeight(40))
                ScrollContextRecorder(seen: seen)
            }
        }
    }
    window.drawFrameIfNeeded()
    let region = try #require(window.lastScrollRegions.first)

    for _ in 0..<5 {
        platformWindow.simulateInput(wheel(at: pt(60, 60), deltaY: -37))
    }
    window.drawFrameIfNeeded()

    try #require(seen.values.count == 2)
    let published = try #require(seen.values[1])
    #expect(published.offset == 185,
            "RAW: five -37 events with no render between them sum to 185, unclamped")

    let stored = window.stateTable.peek(region.id, as: ScrollState.self)?.offset
    #expect(stored == 80,
            "CLAMPED: this same frame's own prepaint bounds the STORED value to the 80pt scrollable range — two visibly different numbers from one frame")
}

/// **Nested `ScrollView`s: the INNERMOST context wins while inside it, and
/// popping restores the OUTER context — not `nil` — for anything declared
/// after the inner one but still inside the outer one.**
///
/// One test, two mutants. A recorder inside `inner` must see `inner`'s own
/// `.horizontal` axis; if `Frame.activeScrollContext` read `.first` off the
/// stack instead of `.last`, it would see `outer`'s `.vertical` there
/// instead — caught by the first `#expect`. A second recorder, declared
/// AFTER `inner` but still inside `outer`'s content, must see `outer`'s
/// `.vertical` again once `inner`'s context is popped; if
/// `withScrollContext`'s `defer` were dropped, `inner`'s `.horizontal` would
/// leak past its own closing brace and reach this recorder instead — caught
/// by the second `#expect`. `aSiblingAfterAScrollViewSeesNoScrollContext`
/// below covers the case where nothing is left to leak INTO (context must be
/// `nil`); this covers the case where something IS (context must revert, not
/// merely disappear), which a bare "must be nil" assertion cannot tell apart
/// from a leak.
@Test(arguments: ScrollAuthorityCoverage.authorities) @MainActor
func nestedScrollViewsInnermostWinsAndPoppingRestoresTheOuterContext(_ authority: LayoutAuthority) throws {
    ScrollAuthorityCoverage.record(#function, authority)
    let device = try #require(MTLCreateSystemDefaultDevice())
    let innerSeen = ScrollContextRecorder.Seen()
    let afterSeen = ScrollContextRecorder.Seen()
    let (window, _) = try makeFakeWindow(device: device, size: 120, layoutAuthority: authority) {
        ScrollView(.vertical, elementID: ElementID("outer")) {
            Box(style: columnStyle()) {
                ScrollView(.horizontal, elementID: ElementID("inner")) {
                    ScrollContextRecorder(width: 150, height: 0, seen: innerSeen)
                }
                ScrollContextRecorder(width: 120, height: 20, seen: afterSeen)
            }
        }
    }

    window.drawFrameIfNeeded()

    try #require(innerSeen.values.count == 1)
    let inner = try #require(innerSeen.values[0],
                             "the recorder inside `inner` must see A context at all")
    #expect(inner.axis == .horizontal, "and it must be the INNERMOST one, `inner`'s own")

    try #require(afterSeen.values.count == 1)
    let after = try #require(afterSeen.values[0],
                             "still inside `outer`'s content — `outer`'s own context must still be active")
    #expect(after.axis == .vertical,
            "declared after `inner`: popping `inner`'s context must restore `outer`'s, neither leak `inner`'s nor clear to nil")
}

/// A sibling declared AFTER a `ScrollView`, not inside it, must see no scroll
/// context at all — the push in `ScrollView.requestLayout` is popped via
/// `defer` before that sibling's own `requestLayout` runs, exactly as a
/// `clipped(to:offsetBy:)` block does not leak its clip past its closing
/// brace.
///
/// **A dropped `defer` in `withScrollContext` leaves the push unbalanced**:
/// the pushed context stays on `Frame.scrollContextStack` after
/// `content.requestGroupLayout` returns, so it reaches whatever the caller
/// builds next — this test's trailing recorder — instead of stopping at the
/// `ScrollView`'s own closing brace. Replacing `withScrollContext` with a
/// bare, unbalanced `frame.pushScrollContext` call reddens exactly this
/// test: the trailing recorder's context reads the `ScrollView`'s own
/// `ScrollContext(offset: 0, viewportExtent: 0, axis: .vertical)` instead of
/// `nil`.
@Test(arguments: ScrollAuthorityCoverage.authorities) @MainActor
func aSiblingAfterAScrollViewSeesNoScrollContext(_ authority: LayoutAuthority) throws {
    ScrollAuthorityCoverage.record(#function, authority)
    let device = try #require(MTLCreateSystemDefaultDevice())
    let seen = ScrollContextRecorder.Seen()
    let (window, _) = try makeFakeWindow(device: device, size: 120, layoutAuthority: authority) {
        Box(style: columnStyle()) {
            ScrollView(.vertical, elementID: ElementID("list")) {
                Box(style: fixedHeight(200))
            }
            ScrollContextRecorder(width: 120, height: 20, seen: seen)
        }
    }

    window.drawFrameIfNeeded()

    try #require(seen.values.count == 1)
    #expect(seen.values[0] == nil,
            "a sibling after the ScrollView, not inside it, must not inherit its scroll context")
}

// MARK: - Task 7: one list

/// A leaf that registers exactly one hitbox at its own bounds and nothing
/// else — the shape a modal scrim has.
///
/// **This said "a shape no PRODUCTION element has yet (Task 8's `onClick` is
/// the first that will register one)", and both halves are false now.**
/// `StyledElement.onClick(_:)` shipped, so `Box`, `Column`, `Row`, `Stack`,
/// `Text` and `List` each register exactly this shape — one opaque,
/// non-scrolling hitbox at their own bounds — whenever they were given a
/// handler, and nothing at all when they were not. A reader auditing which
/// production elements register non-scrolling hitboxes should look at
/// `Frame.registerHandlers`' call sites, not here.
///
/// The probe stays anyway, and not out of inertia: it registers a hitbox with
/// **no handler attached**, which no production element does, so the wheel
/// tests below stay about routing and cannot be reddened by a change to click
/// dispatch.
///
/// `opaque` is a stored property rather than a constant `true` so Step 5's
/// mutation is expressible as a fixture change rather than as an edit to the
/// implementation: flipping it to `false` must make the wheel fall through to
/// the scroller underneath again.
///
/// **A probe LEAF, on both authorities** (plan task 7, stage 3, lane 3, ruling
/// `LR-BI`), for `ScrollContextRecorder`'s reason: `requestNode` is
/// `customElement.requestNode` under the proposal authority. Both of its call
/// sites declared both axes in pixels, so the two arms answer the same
/// `width`×`height` and the scrim covers the same 200×200 under either engine —
/// measured before the re-spelling, not assumed.
private struct HitboxProbe: Element, StyledElement {
    var style = Style()
    var decoration = Decoration()
    var elementID: ElementID?
    // `StyledElement`'s fourth requirement. This probe registers no click
    // target — nothing calls `registerHandlers` — so it stays at the empty set.
    var handlers: Handlers = Handlers()
    var opaque: Bool = true
    var width: Double = 0
    var height: Double = 0

    func requestLayout(_ id: GlobalElementID,
                       pass: inout LayoutPass) -> (LayoutNodeID, LayoutNodeID) {
        let w = width, h = height
        let node = pass.lowersToProposal
            ? pass.frame.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: w, height: h)) }
            : pass.requestLeaf(style: style) { _, _ in SizeD(width: w, height: h) }
        return (node, node)
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                  layout: inout LayoutNodeID, pass: inout PrepaintPass) {
        pass.insertHitbox(bounds, id: id, opaque: opaque)
    }

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
               layout: inout LayoutNodeID, prepaint: inout Void, pass: inout PaintPass) {}
}

/// **Both** axes declared in pixels, and no `flexDirection` — deliberately not
/// `fixedHeight`, whose width is `.auto`.
///
/// The scrim fixture depends on the width being literal: a scrim that
/// shrink-wrapped instead of measuring 200 would not cover the `(100, 100)`
/// the wheel event is sent to, and the test would pass for the wrong reason.
private func fixedSize(_ w: Float, _ h: Float) -> Style {
    var s = Style()
    s.size = Size(width: .length(.pixels(Pixels(w))), height: .length(.pixels(Pixels(h))))
    return s
}

/// **A `Deferred` scrim swallows a wheel event that reaches it, instead of
/// letting it scroll the list beneath.**
///
/// This is the limitation three milestones recorded and this task closes.
/// Before the fold, `Frame.scrollRegions` was the only hitbox list this
/// framework had, so a non-scrolling `Deferred` registered nothing at all and
/// could not be seen by wheel routing: CLAUDE.md's failure 4 of the
/// absolute-positioning entry says in as many words that the list DOES move
/// under the modal and that "nothing short of §8.1's general hitbox list will
/// change that". This is that list.
///
/// **The scrim is declared FIRST, which is what makes the two orderings
/// disagree** — the same construction
/// `aDeferredScrollViewTakesTheWheelFromAnOverlappingSiblingBeneathIt` uses.
/// Prepaint registers in declaration order, so the scrim is index 0 and the
/// scroller index 1; only the layer key can put the scrim on top.
///
/// **Both halves are asserted, and they fail differently.** The list's offset
/// is the half that was reported from a running demo. The claimed return value
/// is the other half of "swallow": an event that landed on an opaque element
/// and produced no scroll must not then be re-offered to the window's fallback
/// handler as an unhandled one.
@Test(arguments: ScrollAuthorityCoverage.authorities) @MainActor
func anOpaqueDeferredScrimSwallowsAWheelEventInsteadOfScrollingTheListBeneath(_ authority: LayoutAuthority) throws {
    ScrollAuthorityCoverage.record(#function, authority)
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 200, layoutAuthority: authority) {
        Box(style: stackStyle()) {
            Deferred {
                HitboxProbe(elementID: ElementID("scrim"), width: 200, height: 200)
            }
            ScrollView(.vertical, elementID: ElementID("list")) {
                Box(style: columnStyle()) {
                    Box(style: fixedHeight(150)); Box(style: fixedHeight(150))
                }
            }
        }
    }
    window.drawFrameIfNeeded()
    let list = try #require(window.lastScrollRegions.first,
                            "the ScrollView must still register a scrolling region")

    let claimed = platformWindow.simulateInput(wheel(at: pt(100, 100), deltaY: -37))

    #expect(window.stateTable.peek(list.id, as: ScrollState.self)?.offset == 0,
            "the scrim is opaque and on top: the list underneath must not move")
    #expect(claimed, "and the event is consumed rather than offered on to the window's own handler")
}

/// **The differential for the test above**: the identical fixture with a
/// NON-opaque scrim lets the wheel through, and the list scrolls exactly as
/// it did before this task.
///
/// Without this, `anOpaqueDeferredScrimSwallows…` would also pass under an
/// implementation that had simply stopped routing wheel events altogether —
/// "the list did not move" is what a broken `applyScroll` produces too. It is
/// also Step 5's mutation, kept as a test rather than run once and reported:
/// `opaque` is the single field that decides between the two, and design spec
/// §3.2's "a non-opaque hitbox does not stop the walk" is exactly the rule
/// being checked.
@Test(arguments: ScrollAuthorityCoverage.authorities) @MainActor
func aNonOpaqueDeferredScrimLetsTheWheelReachTheListBeneath(_ authority: LayoutAuthority) throws {
    ScrollAuthorityCoverage.record(#function, authority)
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 200, layoutAuthority: authority) {
        Box(style: stackStyle()) {
            Deferred {
                HitboxProbe(elementID: ElementID("scrim"), opaque: false,
                            width: 200, height: 200)
            }
            ScrollView(.vertical, elementID: ElementID("list")) {
                Box(style: columnStyle()) {
                    Box(style: fixedHeight(150)); Box(style: fixedHeight(150))
                }
            }
        }
    }
    window.drawFrameIfNeeded()
    let list = try #require(window.lastScrollRegions.first)

    let claimed = platformWindow.simulateInput(wheel(at: pt(100, 100), deltaY: -37))

    #expect(window.stateTable.peek(list.id, as: ScrollState.self)?.offset == 37,
            "a transparent hitbox does not stop the walk — the list takes the wheel")
    #expect(claimed, "and the scroller claims it, exactly as it did before the fold")
}

/// `fixedHeight`, plus the `min-height: 0` that keeps CSS Sizing §4.5's
/// automatic minimum from floating the box back up to its content's
/// min-content height.
///
/// **Measured, not decorative.** Without it this fixture's 100pt box is
/// floored at the 150pt its nested `ScrollView`'s content node reports — the
/// half of §4.5 this engine DOES implement (CLAUDE.md divergence 5), and the
/// same reason `Sources/MetalUIDemoContent/DemoContent.swift` writes `.minHeight(Pixels(0))`
/// around its own scroll list. The first draft of the test below had `outer`
/// parked at 74 instead of its intended 50pt ceiling for exactly this reason.
private func boundedHeight(_ h: Float) -> Style {
    var s = fixedHeight(h)
    s.minSize.height = .length(.pixels(Pixels(0)))
    return s
}

/// **A nested `ScrollView` inside an ALREADY-SCROLLED one receives wheel
/// events where it PAINTS, not where the engine stored it** — ruling IN-F, the
/// live routing defect Task 5's review found and this task owns.
///
/// (This citation read `C1` until the end of the milestone. `C1` was a review
/// *concern* id in the execution ledger, never a ruling — the decision it names
/// is `IN-F` in `docs/superpowers/2026-08-29-input-decisions.md`, and a reader
/// grepping that doc for `C1` finds nothing. Five sites carried the dangling
/// id, and one of them wrapped `ruling` and `C1` onto separate comment lines,
/// so a plain `grep -n "ruling C1"` finds only four — CLAUDE.md's
/// sweep-case-insensitively rule, in a new shape.)
///
/// `registerScrollRegion` recorded its bounds without the active offset while
/// `insertHitbox` recorded them with it, and folding the two lists forces a
/// choice. `insertHitbox`'s translating convention is the correct one, and the
/// only production configuration it moves is the one that is wrong today.
///
/// **This fixture is the reason the choice is not a coin flip.** Task 5's
/// reviewer measured that adding `+ activeOffset` to `registerScrollRegion`
/// reddened NOTHING in a 631-test suite — every routing fixture in this file
/// either has no ancestor scroller or has one sitting at offset 0, so the
/// translation is provably inert in all of them. That is ruling MP-J's shape:
/// the fixture cannot express the defect, so the assertion never gets a
/// chance.
///
/// The geometry, hand-derived and then confirmed by the registered rect this
/// test asserts directly: a 200pt viewport over 250pt of content (a 150pt
/// filler above a 100pt box holding `inner`) leaves 50pt of travel. Two -37
/// events with a render after each drive `outer` to the 50pt ceiling, so
/// `inner` — stored at y 150 by the engine — PAINTS at y 100. Its registered
/// region must therefore be (0, 100) 200x100. Under the untranslated
/// convention it is recorded at (0, 150) 200x50 instead: 50pt low and half the
/// height, because the ancestor clip then cuts it rather than the offset
/// moving it.
///
/// **(100, 120) is the point that tells the two apart** — inside the painted
/// rect, outside the untranslated one. The seeding events fire at (100, 20)
/// instead, which is above `inner` under either convention and at every offset
/// the seeding passes through, so they can only reach `outer`.
///
/// Asserted on both offsets, not just `inner`'s: under the defect the event
/// does not vanish, it goes to `outer`, and "outer did not also move" is what
/// says the event was routed rather than dropped.
@Test(arguments: ScrollAuthorityCoverage.authorities) @MainActor
func aNestedScrollViewInsideAScrolledOneReceivesTheWheelWhereItPaints(_ authority: LayoutAuthority) throws {
    ScrollAuthorityCoverage.record(#function, authority)
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 200, layoutAuthority: authority) {
        ScrollView(.vertical, elementID: ElementID("outer")) {
            Box(style: columnStyle()) {
                Box(style: fixedHeight(150))
                Box(style: boundedHeight(100)) {
                    ScrollView(.vertical, elementID: ElementID("inner")) {
                        Box(style: columnStyle()) {
                            Box(style: fixedHeight(50)); Box(style: fixedHeight(50))
                            Box(style: fixedHeight(50))
                        }
                    }
                }
            }
        }
    }
    window.drawFrameIfNeeded()
    try #require(window.lastScrollRegions.count == 2,
                 "outer and inner must each register exactly one region")
    let outerID = window.lastScrollRegions[0].id
    let innerID = window.lastScrollRegions[1].id

    func stored(_ id: GlobalElementID) -> Double? {
        window.stateTable.peek(id, as: ScrollState.self)?.offset
    }

    // Drive `outer` to its 50pt ceiling. (100, 20) is above `inner` at every
    // offset this passes through, under either convention.
    for _ in 0..<2 {
        platformWindow.simulateInput(wheel(at: pt(100, 20), deltaY: -37))
        window.drawFrameIfNeeded()
    }
    try #require(stored(outerID) == 50, "outer must be parked at its 50pt ceiling")

    // Re-derived, and re-`require`d rather than re-indexed: `lastScrollRegions`
    // is a computed view of the list the two renders above rebuilt from
    // scratch, so the count asserted before them says nothing about this one.
    // This repo's rule is one word wide — any count a later line indexes on is
    // `try #require`, after a wrong implementation once truncated ~200 tests
    // with `Index out of range` and no summary line (taxonomy shape 13).
    let scrolled = window.lastScrollRegions
    try #require(scrolled.count == 2, "both regions must survive the two renders")
    #expect(scrolled[1].bounds
                == Bounds(origin: pt(0, 100),
                          size: Size(width: Pixels(200), height: Pixels(100))),
            "inner's region is recorded where it PAINTS, translated by the ancestor scroll")

    platformWindow.simulateInput(wheel(at: pt(100, 120), deltaY: -37))

    #expect(stored(innerID) == 37,
            "a point inside inner's PAINTED rect must scroll inner")
    #expect(stored(outerID) == 50,
            "and outer must not also move — under the untranslated convention it takes this event instead")
}
