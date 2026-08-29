import Testing
import MetalUICore
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

private func leafStyle() -> Style {
    var style = Style()
    style.size = Size(width: .length(.pixels(px(10))), height: .length(.pixels(px(10))))
    return style
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
        return (pass.requestNode(style: leafStyle(), children: []), 0)
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
        return (pass.requestNode(style: leafStyle(), children: []), 0)
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
        (pass.requestNode(style: leafStyle(), children: []), 0)
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
        Frame(contentSize: size, scaleFactor: 1, stateTable: table).render(&tree)
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
        Frame(contentSize: size, scaleFactor: 1, stateTable: table).render(&tree)
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
        return (pass.requestNode(style: leafStyle(), children: []), 0)
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
