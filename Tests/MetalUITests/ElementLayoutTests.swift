import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUI

// Task 4: the flex engine's first production caller. Six milestones of engine
// with 81 browser fixtures already pin *flexbox*; what is new here is the
// **plumbing** — that a container hands the engine its children in source
// order, that each child reads back its own rect and not a sibling's or its
// parent's, and that the builder folds a block into concrete types rather than
// boxes.
//
// So the layout assertions below compare against the same tree built by hand
// and run through `computeLayout` directly. A divergence therefore means the
// plumbing is wrong, not that flexbox is. Literal numbers are asserted
// alongside, because two runs of a broken engine agree with each other.

// MARK: - Probes

/// Records what each phase was handed, by name.
///
/// A **class** for the same reason `PhaseLog` is one: `Element`'s phases are
/// `mutating` on a value type, so anything recorded into the struct would be
/// observed on whichever copy the driver happened to keep.
@MainActor
final class ElementLog {
    /// `requestLayout` entries, in call order — this is the order children are
    /// registered with the engine, and therefore flex order.
    var registered: [String] = []
    var bounds: [String: Bounds<Pixels>] = [:]
    /// The node each probe was issued, so a test can hold a real id rather than
    /// fabricating one through an initialiser the module keeps internal.
    var nodes: [String: LayoutNodeID] = [:]
    /// Cross-frame counter readings, in the order the probes took them.
    var counters: [(name: String, value: Int)] = []
    /// Identities as delivered to `prepaint`, in call order.
    ///
    /// **This was `[(String, GlobalElementID?)]` read through a double
    /// optional**, because `nil` was a real answer before structural identity
    /// and a dictionary would have swallowed the difference between "unnamed
    /// ancestor" and "never visited". Every element now has an identity, so the
    /// inner optional is gone; the array stays, because two probes may share a
    /// name and order is what `aContainerGivesItsChildrenPathsBuiltFromItsOwn`
    /// reads.
    var identities: [(name: String, id: GlobalElementID)] = []

    func identity(of name: String) -> GlobalElementID? {
        identities.first { $0.name == name }?.id
    }
}

/// A childless element that records the bounds and identity its phases receive.
///
/// Conforms to `StyledElement`, so the production modifiers apply to it and a
/// modifier that writes the wrong `Style` field shows up as a wrong rect here.
@MainActor
struct Probe: Element, StyledElement {
    var style = Style()
    var decoration = Decoration()
    var elementID: ElementID?
    let name: String
    let log: ElementLog

    init(_ name: String, log: ElementLog) {
        self.name = name
        self.log = log
    }

    func requestLayout(_ id: GlobalElementID,
                       pass: inout LayoutPass) -> (LayoutNodeID, LayoutNodeID) {
        log.registered.append(name)
        let node = pass.requestNode(style: style, children: [])
        log.nodes[name] = node
        return (node, node)
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                  layout: inout LayoutNodeID, pass: inout PrepaintPass) {
        log.bounds[name] = bounds
        log.identities.append((name, id))
    }

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
               layout: inout LayoutNodeID, prepaint: inout Void, pass: inout PaintPass) {}
}

private func px(_ v: Float) -> Pixels { Pixels(v) }

private func rect(_ b: Bounds<Pixels>) -> (Float, Float, Float, Float) {
    (b.origin.x.value, b.origin.y.value, b.size.width.value, b.size.height.value)
}

private func rect(_ r: LayoutRect) -> (Float, Float, Float, Float) {
    (Float(r.x), Float(r.y), Float(r.width), Float(r.height))
}

// MARK: - The allocation guard (§4.6 mitigation 1)

/// The builder preserves concrete types — nothing is boxed on the static path.
///
/// **No behavioural test in this file can see this.** A builder that erased
/// every child to `AnyElement` lays out identically, paints identically, and
/// leaves the whole suite green while §4.6's first allocation mitigation is
/// gone. Measured: adding **both** `buildExpression<E: Element>(_:) -> AnyElement`
/// and `buildExpression(_ e: AnyElement) -> AnyElement` to `ElementBuilder`
/// reddens this test, `aThreeChildBlockNestsPairsRatherThanFlattening`
/// and `controlFlowInABlockStaysUnboxed` — the three type-level tests — and
/// **no behavioural test at all**, out of 303. That "nothing else" is the
/// finding, and it is what justifies asserting on a type name.
///
/// The generic overload alone is not a usable mutation any more: it makes the
/// suite fail to *compile*, because `anExplicitAnyElementIsStillAcceptedAsAChild`
/// below puts an `AnyElement` in a builder block and `buildExpression<E: Element>`
/// then requires `AnyElement: Element`. The non-generic overload is what gives
/// the type checker a path and turns the mutation back into a measurement.
///
/// Both halves are needed. `contains("Pair")` alone passes against a
/// `Pair<AnyElement, AnyElement>`; `!contains("AnyElement")` alone passes
/// against a builder that flattened everything into one node type.
@MainActor
@Test func theBuilderPreservesConcreteTypesRatherThanBoxing() {
    let column = Column { Box(); Box() }
    let name = String(describing: type(of: column))

    #expect(name.contains("Pair"))
    #expect(!name.contains("AnyElement"))
    // The spec's own spelling: `Column<Pair<…>>`, not `Column<[…]>` and not a
    // wrapper element between the column and its children.
    #expect(name.hasPrefix("Column<Pair<"))
}

