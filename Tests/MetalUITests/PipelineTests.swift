import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUI

// The runtime half of spec §4.1. `PhaseSeparationTests` pins what must not
// compile; this file pins what the three phases actually do when they run.

/// The identity a test hands an element it drives **by hand**, outside any
/// container.
///
/// These tests used to pass `nil` here. Structural identity removed the
/// `Optional` from `Element`'s phases, so an unparented probe needs a real id;
/// `.positional(0)` under no parent is exactly what `Frame.render` would build
/// for an unnamed root, so the value is the production one rather than a
/// fabrication. None of these tests reads it — they assert on phase ordering and
/// state write-back — which is why one shared constant is enough.
private let standaloneID = GlobalElementID.child(of: nil, at: 0, name: nil)

/// Records phase entries in order, and what each phase could see.
///
/// A **class**, held by reference from the probe element: `Element`'s phases are
/// `mutating` on a value type, so anything recorded into the struct itself would
/// be observed on whichever copy the driver happened to keep.
@MainActor
final class PhaseLog {
    var phases: [String] = []
    var boundsSeenInPrepaint: [Bounds<Pixels>] = []
    var boundsSeenInPaint: Bounds<Pixels>?
}

/// A row container with two fixed, **differently sized** children.
///
/// Deliberately not square and not uniform: a 400x100 root with a 100x40 and a
/// 60x20 child distinguishes width from height, the first child from the second,
/// and an absolute origin from a relative one. A symmetric probe would pass
/// against an engine that swapped either.
@MainActor
struct ProbeRow: Element {
    struct Layout {
        var root: LayoutNodeID
        var children: [LayoutNodeID]
    }
    struct Prepaint {
        var childBounds: [Bounds<Pixels>]
    }

    let log: PhaseLog

    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Layout) {
        log.phases.append("requestLayout")

        var rootStyle = Style()
        rootStyle.size = Size(width: .length(.pixels(Pixels(400))),
                              height: .length(.pixels(Pixels(100))))
        rootStyle.flexDirection = .row

        var first = Style()
        first.size = Size(width: .length(.pixels(Pixels(100))),
                          height: .length(.pixels(Pixels(40))))
        var second = Style()
        second.size = Size(width: .length(.pixels(Pixels(60))),
                           height: .length(.pixels(Pixels(20))))

        let children = [pass.requestNode(style: first, children: []),
                        pass.requestNode(style: second, children: [])]
        let root = pass.requestNode(style: rootStyle, children: children)
        return (root, Layout(root: root, children: children))
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                  layout: inout Layout, pass: inout PrepaintPass) -> Prepaint {
        log.phases.append("prepaint")
        let childBounds = layout.children.map { pass.bounds(of: $0) }
        log.boundsSeenInPrepaint = childBounds
        return Prepaint(childBounds: childBounds)
    }

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
               layout: inout Layout, prepaint: inout Prepaint, pass: inout PaintPass) {
        log.phases.append("paint")
        log.boundsSeenInPaint = bounds
        for child in prepaint.childBounds {
            pass.fill(child, color: .white)
        }
    }
}

@MainActor
@Test func theThreePhasesRunInOrder() {
    let log = PhaseLog()
    var element = ProbeRow(log: log)
    let frame = Frame(contentSize: Size(width: Pixels(400), height: Pixels(100)), scaleFactor: 1)

    frame.render(&element)

    #expect(log.phases == ["requestLayout", "prepaint", "paint"])
}

