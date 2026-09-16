import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUI

// M4 spec 2. A `Component` is TRANSPARENT to layout and OPAQUE to identity:
// it contributes no layout node of its own, and it consumes one cursor index so
// that its `@State` has an id to hang on. Those are separate axes and this is
// the first type in the framework to use them differently — every other element
// is opaque to both. **This file pins BOTH halves, and the modifier-
// distribution mechanism on top of them.** It said "the layout-transparency
// half only" when it held only Task 1's tests, and sent the reader to "Task 2's
// `ComponentTests` additions" for the rest — additions that landed in this same
// file. They are here: `aComponentsOwnStateSurvivesAcrossFrames`,
// `twoSiblingComponentsHoldIndependentState`,
// `aNamedComponentKeepsItsStateThroughAReorderAndAnUnnamedOneDoesNot`,
// `anEmptyComponentStillHoldsItsOwnState`,
// `stateInsideAComponentsContentIsAlsoSeeded`,
// `aNamedComponentsContentKeepsItsStateWhenASiblingIsInsertedBeforeIt` and
// `contentIsMaterializedExactlyOncePerFrame` pin the identity-opaque half —
// the cursor arithmetic that gives a component an id, and `content`
// materialized once rather than re-evaluated per phase. Task 3's six
// (`aModifierOnAComponentDistributesToEachTopLevelChild` through
// `chainedPaddingAccumulatesOnAComponentAsItDoesOnAnElement`) pin distribution,
// and the lane-4 section at the end of the file (outer modifiers, `OM-D`,
// `OM-E`, `OM-F`) pins that `.padding` on a component WRAPS each top-level
// node, accumulating, while `width`/`height` still amend.
//
// The assertions below are structural and geometric together. A component that
// wrongly contributed its own flex container would still produce the right
// CHILD COUNT in some trees while moving every rect, so counting alone cannot
// see the defect this file exists to prevent — but the geometry only sees it
// when the fixture's leaves DISAGREE in height; see `TwoLeaves`' own doc for
// the mutation that found this the hard way.
//
// **Node-count spelling.** `frame.layoutNodeCount` does not exist on `Frame`.
// `LayoutTree.nodeCount` does (`Sources/MetalUILayout/LayoutTree.swift:59`,
// `public var nodeCount: Int { styles.count }`), and `Frame.tree` is an
// internal, unqualified `let` (`Sources/MetalUI/Frame.swift:123`) — reachable
// here only because this file is `@testable import MetalUI`. `frame.tree.nodeCount`
// is also the exact idiom the existing suite already uses for this question
// (`Tests/MetalUITests/ElementLayoutTests.swift:365`), so this file matches it
// rather than inventing a second spelling.

// MARK: - Probes

/// Records what each phase was handed, by name. A **class** because `Element`'s
/// phases are `mutating` on a value type, so anything recorded into a struct
/// would be observed on whichever copy the driver happened to keep.
@MainActor
final class ComponentLog {
    var registered: [String] = []
    var bounds: [String: Bounds<Pixels>] = [:]
}

/// A styled leaf that reports its own name and rect.
private struct Leaf: Element, StyledElement {
    var style = Style()
    var decoration = Decoration()
    var elementID: ElementID?
    var handlers = Handlers()
    let name: String
    let log: ComponentLog

    init(_ name: String, log: ComponentLog) {
        self.name = name
        self.log = log
    }

    func requestLayout(_ id: GlobalElementID,
                       pass: inout LayoutPass) -> (LayoutNodeID, LayoutNodeID) {
        log.registered.append(name)
        let node = pass.requestNode(style: style, children: [])
        return (node, node)
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                  layout: inout LayoutNodeID,
                  pass: inout PrepaintPass) -> LayoutNodeID {
        log.bounds[name] = bounds
        return layout
    }

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
               layout: inout LayoutNodeID, prepaint: inout LayoutNodeID,
               pass: inout PaintPass) {}
}

/// Two leaves and nothing else — the shape that distinguishes a transparent
/// component from an opaque one. If `TwoLeaves` contributed a node, `a` and `b`
/// would be children of THAT node rather than of the enclosing container.
///
/// **`a` and `b` have DIFFERENT heights, and that is load-bearing.** A wrapping
/// node built from a default `Style` is an `auto`-sized flex row, and with
/// equal-height leaves it shrink-wraps to exactly the leaves' own extent and
/// the outer `Row` centres it to the same `y` the leaves would have gotten
/// directly — so a component that wrongly wraps its content is byte-identical
/// on rects to a correct one, and only the node COUNT would tell them apart.
/// Measured: with both leaves at height 10, mutating `requestGroupLayout` to
/// wrap `nodes` in `pass.requestNode(style: Style(), children: nodes)` left
/// both rect-based tests below green. With `b` at 30, the wrapper's own cross
/// size (30, from its tallest child) no longer matches the outer `Row`'s
/// height (40), so `a` centres at a different `y` when it is laid out
/// directly under the `Row` (15) than when it is laid out under an
/// intervening 30-tall wrapper (5) — the two cases separate.
private struct TwoLeaves: Component {
    let log: ComponentLog
    var elementID: ElementID?

    var content: some ElementGroup {
        Leaf("a", log: log).width(px(30)).height(px(10))
        Leaf("b", log: log).width(px(50)).height(px(30))
    }
}

private func px(_ v: Float) -> Pixels { Pixels(v) }

private func rect(_ b: Bounds<Pixels>) -> (Float, Float, Float, Float) {
    (b.origin.x.value, b.origin.y.value, b.size.width.value, b.size.height.value)
}

// MARK: - Layout transparency

/// Spec §2. `Row { TwoLeaves() }` must lay `a` and `b` out as the ROW's own
/// children, side by side, exactly as `Row { Leaf; Leaf }` would.
///
/// The geometry is the load-bearing half. A component that contributed its own
/// flex container would still register both leaves in the right order — so
/// `registered` alone cannot see the defect — but `TwoLeaves`' own doc records
/// why an equal-height fixture would have let the rects agree anyway; `a` and
/// `b` differ in height precisely so a wrapping node's own cross size (bounded
/// by its tallest child) pulls `a`'s `y` away from what the `Row` would give it
/// directly.
@MainActor
@Test func aComponentsContentFlattensIntoItsParent() {
    let componentLog = ComponentLog()
    let frame = Frame(contentSize: Size(width: px(300), height: px(40)), scaleFactor: 1)
    var withComponent = Row { TwoLeaves(log: componentLog) }
    frame.render(&withComponent)

    let inlineLog = ComponentLog()
    let inlineFrame = Frame(contentSize: Size(width: px(300), height: px(40)), scaleFactor: 1)
    var inline = Row {
        Leaf("a", log: inlineLog).width(px(30)).height(px(10))
        Leaf("b", log: inlineLog).width(px(50)).height(px(30))
    }
    inlineFrame.render(&inline)

    #expect(componentLog.registered == ["a", "b"])
    #expect(componentLog.registered == inlineLog.registered)
    // The differential IS the assertion: a wrapped component and the inline
    // spelling must be geometrically indistinguishable.
    #expect(rect(componentLog.bounds["a"]!) == rect(inlineLog.bounds["a"]!))
    #expect(rect(componentLog.bounds["b"]!) == rect(inlineLog.bounds["b"]!))
    // Literal numbers alongside, because two runs of a broken engine agree with
    // each other. A 40-tall row centres each leaf INDEPENDENTLY on the cross
    // axis (ruling EP-8): the 10-tall `a` at y = 15, the 30-tall `b` at y = 5.
    #expect(rect(componentLog.bounds["a"]!) == (0, 15, 30, 10))
    #expect(rect(componentLog.bounds["b"]!) == (30, 5, 50, 30))
}

