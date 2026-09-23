import Testing
import Metal
import MetalUICore
import MetalUILayout
import MetalUIRender
@testable import MetalUI

// Task 9: the fading overlay scroll indicator. Five tests, matching the
// task-9 brief's stubs one for one.
//
// **This file is why Task 1 exists.** Before the draw list, `Renderer.encode`
// drew every rect and then every glyph regardless of emission order, so an
// overlay indicator over a list of text was not expressible at all —
// `theIndicatorIsTheLastPrimitiveInTheScene` is the payoff, and it asserts the
// indicator is genuinely last in the DRAW LIST (`Scene.drawList`, built by
// `finalize()`), not merely that a rect exists somewhere in the scene.

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

private func fixedWidth(_ w: Float, _ h: Float) -> Style {
    var s = Style()
    s.flexDirection = .row
    s.size = Size(width: .length(.pixels(Pixels(w))), height: .length(.pixels(Pixels(h))))
    return s
}

// **Why the single-child fixtures below declare BOTH axes** (plan task 7, stage
// 3, lane 3, ruling `LR-BN`). A `ScrollView`'s only child used to declare the
// scrolling axis and leave the cross axis `.auto`, and the legacy engine
// stretched it: `flexShrink: 0` content in a viewport whose own cross size came
// from the definite window. The kernel viewport's cross answer is its CONTENT's
// (`CN-M`), and a single child is exempt from the stretch item frame (stage 2's
// elision, `LR-AC`), so the same fixture measures a 0-wide viewport under the
// proposal authority, centred at the window's midpoint — which is stage 2's
// ruled divergence, not this lane's subject. Declaring the cross axis removes
// that degree of freedom and leaves the scenario (the thumb's geometry, its
// ramp, its clip) the thing being compared. **It moves no legacy number**: the
// stretch already produced exactly these values, which is why every literal
// below is unchanged.

private let listID = ElementID("list")
private let rootID = GlobalElementID.child(of: nil, at: 0, name: listID)

/// Runs `element` through all three phases by hand — `requestLayout`,
/// `computeRootLayout`, `prepaint`, `paint` — exactly what `Frame.render`
/// does, except it hands back the element's own `LayoutState` afterward.
/// `Frame.render` discards it, so a caller outside the element has no way
/// back to `ScrollView.Layout.contentNode` — the one node several tests below
/// need to compute the SAME geometry the implementation is pinned to,
/// independently of it.
@MainActor
private func fullyRendered<E: Element>(_ element: inout E, width: Float, height: Float,
                                       stateTable: StateTable = StateTable(),
                                       timestamp: Double = 0,
                                       authority: LayoutAuthority = .legacy) -> (Frame, E.LayoutState) {
    // Plan task 7, stage 3, lane 3 (`LR-BI`): `reportsUnlowerableFields` is left
    // OFF on purpose, so this helper fails the way a production frame does — a
    // site with no lowering traps rather than reporting. Every fixture below was
    // measured to report nothing before the parameterisation (record §9).
    let frame = Frame(contentSize: Size(width: Pixels(width), height: Pixels(height)),
                      scaleFactor: 1, stateTable: stateTable, timestamp: timestamp,
                      layoutAuthority: authority)
    let id = GlobalElementID.child(of: nil, at: 0, name: element.elementID)
    var layoutPass = LayoutPass(frame: frame)
    let (root, layoutState) = element.requestLayout(id, pass: &layoutPass)
    var state = layoutState
    frame.computeRootLayout(root: root)
    let rootBounds = frame.bounds(of: root)
    var prepaintPass = PrepaintPass(frame: frame)
    var prepaintState = element.prepaint(id, bounds: rootBounds, layout: &state, pass: &prepaintPass)
    var paintPass = PaintPass(frame: frame)
    element.paint(id, bounds: rootBounds, layout: &state, prepaint: &prepaintState, pass: &paintPass)
    return (frame, state)
}

/// A `StateTable` with `rootID`'s `ScrollState` pre-populated, so a test can
/// pin the offset and the last-scroll instant before painting rather than
/// only reaching them through a simulated wheel event.
@MainActor
private func scrolledState(offset: Double, lastScrollTime: Double) -> StateTable {
    let table = StateTable()
    table.withState(rootID, initial: ScrollState()) {
        $0.offset = offset
        $0.lastScrollTime = lastScrollTime
    }
    return table
}

// MARK: - 1. The composition Task 1 was built for

/// The indicator is emitted after the content, so the draw list puts it last.
///
/// **This is the composition the draw list was built for.** Before it, a rect
/// emitted after glyphs still drew beneath them, so an overlay indicator over a
/// list of text was not expressible at all.
///
/// Two claims, because either alone is satisfiable by a wrong implementation:
/// the ORDER (last run in the draw list is `.rect`) and the POSITION (the
/// indicator's bounds are the viewport-space thumb formula, not shifted by the
/// content's scroll offset). The second is what actually distinguishes
/// "painted after the clipped block" from "painted as the last statement
/// INSIDE it" — both emit the rect last in sequence, since nothing about the
/// clip stack reorders emission, but only the wrong placement inherits the
/// block's `-offset` translation and moves the thumb by exactly the scrolled
/// amount, which is required mutation 1 (see the task report).
@Test(arguments: AuthorityCoverage.authorities) @MainActor
func theIndicatorIsTheLastPrimitiveInTheScene(_ authority: LayoutAuthority) throws {
    AuthorityCoverage.record(#function, authority)
    let table = scrolledState(offset: 20, lastScrollTime: 0)
    var view = ScrollView(.vertical, elementID: listID) {
        Column {
            Text("Row one"); Text("Row two"); Text("Row three"); Text("Row four")
            Text("Row five"); Text("Row six"); Text("Row seven"); Text("Row eight")
        }
    }
    let (frame, layout) = fullyRendered(&view, width: 120, height: 100, stateTable: table,
                                        authority: authority)
    let scene = frame.finalizedScene()

    try #require(!scene.glyphs.isEmpty,
                "the text must actually overflow and emit glyphs, or this proves nothing about rects over glyphs")
    let runs = scene.drawList
    try #require(runs.count == 2, "expected one glyph run then one rect run for the indicator, got \(runs.count)")
    #expect(runs[0].kind == .glyph, "the content paints first")
    #expect(runs[1].kind == .rect, "the indicator must be the LAST primitive in the draw list")
    #expect(runs[1].count == 1)

    let viewportHeight = Double(frame.bounds(of: layout.node).size.height.value)
    let contentHeight = Double(frame.bounds(of: layout.contentNode).size.height.value)
    let scrollable = max(0, contentHeight - viewportHeight)
    try #require(scrollable > 20, "the fixture must overflow by more than the pinned offset")
    let thumb = max(20, viewportHeight * (viewportHeight / contentHeight))
    let expectedTravel = (20 / scrollable) * (viewportHeight - thumb)
    let expectedY = Double(frame.bounds(of: layout.node).origin.y.value) + expectedTravel

    let rect = try #require(scene.rects.last)
    #expect(abs(Double(rect.bounds.origin.y) - expectedY) < 0.05,
            "the indicator's y must be the viewport-space thumb position; painting it inside the clipped block would additionally shift it by the scroll offset (-20), which this would catch")
}

