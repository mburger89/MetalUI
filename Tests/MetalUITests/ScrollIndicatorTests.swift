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

private func fixedWidth(_ w: Float) -> Style {
    var s = Style()
    s.flexDirection = .row
    s.size = Size(width: .length(.pixels(Pixels(w))), height: .auto)
    return s
}

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
                                       timestamp: Double = 0) -> (Frame, E.LayoutState) {
    let frame = Frame(contentSize: Size(width: Pixels(width), height: Pixels(height)),
                      scaleFactor: 1, stateTable: stateTable, timestamp: timestamp)
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
@Test @MainActor func theIndicatorIsTheLastPrimitiveInTheScene() throws {
    let table = scrolledState(offset: 20, lastScrollTime: 0)
    var view = ScrollView(.vertical, elementID: listID) {
        Column {
            Text("Row one"); Text("Row two"); Text("Row three"); Text("Row four")
            Text("Row five"); Text("Row six"); Text("Row seven"); Text("Row eight")
        }
    }
    let (frame, layout) = fullyRendered(&view, width: 120, height: 100, stateTable: table)
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
@Test @MainActor func contentThatFitsDrawsNoIndicator() throws {
    var view = ScrollView(.vertical, elementID: listID) {
        Box(style: fixedHeight(40))
    }
    let (frame, _) = fullyRendered(&view, width: 120, height: 100)
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
@Test @MainActor func theThumbIsProportionalAndFlooredAtTwentyPoints() throws {
    // viewport 100, content 200 → 100 * (100/200) = 50, well clear of the
    // floor: this isolates the PROPORTION formula.
    do {
        var view = ScrollView(.vertical, elementID: listID) {
            Box(style: fixedHeight(200))
        }
        let (frame, _) = fullyRendered(&view, width: 120, height: 100)
        let rect = try #require(frame.scene.rects.first)
        #expect(abs(Double(rect.bounds.size.height) - 50) < 0.05,
                "100 * (100/200) = 50 — a bare proportional size, not the floor")
        // The CROSS axis, which nothing else in this file reads: 3pt wide,
        // inset 2pt from the viewport's trailing edge (origin.x + width - 5).
        // Catches a transposed `width:`/`height:` in `indicatorBounds`'s
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
            Box(style: fixedHeight(1000))
        }
        let (frame, _) = fullyRendered(&view, width: 120, height: 100)
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
@Test @MainActor func theThumbReachesTheEndOfItsTrackAtMaximumOffset() throws {
    // viewport 100, content 200 → scrollable 100, thumb 50: clear of the
    // 20pt floor, so this isolates the position formula from it.
    do {
        var view = ScrollView(.vertical, elementID: listID) {
            Box(style: fixedHeight(200))
        }
        let (frame, layout) = fullyRendered(&view, width: 120, height: 100,
                                            stateTable: scrolledState(offset: 100, lastScrollTime: 0))
        let rect = try #require(frame.scene.rects.first)
        let trackBottom = Double(frame.bounds(of: layout.node).origin.y.value)
                         + Double(frame.bounds(of: layout.node).size.height.value)
        let thumbBottom = Double(rect.bounds.origin.y) + Double(rect.bounds.size.height)
        #expect(abs(thumbBottom - trackBottom) < 0.01,
                "at the maximum offset the thumb's far edge must land EXACTLY at the end of the track")
    }

    do {
        var view = ScrollView(.vertical, elementID: listID) {
            Box(style: fixedHeight(200))
        }
        let (frame, layout) = fullyRendered(&view, width: 120, height: 100,
                                            stateTable: scrolledState(offset: 0, lastScrollTime: 0))
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
@Test @MainActor func theIndicatorRequestsFramesWhileFadingAndStopsWhenDone() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 120, startsDisplayLink: true) {
        ScrollView(.vertical, elementID: listID) {
            Box(style: columnStyle()) {
                Box(style: fixedHeight(40)); Box(style: fixedHeight(40))
                Box(style: fixedHeight(40)); Box(style: fixedHeight(40))
                Box(style: fixedHeight(40))
            }
        }
    }

    // A baseline tick far from zero. Nothing has scrolled yet — ScrollState's
    // default `lastScrollTime` is 0 — so `age` here is enormous and the
    // window must already be clean: a never-scrolled but scrollABLE list
    // must not paint an indicator or request anything, either.
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
@Test @MainActor func theIndicatorFadesOnARampAndTakesItsColourFromTheScrollIndicatorToken() throws {
    func alphaAtAge(_ age: Double) throws -> Double {
        var view = ScrollView(.vertical, elementID: listID) {
            Box(style: fixedHeight(200))
        }
        let (frame, _) = fullyRendered(&view, width: 120, height: 100,
                                       stateTable: scrolledState(offset: 20, lastScrollTime: 100),
                                       timestamp: 100 + age)
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
    var view = ScrollView(.vertical, elementID: listID) { Box(style: fixedHeight(200)) }
    let (frame, _) = fullyRendered(&view, width: 120, height: 100,
                                   stateTable: scrolledState(offset: 20, lastScrollTime: 100),
                                   timestamp: 100.2)
    #expect(try #require(frame.scene.rects.first).background.l == 0,
            "Theme.light.scrollIndicator is 0x000000; textPrimary is 0x14181F and is not black")
}

// MARK: - 7. The horizontal branch's geometry

/// The `.horizontal` branch of `indicatorBounds`, which ran in
/// `aHorizontalScrollViewMovesOnDeltaXNotDeltaY` with nothing reading the rect
/// it produced.
///
/// What this catches, measured: **transposing `width:` and `height:` at
/// `ScrollView.indicatorBounds`'s `.horizontal` case** — the thumb comes back
/// 3pt wide and 50pt tall, a vertical bar lying across a horizontal track —
/// passed the entire suite. So did an inset or a travel axis taken from the
/// wrong coordinate.
///
/// The numbers, computed here rather than read off the element: viewport 100
/// wide over 200 of content gives `thumb = max(20, 100 * (100/200)) = 50` and
/// a scrollable range of 100; at offset 50 the travel is
/// `(50/100) * (100 - 50) = 25`.
@Test @MainActor func theHorizontalIndicatorLiesAlongTheBottomOfItsViewport() throws {
    var view = ScrollView(.horizontal, elementID: listID) {
        Box(style: fixedWidth(200))
    }
    let (frame, layout) = fullyRendered(&view, width: 100, height: 60,
                                        stateTable: scrolledState(offset: 50, lastScrollTime: 0))
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
    return s
}

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
@Test @MainActor func theIndicatorIsClippedByTheViewportsRoundedCornerWithoutScrollingWithIt() throws {
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
        let (frame, _) = fullyRendered(&root, width: 160, height: 140, stateTable: table)
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