/// Spec §2. The node count for a tree holding a component equals the count for
/// the same tree written inline. This is the direct form of "contributes no
/// layout node", and it is the assertion a wrapping node reddens first.
@MainActor
@Test func aComponentContributesNoLayoutNodeOfItsOwn() {
    let frame = Frame(contentSize: Size(width: px(300), height: px(40)), scaleFactor: 1)
    var withComponent = Row { TwoLeaves(log: ComponentLog()) }
    frame.render(&withComponent)
    let withCount = frame.tree.nodeCount

    let inlineFrame = Frame(contentSize: Size(width: px(300), height: px(40)), scaleFactor: 1)
    let log = ComponentLog()
    var inline = Row {
        Leaf("a", log: log).width(px(30)).height(px(10))
        Leaf("b", log: log).width(px(50)).height(px(30))
    }
    inlineFrame.render(&inline)

    #expect(withCount == inlineFrame.tree.nodeCount,
            "a component must add no layout node; got \(withCount) against \(inlineFrame.tree.nodeCount)")
}

/// Spec §6 assertion 8. Two identity levels, zero layout nodes.
@MainActor
@Test func aComponentInsideAComponentFlattensThroughBothLevels() {
    struct Outer: Component {
        let log: ComponentLog
        var elementID: ElementID?
        var content: some ElementGroup { TwoLeaves(log: log) }
    }

    let log = ComponentLog()
    let frame = Frame(contentSize: Size(width: px(300), height: px(40)), scaleFactor: 1)
    var root = Row { Outer(log: log) }
    frame.render(&root)

    #expect(log.registered == ["a", "b"])
    #expect(rect(log.bounds["a"]!) == (0, 15, 30, 10))
    #expect(rect(log.bounds["b"]!) == (30, 5, 50, 30))
}

/// Spec §4.3. `EmptyGroup` is an `ElementGroup`, so a component with an empty
/// content block is legal and contributes zero nodes — consistent with `Box()`,
/// which is also childless. Not an error.
@MainActor
@Test func anEmptyComponentContributesNoNodes() {
    struct Nothing: Component {
        var elementID: ElementID?
        var content: some ElementGroup { EmptyGroup() }
    }

    let frame = Frame(contentSize: Size(width: px(300), height: px(40)), scaleFactor: 1)
    var root = Row { Nothing() }
    frame.render(&root)

    let bareFrame = Frame(contentSize: Size(width: px(300), height: px(40)), scaleFactor: 1)
    var bare = Row { EmptyGroup() }
    bareFrame.render(&bare)

    #expect(frame.tree.nodeCount == bareFrame.tree.nodeCount)
}

// MARK: - Identity opacity: `@State` inside a component

/// `@Binding` does not exist in this framework — `grep -rn "propertyWrapper"
/// Sources/MetalUI/` finds exactly one `@propertyWrapper`, `State.swift:39`.
/// So this component takes the brief's stated fallback: it increments its own
/// `@State` directly inside `content`'s getter, rather than handing a binding
/// down to a child leaf. That is safe only because `content` is materialized
/// **exactly once per frame** — `requestGroupLayout` evaluates the getter once
/// and stashes the result in `ComponentLayout.content` (spec §4.2); a getter
/// re-evaluated by `prepaintGroup` would double-count, which is exactly what
/// `contentIsMaterializedExactlyOncePerFrame` below is watching for.
///
/// `content` also returns `EmptyGroup()` — the component's own `@State` and
/// its identity level do not depend on `content` producing any layout nodes at
/// all, and `anEmptyComponentStillHoldsItsOwnState` below already covers that
/// shape on its own type. `log`/`name` are kept only to match the brief's call
/// sites (`Counter("a", log: log)`); this file does not assert on `log`.
///
/// **Writing `@State` from a `content` getter is a TEST-ONLY idiom and is
/// forbidden in production**, for the same reason writing it from
/// `requestLayout` is (see the `@State` bullet in `CLAUDE.md`): it keeps the
/// window permanently dirty, since a value that mutates on every frame's
/// materialization gives `StateTable.onWrite` something to fire on every
/// frame, which is milestone 4's exit criterion sabotaged from an element. A
/// reader landing on this file without that context should not copy the
/// pattern into a real component.
private struct Counter: Component {
    @State var count = 0
    var elementID: ElementID?
    let log: ComponentLog
    let name: String

    init(_ name: String, log: ComponentLog, elementID: ElementID? = nil) {
        self.name = name
        self.log = log
        self.elementID = elementID
    }

    var content: some ElementGroup {
        count += 1
        log.registered.append(name)
        return EmptyGroup()
    }
}

/// A plain `Element` with one `@State` slot, incremented in `requestLayout` —
/// copied from `StateTests.swift:77`'s `CounterElement` rather than widening
/// that type's access level.
private struct CounterLeaf: Element {
    @State var count = 0
    var elementID: ElementID?

    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Int) {
        count += 1
        var style = Style()
        style.size = Size(width: .length(.pixels(px(10))), height: .length(.pixels(px(10))))
        return (pass.requestNode(style: style, children: []), 0)
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                  layout: inout Int, pass: inout PrepaintPass) -> Int { 0 }

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
               layout: inout Int, prepaint: inout Int, pass: inout PaintPass) {}
}

/// A component whose CONTENT (not the component itself) holds the `@State` —
/// file-scoped, rather than local to `stateInsideAComponentsContentIsAlsoSeeded`
/// (which first declared this shape), so
/// `aNamedComponentsContentKeepsItsStateWhenASiblingIsInsertedBeforeIt` can
/// reuse it with a name rather than inventing a second copy of the shape.
private struct Wrapper: Component {
    let inner: CounterLeaf
    var elementID: ElementID?
    var content: some ElementGroup { inner }
}

/// Spec §6 assertion 3. The component's own `@State` must survive across
/// frames, which requires its own `GlobalElementID`, which is what the
/// extension's `cursor += 1` buys.
@MainActor
@Test func aComponentsOwnStateSurvivesAcrossFrames() {
    let table = StateTable()
    let size = Size<Pixels>(width: px(100), height: px(100))
    var tree = Box(content: Counter("c", log: ComponentLog()))

    for _ in 0..<3 {
        Frame(contentSize: size, scaleFactor: 1, stateTable: table).render(&tree)
    }

    #expect(tree.content.count == 3,
            "the component's own @State must accumulate, not reset; got \(tree.content.count)")
}

