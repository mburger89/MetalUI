import Testing
import Metal
import MetalUICore
import MetalUILayout
import MetalUIPlatform
@testable import MetalUI

private func px(_ v: Float) -> Pixels { Pixels(v) }

private func pt(_ x: Float, _ y: Float) -> Point<Pixels> {
    Point(x: px(x), y: px(y))
}

private func mouseDown(at position: Point<Pixels>) -> InputEvent {
    .mouseDown(MouseEvent(position: position))
}

private func mouseUp(at position: Point<Pixels>) -> InputEvent {
    .mouseUp(MouseEvent(position: position))
}

private func mouseMoved(to position: Point<Pixels>) -> InputEvent {
    .mouseMoved(MouseEvent(position: position))
}

/// Press and release at the same point — the whole gesture, since a click is
/// press-in-then-release-on-the-same-element and neither half alone is one.
@MainActor
private func click(_ platformWindow: FakePlatformWindow, at position: Point<Pixels>) {
    platformWindow.simulateInput(mouseDown(at: position))
    platformWindow.simulateInput(mouseUp(at: position))
}

/// What a handler wrote down, in the order the handlers ran.
///
/// A **reference** type, and that is load-bearing rather than convenient: the
/// content closure `makeFakeWindow` holds runs fresh on every frame and builds a
/// fresh element value each time, so a counter stored on the element itself
/// would be discarded with the element. Nothing survives a frame here except
/// what the closure captured by reference.
private final class ClickLog {
    var names: [String] = []
    var count: Int { names.count }
}

// MARK: - The four the brief names

/// A click inside an `onClick` box's bounds runs its handler exactly once.
///
/// **The `count == 1` is not decoration.** A dispatcher that fired on
/// `.mouseDown` *and* `.mouseUp`, or one that ran every hit rather than the
/// topmost, passes a bare "did it run" assertion and fails this one.
@Test @MainActor func aClickInsideTheBoundsRunsTheHandler() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let log = ClickLog()
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 100) {
        Box().width(px(40)).height(px(40)).onClick { log.names.append("btn") }
    }
    window.drawFrameIfNeeded()

    click(platformWindow, at: pt(20, 20))
    #expect(log.names == ["btn"], "a press and release inside the box is one click")
}

/// A click outside the box's bounds runs nothing.
///
/// The negative control for every assertion above: without it a dispatcher
/// that ignored geometry entirely and ran every registered handler on every
/// `mouseUp` would look correct.
@Test @MainActor func aClickOutsideTheBoundsDoesNotRunTheHandler() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let log = ClickLog()
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 100) {
        Box().width(px(40)).height(px(40)).onClick { log.names.append("btn") }
    }
    window.drawFrameIfNeeded()

    click(platformWindow, at: pt(80, 80))
    #expect(log.count == 0, "the press never landed on the box")
    // And the box really is where this test assumes it is — otherwise the line
    // above would pass against a box that had somehow been laid out at 0x0.
    click(platformWindow, at: pt(20, 20))
    #expect(log.names == ["btn"], "the same fixture does fire inside the bounds")
}

/// Two overlapping handlers: the topmost runs and the lower does not.
///
/// **Two-sided by geometry, not by a single probe.** The outer box is 60x60 and
/// the inner 30x30, both centred by the enclosing `Stack`, so each has a region
/// the other does not cover: an implementation that always answered "outer"
/// reddens at the centre and one that always answered "inner" reddens at the
/// outer box's own corner. A `Stack` layers its children in declaration order,
/// first at the back, so `inner` — declared last — is the one on top.
@Test @MainActor func theTopmostOfTwoOverlappingHandlersRuns() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let log = ClickLog()
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 100) {
        Stack {
            Box().width(px(60)).height(px(60)).onClick { log.names.append("outer") }
            Box().width(px(30)).height(px(30)).onClick { log.names.append("inner") }
        }
    }
    window.drawFrameIfNeeded()

    // Centred in a 100x100 window: outer covers 20..80, inner covers 35..65.
    click(platformWindow, at: pt(50, 50))
    #expect(log.names == ["inner"], "the topmost handler runs and the lower one does not")

    click(platformWindow, at: pt(25, 25))
    #expect(log.names == ["inner", "outer"],
            "outside the inner box the outer one is the only candidate")
}

