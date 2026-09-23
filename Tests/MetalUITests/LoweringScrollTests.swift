import Testing
import Metal
import MetalUICore
@testable import MetalUILayout
import MetalUIRender
@testable import MetalUIText
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
// than as drift. Their evidence is their mutations (record §25, lane 1), not a
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
        // The frame request, not only the rect. **Found by mutation M1d**: with
        // the `.hidden` guard moved below `pass.requestAnotherFrame()` the rect
        // count above is unchanged — the guard still returns before the fill —
        // and only this assertion sees it. A hidden scroller that kept asking
        // would hold the display link awake forever, spec §4.4's exit criterion.
        // `ScrollView`'s half is `hiddenIndicatorDoesNotKeepTheWindowDirtyOrTheLinkAwake`.
        #expect(!hiddenFrame.wantsAnotherFrame,
                "`.hidden` must return before `requestAnotherFrame()`, not merely before the fill")

        var automatic = proposalScroller(contentHeight: 200)
        let (automaticFrame, _) = chromeRendered(&automatic, width: 120, height: 100,
                                                 stateTable: chromeScrolledState(chromeRootID, offset: 20,
                                                                                 lastScrollTime: 100),
                                                 timestamp: 100)
        #expect(automaticFrame.scene.rects.count == 2,
                "the same fixture under `.automatic` must paint the thumb, or the assertion above proves nothing")
        #expect(automaticFrame.wantsAnotherFrame,
                "and must ask for the frames that fade it, or the `.hidden` assertion above proves nothing")
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
/// `ScrollChrome.paintIndicator` into one of the two elements with a different
/// thumb floor, which is exactly the drift the fold exists to prevent.
///
/// **Two content heights, because one of them cannot see that mutation.** The
/// first writing used a single 200pt content behind a 100pt viewport, where the
/// thumb is the proportional `100 × (100/200) = 50` and the 20pt floor is
/// inactive — so a re-inlined copy with a **30**pt floor answers the same 50 and
/// M1f left this test green while reddening 1.2 (practices shape 2, a fixture
/// too shallow to distinguish two implementations). The 1000pt arm is where the
/// floor bites: `100 × (100/1000) = 10`, floored to 20, against a drifted
/// copy's 30.
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
/// The numbers, hand-derived, for a stored 999 at age 0.2:
///
/// | content | clamped offset | thumb | travel | thumb rect |
/// |---|---|---|---|---|
/// | 200 | `200 − 100 = 100` | `max(20, 50) = 50` | `(100/100) × (100 − 50) = 50` | (115, 50) 3×50 |
/// | 1000 | `1000 − 100 = 900` | `max(20, 10) = 20` | `(900/900) × (100 − 20) = 80` | (115, 80) 3×20 |
///
/// 115 is `120 − 5` on both, and the colour is the scroll-indicator token's own
/// 0.35 (age 0.2 is inside the fully-opaque window).
@Test @MainActor func theTwoScrollElementsShareOneChromeImplementation() throws {
    func fixedBox(_ height: Float) -> Style {
        var s = Style()
        s.size = Size(width: .length(.pixels(Pixels(120))), height: .length(.pixels(Pixels(height))))
        return s
    }

    for (contentHeight, clamped, thumbY, thumbHeight) in
        [(Float(200), 100.0, 50.0, 50.0), (Float(1000), 900.0, 80.0, 20.0)] {
        var legacy = ScrollView(.vertical, elementID: chromeListID) {
            Box(style: fixedBox(contentHeight))
        }
        let legacyTable = chromeScrolledState(chromeRootID, offset: 999, lastScrollTime: 100)
        let (legacyFrame, legacyLayout) = chromeRendered(&legacy, width: 120, height: 100,
                                                         stateTable: legacyTable, timestamp: 100.2)

        var proposal = proposalScroller(contentHeight: contentHeight)
        let proposalTable = chromeScrolledState(chromeRootID, offset: 999, lastScrollTime: 100)
        let (proposalFrame, proposalLayout) = chromeRendered(&proposal, width: 120, height: 100,
                                                             stateTable: proposalTable, timestamp: 100.2)

        let legacyViewport = legacyFrame.bounds(of: legacyLayout.node)
        let proposalViewport = proposalFrame.bounds(of: proposalLayout.node)
        try #require(legacyViewport == proposalViewport,
                     "the two chrome implementations can only be compared over one viewport; got \(legacyViewport) and \(proposalViewport)")
        try #require(legacyViewport.size == Size(width: Pixels(120), height: Pixels(100)),
                     "and it must be the hand-derived 120×100, or every number below is measuring something else")
        try #require(legacyFrame.bounds(of: legacyLayout.contentNode).size.height == Pixels(contentHeight))
        try #require(proposalFrame.bounds(of: proposalLayout.contentNode).size.height == Pixels(contentHeight))

        // The clamp, through each element's own prepaint write-back.
        #expect(legacyTable.peek(chromeRootID, as: ScrollState.self)?.offset == clamped)
        #expect(proposalTable.peek(chromeRootID, as: ScrollState.self)?.offset == clamped,
                "both elements must clamp a stored 999 to the same \(clamped) and write it back")

        let legacyThumb = try #require(legacyFrame.finalizedScene().rects.last)
        let proposalThumb = try #require(proposalFrame.finalizedScene().rects.last)
        #expect(Double(legacyThumb.bounds.origin.x) == 115
                && Double(legacyThumb.bounds.origin.y) == thumbY,
                "hand-derived: 120 - 5 across, and a travel of \(thumbY) along")
        #expect(Double(legacyThumb.bounds.size.width) == 3
                && Double(legacyThumb.bounds.size.height) == thumbHeight,
                "and a \(thumbHeight)pt thumb — the 1000pt arm is the one where the 20pt floor decides it")
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
}

// MARK: - Lane 2: the `ScrollView` lowering (`LR-BB`, `LR-BC`)
//
// Under the proposal authority `ScrollView.requestLayout` stops reporting
// `scrollView.noLowering` and registers, in the same order and under the same
// ids as the legacy branch: the content children, a **content node** through
// stage 2's `lowerLegacyNode` at site `scrollView` with a style carrying only
// `flexDirection`, and a **viewport** through
// `Frame.requestNativeScrollViewport`, recorded as the element's own
// `LoweredItem` so a lowered container above it stretches or grows it as the
// legacy flex line did.
//
// Every test below is RED at lane 1's HEAD: each renders a tree holding a
// `ScrollView` under the proposal authority with diagnostics on, so the report
// carries `scrollView.noLowering` and the viewport and content rects are the
// 0×0 leaf `Frame.unlowerable` returns.

