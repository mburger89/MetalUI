import Testing
import Metal
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// Plan task 8, lane 2 (`docs/superpowers/specs/2026-09-25-composition-identity-design.md`,
// rulings `ID-B`, `ID-C`, `ID-D`): an `if` without `else` and a `for` loop take
// ONE structural slot and number their content inside it; content an EVALUATED
// conditional removes is reset (except the window-owned `$ax` slot — `$focus`
// was exempt too until plan task 12's `IX-I`);
// `if`/`else` compiles inside proposal containers. SwiftUI's answers are probe
// arms V1–V10 and G7 of `docs/probes/swiftui-composition-identity.swift`.
//
// Every frame here is driven through `Frame.render` (whose `stateTable.sweep()`
// swaps the produced-slot sets) or a real `Window` — a layout-only frame never
// swaps them and so never resets.
//
// **Two copies of every group** (`ElementGroup.swift`'s untyped entries,
// `ProposalElementGroup.swift`'s typed ones): each test names the copy its
// mutation is applied to, and a copy is mutated on its own.

// MARK: - Shared probes

/// What each labelled probe read out of its cross-frame state on its last
/// layout, and the id it was laid out at.
@MainActor
final class ConditionalReads {
    var values: [String: Int] = [:]
    var ids: [String: GlobalElementID] = [:]
}

/// A 10×10 leaf that adds `step` to a counter each frame its key is laid out,
/// in the `StateTable` under its own id, and records the count and the id by
/// label — so a test reads what a probe SAW without hand-building its path. A
/// `step` other than 1 makes an adopted count distinguishable from an own one.
struct ConditionalCounter: Element {
    let label: String
    let reads: ConditionalReads
    let step: Int
    var elementID: ElementID? { nil }

    init(_ label: String, _ reads: ConditionalReads, step: Int = 1) {
        self.label = label
        self.reads = reads
        self.step = step
    }

    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        var value = 0
        pass.withState(id, initial: 0) { $0 += step; value = $0 }
        reads.values[label] = value
        reads.ids[label] = id
        return (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }.layoutNodeID,
                ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                  layout: inout Void, pass: inout PrepaintPass) {}

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
               layout: inout Void, prepaint: inout Void, pass: inout PaintPass) {}
}

/// `ConditionalCounter` on the proposal vocabulary, for `HStack` content.
struct ProposalConditionalCounter: ProposalElement {
    let label: String
    let reads: ConditionalReads

    init(_ label: String, _ reads: ConditionalReads) {
        self.label = label
        self.reads = reads
    }

    mutating func requestProposalLayout(_ id: GlobalElementID,
                                        pass: inout LayoutPass) -> (ProposalNodeID, Void) {
        var value = 0
        pass.withState(id, initial: 0) { $0 += 1; value = $0 }
        reads.values[label] = value
        reads.ids[label] = id
        return (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }, ())
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                           pass: inout PrepaintPass) {}
    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                        prepaint: inout Void, pass: inout PaintPass) {}
}

/// Two counters as one `Component` — a multi-member group (probe G7's arm).
struct TwoCounters: Component {
    let first: String
    let second: String
    let reads: ConditionalReads

    var content: some ElementGroup {
        ConditionalCounter(first, reads)
        ConditionalCounter(second, reads)
    }
}

private let size = Size<Pixels>(width: Pixels(200), height: Pixels(100))
private let root = GlobalElementID.child(of: nil, at: 0, name: nil)

private func child(_ parent: GlobalElementID, _ index: Int) -> GlobalElementID {
    GlobalElementID.child(of: parent, at: index, name: nil)
}

/// Renders `make(step)` for each step against one table, through `Frame.render`.
@MainActor
private func render<Root: Element, Step>(_ steps: [Step], table: StateTable = StateTable(),
                                         _ make: (Step) -> Root) -> StateTable {
    for step in steps {
        var tree = make(step)
        Frame(contentSize: size, scaleFactor: 1, stateTable: table).render(&tree)
    }
    return table
}

// MARK: - C2.2–C2.4: one structural slot (`ID-B`)