/// A handler registered on frame N runs for an event arriving before frame
/// N+1 — and it is **that frame's** handler, not an older one.
///
/// §8.2: "dispatch runs against the most recent frame's handler set". The tree
/// is rebuilt every frame, so the closure a click runs is one of a series of
/// distinct closures, and a dispatcher holding the first one it ever saw would
/// pass a single-frame test. Flipping the toggle between the two frames is what
/// tells those two implementations apart.
@Test @MainActor func aHandlerRegisteredOnFrameNRunsForAnEventBeforeFrameNPlusOne() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let log = ClickLog()
    let label = LabelBox()
    label.name = "v1"
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 100) {
        Box().width(px(40)).height(px(40)).onClick { log.names.append(label.name) }
    }

    window.drawFrameIfNeeded()
    click(platformWindow, at: pt(20, 20))
    #expect(log.names == ["v1"], "frame 1's handler runs for an event arriving after frame 1")

    label.name = "v2"
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    click(platformWindow, at: pt(20, 20))
    #expect(log.names == ["v1", "v2"],
            "frame 2 replaced the handler set; the click runs frame 2's closure")
}

/// A mutable name the content closure reads fresh on every frame, so frame 2's
/// element carries a different handler from frame 1's. A class for `ClickLog`'s
/// reason — the closure runs again per frame and must see the current value,
/// not one captured when the window was made.
private final class LabelBox {
    var name = ""
}

// MARK: - A click is press-then-release-on-the-same-element

/// Pressing one element and releasing over another is not a click on either.
///
/// **This is what "resolve the hitbox under the `mouseUp` point and require it
/// to be the pressed `GlobalElementID`" buys, and nothing else here can see
/// it.** A dispatcher that fired on whatever the release landed on would run
/// `right`; one that fired on whatever the press landed on would run `left`.
/// Both are wrong and both pass every other test in this file.
@Test @MainActor func aPressOnOneElementReleasedOnAnotherIsNotAClick() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let log = ClickLog()
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 100) {
        Row {
            Box().width(px(40)).height(px(40)).onClick { log.names.append("left") }
            Box().width(px(40)).height(px(40)).onClick { log.names.append("right") }
        }
    }
    window.drawFrameIfNeeded()

    // A `Row` in a 100x100 window lays the two 40-wide boxes at x 0..40 and
    // 40..80, centred vertically at y 30..70.
    platformWindow.simulateInput(mouseDown(at: pt(20, 50)))
    platformWindow.simulateInput(mouseUp(at: pt(60, 50)))
    #expect(log.count == 0, "neither the pressed element nor the released one is clicked")

    // The positive control: the same two points each click their own box.
    click(platformWindow, at: pt(20, 50))
    click(platformWindow, at: pt(60, 50))
    #expect(log.names == ["left", "right"], "the fixture's two boxes are where this assumes")
}

/// A click on a child with its own handler runs the child's and **not** its
/// container's — the container does not also fire, and does not fire instead.
///
/// **Two independent properties in one fixture, and the second was found by
/// mutation.** The first is the no-chaining rule stated at `Handlers`: dispatch
/// stops at one hitbox, so a container's `onClick` never sees a click its child
/// took. The second is registration *order*: `Box.prepaint` registers its own
/// click target **before** recursing into its children, so a child's hitbox
/// takes a later index and `topmostOpaqueHitbox` — which breaks a layer tie by
/// registration index — ranks it above its parent, matching the fact that a
/// child paints over its parent. Moving that call after the recursion left the
/// whole 655-test suite green before this test existed; under that mutant the
/// first assertion below reads `["outer"]`.
@Test @MainActor func aNestedHandlerWinsOverItsContainerWhichDoesNotAlsoFire() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let log = ClickLog()
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 100) {
        Box {
            Box().width(px(30)).height(px(30)).onClick { log.names.append("inner") }
        }
        .width(px(60)).height(px(60)).onClick { log.names.append("outer") }
    }
    window.drawFrameIfNeeded()

    // The child sits at (0, 0) 30x30 inside a container at (0, 0) 60x60, so
    // this point is inside both.
    click(platformWindow, at: pt(10, 10))
    #expect(log.names == ["inner"],
            "the child took the click, and the container did not also receive it")

    // The differential: the container's own uncovered area still clicks it, so
    // the line above is about ranking rather than about a dead container.
    click(platformWindow, at: pt(45, 45))
    #expect(log.names == ["inner", "outer"], "outside the child, the container wins")
}

