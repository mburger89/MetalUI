import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUI

// M4 spec 2. A `Component` is TRANSPARENT to layout and OPAQUE to identity:
// it contributes no layout node of its own, and it consumes one cursor index so
// that its `@State` has an id to hang on. Those are separate axes and this is
// the first type in the framework to use them differently — every other element
// is opaque to both. **This file pins the layout-transparency half only.** The
// identity-opaque half's own mechanics — the cursor arithmetic that gives a
// component an id, `content` materialized once rather than re-evaluated per
// phase — are Task 2's `ComponentTests` additions to pin, not this file's.
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
/// `layout.content` reddens **10 issues across 6 of this file's 14 tests** —
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
/// SwiftUI measurement is about the DESIGN (distribute, don't wrap); it is not
/// reproducible as a literal number here, because SwiftUI's `.padding()` grows
/// a fixed-size frame (content-box-shaped) where this engine's `.padding()`
/// is border-box only (`Style.swift:97`) and cannot move a box with an
/// explicit size at all — see `TwoAutoLeaves`' own doc for the mismatch this
/// forced, measured against the brief's literal fixture before it was changed.
///
/// **Both halves are asserted and both are needed.** The node count alone cannot
/// tell distribution from a modifier that did nothing at all; the rects alone
/// cannot tell distribution from wrapping in every fixture. Together they can.
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

    // Transparency survives the modifier: still no node of the component's own.
    #expect(padFrame.tree.nodeCount == bareFrame.tree.nodeCount,
            "a modified component must still add no node; got \(padFrame.tree.nodeCount) against \(bareFrame.tree.nodeCount)")

    // And EACH leaf grew by the padding on both axes — distribution, not one
    // padding around the pair.
    let bareA = rect(bareLog.bounds["a"]!)
    let padA = rect(padLog.bounds["a"]!)
    #expect(padA.2 == bareA.2 + 8, "leaf a's width gains 2x4; got \(padA.2) against \(bareA.2)")
    let bareB = rect(bareLog.bounds["b"]!)
    let padB = rect(padLog.bounds["b"]!)
    #expect(padB.2 == bareB.2 + 8,
            "leaf b's width gains 2x4 too — this is the assertion that separates distribution from wrapping")
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

/// `.padding(_:).padding(_:)` — chained onto the SAME field, unlike
/// width/height above. `StyledElement.modifying` (`Box.swift:293`) does not
/// merge two calls to the same modifier; it assigns the field directly, so a
/// second `.padding(_:)` on a `Box` simply overwrites the first one's value.
/// `StyledComponent`'s chained `padding(_:)` reproduces exactly that — run
/// and measured here rather than assumed: the SECOND value wins outright,
/// and the two do NOT accumulate (4 then 8 reads as a border box padded by
/// 8, not by 4, and not by 12).
@MainActor
@Test func chainedPaddingReplacesRatherThanAccumulates() {
    let log = ComponentLog()
    let frame = Frame(contentSize: Size(width: px(300), height: px(60)), scaleFactor: 1)
    var tree = Row { TwoAutoLeaves(log: log).padding(px(4)).padding(px(8)) }
    frame.render(&tree)

    // Content is 0 (Leaf has no children and no measure), so the border box
    // is padding alone: 2x8 = 16 if the second call wins, 2x4 = 8 if the
    // first call wins, 2x(4+8) = 24 if the two accumulated.
    #expect(rect(log.bounds["a"]!).2 == 16,
            "the second .padding(_:) call must win outright; got \(rect(log.bounds["a"]!).2)")
    #expect(rect(log.bounds["b"]!).2 == 16, "got \(rect(log.bounds["b"]!).2)")
}
