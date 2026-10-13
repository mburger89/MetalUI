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

// guide: layout #1
import MetalUI

/// A profile card: a title over a row whose spacer pushes two labels apart.
@MainActor
func layoutProfileCard() -> some Element {
    VStack(alignment: .leading, spacing: Pixels(8)) {
        Text("Ada Lovelace").font(size: 20)
        HStack {
            Text("Mathematician")
            Spacer()
            Text("1815")
        }
    }
    .padding(Edges(all: Pixels(16)))
    .frame(width: Pixels(240))
    .background(.surface)
}
// end guide

// guide: layout #2
/// Two 20-point boxes in a legacy `Row`: no gap.
@MainActor
func layoutLegacyRow() -> some Element {
    Row {
        Box().frame(width: Pixels(20), height: Pixels(20)).id("legacy-a")
        Box().frame(width: Pixels(20), height: Pixels(20)).id("legacy-b")
    }
}

/// The same boxes in an `HStack`: the default spacing of 8.
@MainActor
func layoutStackRow() -> some Element {
    HStack {
        Box().frame(width: Pixels(20), height: Pixels(20)).id("stack-a")
        Box().frame(width: Pixels(20), height: Pixels(20)).id("stack-b")
    }
}
// end guide

// guide: layout #3
/// A fill that takes whatever it is proposed; a `Box` is the leaf the harness reads by id.
@MainActor
func layoutFill(_ name: String) -> some ProposalElementGroup {
    HStack {
        Box().frame(maxWidth: .infinity, maxHeight: .infinity).id(name)
    }
}

/// The fill sits outside the padding: it measures 40 × 40.
@MainActor
func layoutPaddingThenBackground() -> some Element {
    Rectangle().frame(width: Pixels(20), height: Pixels(20))
        .padding(Edges(all: Pixels(10)))
        .background(alignment: .center) { layoutFill("fill-outside") }
}

/// The fill sits inside the padding: it measures 20 × 20.
@MainActor
func layoutBackgroundThenPadding() -> some Element {
    Rectangle().frame(width: Pixels(20), height: Pixels(20))
        .background(alignment: .center) { layoutFill("fill-inside") }
        .padding(Edges(all: Pixels(10)))
}
// end guide

// guide: layout #4
/// `.id` last: the name belongs to the padded element, 40 × 40.
@MainActor
func layoutNamedWhole() -> some Element {
    HStack {
        Box().frame(width: Pixels(20), height: Pixels(20))
            .padding(Pixels(10))
            .id("whole")
    }
}
// end guide

// guide: layout #5
/// Two rows of two cells: column one is 60 wide, column two starts after it.
@MainActor
func layoutGrid() -> some Element {
    Grid(alignment: .topLeading, horizontalSpacing: Pixels(8), verticalSpacing: Pixels(4)) {
        GridRow {
            Box().frame(width: Pixels(40), height: Pixels(10)).id("cell-a1")
            Box().frame(width: Pixels(80), height: Pixels(10)).id("cell-a2")
        }
        GridRow {
            Box().frame(width: Pixels(60), height: Pixels(10)).id("cell-b1")
            Box().frame(width: Pixels(20), height: Pixels(10)).id("cell-b2")
        }
    }
}
// end guide

// guide: state-and-identity #1
import MetalUI

/// `@State` lives as long as the component keeps its place in the tree;
/// `$name` is a `Binding` to it.
struct StateGreeting: Component {
    @State var name = "Ada"
    @State var greetings = 0

    var content: some ElementGroup {
        TextField("Name", text: $name)
        Button("Greet") { greetings += 1 }
        Text("Hello \(name), greeted \(greetings) times")
    }
}

/// The window's root: any container takes the component.
@MainActor
func stateGreetingRoot() -> some Element {
    VStack(alignment: .leading) { StateGreeting() }
}
// end guide

// guide: state-and-identity #2
import Observation

/// A shared model: an `@Observable` class, provided once and read by type.
@Observable @MainActor
final class StateTodoStore {
    var items = ["Write", "Test", "Ship"]

