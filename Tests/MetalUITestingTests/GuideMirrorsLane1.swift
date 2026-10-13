import MetalUI
import MetalUITesting
import Observation
import Testing

// Lane 1 of the developer guides (item 10b; rulings `DG-C`…`DG-M`): the mirrors of the
// swift blocks of `docs/guides/layout.md`, `state-and-identity.md` and `input.md`, copied
// BY HAND between the `// guide:` and `// end guide` markers, byte for byte, so the ordinary
// build compiles them on every platform; `GuideDocCheck.swift` compares each region with
// its guide. Below the regions, the tests that run the blocks in a headless window and
// prove the claims the guides pin to them. Change a guide and its mirror together. Every
// top-level name carries its guide's topic as prefix (`DG-K`: one module, both lanes).
// Mutations: delete the modifier a test names (the second `.padding`, the `.id(...)`, the
// `.onCancelled`, `.hoverKeyRegion()`).


// MARK: - Tests

private func guideX(_ bounds: Bounds<Pixels>) -> Float { bounds.origin.x.value }

// MARK: Layout

/// **T8** — every root function of the layout guide builds in a headless window.
/// Mutation: rename a block's root function (the window cannot build it).
@Test @MainActor func theLayoutGuideBuildsInAHeadlessWindow() throws {
    _ = try harnessWindow { layoutProfileCard() }
    _ = try harnessWindow { layoutLegacyRow() }
    _ = try harnessWindow { layoutStackRow() }
    _ = try harnessWindow { layoutPaddingThenBackground() }
    _ = try harnessWindow { layoutBackgroundThenPadding() }
    _ = try harnessWindow { layoutNamedWhole() }
    _ = try harnessWindow { layoutGrid() }
    let card = try harnessWindow { layoutProfileCard() }
    _ = try card.element(label: "Ada Lovelace")
}

/// Two 20-point boxes: 20 apart in a `Row` (gap 0), 28 in an `HStack` (default 8).
/// Mutation: give the `HStack` `spacing: 0`.
@Test @MainActor func theLayoutGuideRowAndHStackDifferByTheDefaultGap() throws {
    let legacy = try harnessWindow { layoutLegacyRow() }
    let stack = try harnessWindow { layoutStackRow() }
    let legacyGap = guideX(try legacy.frame(ofID: "legacy-b")) - guideX(try legacy.frame(ofID: "legacy-a"))
    let stackGap = guideX(try stack.frame(ofID: "stack-b")) - guideX(try stack.frame(ofID: "stack-a"))
    #expect(legacyGap == 20, "a Row's boxes touch; read \(legacyGap)")
    #expect(stackGap == 28, "an HStack puts 8 between them; read \(stackGap)")
}

/// The fill after `.padding` measures the padded box; the fill before it, the content.
/// Mutation: swap `.padding` and `.background` in one function.
@Test @MainActor func theLayoutGuideBackgroundFollowsTheModifierOrder() throws {
    let outside = try harnessWindow { layoutPaddingThenBackground() }
    let inside = try harnessWindow { layoutBackgroundThenPadding() }
    let outer = try outside.frame(ofID: "fill-outside")
    let inner = try inside.frame(ofID: "fill-inside")
    #expect(outer.size.width.value == 40 && outer.size.height.value == 40, "read \(outer)")
    #expect(inner.size.width.value == 20 && inner.size.height.value == 20, "read \(inner)")
}

/// `.id` after the last modifier names the whole padded element: 40 × 40, not the 20 × 20
/// content. Mutation: move `.id("whole")` before `.padding`.
@Test @MainActor func theLayoutGuideAnIdWrittenLastNamesTheWholeElement() throws {
    let window = try harnessWindow { layoutNamedWhole() }
    let whole = try window.frame(ofID: "whole")
    #expect(whole.size.width.value == 40 && whole.size.height.value == 40, "read \(whole)")
}