@MainActor
@Test func prepaintSeesBoundsTheEngineResolvedBetweenTheFirstTwoPhases() {
    // The engine runs *between* requestLayout and prepaint. If it did not, every
    // rect would still be the zero `LayoutTree.newNode` initialised it with —
    // which is a silent wrong answer, not a crash, and is why prepaint is the
    // first phase allowed to ask.
    let log = PhaseLog()
    var element = ProbeRow(log: log)
    let frame = Frame(contentSize: Size(width: Pixels(400), height: Pixels(100)), scaleFactor: 1)

    frame.render(&element)

    #expect(log.boundsSeenInPrepaint.count == 2)
    let first = log.boundsSeenInPrepaint[0]
    let second = log.boundsSeenInPrepaint[1]

    // Every field asserted separately, with a distinct value in each: a single
    // `== Bounds(...)` on uniform numbers passes against a transposition.
    #expect(first.origin.x == Pixels(0))
    #expect(first.origin.y == Pixels(0))
    #expect(first.size.width == Pixels(100))
    #expect(first.size.height == Pixels(40))

    // The second child's origin is what makes this more than "the engine ran":
    // rects are absolute to the root, so `x` is the first child's width.
    #expect(second.origin.x == Pixels(100))
    #expect(second.origin.y == Pixels(0))
    #expect(second.size.width == Pixels(60))
    #expect(second.size.height == Pixels(20))
}

@MainActor
@Test func paintReceivesTheRootBoundsAndEmitsIntoTheFramesScene() throws {
    let log = PhaseLog()
    var element = ProbeRow(log: log)
    let frame = Frame(contentSize: Size(width: Pixels(400), height: Pixels(100)), scaleFactor: 1)

    frame.render(&element)

    let root = try #require(log.boundsSeenInPaint)
    #expect(root.size.width == Pixels(400))
    #expect(root.size.height == Pixels(100))
    #expect(frame.scene.rects.count == 2)
}

@MainActor
@Test func fillScalesEveryComponentOfTheBoundsByTheDisplayFactor() throws {
    // Origin as well as size, and a non-square box at a factor that is not 1:
    // scaling the size alone leaves everything but the top-left item in the
    // wrong place on a Retina display, and a square box cannot tell width from
    // height.
    let frame = Frame(contentSize: Size(width: Pixels(400), height: Pixels(100)), scaleFactor: 2)
    frame.fill(Bounds(origin: Point(x: Pixels(3), y: Pixels(7)),
                      size: Size(width: Pixels(40), height: Pixels(25))),
               color: .white)

    let rect = try #require(frame.scene.rects.first)
    #expect(rect.bounds.origin.x == 6)
    #expect(rect.bounds.origin.y == 14)
    #expect(rect.bounds.size.width == 80)
    #expect(rect.bounds.size.height == 50)
}

@MainActor
@Test func eachFrameOwnsItsOwnStateSoNothingLeaksBetweenFrames() {
    // §4.1: the tree is rebuilt from scratch every frame, with no diffing and no
    // persistent node graph. Two frames over the same element must produce the
    // same scene, not an accumulating one.
    let contentSize = Size(width: Pixels(400), height: Pixels(100))
    var element = ProbeRow(log: PhaseLog())

    let first = Frame(contentSize: contentSize, scaleFactor: 1)
    first.render(&element)
    let second = Frame(contentSize: contentSize, scaleFactor: 1)
    second.render(&element)

    #expect(first.scene.rects.count == 2)
    #expect(second.scene.rects.count == 2)

    // **Absolute counts, and separate objects.** `first.tree.nodeCount ==
    // second.tree.nodeCount` is a tautology in exactly the case this test exists
    // to catch: if the two frames shared a tree they would be the *same object*
    // and the two counts would be trivially equal. Measured — with a shared
    // tree that comparison stays green while the real count doubles to 6.
    #expect(first.tree !== second.tree)
    #expect(first.tree.nodeCount == 3)   // two children plus the root
    #expect(second.tree.nodeCount == 3)
}

// MARK: - Type erasure (spec §4.6)

/// A counter shared by every copy of a probe element.
///
/// A **class**, for the same reason `PhaseLog` is one: the probe is a value
/// type whose phases are `mutating`, so a counter stored inline would be
/// incremented on whichever copy the caller happened to keep.
@MainActor
final class InstanceCounter {
    var issued = 0
    /// Hands out 1, 2, 3, … in call order.
    func next() -> Int {
        issued += 1
        return issued
    }
}