    func reverse() { items.reverse() }
}

/// A row's `@State` follows its value: the `ForEach` below uses the item as the id.
struct StateTodoRow: Component {
    let title: String
    @State var taps = 0

    var content: some ElementGroup {
        Button("\(title): \(taps)") { taps += 1 }
    }
}

struct StateTodoList: Component {
    @Environment(StateTodoStore.self) var store

    var content: some ElementGroup {
        Button("Reverse") { store.reverse() }
        ForEach(store.items, id: \.self) { item in
            StateTodoRow(title: item)
        }
    }
}

/// The store is provided once, around the component that reads it.
@MainActor
func stateTodoRoot(_ store: StateTodoStore) -> some Element {
    VStack(alignment: .leading) {
        StateTodoList().environment(store)
    }
}
// end guide

// guide: state-and-identity #3
struct StateTaps: Component {
    @State var taps = 0

    var content: some ElementGroup {
        Button("Taps: \(taps)") { taps += 1 }
    }
}

/// "Toggle" hides and shows the counter; "New id" gives it another name.
struct StateLosses: Component {
    @State var shown = true
    @State var generation = 0

    var content: some ElementGroup {
        Button("Toggle") { shown.toggle() }
        Button("New id") { generation += 1 }
        if shown {
            StateTaps().id("taps-\(generation)")
        }
    }
}
// end guide

// guide: state-and-identity #4
struct StateRowItem: Identifiable {
    let id: Int
    var title: String { "Row \(id)" }
}

struct StateRowPicker: Component {
    @State var picked: Set<Int> = []
    let items = (0..<200).map { StateRowItem(id: $0) }

    var content: some ElementGroup {
        Text("Selected: \(picked.count)")
        ScrollView {
            List(items, selection: $picked) { item in
                Text(item.title).padding(Pixels(6))
            }
        }
        .frame(height: Pixels(200))
    }
}
// end guide

// guide: input #1
import MetalUI

/// A button and a toggle over `@State`.
struct InputControls: Component {
    @State var count = 0
    @State var notifications = true

    var content: some ElementGroup {
        Button("Add") { count += 1 }
        Toggle("Notifications", isOn: $notifications)
        Text("Count \(count)")
    }
}

@MainActor
func inputControlsRoot() -> some Element {
    VStack(alignment: .leading) { InputControls() }
}
// end guide

// guide: input #2
/// What a gesture saw, in order.
@MainActor
final class InputGestureLog {
    var entries: [String] = []
}

/// A drag pad that logs `changed`, `ended` and `cancelled`.
@MainActor
func inputDragPad(_ log: InputGestureLog) -> some Element {
    Rectangle()
        .frame(width: Pixels(200), height: Pixels(100))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in log.entries.append("changed") }
                .onEnded { _ in log.entries.append("ended") }
                .onCancelled { log.entries.append("cancelled") }
        )
}
// end guide

// guide: input #3
/// A full-window viewport with a 32-point drag handle on top of it.
@MainActor
func inputWindowDragHandle() -> some Element {
    ZStack(alignment: .top) {
        Rectangle().frame(width: Pixels(300), height: Pixels(300))
        Rectangle().frame(width: Pixels(300), height: Pixels(32)).gesture(WindowDragGesture())
    }
}
// end guide

// guide: input #4
/// What a key handler saw.
@MainActor
final class InputKeyLog {
    var entries: [String] = []
}

/// A canvas stand-in that is a key region and handles Space.
@MainActor
func inputKeyRegion(_ log: InputKeyLog) -> some Element {
    Rectangle()
        .frame(width: Pixels(120), height: Pixels(80))
        .hoverKeyRegion()
        .onKeyPress(keys: [.space]) { _ in
            log.entries.append("space")
            return .handled
        }
}
// end guide

// guide: input #5
/// A field whose selection the app can read and write.
@available(macOS 15, *)
struct InputRename: Component {
    @State var title = "Quarterly plan"
    @State var selection: TextSelection?