private func lane2Px(_ v: Float) -> Pixels { Pixels(v) }

private func lane2Bounds(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> Bounds<Pixels> {
    Bounds(origin: Point(x: Pixels(x), y: Pixels(y)), size: Size(width: Pixels(w), height: Pixels(h)))
}

private let lane2Root = GlobalElementID.child(of: nil, at: 0, name: nil)

private func lane2Child(_ parent: GlobalElementID, _ index: Int) -> GlobalElementID {
    GlobalElementID.child(of: parent, at: index, name: nil)
}

private func lane2Field(_ site: LoweringSite, _ name: String) -> UnlowerableField {
    UnlowerableField(site: site, field: name)
}

/// A fixed-size childless `Box` — the one shape that can carry an item field.
@MainActor
private func lane2Fixed(_ w: Float, _ h: Float) -> Box<EmptyGroup> {
    Box().width(lane2Px(w)).height(lane2Px(h))
}

/// Every whole-frame observation agrees and nothing was reported.
@MainActor
private func lane2ExpectAgreement(_ r: LayoutDifferential.Report, _ arm: String,
                                  sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(r.unlowerable.isEmpty, "\(arm): \(r.unlowerable)", sourceLocation: sourceLocation)
    #expect(r.disagreeing.isEmpty, "\(arm): \(r.disagreeing)", sourceLocation: sourceLocation)
    #expect(r.legacyOnly.isEmpty && r.loweredOnly.isEmpty,
            "\(arm): legacyOnly \(r.legacyOnly) loweredOnly \(r.loweredOnly)", sourceLocation: sourceLocation)
    #expect(r.scenesEqual, "\(arm): scenes", sourceLocation: sourceLocation)
    #expect(r.hitboxesEqual, "\(arm): hitboxes", sourceLocation: sourceLocation)
    #expect(r.accessibilityEqual, "\(arm): accessibility", sourceLocation: sourceLocation)
    #expect(r.stateSlotsEqual, "\(arm): state slots", sourceLocation: sourceLocation)
}

// MARK: - 2.1 The bounded shapes, where the two authorities agree