/// Column one is as wide as its widest cell (60), so column two starts 60 + 8 on, in both rows.
/// Mutation: change a cell width in the guide's first column to 100 (the literal moves).
@Test @MainActor func theLayoutGuideGridColumnsTakeTheirWidestCell() throws {
    let window = try harnessWindow { layoutGrid() }
    let a1 = try window.frame(ofID: "cell-a1"), a2 = try window.frame(ofID: "cell-a2")
    let b2 = try window.frame(ofID: "cell-b2")
    #expect(guideX(a2) - guideX(a1) == 68, "read \(guideX(a2) - guideX(a1))")
    #expect(guideX(b2) == guideX(a2), "the second column is one column")
}

// MARK: State

@MainActor
private func stateLabelIsAbsent(_ window: TestWindow, _ label: String) -> Bool {
    (try? window.element(label: label)) == nil
}

/// **T9** — the state guide builds, and a typed character reaches the binding the field
/// shares with the label. Mutation: replace `$name` with `.constant(name)`.
@Test @MainActor func theStateGuideBuildsInAHeadlessWindowAndItsClaimsHold() throws {
    _ = try harnessWindow { stateGreetingRoot() }
    _ = try harnessWindow { stateTodoRoot(StateTodoStore()) }
    _ = try harnessWindow { VStack { StateLosses() } }
    _ = try harnessWindow { VStack { StateRowPicker() } }
}

@Test @MainActor func theStateGuideATypedNameWritesTheBinding() throws {
    let window = try harnessWindow { stateGreetingRoot() }
    _ = try window.element(label: "Hello Ada, greeted 0 times")
    let field = try #require(try window.elements(role: .textField).first)
    try window.click(field)
    window.typeText("!")
    _ = try window.element(label: "Hello Ada!, greeted 0 times")
    try window.click(window.element(label: "Greet"))
    _ = try window.element(label: "Hello Ada!, greeted 1 times")
}

/// Reversing the store reorders the rows and each row keeps its taps (the id is the value).
/// Mutation: `id: \.self` to an index id (`Array(items.indices)`).
@Test @MainActor func theStateGuideForEachRowsKeepTheirStateWhenTheDataReorders() async throws {
    let store = StateTodoStore()
    let window = try harnessWindow { stateTodoRoot(store) }
    try window.click(window.element(label: "Write: 0"))
    try await window.runUntilIdle()
    let writeBefore = try window.element(label: "Write: 1")
    let shipBefore = try window.element(label: "Ship: 0")
    try #require(writeBefore.frame.origin.y.value < shipBefore.frame.origin.y.value, "set up: Write is above Ship")
    try window.click(window.element(label: "Reverse"))
    try await window.runUntilIdle()
    #expect(store.items == ["Ship", "Test", "Write"])
    let write = try window.element(label: "Write: 1")
    let ship = try window.element(label: "Ship: 0")
    #expect(ship.frame.origin.y.value < write.frame.origin.y.value, "the rows are reordered")
}

/// Hiding the counter and showing it again starts it at 0. Mutation: delete the `if shown`.
@Test @MainActor func theStateGuideAHiddenBranchStartsFreshWhenItReturns() throws {
    let window = try harnessWindow { VStack { StateLosses() } }
    try window.click(window.element(label: "Taps: 0"))
    try window.click(window.element(label: "Taps: 1"))
    _ = try window.element(label: "Taps: 2")
    try window.click(window.element(label: "Toggle"))
    #expect(stateLabelIsAbsent(window, "Taps: 2"), "the branch is gone")
    try window.click(window.element(label: "Toggle"))
    _ = try window.element(label: "Taps: 0")
}

/// A changed `.id` is a new element. Mutation: delete `.id("taps-\(generation)")`.
@Test @MainActor func theStateGuideANewIdStartsFresh() throws {
    let window = try harnessWindow { VStack { StateLosses() } }
    try window.click(window.element(label: "Taps: 0"))
    _ = try window.element(label: "Taps: 1")
    try window.click(window.element(label: "New id"))
    _ = try window.element(label: "Taps: 0")
}