// MARK: - 2. Nothing to scroll, nothing drawn

/// No indicator when there is nothing to scroll.
///
/// What a wrong implementation this catches: dropping (or inverting) the
/// `guard scrollable > 0 else { return }` — with content no taller than the
/// viewport, `scrollable` is 0 and `travel`'s division by it would produce a
/// NaN rect that still gets inserted into the scene rather than nothing at
/// all.
///
/// **The scroll state is explicit and fresh (`age == 0`)** so that
/// `guard scrollable > 0` is the only guard that can return here. Rendered
/// against a default `ScrollState` — `lastScrollTime == -.infinity`, never
/// scrolled — `guard alpha > 0` would return first and this would pass
/// with the scrollable guard deleted.
@Test(arguments: AuthorityCoverage.authorities) @MainActor
func contentThatFitsDrawsNoIndicator(_ authority: LayoutAuthority) throws {
    AuthorityCoverage.record(#function, authority)
    var view = ScrollView(.vertical, elementID: listID) {
        Box(style: fixedSize(120, 40))
    }
    let (frame, _) = fullyRendered(&view, width: 120, height: 100,
                                   stateTable: scrolledState(offset: 0, lastScrollTime: 0),
                                   authority: authority)
    #expect(frame.scene.rects.isEmpty,
            "content shorter than the viewport has nothing to scroll, so no thumb and no draw call for one")
}

// MARK: - 3. Proportional, floored — at ratios where the two differ

/// The thumb is proportional to the viewport/content ratio and floored so it
/// never becomes an invisible sliver on a very long list.
///
/// Two fixtures, chosen so the proportional answer and the 20pt floor give
/// DIFFERENT numbers in each — a fixture where they coincide could not tell a
/// working floor from a working proportion (or the reverse).
@Test(arguments: AuthorityCoverage.authorities) @MainActor
func theThumbIsProportionalAndFlooredAtTwentyPoints(_ authority: LayoutAuthority) throws {
    AuthorityCoverage.record(#function, authority)
    // viewport 100, content 200 → 100 * (100/200) = 50, well clear of the
    // floor: this isolates the PROPORTION formula.
    do {
        var view = ScrollView(.vertical, elementID: listID) {
            Box(style: fixedSize(120, 200))
        }
        // A fresh scroll (age 0): a never-scrolled default state paints no
        // thumb at all, so there would be nothing here to measure.
        let (frame, _) = fullyRendered(&view, width: 120, height: 100,
                                       stateTable: scrolledState(offset: 0, lastScrollTime: 0),
                                       authority: authority)
        let rect = try #require(frame.scene.rects.first)
        #expect(abs(Double(rect.bounds.size.height) - 50) < 0.05,
                "100 * (100/200) = 50 — a bare proportional size, not the floor")
        // The CROSS axis, which nothing else in this file reads: 3pt wide,
        // inset 2pt from the viewport's trailing edge (origin.x + width - 5).
        // Catches a transposed `width:`/`height:` in `ScrollChrome.indicatorBounds`'s
        // `.vertical` branch (the thumb would come back 50 wide and 3 tall)
        // and a wrong inset (a thumb hard against the edge, or off it).
        #expect(abs(Double(rect.bounds.size.width) - 3) < 0.001,
                "the thumb is 3pt on its cross axis")
        #expect(abs(Double(rect.bounds.origin.x) - (120 - 5)) < 0.001,
                "the thumb sits 5pt in from the 120pt-wide viewport's left origin: 2pt inset plus its own 3pt width")
    }

    // viewport 100, content 1000 → 100 * (100/1000) = 10, an invisible sliver:
    // this isolates the FLOOR, which must win over the smaller proportion.
    do {
        var view = ScrollView(.vertical, elementID: listID) {
            Box(style: fixedSize(120, 1000))
        }
        // A fresh scroll (age 0): a never-scrolled default state paints no
        // thumb at all, so there would be nothing here to measure.
        let (frame, _) = fullyRendered(&view, width: 120, height: 100,
                                       stateTable: scrolledState(offset: 0, lastScrollTime: 0),
                                       authority: authority)
        let rect = try #require(frame.scene.rects.first)
        #expect(abs(Double(rect.bounds.size.height) - 20) < 0.05,
                "100 * (100/1000) = 10 must be floored to 20, not left as a 10pt sliver")
    }
}

// MARK: - 4. Exactly at the end of the track

