import Testing
import Metal
import MetalUICore
import MetalUIPlatform
import MetalUIRender
@testable import MetalUI

/// The storage contract for `@State`, ahead of Task 2's reflection-driven
/// seeding — nothing here calls `bind` except by hand.

@MainActor
@Test func anUnboundStateReturnsItsInitialValueAndDiscardsWrites() throws {
    // An unbound wrapper must not trap — an element constructed outside a
    // frame is legal, and a trap there would make `List(data) { Row($0) }`
    // crash at the point the closure is *built* rather than run.
    let s = State(wrappedValue: 7)
    #expect(s.wrappedValue == 7)
    s.wrappedValue = 9
    #expect(s.wrappedValue == 7, "an unbound write has nowhere to go")
}

@MainActor
@Test func aBoundStateReadsAndWritesTheTableUnderItsOwnSlotID() throws {
    let table = StateTable()
    let owner = GlobalElementID.child(of: nil, at: 0, name: nil)
    let s = State(wrappedValue: 0)
    s.bind(to: table, id: owner, slot: 0)

    s.wrappedValue = 5
    #expect(s.wrappedValue == 5)

    let slotID = GlobalElementID.child(of: owner, at: 0,
                                       name: ElementID("$state0"))
    #expect(table.peek(slotID, as: Int.self) == 5)
}

/// Two slots on one element must not share an entry. The ordinal lives in the
/// NAME, not in `at:` — a name replaces a position rather than joining it
/// (`ElementID.swift:79`), so `at:` is ignored whenever a name is supplied.
@MainActor
@Test func twoSlotsOnOneElementGetDistinctEntries() throws {
    let table = StateTable()
    let owner = GlobalElementID.child(of: nil, at: 0, name: nil)
    let a = State(wrappedValue: 1), b = State(wrappedValue: 2)
    a.bind(to: table, id: owner, slot: 0)
    b.bind(to: table, id: owner, slot: 1)

    a.wrappedValue = 10
    b.wrappedValue = 20
    #expect(a.wrappedValue == 10)
    #expect(b.wrappedValue == 20)
}

/// A slot id can never collide with a positional child's, because positional
/// children carry no name.
@MainActor
@Test func aSlotIDCannotCollideWithAPositionalChild() throws {
    let owner = GlobalElementID.child(of: nil, at: 0, name: nil)
    let slot0 = GlobalElementID.child(of: owner, at: 0, name: ElementID("$state0"))
    let child0 = GlobalElementID.child(of: owner, at: 0, name: nil)
    #expect(slot0 != child0)
}

// MARK: - Task 2: reflection-driven seeding at both element sites

private func px(_ v: Float) -> Pixels { Pixels(v) }

/// The fixtures' 10×10 leaf. Registered natively since stage 6a (record §38,
/// disposition R): these tests are about `@State`, not the leaf's layout, so a
/// test whose tree holds a legacy container runs under the proposal authority.
@MainActor
private func leafNode(_ pass: LayoutPass) -> LayoutNodeID {
    pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }.layoutNodeID
}

/// One `@State` slot that increments itself every `requestLayout`, the same
/// idiom `StateTableTests.CountingElement` uses for `pass.withState` — this is
/// the `@State`-wrapper equivalent.
private struct CounterElement: Element {
    @State var count = 0
    var elementID: ElementID?
    init(elementID: ElementID? = nil) { self.elementID = elementID }

    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Int) {
        count += 1
        return (leafNode(pass), 0)
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                  layout: inout Int, pass: inout PrepaintPass) -> Int { 0 }

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
               layout: inout Int, prepaint: inout Int, pass: inout PaintPass) {}
}

/// A leaf whose `@State` `requestLayout` never touches — deliberately, so the
/// only thing that can keep it alive across a sweep is seeding's own `mark`.
private struct ConditionalReadElement: Element {
    @State var count = 0
    var elementID: ElementID?
    var touch: Bool

    init(elementID: ElementID?, touch: Bool) {
        self.elementID = elementID
        self.touch = touch
    }

    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Int) {
        if touch { count = 42 }
        return (leafNode(pass), 0)
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                  layout: inout Int, pass: inout PrepaintPass) -> Int { 0 }

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
               layout: inout Int, prepaint: inout Int, pass: inout PaintPass) {}
}