/// **C2.2 — an element after an APPEARING `if` keeps its own state** (probe
/// V2). `Row { if flag { C }; C }` false → true: the trailing element stays at
/// `root/1` and reads 2; the new content is `root/0/0` and reads 1.
///
/// Before `ID-B` the appearing content took `root/0` — the trailing element's
/// old slot — and read its 2, while the trailing element moved to `root/1` and
/// started at 1. Mutation **M2a** (untyped `OptionalGroup` advances the cursor
/// only when `wrapped != nil`) reddens this.
@MainActor
@Test func anElementAfterAnAppearingIfKeepsItsOwnState() {
    let table = render([false, true]) { flag in
        Row {
            if flag { CountingElement(nil) }
            CountingElement(nil)
        }
    }
    #expect(table.peek(child(root, 1), as: Int.self) == 2, "the trailing element's own count")
    #expect(table.peek(child(child(root, 0), 0), as: Int.self) == 1, "the new content starts fresh")
}

/// **C2.3 — a two-member `if` takes one slot and numbers its members inside
/// it** (probe V3). `Row { if flag { C; C }; C }` across true, false, true: the
/// members sit at `root/0/0` and `root/0/1` (fresh after the reset, 1 each), and
/// the trailing element at `root/1` counts every frame (3).
///
/// Mutation **M2b** (untyped: reserve the slot but number the members with the
/// outer cursor under `parent` — no nesting) reddens this.
@MainActor
@Test func aTwoMemberIfTakesOneSlotAndNumbersItsMembersInside() {
    let table = render([true, false, true]) { flag in
        Row {
            if flag {
                CountingElement(nil)
                CountingElement(nil)
            }
            CountingElement(nil)
        }
    }
    let slot = child(root, 0)
    #expect(table.peek(child(slot, 0), as: Int.self) == 1, "member 0 inside the slot")
    #expect(table.peek(child(slot, 1), as: Int.self) == 1, "member 1 inside the slot")
    #expect(table.peek(child(root, 1), as: Int.self) == 3, "the trailing element counted every frame")
}

/// **C2.4 — a shrinking `for` loop leaves the trailing sibling's state alone**
/// (probe V6). `Row { for _ in 0..<n { C }; C }`, n 2 → 1: the trailing element
/// reads its own 2. The iterations count in steps of 10, so an adopted count
/// reads 11 — with equal steps adoption and ownership both read 2 (measured at
/// the red run: the first spelling was green before the fix).
///
/// **C2.4b — inverted by plan task 10 (ruling `DD-C`), retiring divergence
/// 74**: n 2 → 1 → 2 — the loop's second iteration, `root/0/1`, reads **1**: an
/// element a `for` loop stops producing is reset and starts fresh when the loop
/// grows again, as SwiftUI's `ForEach` over a range does (probe F3, V10). Until
/// `DD-C` it read **2** (the dropped iteration's entries were retained and handed
/// back — divergence 74, pinned here), measured at lane 1's red run.
///
/// Mutation **M2c** (untyped `ArrayGroup` reserves no slot: members threaded
/// through the outer cursor as before) reddens this; so does **M1g** (lane 1:
/// the untyped `ArrayGroup`'s `noteLoop` call removed — the arm reads 2 again).
@MainActor
@Test func aShrinkingForLoopLeavesTheTrailingSiblingsStateAlone() {
    let reads = ConditionalReads()
    _ = render([2, 1]) { n in
        Row {
            for i in 0..<n { ConditionalCounter("i\(i)", reads, step: 10) }
            ConditionalCounter("t", reads)
        }
    }
    #expect(reads.values["t"] == 2, "the trailing element's own count (11 is adoption): \(reads.values)")
    #expect(reads.ids["t"] == child(root, 1), "\(String(describing: reads.ids["t"]))")

    // C2.4b: grown back.
    let regrown = render([2, 1, 2]) { n in
        Row {
            for _ in 0..<n { CountingElement(nil) }
            CountingElement(nil)
        }
    }
    let loop = child(root, 0)
    #expect(regrown.peek(child(loop, 1), as: Int.self) == 1,
            "DD-C: the dropped iteration was reset and starts fresh (2 is divergence 74's retention)")
    #expect(regrown.peek(child(loop, 0), as: Int.self) == 3)
    #expect(regrown.peek(child(root, 1), as: Int.self) == 3)
}