/// Three statements nest left — `Pair<Pair<A, B>, C>` — and stay concrete.
///
/// Arity is where a "preserve types" builder is most tempted to give up: a
/// `buildBlock` ladder runs out, and `[AnyElement]` is the easy escape.
@MainActor
@Test func aThreeChildBlockNestsPairsRatherThanFlattening() {
    let row = Row { Box(); Box(); Box() }
    let name = String(describing: type(of: row))

    #expect(name.hasPrefix("Row<Pair<Pair<"))
    #expect(!name.contains("AnyElement"))
}

/// `if`, `if`/`else` and `for` keep concrete types too.
///
/// These are the three constructs a builder normally erases, so the mitigation
/// would leak here first even if the straight-line path stayed honest.
@MainActor
@Test func controlFlowInABlockStaysUnboxed() {
    let flag = Bool.random()
    let column = Column {
        if flag { Box() }
        if flag { Box() } else { Row { Box() } }
        for _ in 0..<3 { Box() }
    }
    let name = String(describing: type(of: column))

    #expect(name.contains("OptionalGroup"))
    #expect(name.contains("EitherGroup"))
    #expect(name.contains("ArrayGroup"))
    #expect(!name.contains("AnyElement"))
}

/// `AnyElement` is still reachable — the escape hatch exists, it is just not the
/// default (§4.6).
///
/// Without this, "the builder never boxes" would be indistinguishable from
/// "boxing is impossible", and a future reader could delete the erasure as dead.
@MainActor
@Test func anExplicitAnyElementIsStillAcceptedAsAChild() {
    let log = ElementLog()
    let frame = Frame(contentSize: Size(width: px(200), height: px(80)), scaleFactor: 1)
    var row = Row {
        AnyElement(Probe("erased", log: log).width(px(40)).height(px(25)))
        Probe("plain", log: log).width(px(60)).height(px(15))
    }

    frame.render(&row)

    #expect(String(describing: type(of: row)).contains("AnyElement"))
    // **Was `(0, 0, 40, 25)` and `(40, 0, 60, 15)` before ruling EP-8**, when
    // `Row` inherited CSS's `align-items: stretch` and every child sat at the
    // line's leading edge. `Row` now centres on the cross axis; only the two
    // `y`s moved, which is what "centring, not a resize" looks like.
    //
    // Derived rather than pasted. The row's content box is the whole 200x80
    // frame — no padding — so the cross extent is 80:
    //   erased: y = (80 - 25) / 2 = **27.5**, then `roundLayout` takes the
    //           cumulative edges: y0 = 27.5.rounded() = 28,
    //           y1 = 52.5.rounded() = 53, height = 25.
    //   plain:  y = (80 - 15) / 2 = **32.5** → y0 = 33, y1 = 47.5 → 48,
    //           height = 15.
    // Both offsets land on a half pixel, so these two numbers also pin
    // `roundLayout`'s half-away-from-zero rule. That is engine-internal and
    // deterministic — not the WebKit 1/64 hazard the practices doc warns about,
    // which is a disagreement between two engines and has no counterpart here.
    #expect(rect(log.bounds["erased"]!) == (0, 28, 40, 25))
    // The boxed child still contributes its node in source order: the plain
    // sibling begins where it ends. That is the `x`, and EP-8 does not touch it.
    #expect(rect(log.bounds["plain"]!) == (40, 33, 60, 15))
}

// MARK: - The plumbing

/// The fixture both halves of `aNestedLayoutMatchesTheEngineRunDirectly` use.
///
/// Deliberately three levels, non-square at every level, with no two children
/// the same size and no origin at zero below the root:
///
/// - a 400x120 root, so width and height cannot be confused;
/// - `padding: 10` on the root and `5` on the column, so a grandchild's origin
///   (15) is neither zero, nor the root's padding, nor the column's;
/// - children of 100x30 and 60x20, so reading the wrong child index moves every
///   number.
private enum Fixture {
    static let contentSize = Size(width: px(400), height: px(120))

    static func styles() -> (root: Style, column: Style, a: Style, b: Style, c: Style) {
        var root = Style()
        root.flexDirection = .row
        root.padding = Edges(all: .pixels(px(10)))
        root.gap = Axes(both: .pixels(px(8)))
        // **Ruling EP-8, and the one line that stops these styles mirroring the
        // element tree.** `Style`'s `alignItems` default is `nil`, which the
        // engine reads as CSS's `stretch`; `Column.init`/`Row.init` now write
        // `.center` instead. The engine is deliberately NOT changed — the 81
        // browser fixtures depend on it answering as WebKit does — so the
        // hand-built tree has to say `.center` out loud to be the same tree.
        // Deleting either line below is a real mutation of this fixture and
        // reddens `aNestedLayoutMatchesTheEngineRunDirectly`.
        root.alignItems = .center

        var column = Style()
        column.flexDirection = .column
        column.size = Size(width: .length(.pixels(px(150))), height: .length(.pixels(px(90))))
        column.padding = Edges(all: .pixels(px(5)))
        column.gap = Axes(both: .pixels(px(4)))
        column.alignItems = .center

        var a = Style()
        a.size = Size(width: .length(.pixels(px(100))), height: .length(.pixels(px(30))))
        var b = Style()
        b.size = Size(width: .length(.pixels(px(60))), height: .length(.pixels(px(20))))
        var c = Style()
        c.size = Size(width: .length(.pixels(px(90))), height: .length(.pixels(px(60))))

        return (root, column, a, b, c)
    }