/// 200 rows in a 200-point scroller: the first is in the tree, row 150 is not; a click selects.
/// Mutation: `List` to a `ForEach` in a `Column` (every row is built).
@Test @MainActor func theStateGuideAListBuildsOnlyItsWindowAndSelectsOnClick() throws {
    let window = try harnessWindow { VStack { StateRowPicker() } }
    _ = try window.element(label: "Selected: 0")
    _ = try window.element(label: "Row 0")
    #expect(stateLabelIsAbsent(window, "Row 150"), "a row out of the window is not in the tree")
    try window.click(window.element(label: "Row 1"))
    _ = try window.element(label: "Selected: 1")
}

// MARK: Input

/// **T10** — the input guide builds. Mutation: rename `inputDragPad`.
@Test @MainActor func theInputGuideBuildsInAHeadlessWindowAndItsClaimsHold() throws {
    _ = try harnessWindow { inputControlsRoot() }
    _ = try harnessWindow { inputDragPad(InputGestureLog()) }
    _ = try harnessWindow { inputWindowDragHandle() }
    _ = try harnessWindow { inputKeyRegion(InputKeyLog()) }
    if #available(macOS 15, *) { _ = try harnessWindow { inputRenameRoot() } }
}

@Test @MainActor func theInputGuideAClickPressesAButtonWithoutFocusingIt() throws {
    let window = try harnessWindow { inputControlsRoot() }
    try window.click(window.element(label: "Add"))
    _ = try window.element(label: "Count 1")
    #expect(try window.focusedElement == nil, "a click on a Button focuses nothing")
}

/// Press, drag, press again (the release is lost), release: the first drag is cancelled once.
/// Mutation: delete `.onCancelled { … }` from `inputDragPad`.
@Test @MainActor func theInputGuideALostReleaseRunsOnCancelledOnce() throws {
    let log = InputGestureLog()
    let window = try harnessWindow { inputDragPad(log) }
    func at(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: Pixels(x), y: Pixels(y)) }
    _ = window.send(.mouseDown(MouseEvent(position: at(200, 150))))
    _ = window.send(.mouseDragged(MouseEvent(position: at(210, 150))))
    _ = window.send(.mouseDown(MouseEvent(position: at(200, 150))))
    _ = window.send(.mouseUp(MouseEvent(position: at(200, 150))))
    #expect(log.entries == ["changed", "changed", "cancelled", "changed", "ended"], "read \(log.entries)")
}

/// A press-drag on the handle asks the platform to move the window once.
/// Mutation: delete `.gesture(WindowDragGesture())`.
@Test @MainActor func theInputGuideAWindowDragHandleAsksThePlatformOnce() throws {
    let window = try harnessWindow(size: Size(width: Pixels(300), height: Pixels(300))) { inputWindowDragHandle() }
    #expect(window.windowDrags == 0)
    window.drag(from: Point(x: Pixels(100), y: Pixels(16)), to: Point(x: Pixels(140), y: Pixels(16)))
    window.tick()
    #expect(window.windowDrags == 1)
}

/// With nothing focused, Space goes to the key region under the pointer; away from it, nowhere.
/// Mutation: delete `.hoverKeyRegion()`.
@Test @MainActor func theInputGuideAKeyGoesToTheKeyRegionUnderThePointer() throws {
    let log = InputKeyLog()
    let window = try harnessWindow { inputKeyRegion(log) }
    window.hover(at: Point(x: Pixels(10), y: Pixels(10)))
    window.typeKey(.space)
    #expect(log.entries.isEmpty, "the pointer is outside the region; read \(log.entries)")
    window.hover(at: Point(x: Pixels(200), y: Pixels(150)))
    window.typeKey(.space)
    #expect(log.entries == ["space"], "read \(log.entries)")
}

/// Writing the selection binding is seen by the label. Mutation: delete the button's write.
@Test @MainActor func theInputGuideSelectAllWritesTheSelectionBinding() throws {
    guard #available(macOS 15, *) else { return }
    let window = try harnessWindow { inputRenameRoot() }
    _ = try window.element(label: "no selection")
    try window.click(window.element(label: "Select all"))
    _ = try window.element(label: "selection set")
}