/// Spec §6 assertion 4. Two sibling instances of the same component type hold
/// INDEPENDENT state. This is what the outer `cursor += 1` and the fresh
/// `innerCursor` buy together — a shared cursor collides them, and each would
/// read 6 or 0 rather than 3.
@MainActor
@Test func twoSiblingComponentsHoldIndependentState() {
    let table = StateTable()
    let size = Size<Pixels>(width: px(100), height: px(100))
    let log = ComponentLog()
    var tree = Box {
        Counter("a", log: log)
        Counter("b", log: log)
    }

    for _ in 0..<3 {
        Frame(contentSize: size, scaleFactor: 1, stateTable: table).render(&tree)
    }

    #expect(tree.content.first.count == 3, "got \(tree.content.first.count)")
    #expect(tree.content.second.count == 3, "got \(tree.content.second.count)")
}

/// Spec §6 assertion 5, both halves in one test, because the ASYMMETRY is the
/// evidence — the pattern `namingTheLaterSiblingIsWhatSurvivesAVanishingIf`
/// already uses. A named component keeps its own count through a swap; an
/// unnamed one's count follows the position.
@MainActor
@Test func aNamedComponentKeepsItsStateThroughAReorderAndAnUnnamedOneDoesNot() {
    let size = Size<Pixels>(width: px(100), height: px(100))

    // Named: the counts travel with the names.
    let namedTable = StateTable()
    let log = ComponentLog()
    var forward = Box {
        Counter("a", log: log, elementID: ElementID("a"))
        Counter("b", log: log, elementID: ElementID("b"))
    }
    Frame(contentSize: size, scaleFactor: 1, stateTable: namedTable).render(&forward)
    Frame(contentSize: size, scaleFactor: 1, stateTable: namedTable).render(&forward)

    var swapped = Box {
        Counter("b", log: log, elementID: ElementID("b"))
        Counter("a", log: log, elementID: ElementID("a"))
    }
    Frame(contentSize: size, scaleFactor: 1, stateTable: namedTable).render(&swapped)

    #expect(swapped.content.first.count == 3, "\"b\" kept its own slot across the swap")
    #expect(swapped.content.second.count == 3, "\"a\" kept its own slot across the swap")

    // Unnamed: the counts stay with the POSITIONS, so the swap is invisible to
    // the table and both still read 3 — but for the opposite reason. To make
    // the asymmetry observable, give the two different starting counts by
    // rendering the unnamed pair an unequal number of times before swapping.
    let unnamedTable = StateTable()
    var first = Box { Counter("a", log: log) }
    Frame(contentSize: size, scaleFactor: 1, stateTable: unnamedTable).render(&first)
    Frame(contentSize: size, scaleFactor: 1, stateTable: unnamedTable).render(&first)

    var pair = Box {
        Counter("x", log: log)
        Counter("y", log: log)
    }
    Frame(contentSize: size, scaleFactor: 1, stateTable: unnamedTable).render(&pair)

    // Position 0 inherits the slot the single unnamed component built up.
    #expect(pair.content.first.count == 3,
            "an unnamed component at position 0 ADOPTS the slot a previous unnamed component at position 0 left; got \(pair.content.first.count)")
    #expect(pair.content.second.count == 1,
            "position 1 is fresh; got \(pair.content.second.count)")
}

/// Spec §4.3 second half. A childless component still has an identity level,
/// so its own `@State` still works.
@MainActor
@Test func anEmptyComponentStillHoldsItsOwnState() {
    struct Quiet: Component {
        @State var count = 0
        var elementID: ElementID?
        var content: some ElementGroup {
            count += 1
            return EmptyGroup()
        }
    }

    let table = StateTable()
    let size = Size<Pixels>(width: px(100), height: px(100))
    var tree = Box(content: Quiet())

    for _ in 0..<3 {
        Frame(contentSize: size, scaleFactor: 1, stateTable: table).render(&tree)
    }

    #expect(tree.content.count == 3, "got \(tree.content.count)")
}

/// Spec §4.2's load-bearing line: the content is reached through
/// `requestGroupLayout`, which is what calls `StateBinder.bind` for every
/// element inside it. Forwarding to `requestLayout` instead is the live
/// `AnyElement` defect — `@State` returns its initial value forever, with no
/// diagnostic.
///
/// **This and `aComponentsOwnStateSurvivesAcrossFrames` must be reddened by
/// DIFFERENT mutations**, or one of the two is proving less than it claims.
@MainActor
@Test func stateInsideAComponentsContentIsAlsoSeeded() {
    let table = StateTable()
    let size = Size<Pixels>(width: px(100), height: px(100))
    var tree = Box(content: Wrapper(inner: CounterLeaf()))

    for _ in 0..<3 {
        Frame(contentSize: size, scaleFactor: 1, stateTable: table).render(&tree)
    }

    #expect(tree.content.inner.count == 3,
            "@State inside a component's CONTENT must be seeded too; got \(tree.content.inner.count)")
}

/// Fix round 1. A NAMED component's content must not depend on how many
/// siblings preceded the component — that is the whole point of naming it.
/// Threading the outer `cursor` into the content (instead of a fresh
/// `innerCursor`) does not collide two components' ids — `GlobalElementID`
/// nests content under the component's OWN id regardless, so the numbers
/// stay unique — but it does make the content's ids depend on how many
/// siblings preceded the NAMED component, which defeats naming: inserting a
/// sibling before the named component shifts its content's numeric position
/// and resets its content's state. `aNamedComponentKeepsItsStateThroughAReorderAndAnUnnamedOneDoesNot`
/// cannot see this, because that test's state lives on the COMPONENT itself,
/// not inside its content.
@MainActor
@Test func aNamedComponentsContentKeepsItsStateWhenASiblingIsInsertedBeforeIt() {
    let table = StateTable()
    let size = Size<Pixels>(width: px(100), height: px(100))
    let log = ComponentLog()

    var solo = Box(content: Wrapper(inner: CounterLeaf(), elementID: ElementID("named")))
    Frame(contentSize: size, scaleFactor: 1, stateTable: table).render(&solo)

    var withSibling = Box {
        Leaf("sibling", log: log).width(px(10)).height(px(10))
        Wrapper(inner: CounterLeaf(), elementID: ElementID("named"))
    }
    Frame(contentSize: size, scaleFactor: 1, stateTable: table).render(&withSibling)

    #expect(withSibling.content.second.inner.count == 2,
            "a named component's content state must survive a sibling inserted before it; got \(withSibling.content.second.inner.count)")
}