    /// The same tree built straight onto a `LayoutTree` and run through
    /// `computeLayout` — the oracle for the pipeline's answer.
    static func directEngineRects() -> (a: LayoutRect, b: LayoutRect, c: LayoutRect,
                                        column: LayoutRect, root: LayoutRect, nodeCount: Int) {
        let s = styles()
        let tree = LayoutTree(generation: 0)
        let a = tree.newNode(style: s.a, children: [])
        let b = tree.newNode(style: s.b, children: [])
        let column = tree.newNode(style: s.column, children: [a, b])
        let c = tree.newNode(style: s.c, children: [])
        let root = tree.newNode(style: s.root, children: [column, c])

        computeLayout(tree, root: root,
                      available: AvailableSpaceSize(
                        width: .definite(Double(contentSize.width.value)),
                        height: .definite(Double(contentSize.height.value))),
                      rootFontSize: 16)

        return (tree.layout(a), tree.layout(b), tree.layout(c),
                tree.layout(column), tree.layout(root), tree.nodeCount)
    }

    /// The same tree as elements, built with the production modifiers.
    ///
    /// The styles are written twice on purpose — once as `Style` above, once
    /// through modifiers here. A modifier that wrote `padding` into `margin`, or
    /// transposed two edges, shows up as a disagreement between the two.
    @MainActor
    static func elementTree(log: ElementLog) -> some Element {
        Row {
            Column {
                Probe("a", log: log).width(px(100)).height(px(30))
                Probe("b", log: log).width(px(60)).height(px(20))
            }
            .width(px(150)).height(px(90)).padding(px(5)).gap(px(4))

            Probe("c", log: log).width(px(90)).height(px(60))
        }
        .padding(px(10)).gap(px(8))
    }
}

/// A nested layout resolves to the same rects the engine produces directly.
///
/// Two levels of container, non-square, asymmetric — a one-level square tree
/// cannot distinguish width from height, nor a child's own rect from its
/// parent's.
///
/// **The agreement is now conditional, and ruling EP-8 is the condition.** Until
/// EP-8 the element tree and `Fixture.styles()` were the same tree written twice
/// and the engine was an unconditional oracle for the pipeline. `Column`/`Row`
/// now add a cross-axis default the engine does not have, so the hand-built tree
/// carries `alignItems = .center` explicitly (see `Fixture.styles()`), and what
/// this test says is: **given that one declared difference, everything else
/// agrees.** That is still the claim worth making — the plumbing hands the
/// engine the children, in order, with the styles the modifiers wrote — and it
/// is why the fix is an explicit `.center` on the engine side rather than
/// dropping to a size-only comparison. A size-only comparison would be green
/// against a pipeline that put every child at the origin.
///
/// **The literal numbers below moved and the sizes did not**, which is the
/// second half of the same claim. Derived from the boxes, not read off a run:
///
/// - Root content box: x [10, 390], y [10, 110] — cross extent **100**.
///   - `column` (150x90): x = 10, y = 10 + (100 - 90) / 2 = **15**.
///   - `c` (90x60): x = 10 + 150 + 8 = 168, y = 10 + (100 - 60) / 2 = **30**.
/// - Column content box: x [15, 155] — cross extent **140** — y [20, 100].
///   - `a` (100x30): y = 20, x = 15 + (140 - 100) / 2 = **35**.
///   - `b` (60x20): y = 20 + 30 + 4 = 54, x = 15 + (140 - 60) / 2 = **55**.
///
/// Every one of those is an integer, so `roundLayout` is a no-op here and these
/// numbers pin centring alone.
@MainActor
@Test func aNestedLayoutMatchesTheEngineRunDirectly() {
    let log = ElementLog()
    let frame = Frame(contentSize: Fixture.contentSize, scaleFactor: 1)
    var tree = Fixture.elementTree(log: log)

    frame.render(&tree)

    let engine = Fixture.directEngineRects()

    #expect(rect(log.bounds["a"]!) == rect(engine.a))
    #expect(rect(log.bounds["b"]!) == rect(engine.b))
    #expect(rect(log.bounds["c"]!) == rect(engine.c))

    // And the literal numbers, so that "the pipeline agrees with the engine"
    // cannot be satisfied by both being wrong in the same way. Every field is
    // asserted with a value distinct from its neighbours.
    // Was (15, 15, 100, 30) / (15, 49, 60, 20) / (168, 10, 90, 60) under
    // stretch, when every child sat at its line's leading edge.
    #expect(rect(log.bounds["a"]!) == (35, 20, 100, 30))
    #expect(rect(log.bounds["b"]!) == (55, 54, 60, 20))
    #expect(rect(log.bounds["c"]!) == (168, 30, 90, 60))
}