/// An element that stamps a **distinct** number into its `LayoutState` when
/// `requestLayout` runs, and reads it back in the two later phases.
///
/// Both halves matter. Distinct values are what tells `[1, 2]` apart from
/// `[2, 2]`: a probe that recorded a constant would agree with a shared box.
/// Reading it back in a *later phase* is what makes the sharing observable at
/// all — aliasing that nothing ever reads is aliasing no test can see.
@MainActor
struct StampedProbe: Element {
    struct Layout {
        var node: LayoutNodeID
        /// Which `requestLayout` call produced this state.
        var stamp: Int
    }
    struct Prepaint {
        var stamp: Int
    }

    let counter: InstanceCounter
    let stampsSeenInPrepaint: Recorder
    let stampsSeenInPaint: Recorder

    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Layout) {
        var style = Style()
        style.size = Size(width: .length(.pixels(Pixels(30))),
                          height: .length(.pixels(Pixels(10))))
        let node = pass.requestNode(style: style, children: [])
        return (node, Layout(node: node, stamp: counter.next()))
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                  layout: inout Layout, pass: inout PrepaintPass) -> Prepaint {
        stampsSeenInPrepaint.values.append(layout.stamp)
        return Prepaint(stamp: layout.stamp)
    }

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
               layout: inout Layout, prepaint: inout Prepaint, pass: inout PaintPass) {
        stampsSeenInPaint.values.append(prepaint.stamp)
        pass.fill(bounds, color: .white)
    }
}

@MainActor
final class Recorder {
    var values: [Int] = []
}

/// Two sibling copies of the same element must not share one `LayoutState`.
///
/// **Measured in the spec (§4.6): with a CLASS box both copies report
/// `layoutState = 2`** — the first is then laid out at the second's bounds,
/// with no error and no diagnostic. With the struct box it is 1 then 2.
///
/// This is why `AnyElementBox` is a struct, and why a future refactor that
/// "simplifies" it to a class is a silent-corruption regression rather than a
/// style change.
///
/// The shape is load-bearing in three ways, and dropping any one of them makes
/// the test unable to fail: the two children are **copies of one `AnyElement`
/// value** (a class box that each child constructed for itself would alias
/// nothing), they are the **same element type** (two different types get two
/// different boxes either way), and the stamp is **read back in a later phase**.
@MainActor
@Test func twoCopiesOfOneElementDoNotShareLayoutState() {
    let counter = InstanceCounter()
    let inPrepaint = Recorder()
    let inPaint = Recorder()

    // One value, copied. This is `Row { sep; sep }` from §4.6 — the erasure is
    // copied into two slots, not built twice.
    let separator = AnyElement(StampedProbe(counter: counter,
                                            stampsSeenInPrepaint: inPrepaint,
                                            stampsSeenInPaint: inPaint))
    var children = [separator, separator]

    let frame = Frame(contentSize: Size(width: Pixels(100), height: Pixels(50)), scaleFactor: 1)

    var layoutPass = LayoutPass(frame: frame)
    // In place, by index. `for child in children` does not compile — the loop
    // variable is a `let` and the phases are `mutating` — so the copy-walking
    // version of this loop is rejected by the compiler rather than left to
    // this comment. Measured; see `AnyElement`'s doc comment.
    var nodes: [LayoutNodeID] = []
    for index in children.indices {
        nodes.append(children[index].requestLayout(standaloneID, pass: &layoutPass))
    }
    var rootStyle = Style()
    rootStyle.flexDirection = .row
    let root = layoutPass.requestNode(style: rootStyle, children: nodes)
    frame.computeRootLayout(root: root)

    var prepaintPass = PrepaintPass(frame: frame)
    for index in children.indices {
        children[index].prepaint(standaloneID, bounds: frame.bounds(of: nodes[index]), pass: &prepaintPass)
    }

    var paintPass = PaintPass(frame: frame)
    for index in children.indices {
        children[index].paint(standaloneID, bounds: frame.bounds(of: nodes[index]), pass: &paintPass)
    }

    #expect(counter.issued == 2)
    #expect(inPrepaint.values == [1, 2])
    #expect(inPaint.values == [1, 2])
}