/// A distinct type from `CounterElement`, used ONLY by
/// `reflectionRunsOncePerTypeNotOncePerElement` — sharing a type with a test
/// that renders it first would let that test's reflection satisfy this one's
/// cache, making the count assertion pass for the wrong reason regardless of
/// test order.
private struct ReflectOnceElement: Element {
    @State var count = 0
    var elementID: ElementID?

    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Int) {
        (leafNode(pass), 0)
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                  layout: inout Int, pass: inout PrepaintPass) -> Int { 0 }

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
               layout: inout Int, prepaint: inout Int, pass: inout PaintPass) {}
}

/// State survives across frames for a NON-root element — the seeding site in
/// `Element`'s default `requestGroupLayout` (`ElementGroup.swift`), reached
/// here because `CounterElement` is `Box`'s child rather than the frame's
/// root.
@MainActor
@Test func stateSurvivesAcrossFramesForTheSameElement() throws {
    let table = StateTable()
    let size = Size<Pixels>(width: px(100), height: px(100))
    var tree = Box(content: CounterElement(elementID: ElementID("counter")))

    for _ in 0..<3 {
        Frame(contentSize: size, scaleFactor: 1, stateTable: table, layoutAuthority: .proposal).render(&tree)
    }

    #expect(tree.content.count == 3)
}

/// The root element is seeded too. `Frame.render` calls the root's
/// `requestLayout` directly rather than through `requestGroupLayout` — that
/// method never runs for the root at all — so a root `@State` takes a
/// genuinely different path from every other element's.
@MainActor
@Test func aRootElementsStateIsSeededAndSurvives() throws {
    let table = StateTable()
    let size = Size<Pixels>(width: px(100), height: px(100))
    var element = CounterElement(elementID: ElementID("root-counter"))

    for _ in 0..<3 {
        Frame(contentSize: size, scaleFactor: 1, stateTable: table).render(&element)
    }

    #expect(element.count == 3)
}

/// Reflection is per TYPE, not per instance. 40 elements of one type across
/// two frames must reflect once, not eighty times, or this undoes the
/// per-type memo the element pipeline's performance milestone bought.
///
/// **The expected count is 2, not 1** — the root `Box` wrapping the 40
/// children is seeded too (`Frame.render`'s own seeding site), and it is a
/// distinct type from `ReflectOnceElement` with no `@State` of its own, so it
/// costs its own one-time cache miss (an empty ordinal list) alongside
/// `ReflectOnceElement`'s. What the count rules out is the thing this test
/// exists for: 40 children over 2 frames reflecting once each, per instance
/// or per frame, would read 80 or more — not 2.
@MainActor
@Test func reflectionRunsOncePerTypeNotOncePerElement() throws {
    StateBinder.resetReflectionCount()
    let table = StateTable()
    let size = Size<Pixels>(width: px(2000), height: px(2000))
    var tree = Box(content: ArrayGroup((0..<40).map { _ in ReflectOnceElement() }))

    for _ in 0..<2 {
        Frame(contentSize: size, scaleFactor: 1, stateTable: table, layoutAuthority: .proposal).render(&tree)
    }

    #expect(StateBinder.reflectionCount == 2)
}

/// Seeding MARKS, so a conditionally-read `@State` is not swept. `StateTable`
/// marks on access and `sweep()` drops the unmarked; without seeding's own
/// mark, a counter whose value is read only on some frames silently resets.
@MainActor
@Test func aStateThatIsNeverReadInAFrameIsStillNotSwept() throws {
    let table = StateTable()
    let size = Size<Pixels>(width: px(100), height: px(100))

    var setter = ConditionalReadElement(elementID: ElementID("cond"), touch: true)
    Frame(contentSize: size, scaleFactor: 1, stateTable: table).render(&setter)
    #expect(setter.count == 42)

    // Two frames in a row that never touch `count` at all — only seeding's
    // `mark` call can keep the entry alive through their sweeps.
    var quiet1 = ConditionalReadElement(elementID: ElementID("cond"), touch: false)
    Frame(contentSize: size, scaleFactor: 1, stateTable: table).render(&quiet1)
    var quiet2 = ConditionalReadElement(elementID: ElementID("cond"), touch: false)
    Frame(contentSize: size, scaleFactor: 1, stateTable: table).render(&quiet2)

    #expect(quiet2.count == 42,
            "declaring @State is sufficient intent to keep it, whether or not a frame reads it")
}