/// Added by Task 2 beyond the brief's five. **Measured** (fix round 2; the
/// dispatch's prediction that this mutation "reddens nothing, because none of
/// the other tests in this file reads state during prepaint" was wrong): a
/// `prepaintGroup` that re-evaluates `content` instead of using the stashed
/// `layout.content` reddens **10 issues across 6 of this file's 18 tests**.
/// **The denominator read 14 until the fix wave; the mutation was RE-RUN there
/// rather than re-dated**, and it still reddens exactly 10 issues across
/// exactly the same six tests, out of 18. Task 3's fix round added four tests
/// after this comment was written and none of them is sensitive to this line —
/// which is a result, not an assumption, and is why the numerator did not move
/// with the denominator. (The stale denominator is the practices doc's third
/// record-mechanism arriving as a count of what a claim was measured
/// *against*, rather than as a count of what it reddened.) The six are —
/// `aComponentsOwnStateSurvivesAcrossFrames`,
/// `twoSiblingComponentsHoldIndependentState`,
/// `aNamedComponentKeepsItsStateThroughAReorderAndAnUnnamedOneDoesNot`,
/// `anEmptyComponentStillHoldsItsOwnState`, this test itself and
/// `addingAModifierDoesNotResetAComponentsState`, because the `@Binding`
/// fallback puts `Counter`'s and `Quiet`'s own `@State` increment inside
/// `content`'s getter — see `Counter`'s doc — so re-evaluating it
/// double-increments every one of them. This test is kept and is still the
/// right one to have, not because it is the only thing that catches the
/// defect, but because it **isolates the property directly**: `calls` is a
/// plain `@MainActor` class the test owns, not `@State`, so it counts
/// materializations themselves rather than inferring the count from a value
/// `@State` happens to carry, and it fails on exactly this mutation with no
/// dependence on how any other fixture in the file happens to be shaped.
@MainActor
@Test func contentIsMaterializedExactlyOncePerFrame() {
    struct Once: Component {
        let calls: CallCounter
        var elementID: ElementID?
        var content: some ElementGroup {
            calls.count += 1
            return EmptyGroup()
        }
    }

    let table = StateTable()
    let size = Size<Pixels>(width: px(100), height: px(100))
    let calls = CallCounter()
    var tree = Box(content: Once(calls: calls))

    let frameCount = 5
    for _ in 0..<frameCount {
        Frame(contentSize: size, scaleFactor: 1, stateTable: table).render(&tree)
    }

    #expect(calls.count == frameCount,
            "content must be materialized exactly once per frame; got \(calls.count)")
}

/// Plain call counter for `contentIsMaterializedExactlyOncePerFrame` —
/// deliberately not `@State`, since the point is to observe how many times
/// the `content` getter itself runs, independent of any state seeding.
@MainActor
private final class CallCounter {
    var count = 0
}

// MARK: - Modifiers distribute

/// Two AUTO-sized leaves — deliberately **not** `TwoLeaves`, whose two leaves
/// each declare an explicit `.width(_:).height(_:)`.
///
/// **This is a reported mismatch against the brief, not a silent
/// substitution.** The brief's Step 2 fixture reuses `TwoLeaves` and predicts
/// `padA.2 == bareA.2 + 8` — a leaf's outer rect growing by the padding, the
/// way SwiftUI's own `.padding()` grows a fixed-size view's frame. That is
/// **content-box** reasoning, and this framework's box model is border-box
/// **only**, by design: `Style.swift:97`, "`size`, `minSize` and `maxSize`
/// include padding and border. There is deliberately no `boxSizing`
/// property." Measured against `TwoLeaves` first, as the brief specifies:
/// `.padding(px(4))` left leaf `a`'s width at exactly 30.0 and leaf `b`'s at
/// exactly 50.0 — unchanged from the unpadded run, both times, because an
/// EXPLICIT `.width()` already fixes the border box and padding can only eat
/// into the content area inside it, which nothing here logs. No implementation
/// of distribution-vs-wrapping could move that number; the fixture cannot see
/// the effect it was written to demonstrate.
///
/// An **auto**-sized leaf can: `size == .auto` on both axes with no content
/// (`Leaf` has no children and no measure function) resolves its border box
/// to padding-plus-border alone, so padding genuinely changes what these two
/// leaves paint at, and the same discriminator the brief wanted — each leaf's
/// rect moves under distribution, neither leaf's rect moves under wrapping —
/// is observable here instead.
///
/// **Since the outer-modifiers task (`OM-D`) the discriminator reads
/// differently but still discriminates.** A component's `.padding` now wraps
/// each member, so the leaves keep their 0x0 and their ORIGINS move instead:
/// `a` to x 4 inside its own wrapper and `b` to x 12 (after `a`'s 8-wide
/// wrapper, plus its own 4). One wrapper around the pair would put both at
/// x 4; the old amend put `a` at 0 with 8x8. The node count (+2, one per
/// member) is the other half of the reading.
private struct TwoAutoLeaves: Component {
    let log: ComponentLog
    var elementID: ElementID?

    var content: some ElementGroup {
        Leaf("a", log: log)
        Leaf("b", log: log)
    }
}

/// Spec §5. A modifier on a component applies to EACH top-level node its content
/// contributed, and the component stays layout-transparent — no node is added.
///
/// **Measured against SwiftUI, which is why it is distribution and not wrapping**:
/// `HStack { MyRow().padding(8) }` is 120x26 where `MyRow`'s body is a 30x10 and
/// a 50x10, which is `(30+16) + 8 + (50+16)` — each child padded — and is
/// bit-identical to `Group { A; B }.padding(8)`. Wrapping predicts 96-104. That
/// SwiftUI measurement is about the DESIGN (distribute, don't wrap). **Until
/// the outer-modifiers task it was not reproducible as a literal number
/// here**, because the amend wrote border-box `Style.padding` onto a leaf that
/// already fixed its size — see `TwoAutoLeaves`' own doc for the mismatch that
/// forced, measured against the brief's literal fixture before it was
/// changed. Since lane 4 (`OM-D`) it IS reproduced literally:
/// `aTwoMemberComponentsPaddingIsAppliedToEachMember` reads G2's 120x26 with
/// `a` at (8, 8) and `b` at (62, 8).
///
/// **Both halves are asserted and both are needed.** The node count alone cannot
/// tell distribution from a modifier that did nothing at all; the rects alone
/// cannot tell distribution from wrapping in every fixture. Together they can.
///
/// **Rewritten in the outer-modifiers task (lane 4, `OM-D`).** `.padding` on a
/// component is no longer an amend of each member's `Style.padding` but a
/// WRAPPER NODE around each member — still per member (distribution), now with
/// SwiftUI's box model. The node count therefore grows by the member count,
/// and each leaf is offset by the padding inside its own wrapper rather than
/// enlarged. `aComponentsPaddingWrapsEachTopLevelNode` below pins the probe's
/// numbers; this test keeps the two-member shape that separates per-member
/// from around-the-pair.
@MainActor
@Test func aModifierOnAComponentDistributesToEachTopLevelChild() {
    let bareLog = ComponentLog()
    let bareFrame = Frame(contentSize: Size(width: px(300), height: px(60)), scaleFactor: 1)
    var bare = Row { TwoAutoLeaves(log: bareLog) }
    bareFrame.render(&bare)

    let padLog = ComponentLog()
    let padFrame = Frame(contentSize: Size(width: px(300), height: px(60)), scaleFactor: 1)
    var padded = Row { TwoAutoLeaves(log: padLog).padding(px(4)) }
    padFrame.render(&padded)

    // Transparency survives the modifier — no node of the COMPONENT's own —
    // and the padding is one wrapper PER MEMBER (OM-D): two members, two new
    // nodes. One node around the pair would read +1; an amend +0.
    #expect(padFrame.tree.nodeCount == bareFrame.tree.nodeCount + 2,
            "a padded component must add exactly one wrapper per member; got \(padFrame.tree.nodeCount) against \(bareFrame.tree.nodeCount)")

    // EACH leaf sits 4 inside its own wrapper: `a` at x 4, and `b` at x 12 —
    // after `a`'s 8-wide wrapper, plus its own 4. One wrapper around the pair
    // would put both leaves at x 4; the old amend put `a` at 0 and `b` at 8.
    // The leaves' own sizes do not move (0 wide: `Leaf` has no measure and no
    // children); the wrappers are what grew.
    let bareA = rect(bareLog.bounds["a"]!)
    let padA = rect(padLog.bounds["a"]!)
    #expect(bareA == (0, 30, 0, 0), "got \(bareA)")
    #expect(padA == (4, 30, 0, 0), "leaf a sits 4 inside its own wrapper; got \(padA)")
    let bareB = rect(bareLog.bounds["b"]!)
    let padB = rect(padLog.bounds["b"]!)
    #expect(bareB == (0, 30, 0, 0), "got \(bareB)")
    #expect(padB == (12, 30, 0, 0),
            "leaf b sits after a's 8-wide wrapper and 4 inside its own — this is the reading that separates one wrapper per member from one around the pair; got \(padB)")
}