/// The builder invents no layout nodes.
///
/// `Pair` is not an element and must not become one: a wrapper node would be a
/// flex container in its own right, so `Column { a; b }` would lay out as a
/// column containing a *row*. Five nodes for five boxes is the whole claim, and
/// the rect assertions above are what make a sixth node visible as more than a
/// count.
@MainActor
@Test func theBuilderContributesNoNodesOfItsOwn() {
    let log = ElementLog()
    let frame = Frame(contentSize: Fixture.contentSize, scaleFactor: 1)
    var tree = Fixture.elementTree(log: log)

    frame.render(&tree)

    #expect(frame.tree.nodeCount == 5)
    #expect(frame.tree.nodeCount == Fixture.directEngineRects().nodeCount)
}

/// Children reach the engine in source order.
///
/// Three children of **different widths** at three different x positions: with
/// equal children a reversed or rotated order is invisible, which is the point
/// of 30/50/70 rather than 50/50/50.
@MainActor
@Test func childrenAreRegisteredAndLaidOutInSourceOrder() {
    let log = ElementLog()
    let frame = Frame(contentSize: Size(width: px(300), height: px(40)), scaleFactor: 1)
    var row = Row {
        Probe("first", log: log).width(px(30)).height(px(10))
        Probe("second", log: log).width(px(50)).height(px(20))
        Probe("third", log: log).width(px(70)).height(px(30))
    }

    frame.render(&row)

    #expect(log.registered == ["first", "second", "third"])
    // **The three `y`s were all 0 before ruling EP-8** — stretch put every child
    // at the line's leading edge, which made them uniform and therefore blind to
    // a cross-axis mistake (practices doc, shape 1). Centring in a 40-tall row
    // gives three *different* `y`s, one per child height, so the order claim is
    // now readable on both axes:
    //   first:  (40 - 10) / 2 = 15
    //   second: (40 - 20) / 2 = 10
    //   third:  (40 - 30) / 2 =  5
    // All integral; no rounding step involved. The `x`s are unchanged, and they
    // are what "source order" means.
    #expect(rect(log.bounds["first"]!) == (0, 15, 30, 10))
    #expect(rect(log.bounds["second"]!) == (30, 10, 50, 20))
    #expect(rect(log.bounds["third"]!) == (80, 5, 70, 30))
}

/// A `Column` stacks vertically and a `Row` horizontally — the one thing the two
/// types differ in.
///
/// Same children, same sizes, one fixture each: without the pair, a `Column`
/// that had quietly kept `Style`'s default `.row` would still pass every rect
/// assertion written against a row.
@MainActor
@Test func columnStacksOnTheAxisRowDoesNot() {
    let rowLog = ElementLog()
    let rowFrame = Frame(contentSize: Size(width: px(200), height: px(80)), scaleFactor: 1)
    var row = Row {
        Probe("one", log: rowLog).width(px(40)).height(px(25))
        Probe("two", log: rowLog).width(px(60)).height(px(15))
    }
    rowFrame.render(&row)

    let columnLog = ElementLog()
    let columnFrame = Frame(contentSize: Size(width: px(200), height: px(80)), scaleFactor: 1)
    var column = Column {
        Probe("one", log: columnLog).width(px(40)).height(px(25))
        Probe("two", log: columnLog).width(px(60)).height(px(15))
    }
    columnFrame.render(&column)

    // **Was `(40, 0, …)` and `(0, 25, …)` before ruling EP-8.** Under stretch
    // the cross coordinate of each was 0; under centring each stack centres
    // `two` on its own cross axis, so the *pair* still says exactly what it
    // existed to say — the row advances `x` and the column advances `y` — and
    // now neither cross coordinate is 0, so a container that had quietly kept
    // the wrong `flexDirection` moves both numbers rather than one.
    //   row (cross = vertical, extent 80):   y = (80 - 15) / 2 = 32.5
    //                                            → `roundLayout` → 33
    //   column (cross = horizontal, extent 200): x = (200 - 60) / 2 = 70
    #expect(rect(rowLog.bounds["two"]!) == (40, 33, 60, 15))
    #expect(rect(columnLog.bounds["two"]!) == (70, 25, 60, 15))
}

// MARK: - The cross-axis default (ruling EP-8)