/// The same two properties for `Stack`, whose `prepaint` is a hand-copied
/// sibling of `Box`'s rather than a call into it.
///
/// **A separate test because the line is a separate line.** `Stack` does not
/// wrap a `Box` the way `Column`/`Row` do — its own doc says its stored
/// properties already match `Box`'s and there is nothing to delegate — so its
/// `registerHandlers` call is a second copy that can drift. Measured: moving
/// `Stack`'s call after its recursion left the 657-test suite green with the
/// `Box` version of this test present, so one test cannot stand for both.
@Test @MainActor func aNestedHandlerWinsOverItsContainingStackToo() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let log = ClickLog()
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 100) {
        Stack {
            Box().width(px(30)).height(px(30)).onClick { log.names.append("inner") }
        }
        .width(px(60)).height(px(60)).onClick { log.names.append("outer") }
    }
    window.drawFrameIfNeeded()

    // A `Stack` centres its children, so the 30x30 child sits at (15, 15) inside
    // a 60x60 stack rooted at (0, 0).
    click(platformWindow, at: pt(30, 30))
    #expect(log.names == ["inner"], "the child ranks above the stack that contains it")

    click(platformWindow, at: pt(5, 5))
    #expect(log.names == ["inner", "outer"], "outside the child, the stack wins")
}

/// A press on the LOWER of two overlapping handlers, released over the upper
/// one, is not a click on either.
///
/// **This is the sibling-swap `aPressOnOneElementReleasedOnAnotherIsNotAClick`
/// cannot make, and it was found by mutation rather than by reading.** That
/// test's two boxes sit side by side, so the release point contains exactly one
/// hitbox and "the topmost hit is the pressed one" and "some hit is the pressed
/// one" are the same question. Here they differ: the release point contains
/// *both* boxes, and the pressed one is the lower of the two. Measured — the
/// brief's own suggested mutation, "dispatch to all hits rather than the
/// topmost", left the whole 655-test suite green, because the pressed-id guard
/// already narrows every other fixture to one candidate. Under that mutant this
/// test fires `outer`; under the shipped code it fires nothing.
@Test @MainActor func aPressReleasedOverSomethingCoveringItIsNotAClick() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let log = ClickLog()
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 100) {
        Stack {
            Box().width(px(60)).height(px(60)).onClick { log.names.append("outer") }
            Box().width(px(30)).height(px(30)).onClick { log.names.append("inner") }
        }
    }
    window.drawFrameIfNeeded()

    // Press on the outer box's own corner (25, 25), release at the centre
    // (50, 50) — which is inside BOTH boxes, with the inner one on top.
    platformWindow.simulateInput(mouseDown(at: pt(25, 25)))
    platformWindow.simulateInput(mouseUp(at: pt(50, 50)))
    #expect(log.count == 0,
            "the release landed on `inner`, so the press on `outer` is not a click")

    // The positive control, so the line above cannot pass against a fixture in
    // which nothing is clickable at all.
    click(platformWindow, at: pt(25, 25))
    #expect(log.names == ["outer"], "the same press point does click when released on itself")
}

/// A press that leaves the element and returns still fires — §3.4's stated
/// reason for keying `active` by `GlobalElementID` rather than by index.
@Test @MainActor func aPressThatLeavesTheElementAndReturnsStillClicks() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let log = ClickLog()
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 100) {
        Box().width(px(40)).height(px(40)).onClick { log.names.append("btn") }
    }
    window.drawFrameIfNeeded()

    platformWindow.simulateInput(mouseDown(at: pt(20, 20)))
    platformWindow.simulateInput(mouseMoved(to: pt(90, 90)))
    platformWindow.simulateInput(mouseMoved(to: pt(20, 20)))
    platformWindow.simulateInput(mouseUp(at: pt(20, 20)))
    #expect(log.names == ["btn"], "the press was never released elsewhere, so it is one click")
}

