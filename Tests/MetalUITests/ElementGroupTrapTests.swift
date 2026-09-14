import Testing
import MetalUICore
import MetalUILayout
import MetalUITestSupport
@testable import MetalUI

// The guards that cost more than an `#expect`: the two phase-state traps in
// `ElementGroup.swift`, the modifier that must *not* exist on `Column`, and the
// duplicate-sibling-id behaviour that must be pinned rather than trapped.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

private func px(_ v: Float) -> Pixels { Pixels(v) }

/// The proposal overlay registers only native nodes, so it must reject a
/// legacy child at the type boundary rather than build a mixed tree that traps
/// during layout. The positive control proves this is a boundary, not a
/// missing overlay API.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func proposalOverlayAcceptsProposalContentAndRejectsLegacyContent() throws {
    let positive = try typecheck("""
        @MainActor func probe() {
            _ = Rectangle().overlay {
                Color(.accent)
            }
        }
        """, importing: "MetalUI")
    #expect(positive.succeeded,
            "proposal content must retain the canonical overlay API:\n\(positive.output)")

    let negative = try typecheck("""
        @MainActor func probe() {
            _ = Text("legacy").overlay {
                Rectangle()
            }
        }
        """, importing: "MetalUI")
    #expect(!negative.succeeded,
            "a legacy child must not enter the proposal overlay and trap while registering layout:\n\(negative.output)")
    #expect(negative.messages.contains("overlay"),
            "rejected, but not because the proposal overlay boundary was absent:\n\(negative.output)")
}

/// `onTap` has no layout footprint, but it still delegates registration to its
/// content. Keeping the same proposal-only boundary as outer layout modifiers
/// prevents an ordinary CSS element from failing later at runtime.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func proposalOnTapAcceptsProposalContentAndRejectsLegacyContent() throws {
    let positive = try typecheck("""
        @MainActor func probe() {
            _ = Rectangle().onTap {}
        }
        """, importing: "MetalUI")
    #expect(positive.succeeded,
            "proposal content must retain the canonical onTap API:\n\(positive.output)")

    let negative = try typecheck("""
        @MainActor func probe() {
            _ = Text("legacy").onTap {}
        }
        """, importing: "MetalUI")
    #expect(!negative.succeeded,
            "a legacy child must not enter the proposal onTap wrapper and trap while registering layout:\n\(negative.output)")
    #expect(negative.messages.contains("onTap"),
            "rejected, but not because the proposal onTap boundary was absent:\n\(negative.output)")
}

/// Proposal containers and their stored wrapper forms all register native
/// nodes. Their generic constraints must therefore reject a legacy subtree at
/// construction time; checking each constructor independently prevents one
/// unconstrained builder from reintroducing the runtime mixed-tree trap.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func proposalLayoutConstructorsRequireProposalContent() throws {
    let positive = try typecheck("""
        @MainActor func probe() {
            _ = HStack { Rectangle(); Color(.accent) }
            _ = VStack { Rectangle(); Color(.accent) }
            _ = ZStack { Rectangle(); Color(.accent) }
            _ = ProposalFrame { Rectangle() }
            _ = Padding(Edges(all: Pixels(1))) { Rectangle() }
            _ = Background(.accent) { Rectangle() }
            _ = FixedSize { Rectangle() }
            _ = ModifiedContent(content: Rectangle(), modifier: .padding(Edges(all: Pixels(1))))
            _ = OnTapModifier(content: Rectangle()) {}
            _ = OverlayModifier(content: Rectangle()) { Color(.accent) }
        }
        """, importing: "MetalUI")
    #expect(positive.succeeded,
            "every proposal builder must remain constructible with proposal content:\n\(positive.output)")

    func assertRejectsLegacyContent(_ source: String) throws {
        let result = try typecheck(source, importing: "MetalUI")
        #expect(!result.succeeded,
                "a legacy subtree must be rejected before native layout registration:\n\(result.output)")
        #expect(result.messages.contains("ProposalElementGroup"),
                "rejected, but not because the proposal-content constraint was missing:\n\(result.output)")
    }

    try assertRejectsLegacyContent("""
        @MainActor func probe() { _ = HStack { Text("legacy") } }
        """)
    try assertRejectsLegacyContent("""
        @MainActor func probe() { _ = VStack { Text("legacy") } }
        """)
    try assertRejectsLegacyContent("""
        @MainActor func probe() { _ = ZStack { Text("legacy") } }
        """)
    try assertRejectsLegacyContent("""
        @MainActor func probe() { _ = ProposalFrame { Text("legacy") } }
        """)
    try assertRejectsLegacyContent("""
        @MainActor func probe() {
            _ = Padding(Edges(all: Pixels(1))) { Text("legacy") }
        }
        """)
    try assertRejectsLegacyContent("""
        @MainActor func probe() { _ = Background(.accent) { Text("legacy") } }
        """)
    try assertRejectsLegacyContent("""
        @MainActor func probe() { _ = FixedSize { Text("legacy") } }
        """)
    try assertRejectsLegacyContent("""
        @MainActor func probe() {
            _ = ModifiedContent(content: Text("legacy"), modifier: .padding(Edges(all: Pixels(1))))
        }
        """)
    try assertRejectsLegacyContent("""
        @MainActor func probe() { _ = OnTapModifier(content: Text("legacy")) {} }
        """)
    try assertRejectsLegacyContent("""
        @MainActor func probe() {
            _ = OverlayModifier(content: Text("legacy")) { Rectangle() }
        }
        """)
}

