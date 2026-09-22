import Testing
import Metal
import MetalUICore
import MetalUILayout
import MetalUIRender
@testable import MetalUI

// Plan task 7, stage 3 of the engine replacement — the scroll lane.
// Design: `docs/superpowers/specs/2026-09-22-engine-stage-3-design.md`.
//
// **Lane 1 (`LR-BD`): the shared scroll chrome.** `ScrollView` and
// `ProposalScrollView` each held a copy of the clamp, the offset resolution and
// the fading overlay indicator — seven members, line-equivalent, ten lines
// apart. CLAUDE.md's practice *a copy of a pinned implementation is unpinned*
// is the whole reason the fold happens: every assertion about that behaviour
// named `ScrollView`, and `ProposalScrollView`'s copy could have drifted (one
// of them already had — the two `lastScroll` seeds differed) without a single
// test noticing.
//
// The four tests below are **characterization** tests: each is green at
// `57893d0`, before the fold, because the two copies agreed. What they buy is
// that the fold cannot change either element's behaviour silently, and that a
// future re-inlining of any of the seven members shows up as a failure rather
// than as drift. Their evidence is their mutations (record §24, lane 1), not a
// red-before run.
//
// Lanes 2–5 add the `ScrollView` lowering's own tests to this file.

private let chromeListID = ElementID("chrome-list")
private let chromeRootID = GlobalElementID.child(of: nil, at: 0, name: chromeListID)

@MainActor
private func chromeScrolledState(_ id: GlobalElementID, offset: Double,
                                 lastScrollTime: Double) -> StateTable {
    let table = StateTable()
    table.withState(id, initial: ScrollState()) {
        $0.offset = offset
        $0.lastScrollTime = lastScrollTime
    }
    return table
}

/// `requestLayout` → `computeRootLayout` → `prepaint` → `paint` by hand: the
/// three phases `Frame.render` runs, handing back the element's own
/// `LayoutState` afterward. `Frame.render` discards it, and it is the only way
/// to a scroller's viewport and content nodes from outside the element. The
/// same idiom as `ScrollIndicatorTests.fullyRendered`, written out again rather
/// than shared because that one is `private` to its own file.
@MainActor
private func chromeRendered<E: Element>(_ element: inout E, width: Float, height: Float,
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

/// A vertical `ProposalScrollView` of one fixed rectangle: the proposal twin of
/// the `Box(style: fixedHeight(…))` fixture the `ScrollView` indicator tests
/// use. One child, so `requestProposalLayout` takes its `children.count == 1`
/// branch and the content node IS the rectangle — its extent is the literal
/// height passed here, with no stack spacing in the way.
@MainActor
private func proposalScroller(contentHeight: Float, width: Float = 120)
    -> ProposalScrollView<Rectangle> {
    ProposalScrollView(.vertical, elementID: chromeListID) {
        Rectangle(width: Pixels(width), height: Pixels(contentHeight), color: .accent)
    }
}

private func pt(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: Pixels(x), y: Pixels(y)) }

private func wheelEvent(at position: Point<Pixels>, deltaY: Float) -> InputEvent {
    .scrollWheel(ScrollEvent(position: position, delta: Point(x: Pixels(0), y: Pixels(deltaY)),
                             isMomentum: false))
}

// MARK: - 1.1 The clamp and its write-back, on the proposal element