/// **Test 2.1** (`LR-BB`). The five prototype-P4 arms in which the lowered
/// `ScrollView` and the legacy one agree in **every** observation — element
/// rects, the emitted and finalized scenes, the hitbox list (a scroll region is
/// a hitbox with an axis), the accessibility records and the `StateTable` ids —
/// with the id count of each `try #require`d, derived by hand here before the
/// first run.
///
/// | arm | shape | ids |
/// |---|---|---|
/// | **A1** | `Box { ScrollView(.vertical) { 3 × 80×40 } }.width(80).height(60)` | root, `Box`, `ScrollView`, 3 leaves = **6** |
/// | **A2** | the demo's own spelling: the scroller `Box` `.width(80).flexGrow(1).flexBasis(0).minHeight(0)` as the second child of a stretching 120×120 column | root, column, the 20×10 sibling, `Box`, `ScrollView`, 3 leaves = **8** |
/// | **A2b** | A1's shape whose **content** carries an item field — a second row `.alignSelf(.center)` — so the arm can tell `lowerLegacyNode` from a bare stack | root, `Box`, `ScrollView`, 2 children = **5** |
/// | **A5** | content (50×30) **smaller** than a 100×100 viewport | root, `Box`, `ScrollView`, leaf = **4** |
/// | **A8** | content **wider** than a vertical viewport (160×30 in 80×60) | **4** |
/// | **A9** | a `ScrollView` inside a `ScrollView` | root, `Box`, outer, inner, 3 leaves = **7** |
///
/// **Why each agrees is a different sentence, which is why there are five.**
/// A1 and A5 and A8: the scroller's parent declares a cross size, so stage 2
/// wraps the lowered viewport in a stretch item frame and the alias reports
/// that frame's rect — the same number the legacy flex line stretched to.
/// **A2 is the one that shows the two mechanisms are not the same**: the
/// scroller `Box` declares no height, so stage 2's single-child stretch elision
/// (`LR-AC`) leaves the `ScrollView` unstretched, and the lowered viewport
/// still fills its 110pt allocation — because it answers its **proposal** on
/// the scrolling axis (`LR-BC`), not because anything stretched it. A9 is the
/// nested case, where the inner viewport's scrolling axis is proposed `nil` by
/// the outer content stack and it answers its content's own 120.
///
/// **A2b exists because M2b reddened nothing here on its first run.** The
/// design predicted that registering the content through
/// `requestNativeLinearStack` instead of `lowerLegacyNode` would move "A2's
/// stretch rows"; it does not, because every other arm's scroll content is
/// fixed-size leaves that record no item field, so the container lowering's
/// `planLegacyItems`, `arrangeLegacyMainAxis` and `paddedAndSized` are all
/// no-ops over them and a bare stack produces the identical geometry. A2b gives
/// the content one child that declares `alignSelf(.center)`: the legacy content
/// column centres it in the column's 80, and only `lowerLegacyNode`'s alignment
/// frame reproduces that — a bare stack leaves it at x 0 and leaves its record
/// unconsumed as well.
///
/// **Every leaf's cross size equals its container's, deliberately.**
/// `ProbeLeaf` registers a raw native leaf and records no `LoweredItem`, so no
/// lowered container ever stretches it, where the legacy container stretches it
/// like any other flex item. A fixture whose leaves are narrower (or shorter)
/// than the content node would therefore disagree on the **probe type**, not on
/// the scroller — 2.3 hit exactly that on the first full run. Here the three
/// 80×40 leaves sit in an 80-wide column, A5's 50×30 in a 50-wide one, and so on,
/// so the legacy stretch is a no-op and the arms measure the viewport alone.
///
/// Mutations that must redden it: **M2a** the viewport registered as a plain
/// native leaf (A1's content rects collapse); **M2b** the content node
/// registered through `requestNativeLinearStack` directly instead of
/// `lowerLegacyNode` (A2's rows move).
@MainActor
@Test func aLoweredScrollViewAgreesWithTheLegacyEngineOnEveryBoundedShape() throws {
    let a1 = LayoutDifferential.compare(width: 200, height: 200) {
        Box {
            ScrollView(.vertical) {
                ProbeLeaf(width: 80, height: 40)
                ProbeLeaf(width: 80, height: 40)
                ProbeLeaf(width: 80, height: 40)
            }
        }
        .width(lane2Px(80)).height(lane2Px(60))
    }
    try #require(a1.elements == 6, "A1 ids: \(a1.elements)")
    lane2ExpectAgreement(a1, "A1")

    let a2 = LayoutDifferential.compare(width: 200, height: 200) {
        Column {
            lane2Fixed(20, 10)
            Box {
                ScrollView(.vertical) {
                    ProbeLeaf(width: 80, height: 40)
                    ProbeLeaf(width: 80, height: 40)
                    ProbeLeaf(width: 80, height: 40)
                }
            }
            .width(lane2Px(80)).flexGrow(1).flexBasis(lane2Px(0)).minHeight(lane2Px(0))
        }
        .alignItems(.stretch).width(lane2Px(120)).height(lane2Px(120))
    }
    try #require(a2.elements == 8, "A2 ids: \(a2.elements)")
    lane2ExpectAgreement(a2, "A2")
    // The number the arm exists for: the scroller is 110 tall on BOTH sides
    // (120 − the 10pt sibling), and the lowered one gets there without a
    // stretch wrapper.
    let a2Column = lane2Child(lane2Root, 0), a2Scroller = lane2Child(a2Column, 1)
    #expect(a2.loweredBounds[lane2Child(a2Scroller, 0)] == lane2Bounds(0, 10, 80, 110),
            "\(String(describing: a2.loweredBounds[lane2Child(a2Scroller, 0)]))")

    // A2b: the content itself carries an item field only the container lowering
    // takes. The second row is 40 wide in an 80-wide content column and
    // `alignSelf(.center)` puts it at x = (80 − 40)/2 = 20 under both
    // authorities; the alignment frame is not aliased, so the element's own rect
    // is still its 40×40 box.
    let a2b = LayoutDifferential.compare(width: 200, height: 200) {
        Box {
            ScrollView(.vertical) {
                lane2Fixed(80, 40)
                lane2Fixed(40, 40).alignSelf(.center)
            }
        }
        .width(lane2Px(80)).height(lane2Px(60))
    }
    try #require(a2b.elements == 5, "A2b ids: \(a2b.elements)")
    lane2ExpectAgreement(a2b, "A2b")
    let a2bScroller = lane2Child(lane2Child(lane2Root, 0), 0)
    #expect(a2b.loweredBounds[lane2Child(a2bScroller, 1)] == lane2Bounds(20, 40, 40, 40),
            "A2b centred row: \(String(describing: a2b.loweredBounds[lane2Child(a2bScroller, 1)]))")

    let a5 = LayoutDifferential.compare(width: 200, height: 200) {
        Box { ScrollView(.vertical) { ProbeLeaf(width: 50, height: 30) } }
            .width(lane2Px(100)).height(lane2Px(100))
    }
    try #require(a5.elements == 4, "A5 ids: \(a5.elements)")
    lane2ExpectAgreement(a5, "A5")

    let a8 = LayoutDifferential.compare(width: 200, height: 200) {
        Box { ScrollView(.vertical) { ProbeLeaf(width: 160, height: 30) } }
            .width(lane2Px(80)).height(lane2Px(60))
    }
    try #require(a8.elements == 4, "A8 ids: \(a8.elements)")
    lane2ExpectAgreement(a8, "A8")

    let a9 = LayoutDifferential.compare(width: 200, height: 200) {
        Box {
            ScrollView(.vertical) {
                ScrollView(.vertical) {
                    ProbeLeaf(width: 80, height: 40)
                    ProbeLeaf(width: 80, height: 40)
                    ProbeLeaf(width: 80, height: 40)
                }
            }
        }
        .width(lane2Px(80)).height(lane2Px(60))
    }
    try #require(a9.elements == 7, "A9 ids: \(a9.elements)")
    lane2ExpectAgreement(a9, "A9")
}

// MARK: - 2.2 The scrolling axis fills, where the legacy viewport hugs