// MARK: - C2.6–C2.10: reset on an evaluated removal (`ID-C`)

/// **C2.6 — content an `if` removes is reset when it returns** (probe V5).
/// `Row { if flag { c }; t }` true, false, true: `c` reads **1** on its return,
/// `t` counts every frame (3).
///
/// Before `ID-C` the absent content's entry tombstoned and `c` came back
/// reading 2 (divergence 18). Mutation **M2d** (`noteAbsent` never resets)
/// reddens this.
@MainActor
@Test func contentAnIfRemovesIsResetWhenItReturns() {
    let reads = ConditionalReads()
    _ = render([true, false, true]) { flag in
        Row {
            if flag { ConditionalCounter("c", reads) }
            ConditionalCounter("t", reads)
        }
    }
    #expect(reads.values["c"] == 1, "the returning content starts fresh: \(reads.values)")
    #expect(reads.values["t"] == 3, "the trailing element is untouched: \(reads.values)")
}

/// **C2.7 — an `if`/`else` branch flipped away and back starts fresh** (probe
/// V9). `Row { if flag { a } else { b } }` true, false, true: `a` reads **1**.
///
/// Before `ID-C` the untaken branch's entry tombstoned and `a` read 2 on return.
/// Mutation **M2e** (`EitherGroup` notes no absent branch — only `OptionalGroup`
/// resets) reddens this.
@MainActor
@Test func anIfElseBranchFlippedAwayAndBackStartsFresh() {
    let reads = ConditionalReads()
    _ = render([true, false, true]) { flag in
        Row {
            if flag { ConditionalCounter("a", reads) } else { ConditionalCounter("b", reads) }
        }
    }
    #expect(reads.values["a"] == 1, "the first branch starts fresh on its return: \(reads.values)")
    #expect(reads.values["b"] == 1, "the second branch ran once: \(reads.values)")
}

/// A focusable, accessibility-publishing element holding a `@State` counter,
/// recording its id so a test needs no hand-built path.
private struct FocusableCounter: Element {
    @State var count = 0
    let reads: ConditionalReads
    var elementID: ElementID? { nil }

    mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        count += 1
        reads.values["f"] = count
        reads.ids["f"] = id
        return (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 20)) }.layoutNodeID,
                ())
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                           layout: inout Void, pass: inout PrepaintPass) {
        var handlers = Handlers()
        handlers.isFocusable = true
        handlers.axNode = AXNode(role: .button, label: "counter")
        pass.registerHandlers(handlers, at: bounds, id: id)
    }

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                        layout: inout Void, prepaint: inout Void, pass: inout PaintPass) {}
}

@MainActor
private final class Shown {
    var value = true
}