    var content: some ElementGroup {
        TextField("Title", text: $title, selection: $selection)
        Button("Select all") {
            selection = TextSelection(range: title.startIndex..<title.endIndex)
        }
        Text(selection == nil ? "no selection" : "selection set")
    }
}

@available(macOS 15, *)
@MainActor
func inputRenameRoot() -> some Element {
    VStack(alignment: .leading) { InputRename() }
}
// end guide


// guide: input #6
/// A field and an inert panel: a click on the panel ends editing.
struct InputCommit: Component {
    @State var name = ""

    var content: some ElementGroup {
        TextField("Name", text: $name)
            .frame(width: Pixels(200), height: Pixels(24))
            .accessibilityIdentifier("name")
        Box().frame(width: Pixels(200), height: Pixels(80)).background(.surface).id("panel")
        Text("Hello \(name)")
    }
}

@MainActor
func inputResignRoot() -> some Element {
    VStack(alignment: .leading) { InputCommit() }
        .resignsFocusOnPress()
}
// end guide

// guide: input #7
/// What a field's model heard, in order.
@MainActor
final class InputComposeModel {
    var text = "hello"
    var writes: [String] = []
}

/// A field over a plain class, so a test sees every write.
@MainActor
func inputComposeRoot(_ model: InputComposeModel) -> some Element {
    VStack(alignment: .leading) {
        TextField("Name", text: model.text) { model.writes.append($0); model.text = $0 }
            .frame(width: Pixels(200), height: Pixels(24))
            .accessibilityIdentifier("name")
    }
}
// end guide


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
/// The write is drawn with `runUntilIdle()`, as `docs/testing.md` says for a model written off
/// the macOS main loop (`DG-W`). Mutation: `id: \.self` to an index id.
@Test @MainActor func theStateGuideForEachRowsKeepTheirStateWhenTheDataReorders() async throws {
    let store = StateTodoStore()
    let window = try harnessWindow { stateTodoRoot(store) }
    try window.click(window.element(label: "Write: 0"))
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
    window.tick()   // a List asks for one more frame when its window would grow
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
    _ = try harnessWindow { inputResignRoot() }
    _ = try harnessWindow { inputComposeRoot(InputComposeModel()) }
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

/// **Followup 10c** (`DG-R`). A primary press on the panel inside `.resignsFocusOnPress()` ends editing
/// and keeps the typed text; a later key changes nothing. Mutation: delete `.resignsFocusOnPress()` from `inputResignRoot`.
@Test @MainActor func theInputGuideAClickOnInertChromeEndsEditing() throws {
    let window = try harnessWindow { inputResignRoot() }
    try window.click(window.element(identifier: "name"))
    #expect(try window.focusedElement?.identifier == "name")
    window.typeText("Ada")
    _ = try window.element(label: "Hello Ada")
    let panel = try window.frame(ofID: "panel")
    window.click(at: Point(x: panel.origin.x + Pixels(50), y: panel.origin.y + Pixels(40)))
    #expect(try window.focusedElement == nil, "the click on the panel ended editing")
    window.typeText("zzz")
    _ = try window.element(label: "Hello Ada")
}

/// The driver's four verbs on the guide's field: marked text is in the field, not the model;
/// a commit writes once; a cancel writes nothing; with no focused field every verb answers false.
/// Mutation: delete `model.writes.append($0);` from `inputComposeRoot`.
@Test @MainActor func theInputGuideAnInputMethodComposesCommitsAndCancels() throws {
    let model = InputComposeModel()
    let window = try harnessWindow { inputComposeRoot(model) }
    #expect(!window.setMarkedText("ni"), "no field holds the caret yet")
    try window.click(window.element(identifier: "name"))
    #expect(window.setMarkedText("ni"))
    #expect(window.markedText == "ni")
    #expect(model.writes.isEmpty)
    #expect(try window.focusedElement?.value == "hello", "the AX value is the committed text")
    #expect(window.commitMarkedText("\u{4F60}"))
    #expect(model.writes.count == 1, "read \(model.writes)")
    #expect(window.markedText == "")
    window.setMarkedText("hao")
    #expect(window.cancelMarkedText())
    #expect(model.writes.count == 1)
}