/// The thumb reaches the bottom of its track exactly at the maximum offset —
/// an off-by-one here leaves a gap that looks like the list has more content.
///
/// Asserted at both ends, exactly rather than "close": at offset 0 the thumb
/// starts flush with the top of the track, and at the maximum offset (100,
/// for this fixture's 100pt of scrollable range) its FAR edge lands flush
/// with the bottom — not merely "large" or "near the end".
@Test(arguments: AuthorityCoverage.authorities) @MainActor
func theThumbReachesTheEndOfItsTrackAtMaximumOffset(_ authority: LayoutAuthority) throws {
    AuthorityCoverage.record(#function, authority)
    // viewport 100, content 200 → scrollable 100, thumb 50: clear of the
    // 20pt floor, so this isolates the position formula from it.
    do {
        var view = ScrollView(.vertical, elementID: listID) {
            Box(style: fixedSize(120, 200))
        }
        let (frame, layout) = fullyRendered(&view, width: 120, height: 100,
                                            stateTable: scrolledState(offset: 100, lastScrollTime: 0),
                                            authority: authority)
        let rect = try #require(frame.scene.rects.first)
        let trackBottom = Double(frame.bounds(of: layout.node).origin.y.value)
                         + Double(frame.bounds(of: layout.node).size.height.value)
        let thumbBottom = Double(rect.bounds.origin.y) + Double(rect.bounds.size.height)
        #expect(abs(thumbBottom - trackBottom) < 0.01,
                "at the maximum offset the thumb's far edge must land EXACTLY at the end of the track")
    }

    do {
        var view = ScrollView(.vertical, elementID: listID) {
            Box(style: fixedSize(120, 200))
        }
        let (frame, layout) = fullyRendered(&view, width: 120, height: 100,
                                            stateTable: scrolledState(offset: 0, lastScrollTime: 0),
                                       authority: authority)
        let rect = try #require(frame.scene.rects.first)
        #expect(abs(Double(rect.bounds.origin.y) - Double(frame.bounds(of: layout.node).origin.y.value)) < 0.01,
                "at zero offset the thumb starts EXACTLY at the top of the track")
    }
}

// MARK: - 5. Fades, and stops asking for frames once it has

private func pt(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: Pixels(x), y: Pixels(y)) }

private func wheel(at position: Point<Pixels>, deltaY: Float) -> InputEvent {
    .scrollWheel(ScrollEvent(position: position, delta: Point(x: Pixels(0), y: Pixels(deltaY)),
                             isMomentum: false))
}

/// While fading, the ScrollView asks for another frame; once faded, it stops.
///
/// The second half is what keeps an idle window idle — spec §4.4's "no frames
/// built and display link paused while idle" is an M4 exit criterion and this
/// must not break it early.
///
/// Driven through a real `Window`, not a bare `Frame`, because the idle
/// guarantee is a property of `Window.drawFrameIfNeeded` honouring
/// `frame.wantsAnotherFrame` (Task 8) — a bare `Frame` has no "stays idle"
/// concept to fail.
@Test(arguments: AuthorityCoverage.authorities) @MainActor
func theIndicatorRequestsFramesWhileFadingAndStopsWhenDone(_ authority: LayoutAuthority) throws {
    AuthorityCoverage.record(#function, authority)
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 120, startsDisplayLink: true,
                                               layoutAuthority: authority) {
        ScrollView(.vertical, elementID: listID) {
            Box(style: columnStyle()) {
                Box(style: fixedHeight(40)); Box(style: fixedHeight(40))
                Box(style: fixedHeight(40)); Box(style: fixedHeight(40))
                Box(style: fixedHeight(40))
            }
        }
    }

    // A baseline tick far from zero. Nothing has scrolled yet — ScrollState's
    // default `lastScrollTime` is `-.infinity` — so `age` here is infinite and
    // the window must already be clean: a never-scrolled but scrollABLE list
    // must not paint an indicator or request anything, either. This tick is
    // NOT the window's first frame's instant; that case (timestamp 0, where
    // the old default of 0 gave `age == 0`) is
    // `aNeverScrolledScrollViewPaintsNoIndicatorOnTheWindowsPreTickFirstFrame`.
    platformWindow.simulateTick(timestamp: 100)
    #expect(!window.needsRedraw, "an idle, never-scrolled ScrollView must not keep the window dirty")

    // This stamps lastScrollTime from the window's CURRENT lastTick (100).
    platformWindow.simulateInput(wheel(at: pt(60, 60), deltaY: -20))
    #expect(window.needsRedraw, "the scroll itself must dirty the window")

    // age 0.2 < 0.6: fully opaque, must keep requesting.
    platformWindow.simulateTick(timestamp: 100.2)
    #expect(window.needsRedraw, "age 0.2 is inside the fully-opaque window and must request another frame")

    // age 0.8: inside the 0.6...1.0 ramp, still visible (alpha > 0), must
    // still be requesting.
    platformWindow.simulateTick(timestamp: 100.8)
    #expect(window.needsRedraw, "age 0.8 is inside the fade ramp and must still request another frame")

    // age 1.1: fully faded. This render must be the LAST one this scroll
    // causes — the idle-guarantee half.
    let framesBeforeFadeCompletes = window.framesDrawn
    platformWindow.simulateTick(timestamp: 101.1)
    #expect(window.framesDrawn == framesBeforeFadeCompletes + 1,
            "this tick was still dirty going in (from the 100.8 request) and must have drawn once")
    #expect(!window.needsRedraw,
            "age 1.1 > 1.0: fully faded, and this render must not have asked for another frame")
    // Not just invisible — ABSENT. A fully transparent thumb that still
    // reached `pass.fill` would still cost a draw call every idle frame
    // thereafter, the same waste `anElementWithNoBackgroundEmitsNoPrimitiveAtAll`
    // (ThemeTests) guards for a `Box`. Found by an exploratory mutation that
    // deleted `guard alpha > 0 else { return }` (not one of the three required
    // mutations): the `if age < 1.0` line alone still happens to suppress the
    // *frame request* at this timestamp, so neither `needsRedraw` assertion
    // above would have caught a fully faded indicator that kept drawing an
    // invisible rect — only this one does.
    #expect(window.lastScene.rects.isEmpty,
            "a fully faded indicator must emit no primitive at all, not merely a transparent one")

    // And it actually STAYS idle — a further tick with nothing else going on
    // draws nothing more, which is the only way to tell "stopped requesting"
    // from "requested once more and happened to go quiet after".
    let framesAfterFade = window.framesDrawn
    platformWindow.simulateTick(timestamp: 105)
    #expect(window.framesDrawn == framesAfterFade,
            "idle stays idle: nothing dirtied the window, so no further frame may draw")
}

// MARK: - 5b. A scroll that follows a display-link pause still shows the indicator