/// A `mouseUp` with no press before it — the pointer entered the window
/// already held down, or a press was consumed elsewhere — is not a click.
///
/// The guard this pins is `active` being `nil`: without it, a dispatcher that
/// only compared "is there a handler under the release point" would fire.
@Test @MainActor func aReleaseWithNoPressIsNotAClick() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let log = ClickLog()
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 100) {
        Box().width(px(40)).height(px(40)).onClick { log.names.append("btn") }
    }
    window.drawFrameIfNeeded()

    platformWindow.simulateInput(mouseUp(at: pt(20, 20)))
    #expect(log.count == 0, "a release with nothing active is not a click")
}

// MARK: - Registration is what `onClick` buys, and only `onClick`

/// A `Box` with no `onClick` registers no hitbox; the same `Box` with one
/// registers exactly one, opaque, at its own bounds.
///
/// **The decision this pins is that `onClick` is the gate.** Registering a
/// hitbox for every `Box` would be simpler, and it would also make every box in
/// a `ScrollView` swallow that scroller's wheel (Task 7's fold: a wheel stops
/// at the topmost opaque hitbox and scrolls only if that hitbox is a scroller),
/// which is the measured reason the gate exists rather than a preference.
@Test @MainActor func onlyABoxWithAHandlerRegistersAHitbox() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (plain, _) = try makeFakeWindow(device: device, size: 100) {
        Box().width(px(40)).height(px(40))
    }
    plain.drawFrameIfNeeded()
    #expect(plain.lastHitboxes.isEmpty, "a Box with no handler is not a hit target")

    let (clickable, _) = try makeFakeWindow(device: device, size: 100) {
        Box().width(px(40)).height(px(40)).onClick {}
    }
    clickable.drawFrameIfNeeded()
    let boxes = try #require(clickable.lastHitboxes.count == 1 ? clickable.lastHitboxes : nil,
                             "onClick registers exactly one hitbox, got \(clickable.lastHitboxes.count)")
    #expect(boxes[0].opaque, "a click target consumes the point")
    #expect(boxes[0].scroll == nil, "it is not a scroller")
    #expect(boxes[0].bounds == Bounds(origin: pt(0, 0),
                                      size: Size(width: px(40), height: px(40))),
            "registered at the box's own resolved bounds")
}

/// `onClick` reaches every `StyledElement` conformer that can register one, and
/// each of them actually does.
///
/// **Written as one test over four types on purpose.** `handlers` is a protocol
/// requirement, so `onClick` compiles on every conformer the day it lands; a
/// conformer whose `prepaint` forgets to register is then an API that exists,
/// compiles and does nothing — the shape CLAUDE.md's declared-and-inert table
/// exists to keep out. Only a per-conformer check can see that, and a
/// conformer added later without one is a row in that table.
@Test @MainActor func onClickIsLiveOnEveryConformerThatCanRegisterOne() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let log = ClickLog()

    func fires(_ name: String, _ content: @escaping @MainActor () -> some Element) throws {
        let (window, platformWindow) = try makeFakeWindow(device: device, size: 100, content: content)
        window.drawFrameIfNeeded()
        click(platformWindow, at: pt(20, 20))
        #expect(log.names == [name], "\(name): onClick compiled but registered nothing")
        log.names.removeAll()
    }

    try fires("box") { Box().width(px(40)).height(px(40)).onClick { log.names.append("box") } }
    try fires("column") { Column { Box().width(px(40)).height(px(40)) }
        .width(px(40)).height(px(40)).onClick { log.names.append("column") } }
    try fires("row") { Row { Box().width(px(40)).height(px(40)) }
        .width(px(40)).height(px(40)).onClick { log.names.append("row") } }
    try fires("stack") { Stack { Box().width(px(40)).height(px(40)) }
        .width(px(40)).height(px(40)).onClick { log.names.append("stack") } }
    try fires("text") { Text("Hi").width(px(40)).height(px(40))
        .onClick { log.names.append("text") } }
    try fires("list") {
        List([Datum(id: 0)], rowHeight: px(40)) { _ in Box() }
            .width(px(40)).height(px(40)).onClick { log.names.append("list") }
    }
}