/// **Test 2.2** — a **divergence pin** (`LR-BC`). The lowered viewport answers
/// its **proposal** on the scrolling axis; the legacy one answers whatever the
/// flex line gives it, which for an unconstrained item is its content's size.
/// Probe V1/V2/V3/V4 (stage-3 probe group V) say the fill is SwiftUI's answer:
/// `VStack { 60×30; ScrollView { 60×300 } }` at 200 gives the scroller 162,
/// exactly what a maximally flexible `Color` takes in the same shape, and V5
/// says the hug is reachable there only through `.fixedSize()`.
///
/// Three arms, each `try #require`ing that the two authorities **disagree**
/// before any equality is read:
///
/// - **A7**, a centring `Row` parent 120×100 over a vertical scroller of two
///   50×30: legacy (0, 20) 50×**60** — hugging 60 and centred in the 100pt
///   cross axis — against lowered (0, 0) 50×**100**. Both children move up 20.
/// - **A11**, a centring `Column` parent, the same content: the scroller is now
///   on the column's **main** axis, so the stack offers it the whole 100 and it
///   takes it: legacy (35, 0) 50×60 → lowered (35, 0) 50×100. 35 is
///   `(120 − 50)/2` on both sides, which is the arm's own control — the cross
///   axis does not move.
/// - **A10**, the control that the **cross** axis agrees: the same column with
///   `.alignItems(.stretch)`. The lowered viewport's own cross answer is its
///   content's 50 (`LayoutTree.scrollViewportSize`), and it reads 120 only
///   because it records a `LoweredItem` and stage 2 wraps it in a stretch item
///   frame whose rect the alias reports. Legacy (0, 0) 120×60 → lowered
///   (0, 0) 120×100: **120 on both sides**, and only the scrolling axis moves.
///
/// Mutation that must redden it: **M2c** the viewport lowered as a `fixedSize`
/// over the content — both sides read 60 and every `#require` fails.
@MainActor
@Test func aLoweredScrollViewFillsItsProposalOnTheScrollingAxisWhereTheLegacyViewportHugs() throws {
    let a7 = LayoutDifferential.compare(width: 200, height: 200) {
        Row {
            ScrollView(.vertical) {
                ProbeLeaf(width: 50, height: 30)
                ProbeLeaf(width: 50, height: 30)
            }
        }
        .width(lane2Px(120)).height(lane2Px(100))
    }
    #expect(a7.unlowerable.isEmpty, "A7: \(a7.unlowerable)")
    let a7Scroller = lane2Child(lane2Child(lane2Root, 0), 0)
    try #require(a7.legacyBounds[a7Scroller] != a7.loweredBounds[a7Scroller],
                 "A7: the two authorities agree at \(String(describing: a7.legacyBounds[a7Scroller]))")
    #expect(a7.legacyBounds[a7Scroller] == lane2Bounds(0, 20, 50, 60),
            "A7 legacy: \(String(describing: a7.legacyBounds[a7Scroller]))")
    #expect(a7.loweredBounds[a7Scroller] == lane2Bounds(0, 0, 50, 100),
            "A7 lowered: \(String(describing: a7.loweredBounds[a7Scroller]))")
    #expect(a7.legacyBounds[lane2Child(a7Scroller, 0)] == lane2Bounds(0, 20, 50, 30)
            && a7.legacyBounds[lane2Child(a7Scroller, 1)] == lane2Bounds(0, 50, 50, 30),
            "A7 legacy children")
    #expect(a7.loweredBounds[lane2Child(a7Scroller, 0)] == lane2Bounds(0, 0, 50, 30)
            && a7.loweredBounds[lane2Child(a7Scroller, 1)] == lane2Bounds(0, 30, 50, 30),
            "A7 lowered children: both up 20")

    let a11 = LayoutDifferential.compare(width: 200, height: 200) {
        Column {
            ScrollView(.vertical) {
                ProbeLeaf(width: 50, height: 30)
                ProbeLeaf(width: 50, height: 30)
            }
        }
        .width(lane2Px(120)).height(lane2Px(100))
    }
    #expect(a11.unlowerable.isEmpty, "A11: \(a11.unlowerable)")
    let a11Scroller = lane2Child(lane2Child(lane2Root, 0), 0)
    try #require(a11.legacyBounds[a11Scroller] != a11.loweredBounds[a11Scroller],
                 "A11: the two authorities agree at \(String(describing: a11.legacyBounds[a11Scroller]))")
    #expect(a11.legacyBounds[a11Scroller] == lane2Bounds(35, 0, 50, 60),
            "A11 legacy: \(String(describing: a11.legacyBounds[a11Scroller]))")
    #expect(a11.loweredBounds[a11Scroller] == lane2Bounds(35, 0, 50, 100),
            "A11 lowered: \(String(describing: a11.loweredBounds[a11Scroller]))")

    let a10 = LayoutDifferential.compare(width: 200, height: 200) {
        Column {
            ScrollView(.vertical) {
                ProbeLeaf(width: 50, height: 30)
                ProbeLeaf(width: 50, height: 30)
            }
        }
        .alignItems(.stretch).width(lane2Px(120)).height(lane2Px(100))
    }
    #expect(a10.unlowerable.isEmpty, "A10: \(a10.unlowerable)")
    let a10Scroller = lane2Child(lane2Child(lane2Root, 0), 0)
    try #require(a10.legacyBounds[a10Scroller] != a10.loweredBounds[a10Scroller],
                 "A10: the two authorities agree at \(String(describing: a10.legacyBounds[a10Scroller]))")
    #expect(a10.legacyBounds[a10Scroller] == lane2Bounds(0, 0, 120, 60),
            "A10 legacy: \(String(describing: a10.legacyBounds[a10Scroller]))")
    #expect(a10.loweredBounds[a10Scroller] == lane2Bounds(0, 0, 120, 100),
            "A10 lowered, cross 120 on both sides: \(String(describing: a10.loweredBounds[a10Scroller]))")
}

// MARK: - 2.2a Divergence 54 survives the lowering

/// **Test 2.2a** — a **divergence pin** (`LR-BC` as amended by stage-3 critic
/// round 1, finding 5). The lowering does **not** close divergence 54, and the
/// mechanism is worth a literal rather than a paragraph.
///
/// The kernel viewport's own cross answer is its content's
/// (`LayoutTree.scrollViewportSize`) — the **`ProposalScrollView`** side. A
/// lowered `ScrollView` reads its parent's cross size only because it records a
/// `LoweredItem`: stage 2 wraps it in a stretch item frame and
/// `LoweringState.alias` reports that frame's rect as the element's.
/// `ProposalScrollView` records none — it calls `requestNativeScrollViewport`
/// and never `recordLoweredItem` — so `consume` returns `nil` and it gets no
/// such frame.
///
/// Both as children of ONE stretching lowered `Box` 120×60, both **horizontal**
/// so the scrollers' cross axis is the `Box`'s cross axis, each over a 40×10
/// content. The stack hands each child 60 of the 120pt main axis; the
/// `ScrollView`'s stretch frame then makes it 60×**60** and the
/// `ProposalScrollView` stays 60×**10**.
///
/// **Rendered under the proposal authority only**, not through
/// `LayoutDifferential.compare`: a `ProposalScrollView` inside a legacy `Box`
/// is a native node under a legacy node, which `SA-G` traps on the legacy side.
///
/// Mutation that must redden it: **M2i** `recordLoweredItem` dropped from the
/// lowered `ScrollView` — the two agree at 60×10 and the `#require` fails,
/// which is also how the surviving divergence would silently close.
@MainActor
@Test func divergence54SurvivesTheLoweringBecauseOnlyAScrollViewRecordsAnItem() throws {
    let frame = LayoutDifferential.render(authority: .proposal, width: 200, height: 200) {
        Box {
            ScrollView(.horizontal) { ProbeLeaf(width: 40, height: 10) }
            ProposalScrollView(.horizontal) {
                Rectangle(width: lane2Px(40), height: lane2Px(10), color: .accent)
            }
        }
        .alignItems(.stretch).width(lane2Px(120)).height(lane2Px(60))
    }
    #expect(frame.unlowerableFields.isEmpty, "\(frame.unlowerableFields)")
    let box = lane2Child(lane2Root, 0)
    let legacyScroller = frame.elementBounds[lane2Child(box, 0)]
    let proposalScroller = frame.elementBounds[lane2Child(box, 1)]
    try #require(legacyScroller?.size != proposalScroller?.size,
                 "divergence 54 has closed: both \(String(describing: legacyScroller))")
    #expect(legacyScroller == lane2Bounds(0, 0, 60, 60),
            "the lowered ScrollView takes the line's cross size through its stretch item frame: \(String(describing: legacyScroller))")
    #expect(proposalScroller == lane2Bounds(60, 0, 60, 10),
            "the ProposalScrollView records no item, so it keeps its content's 10: \(String(describing: proposalScroller))")
}