/// **Test 1.1.** `ProposalScrollView`'s half of
/// `scrollingPastTheEndDoesNotBankAnOffsetTheUserMustUnwind` and of
/// `aStoredOffsetPastTheEndIsClampedWhenItIsRead` — the shipped intermittent
/// defect those two pin for `ScrollView`, pinned for the element that held the
/// second copy of the fix.
///
/// The defect: `Window.applyScroll` writes `offset -= delta` with no bound, so
/// clamping what is *read* while leaving what is *stored* alone lets a gesture
/// against either end bank an arbitrarily large excess invisibly — the view
/// sits at the end looking correct, and every reversing event then spends
/// itself paying the excess down. `ScrollChrome.resolvedOffset`'s `PrepaintPass` overload
/// writes the clamped value back, which bounds the stored value to one frame's
/// worth of events.
///
/// **One frame per event**, deliberately, exactly as the `ScrollView` test
/// does: that is both the regime the running app is in and the regime in which
/// the write-back's bound actually holds. Driving a batch between two frames
/// would measure the looser bound.
///
/// **Both ends**, because the clamp is two separately removable terms:
/// `min(…)` bounds the bottom and `max(0, …)` the top.
///
/// **Every number is hand-derived from the fixture.** Five 40pt rectangles in a
/// `VStack(spacing: 0)` are 200pt of content; a 120pt window makes the viewport
/// 120 (the kernel viewport answers its proposal on the scrolling axis), so
/// there are 80pt of travel. The thumb is `max(20, 120 × (120/200)) = 72` on a
/// track of `120 − 72 = 48`, so an offset of 51 out of 80 puts its top at
/// `(51/80) × 48 = 30.6`. A read-only clamp would leave 193 stored here and
/// park the thumb at 48, flush with the end of its track.
///
/// Green at `57893d0`: `ProposalScrollView`'s own copy of the write-back did
/// this already. **Mutation M1a** — the prepaint overload's `$0.offset = …`
/// write-back deleted — must redden this test *and*
/// `scrollingPastTheEndDoesNotBankAnOffsetTheUserMustUnwind`, which is the pair
/// that shows one implementation now serves both elements.
@Test @MainActor func aProposalScrollViewClampsAStoredOffsetPastTheEndAndWritesItBack() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 120) {
        ProposalScrollView(.vertical, elementID: chromeListID) {
            VStack(spacing: Pixels(0)) {
                Rectangle(width: Pixels(120), height: Pixels(40), color: .accent)
                Rectangle(width: Pixels(120), height: Pixels(40), color: .accent)
                Rectangle(width: Pixels(120), height: Pixels(40), color: .accent)
                Rectangle(width: Pixels(120), height: Pixels(40), color: .accent)
                Rectangle(width: Pixels(120), height: Pixels(40), color: .accent)
            }
        }
    }
    window.drawFrameIfNeeded()
    let region = try #require(window.lastScrollRegions.first)
    func stored() -> Double? {
        window.stateTable.peek(region.id, as: ScrollState.self)?.offset
    }
    func scroll(_ deltaY: Float) {
        platformWindow.simulateInput(wheelEvent(at: pt(60, 60), deltaY: deltaY))
        window.drawFrameIfNeeded()
    }

    // Six -37 events sum to 222, nearly three times what the list can travel.
    for _ in 0..<6 { scroll(-37) }
    #expect(stored() == 80,
            "the stored offset must sit at the 80pt ceiling, not at the 222 the six deltas sum to")

    // One event back the other way must move the view immediately, by its own
    // full amount — not spend itself unwinding a banked 142.
    scroll(29)
    #expect(stored() == 51,
            "80 - 29 = 51; under a read-only clamp this reads 193 and still paints as 80")
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

// MARK: - 1.2 The indicator: ramp, token, proportion, floor, track, clip, hidden

