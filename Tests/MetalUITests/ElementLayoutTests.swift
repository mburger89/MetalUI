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
// The layout assertions below were first compared against the same tree built
// by hand and run through the CSS engine directly; that oracle test
// (`aNestedLayoutMatchesTheEngineRunDirectly`) and its fixture were retired by
// stage 7b (record §49 §4 row 225), with the element-to-kernel agreement held
// by `theStageOneCorpusLowersWithNoDiagnosticAndAgreesElementByElement`. The
// tests that remain assert literal numbers.

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

/// The native leaf a stage 6a **Dual** fixture registers under the proposal
/// authority (record §38, spec §5's R spelling): one node answering the pixel
/// size its `Style` declares, 0 on an axis it leaves `auto` — what its legacy
/// node resolved to as a flex item nobody stretches or grows. Shared by lane 3's
/// five Dual elements (`Probe` here, `ComponentTests.Leaf`, `FrameSizingTests.Mark`,
/// `ModifiedElementTests.LayerLeaf`, `ModifierCompositionProofTests.CountingLeaf`);
/// their legacy branch registers through `Frame`'s internal registrar, and
/// which branch runs is the test's authority.
@MainActor
func declaredSizeNativeLeaf(_ style: Style, _ pass: LayoutPass) -> LayoutNodeID {
    func pixels(_ dimension: MetalUICore.Dimension) -> Double {
        if case .length(.pixels(let p)) = dimension { return Double(p.value) }
        precondition(dimension == .auto,
                     "a stage 6a Dual fixture's proposal branch answers only pixel sizes; got \(dimension)")
        return 0
    }
    let size = SizeD(width: pixels(style.size.width), height: pixels(style.size.height))
    return pass.requestNativeLeaf { _ in LayoutMeasurement(size: size) }.layoutNodeID
}

/// A childless element that records the bounds and identity its phases receive.
///
/// Conforms to `StyledElement`, so the production modifiers apply to it and a
/// modifier that writes the wrong `Style` field shows up as a wrong rect here.
///
/// **A Dual fixture since stage 6a** (record §38, spec §5 lane 3): under the
/// proposal authority it is `declaredSizeNativeLeaf`, and its three R tests pass
/// `.proposal`; under the legacy one it registers through `Frame`'s internal
/// legacy registrar, and its eleven P tests pass `.legacy` explicitly so stage
/// 6b's flip cannot reach them.
///
/// **Stage 7b** (record §49 §6.2) retired six P tests; the legacy branch stays
/// while any kept test reaches it (stage 9's, with the legacy authority).
@MainActor
struct Probe: Element, StyledElement {
    var style = Style()
    var decoration = Decoration()
    var elementID: ElementID?
    // `StyledElement`'s fourth requirement. This probe registers no click
    // target — nothing calls `registerHandlers` — so it stays at the empty set.
    var handlers: Handlers = Handlers()
    let name: String
    let log: ElementLog

    init(_ name: String, log: ElementLog) {
        self.name = name
        self.log = log
    }