/// A proposal Text adapter keeps the existing legacy `Text.background` member
/// out of overload resolution while letting the converted value use the
/// proposal wrapper's canonical modifier spelling.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func proposalTextSelectsProposalModifiersWithoutMakingLegacyTextAmbiguous() throws {
    let result = try typecheck("""
        @MainActor func probe() -> ModifiedContent<ProposalText> {
            Text("proposal").proposalLayout().background(.accent)
        }
        """, importing: "MetalUI")
    #expect(result.succeeded,
            "proposal Text must select the proposal background wrapper without changing legacy Text:\n\(result.output)")
}

/// An element that replaces its own children **between `requestLayout` and
/// `prepaint`**.
///
/// This is the mechanism `EitherGroup.mismatch`, `OptionalGroup.mismatch` and
/// `ArrayGroup.countMismatch` all describe, written out. It needs no privileged
/// access and no `@testable`: `Element`'s phases are `mutating` by design (§4.1
/// threads state `inout` so an element can mutate in place), so any element may
/// rebuild its content mid-frame. The three comments said such a value "would
/// have to come from a different group"; it does not — one value suffices.
@MainActor
struct ContentSwapper<Content: ElementGroup>: Element {
    var content: Content
    /// Installed at the top of `prepaint`, after layout has already run.
    var replacement: Content?

    mutating func requestLayout(_ id: GlobalElementID,
                                pass: inout LayoutPass) -> (LayoutNodeID, Content.GroupLayout) {
        var cursor = 0
        let (children, layout) = content.requestGroupLayout(under: id, at: &cursor, pass: &pass)
        return (pass.requestNode(style: Style(), children: children), layout)
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                           layout: inout Content.GroupLayout,
                           pass: inout PrepaintPass) -> Content.GroupPrepaint {
        if let replacement { content = replacement }
        return content.prepaintGroup(layout: &layout, pass: &pass)
    }

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                        layout: inout Content.GroupLayout,
                        prepaint: inout Content.GroupPrepaint, pass: inout PaintPass) {
        content.paintGroup(layout: &layout, prepaint: &prepaint, pass: &pass)
    }
}

@MainActor
private func renderSwapper<Content: ElementGroup>(_ content: Content,
                                                  replacedBy replacement: Content?) {
    let frame = Frame(contentSize: Size(width: px(100), height: px(100)), scaleFactor: 1)
    var element = ContentSwapper(content: content, replacement: replacement)
    frame.render(&element)
}

// **Each trap test reads the abort message off stderr, not just the exit
// status, and that is load-bearing.** Every phase trap in `ElementGroup.swift`
// is backstopped by the next phase's, so deleting `OptionalGroup`'s `prepaint`
// precondition left the whole suite green — measured: the mismatch simply
// reached `paint`, which aborted instead, and an exit-status-only test cannot
// tell the two apart. The message names the phase; the assertion reads it.
//
// The `#expect(processExitsWith:)` call has to be written out at each site: its
// body is re-entered in a subprocess, so it must be a **non-capturing** closure
// and cannot be routed through a shared helper (`error: a C function pointer
// cannot be formed from a closure that captures context`).

// MARK: - The three phase-state traps

/// Flipping an `if`/`else` between layout and prepaint **traps**.
///
/// Reported in task 4 as an unreachable "cannot happen"; it is neither. The
/// element above reaches it in ordinary code, so the trap is a real branch with
/// a real caller rather than a comment about one.
@Test func flippingAnEitherBranchBetweenPhasesTraps() async {
    let result = await #expect(processExitsWith: .failure,
                               observing: [\.standardErrorContent]) {
        await MainActor.run {
            renderSwapper(EitherGroup<Box<EmptyGroup>, Box<EmptyGroup>>.first(Box()),
                          replacedBy: .second(Box()))
        }
    }
    let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(stderr.contains("EitherGroup prepaint"),
            "aborted, but not at the guard this test is about:\n\(stderr)")
}