/// **Test 1.2.** `ProposalScrollView`'s arms of the five `ScrollView` indicator
/// tests the fold makes one implementation:
/// `theIndicatorFadesOnARampAndTakesItsColourFromTheScrollIndicatorToken`,
/// `theThumbIsProportionalAndFlooredAtTwentyPoints`,
/// `theThumbReachesTheEndOfItsTrackAtMaximumOffset`,
/// `theIndicatorIsClippedByTheViewportsRoundedCornerWithoutScrollingWithIt` and
/// `hiddenEmitsNoIndicatorRect`.
///
/// Every expected number is arithmetic written here, not read back from the
/// element:
///
/// - **ramp**: `Theme.light.scrollIndicator` is `.rgb(0x000000, alpha: 0.35)`,
///   and the ramp at age 0.8 is `1 − (0.8 − 0.6)/0.4 = 0.5`, so 0.175. A hard
///   step (`age < 1.0 ? 1 : 0`) reads 0.35 here and the `textPrimary` token
///   reads 0.5 — the two wrong implementations the `ScrollView` test names.
/// - **proportion**: viewport 100 over content 200 gives `100 × (100/200) = 50`,
///   clear of the floor; 3pt across, 5pt in from the 120pt viewport's trailing
///   edge (a 2pt inset plus its own 3pt width).
/// - **floor**: viewport 100 over content 1000 gives 10, which must be floored
///   to 20 rather than left as an invisible sliver.
/// - **track**: at the maximum offset (100) the travel is
///   `(100/100) × (100 − 50) = 50`, so the thumb's far edge lands exactly on
///   the viewport's bottom edge at 100.
/// - **clip**: 17pt of left padding and 23pt of top around a scroller whose
///   content is 100 wide puts a 100×117 viewport at (39, 23) — 39 because
///   native padding centres a child that hugs (`160 − 17 = 143` of room,
///   `17 + (143 − 100)/2`), 117 because the viewport answers the proposal on
///   its scrolling axis. Content 400 tall gives a thumb of
///   `117 × (117/400) = 34.2225`, clear of the floor, on a track of
///   `117 − 34.2225 = 82.7775` over `400 − 117 = 283` of range: exactly 0.2925
///   of travel per point of offset, so offset 100 puts the thumb at
///   `23 + 29.25 = 52.25`. **The 24pt radius is large enough that an unclipped
///   thumb genuinely crosses the curve** — at the thumb's x of 134 the
///   top-right arc sits about 9pt below the thumb's top edge.
/// - **hidden**: the differential is the same fixture under `.automatic`, which
///   must paint two rects where `.hidden` paints one. Without it a fixture that
///   never draws an indicator would pass the `.hidden` half for free.
///
/// Mutations that must redden it: **M1b** the indicator's own clip given
/// `delta(-offset)` instead of `.zero`; **M1c** the 20pt thumb floor removed;
/// **M1d** `.hidden` checked after `requestAnotherFrame()`.
@Test @MainActor func aProposalScrollViewsIndicatorFadesOnTheSameRampAndIsClippedLikeTheContent() throws {
    // The ramp and the token.
    func alphaAtAge(_ age: Double) throws -> Double {
        var view = proposalScroller(contentHeight: 200)
        let (frame, _) = chromeRendered(&view, width: 120, height: 100,
                                        stateTable: chromeScrolledState(chromeRootID, offset: 20,
                                                                        lastScrollTime: 100),
                                        timestamp: 100 + age)
        return Double(try #require(frame.scene.rects.last).background.a)
    }
    #expect(abs(try alphaAtAge(0.2) - 0.35) < 0.001,
            "before the ramp starts the thumb is the scroll-indicator token at full strength")
    #expect(abs(try alphaAtAge(0.8) - 0.175) < 0.001,
            "0.35 × 0.5 — a step function gives 0.35 here, and the textPrimary token gives 0.5")
    do {
        var view = proposalScroller(contentHeight: 200)
        let (frame, _) = chromeRendered(&view, width: 120, height: 100,
                                        stateTable: chromeScrolledState(chromeRootID, offset: 20,
                                                                        lastScrollTime: 100),
                                        timestamp: 100.2)
        #expect(try #require(frame.scene.rects.last).background.l == 0,
                "Theme.light.scrollIndicator is 0x000000; textPrimary is 0x14181F and is not black")
    }

    // The proportion, and the thumb's cross axis.
    do {
        var view = proposalScroller(contentHeight: 200)
        let (frame, _) = chromeRendered(&view, width: 120, height: 100,
                                        stateTable: chromeScrolledState(chromeRootID, offset: 0,
                                                                        lastScrollTime: 0))
        let rect = try #require(frame.scene.rects.last)
        #expect(abs(Double(rect.bounds.size.height) - 50) < 0.05,
                "100 × (100/200) = 50 — a bare proportional size, not the floor")
        #expect(abs(Double(rect.bounds.size.width) - 3) < 0.001, "the thumb is 3pt on its cross axis")
        #expect(abs(Double(rect.bounds.origin.x) - 115) < 0.001,
                "the thumb sits 5pt in from the 120pt-wide viewport's trailing edge: a 2pt inset plus its own 3pt width")
    }

    // The floor, at a ratio where it and the proportion differ.
    do {
        var view = proposalScroller(contentHeight: 1000)
        let (frame, _) = chromeRendered(&view, width: 120, height: 100,
                                        stateTable: chromeScrolledState(chromeRootID, offset: 0,
                                                                        lastScrollTime: 0))
        let rect = try #require(frame.scene.rects.last)
        #expect(abs(Double(rect.bounds.size.height) - 20) < 0.05,
                "100 × (100/1000) = 10 must be floored to 20, not left as a 10pt sliver")
    }

    // The end of the track, exactly.
    do {
        var view = proposalScroller(contentHeight: 200)
        let (frame, _) = chromeRendered(&view, width: 120, height: 100,
                                        stateTable: chromeScrolledState(chromeRootID, offset: 100,
                                                                        lastScrollTime: 0))
        let rect = try #require(frame.scene.rects.last)
        #expect(abs((Double(rect.bounds.origin.y) + Double(rect.bounds.size.height)) - 100) < 0.01,
                "at the maximum offset the thumb's far edge must land EXACTLY on the viewport's 100pt bottom edge")
    }

    // The rounded clip, which must NOT carry the scroll translation.
    func paddedIndicator(offset: Double) throws -> MUIRect {
        let scrollerID = GlobalElementID.child(of: GlobalElementID.child(of: nil, at: 0, name: nil),
                                               at: 0, name: chromeListID)
        var root = Padding(Edges(top: Pixels(23), right: Pixels(0),
                                 bottom: Pixels(0), left: Pixels(17))) {
            ProposalScrollView(.vertical, elementID: chromeListID) {
                Rectangle(width: Pixels(100), height: Pixels(400), color: .accent)
            }
            .cornerRadius(Pixels(24))
        }
        let (frame, _) = chromeRendered(&root, width: 160, height: 140,
                                        stateTable: chromeScrolledState(scrollerID, offset: offset,
                                                                        lastScrollTime: 0))
        let scene = frame.finalizedScene()
        try #require(scene.rects.count == 2, "the content rectangle and the thumb, and nothing else")
        return try #require(scene.rects.last)
    }
    let atTop = try paddedIndicator(offset: 0)
    #expect(Double(atTop.contentMask.origin.x) == 39 && Double(atTop.contentMask.origin.y) == 23,
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
    let scrolled = try paddedIndicator(offset: 100)
    #expect(abs(Double(scrolled.bounds.origin.y) - 52.25) < 0.001,
            "the thumb moves by its travel term (29.25) alone; a clip pushed with the scroll translation would put it at -47.75")
    #expect(abs(Double(scrolled.bounds.origin.x) - 134) < 0.001,
            "and not at all on the cross axis: 39 + 100 - 5")
    #expect(Double(scrolled.contentMask.origin.x) == 39 && Double(scrolled.contentMask.origin.y) == 23,
            "the mask is the viewport's rect in its own space, so scrolling must not move it either")

    // `.hidden`, with `.automatic` as its differential in the same fixture.
    do {
        var hidden = proposalScroller(contentHeight: 200).scrollIndicators(.hidden)
        let (hiddenFrame, _) = chromeRendered(&hidden, width: 120, height: 100,
                                              stateTable: chromeScrolledState(chromeRootID, offset: 20,
                                                                              lastScrollTime: 100),
                                              timestamp: 100)
        #expect(hiddenFrame.scene.rects.count == 1,
                "only the content rectangle: content overflows and the fade has not elapsed (age 0), so `.hidden` is the only thing that can suppress the thumb")

        var automatic = proposalScroller(contentHeight: 200)
        let (automaticFrame, _) = chromeRendered(&automatic, width: 120, height: 100,
                                                 stateTable: chromeScrolledState(chromeRootID, offset: 20,
                                                                                 lastScrollTime: 100),
                                                 timestamp: 100)
        #expect(automaticFrame.scene.rects.count == 2,
                "the same fixture under `.automatic` must paint the thumb, or the assertion above proves nothing")
    }
}