/// An element that **mutates** state the box holds for it, in every place §4.1
/// says it may.
///
/// Three separate write-backs, with three distinguishable values, because the
/// box has three places to drop one: the element itself (`requestLayout` is
/// `mutating`), the `LayoutState` after `prepaint` mutated it in place, and the
/// `PrepaintState`. A probe that only read values back would agree with a box
/// that discarded all three.
@MainActor
struct MutatingProbe: Element {
    struct Layout {
        var node: LayoutNodeID
        var value: Int
    }
    struct Prepaint {
        var value: Int
    }

    let seenInPaint: Recorder
    /// Mutated by **all three** phases, at three different strides, and read in
    /// `paint`. The strides are what make a lost write-back nameable rather
    /// than merely wrong: see the test below.
    var generation = 0

    mutating func requestLayout(_ id: GlobalElementID,
                                pass: inout LayoutPass) -> (LayoutNodeID, Layout) {
        generation += 7
        var style = Style()
        style.size = Size(width: .length(.pixels(Pixels(30))),
                          height: .length(.pixels(Pixels(10))))
        let node = pass.requestNode(style: style, children: [])
        return (node, Layout(node: node, value: 1))
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                           layout: inout Layout, pass: inout PrepaintPass) -> Prepaint {
        // §4.1 threads `LayoutState` `inout` precisely so this is possible.
        layout.value += 10
        // And the element's *own* state. `Element`'s phases are `mutating` on
        // all three, not just the first.
        generation += 20
        return Prepaint(value: 100)
    }

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                        layout: inout Layout, prepaint: inout Prepaint,
                        pass: inout PaintPass) {
        generation += 300
        seenInPaint.values.append(generation)      // 327, then 627
        seenInPaint.values.append(layout.value)    // 11 — prepaint's in-place edit
        seenInPaint.values.append(prepaint.value)  // 100 — the prepaint state
    }
}

/// The erasure must carry every mutation an element makes forward to the phase
/// that reads it — **the element's own `self` included, in all three phases.**
///
/// The box stores `LayoutState` and `PrepaintState` in `Optional`s and hands
/// them to the element as `inout` locals, so each phase needs an explicit write
/// back into the box. Dropping one loses a mutation **silently**: the phase
/// still runs, and reads a stale value. `11` distinguishes "prepaint's edit
/// survived" from `1` ("the layout state was carried, unedited") and from `10`
/// ("prepaint's edit landed on a fresh zero").
///
/// **`generation` is here because of a half-detected refactor.** Replacing
/// `element.prepaint(…)` with `var e = element; e.prepaint(…)` — which is what
/// someone lands by "simplifying" the box's `var element` to a `let` — builds
/// clean, warning-free, and discards the element's own state for that phase.
/// Measured on this suite: the `requestLayout` version of that mutation reddens,
/// and the `prepaint` and `paint` versions did not. That is the worst state a
/// guard can be in, because the one that fires makes you trust the two that do
/// not.
///
/// The three strides (7, 20, 300) and the **second `paint` call** are what make
/// each phase's write-back separately nameable. Paint's own mutation cannot be
/// observed within the call that makes it — only a later call can see it — so
/// one paint would leave that third case exactly as green as it was before.
@MainActor
@Test func theBoxCarriesEveryPhasesMutationForwardToTheNextPhase() {
    let seen = Recorder()
    var erased = AnyElement(MutatingProbe(seenInPaint: seen))

    let frame = Frame(contentSize: Size(width: Pixels(100), height: Pixels(50)), scaleFactor: 1)

    var layoutPass = LayoutPass(frame: frame)
    let node = erased.requestLayout(standaloneID, pass: &layoutPass)
    frame.computeRootLayout(root: node)

    var prepaintPass = PrepaintPass(frame: frame)
    erased.prepaint(standaloneID, bounds: frame.bounds(of: node), pass: &prepaintPass)

    var paintPass = PaintPass(frame: frame)
    let bounds = frame.bounds(of: node)
    erased.paint(standaloneID, bounds: bounds, pass: &paintPass)
    erased.paint(standaloneID, bounds: bounds, pass: &paintPass)

    // 7 + 20 + 300 = 327, then + 300 = 627. Each stride names one lost
    // write-back on its own: 320/620 is requestLayout's, 307/607 is prepaint's,
    // and 327/327 is paint's.
    #expect(seen.values == [327, 11, 100, 627, 11, 100])
}