/// A SwiftUI-style frame is deliberately unlike this framework's older
/// distributing `.width(_:)`: it wraps the component's transparent body in
/// one outer layout node. The body therefore keeps the sizes its author chose,
/// while the caller controls the outer footprint and alignment.
@MainActor
@Test func aFrameWrapsAComponentsBodyWithoutOverwritingItsChildren() {
    let bareLog = ComponentLog()
    let bareFrame = Frame(contentSize: Size(width: px(300), height: px(40)), scaleFactor: 1)
    var bare = Row { TwoLeaves(log: bareLog) }
    bareFrame.render(&bare)

    let framedLog = ComponentLog()
    let framedFrame = Frame(contentSize: Size(width: px(300), height: px(40)), scaleFactor: 1)
    var framed = Row { TwoLeaves(log: framedLog).frame(width: px(100), height: px(40)) }
    framedFrame.render(&framed)

    #expect(framedFrame.tree.nodeCount == bareFrame.tree.nodeCount + 1,
            "a frame must add its own layout node rather than amend each body node")

    // The caller's frame is 100 points wide, but the component's two children
    // retain their own 30- and 50-point widths. They are centred as a unit in
    // the wrapper, so the body's leading edge moves by (100 - 80) / 2.
    #expect(rect(framedLog.bounds["a"]!) == (10, 15, 30, 10))
    #expect(rect(framedLog.bounds["b"]!) == (40, 5, 50, 30))
    #expect(rect(bareLog.bounds["a"]!) == (0, 15, 30, 10))
    #expect(rect(bareLog.bounds["b"]!) == (30, 5, 50, 30))
}

/// A frame is a typed structural wrapper, not an implicit `AnyElement`.
///
/// The explicit stored type is the regression shape that direct conversion of
/// legacy sizing modifiers broke: both wrapper layers must remain available to
/// the generic `Row` builder, and the two different widths must nest rather
/// than overwrite each other.
///
/// **The TYPE is flat and the NODES still nest** (ruling MC-A): the second
/// `.frame` adds a layer to the same `ModifiedElement<TwoLeaves>` rather than a
/// type level, and each layer still registers its own node.
@MainActor
@Test func chainedFramesRemainConcreteAndNestTheirLayoutNodes() {
    let log = ComponentLog()
    let stored: ModifiedElement<TwoLeaves> = TwoLeaves(log: log).frame(width: px(100), height: px(40))
    var tree: Row<ModifiedElement<TwoLeaves>> = Row {
        stored.frame(width: px(120), height: px(40))
    }
    let frame = Frame(contentSize: Size(width: px(300), height: px(40)), scaleFactor: 1)

    frame.render(&tree)

    #expect(frame.tree.nodeCount == 5, "row, two typed frame nodes, and two body leaves")
    #expect(rect(log.bounds["a"]!) == (20, 15, 30, 10))
    #expect(rect(log.bounds["b"]!) == (50, 5, 50, 30))
}

/// Padding on an ordinary element composes by wrapping, as it does in SwiftUI.
/// A `Leaf` has no child layout to inset, so the old direct-style spelling left
/// it at x = 0. A wrapper must add one node and offset the fixed-size leaf by
/// the requested padding without shrinking its 30 × 10 footprint.
@MainActor
@Test func paddingWrapsAnElementAndExpandsItsOuterFootprint() {
    let bareLog = ComponentLog()
    let bareFrame = Frame(contentSize: Size(width: px(300), height: px(40)), scaleFactor: 1)
    var bare = Row { Leaf("leaf", log: bareLog).width(px(30)).height(px(10)) }
    bareFrame.render(&bare)

    let paddedLog = ComponentLog()
    let paddedFrame = Frame(contentSize: Size(width: px(300), height: px(40)), scaleFactor: 1)
    var padded = Row { Leaf("leaf", log: paddedLog).width(px(30)).height(px(10)).padding(px(4)) }
    paddedFrame.render(&padded)

    #expect(paddedFrame.tree.nodeCount == bareFrame.tree.nodeCount + 1)
    #expect(rect(bareLog.bounds["leaf"]!) == (0, 15, 30, 10))
    #expect(rect(paddedLog.bounds["leaf"]!) == (4, 15, 30, 10))
}

/// Each padding call creates a separate outer box, so distinct values add
/// instead of the later call replacing the earlier one.
@MainActor
@Test func chainedPaddingCreatesNestedWrappers() {
    let log = ComponentLog()
    let frame = Frame(contentSize: Size(width: px(300), height: px(40)), scaleFactor: 1)
    var tree = Row {
        Leaf("leaf", log: log).width(px(30)).height(px(10)).padding(px(4)).padding(px(8))
    }
    frame.render(&tree)

    #expect(frame.tree.nodeCount == 4,
            "row, two padding wrappers, and the leaf each contribute one node")
    #expect(rect(log.bounds["leaf"]!) == (12, 15, 30, 10))
}

/// Spec §5's limit. Only `Style`-backed modifiers can be distributed, because
/// `setStyle` reaches `LayoutTree` and nothing reaches `Decoration`/`Handlers`
/// per node. So `background`, `onClick` and `focusable` are NOT offered on a
/// component at all — offering them with wrapping semantics beside a
/// distributing `padding` would be two modifiers that read alike at the call
/// site and behave differently.
///
/// Type-level, because no layout assertion can see an absent method.
@MainActor
@Test func decorationBackedModifiersAreNotOfferedOnAComponent() {
    // `.padding` exists and returns a StyledComponent, not a Box.
    let styled = TwoLeaves(log: ComponentLog()).padding(px(4))
    let name = String(describing: type(of: styled))
    #expect(name.hasPrefix("StyledComponent<"))
    #expect(name.contains("TwoLeaves"))
}

/// A modifier must NOT change a component's identity. `StyledComponent` forwards
/// the parent and cursor it was given straight through, minting no id of its own
/// — so `MyComponent()` and `MyComponent().padding(4)` hold the SAME `@State`.
///
/// If this fails, adding a modifier silently resets a component's state, which
/// is the sharpest hazard in this design and one no rect assertion could see.
///
/// Idiom from `StateTests.swift:143-152`: thread one `StateTable` through
/// several `Frame`s and read the value back through the element's own
/// property. `Counter` is Task 2's fixture, reused here rather than declaring
/// a second one — its `content` increments `count` on every render regardless
/// of whether the component itself carries a modifier.
@MainActor
@Test func addingAModifierDoesNotResetAComponentsState() {
    let table = StateTable()
    let size = Size<Pixels>(width: px(100), height: px(100))
    let log = ComponentLog()

    var bare = Box(content: Counter("c", log: log))
    Frame(contentSize: size, scaleFactor: 1, stateTable: table).render(&bare)
    Frame(contentSize: size, scaleFactor: 1, stateTable: table).render(&bare)

    var modified = Box(content: Counter("c", log: log).padding(px(4)))
    Frame(contentSize: size, scaleFactor: 1, stateTable: table).render(&modified)

    #expect(modified.content.component.count == 3,
            "a modifier must not reset the component's @State; got \(modified.content.component.count)")
}