/// A stack centres its children on the cross axis; a `Box` still stretches.
///
/// **Nothing pinned the stack default before this test.** Every other layout
/// assertion in this file read it *incidentally* — which is why eight of them
/// moved when EP-8 landed — so a revert would have surfaced as eight
/// unexplained diffs in tests named for order, gaps, padding and hiding, and
/// none of them saying what the default is or why. This test is the only place
/// that states it.
///
/// **Both halves are load-bearing, and they fail to different mutations.**
///
/// - The `Column` half is EP-8 itself. 60 in 200 gives three distinct wrong
///   answers: `flexStart` and `stretch` both put a width-declared child at
///   **0**, `flexEnd` at **140**, `center` at **70**. So it separates centring
///   from the old default *and* from an overshoot, on one number.
/// - The `Box` half is EP-8's **split** — the ruling is implemented in
///   `Column.init`/`Row.init` and deliberately not in `Style`, so that the
///   engine keeps answering as WebKit does and the 81 browser fixtures stay
///   valid. Moving the default down into `Style.alignItems` would keep the
///   `Column` half green and redden this one. Without it, "at the element
///   layer" is a comment rather than a checked property.
///
/// **Measured, `--no-parallel`, 361 tests, one mutation at a time.**
///
/// - Deleting `style.alignItems = .center` from **`Column.init`** reddens
///   **three** tests, 6 issues: this one, `columnStacksOnTheAxisRowDoesNot` and
///   `aNestedLayoutMatchesTheEngineRunDirectly`. That is the mutation this test
///   exists for.
/// - Deleting it from **`Row.init`** reddens **seven**, 15 issues: this one and
///   the six row-shaped tests in this file. `paddingEdgesAreNotTransposed` and
///   `marginEdgesAreNotTransposed` are deliberately *not* among them — they
///   declare `.alignItems(.stretch)` explicitly, so the default cannot reach
///   them, which is the point of writing it there.
/// - **Moving the default down into `Style`** — `alignItems: AlignItems? =
///   .center` with both stack lines deleted — reddens **84** tests and 271
///   issues, almost all of them the browser corpus
///   (`rowStretchWithMarginsMatchesWebKit`, `wrapStretchAutoCrossMatchesWebKit`,
///   and so on) plus `defaultStyleMatchesCSSInitialValues`. Every element-layer
///   test in this file stays **green**, including `columnStacksOnTheAxisRowDoesNot`
///   and `aNestedLayoutMatchesTheEngineRunDirectly`, and the only thing in this
///   file that reddens is the `Box` half below. That 84-to-1 asymmetry is the
///   argument for the split stated as a number: the engine's `stretch` default
///   is load-bearing for WebKit agreement, and EP-8 must not touch it.
@MainActor
@Test func aStackCentresOnTheCrossAxisWhereABoxStretches() {
    let stackLog = ElementLog()
    let stackFrame = Frame(contentSize: Size(width: px(200), height: px(90)), scaleFactor: 1)
    var column = Column {
        Probe("stacked", log: stackLog).width(px(60)).height(px(20))
    }
    stackFrame.render(&column)

    let boxLog = ElementLog()
    let boxFrame = Frame(contentSize: Size(width: px(200), height: px(90)), scaleFactor: 1)
    var box = Box {
        Probe("boxed", log: boxLog).width(px(60)).height(px(20))
    }
    .flexDirection(.column)
    boxFrame.render(&box)

    // (200 - 60) / 2 = 70, integral, so `roundLayout` is a no-op.
    #expect(rect(stackLog.bounds["stacked"]!) == (70, 0, 60, 20))
    // `Box` is untouched by EP-8: CSS's `stretch`, which leaves a child that
    // declared its cross size sitting at the leading edge.
    #expect(rect(boxLog.bounds["boxed"]!) == (0, 0, 60, 20))

    // `Row` takes the same default, asserted here rather than left to the seven
    // row tests that read it incidentally — none of them is named for it.
    // Cross extent 90, child 20 tall: y = (90 - 20) / 2 = 35.
    let rowLog = ElementLog()
    let rowFrame = Frame(contentSize: Size(width: px(200), height: px(90)), scaleFactor: 1)
    var row = Row {
        Probe("rowed", log: rowLog).width(px(60)).height(px(20))
    }
    rowFrame.render(&row)
    #expect(rect(rowLog.bounds["rowed"]!) == (0, 35, 60, 20))
}

// MARK: - Identity (§4.3)

/// Builds a path from a sequence of local names, root to leaf — the
/// linked-list equivalent of the old struct's `GlobalElementID([ElementID]...)`
/// array literal (mirrors `StateTableTests.swift`'s private `id(_:)`). Every
/// component here is `.named`; `at: 0` is inert because a name always wins
/// over a position (`PathComponent`'s doc comment).
private func pathID(_ names: String...) -> GlobalElementID {
    var current: GlobalElementID?
    for name in names {
        current = GlobalElementID.child(of: current, at: 0, name: ElementID(name))
    }
    return current!
}