// MARK: - 2.3 A horizontal scroller is bounded by its parent

/// **Test 2.3** — a **divergence pin** (`LR-BC`), arm **A4**.
/// `Box { ScrollView(.horizontal) { 2 × 80×40 } }.width(100).height(40)`: the
/// legacy viewport's automatic minimum floors it at its content's 160 and it
/// **overflows** its 100pt parent; the lowered one answers the 100 it was
/// proposed. Probe V4 is SwiftUI's answer for the horizontal axis (the scroller
/// takes 62 = 100 − 30 − 8 while its 300pt content overflows it).
///
/// `scenesEqual` and `hitboxesEqual` are asserted **false**, with the reason:
/// the viewport's rect is the clip `ScrollView.paint` pushes, so every content
/// rect carries a different `contentMask`; and the scroll region registered in
/// `prepaint` is a hitbox with an axis, so the hitbox list differs too.
///
/// **The parent is 40 tall, not 50, and that is a fixture requirement rather
/// than a choice.** `ProbeLeaf` registers a raw native leaf and records no
/// `LoweredItem`, so `planLegacyItems` gives it no wrapper and **no lowered
/// container ever stretches it** — where the legacy content row stretches it to
/// the viewport's cross size like any other flex item. At a 50pt parent the two
/// leaves read 80×50 legacy against 80×40 lowered and the arm would be measuring
/// the harness's probe type, not the viewport. Giving the parent the leaves' own
/// 40 makes the legacy stretch a no-op, so the content agrees on both sides and
/// the only thing left moving is the window onto it. (The same is true of 2.1's
/// five agreement arms, where every leaf's cross size already equals its
/// container's; found by this assertion failing on the first full run.)
///
/// Mutation that must redden it: **M2c** (the viewport a `fixedSize` over its
/// content).
@MainActor
@Test func aLoweredHorizontalScrollViewIsBoundedByItsParentWhereTheLegacyOneOverflows() throws {
    let a4 = LayoutDifferential.compare(width: 200, height: 200) {
        Box {
            ScrollView(.horizontal) {
                ProbeLeaf(width: 80, height: 40)
                ProbeLeaf(width: 80, height: 40)
            }
        }
        .width(lane2Px(100)).height(lane2Px(40))
    }
    #expect(a4.unlowerable.isEmpty, "A4: \(a4.unlowerable)")
    let scroller = lane2Child(lane2Child(lane2Root, 0), 0)
    try #require(a4.legacyBounds[scroller] != a4.loweredBounds[scroller],
                 "A4: the two authorities agree at \(String(describing: a4.legacyBounds[scroller]))")
    #expect(a4.legacyBounds[scroller] == lane2Bounds(0, 0, 160, 40),
            "A4 legacy — the viewport overflows its 100pt parent: \(String(describing: a4.legacyBounds[scroller]))")
    #expect(a4.loweredBounds[scroller] == lane2Bounds(0, 0, 100, 40),
            "A4 lowered — bounded by construction: \(String(describing: a4.loweredBounds[scroller]))")
    #expect(!a4.scenesEqual,
            "the viewport's rect IS the content clip, so every content rect carries a different mask")
    #expect(!a4.hitboxesEqual,
            "a scroll region is a hitbox with an axis, and it is registered at the viewport's rect")
    // The content itself does not move: both sides lay two 80pt leaves side by
    // side inside the viewport, and only the window onto them changed.
    #expect(a4.legacyBounds[lane2Child(scroller, 1)] == lane2Bounds(80, 0, 80, 40),
            "the second leaf, legacy: \(String(describing: a4.legacyBounds[lane2Child(scroller, 1)]))")
    #expect(a4.loweredBounds[lane2Child(scroller, 1)] == lane2Bounds(80, 0, 80, 40),
            "the second leaf, lowered: \(String(describing: a4.loweredBounds[lane2Child(scroller, 1)]))")
}

// MARK: - 2.4 The content keeps its natural extent

/// **Test 2.4** (`LR-BB`), arm **A6**: `ScrollView(.horizontal) { Text(…) }` in
/// a 100×40 `Box`. The point of the arm is the **width**: the content is
/// measured with the scrolling axis unspecified on both sides, so the `Text`
/// keeps its natural extent inside a viewport a fifth as wide — which is why
/// the legacy content node's `flexShrink: 0` has no counterpart in the lowering
/// and is deliberately not carried (`LR-BB`; the kernel viewport has no freeze
/// loop).
///
/// Both widths are derived from the shaping cache rather than written as
/// literals (`LR-F`), and the arm `try #require`s that the derived width
/// genuinely overflows the viewport, or it would prove nothing.
///
/// The **height** disagrees, 40 → one line, and that is stage 2's single-child
/// stretch elision (`LR-AC`, X9), not a scroll fact: the legacy content row
/// stretches its only child to the viewport's 40, and the lowered content stack
/// does not stretch a single child under a parent with no declared cross size.
/// `accessibilityEqual` is false for the same reason — a `Text`'s accessibility
/// record carries its geometry.
///
/// Mutation that must redden it: **M2d** `flexShrink: 0` carried into the
/// lowered content style. With the content node's record left unconsumed
/// (`LR-BB` as amended) that **reports** `scrollView.flexShrink.unconsumed`.
@MainActor
@Test func aLoweredScrollViewsContentKeepsItsNaturalExtent() throws {
    let sentence = "Scrolling content keeps its own extent"
    let cache = ShapingCache()
    let font = cache.resolveFont(family: nil, size: 13)
    let shaped = cache.shaped(sentence, font: font, wrappingAt: nil)
    let naturalWidth = Float(shaped.widestLine.rounded())
    let lineHeight = Float(shaped.totalHeight.rounded())
    try #require(naturalWidth > 100,
                 "the fixture must overflow its 100pt viewport, or the arm measures nothing: \(naturalWidth)")
    try #require(lineHeight != 40, "and its one line must not already be the viewport's height")

    let a6 = LayoutDifferential.compare(width: 200, height: 200) {
        Box { ScrollView(.horizontal) { Text(sentence) } }
            .width(lane2Px(100)).height(lane2Px(40))
    }
    #expect(a6.unlowerable.isEmpty, "A6: \(a6.unlowerable)")
    let text = lane2Child(lane2Child(lane2Child(lane2Root, 0), 0), 0)
    #expect(a6.legacyBounds[text] == lane2Bounds(0, 0, naturalWidth, 40),
            "A6 legacy text: \(String(describing: a6.legacyBounds[text]))")
    #expect(a6.loweredBounds[text] == lane2Bounds(0, 0, naturalWidth, lineHeight),
            "A6 lowered text: \(String(describing: a6.loweredBounds[text]))")
    #expect(!a6.accessibilityEqual,
            "the text's accessibility record carries its geometry, and the heights differ (LR-AC)")
}