// MARK: - Fix round 1: chained modifiers compose

/// Fix round 1. `StyledComponent<C>` is an `ElementGroup`, not a `Component`,
/// so the three modifiers declared in `extension Component` were unreachable
/// on the value any of them returned — `Leafless().width(10)` had no
/// `.height`. Measured with `swiftc -typecheck`:
/// `error: value of type 'StyledComponent<Leafless>' has no member 'height'`.
/// `.width(_:).height(_:)` is the most natural pairing there is — it is this
/// file's own `TwoLeaves` fixture, above — so this is the discriminating
/// test: both fields must land on EACH top-level child, not just the later
/// call's field.
@MainActor
@Test func widthAndHeightComposeOnAChainedModifier() {
    let log = ComponentLog()
    let frame = Frame(contentSize: Size(width: px(300), height: px(60)), scaleFactor: 1)
    var tree = Row { TwoAutoLeaves(log: log).width(px(20)).height(px(15)) }
    frame.render(&tree)

    let a = rect(log.bounds["a"]!)
    let b = rect(log.bounds["b"]!)
    #expect(a.2 == 20 && a.3 == 15,
            "leaf a must carry BOTH the width and the height from the chained call; got \(a)")
    #expect(b.2 == 20 && b.3 == 15,
            "leaf b must carry BOTH the width and the height too; got \(b)")
}

/// Coverage gap the fix round found: neither `width` nor `height` had ANY
/// test on its own, chained or not — only `padding` was exercised, by
/// `aModifierOnAComponentDistributesToEachTopLevelChild` and the type-name
/// check. A bare (unchained) `.width(_:)` distributing at all.
@MainActor
@Test func widthAloneDistributesToEachTopLevelChild() {
    let log = ComponentLog()
    let frame = Frame(contentSize: Size(width: px(300), height: px(60)), scaleFactor: 1)
    var tree = Row { TwoAutoLeaves(log: log).width(px(20)) }
    frame.render(&tree)

    #expect(rect(log.bounds["a"]!).2 == 20, "got \(rect(log.bounds["a"]!))")
    #expect(rect(log.bounds["b"]!).2 == 20, "got \(rect(log.bounds["b"]!))")
}

/// The other half of the same gap: a bare (unchained) `.height(_:)`.
@MainActor
@Test func heightAloneDistributesToEachTopLevelChild() {
    let log = ComponentLog()
    let frame = Frame(contentSize: Size(width: px(300), height: px(60)), scaleFactor: 1)
    var tree = Row { TwoAutoLeaves(log: log).height(px(15)) }
    frame.render(&tree)

    #expect(rect(log.bounds["a"]!).3 == 15, "got \(rect(log.bounds["a"]!))")
    #expect(rect(log.bounds["b"]!).3 == 15, "got \(rect(log.bounds["b"]!))")
}

/// `.padding(_:).padding(_:)` on a component ACCUMULATES, as it does on an
/// element — outer modifiers lane 4, ruling `OM-E`, probe
/// `swiftui-component-distribution` G4 (`Pair().padding(4).padding(4)` equals
/// `.padding(8)`, 120x26) and `swiftui-outer-modifier-order` E1–E3.
///
/// **This test REPLACES `chainedPaddingReplacesRatherThanAccumulates`**, whose
/// expectation ("the second call wins outright, 16 not 24") was measured on
/// the amend and was right about the amend: two writes to one `Style.padding`
/// field cannot accumulate. Each `.padding` is now its own wrapper node
/// (`OM-D`), so a second call adds a second wrapper outside the first, exactly
/// as `ModifiedElement`'s `_wrap` appends a layer
/// (`chainedPaddingCreatesNestedWrappers`: the element path's leaf lands at
/// x 12 for 4 then 8, and so does the component path's here).
///
/// Three arms, because two would not say which of three answers the chain
/// gives: `.padding(4)` alone puts leaf `a` at x 4, `.padding(8)` alone at 8,
/// and the chain at 12 — "the first call wins" reads 4, "the last call wins"
/// reads 8, and only accumulation reads 12. The two controls are `#require`d
/// to disagree first, so a broken fixture fails as one rather than passing as
/// "the chain equals one of them".
@MainActor
@Test func chainedPaddingAccumulatesOnAComponentAsItDoesOnAnElement() throws {
    @MainActor func leafA<G: ElementGroup>(_ subject: G, _ log: ComponentLog) -> (x: Float, nodes: Int) {
        let frame = Frame(contentSize: Size(width: px(300), height: px(60)), scaleFactor: 1)
        var tree = Row { subject }
        frame.render(&tree)
        return (rect(log.bounds["a"]!).0, frame.tree.nodeCount)
    }

    let bareLog = ComponentLog()
    let bare = leafA(TwoAutoLeaves(log: bareLog), bareLog)
    let fourLog = ComponentLog()
    let four = leafA(TwoAutoLeaves(log: fourLog).padding(px(4)), fourLog)
    let eightLog = ComponentLog()
    let eight = leafA(TwoAutoLeaves(log: eightLog).padding(px(8)), eightLog)
    let chainLog = ComponentLog()
    let chain = leafA(TwoAutoLeaves(log: chainLog).padding(px(4)).padding(px(8)), chainLog)

    try #require(four.x != eight.x,
                 "the two controls must disagree, or the chain's reading proves nothing; got \(four) and \(eight)")
    #expect(four.x == 4 && eight.x == 8, "controls: got \(four) and \(eight)")
    #expect(chain.x == 12,
            "4 then 8 must accumulate to 12 (first-wins 4, last-wins 8); got \(chain.x)")
    // One wrapper per member per call: +2 for one call, +4 for two.
    #expect(four.nodes == bare.nodes + 2 && eight.nodes == bare.nodes + 2,
            "one call adds one wrapper per member; got \(four.nodes), \(eight.nodes) against \(bare.nodes)")
    #expect(chain.nodes == bare.nodes + 4,
            "two calls add two wrappers per member; got \(chain.nodes) against \(bare.nodes)")
}

// MARK: - Outer modifiers, lane 4 (OM-D, OM-E, OM-F): a component's padding WRAPS each member

// Plan task 5, `docs/superpowers/specs/2026-09-15-outer-modifiers-design.md`
// §4.4, §5.4 and §6.4. Every expectation below is a SwiftUI number from probe
// `docs/probes/swiftui-component-distribution.swift` (arm ids in each doc
// comment), except where a test says it pins MetalUI's OWN reading and names
// the divergence (`OM-F`).
//
// The fixtures are the probe's: `Pair` (a 30x10 and a 50x10), `Solo` (one
// 30x10) and `SoloText` (one content-sized `Text("Hi")`). `TwoLeaves` above is
// NOT `Pair` — its second member is 30 tall, for the transparency tests' own
// reason — so the G2 shape gets its own fixture.