/// A wheel event whose own timestamp — the thing `Window.applyScroll` now
/// stamps `ScrollState.lastScrollTime` from — is far ahead of the display
/// link's last delivered tick.
///
/// `FakePlatformWindow.simulateInput` only substitutes `currentTime` for a
/// `.scrollWheel` event that leaves `timestamp` at `ScrollEvent`'s default
/// (`0`); passing one explicitly here is what drives the two clocks apart.
private func wheel(at position: Point<Pixels>, deltaY: Float, timestamp: Double) -> InputEvent {
    .scrollWheel(ScrollEvent(position: position, delta: Point(x: Pixels(0), y: Pixels(deltaY)),
                             isMomentum: false, timestamp: timestamp))
}

/// A scroll that arrives after the display link has gone idle and paused
/// still shows the indicator — the defect this task fixes.
///
/// **Mechanism reproduced end to end.** `Window.applyScroll` used to stamp
/// `ScrollState.lastScrollTime` from `Window.lastTick`, the most recent
/// display-link tick — but the link pauses while the window is clean (spec
/// §4.4), so `lastTick` is frozen at whatever instant the last real tick
/// delivered. A wheel event arriving after a longer idle gets stamped with
/// that stale instant, and the next frame's `age = timestamp - lastScrollTime`
/// is then large enough that `ScrollChrome.paintIndicator`'s `guard alpha > 0 else {
/// return }` suppresses the indicator outright — content scrolls, nothing
/// paints to show it.
///
/// **The idle gap (6) and the fade duration (1.0) are deliberately different
/// numbers**, per the practices doc's fixture-hygiene rule: a fixture where
/// they coincided could not distinguish "the indicator appeared because `age`
/// happened to be small" from "the indicator appeared because the stamp was
/// fresh" — the two claims this test exists to tell apart.
///
/// The tick that renders the post-scroll frame lands 0.05s after the SCROLL
/// EVENT's own timestamp (11), not after the paused tick (5) — the realistic
/// shape of "the wheel event dirties the window, which un-pauses the display
/// link, which ticks again almost immediately." Under the reverted code this
/// still reads `age = 11.05 - 5 = 6.05` (suppressed); under the fix it reads
/// `age = 11.05 - 11 = 0.05` (visible).
@Test(arguments: AuthorityCoverage.authorities) @MainActor
func aScrollFollowingAnIdleThatPausedTheDisplayLinkStillShowsTheIndicator(_ authority: LayoutAuthority) throws {
    AuthorityCoverage.record(#function, authority)
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 120, startsDisplayLink: true,
                                               layoutAuthority: authority) {
        ScrollView(.vertical, elementID: listID) {
            Box(style: columnStyle()) {
                Box(style: fixedHeight(40)); Box(style: fixedHeight(40))
                Box(style: fixedHeight(40)); Box(style: fixedHeight(40))
                Box(style: fixedHeight(40))
            }
        }
    }

    // First real tick: renders once, nothing scrolled, and the window goes
    // clean — nothing requests another frame.
    platformWindow.simulateTick(timestamp: 100)
    #expect(!window.needsRedraw, "an idle, never-scrolled ScrollView must not keep the window dirty")

    // A second tick, 5 seconds later, with the window still clean: this is
    // the tick on which `drawFrameIfNeeded` finds `needsRedraw` already
    // false and pauses the link — the mechanism's "the link pauses while the
    // window goes clean" made concrete rather than assumed.
    let framesBeforeIdle = window.framesDrawn
    platformWindow.simulateTick(timestamp: 105)
    #expect(platformWindow.pauseCalls.last == true, "the display link must be paused while idle")
    #expect(window.framesDrawn == framesBeforeIdle, "a paused-and-clean tick draws no frame")

    // Real time keeps passing — nothing ticks the (paused) link — and then a
    // wheel event arrives, 6 seconds after the link's last delivered tick and
    // well past the fade's ~1s window. Its OWN timestamp (11) is what must
    // reach `ScrollState.lastScrollTime`, not the stale tick (5).
    platformWindow.simulateInput(wheel(at: pt(60, 60), deltaY: -20, timestamp: 111))
    #expect(window.needsRedraw, "the scroll itself must dirty the window and resume the link")

    // The resumed link ticks again almost immediately — close to the EVENT's
    // own timestamp, far from the stale one.
    platformWindow.simulateTick(timestamp: 111.05)

    let rect = try #require(window.lastScene.rects.first,
                            "the indicator must be emitted for a scroll that follows an idle longer than the fade duration")
    #expect(rect.background.a > 0, "and it must be visible, not a fully transparent no-op rect")
}

/// The idle guarantee is not a casualty of this fix: after waking from a
/// paused link on a fresh event timestamp, the indicator still fades on
/// schedule and the window still returns to idle — spec §4.4's "no frames
/// built and display link paused while idle" holds using the event's own
/// clock exactly as it held using the display link's.
///
/// Continues from the same scenario as the test above rather than asserting
/// termination in isolation, because the failure mode this guards against is
/// specific to THIS fix: a stamp sourced from the wrong clock (say, a wall
/// read that keeps advancing with "now") would make `age` never grow and the
/// fade would never complete, silently breaking the idle guarantee this same
/// change touches.
@Test(arguments: AuthorityCoverage.authorities) @MainActor
func theIndicatorStillFadesAndTheWindowReturnsIdleAfterWakingFromAPausedLink(_ authority: LayoutAuthority) throws {
    AuthorityCoverage.record(#function, authority)
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 120, startsDisplayLink: true,
                                               layoutAuthority: authority) {
        ScrollView(.vertical, elementID: listID) {
            Box(style: columnStyle()) {
                Box(style: fixedHeight(40)); Box(style: fixedHeight(40))
                Box(style: fixedHeight(40)); Box(style: fixedHeight(40))
                Box(style: fixedHeight(40))
            }
        }
    }

    platformWindow.simulateTick(timestamp: 100)
    platformWindow.simulateTick(timestamp: 105)
    #expect(platformWindow.pauseCalls.last == true, "set up: the link is paused before the wake-up scroll")

    platformWindow.simulateInput(wheel(at: pt(60, 60), deltaY: -20, timestamp: 111))
    platformWindow.simulateTick(timestamp: 111.05)
    #expect(!window.lastScene.rects.isEmpty, "set up: the indicator is visible right after the wake-up scroll")

    // age 0.3 (11.05's render already covered age 0.05): inside the fully
    // opaque window measured from the EVENT's timestamp (11), not the stale
    // tick (5) — from the latter this would already read age 6.3.
    platformWindow.simulateTick(timestamp: 111.3)
    #expect(window.needsRedraw, "age 0.3 from the event's own timestamp is inside the opaque window")

    // age 0.8: inside the fade ramp, still visible, must still be requesting.
    platformWindow.simulateTick(timestamp: 111.8)
    #expect(window.needsRedraw, "age 0.8 is inside the fade ramp and must still request another frame")

    // age 1.1: fully faded. This render must be the LAST one this scroll
    // causes.
    let framesBeforeFadeCompletes = window.framesDrawn
    platformWindow.simulateTick(timestamp: 112.1)
    #expect(window.framesDrawn == framesBeforeFadeCompletes + 1,
            "this tick was still dirty going in and must have drawn once")
    #expect(!window.needsRedraw, "age 1.1 > 1.0: fully faded, and this render must not ask for another frame")
    #expect(window.lastScene.rects.isEmpty, "a fully faded indicator must emit no primitive at all")

    // And it stays idle.
    let framesAfterFade = window.framesDrawn
    platformWindow.simulateTick(timestamp: 120)
    #expect(window.framesDrawn == framesAfterFade, "idle stays idle: no further frame may draw")
}