// MARK: - 2.5 The viewport is the element's item, and site `scrollView` stays reachable

/// **Test 2.5** (`LR-BB` as amended, critic round 1 findings 2 and 9). Three
/// things the lowering's bookkeeping owes, none of which any rect above can
/// see:
///
/// **(a) The viewport is recorded as the element's own `LoweredItem`**, so a
/// lowered container above it stretches it exactly as the legacy flex line did,
/// and the alias reaches the element's hitbox and its clip. A **horizontal**
/// scroller in a stretching 100×60 `Box`: the viewport's own answer is
/// 100×**10** (its content's height on the non-scrolling axis), and the stretch
/// item frame makes the element 100×**60** — read three ways, through
/// `elementBounds`, through the registered scroll region and through the
/// `contentMask` the content leaf's rect carries.
///
/// **(b) The content node's record is left UNCONSUMED, and with only
/// `flexDirection` on that style nothing reports.** Asserted structurally: of
/// the two records at site `scrollView`, the `.flex` one (the content node) is
/// unconsumed and the `.leaf` one (the viewport) is consumed by its parent
/// `Box`. An unconsumed record is the truthful state — the viewport lowers no
/// item field of its content — and it is what turns a field a later stage puts
/// on that style into a diagnostic rather than a silent drop.
///
/// **(c) `LoweringSite.scrollView` stays reachable, and this arm produces a
/// report on purpose** rather than asserting the case is live. `lowerLegacyNode`
/// passes `site:` to `planLegacyItems` as `parentSite:`, and the field
/// `planLegacyItems` reports **at the parent's site** is `flexGrow.weights`:
/// two scroller children with unequal declared grow factors report
/// `scrollView.flexGrow.weights`. (The design said an `alignSelf: .baseline`
/// child would report `scrollView.alignSelf`; it does not — every per-child
/// report is raised at `item.site`, the child's own. See `LR-BM`.)
///
/// Mutations that must redden it: **M2e** the content node registered with
/// `site: .modifierLayer` — (c) reads the wrong site; **M2f** the viewport not
/// recorded — (a)'s three readings collapse to 100×10.
@MainActor
@Test func aLoweredScrollViewRecordsItsViewportAsItsItemAndKeepsItsSiteReachable() throws {
    // (a)
    let stretched = LayoutDifferential.render(authority: .proposal, width: 200, height: 200) {
        Box { ScrollView(.horizontal) { ProbeLeaf(width: 40, height: 10) } }
            .alignItems(.stretch).width(lane2Px(100)).height(lane2Px(60))
    }
    #expect(stretched.unlowerableFields.isEmpty, "(a): \(stretched.unlowerableFields)")
    let scroller = lane2Child(lane2Child(lane2Root, 0), 0)
    #expect(stretched.elementBounds[scroller] == lane2Bounds(0, 0, 100, 60),
            "(a) element rect: \(String(describing: stretched.elementBounds[scroller]))")
    let region = try #require(stretched.scrollRegions.first)
    #expect(region.bounds == lane2Bounds(0, 0, 100, 60), "(a) scroll region: \(region.bounds)")
    let contentRect = try #require(stretched.scene.rects.first)
    #expect(Double(contentRect.contentMask.size.height) == 60,
            "(a) the content clip is the stretched viewport: \(contentRect.contentMask)")

    // (b)
    let records = stretched.lowering.order.compactMap { stretched.lowering.items[$0] }
        .filter { $0.site == .scrollView }
    try #require(records.count == 2, "a content node and a viewport: \(records.count)")
    let content = try #require(records.first { if case .flex = $0.kind { true } else { false } })
    let viewport = try #require(records.first { $0.kind == .leaf })
    #expect(!content.consumed, "the content node's record is left unconsumed (LR-BB)")
    #expect(viewport.consumed, "the viewport's record is consumed by its parent Box")
    #expect(viewport.declared == Style(), "the viewport records a default declared style")

    // (c)
    let weights = LayoutDifferential.render(authority: .proposal, width: 200, height: 200) {
        Box {
            ScrollView(.vertical) {
                lane2Fixed(20, 10).flexGrow(1)
                lane2Fixed(20, 10).flexGrow(2)
            }
        }
        .width(lane2Px(80)).height(lane2Px(60))
    }
    #expect(weights.unlowerableFields == [lane2Field(.scrollView, "flexGrow.weights")],
            "(c): \(weights.unlowerableFields)")
    #expect(UnlowerableField(site: .scrollView, field: "flexGrow.weights").owningStage == "3",
            "and the entry still names stage 3")
}

// MARK: - 2.6 Both animation slots survive