/// Two `@State`s at non-adjacent ordinals (0 and 2), with an ORDINARY stored
/// property (`spacer`, no `@State`) sitting between them at 1 — a gap
/// `Mirror` still reports, so it separates "the child's true Mirror index"
/// from "its position among only the `State` children," which a slot of `0`
/// and `1` would satisfy just as well as the real `0` and `2`.
private struct TwoOrdinalElement: Element {
    @State var first = 0
    var spacer: Int = 0
    @State var second = 0
    var elementID: ElementID?
    init(elementID: ElementID? = nil) { self.elementID = elementID }

    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Int) {
        first = 11
        second = 22
        return (leafNode(pass), 0)
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                  layout: inout Int, pass: inout PrepaintPass) -> Int { 0 }

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
               layout: inout Int, prepaint: inout Int, pass: inout PaintPass) {}
}

/// The ordinal `bind` receives is the child's actual `Mirror` index, not its
/// position among `ordinals` — unguarded before this test (a constant
/// `slot: 0` mutation left all 617 tests green).
///
/// **Checks the table directly by the ordinal-derived name, not only that
/// `first` and `second` differ.** A slot of 0/1 (position among the two
/// `State` children) would still give `first` and `second` two DISTINCT
/// entries and two correct values — the gap alone does not force a
/// collision. Reading `table.peek` against the name a slot of 2 must produce
/// (`"$state2"`) is what actually distinguishes "true ordinal" from
/// "position among ordinals," since only the former produces that name.
@MainActor
@Test func stateOrdinalsAreTheMirrorIndexNotThePositionAmongStateChildren() throws {
    let table = StateTable()
    let size = Size<Pixels>(width: px(100), height: px(100))
    var element = TwoOrdinalElement(elementID: ElementID("two-state"))
    Frame(contentSize: size, scaleFactor: 1, stateTable: table).render(&element)

    let rootID = GlobalElementID.child(of: nil, at: 0, name: ElementID("two-state"))
    let firstSlot = GlobalElementID.child(of: rootID, at: 0, name: ElementID("$state0"))
    let secondSlot = GlobalElementID.child(of: rootID, at: 2, name: ElementID("$state2"))

    #expect(table.peek(firstSlot, as: Int.self) == 11)
    #expect(table.peek(secondSlot, as: Int.self) == 22)
    #expect(element.first == 11)
    #expect(element.second == 22)
}

// MARK: - Task 3: writing marks the window dirty (design §2.6)

/// Task 3's exit test, required by the brief: writing marks the table dirty,
/// reading does not.
///
/// **Writes the `@State` DIRECTLY, never through `Window.onInput`.**
/// `Window.init` calls `setNeedsRedraw()` unconditionally after every input
/// event, regardless of whether a handler wrote anything — a test that drove
/// this through an input event would pass whether or not this task did
/// anything at all (taxonomy shape 1, `docs/practices/verifying-tests-can-fail.md`).
@MainActor
@Test func writingStateMarksTheTableDirtyAndReadingDoesNot() throws {
    let table = StateTable()
    let owner = GlobalElementID.child(of: nil, at: 0, name: nil)
    let s = State(wrappedValue: 0)
    s.bind(to: table, id: owner, slot: 0)
    #expect(!table.isDirty, "binding and seeding alone must not dirty the table")

    _ = s.wrappedValue
    #expect(!table.isDirty, "a read must not dirty the table")

    s.wrappedValue = 5
    #expect(table.isDirty, "a write must dirty the table")
}

/// `ScrollView`'s per-frame offset bookkeeping (`ScrollChrome.resolvedOffset`, called from
/// both `requestLayout` and `prepaint`) writes back through `withState` on
/// EVERY render, scrolled or not — `prepaint`'s overload always stores a
/// fresh `viewportExtent`. If `withState` raised `isDirty` the way `write`
/// does, this alone would keep the table dirty forever and the display link
/// would never pause (ruling 3 / milestone 4's exit criterion). Required by
/// this task's mutation (b): a mutation moving the raise into `withState`
/// must redden this.
@MainActor
@Test func aScrollViewsPerFrameOffsetBookkeepingDoesNotDirtyTheTable() throws {
    let table = StateTable()
    let size = Size<Pixels>(width: px(100), height: px(100))
    var tree = ScrollView(.vertical) { Box().width(px(50)).height(px(200)) }

    Frame(contentSize: size, scaleFactor: 1, stateTable: table).render(&tree)

    #expect(!table.isDirty,
            "ScrollView's own per-frame state bookkeeping goes through withState, not write, and must not dirty the table")
}