/// Positive control: the identical render with nothing swapped in.
///
/// Without it, "the subprocess died" would be satisfied by a `ContentSwapper`
/// that cannot render at all, or by an `EitherGroup` that traps on every
/// prepaint.
@Test func anUnflippedEitherBranchDoesNotTrap() async {
    await #expect(processExitsWith: .success) {
        await MainActor.run {
            renderSwapper(EitherGroup<Box<EmptyGroup>, Box<EmptyGroup>>.first(Box()),
                          replacedBy: nil)
        }
    }
}

/// Dropping an `if`'s child between layout and prepaint **traps**.
///
/// This branch returned `nil` silently until fix round 1: the same flip that
/// aborted inside an `if`/`else` was ignored inside a bare `if`, so the two
/// spellings of one condition disagreed about whether a mid-frame rebuild was an
/// error. It is the trap now, for the reason `OptionalGroup.mismatch` gives.
@Test func droppingAnOptionalChildBetweenPhasesTraps() async {
    let result = await #expect(processExitsWith: .failure,
                               observing: [\.standardErrorContent]) {
        await MainActor.run {
            renderSwapper(OptionalGroup(Box<EmptyGroup>()), replacedBy: OptionalGroup(nil))
        }
    }
    let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    // Not merely "OptionalGroup": the `paint` guard catches the same mismatch
    // one phase later, and this test is about the `prepaint` one.
    #expect(stderr.contains("OptionalGroup prepaint"),
            "aborted, but not at the guard this test is about:\n\(stderr)")
}

/// Positive control, and the one that also proves the **ordinary absent case is
/// not a mismatch**: an `OptionalGroup` that is `nil` in both phases must render
/// clean, or the new precondition would abort every `if` whose condition is
/// false.
@Test func anOptionalChildThatIsAbsentInBothPhasesDoesNotTrap() async {
    await #expect(processExitsWith: .success) {
        await MainActor.run {
            renderSwapper(OptionalGroup<Box<EmptyGroup>>(nil), replacedBy: nil)
            renderSwapper(OptionalGroup(Box<EmptyGroup>()), replacedBy: nil)
        }
    }
}

/// Shortening a `for` loop's output between layout and prepaint **traps**.
///
/// `ArrayGroup`'s count mismatch is reachable by exactly the same mechanism as
/// `EitherGroup`'s — it is not the narrower "cannot happen" the task-4 report
/// left it as. Two members become one, and the per-member state array no longer
/// matches.
@Test func changingAnArrayGroupsCountBetweenPhasesTraps() async {
    let result = await #expect(processExitsWith: .failure,
                               observing: [\.standardErrorContent]) {
        await MainActor.run {
            renderSwapper(ArrayGroup([Box<EmptyGroup>(), Box<EmptyGroup>()]),
                          replacedBy: ArrayGroup([Box<EmptyGroup>()]))
        }
    }
    let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(stderr.contains("ArrayGroup prepaint"),
            "aborted, but not at the guard this test is about:\n\(stderr)")
}

/// Positive control: the same two members, unchanged.
@Test func anUnchangedArrayGroupDoesNotTrap() async {
    await #expect(processExitsWith: .success) {
        await MainActor.run {
            renderSwapper(ArrayGroup([Box<EmptyGroup>(), Box<EmptyGroup>()]), replacedBy: nil)
        }
    }
}

// MARK: - `flexDirection` is `Box`'s alone

/// `Column` offers no way to become a row.
///
/// **No runtime test can see this**, which is how it went wrong:
/// `flexDirection(_:)` sat on `StyledElement` for one commit, `Column` conforms
/// to `StyledElement`, and so `Column { … }.flexDirection(.row)` compiled, kept
/// its `Column<…>` type, and laid its children out horizontally — while the
/// comment at the top of `Stack.swift` said that was the thing being prevented.
/// The guard has to be a compile guard, and it asserts on `messages` rather than
/// `output` because swiftc echoes the source line.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func columnCannotBeTurnedIntoARowByAModifier() throws {
    let negative = try typecheck("""
        @MainActor func probe() {
            _ = Column { Box() }.flexDirection(.row)
        }
        """, importing: "MetalUI")
    #expect(!negative.succeeded,
            "Column accepts flexDirection again — the type now says column while the style says row")
    #expect(negative.messages.contains("flexDirection"),
            "rejected, but not for the reason this test is about:\n\(negative.output)")

    // The load-bearing half. Without it the negative passes just as well when
    // `Column` does not exist, when the module fails to import, or when no
    // element in the framework has a `flexDirection` modifier at all.
    let positive = try typecheck("""
        @MainActor func probe() {
            _ = Box { Box() }.flexDirection(.row)
        }
        """, importing: "MetalUI")
    #expect(positive.succeeded,
            "Box lost flexDirection, so the negative above proves nothing:\n\(positive.output)")
}