/// **Test 2.6** (`LR-BE`). `ScrollView` registers **two** nodes from one element
/// id, so `requestLayout` passes a named child id to `animated(_:_:for:)` per
/// node — `$anim-content` and `$anim-viewport`, which are id PREFIXES, not
/// slots: the stored value ends up at a **grandchild**,
/// `child(child(id, "$anim-content"), "$anim")`. The lowered branch must keep
/// both calls, or a scroller mid-animation would interpolate the viewport's
/// style into the content's.
///
/// Asserted under **both** authorities, with the two ids built by calling the
/// same `scrollViewContentAnimID`/`scrollViewViewportAnimID` the element calls
/// (a test with its own copy of the two string literals cannot catch a rename —
/// `AnimatedStyle.swift`'s own doc records that mistake being made).
///
/// Mutation that must redden it: **M2g** both `animated(…)` calls given the
/// bare `id` (the two slots collapse onto one).
@MainActor
@Test func aLoweredScrollViewKeepsItsTwoAnimationSlots() throws {
    let scroller = lane2Child(lane2Child(lane2Root, 0), 0)
    let contentSlot = animRetentionSlot(for: scrollViewContentAnimID(for: scroller))
    let viewportSlot = animRetentionSlot(for: scrollViewViewportAnimID(for: scroller))
    try #require(contentSlot != viewportSlot, "the two slot ids must differ before anything is read")

    for authority in [LayoutAuthority.legacy, .proposal] {
        let frame = LayoutDifferential.render(authority: authority, width: 200, height: 200) {
            Box { ScrollView(.vertical) { ProbeLeaf(width: 80, height: 40) } }
                .width(lane2Px(80)).height(lane2Px(60))
        }
        let ids = frame.stateTable.ids
        #expect(ids.contains(contentSlot), "\(authority): no $anim-content slot")
        #expect(ids.contains(viewportSlot), "\(authority): no $anim-viewport slot")
    }
}

// MARK: - 2.7 The native work the lowering registers

/// **Test 2.7** (`SA-M`'s method). A1's tree — `Box { ScrollView(.vertical) {
/// 3 × 80×40 } }.width(80).height(60)` in a 200×200 harness root — counted in
/// nodes and in `LayoutTree.lastNativeLayoutWork`, both **derived by hand here
/// before the first run**.
///
/// **The registered tree, 10 nodes.** Each `ProbeLeaf` is one native leaf
/// (`L1`, `L2`, `L3`). The `ScrollView` lowers to a vertical linear stack `SC`
/// (the content node: `lowerLegacyNode` over the three leaves, no padding and
/// no declared size, so `paddedAndSized` adds nothing) inside a scroll viewport
/// `V`. The `Box` stretches its only child on the cross axis — it declares a
/// height, so the single-child elision does not apply — which is one item frame
/// `W`; then its own horizontal stack `SB` and its fixed 80×60 frame `FB`. The
/// harness root is an overlay `O` in a fixed 200×200 frame `R`.
/// 3 + 1 + 1 + 1 + 1 + 1 + 1 + 1 = **10**.
///
/// **Measurement, 10 misses / 0 hits / 3 calls.** `R` at (200, 200) → `O` at
/// (200, 200) → `FB` at (200, 200) → `SB` at (80, 60). `SB` has ONE child, so
/// `solveLinearStack` skips its flexibility probes entirely and offers `W` the
/// whole 80: `W` at (80, 60) → `V` at (80, 60) → `SC` at (80, **nil**) — the
/// scrolling axis is unspecified for the content — where the vertical stack's
/// main axis is nil, so each leaf is measured once at (80, nil). Ten distinct
/// keys, three leaf closures, nothing repeated.
///
/// **Placement, 1 miss / 9 hits.** The root is placed at its answer, then `O`
/// re-measures its children at its OWN size (`CN-E`): `FB` at (80, 60) is a new
/// key — the one placement miss — and everything under it is already cached.
/// The nine hits are `O` (from `R`), `SB` (inside that new `FB`), `SB` again
/// (from placing `FB`), `W` (from `SB`'s re-solve), `V` (from placing `W`),
/// `SC` (from placing `V`) and the three leaves (from `SC`'s re-solve).
///
/// **Totals: 11 misses, 9 hits, 3 calls.**
///
/// Mutation that must redden it: **M2h** the content node registered twice (the
/// node count and the figures move).
@MainActor
@Test func aLoweredScrollViewRegistersAHandDerivedAmountOfNativeWork() throws {
    let frame = LayoutDifferential.render(authority: .proposal, width: 200, height: 200) {
        Box {
            ScrollView(.vertical) {
                ProbeLeaf(width: 80, height: 40)
                ProbeLeaf(width: 80, height: 40)
                ProbeLeaf(width: 80, height: 40)
            }
        }
        .width(lane2Px(80)).height(lane2Px(60))
    }
    try #require(frame.unlowerableFields.isEmpty, "\(frame.unlowerableFields)")
    #expect(frame.tree.nodeCount == 10, "nodes: \(frame.tree.nodeCount)")
    let work = frame.tree.lastNativeLayoutWork
    #expect(work.cacheMisses == 11, "cacheMisses: \(work.cacheMisses)")
    #expect(work.cacheHits == 9, "cacheHits: \(work.cacheHits)")
    #expect(work.measureCalls == 3, "measureCalls: \(work.measureCalls)")
}

// MARK: - Lane 3 (`LR-BI`): `ScrollContext` across a lowered viewport

/// A leaf that records `pass.scrollContext` every time its `requestLayout` runs,
/// on both authorities — `ProbeLeaf`'s shape (`LayoutDifferential.swift`), so it
/// registers a native leaf under the proposal authority and a legacy one under
/// the legacy authority and answers the same size on both.
///
/// `ScrollRoutingTests` has its own copy, `private` to that file. This one exists
/// because 3.5 drives **two windows in one body** and compares them, which that
/// file's parameterised scenarios cannot.
@MainActor
private struct ContextProbe: Element {
    final class Seen { var values: [ScrollContext?] = [] }

    var width: Double = 0
    var height: Double = 0
    let seen: Seen

    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        seen.values.append(pass.scrollContext)
        let w = width, h = height
        if pass.lowersToProposal {
            return (pass.frame.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: w, height: h)) }, ())
        }
        return (pass.requestLeaf(style: Style()) { _, _ in SizeD(width: w, height: h) }, ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                  pass: inout PrepaintPass) {}
    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
               prepaint: inout Void, pass: inout PaintPass) {}
}

@MainActor
private func lane3Column() -> Style {
    var s = Style()
    s.flexDirection = .column
    return s
}

@MainActor
private func lane3Row() -> Style {
    var s = Style()
    s.flexDirection = .row
    return s
}