// MARK: - 1.4 One chrome, two elements

/// **Test 1.4.** The property the fold creates, asserted directly: the same
/// fixture rendered as a `ScrollView` and as a `ProposalScrollView` — same
/// axis, same corner radius, same viewport, same content extent, same stored
/// offset, same timestamps — produces the **same indicator rect, the same
/// colour and the same clamped offset**.
///
/// **Characterization, green at `57893d0`**, and deliberately so: before the
/// fold the two implementations were line-equivalent, and both `lastScroll`
/// seeds (`0` and `-.infinity`) are dead because `StateTable.withState` always
/// runs its closure. There was no discriminator to be red about. What the test
/// guards is the *future*: **mutation M1f** re-inlines a private copy of
/// `ScrollChrome.paintIndicator` into one of the two elements with a different thumb floor,
/// which is exactly the drift the fold exists to prevent, and only this test
/// sees it.
///
/// **The `try #require` that the two viewports agree comes first, and the
/// fixture is built so it can pass.** Divergence 54 is a *cross-axis*
/// difference between exactly these two types (`LR-BC`): a `ScrollView` takes
/// its cross size from its parent where a `ProposalScrollView` takes its
/// content's. Here each scroller is the window root — stored at the full window
/// either way — and the content fills the cross axis at 120, so the two
/// viewports are the same 120×100 rect. A hugging fixture would fail the
/// require rather than pass it.
///
/// The numbers, hand-derived: a stored 999 clamps to `200 − 100 = 100`; the
/// thumb is `max(20, 100 × (100/200)) = 50` and the travel
/// `(100/100) × (100 − 50) = 50`, so the rect is 3×50 at (115, 50); at age 0.2
/// the colour is the scroll-indicator token's own 0.35.
@Test @MainActor func theTwoScrollElementsShareOneChromeImplementation() throws {
    var legacy = ScrollView(.vertical, elementID: chromeListID) {
        Box(style: {
            var s = Style()
            s.size = Size(width: .length(.pixels(Pixels(120))), height: .length(.pixels(Pixels(200))))
            return s
        }())
    }
    let legacyTable = chromeScrolledState(chromeRootID, offset: 999, lastScrollTime: 100)
    let (legacyFrame, legacyLayout) = chromeRendered(&legacy, width: 120, height: 100,
                                                     stateTable: legacyTable, timestamp: 100.2)

    var proposal = proposalScroller(contentHeight: 200)
    let proposalTable = chromeScrolledState(chromeRootID, offset: 999, lastScrollTime: 100)
    let (proposalFrame, proposalLayout) = chromeRendered(&proposal, width: 120, height: 100,
                                                         stateTable: proposalTable, timestamp: 100.2)

    let legacyViewport = legacyFrame.bounds(of: legacyLayout.node)
    let proposalViewport = proposalFrame.bounds(of: proposalLayout.node)
    try #require(legacyViewport == proposalViewport,
                 "the two chrome implementations can only be compared over one viewport; got \(legacyViewport) and \(proposalViewport)")
    try #require(legacyViewport.size == Size(width: Pixels(120), height: Pixels(100)),
                 "and it must be the hand-derived 120×100, or every number below is measuring something else")
    try #require(legacyFrame.bounds(of: legacyLayout.contentNode).size.height == Pixels(200))
    try #require(proposalFrame.bounds(of: proposalLayout.contentNode).size.height == Pixels(200))

    // The clamp, through each element's own prepaint write-back.
    #expect(legacyTable.peek(chromeRootID, as: ScrollState.self)?.offset == 100)
    #expect(proposalTable.peek(chromeRootID, as: ScrollState.self)?.offset == 100,
            "both elements must clamp a stored 999 to the same 100 and write it back")

    let legacyThumb = try #require(legacyFrame.finalizedScene().rects.last)
    let proposalThumb = try #require(proposalFrame.finalizedScene().rects.last)
    #expect(Double(legacyThumb.bounds.origin.x) == 115 && Double(legacyThumb.bounds.origin.y) == 50,
            "hand-derived: 120 - 5 across, and a travel of (100/100) × (100 - 50) along")
    #expect(Double(legacyThumb.bounds.size.width) == 3 && Double(legacyThumb.bounds.size.height) == 50)
    #expect(Double(proposalThumb.bounds.origin.x) == Double(legacyThumb.bounds.origin.x)
            && Double(proposalThumb.bounds.origin.y) == Double(legacyThumb.bounds.origin.y),
            "one implementation, so the two thumbs must sit at the same point")
    #expect(Double(proposalThumb.bounds.size.width) == Double(legacyThumb.bounds.size.width)
            && Double(proposalThumb.bounds.size.height) == Double(legacyThumb.bounds.size.height),
            "and be the same size — a re-inlined copy with a different thumb floor shows up here")
    #expect(proposalThumb.background.a == legacyThumb.background.a
            && proposalThumb.background.l == legacyThumb.background.l,
            "and carry the same colour off the same ramp")
    #expect(abs(Double(legacyThumb.background.a) - 0.35) < 0.001,
            "age 0.2 is inside the fully-opaque window, so the token's own 0.35 — not some other alpha both sides happen to share")
}