// MARK: - Duplicate sibling ids (pinned, not trapped)

/// An element that increments a cross-frame counter and records what it saw.
@MainActor
struct StateProbe: Element, StyledElement {
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
        let node = pass.requestNode(style: style, children: [])
        return (node, node)
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                  layout: inout LayoutNodeID, pass: inout PrepaintPass) {
        pass.withState(id, initial: 0) { (value: inout Int) in
            value += 1
            log.counters.append((name, value))
        }
    }

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
               layout: inout LayoutNodeID, prepaint: inout Void, pass: inout PaintPass) {}
}

/// Two siblings with the same local id share **one** state entry, and that is
/// the settled answer rather than a placeholder.
///
/// **Formerly `twoSiblingsWithTheSameIDShareOneStateEntryForNow`.** The "for
/// now" promised a fix that structural identity has now declined to make, so the
/// assertions below are unchanged and only the claim about them has moved. The
/// old comment said "the fix here is a positional component folded into the key
/// where siblings collide". A positional component now exists — it is what an
/// **unnamed** sibling is keyed on — and folding it in *alongside* a name is
/// exactly what `PathComponent` refuses to do: a name **replaces** a position,
/// because an index in the key would reset a named list item's state whenever it
/// moved, which is the one thing `.id()` exists to prevent
/// (`reorderingANamedListCarriesEachItemsState` in `IdentityTests.swift` is that
/// rule's pin). Two siblings written with the same id therefore have the same
/// path, by construction and on purpose.
///
/// **SwiftUI behaves the same way and documents it as a caller error**, so this
/// is a matching hazard rather than a divergence: duplicate ids among siblings
/// give one identity, and the caller is expected not to write them.
///
/// **Deliberately not a trap.** Aborting would turn a data bug into a crash in a
/// shipping app — an `ArrayGroup` whose data genuinely holds duplicate keys is a
/// wrong list, not a wrong program. The same reasoning as
/// `anOverConstrainedBoxGrowsToFitItsPaddingAndBorder` (which carried this
/// reasoning under its old name, `containerDoesNotGrowToFitOverconstrained…`,
/// until the sizing milestone closed the divergence): name the other
/// answer in the comment so the choice is a decision rather than a surprise.
@MainActor
@Test func twoSiblingsWithTheSameIDShareOneStateEntry() {
    let log = ElementLog()
    let table = StateTable()
    let frame = Frame(contentSize: Size(width: px(100), height: px(100)),
                      scaleFactor: 1, stateTable: table)
    var column = Column {
        StateProbe("left", log: log).id("a").width(px(10)).height(px(10))
        StateProbe("right", log: log).id("a").width(px(10)).height(px(10))
    }
    .id("root")

    frame.render(&column)

    // One shared entry, incremented twice — the second sibling continued the
    // first's count instead of starting its own — plus one more: the
    // animation milestone's Task 4 wired `Column` (via its wrapped `Box`)
    // through `animated(_:_:for:pass:)`, which unconditionally persists a
    // `$anim` baseline for the container on its first frame.
    #expect(log.counters.map(\.name) == ["left", "right"])
    #expect(log.counters.map(\.value) == [1, 2])
    #expect(table.count == 2)
    #expect(table.peek(GlobalElementID.child(of: GlobalElementID.child(of: nil, at: 0, name: ElementID("root")),
                                             at: 0, name: ElementID("a")),
                       as: Int.self) == 2)
}

/// The control: two siblings with **different** ids each get their own entry.
///
/// Without it, `[1, 2]` above would be indistinguishable from a `withState` that
/// ignores its key entirely, or from a table with one global slot.
@MainActor
@Test func twoSiblingsWithDifferentIDsDoNotShareState() {
    let log = ElementLog()
    let table = StateTable()
    let frame = Frame(contentSize: Size(width: px(100), height: px(100)),
                      scaleFactor: 1, stateTable: table)
    var column = Column {
        StateProbe("left", log: log).id("a").width(px(10)).height(px(10))
        StateProbe("right", log: log).id("b").width(px(10)).height(px(10))
    }
    .id("root")

    frame.render(&column)

    #expect(log.counters.map(\.value) == [1, 1])
    // 2 (one per sibling) + 1 — the `Column`'s own `$anim` baseline, on
    // `twoSiblingsWithTheSameIDShareOneStateEntry`'s footing above.
    #expect(table.count == 3)
}