@MainActor
private func lane3RowFixed(_ w: Float, _ h: Float) -> Style {
    var s = lane3Row()
    s.size = Size(width: .length(.pixels(Pixels(w))), height: .length(.pixels(Pixels(h))))
    return s
}

/// The root: a column the window's own size on both axes.
///
/// **Declared, not left to the root's own answer.** The legacy root takes the
/// frame's definite 120x120; a native root is centred at whatever it measures
/// (`CN-J`), and this column hugs its 60pt of content, so the whole tree would
/// sit 30pt lower under the proposal authority. That is stage 1's root
/// divergence, not this test's subject.
@MainActor
private func lane3Root() -> Style {
    var s = lane3Column()
    s.size = Size(width: .length(.pixels(Pixels(120))), height: .length(.pixels(Pixels(120))))
    return s
}

/// **3.5.** A `ScrollView`'s published `ScrollContext` is the same, frame by
/// frame, across a **lowered** viewport as across a legacy one — and the sibling
/// after it still sees none (ruling `LR-BF`: publication is unchanged by the
/// lowering, because it happens in the shared part of `requestLayout`, before
/// either branch).
///
/// **Two frames, and the second is what makes this non-vacuous.** Frame 1 runs
/// before any `prepaint` has stored a `viewportExtent`, so the context is
/// `(0, 0, .horizontal)` under either authority — a pair of zeros a `ScrollView`
/// publishing nothing at all would also produce. One wheel event of −37 (natural
/// scrolling adds 37) and a second frame make it `(37, 120, …)`: the offset the
/// window wrote, and the viewport extent frame 1's `prepaint` stored, which only
/// `ScrollChrome.resolvedOffset`'s `PrepaintPass` overload ever writes.
///
/// **A HORIZONTAL scroller, and that is the fixture's load-bearing choice.**
/// The scrolling axis has to be an axis on which the two authorities agree, or
/// this test would be re-pinning ruling `LR-BC` instead of the `ScrollContext`.
/// A vertical scroller inside a 100pt-tall wrapper measures **200** under the
/// legacy engine — the viewport hugs its content and overflows the wrapper — and
/// **100** under the proposal authority, which is exactly what test 2.2 above
/// pins. On the CROSS axis of a column the legacy engine stretches the viewport
/// to the parent's definite width and the kernel viewport reports its proposal,
/// and both come out 120: measured on this fixture before the literals below
/// were written.
///
/// **A non-`List` recorder, and that is a correction** (`LR-BI` amended, stage
/// 3's critic round 1 finding 4). The design's first writing windowed a `List`
/// against the two contexts. At the time that was vacuous either way: a `List`
/// under the proposal authority called `noteUnlowerable(.list, "noLowering")`
/// before any row, so through a `Window` it **trapped** and under diagnostics
/// it built zero rows. **Stage 4's lane 2 lowered `List`** (`LR-BQ`), so that
/// reason has expired; the fixture stays as it is because a `ContextProbe`
/// records the context directly, where a `List` would only let it be inferred
/// from which rows were built. `List` windowing under the proposal authority is
/// pinned in `ListLoweringTests.swift`.
///
/// **Both authorities in one body**, rather than as two `@Test` arguments, so
/// the two windows' recordings are compared against each other as well as
/// against the literals.
///
/// Mutations that must redden it: **M3d**, `withScrollContext` moved after the
/// content build (the inside probe sees `nil`); **M3e**, the prepaint overload's
/// `viewportExtent` write removed (frame 2's extent reads 0 on both sides).
@MainActor
@Test func aScrollContextSurvivesALoweredViewportAcrossTwoFrames() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    var recorded: [LayoutAuthority: (inside: [ScrollContext?], after: [ScrollContext?])] = [:]

    for authority in LayoutAuthority.allCases {
        let inside = ContextProbe.Seen(), after = ContextProbe.Seen()
        let (window, platform) = try makeFakeWindow(device: device, size: 120,
                                                    layoutAuthority: authority) {
            Box(style: lane3Root()) {
                ScrollView(.horizontal, elementID: chromeListID) {
                    Box(style: lane3Row()) {
                        Box(style: lane3RowFixed(40, 40)); Box(style: lane3RowFixed(40, 40))
                        Box(style: lane3RowFixed(40, 40)); Box(style: lane3RowFixed(40, 40))
                        Box(style: lane3RowFixed(40, 40))
                        ContextProbe(seen: inside)
                    }
                }
                ContextProbe(width: 120, height: 20, seen: after)
            }
        }
        window.drawFrameIfNeeded()
        // The viewport, read back rather than assumed: 120 is what frame 2's
        // `viewportExtent` must be, and it comes from this rect.
        let region = try #require(window.lastScrollRegions.first)
        #expect(region.axis == .horizontal)
        #expect(region.bounds == Bounds(origin: Point(x: Pixels(0), y: Pixels(0)),
                                        size: Size(width: Pixels(120), height: Pixels(40))),
                "\(authority): the scroller is 120 wide — 5 x 40 of content behind it — on both authorities")

        platform.simulateInput(.scrollWheel(ScrollEvent(
            position: pt(60, 20), delta: Point(x: Pixels(-37), y: Pixels(0)), isMomentum: false)))
        window.drawFrameIfNeeded()
        recorded[authority] = (inside.values, after.values)
    }

    for authority in LayoutAuthority.allCases {
        let seen = try #require(recorded[authority])
        try #require(seen.inside.count == 2, "\(authority): one requestLayout per frame, two frames")
        let first = try #require(seen.inside[0], "\(authority): the probe is inside the scroller")
        #expect(first == ScrollContext(offset: 0, viewportExtent: 0, axis: .horizontal),
                "\(authority): frame 1 — nothing scrolled, no prepaint has stored an extent yet")
        let second = try #require(seen.inside[1])
        #expect(second == ScrollContext(offset: 37, viewportExtent: 120, axis: .horizontal),
                "\(authority): frame 2 — the wheel's 37, and the 120 frame 1's prepaint stored")

        try #require(seen.after.count == 2)
        #expect(seen.after.allSatisfy { $0 == nil },
                "\(authority): the sibling after the scroller is not inside it")
    }
    #expect(recorded[.legacy]?.inside == recorded[.proposal]?.inside,
            "the lowering must not change what a scroller publishes: \(String(describing: recorded))")
}