/// The probe's `SoloText`: a component whose body is one CONTENT-SIZED leaf.
/// This is the row CLAUDE.md's inert table made inert on the old amend
/// (`Style.padding` on a content-sized leaf is ignored), and the most likely
/// first component anyone writes.
private struct SoloText: Component {
    var content: some ElementGroup { Text("Hi") }
}

/// The probe's `Solo`: one fixed 30x10 leaf.
private struct SoloLeaf: Component {
    let log: ComponentLog
    var content: some ElementGroup { Leaf("solo", log: log).width(px(30)).height(px(10)) }
}

/// The probe's `Pair`: a 30x10 and a 50x10.
private struct PairLeaves: Component {
    let log: ComponentLog
    var content: some ElementGroup {
        Leaf("a", log: log).width(px(30)).height(px(10))
        Leaf("b", log: log).width(px(50)).height(px(10))
    }
}

/// The subject's outer footprint, read the way record §15's scratch arms read
/// it: a 1x1 marker leaf declared after the subject in a `Row` gives its
/// outer WIDTH as the marker's x, and the same in a `Column` gives its outer
/// HEIGHT as the marker's y. `.alignItems(.flexStart)` on both, because a
/// `Row` centres on the cross axis (EP-8) and the subject's y would otherwise
/// be the row's answer rather than the modifier's. `nodes` is the row render's
/// node count.
@MainActor
private func outerFootprint<G: ElementGroup>(_ subject: G, log: ComponentLog = ComponentLog())
    -> (width: Float, height: Float, nodes: Int) {
    let rowLog = ComponentLog()
    let rowFrame = Frame(contentSize: Size(width: px(300), height: px(100)), scaleFactor: 1)
    var row = Row {
        subject
        Leaf("marker", log: rowLog).width(px(1)).height(px(1))
    }.alignItems(.flexStart)
    rowFrame.render(&row)

    let columnLog = ComponentLog()
    let columnFrame = Frame(contentSize: Size(width: px(300), height: px(100)), scaleFactor: 1)
    var column = Column {
        subject
        Leaf("marker", log: columnLog).width(px(1)).height(px(1))
    }.alignItems(.flexStart)
    columnFrame.render(&column)

    return (rect(rowLog.bounds["marker"]!).0,
            rect(columnLog.bounds["marker"]!).1,
            rowFrame.tree.nodeCount)
}

/// **`.padding` on a component wraps each top-level node in a real padding
/// node** (`OM-D`), producing SwiftUI's numbers on both body kinds:
///
/// - **G10/G11**: `SoloText()` is 13x16 and `.padding(20)` makes it **53x56**.
///   The 13x16 is the system font's answer for `Text("Hi")` on this machine —
///   the SAME 13x16 MetalUI's own `Text("Hi")` measures (record §15, scratch
///   T1) — and 53 is the SAME 53 MetalUI's ELEMENT path already produces for
///   `Text("Hi").padding(20)` (scratch T2). So SwiftUI and the element path
///   agree digit for digit, and before this lane the COMPONENT path alone was
///   inert here (the marker stayed at 13).
/// - **G12**: `Solo()` is 30x10 and `.padding(20)` makes it **70x50** with the
///   leaf at (20, 20). Before this lane the amend absorbed the declared 30x10
///   into CSS border-box padding and the node read 40x40.
///
/// The literal 13x16 is the font's, not the modifier's: if it ever reads
/// otherwise, the mechanism claim is the RELATIVE one (`+40` on each axis)
/// and the literals are the machine's.
@MainActor
@Test func aComponentsPaddingWrapsEachTopLevelNode() throws {
    // The content-sized body (G10/G11).
    let bareText = outerFootprint(SoloText())
    let paddedText = outerFootprint(SoloText().padding(px(20)))
    #expect(bareText.width == 13 && bareText.height == 16,
            "SoloText bare: SwiftUI's G10 and record §15 T1 both read 13x16 on this machine; got \(bareText)")
    #expect(paddedText.width == bareText.width + 40 && paddedText.height == bareText.height + 40,
            "SoloText.padding(20) must grow the footprint by 40 on each axis, as G11 does; got \(paddedText) against \(bareText)")
    #expect(paddedText.width == 53 && paddedText.height == 56,
            "SoloText.padding(20): SwiftUI's G11 reads 53x56; got \(paddedText)")
    #expect(paddedText.nodes == bareText.nodes + 1,
            "one member, one wrapper node; got \(paddedText.nodes) against \(bareText.nodes)")

    // The fixed-size body (G12).
    let bareLog = ComponentLog()
    let bareLeaf = outerFootprint(SoloLeaf(log: bareLog), log: bareLog)
    let paddedLog = ComponentLog()
    let paddedLeaf = outerFootprint(SoloLeaf(log: paddedLog).padding(px(20)), log: paddedLog)
    #expect(bareLeaf.width == 30 && bareLeaf.height == 10, "Solo bare: G5 reads 30x10; got \(bareLeaf)")
    #expect(paddedLeaf.width == 70 && paddedLeaf.height == 50,
            "Solo.padding(20): SwiftUI's G12 reads 70x50 (today's amend reads 40x40); got \(paddedLeaf)")
    #expect(paddedLeaf.nodes == bareLeaf.nodes + 1,
            "one member, one wrapper node; got \(paddedLeaf.nodes) against \(bareLeaf.nodes)")
    // The leaf keeps its own 30x10 and sits at the padding inset — the last
    // render `outerFootprint` did is the column's, whose flex-start puts the
    // subject at the origin, so the leaf's rect is (20, 20, 30, 10) exactly.
    #expect(rect(paddedLog.bounds["solo"]!) == (20, 20, 30, 10),
            "the leaf keeps 30x10 and sits at (20, 20) inside its wrapper, as G12's `a` does; got \(rect(paddedLog.bounds["solo"]!))")
}