/// `isDirty` alone is unreachable while the window is idle, because
/// `drawFrameIfNeeded` only consults it once a frame is already being built
/// — and an idle window has its display link PAUSED, so nothing is about to
/// build one. `onWrite` is the hook that closes that gap: `Window.init`
/// installs it to call `setNeedsRedraw()`, which is what actually unpauses
/// the link. Required by this task's mutation (c): deleting the `onWrite`
/// invocation (keeping the flag) must redden this.
@MainActor
@Test func aStateWriteWakesAPausedDisplayLinkThroughTheOnWriteHook() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let (window, platformWindow) = try makeFakeWindow(device: device) { Box() }

    // First call renders (the window starts dirty); the second finds it
    // clean and pauses the link — the same two-call idiom
    // `windowDrawsOnlyWhenDirty` uses in `FrameLoopTests.swift`.
    window.drawFrameIfNeeded()
    window.drawFrameIfNeeded()
    #expect(platformWindow.pauseCalls.last == true, "set up: the link is paused before the write")

    let id = GlobalElementID.child(of: nil, at: 0, name: ElementID("external-write"))
    window.stateTable.write(id, 1)

    #expect(platformWindow.pauseCalls.last == false,
            "a write while the display link is paused must wake it")
    #expect(window.needsRedraw)
}

/// A leaf whose `@State` it writes to unconditionally, every `requestLayout`
/// — the same idiom `CounterElement` above uses, reused here so this test's
/// intent (a write made DURING a frame) reads as the whole point rather than
/// as a side effect of a helper defined elsewhere.
///
/// Required by this task's mutation (d): clearing `isDirty` AFTER the frame
/// instead of before would let this element's write raise the flag during
/// `renderRoot` and then immediately swallow it on the next line, leaving
/// `window.stateTable.isDirty` false when this test reads it back. Clearing
/// before (this task's ruling 2) is what lets the write survive.
@MainActor
@Test func aStateWriteDuringTheFramesOwnRenderIsNotSwallowedByClearingAfterward() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let (window, _) = try makeFakeWindow(device: device) {
        CounterElement(elementID: ElementID("counter"))
    }

    // The window's first frame: `needsRedraw` starts true, so this renders
    // immediately and `CounterElement.requestLayout` writes `count` as part
    // of it.
    window.drawFrameIfNeeded()

    #expect(window.stateTable.isDirty,
            "a @State write made during the frame's own render must not be swallowed by the flag's own clear")
    // The production-visible half, pinned alongside the ordering above: the
    // hook (`onWrite` → `setNeedsRedraw()`) is what actually keeps the window
    // scheduled, and nothing clears `needsRedraw` after this point in the
    // same frame — so it stays green whether `clearDirty()` runs before or
    // after `renderRoot`, which `isDirty` alone does not.
    #expect(window.needsRedraw)
}

/// `write` must mark the slot live for THIS frame's sweep, exactly as
/// `withState` does — the mark is redundant on every path this task's other
/// tests exercise, because `StateBinder.bind` already marks every `@State`
/// slot every frame. It becomes load-bearing on a write made on a frame
/// where the element is NOT produced at all: the out-of-band write `onWrite`
/// exists to serve (a click handler, a completion callback), and what
/// Tasks 4+ make routine. Without the mark, `sweep()` would drop the entry
/// on the very frame it was written, and the write would be silently lost.
@MainActor
@Test func writeMarksTheSlotLiveSoItSurvivesTheNextSweep() throws {
    let table = StateTable()
    let owner = GlobalElementID.child(of: nil, at: 0, name: nil)
    let s = State(wrappedValue: 0)
    s.bind(to: table, id: owner, slot: 0)

    let slotID = GlobalElementID.child(of: owner, at: 0, name: ElementID("$state0"))
    table.sweep() // drop the mark `bind` made; only `write`'s own mark can save it now

    s.wrappedValue = 7
    table.sweep()

    #expect(table.peek(slotID, as: Int.self) == 7,
            "a write must survive the sweep that follows it, on a frame where nothing else marked the slot")
    #expect(s.wrappedValue == 7)
}