private struct Datum: Identifiable { let id: Int }

// MARK: - The accepted cost (recorded, not fixed)

/// **An `onClick` inside a `ScrollView` swallows that scroller's wheel.** This
/// test asserts the behaviour this framework has today, which is *not* what a
/// browser does — it is pinned so the cost is a decision a reader can find
/// rather than a surprise, exactly as the divergence pins in `ListTests` and
/// `AbsolutePositioningTests` are.
///
/// The mechanism is Task 7's fold: a wheel event stops at the topmost **opaque**
/// hitbox under the pointer and scrolls only if that hitbox is itself a
/// scroller. A click target registers opaque — it must, or a modal scrim could
/// not swallow clicks aimed at what it covers — so a button inside a scroller
/// blocks the wheel over its own rect. The named fix, deliberately not made
/// here, is at `Window.applyScroll`: a wheel should stop at an opaque hitbox
/// only when that hitbox is on a **higher layer** than the topmost scroller
/// under the same point, which the layer already on every `Hitbox` decides with
/// no ancestor walk.
///
/// Whoever implements that gets a red test here and should invert it.
@Test @MainActor func aClickTargetInsideAScrollViewSwallowsTheWheel() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    var rowStyle = Style()
    rowStyle.size = Size(width: .auto, height: .length(.pixels(px(40))))
    // A `Box(style:)` column rather than the public `Column`, so the rows keep
    // the engine's `stretch` default and fill the viewport's width — the idiom
    // `ScrollRoutingTests` uses, and for the same reason.
    var column = Style()
    column.flexDirection = .column
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 100) {
        ScrollView(.vertical, elementID: ElementID("list")) {
            Box(style: column) {
                Box(style: rowStyle).onClick {}
                Box(style: rowStyle); Box(style: rowStyle); Box(style: rowStyle)
            }
        }
    }
    window.drawFrameIfNeeded()
    let scroller = GlobalElementID.child(of: nil, at: 0, name: ElementID("list"))

    // Over the button: swallowed, and the scroller does not move.
    platformWindow.simulateInput(
        .scrollWheel(ScrollEvent(position: pt(20, 20),
                                 delta: Point(x: px(0), y: px(-37)))))
    var offset = 0.0
    window.stateTable.withState(scroller, initial: ScrollState()) { offset = $0.offset }
    #expect(offset == 0,
            "TODAY'S BEHAVIOUR, not the desired one: the click target swallowed the wheel")

    // The differential: the identical event below the button scrolls normally,
    // so the line above is about the button and not about the scroller.
    platformWindow.simulateInput(
        .scrollWheel(ScrollEvent(position: pt(20, 60),
                                 delta: Point(x: px(0), y: px(-37)))))
    window.stateTable.withState(scroller, initial: ScrollState()) { offset = $0.offset }
    #expect(offset == 37, "the same wheel event off the button reaches the scroller")
}

// MARK: - Dispatch claims the event

/// A click that runs a handler does not also reach `Window.onInput`, and one
/// that runs nothing does.
///
/// The same shape `applyScroll` already has: an element that consumed the point
/// consumed the event, and re-offering it to the window's own fallback handler
/// would be half a swallow.
@Test @MainActor func aDispatchedClickDoesNotAlsoReachTheWindowsRawHandler() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let log = ClickLog()
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 100) {
        Box().width(px(40)).height(px(40)).onClick { log.names.append("btn") }
    }
    window.drawFrameIfNeeded()
    var raw: [String] = []
    window.onInput = { event in
        if case .mouseUp = event { raw.append("up") }
        return false
    }

    click(platformWindow, at: pt(20, 20))
    #expect(log.names == ["btn"])
    #expect(raw.isEmpty, "the click was claimed, so the raw handler never saw the release")

    click(platformWindow, at: pt(90, 90))
    #expect(log.names == ["btn"], "nothing under the pointer, so no handler ran")
    #expect(raw == ["up"], "and the unclaimed release fell through to the raw handler")
}