/// **G2's shape, exactly**: a two-member component at `.padding(8)` is 120x26
/// with `a` at (8, 8) 30x10 and `b` at (62, 8) 50x10 — `(30+16) + 8 + (50+16)`,
/// each member padded, one wrapper per member. This is `CO-U`'s measurement
/// re-taken from source, and the shape a wrap around the PAIR cannot produce
/// (it predicts 96–104 and puts `b` at x 46). The `Row` carries `.gap(8)`
/// because SwiftUI's `HStack` spacing is implicit and MetalUI's is explicit;
/// the marker therefore sits at 128 and the outer width is `128 - 8`.
@MainActor
@Test func aTwoMemberComponentsPaddingIsAppliedToEachMember() throws {
    @MainActor func arms<G: ElementGroup>(_ subject: G, _ log: ComponentLog)
        -> (a: (Float, Float, Float, Float), b: (Float, Float, Float, Float), marker: Float, nodes: Int) {
        let markerLog = ComponentLog()
        let frame = Frame(contentSize: Size(width: px(300), height: px(100)), scaleFactor: 1)
        var tree = Row {
            subject
            Leaf("marker", log: markerLog).width(px(1)).height(px(1))
        }.gap(px(8)).alignItems(.flexStart)
        frame.render(&tree)
        return (rect(log.bounds["a"]!), rect(log.bounds["b"]!),
                rect(markerLog.bounds["marker"]!).0, frame.tree.nodeCount)
    }

    let bareLog = ComponentLog()
    let bare = arms(PairLeaves(log: bareLog), bareLog)
    let paddedLog = ComponentLog()
    let padded = arms(PairLeaves(log: paddedLog).padding(px(8)), paddedLog)

    // G0/G1: the bare pair is 88x10, `a` at (0, 0), `b` at (38, 0).
    try #require(bare.a == (0, 0, 30, 10) && bare.b == (38, 0, 50, 10) && bare.marker == 96,
                 "the control must read G1's 88x10 pair (marker at 88 + 8); got \(bare)")

    #expect(padded.a == (8, 8, 30, 10), "G2: a at (8, 8) 30x10; got \(padded.a)")
    #expect(padded.b == (62, 8, 50, 10),
            "G2: b at (62, 8) 50x10 — after a's 46-wide wrapper, the 8 gap, and its own 8 inset; got \(padded.b)")
    #expect(padded.marker - 8 == 120, "G2: outer width 120; got \(padded.marker - 8)")
    #expect(padded.nodes == bare.nodes + 2,
            "two members, two wrapper nodes; got \(padded.nodes) against \(bare.nodes)")
}

/// **A component's modifiers apply in the order they are written** (`OM-E`):
/// `.padding(4).width(70)` sizes the PADDED box to 70 and leaves the member
/// 30 wide; `.width(70).padding(4)` sizes the MEMBER to 70 and then pads it,
/// for an outer 78. `StyledComponent` keeps an ordered op list with a "current
/// node" per member — a `.wrap` replaces the current node, an `.amend` writes
/// it — so a `width` written after a `padding` lands on the wrapper.
///
/// **This test pins MetalUI's OWN two readings, and they are NOT SwiftUI's
/// member geometry** (`OM-F`, a recorded divergence owned by task 4). SwiftUI's
/// G15 (`Solo().padding(4).frame(width: 70)`) reads 70x18 with the member still
/// 30 wide, CENTRED at x 20; G16 (`.frame(width: 70).padding(4)`) reads 78x18
/// with the member 30 wide at x 24. SwiftUI's `.frame` WRAPS and keeps the
/// member's size; MetalUI's `Component.width` AMENDS and overwrites it, so the
/// second order here makes the member itself 70 wide, and the first order
/// leaves the 30-wide member at the wrapper's leading inset (x 4) rather than
/// centred. The OUTER widths agree with SwiftUI in both orders (70 and 78);
/// the member's does not. What this test proves is that the two orders
/// DIFFER — the property an ordered op list exists to deliver, and which an
/// amend-set-plus-wrap-set collapses — `#require`d before either reading is
/// compared.
@MainActor
@Test func aModifierOnAComponentAppliesInTheOrderItIsWritten() throws {
    @MainActor func reading<G: ElementGroup>(_ subject: G, _ log: ComponentLog)
        -> (leaf: (Float, Float, Float, Float), outer: Float) {
        let markerLog = ComponentLog()
        let frame = Frame(contentSize: Size(width: px(300), height: px(100)), scaleFactor: 1)
        var tree = Row {
            subject
            Leaf("marker", log: markerLog).width(px(1)).height(px(1))
        }.alignItems(.flexStart)
        frame.render(&tree)
        return (rect(log.bounds["solo"]!), rect(markerLog.bounds["marker"]!).0)
    }

    let padThenWidthLog = ComponentLog()
    let padThenWidth = reading(SoloLeaf(log: padThenWidthLog).padding(px(4)).width(px(70)), padThenWidthLog)
    let widthThenPadLog = ComponentLog()
    let widthThenPad = reading(SoloLeaf(log: widthThenPadLog).width(px(70)).padding(px(4)), widthThenPadLog)

    try #require(padThenWidth.leaf != widthThenPad.leaf || padThenWidth.outer != widthThenPad.outer,
                 "the two orders must disagree, or the op list is not ordered; both read \(padThenWidth)")

    // MetalUI's own numbers. G15's outer 70 agrees; its member (30 wide at
    // x 20, centred) does not — the wrapper is a flex-start box, not a
    // centring frame (OM-F: `width` is not `frame`).
    #expect(padThenWidth.outer == 70, "padding(4).width(70): the padded box is 70 wide; got \(padThenWidth.outer)")
    #expect(padThenWidth.leaf == (4, 4, 30, 10),
            "padding(4).width(70): the member keeps 30x10 at the 4 inset; got \(padThenWidth.leaf)")
    // G16's outer 78 agrees; its member (30 wide at x 24) does not — the
    // amend overwrote the member's own 30 with 70 (OM-F).
    #expect(widthThenPad.outer == 78, "width(70).padding(4): 70 + 8; got \(widthThenPad.outer)")
    #expect(widthThenPad.leaf == (4, 4, 70, 10),
            "width(70).padding(4): the member itself is 70 wide (OM-F), at the 4 inset; got \(widthThenPad.leaf)")
}

/// **`width` on a component still OVERWRITES each member's own declared width**
/// — pinned wrong on purpose (`OM-F`), owned by task 4. SwiftUI's G7
/// (`Pair().frame(width: 70)`) reads outer 148 with the members STILL 30 and
/// 50 wide, centred in 70 each; G8 (`Solo().frame(width: 70)`) reads 70 with
/// the member 30 at x 20. MetalUI's `Component.width` is an amend of the
/// member's own `Style.size.width`, so both members read 70 here — `CO-U`'s
/// measurement (30/50 → 70/70), re-taken. When task 4 makes `width` wrap,
/// this test flips to G7's numbers.
@MainActor
@Test func aComponentsWidthStillOverwritesItsMembersDeclaredWidth() {
    let bareLog = ComponentLog()
    let bareFrame = Frame(contentSize: Size(width: px(300), height: px(40)), scaleFactor: 1)
    var bare = Row { TwoLeaves(log: bareLog) }
    bareFrame.render(&bare)

    let log = ComponentLog()
    let frame = Frame(contentSize: Size(width: px(300), height: px(40)), scaleFactor: 1)
    var tree = Row { TwoLeaves(log: log).width(px(70)) }
    frame.render(&tree)

    #expect(rect(bareLog.bounds["a"]!).2 == 30 && rect(bareLog.bounds["b"]!).2 == 50,
            "control: the members declare 30 and 50; got \(rect(bareLog.bounds["a"]!)) and \(rect(bareLog.bounds["b"]!))")
    #expect(rect(log.bounds["a"]!).2 == 70,
            "WRONG ON PURPOSE — OM-F. SwiftUI's G7 keeps the member 30 wide inside a 70 frame; MetalUI's amend makes the member itself 70. If this reads 30, task 4 landed; flip to G7. Got \(rect(log.bounds["a"]!))")
    #expect(rect(log.bounds["b"]!).2 == 70,
            "WRONG ON PURPOSE — OM-F, member b: G7 keeps it 50; got \(rect(log.bounds["b"]!))")
    #expect(frame.tree.nodeCount == bareFrame.tree.nodeCount,
            "an amend adds no node; got \(frame.tree.nodeCount) against \(bareFrame.tree.nodeCount)")
}