// MARK: - 5c. The window's first frame is built before any tick
//
/// A never-scrolled, scrollABLE `ScrollView` paints no indicator and requests
/// no frame on the window's **pre-tick** first frame — the one
/// `App.openWindow` draws itself, before the display link has ever fired.
///
/// **Why every other idle test in this file cannot see it.** `Window.lastTick`
/// is 0 until the first tick, so that frame's `PaintPass.timestamp` is 0, and
/// `ScrollState.lastScrollTime` used to default to 0 as well: `age` came out
/// exactly 0, deep inside the fully-opaque window, so every scrollable
/// `ScrollView` painted its thumb at the token's full 0.35 on the first frame
/// and called `requestAnotherFrame()`. The next frame is built at a real
/// `targetTimestamp`, which is why it lasted one frame. The three tests in
/// this file that assert "an idle, never-scrolled ScrollView must not keep the
/// window dirty" all open at `simulateTick(timestamp: 100)`, where the old
/// default gives `age == 100`, so all three were green against it.
///
/// **The positive control is the same window at the same instant.** After the
/// first frame, a wheel event (stamped with the fake's `currentTime`, still 0)
/// and a second pre-tick draw DO paint the thumb and keep the window dirty.
/// Without that half, a fixture that could not scroll at all would pass the
/// first half for the wrong reason — `guard scrollable > 0` returns just as
/// early as `guard alpha > 0` does.
///
/// **The `ProposalScrollView` arm** (stage 3 lane 1, test 1.3, `LR-BD`) is the
/// same claim for the element that held the second copy of the chrome. It is
/// writable and green at `57893d0` — `ProposalScrollView` already reads
/// `ScrollState()`, so it already inherits the `-.infinity` default — and the
/// fold is what must not change it. **Mutation M1e**, `ScrollState.lastScrollTime`'s
/// default (and its init's parameter default) set to `0`, must redden **both**
/// arms: with `age == 0` on the pre-tick frame every scrollable scroller of
/// either kind paints its thumb at full strength and asks for another frame.
@Test(arguments: AuthorityCoverage.authorities) @MainActor
func aNeverScrolledScrollViewPaintsNoIndicatorOnTheWindowsPreTickFirstFrame(_ authority: LayoutAuthority) throws {
    AuthorityCoverage.record(#function, authority)
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 120, startsDisplayLink: true,
                                               layoutAuthority: authority) {
        ScrollView(.vertical, elementID: listID) {
            Box(style: columnStyle()) {
                Box(style: fixedHeight(40)); Box(style: fixedHeight(40))
                Box(style: fixedHeight(40)); Box(style: fixedHeight(40))
                Box(style: fixedHeight(40))
            }
        }
    }

    // `App.openWindow`'s own pre-tick draw: no `simulateTick` has run.
    let framesBefore = window.framesDrawn
    window.drawFrameIfNeeded()
    try #require(window.framesDrawn == framesBefore + 1, "set up: the pre-tick first frame must actually draw")
    #expect(window.lastScene.rects.isEmpty,
            "a never-scrolled ScrollView must not paint its indicator on the window's first frame")
    #expect(!window.needsRedraw,
            "and must not request another frame from it: nothing has scrolled, so there is nothing to fade")

    // The control: a real scroll at the same instant does paint.
    platformWindow.simulateInput(wheel(at: pt(60, 60), deltaY: -20))
    try #require(window.needsRedraw, "set up: the scroll itself must dirty the window")
    window.drawFrameIfNeeded()
    let rect = try #require(window.lastScene.rects.first,
                            "control: the same fixture, scrolled at the same instant, must paint the thumb — or it cannot scroll and the first half proves nothing")
    #expect(abs(Double(rect.background.a) - 0.35) < 0.001,
            "control: age 0 after a real scroll is the token's full 0.35")
    #expect(window.needsRedraw, "control: a thumb that just appeared must request the frames that fade it")

    // The `ProposalScrollView` arm, in its own window so the two cannot share
    // a `ScrollState`. Its content is five 40pt rectangles in a zero-spacing
    // `VStack` — 200pt of content behind a 120pt viewport, the same overflow
    // the legacy arm has, and the rectangles paint, so "no indicator" here is
    // a rect COUNT rather than an empty scene.
    let (proposalWindow, proposalPlatformWindow) =
        try makeFakeWindow(device: device, size: 120, startsDisplayLink: true,
                           layoutAuthority: authority) {
            ProposalScrollView(.vertical, elementID: listID) {
                VStack(spacing: Pixels(0)) {
                    Rectangle(width: Pixels(120), height: Pixels(40), color: .accent)
                    Rectangle(width: Pixels(120), height: Pixels(40), color: .accent)
                    Rectangle(width: Pixels(120), height: Pixels(40), color: .accent)
                    Rectangle(width: Pixels(120), height: Pixels(40), color: .accent)
                    Rectangle(width: Pixels(120), height: Pixels(40), color: .accent)
                }
            }
        }
    let proposalFramesBefore = proposalWindow.framesDrawn
    proposalWindow.drawFrameIfNeeded()
    try #require(proposalWindow.framesDrawn == proposalFramesBefore + 1,
                 "set up: the pre-tick first frame must actually draw")
    #expect(proposalWindow.lastScene.rects.count == 5,
            "the five content rectangles and no thumb: a never-scrolled ProposalScrollView must not paint its indicator on the window's first frame either")
    #expect(!proposalWindow.needsRedraw,
            "and must not request another frame from it")

    proposalPlatformWindow.simulateInput(wheel(at: pt(60, 60), deltaY: -20))
    try #require(proposalWindow.needsRedraw, "set up: the scroll itself must dirty the window")
    proposalWindow.drawFrameIfNeeded()
    let proposalRect = try #require(proposalWindow.lastScene.rects.last,
                                    "control: the same fixture, scrolled at the same instant, must paint the thumb")
    #expect(proposalWindow.lastScene.rects.count == 6, "five rectangles plus the thumb")
    #expect(abs(Double(proposalRect.background.a) - 0.35) < 0.001,
            "control: age 0 after a real scroll is the token's full 0.35 here too")
    #expect(proposalWindow.needsRedraw, "control: a thumb that just appeared must request the frames that fade it")
}