/// **C2.8, re-derived as 3.3 (plan task 12 part 1, `IX-I`) — a reset keeps
/// the accessibility slot but not focus.** A focused, accessibility-published
/// element inside an `if` goes false for one frame: `window.focusedElement` is
/// `nil`, its `$ax` entry is present, and its `$focus` and `$state0` entries
/// are gone.
///
/// **Renamed** from `aResetKeepsTheFocusAndAccessibilityRetentionSlots`, whose
/// focus clause inverts (T row): `ID-C` exempted `.named("$focus")` and
/// `.named("$ax")`; `IX-I` keeps only `$ax` (accessibility is part 2's, `AB-U`),
/// and the frame whose sweep deletes the focused element's `$focus` slot clears
/// focus in that frame (probe arm F2). Mutation **MRk′** (`$focus` exempt again)
/// reddens the focus half; **M2f** of `ID-C` (no exemption at all) still reddens
/// the `$ax` half.
@MainActor
@Test func aResetKeepsTheAccessibilitySlotButNotFocus() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let reads = ConditionalReads()
    let shown = Shown()
    let (window, platform) = try makeFakeWindow(device: device, size: 100) {
        Box {
            if shown.value { FocusableCounter(reads: reads) }
        }
        .id("root")
    }
    platform.simulateAccessibilityRequest(.activate)
    window.drawFrameIfNeeded()
    let id = try #require(reads.ids["f"], "the element was laid out")
    window.focus(id)
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    let axSlot = GlobalElementID.child(of: id, at: 0, name: ElementID("$ax"))
    let focusSlot = GlobalElementID.child(of: id, at: 0, name: ElementID("$focus"))
    let stateSlot = GlobalElementID.child(of: id, at: 0, name: ElementID("$state0"))
    try #require(window.focusedElement == id, "set up: the confirming frame took focus")
    try #require(window.stateTable.peek(axSlot, as: AXNode.self) != nil, "set up: the element published")
    try #require(window.stateTable.peek(focusSlot, as: Bool.self) != nil, "set up: the focus retention slot exists")
    try #require(window.stateTable.peek(stateSlot, as: Int.self) != nil, "set up: the counter holds state")

    shown.value = false
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    #expect(window.focusedElement == nil, "focus leaves with its identity (IX-I, F2)")
    #expect(window.stateTable.peek(focusSlot, as: Bool.self) == nil, "`$focus` is no longer exempt")
    #expect(window.stateTable.peek(axSlot, as: AXNode.self) != nil, "`$ax` is exempt")
    #expect(window.stateTable.peek(stateSlot, as: Int.self) == nil, "the element's own `@State` is reset")
}

// **C2.13 `focusOutlivesARenameAndAnIfUntilItsElementReturns` is retired**
// (plan task 12 part 1, `IX-I`): it pinned focus retained through a rename and
// an `if` until the element returned — `ID-R` item 9's known, unprobed
// difference. Probe arms F1/F2 measured SwiftUI dropping focus for good, and
// `IX-I` fixes it; its two arms are replaced by 3.1
// `focusDropsWhenItsElementIsRenamedAndDoesNotReturn` (`FocusIdentityTests`)
// and 3.2 `focusDropsWhenAnIfRemovesItsElement` (`FocusTests`).

/// **C2.9 — a reset scans the table only on a transition.** An `if` true for 3
/// frames, false for 3, true for 3: `StateTable.subtreeResetScans` reads exactly
/// **1** — the produced → absent frame, never the steady absent ones.
///
/// Mutation **M2g** (`noteAbsent` scans whenever absent — the transition check
/// dropped) reads 3 and reddens this.
@MainActor
@Test func aResetScansTheTableOnlyOnATransition() {
    let flags = [true, true, true, false, false, false, true, true, true]
    let table = render(flags) { flag in
        Row {
            if flag { CountingElement(nil) }
            CountingElement(nil)
        }
    }
    #expect(table.subtreeResetScans == 1, "scans: \(table.subtreeResetScans)")
}

private struct ConditionalItem: Identifiable {
    let id: String
}