/// A container builds its children's paths from its own, so identity is a path
/// and not a local name.
///
/// **Not a duplicate of `sameLocalIDUnderDifferentParentsDoesNotShareState`.**
/// That one calls `GlobalElementID.child(of:at:name:)` and `StateTable`
/// directly and says nothing about who calls them; this is the first test in
/// the repo that a **production container** must satisfy — that `Box`,
/// `Column` and `Row` derive their children's identities from their own
/// rather than passing `nil` or a constant down. **Re-measured 2026-08-27,
/// `--no-parallel`, on a 358-test suite**: replacing
/// `GlobalElementID.child(of: parent, at: cursor, name: elementID)` with
/// `GlobalElementID.child(of: nil, at: cursor, name: elementID)` in
/// `Element.requestGroupLayout` (`ElementGroup.swift`, the default
/// implementation and not `AnyElement`'s copy) reddens **ten** tests —
/// this one and `anIdentifiedChildOfAnUnnamedContainerHasAnIdentityThroughItsPosition`
/// below, `twoSiblingsWithTheSameIDShareOneStateEntry` in
/// `ElementGroupTrapTests.swift`, and seven in `IdentityTests.swift`
/// (`theIndexSpaceIsFlatRatherThanNested`,
/// `reorderingANamedListCarriesEachItemsState`,
/// `reorderingAnUnnamedListKeepsStateWithThePositionNotTheItem`,
/// `flippingAnEitherBranchResetsTheBranchesState`,
/// `aBranchWithTwoMembersDoesNotLeakStateIntoAOneMemberBranch`,
/// `anElementAfterAVanishingIfAdoptsTheVanishedElementsState`,
/// `namingTheLaterSiblingIsWhatSurvivesAVanishingIf`). **This comment said
/// "eight" until Task 4 re-ran it**: the count was taken before the fix commit
/// that added the last two, which is ruling SI-H.
///
/// **Two things a first draft of this paragraph predicted and measurement
/// falsified**, which is why it is worth reading rather than trusting: it named
/// six tests, and it named `twoSiblingsWithDifferentIDsDoNotShareState` among
/// them. That one stays **green** — its two siblings have different names, so
/// they get distinct ids with or without a parent, and it cannot see this
/// mutation at all. Nothing in `StateTableTests.swift` moves either: it builds
/// every path it asserts by hand and never goes through a container.
///
/// The two `"leaf"` children carry the **same** local id under different
/// parents; only a path distinguishes them, and a table keyed on the local name
/// would give them one shared state entry with no layout or paint assertion able
/// to see it.
@MainActor
@Test func aContainerGivesItsChildrenPathsBuiltFromItsOwn() {
    let log = ElementLog()
    let frame = Frame(contentSize: Size(width: px(200), height: px(80)), scaleFactor: 1)
    var tree = Column {
        Row {
            Probe("left", log: log).id("leaf").width(px(10)).height(px(10))
        }
        .id("first")
        Row {
            Probe("right", log: log).id("leaf").width(px(10)).height(px(10))
        }
        .id("second")
    }
    .id("root")

    frame.render(&tree)

    #expect(log.identity(of: "left") == pathID("root", "first", "leaf"))
    #expect(log.identity(of: "right") == pathID("root", "second", "leaf"))
}

/// Identity **does** resume below an unnamed container (§4.3).
///
/// **Formerly `anIdentifiedChildOfAnUnnamedContainerStillHasNoIdentity`, and
/// this is the reversal the milestone exists for.** That test rendered exactly
/// this tree and asserted `log.identity(of: "deep") == GlobalElementID??.some(nil)`
/// — a named leaf under an unnamed `Row` got no identity at all, because
/// `ElementGroup`'s `requestGroupLayout` short-circuited to `nil` before
/// `GlobalElementID.child(of:at:name:)` was ever called. The tree is unchanged
/// on purpose so the two assertions can be read against each other.
///
/// The unnamed `Row` now contributes `.positional(0)` — its index in the
/// `Column`'s flat child list — and the leaf's own `.id("named")` sits under it.
/// Note what is *not* the answer: the leaf's path is **not**
/// `["root", "named"]`. A container that substituted its own parent's path when
/// it had no name would produce that, would pass every rect assertion in this
/// file, and would quietly give two unnamed siblings' children one shared state
/// entry — which is why the unnamed level is asserted explicitly rather than
/// skipped over.
@MainActor
@Test func anIdentifiedChildOfAnUnnamedContainerHasAnIdentityThroughItsPosition() {
    let log = ElementLog()
    let frame = Frame(contentSize: Size(width: px(200), height: px(80)), scaleFactor: 1)
    var tree = Column {
        Row {
            Probe("deep", log: log).id("named").width(px(10)).height(px(10))
        }
        // deliberately unnamed
    }
    .id("root")

    frame.render(&tree)

    let root = GlobalElementID.child(of: nil, at: 0, name: ElementID("root"))
    let unnamedRow = GlobalElementID.child(of: root, at: 0, name: nil)
    let leaf = GlobalElementID.child(of: unnamedRow, at: 0, name: ElementID("named"))

    #expect(log.identity(of: "deep") == leaf)
    // The unnamed level is a component of the path, not a level skipped: the
    // shorter path a "borrow the parent's id" container would produce is a
    // different id, and asserting it is not equal is what says so.
    #expect(log.identity(of: "deep") != GlobalElementID.child(of: root, at: 0,
                                                              name: ElementID("named")))
}

// MARK: - Modifiers