// MARK: - 6. The fade is a RAMP, and it uses the scroll-indicator token

/// The alpha at a mid-ramp age, which is the one measurement that separates a
/// ramp from a step and names the theme token in one assertion.
///
/// Two wrong implementations this catches, both of which passed the whole
/// suite before it existed:
///
/// - **`let alpha = age < 1.0 ? 1.0 : 0.0`** — a hard step with no fade at
///   all. Every existing assertion about the indicator is about its
///   *presence*, and this mutant keeps it present for exactly as long, so
///   nothing saw it. At age 0.8 it gives 0.35 where the ramp gives 0.175.
/// - **`pass.theme[.textPrimary]`** in place of `pass.theme[.scrollIndicator]`.
///   `textPrimary` is opaque (alpha 1) and `scrollIndicator` is alpha 0.35, so
///   the same assertion separates them 0.5 against 0.175.
///
/// The expectation is arithmetic named here rather than read back from the
/// element: `Theme.light.scrollIndicator` is `.rgb(0x000000, alpha: 0.35)`, and
/// the ramp at age 0.8 is `1 - (0.8 - 0.6) / 0.4 = 0.5`.
@Test(arguments: AuthorityCoverage.authorities) @MainActor
func theIndicatorFadesOnARampAndTakesItsColourFromTheScrollIndicatorToken(_ authority: LayoutAuthority) throws {
    AuthorityCoverage.record(#function, authority)
    func alphaAtAge(_ age: Double) throws -> Double {
        var view = ScrollView(.vertical, elementID: listID) {
            Box(style: fixedSize(120, 200))
        }
        let (frame, _) = fullyRendered(&view, width: 120, height: 100,
                                       stateTable: scrolledState(offset: 20, lastScrollTime: 100),
                                       timestamp: 100 + age, authority: authority)
        return Double(try #require(frame.scene.rects.first).background.a)
    }

    // age 0.2: inside the fully-opaque window, so the token's own alpha.
    #expect(abs(try alphaAtAge(0.2) - 0.35) < 0.001,
            "before the ramp starts the thumb is the scroll-indicator token at full strength")
    // age 0.8: halfway down the 0.6...1.0 ramp.
    #expect(abs(try alphaAtAge(0.8) - 0.175) < 0.001,
            "0.35 x 0.5 — a step function gives 0.35 here, and the textPrimary token gives 0.5")
    // The token is black, not `textPrimary`'s 0x14181F. Named separately so a
    // failure says WHICH half is wrong.
    var view = ScrollView(.vertical, elementID: listID) { Box(style: fixedSize(120, 200)) }
    let (frame, _) = fullyRendered(&view, width: 120, height: 100,
                                   stateTable: scrolledState(offset: 20, lastScrollTime: 100),
                                   timestamp: 100.2,
                                   authority: authority)
    #expect(try #require(frame.scene.rects.first).background.l == 0,
            "Theme.light.scrollIndicator is 0x000000; textPrimary is 0x14181F and is not black")
}

// MARK: - 7. The horizontal branch's geometry

/// The `.horizontal` branch of `ScrollChrome.indicatorBounds`, which ran in
/// `aHorizontalScrollViewMovesOnDeltaXNotDeltaY` with nothing reading the rect
/// it produced.
///
/// What this catches, measured: **transposing `width:` and `height:` at
/// `ScrollChrome.indicatorBounds`'s `.horizontal` case** — the thumb comes back
/// 3pt wide and 50pt tall, a vertical bar lying across a horizontal track —
/// passed the entire suite. So did an inset or a travel axis taken from the
/// wrong coordinate.
///
/// The numbers, computed here rather than read off the element: viewport 100
/// wide over 200 of content gives `thumb = max(20, 100 * (100/200)) = 50` and
/// a scrollable range of 100; at offset 50 the travel is
/// `(50/100) * (100 - 50) = 25`.
@Test(arguments: AuthorityCoverage.authorities) @MainActor
func theHorizontalIndicatorLiesAlongTheBottomOfItsViewport(_ authority: LayoutAuthority) throws {
    AuthorityCoverage.record(#function, authority)
    var view = ScrollView(.horizontal, elementID: listID) {
        Box(style: fixedWidth(200, 60))
    }
    let (frame, layout) = fullyRendered(&view, width: 100, height: 60,
                                        stateTable: scrolledState(offset: 50, lastScrollTime: 0),
                                        authority: authority)
    let viewport = frame.bounds(of: layout.node)
    try #require(Double(frame.bounds(of: layout.contentNode).size.width.value) == 200,
                 "the fixture must overflow horizontally, or there is no thumb to measure")

    let rect = try #require(frame.scene.rects.first)
    #expect(abs(Double(rect.bounds.size.width) - 50) < 0.05,
            "the thumb runs ALONG the scroll axis: 50pt wide, not 50pt tall")
    #expect(abs(Double(rect.bounds.size.height) - 3) < 0.001,
            "and 3pt across it")
    #expect(abs(Double(rect.bounds.origin.x) - (Double(viewport.origin.x.value) + 25)) < 0.05,
            "travel is (50/100) * (100 - 50) = 25 along x, the scroll axis")
    #expect(abs(Double(rect.bounds.origin.y)
                - (Double(viewport.origin.y.value) + Double(viewport.size.height.value) - 5)) < 0.001,
            "it sits 5pt up from the viewport's bottom edge: a 2pt inset plus its own 3pt height")
}