    func requestLayout(_ id: GlobalElementID,
                       pass: inout LayoutPass) -> (LayoutNodeID, LayoutNodeID) {
        log.registered.append(name)
        let node = pass.lowersToProposal
            ? declaredSizeNativeLeaf(style, pass)
            : pass.frame.requestNode(style: style, children: [])
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
///
/// Pinned to the legacy authority by stage 6a (CE+RP, record §38 §4); unpinned
/// by stage 6b (`LR-DG`, R-fill): every root declares its frame's extent on its
/// two auto axes — what `CS-I` gave the legacy root, now spelled — so the
/// literals hold on both authorities.
@MainActor
@Test func anExplicitAnyElementIsStillAcceptedAsAChild() {
    let log = ElementLog()
    let frame = Frame(contentSize: Size(width: px(200), height: px(80)), scaleFactor: 1)
    var row = Row {
        AnyElement(Probe("erased", log: log).width(px(40)).height(px(25)))
        Probe("plain", log: log).width(px(60)).height(px(15))
    }.width(px(200)).height(px(80))

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

/// Children reach the engine in source order.
///
/// Three children of **different widths** at three different x positions: with
/// equal children a reversed or rotated order is invisible, which is the point
/// of 30/50/70 rather than 50/50/50.
///
/// Pinned to the legacy authority by stage 6a (CE+RP, record §38 §4); unpinned
/// by stage 6b (`LR-DG`, R-fill): every root declares its frame's extent on its
/// two auto axes — what `CS-I` gave the legacy root, now spelled — so the
/// literals hold on both authorities.
@MainActor
@Test func childrenAreRegisteredAndLaidOutInSourceOrder() {
    let log = ElementLog()
    let frame = Frame(contentSize: Size(width: px(300), height: px(40)), scaleFactor: 1)
    var row = Row {
        Probe("first", log: log).width(px(30)).height(px(10))
        Probe("second", log: log).width(px(50)).height(px(20))
        Probe("third", log: log).width(px(70)).height(px(30))
    }.width(px(300)).height(px(40))

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
///
/// Pinned to the legacy authority by stage 6a (CE+RP, record §38 §4); unpinned
/// by stage 6b (`LR-DG`, R-fill): every root declares its frame's extent on its
/// two auto axes — what `CS-I` gave the legacy root, now spelled — so the
/// literals hold on both authorities.
@MainActor
@Test func columnStacksOnTheAxisRowDoesNot() {
    let rowLog = ElementLog()
    let rowFrame = Frame(contentSize: Size(width: px(200), height: px(80)), scaleFactor: 1)
    var row = Row {
        Probe("one", log: rowLog).width(px(40)).height(px(25))
        Probe("two", log: rowLog).width(px(60)).height(px(15))
    }.width(px(200)).height(px(80))
    rowFrame.render(&row)

    let columnLog = ElementLog()
    let columnFrame = Frame(contentSize: Size(width: px(200), height: px(80)), scaleFactor: 1)
    var column = Column {
        Probe("one", log: columnLog).width(px(40)).height(px(25))
        Probe("two", log: columnLog).width(px(60)).height(px(15))
    }.width(px(200)).height(px(80))
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
///
/// Pinned to the legacy authority by stage 6a (CE+RP, record §38 §4); unpinned
/// by stage 6b (`LR-DG`, R-fill): every root declares its frame's extent on its
/// two auto axes — what `CS-I` gave the legacy root, now spelled — so the
/// literals hold on both authorities.
@MainActor
@Test func aStackCentresOnTheCrossAxisWhereABoxStretches() {
    let stackLog = ElementLog()
    let stackFrame = Frame(contentSize: Size(width: px(200), height: px(90)), scaleFactor: 1)
    var column = Column {
        Probe("stacked", log: stackLog).width(px(60)).height(px(20))
    }.width(px(200)).height(px(90))
    stackFrame.render(&column)

    let boxLog = ElementLog()
    let boxFrame = Frame(contentSize: Size(width: px(200), height: px(90)), scaleFactor: 1)
    var box = Box {
        Probe("boxed", log: boxLog).width(px(60)).height(px(20))
    }
    .flexDirection(.column).width(px(200)).height(px(90))
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
    }.width(px(200)).height(px(90))
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
    let frame = Frame(contentSize: Size(width: px(200), height: px(80)), scaleFactor: 1, layoutAuthority: .proposal)
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
    let frame = Frame(contentSize: Size(width: px(200), height: px(80)), scaleFactor: 1, layoutAuthority: .proposal)
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

/// `gap(horizontal:vertical:)` writes both axes, and the row reads the
/// horizontal one.
///
/// Asymmetric on purpose: `gap(12)` sets both axes equal and cannot detect an
/// engine — or a modifier — reading the wrong one.
///
/// Pinned to the legacy authority by stage 6a (CE+RP, record §38 §4); unpinned
/// by stage 6b (`LR-DG`, R-fill): every root declares its frame's extent on its
/// two auto axes — what `CS-I` gave the legacy root, now spelled — so the
/// literals hold on both authorities.
@MainActor
@Test func gapIsPerAxisAndTheRowReadsTheHorizontalOne() {
    let log = ElementLog()
    let frame = Frame(contentSize: Size(width: px(300), height: px(60)), scaleFactor: 1)
    var row = Row {
        Probe("first", log: log).width(px(30)).height(px(10))
        Probe("second", log: log).width(px(50)).height(px(20))
    }
    .gap(horizontal: px(20), vertical: px(5)).width(px(300)).height(px(60))

    frame.render(&row)

    // **Was `(50, 0, 50, 20)` before ruling EP-8** — stretch put `second` at
    // y = 0. The `x` is what this test is named for and it has not moved:
    // 30 + 20 = 50, so the row read the *horizontal* gap. The `y` is centring,
    // (60 - 20) / 2 = **20**, and it is worth asserting rather than dropping,
    // because a row that read the vertical gap (5) on the cross axis would
    // have to put it somewhere and this is where it would show.
    #expect(rect(log.bounds["second"]!) == (50, 20, 50, 20))
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
    let first = Frame(contentSize: Size(width: px(200), height: px(80)), scaleFactor: 1, layoutAuthority: .proposal)
    var firstTree = Row { Probe("x", log: firstLog).width(px(20)).height(px(10)) }
    first.render(&firstTree)

    let secondLog = ElementLog()
    let second = Frame(contentSize: Size(width: px(200), height: px(80)), scaleFactor: 1, layoutAuthority: .proposal)
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