/// Each edge modifier lands on the edge it names.
///
/// **Four different values, and every one of them observable**: with a uniform
/// `padding(8)` an `init` that transposed top and bottom passes. `left` and
/// `top` show up in the child's origin; `right` and `bottom` show up in the
/// grown/stretched child's size, so a transposed pair moves a number.
///
/// **`.alignItems(.stretch)` is written here on purpose, and it is no longer
/// the default — ruling EP-8 made `Row` centre.** It is kept, rather than
/// re-baselined onto the new default, because centring would give this childless
/// `Probe` an `auto` cross size of **0**, and a zero extent hides transposition
/// errors: `height` stops carrying `bottom`, and two of the four edges would be
/// readable only through one `y`. Cross-axis extent is also **a shape this
/// engine has actually been wrong about** — CLAUDE.md's box-model work found
/// that a stretched item's cross size ignored its cross margins, WebKit
/// `50x65` against the engine's `50x100` — so an element-layer guard on it is
/// worth two tests sitting deliberately off the new default. The browser corpus
/// covers the composition at the engine level; this covers it through the
/// modifiers.
///
/// Derived, not pasted. Content box x [16, 392], y [4, 108]:
///   x      = left = **16**            (transposing left/right gives 8)
///   y      = top  = **4**             (transposing top/bottom gives 12)
///   width  = 400 - 16 - 8  = **376**
///   height = 120 -  4 - 12 = **104**  (stretch fills the content box)
@MainActor
@Test func paddingEdgesAreNotTransposed() {
    let log = ElementLog()
    let frame = Frame(contentSize: Size(width: px(400), height: px(120)), scaleFactor: 1)
    var row = Row {
        Probe("only", log: log).flexGrow(1)
    }
    .padding(Edges(top: .pixels(px(4)), right: .pixels(px(8)),
                   bottom: .pixels(px(12)), left: .pixels(px(16))))
    // Not the default since EP-8 — see the doc comment for why it stays.
    .alignItems(.stretch)

    frame.render(&row)

    // origin = (left, top); size = content box = (400-16-8, 120-4-12).
    #expect(rect(log.bounds["only"]!) == (16, 4, 376, 104))
}

/// Margins land on the edge they name too, and shrink the space available to
/// the item rather than moving it alone.
///
/// **`.alignItems(.stretch)` is written here on purpose and is no longer the
/// default** — see `paddingEdgesAreNotTransposed` above for the general reason.
/// This test is the *stronger* of the two cases for keeping it, because the
/// composition it exercises is **stretch x cross-margins**, and that is one of
/// the three real engine bugs the box-model milestone found: a stretched item's
/// cross size ignored its cross margins and overflowed its container, WebKit
/// `50x65` against the engine's `50x100`. A shape this engine has been wrong
/// about once keeps its element-layer guard; re-baselining onto centring would
/// have replaced it with a 0-height child that cannot see the bug at all.
///
/// Derived, not pasted:
///   x      = margin-left = **16**        (transposing left/right gives 8)
///   y      = margin-top  = **4**         (transposing top/bottom gives 12)
///   width  = 400 - 16 - 8  = **376**     (the item grows into what the margins left)
///   height = 120 -  4 - 12 = **104**     (stretch subtracts the cross margins —
///                                         the clause that was once missing)
@MainActor
@Test func marginEdgesAreNotTransposed() {
    let log = ElementLog()
    let frame = Frame(contentSize: Size(width: px(400), height: px(120)), scaleFactor: 1)
    var row = Row {
        Probe("only", log: log).flexGrow(1)
            .margin(Edges(top: .pixels(px(4)), right: .pixels(px(8)),
                          bottom: .pixels(px(12)), left: .pixels(px(16))))
    }
    // Not the default since EP-8 — see the doc comment for why it stays.
    .alignItems(.stretch)

    frame.render(&row)

    #expect(rect(log.bounds["only"]!) == (16, 4, 376, 104))
}

/// `gap(horizontal:vertical:)` writes both axes, and the row reads the
/// horizontal one.
///
/// Asymmetric on purpose: `gap(12)` sets both axes equal and cannot detect an
/// engine — or a modifier — reading the wrong one.
@MainActor
@Test func gapIsPerAxisAndTheRowReadsTheHorizontalOne() {
    let log = ElementLog()
    let frame = Frame(contentSize: Size(width: px(300), height: px(60)), scaleFactor: 1)
    var row = Row {
        Probe("first", log: log).width(px(30)).height(px(10))
        Probe("second", log: log).width(px(50)).height(px(20))
    }
    .gap(horizontal: px(20), vertical: px(5))

    frame.render(&row)

    // **Was `(50, 0, 50, 20)` before ruling EP-8** — stretch put `second` at
    // y = 0. The `x` is what this test is named for and it has not moved:
    // 30 + 20 = 50, so the row read the *horizontal* gap. The `y` is centring,
    // (60 - 20) / 2 = **20**, and it is worth asserting rather than dropping,
    // because a row that read the vertical gap (5) on the cross axis would
    // have to put it somewhere and this is where it would show.
    #expect(rect(log.bounds["second"]!) == (50, 20, 50, 20))
}

/// A `hidden()` child contributes no box, and its siblings close over it.
@MainActor
@Test func aHiddenChildTakesNoSpace() {
    let log = ElementLog()
    let frame = Frame(contentSize: Size(width: px(300), height: px(60)), scaleFactor: 1)
    var row = Row {
        Probe("first", log: log).width(px(30)).height(px(10))
        Probe("gone", log: log).width(px(50)).height(px(20)).hidden()
        Probe("third", log: log).width(px(70)).height(px(30))
    }

    frame.render(&row)

    // Third sits where the second would have, not 50 further along. **The `y`
    // was 0 before ruling EP-8**, when stretch put every child at the line's
    // leading edge; the row centres now, so y = (60 - 30) / 2 = **15**. The `x`
    // is the claim and it is unchanged.
    #expect(rect(log.bounds["third"]!) == (30, 15, 70, 30))
    // It is skipped as an item, not skipped as a phase: it still ran.
    #expect(log.registered == ["first", "gone", "third"])
}