// MARK: - 7. Clipped by the viewport's rounded corner, without scrolling with it

/// A padded wrapper so the `ScrollView`'s viewport lands at a **non-zero origin
/// on both axes**, and the ids for both levels.
///
/// The origin matters more than it looks. Two GPU clip mutants survived this
/// branch's whole suite because every fixture in it sat at `(0, 0)` and cut in
/// `x` only, so a mask that ignored its origin — or that read `x` where it
/// meant `y` — produced the right answer by coincidence. 17 and 23 are
/// deliberately different from each other and from every other number in the
/// fixture's geometry.
private func paddedRow() -> Style {
    var s = Style()
    s.flexDirection = .row
    s.padding = Edges(top: .pixels(Pixels(23)), right: .pixels(Pixels(0)),
                      bottom: .pixels(Pixels(0)), left: .pixels(Pixels(17)))
    // **The width is declared for the same reason the fixtures below it are**
    // (`LR-BN`): the legacy root takes the frame's definite 160, a native root
    // is centred at its own answer (`CN-J`), and this box's answer is its
    // content's 100 plus 17 of padding — which would put the viewport at x 39
    // rather than 17 and move every literal in the test. Declaring 160 makes
    // the two roots the same box; the legacy numbers do not move.
    s.size.width = .length(.pixels(Pixels(160)))
    return s
}

/// Both axes in pixels, on a column. The cross-axis half is what the
/// single-child `ScrollView` fixtures need under both authorities — see the note
/// above `fixedWidth`.
private func fixedSize(_ w: Float, _ h: Float) -> Style {
    var s = columnStyle()
    s.size = Size(width: .length(.pixels(Pixels(w))), height: .length(.pixels(Pixels(h))))
    return s
}

private let nestedRootID = GlobalElementID.child(of: nil, at: 0, name: nil)
private let nestedListID = GlobalElementID.child(of: nestedRootID, at: 0, name: listID)

/// The overlay indicator carries the viewport's clip — rounded corners included
/// — while carrying none of its scroll translation.
///
/// **The two halves pull in opposite directions, which is why they are asserted
/// together.** The thumb is painted OUTSIDE `paint`'s `clipped(to:offsetBy:)`
/// block so that it does not scroll away with the content; before this, outside
/// the block also meant clipped by nothing at all, and `Frame.fill` stamped it
/// with the whole surface and zero radii — so on a rounded viewport it painted
/// square across the corner the background had curved away. The fix is its own
/// `clipped(to:)` at the same bounds and the same radii with `offsetBy: .zero`,
/// and a test that checked only the clip would pass just as well if that
/// `.zero` were the content's `-offset`.
///
/// **Every number below is hand-derived from the fixture, not read back from
/// the implementation.** A 160×140 frame, 17pt of left padding and 23pt of top
/// padding put a 100×117 viewport at (17, 23): 100 because the `ScrollView`'s
/// main axis in a `.row` parent is its width and its content declares 100, 117
/// because its height is the cross axis and stretches into 140 - 23. Content is
/// 400 tall, so the thumb is 117 × (117/400) = 34.2225 — clear of the 20pt
/// floor — and the track is 117 - 34.2225 = 82.7775 over 400 - 117 = 283 of
/// scrollable range, giving exactly 0.2925 of travel per point of offset.
///
/// **The 24pt radius is chosen so an unclipped thumb genuinely crosses the
/// curve**, which a smaller one would not. The viewport's top-right corner arc
/// is centred at (117 - 24, 23 + 24) = (93, 47); at the thumb's x of 112 the arc
/// sits at y = 47 - sqrt(24² - 19²) = 32.34, while at offset 0 the thumb starts
/// at y = 23. Roughly nine points of it are outside the rounded corner and must
/// be masked away.
@Test(arguments: AuthorityCoverage.authorities) @MainActor
func theIndicatorIsClippedByTheViewportsRoundedCornerWithoutScrollingWithIt(_ authority: LayoutAuthority) throws {
    AuthorityCoverage.record(#function, authority)
    func indicator(offset: Double) throws -> MUIRect {
        let table = StateTable()
        table.withState(nestedListID, initial: ScrollState()) {
            $0.offset = offset
            $0.lastScrollTime = 0
        }
        var root = Box(style: paddedRow()) {
            ScrollView(.vertical, elementID: listID) {
                Box(style: fixedSize(100, 400))
            }
            .cornerRadius(Pixels(24))
        }
        let (frame, _) = fullyRendered(&root, width: 160, height: 140, stateTable: table,
                                       authority: authority)
        let scene = frame.finalizedScene()
        try #require(scene.rects.count == 1,
                     "only the thumb paints here — the boxes carry no decoration")
        return try #require(scene.rects.first)
    }

    // Offset 0: the thumb sits at the very top of its track, inside the
    // top-right corner's curve, which is the position the missing clip was
    // visible in.
    let atTop = try indicator(offset: 0)
    #expect(Double(atTop.contentMask.origin.x) == 17 && Double(atTop.contentMask.origin.y) == 23,
            "the thumb must be masked to the VIEWPORT, at its own non-zero origin on both axes — unclipped it would carry the whole 160×140 surface at (0, 0)")
    #expect(Double(atTop.contentMask.size.width) == 100 && Double(atTop.contentMask.size.height) == 117,
            "and to the viewport's own extent, not the surface's")
    #expect(Double(atTop.maskCornerRadii.topRight) == 24
            && Double(atTop.maskCornerRadii.topLeft) == 24
            && Double(atTop.maskCornerRadii.bottomRight) == 24
            && Double(atTop.maskCornerRadii.bottomLeft) == 24,
            "the mask must carry the viewport's 24pt curve; a square mask lets the thumb paint across the corner the background curved away")
    #expect(abs(Double(atTop.bounds.origin.y) - 23) < 0.001,
            "at offset 0 the thumb starts flush with the top of its track")

    // Offset 100: the thumb must have moved by its OWN travel term and by
    // nothing else. 100 × 0.2925 = 29.25, so y = 23 + 29.25 = 52.25. Had the
    // new clip been pushed with the content's `-offset` instead of `.zero`,
    // this would read 52.25 - 100 = -47.75 and the thumb would have scrolled
    // off the top of the window.
    let scrolled = try indicator(offset: 100)
    #expect(abs(Double(scrolled.bounds.origin.y) - 52.25) < 0.001,
            "the thumb moves by its travel term (29.25) alone; a clip pushed with the scroll translation would put it at -47.75")
    #expect(abs(Double(scrolled.bounds.origin.x) - 112) < 0.001,
            "and not at all on the cross axis: 17 + 100 - 5")
    #expect(Double(scrolled.contentMask.origin.x) == 17 && Double(scrolled.contentMask.origin.y) == 23,
            "the mask is the viewport's rect in its own space, so scrolling must not move it either")
}