/// **C2.10 — a conditional in a windowed `List` row is not reset by an
/// excursion.** A row whose content holds `if shown { counter }` is scrolled out
/// for two generations and back, with the table held above `sweepThreshold` as
/// `aListRowsStateSurvivesABoundedExcursionButNotALongerOne` holds it: its
/// counter survives (reads 4).
///
/// Only an EVALUATED conditional resets; a row out of the window is not
/// evaluated, so `TB-AH`'s bounded retention is untouched (`ID-C`). Green
/// before (pin). Mutation **M2h** (`sweep()` resets every previously produced
/// slot not produced this frame) reads 1 and reddens this.
@MainActor
@Test func aConditionalInAWindowedListRowIsNotResetByAnExcursion() {
    let reads = ConditionalReads()
    let shown = Shown()
    let data = (0..<12).map { ConditionalItem(id: "row\($0)") }
    let table = StateTable()
    let paddingIDs = (0..<260).map {
        GlobalElementID.child(of: nil, at: 10_000 + $0, name: ElementID("pad\($0)"))
    }
    for id in paddingIDs { table.write(id, 0) }

    var tree = ScrollView(.vertical, elementID: ElementID("scroller")) {
        List(data, rowHeight: Pixels(20)) { item in
            Box {
                if shown.value { ConditionalCounter(item.id, reads) }
            }
        }
    }
    let scrollerID = GlobalElementID.child(of: nil, at: 0, name: ElementID("scroller"))
    func renderFrame(offset: Double?) {
        for id in paddingIDs { table.mark(id) }
        if let offset {
            let current = table.peek(scrollerID, as: ScrollState.self) ?? ScrollState()
            table.write(scrollerID, ScrollState(offset: offset, lastScrollTime: current.lastScrollTime,
                                                viewportExtent: current.viewportExtent))
        }
        Frame(contentSize: Size(width: Pixels(100), height: Pixels(20)), scaleFactor: 1,
              stateTable: table).render(&tree)
    }

    renderFrame(offset: nil)            // cold: every row built
    renderFrame(offset: 100)            // window [3, 8): row 4 in
    renderFrame(offset: 100)
    #expect(reads.values["row4"] == 3, "set up: \(String(describing: reads.values["row4"]))")
    renderFrame(offset: 0)              // window [0, 3): row 4 out, two generations
    renderFrame(offset: 0)
    reads.values["row4"] = nil
    renderFrame(offset: 80)             // window [2, 7): row 4 back
    #expect(reads.values["row4"] == 4,
            "the row's conditional was never evaluated absent, so nothing reset it: \(String(describing: reads.values["row4"]))")
}

// MARK: - C2.11: `if`/`else` inside a proposal container (`ID-D`)

/// **C2.11 — an `if`/`else` inside a proposal stack takes its branch
/// identity.** `HStack { if flag { a } else { b }; t }`: the branches sit at
/// `root/0/0` and `root/1/0` (the `if`/`else` reserves both indices, `SI-F`),
/// the trailing probe at `root/2`; true, false, true resets the first branch (1)
/// and keeps the trailing probe (3).
///
/// Before `ID-D`, `EitherGroup` did not conform to `ProposalElementGroup` and
/// this did not compile. Mutation **M2i** (the TYPED `EitherGroup` copy numbers
/// both branches at `branchIndex`) reddens this.
@MainActor
@Test func anIfElseInsideAProposalStackTakesItsBranchIdentity() {
    let reads = ConditionalReads()
    let table = StateTable()
    for flag in [true, false, true] {
        var tree = HStack(spacing: Pixels(0)) {
            if flag { ProposalConditionalCounter("a", reads) } else { ProposalConditionalCounter("b", reads) }
            ProposalConditionalCounter("t", reads)
        }
        Frame(contentSize: size, scaleFactor: 1, stateTable: table).render(&tree)
    }
    #expect(reads.ids["a"] == child(child(root, 0), 0), "\(String(describing: reads.ids["a"]))")
    #expect(reads.ids["b"] == child(child(root, 1), 0), "\(String(describing: reads.ids["b"]))")
    #expect(reads.ids["t"] == child(root, 2), "\(String(describing: reads.ids["t"]))")
    #expect(reads.values["a"] == 1, "the first branch starts fresh on its return: \(reads.values)")
    #expect(reads.values["t"] == 3, "the trailing probe keeps counting: \(reads.values)")
}

/// **C2.13 — content an `if` removes inside a PROPOSAL container is reset when
/// it returns** (`ID-C`, spec §3.2: both `OptionalGroup` copies note produced
/// and absent). `HStack { if flag { c }; t }` true, false, true: `c` sits at
/// `root/0/0` and reads **1** on its return; `t` stays at `root/1` and counts
/// every frame (3).
///
/// C2.6 pins the untyped copy's reset and C2.5a/C2.5b only the typed copy's
/// slot, so without this test the typed copy's `noteAbsent` was unpinned.
/// Mutation **N1** (typed `OptionalGroup`: `noteAbsent(slot)` replaced with
/// `_ = slot`) reddens this, `c` reading 2.
@MainActor
@Test func contentAnIfInsideAProposalContainerRemovesIsResetWhenItReturns() {
    let reads = ConditionalReads()
    let table = StateTable()
    for flag in [true, false, true] {
        var tree = HStack(spacing: Pixels(0)) {
            if flag { ProposalConditionalCounter("c", reads) }
            ProposalConditionalCounter("t", reads)
        }
        Frame(contentSize: size, scaleFactor: 1, stateTable: table).render(&tree)
    }
    #expect(reads.ids["c"] == child(child(root, 0), 0), "\(String(describing: reads.ids["c"]))")
    #expect(reads.ids["t"] == child(root, 1), "\(String(describing: reads.ids["t"]))")
    #expect(reads.values["c"] == 1, "the returning content starts fresh: \(reads.values)")
    #expect(reads.values["t"] == 3, "the trailing probe keeps counting: \(reads.values)")
}