/// `alignItems` and `alignSelf` reach the engine, and `alignSelf` wins.
///
/// Three children with three different cross-axis answers in one 90-tall row, so
/// a modifier that wrote the container's value onto the item — or the reverse —
/// moves at least one `y`.
///
/// **The container's value is `.flexEnd` because of ruling EP-8, and this is a
/// measured regression it caused rather than a stylistic choice.** The test used
/// to declare `.alignItems(.center)` on a `Row` whose inherited default was
/// CSS's `stretch`, so the modifier was load-bearing. EP-8 makes `.center` the
/// `Row` default, and the declaration became indistinguishable from saying
/// nothing — taxonomy shape 1, the container's value equal to the default it
/// was meant to override. **Measured, `--no-parallel`, 361 tests:** with
/// `.alignItems(.center)` still written here, replacing
/// `alignItems(_:)`'s body in `Box.swift` with `self` — a no-op modifier —
/// reddened exactly **one** test, `everyPublicModifierWritesItsOwnFieldAndOnlyThatField`,
/// which reads the `Style` field and never runs the engine. Nothing behavioural
/// noticed that the modifier had stopped working. With `.flexEnd` written here
/// the same mutation reddens **two** — that test and this one, `container`
/// falling from y 70 to the default's 30.
///
/// Derived, cross extent 90:
///   container: `flexEnd`   → y = 90 - 20 = **70**
///   start:     `flexStart` → y = **0**
///   centred:   `center`    → y = (90 - 30) / 2 = **30**
/// Three distinct answers, none of them the container's default, and the third
/// is now an `alignSelf` that *agrees with the old default* — so a build that
/// dropped `alignSelf` in favour of the container's value moves all three.
@MainActor
@Test func alignItemsAndAlignSelfBothReachTheEngine() {
    let log = ElementLog()
    let frame = Frame(contentSize: Size(width: px(300), height: px(90)), scaleFactor: 1)
    var row = Row {
        Probe("container", log: log).width(px(30)).height(px(20))
        Probe("start", log: log).width(px(40)).height(px(10)).alignSelf(.flexStart)
        Probe("centred", log: log).width(px(50)).height(px(30)).alignSelf(.center)
    }
    .alignItems(.flexEnd)

    frame.render(&row)

    #expect(rect(log.bounds["container"]!) == (0, 70, 30, 20))
    #expect(rect(log.bounds["start"]!) == (30, 0, 40, 10))
    #expect(rect(log.bounds["centred"]!) == (70, 30, 50, 30))
}

// MARK: - Ruling C-3

/// A `LayoutNodeID` minted in one frame is not valid in the next, and the tree
/// says so.
///
/// **This is m1a's ruling C-3 going live.** Task 4 is the first code to hold a
/// node id across a phase boundary, and `pass.withState` will hold one across a
/// *frame* boundary for anyone who asks — its `S` is unconstrained. Without a
/// generation the stale id resolves silently against the new frame's tree,
/// because both trees number from zero.
///
/// The indices are asserted equal first: that is what makes the generation
/// load-bearing rather than decorative.
@MainActor
@Test func aNodeIDDoesNotSilentlyResolveAgainstAnotherFramesTree() {
    let firstLog = ElementLog()
    let first = Frame(contentSize: Size(width: px(200), height: px(80)), scaleFactor: 1)
    var firstTree = Row { Probe("x", log: firstLog).width(px(20)).height(px(10)) }
    first.render(&firstTree)

    let secondLog = ElementLog()
    let second = Frame(contentSize: Size(width: px(200), height: px(80)), scaleFactor: 1)
    var secondTree = Row { Probe("y", log: secondLog).width(px(60)).height(px(40)) }
    second.render(&secondTree)

    // Real ids, issued by `LayoutPass.requestNode` in each frame — not
    // fabricated, so the test cannot pass against a `LayoutNodeID` the
    // production path would never mint.
    let stale = firstLog.nodes["x"]!
    let live = secondLog.nodes["y"]!

    #expect(stale.index == live.index)
    #expect(first.tree.generation != second.tree.generation)
    #expect(!second.tree.isCurrent(stale))
    #expect(second.tree.isCurrent(live))
    // And the reason it matters: index 0 addresses different geometry in the two
    // trees, so the silent answer would have been wrong rather than merely stale.
    #expect(rect(first.tree.layout(stale)) != rect(second.tree.layout(live)))
}

/// Every `Frame` takes a fresh generation, so no two frames' ids can be
/// confused — including frames alive at the same time.
@MainActor
@Test func everyFrameTakesADistinctTreeGeneration() {
    let generations = (0..<4).map { _ in
        Frame(contentSize: Size(width: px(10), height: px(10)), scaleFactor: 1).tree.generation
    }
    #expect(Set(generations).count == 4)
}