/// An element with a local identity, and one that mutates state in `paint`.
///
/// Both properties are here rather than on `MutatingProbe` because both are
/// about calls the *box* makes on the far side of the erasure, and both were
/// added after a mutation that reddened nothing: replacing either
/// `elementID` forwarding hop with `nil`, and dropping `paint`'s write-backs,
/// left all 227 tests green.
@MainActor
struct IdentifiedProbe: Element {
    struct Layout {
        var node: LayoutNodeID
        var paints: Int
    }
    struct Prepaint {
        var paints: Int
    }

    let seenInPaint: Recorder
    let elementID: ElementID?

    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Layout) {
        var style = Style()
        style.size = Size(width: .length(.pixels(Pixels(30))),
                          height: .length(.pixels(Pixels(10))))
        let node = pass.requestNode(style: style, children: [])
        return (node, Layout(node: node, paints: 0))
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                  layout: inout Layout, pass: inout PrepaintPass) -> Prepaint {
        Prepaint(paints: 0)
    }

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
               layout: inout Layout, prepaint: inout Prepaint, pass: inout PaintPass) {
        layout.paints += 1
        prepaint.paints += 10
        seenInPaint.values.append(layout.paints)
        seenInPaint.values.append(prepaint.paints)
    }
}

/// The erasure must forward the element's identity, through both hops.
///
/// `AnyElement.elementID` reads `box.elementID`, which reads
/// `element.elementID`. Either hop can be replaced by a hardcoded `nil`
/// without breaking anything else — `nil` is also the `Element` extension's
/// default, so the wrong answer is the common answer and nothing looks amiss.
/// The identity path (§4.3, Task 3) is what will consume this.
@MainActor
@Test func theErasureForwardsTheElementsIdentity() {
    let named = AnyElement(IdentifiedProbe(seenInPaint: Recorder(),
                                           elementID: ElementID("separator")))
    let anonymous = AnyElement(IdentifiedProbe(seenInPaint: Recorder(), elementID: nil))

    // Both cases, because a forwarding hop replaced by `nil` agrees with the
    // second one and only the first can tell them apart.
    #expect(named.elementID == ElementID("separator"))
    #expect(anonymous.elementID == nil)
}

/// `paint` must write its states back too, because `Element.paint` takes both
/// of them `inout`.
///
/// Painting one element twice in a frame is legal and reachable — §4.5 hoists a
/// `Deferred` subtree to a higher layer, and a container may paint a child in
/// more than one place. Without the write-backs the second call sees the state
/// as of `prepaint` and the mutation vanishes, which is the same silent shape
/// as the class box: no error, wrong pixels.
@MainActor
@Test func paintWritesItsStatesBackSoASecondPaintSeesTheFirst() {
    let seen = Recorder()
    var erased = AnyElement(IdentifiedProbe(seenInPaint: seen, elementID: nil))

    let frame = Frame(contentSize: Size(width: Pixels(100), height: Pixels(50)), scaleFactor: 1)

    var layoutPass = LayoutPass(frame: frame)
    let node = erased.requestLayout(standaloneID, pass: &layoutPass)
    frame.computeRootLayout(root: node)

    var prepaintPass = PrepaintPass(frame: frame)
    erased.prepaint(standaloneID, bounds: frame.bounds(of: node), pass: &prepaintPass)

    var paintPass = PaintPass(frame: frame)
    let bounds = frame.bounds(of: node)
    erased.paint(standaloneID, bounds: bounds, pass: &paintPass)
    erased.paint(standaloneID, bounds: bounds, pass: &paintPass)

    // Two counters at different strides: 1,10 then 2,20. A single counter
    // could not tell "the layout state was carried" from "the prepaint state
    // was", and both write-backs sit on adjacent lines.
    #expect(seen.values == [1, 10, 2, 20])
}
