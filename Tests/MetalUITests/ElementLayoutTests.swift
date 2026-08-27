import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUI

// Task 4: the flex engine's first production caller. Six milestones of engine
// with 61 browser fixtures already pin *flexbox*; what is new here is the
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
    /// Identities as delivered to `prepaint`; `nil` is a real answer (§4.3), so
    /// this is an array rather than a dictionary that would swallow it.
    var identities: [(name: String, id: GlobalElementID?)] = []

    func identity(of name: String) -> GlobalElementID?? {
        identities.first { $0.name == name }.map(\.id)
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

    func requestLayout(_ id: GlobalElementID?,
                       pass: inout LayoutPass) -> (LayoutNodeID, LayoutNodeID) {
        log.registered.append(name)
        let node = pass.requestNode(style: style, children: [])
        log.nodes[name] = node
        return (node, node)
    }

    func prepaint(_ id: GlobalElementID?, bounds: Bounds<Pixels>,
                  layout: inout LayoutNodeID, pass: inout PrepaintPass) {
        log.bounds[name] = bounds
        log.identities.append((name, id))
    }

    func paint(_ id: GlobalElementID?, bounds: Bounds<Pixels>,
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
    #expect(rect(log.bounds["erased"]!) == (0, 0, 40, 25))
    // The boxed child still contributes its node in source order: the plain
    // sibling begins where it ends.
    #expect(rect(log.bounds["plain"]!) == (40, 0, 60, 15))
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

        var column = Style()
        column.flexDirection = .column
        column.size = Size(width: .length(.pixels(px(150))), height: .length(.pixels(px(90))))
        column.padding = Edges(all: .pixels(px(5)))
        column.gap = Axes(both: .pixels(px(4)))

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
    #expect(rect(log.bounds["a"]!) == (15, 15, 100, 30))
    #expect(rect(log.bounds["b"]!) == (15, 49, 60, 20))
    #expect(rect(log.bounds["c"]!) == (168, 10, 90, 60))
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
    #expect(rect(log.bounds["first"]!) == (0, 0, 30, 10))
    #expect(rect(log.bounds["second"]!) == (30, 0, 50, 20))
    #expect(rect(log.bounds["third"]!) == (80, 0, 70, 30))
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

    #expect(rect(rowLog.bounds["two"]!) == (40, 0, 60, 15))
    #expect(rect(columnLog.bounds["two"]!) == (0, 25, 60, 15))
}

// MARK: - Identity (§4.3)

/// Builds a path from a sequence of local names, root to leaf — the
/// linked-list equivalent of the old struct's `GlobalElementID([ElementID]...)`
/// array literal (mirrors `StateTableTests.swift`'s private `id(_:)`).
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
/// That one calls `GlobalElementID.child(of:_:)` and `StateTable` directly and
/// says nothing about who calls them; this is the first test in the repo that a
/// **production container** must satisfy — that `Box`, `Column` and `Row` derive
/// their children's identities from their own rather than passing `nil`, their
/// own path, or `.root` down. Measured: building the child id from `.root`
/// instead of `parent` in `ElementGroup.swift` reddens this and nothing in
/// `StateTableTests`.
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

/// Identity does not resume below an anonymous container (§4.3).
///
/// `GlobalElementID.child(of:_:)` returns `nil` when either end is anonymous,
/// and a container is an "end". Named leaf, unnamed parent, no identity.
///
/// `anIdentifiedChildOfAnAnonymousParentHasNoIdentity` pins the *rule* on the
/// function; this pins that a real container obeys it, including the part that
/// is easy to get wrong by being helpful — a container that substituted its own
/// parent's path when it had no id of its own would pass every rect assertion
/// here and quietly give two anonymous siblings' children one shared entry.
@MainActor
@Test func anIdentifiedChildOfAnUnnamedContainerStillHasNoIdentity() {
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

    #expect(log.identity(of: "deep") == GlobalElementID??.some(nil))
}

// MARK: - Modifiers

/// Each edge modifier lands on the edge it names.
///
/// **Four different values, and every one of them observable**: with a uniform
/// `padding(8)` an `init` that transposed top and bottom passes. `left` and
/// `top` show up in the child's origin; `right` and `bottom` show up in the
/// grown/stretched child's size, so a transposed pair moves a number.
@MainActor
@Test func paddingEdgesAreNotTransposed() {
    let log = ElementLog()
    let frame = Frame(contentSize: Size(width: px(400), height: px(120)), scaleFactor: 1)
    var row = Row {
        Probe("only", log: log).flexGrow(1)
    }
    .padding(Edges(top: .pixels(px(4)), right: .pixels(px(8)),
                   bottom: .pixels(px(12)), left: .pixels(px(16))))

    frame.render(&row)

    // origin = (left, top); size = content box = (400-16-8, 120-4-12).
    #expect(rect(log.bounds["only"]!) == (16, 4, 376, 104))
}

/// Margins land on the edge they name too, and shrink the space available to
/// the item rather than moving it alone.
@MainActor
@Test func marginEdgesAreNotTransposed() {
    let log = ElementLog()
    let frame = Frame(contentSize: Size(width: px(400), height: px(120)), scaleFactor: 1)
    var row = Row {
        Probe("only", log: log).flexGrow(1)
            .margin(Edges(top: .pixels(px(4)), right: .pixels(px(8)),
                          bottom: .pixels(px(12)), left: .pixels(px(16))))
    }

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

    #expect(rect(log.bounds["second"]!) == (50, 0, 50, 20))
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

    // Third sits where the second would have, not 50 further along.
    #expect(rect(log.bounds["third"]!) == (30, 0, 70, 30))
    // It is skipped as an item, not skipped as a phase: it still ran.
    #expect(log.registered == ["first", "gone", "third"])
}

/// `alignItems` and `alignSelf` reach the engine, and `alignSelf` wins.
///
/// Three children with three different cross-axis answers in one 90-tall row, so
/// a modifier that wrote the container's value onto the item — or the reverse —
/// moves at least one `y`.
@MainActor
@Test func alignItemsAndAlignSelfBothReachTheEngine() {
    let log = ElementLog()
    let frame = Frame(contentSize: Size(width: px(300), height: px(90)), scaleFactor: 1)
    var row = Row {
        Probe("centred", log: log).width(px(30)).height(px(20))
        Probe("start", log: log).width(px(40)).height(px(10)).alignSelf(.flexStart)
        Probe("end", log: log).width(px(50)).height(px(30)).alignSelf(.flexEnd)
    }
    .alignItems(.center)

    frame.render(&row)

    #expect(rect(log.bounds["centred"]!) == (0, 35, 30, 20))
    #expect(rect(log.bounds["start"]!) == (30, 0, 40, 10))
    #expect(rect(log.bounds["end"]!) == (70, 60, 50, 30))
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