// MARK: - C2.12: a focused `TextField` inside a toggled `if` (`ID-M` item 4)

@MainActor
private final class FieldModel {
    var text = "hello"
    var shown = true
}

/// **C2.12, re-derived as 3.4 (plan task 12 part 1, `IX-I`) — a focused
/// `TextField` inside a toggled `if` loses focus and starts fresh.** Through a
/// real `Window`: the field is focused, holds a selection and marked text; its
/// `if` goes false for one frame and back. While absent, `setTextInputArea(nil)`
/// is recorded and `window.focusedElement` is `nil`; on return the field is
/// still unfocused (text input stays off) and its `TextEditState` equals
/// `TextEditState()`.
///
/// **Renamed** from `aFocusedTextFieldInsideAToggledIfKeepsFocusAndStartsItsEditStateFresh`,
/// whose focus clause inverts (T row; `IX-I`'s migration note names a
/// `TextField` in an `if` that goes false). **M2d** (no reset) reddens the
/// state half; **MRk′** (`$focus` exempt again) the focus half.
@MainActor
@Test func aFocusedTextFieldInsideAToggledIfLosesFocusAndStartsFresh() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let model = FieldModel()
    let (window, platform) = try makeFakeWindow(device: device, size: 200) {
        Box {
            if model.shown { TextField("Name", text: model.text) { model.text = $0 } }
        }
    }
    window.drawFrameIfNeeded()
    func target() throws -> (bounds: Bounds<Pixels>, input: TextInputTarget) {
        let hitbox = try #require(window.lastHitboxes.first { $0.handlers.textInput != nil })
        return (hitbox.bounds, try #require(hitbox.handlers.textInput))
    }
    let (bounds, input) = try target()
    let y = bounds.origin.y.value + bounds.size.height.value / 2
    let x = Float(input.originX + input.caretOffsets[2]) + 0.5
    platform.simulateInput(.mouseDown(MouseEvent(position: Point(x: Pixels(x), y: Pixels(y)))))
    platform.simulateInput(.mouseUp(MouseEvent(position: Point(x: Pixels(x), y: Pixels(y)))))
    let field = try #require(window.focusedElement, "a press focuses a field")
    platform.simulateInput(.keyDown(KeyEvent(charactersIgnoringModifiers: TextEditing.rightArrow,
                                             characters: TextEditing.rightArrow, modifiers: [.shift],
                                             timestamp: 0)))
    platform.simulateInput(.textComposition(TextComposition(text: "にほ", selection: 2..<2)))
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    let before = try #require(window.stateTable.peek(field, as: TextEditState.self))
    try #require(before.head != 0 && before.composition != .none,
                 "set up: the field holds a caret away from 0 and marked text: \(before)")

    model.shown = false
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    #expect(platform.textInputAreas.last == .some(nil), "an absent field switches text input off")
    #expect(window.focusedElement == nil, "focus leaves with the field (IX-I)")

    model.shown = true
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    #expect(window.focusedElement == nil, "focus does not return with the field (F2)")
    let after = window.stateTable.peek(field, as: TextEditState.self)
    #expect(after == nil || after == TextEditState(),
            "the returning field's edit state is fresh: \(String(describing: after))")
    #expect(platform.textInputAreas.last == .some(nil), "an unfocused field leaves text input off")
    _ = try target()
}