// MARK: - 7. `scrollIndicators(.hidden)`

/// `.hidden` emits no indicator rect at all, in a fixture that would
/// otherwise definitely show one — content taller than the viewport,
/// rendered immediately after a scroll so the fade has not had time to
/// elapse (`lastScrollTime` equals the render's own `timestamp`, giving
/// `age == 0`, deep inside the fully-opaque window).
///
/// Paired with `automaticStillPaintsTheIndicatorInTheSameFixture` below as
/// the differential this rule needs: without that second test, this one
/// would pass equally against a `ScrollView` that never painted an
/// indicator at all, proving nothing about `.hidden` specifically.
@Test(arguments: AuthorityCoverage.authorities) @MainActor
func hiddenEmitsNoIndicatorRect(_ authority: LayoutAuthority) throws {
    AuthorityCoverage.record(#function, authority)
    var view = ScrollView(.vertical, elementID: listID) {
        Box(style: fixedSize(120, 200))
    }
    .scrollIndicators(.hidden)
    let (frame, _) = fullyRendered(&view, width: 120, height: 100,
                                   stateTable: scrolledState(offset: 20, lastScrollTime: 100),
                                   timestamp: 100,
                                   authority: authority)
    #expect(frame.scene.rects.isEmpty,
            "content overflows and the fade has not elapsed (age 0), so an `.automatic` indicator would definitely paint here — `.hidden` must suppress it entirely")
}

/// The differential for the test above: the identical fixture, `.automatic`
/// (the default) in place of `.hidden`, does paint the thumb. Without this,
/// `hiddenEmitsNoIndicatorRect` could pass against a fixture that never
/// draws an indicator regardless of the setting.
@Test(arguments: AuthorityCoverage.authorities) @MainActor
func automaticStillPaintsTheIndicatorInTheSameFixture(_ authority: LayoutAuthority) throws {
    AuthorityCoverage.record(#function, authority)
    var view = ScrollView(.vertical, elementID: listID) {
        Box(style: fixedSize(120, 200))
    }
    let (frame, _) = fullyRendered(&view, width: 120, height: 100,
                                   stateTable: scrolledState(offset: 20, lastScrollTime: 100),
                                   timestamp: 100,
                                   authority: authority)
    #expect(!frame.scene.rects.isEmpty,
            "the same fixture under `.automatic` (the default) must paint the thumb, or the test above proves nothing")
}

/// A hidden indicator must not keep the window dirty or the display link
/// awake. `ScrollChrome.paintIndicator`'s `.hidden` guard sits before
/// `pass.requestAnotherFrame()`; if it moved after that call (or was
/// removed), a hidden scroll view would still ask for another frame on
/// every tick while nothing ever fades, holding the display link awake
/// forever — spec §4.4's "no frames built and display link paused while
/// idle" is an M4 exit criterion this must not break.
///
/// Driven through a real `Window`, matching
/// `theIndicatorRequestsFramesWhileFadingAndStopsWhenDone` above — a bare
/// `Frame` has no "stays idle" concept to fail.
@Test(arguments: AuthorityCoverage.authorities) @MainActor
func hiddenIndicatorDoesNotKeepTheWindowDirtyOrTheLinkAwake(_ authority: LayoutAuthority) throws {
    AuthorityCoverage.record(#function, authority)
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 120, startsDisplayLink: true,
                                               layoutAuthority: authority) {
        ScrollView(.vertical, elementID: listID) {
            Box(style: columnStyle()) {
                Box(style: fixedHeight(40)); Box(style: fixedHeight(40))
                Box(style: fixedHeight(40)); Box(style: fixedHeight(40))
                Box(style: fixedHeight(40))
            }
        }
        .scrollIndicators(.hidden)
    }

    platformWindow.simulateTick(timestamp: 100)
    #expect(!window.needsRedraw, "an idle, never-scrolled ScrollView must not keep the window dirty")

    // The scroll itself still dirties the window and draws once — hiding
    // the indicator does not stop content from scrolling.
    platformWindow.simulateInput(wheel(at: pt(60, 60), deltaY: -20))
    #expect(window.needsRedraw, "the scroll itself must still dirty the window")
    let framesBeforeSettling = window.framesDrawn
    platformWindow.simulateTick(timestamp: 100.05)
    #expect(window.framesDrawn == framesBeforeSettling + 1, "the dirtied window draws exactly once")
    #expect(window.lastScene.rects.isEmpty, "a hidden indicator paints no rect on the scroll's own frame either")

    // The load-bearing assertion: with an `.automatic` indicator this same
    // shape (age 0.05, well inside the 0.6s opaque window) would still be
    // requesting frames — see `theIndicatorRequestsFramesWhileFadingAndStopsWhenDone`
    // above. Here the window must already be clean, because `.hidden`
    // returns before `requestAnotherFrame()` is ever called.
    #expect(!window.needsRedraw, "`.hidden` must not request another frame even while an `.automatic` indicator would still be fading")

    // And it stays clean: the (already paused, or about to pause) link
    // never ticks it back to life.
    let framesAfterSettling = window.framesDrawn
    platformWindow.simulateTick(timestamp: 100.2)
    platformWindow.simulateTick(timestamp: 101.1)
    #expect(window.framesDrawn == framesAfterSettling,
            "nothing dirtied the window after the scroll settled, so no further frame may draw")
    #expect(platformWindow.pauseCalls.last == true, "the display link must pause — a hidden indicator must not hold it awake")
}
