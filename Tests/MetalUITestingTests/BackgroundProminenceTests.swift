import Foundation
import MetalUI
import MetalUIScene
import MetalUITesting
import Observation
import Testing

// `EnvironmentValues.backgroundProminence` (ruling `OG-Q`, record 408, probe `docs/probes/swiftui-background-prominence.swift`):
// a selected row's content reads `.increased`, every other row `.standard`, and a selection change re-runs only the old and
// the new row's `.equatable()` labels. Counts are read after `runUntilIdle()` then `tick()` and summed over `frameWork`;
// `Modifiers.primary`; narrow builder blocks (`PE-K`); the harness text system. Each test names its mutation.

/// What each label's body saw and how often it ran.
@MainActor private final class ProminenceLog {
    var runs: [String: Int] = [:]
    var last: [String: BackgroundProminence] = [:]
    var total: Int { runs.values.reduce(0, +) }
    func note(_ name: String, _ value: BackgroundProminence) { runs[name, default: 0] += 1; last[name] = value }
    func resetRuns() { runs = [:] }
}

/// A row label that reads `backgroundProminence` and nothing else, behind `.equatable()` as Alloy's `FileTreeLabel` is.
private struct PLabel: Component, @MainActor Equatable {
    let name: String
    let log: ProminenceLog
    @Environment(\.backgroundProminence) var prominence
    static func == (a: PLabel, b: PLabel) -> Bool { a.name == b.name }
    var content: some ElementGroup {
        let _ = log.note(name, prominence)
        Text(name)
    }
}

/// A row label that never reads the value: the steady-frame fixture.
private struct PlainLabel: Component, @MainActor Equatable {
    let name: String
    var content: some ElementGroup { Text(name) }
}

@MainActor @Observable private final class PSelection {
    var one: Int?
    var many: Set<Int> = []
    var text: String?
    func oneBinding() -> Binding<Int?> { Binding(get: { self.one }, set: { self.one = $0 }) }
    func manyBinding() -> Binding<Set<Int>> { Binding(get: { self.many }, set: { self.many = $0 }) }
    func textBinding() -> Binding<String?> { Binding(get: { self.text }, set: { self.text = $0 }) }
}

private struct PRow: Identifiable { let id: Int }

/// A data `List` of `count` rows, 28 high, in a 300 x 300 window; `multi` selects into a set.
@MainActor private func flatWindow(count: Int = 200, model: PSelection, log: ProminenceLog, multi: Bool = false) throws -> TestWindow {
    let rows = (0..<count).map(PRow.init)
    return try harnessWindow(size: sz(300, 300)) {
        ScrollView {
            if multi {
                List(rows, selection: model.manyBinding(), rowHeight: Pixels(28)) { r in
                    Column { PLabel(name: "r\(r.id)", log: log).equatable() }
                }
            } else {
                List(rows, selection: model.oneBinding(), rowHeight: Pixels(28)) { r in
                    Column { PLabel(name: "r\(r.id)", log: log).equatable() }
                }
            }
        }
        .frame(width: Pixels(300), height: Pixels(300))
    }
}

private func flatPoint(_ row: Int) -> Point<Pixels> { pt(150, Float(row) * 28 + 14) }

@MainActor private func idle(_ w: TestWindow) async throws {
    try await w.runUntilIdle()
    w.tick()
}

// MARK: - The value, on a flat list

/// **P1** (probe arms `BP1`, `BP9`: a selected row, emphasized, reads `.increased`; `BP5`: it moves with the selection) The selected row reads `.increased`, every other realised row `.standard`; a click moves it, so the old row reads
/// `.standard` again and the new `.increased`, and a deselect clears it. Mutation: `increased.insert(offset)` dropped from
/// `List.requestLayout` (nothing reads `.increased`).
@Test @MainActor func theSelectedRowReadsIncreasedAndItMovesAndClears() async throws {
    let model = PSelection(), log = ProminenceLog()
    model.one = 2
    let w = try flatWindow(model: model, log: log)
    try await idle(w)
    #expect(log.last["r2"] == .increased)
    for name in ["r0", "r1", "r3", "r4"] { #expect(log.last[name] == .standard, "\(name) reads \(String(describing: log.last[name]))") }
    w.click(at: flatPoint(4)); try await idle(w)
    #expect(model.one == 4)
    #expect(log.last["r4"] == .increased && log.last["r2"] == .standard, "r4 \(String(describing: log.last["r4"])) r2 \(String(describing: log.last["r2"]))")
    model.one = nil; try await idle(w)
    #expect(log.last["r4"] == .standard, "cleared: \(String(describing: log.last["r4"]))")
}

/// **P2** Every selected row of a multi-selection reads `.increased` and no other does; a primary-click adds one and a
/// primary-click on a selected one removes it. Mutation: stop after the first selected row (`break` in the insert).
@Test @MainActor func everySelectedRowOfAMultiSelectionReadsIncreased() async throws {
    let model = PSelection(), log = ProminenceLog()
    model.many = [1, 3]
    let w = try flatWindow(model: model, log: log, multi: true)
    try await idle(w)
    #expect(log.last["r1"] == .increased && log.last["r3"] == .increased)
    #expect(log.last["r0"] == .standard && log.last["r2"] == .standard && log.last["r4"] == .standard)
    w.click(at: flatPoint(5), modifierFlags: Modifiers.primary); try await idle(w)
    #expect(model.many == [1, 3, 5])
    #expect([1, 3, 5].allSatisfy { log.last["r\($0)"] == .increased })
    w.click(at: flatPoint(1), modifierFlags: Modifiers.primary); try await idle(w)
    #expect(model.many == [3, 5])
    #expect(log.last["r1"] == .standard && log.last["r3"] == .increased && log.last["r5"] == .increased)
}

/// **P3** A list with no selection binding never reads `.increased`. Mutation: insert every row.
@Test @MainActor func aListWithNoSelectionReadsStandardEverywhere() async throws {
    let log = ProminenceLog()
    let rows = (0..<20).map(PRow.init)
    let w = try harnessWindow(size: sz(300, 300)) {
        ScrollView { List(rows, rowHeight: Pixels(28)) { r in Column { PLabel(name: "r\(r.id)", log: log).equatable() } } }
            .frame(width: Pixels(300), height: Pixels(300))
    }
    try await idle(w)
    w.click(at: flatPoint(2)); try await idle(w)
    #expect(!log.last.isEmpty && log.last.values.allSatisfy { $0 == .standard })
}

/// **P4** (probe arm `BP17`) An explicit `.environment(\.backgroundProminence, .increased)` below a list row sets it for its content and a
/// sibling does not see it (the value is an ordinary environment key). Mutation: none (a pin on the plain key).
@Test @MainActor func anExplicitWriteSetsTheValueForItsContentOnly() async throws {
    let log = ProminenceLog()
    let w = try harnessWindow(size: sz(300, 100)) {
        Column {
            PLabel(name: "plain", log: log).equatable()
            PLabel(name: "forced", log: log).equatable().environment(\.backgroundProminence, .increased)
        }
    }
    try await idle(w)
    #expect(log.last["plain"] == .standard && log.last["forced"] == .increased)
}

// MARK: - Cost

/// **P5** The pin. A list of 200 rows with `.equatable()` labels reading the value: moving the selection from row 3 to row 5
/// runs exactly two label bodies (the old row's and the new row's), over every frame it takes. Mutation: push `.increased` to
/// every row (`increased = Set(rows.indices)`) reddens it with every realised label re-running; reading the selection in the
/// label (the shape this replaces) reddens it the same way.
@Test @MainActor func movingTheSelectionRunsOnlyTheOldAndTheNewLabel() async throws {
    let model = PSelection(), log = ProminenceLog()
    model.one = 3
    let w = try flatWindow(model: model, log: log)
    try await idle(w)
    #expect(log.runs.count > 8, "realised labels \(log.runs.count)")
    log.resetRuns(); w.resetFrameWork()
    model.one = 5
    try await idle(w)
    let evaluated = w.frameWork.reduce(0) { $0 + $1.contentEvaluations }
    print("OG-Q flat: label runs \(log.total) \(log.runs.keys.sorted()), contentEvaluations \(evaluated)")
    #expect(log.total == 2 && Set(log.runs.keys) == ["r3", "r5"], "runs \(log.runs)")
    #expect(log.last["r3"] == .standard && log.last["r5"] == .increased)
}

/// **P6** A selection that is cleared and set again moves the same two rows only. Mutation as `P5`.
@Test @MainActor func settingAndClearingTheSelectionRunsOnlyThatLabel() async throws {
    let model = PSelection(), log = ProminenceLog()
    let w = try flatWindow(model: model, log: log)
    try await idle(w)
    log.resetRuns(); model.one = 4; try await idle(w)
    #expect(log.total == 1 && log.runs["r4"] == 1, "set: \(log.runs)")
    log.resetRuns(); model.one = nil; try await idle(w)
    #expect(log.total == 1 && log.runs["r4"] == 1, "cleared: \(log.runs)")
}

/// What a frame did, over the fields the retained and build work moves.
private struct Work: Equatable, CustomStringConvertible {
    var builds, requests, prepaints, paints, evaluations, measures, hits, misses: Int
    init(_ all: FrameWork) {
        builds = all.builds; requests = all.elementRequests; prepaints = all.elementPrepaints; paints = all.elementPaints
        evaluations = all.contentEvaluations; measures = all.layoutMeasureCalls
        hits = all.retainedHits; misses = all.retainedMisses
    }
    var description: String {
        "builds \(builds) requests \(requests) prepaints \(prepaints) paints \(paints) evaluations \(evaluations) measures \(measures) hits \(hits) misses \(misses)"
    }
}

/// The steady-frame fixture: 200 rows, selecting, no label reading the value; the rows are plain `Text` or `.equatable()`
/// components, and `selectionMoves` returns the work of the frames a selection change from row 3 to row 5 takes.
@MainActor private func steadyWork(equatable: Bool) async throws -> (steady: Work, moved: Work) {
    let model = PSelection()
    let rows = (0..<200).map(PRow.init)
    let w = try harnessWindow(size: sz(300, 300)) {
        ScrollView {
            if equatable {
                List(rows, selection: model.oneBinding(), rowHeight: Pixels(28)) { r in
                    Column { PlainLabel(name: "r\(r.id)").equatable() }
                }
            } else {
                List(rows, selection: model.oneBinding(), rowHeight: Pixels(28)) { r in Column { Text("r\(r.id)") } }
            }
        }
        .frame(width: Pixels(300), height: Pixels(300))
    }
    model.one = 3
    try await idle(w)
    w.resetFrameWork(); w.window.setNeedsRedraw(); w.tick()
    let steady = Work(w.frameWork.reduce(FrameWork(), +))
    w.resetFrameWork(); model.one = 5; try await idle(w)
    return (steady, Work(w.frameWork.reduce(FrameWork(), +)))
}

/// **P7** Steady frame: a list that never reads the value does the work it did before the value existed, on an idle frame
/// and on a selection change. The literals were measured on master `361c9944` before this change. Mutation: a push of the
/// value on every row, or a read of the selection in every row, which moves `evaluations` or `requests`.
@Test @MainActor func aListThatNeverReadsTheValueKeepsItsWork() async throws {
    let (steady, moved) = try await steadyWork(equatable: false)
    print("OG-Q steady plain: \(steady)")
    print("OG-Q moved plain: \(moved)")
    #expect(steady.description == "builds 1 requests 41 prepaints 42 paints 42 evaluations 0 measures 1 hits 0 misses 0", "\(steady)")
    #expect(moved.description == "builds 1 requests 41 prepaints 42 paints 42 evaluations 0 measures 1 hits 0 misses 0", "\(moved)")
}

/// **P7b** The same with `.equatable()` labels that do not read the value: the idle frame is master's, and a selection
/// change costs the old and the new row's retained occurrences one miss each (the value is in the retained ambient key, so a
/// replayed paint cannot show a stale style), `paints` 2 more and `hits` 2 fewer than master `361c9944` (hits 13, misses 0,
/// paints 29); builds, requests, prepaints and evaluations are master's. Mutation: drop `backgroundProminence` from
/// `EnvironmentValues.retainedFingerprint` (misses 0, and `P12` reddens).
@Test @MainActor func equatableLabelsThatNeverReadTheValueMissOnlyAtTheTwoRows() async throws {
    let (steady, moved) = try await steadyWork(equatable: true)
    print("OG-Q steady equatable: \(steady)")
    print("OG-Q moved equatable: \(moved)")
    #expect(steady.description == "builds 1 requests 41 prepaints 42 paints 29 evaluations 0 measures 1 hits 13 misses 0", "\(steady)")
    #expect(moved.description == "builds 1 requests 41 prepaints 42 paints 31 evaluations 0 measures 1 hits 11 misses 2", "\(moved)")
}

/// A label whose body does not read the value but whose style scope resolves a custom `ShapeStyle` against it when built.
private struct ProminentInk: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> Color { environment.backgroundProminence == .increased ? .red : .blue }
}

private struct PaintLabel: Component, @MainActor Equatable {
    let name: String
    var content: some ElementGroup { Row { Text(name) }.foregroundStyle(ProminentInk()) }
}

/// **P12** (probe arm `BP17`'s write) A retained label that reads the value only through a style scope's resolve, not
/// in its body, repaints with the new colour when its row is selected, and the unselected row beside it replays. Mutation:
/// drop `backgroundProminence` from `retainedFingerprint` (the replayed paint keeps the old ink).
@Test @MainActor func aStyleResolvedAtPaintSeesTheValueThroughARetainedLabel() async throws {
    let model = PSelection()
    let rows = (0..<20).map(PRow.init)
    let w = try harnessWindow(size: sz(300, 300)) {
        ScrollView {
            List(rows, selection: model.oneBinding(), rowHeight: Pixels(28)) { r in
                Column { PaintLabel(name: "r\(r.id)").equatable() }
            }
        }
        .frame(width: Pixels(300), height: Pixels(300))
    }
    try await idle(w)
    let before = try w.drawnTextColors(in: w.element(label: "r2"))
    model.one = 2; try await idle(w)
    let after = try w.drawnTextColors(in: w.element(label: "r2"))
    #expect(before != after, "the ink of r2 did not change on selection: \(before) \(after)")
}

// MARK: - Prepaint and paint

/// A leaf whose prepaint and paint read the value off the pass, not off a body: only the three phases' own environment can
/// tell it, and a retained replay can only notice through the key.
private struct PhaseLeaf: Element {
    let name: String
    let log: ProminenceLog
    var elementID: ElementID? { nil }
    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 40, height: 20)) }.layoutNodeID, ())
    }
    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, pass: inout PrepaintPass) {
        log.note(name + ".prepaint", pass.environment.backgroundProminence)
    }
    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, prepaint: inout Void, pass: inout PaintPass) {
        let value = pass.environment.backgroundProminence
        log.note(name + ".paint", value)
        pass.fill(bounds, color: value == .increased ? Hsla(h: 0, s: 1, l: 0.5, a: 1) : Hsla(h: 0.66, s: 1, l: 0.5, a: 1))
    }
}

private struct PhaseCard: Component, @MainActor Equatable {
    let name: String
    let log: ProminenceLog
    static func == (a: PhaseCard, b: PhaseCard) -> Bool { a.name == b.name }
    var content: some ElementGroup { PhaseLeaf(name: name, log: log) }
}

@MainActor private func redRects(_ w: TestWindow) -> Int { w.allRects.filter { $0.background.h == 0 && $0.background.s == 1 }.count }

@MainActor @TableColumnBuilder<RowRef, Never> private func phaseColumns(_ log: ProminenceLog) -> TableColumnGroup<RowRef, Never> {
    TableColumn("A") { r in PhaseCard(name: "t\(r.id)", log: log).equatable() }.width(Pixels(100))
}

/// **P13** Prepaint and paint of a selected row run under the value too, in a flat list, a content list and a table: a leaf
/// that reads it off the pass at both phases sees `.increased` on the selected row alone, one red rect is drawn, and moving
/// the selection moves it. Mutation: unwrap the phase in `ListRows.prepaintGroup`/`paintGroup`, `ListContentEngine`'s
/// `prepaint`/`paint` helpers, or `TableRowElement.prepaint`/`paint`.
@Test @MainActor func prepaintAndPaintOfASelectedRowRunUnderTheValueInEveryForm() async throws {
    let model = PSelection(), log = ProminenceLog()
    let rows = (0..<12).map(PRow.init)
    let flat = try harnessWindow(size: sz(300, 300)) {
        ScrollView {
            List(rows, selection: model.oneBinding(), rowHeight: Pixels(28)) { r in
                Column { PhaseCard(name: "f\(r.id)", log: log).equatable() }
            }
        }
        .frame(width: Pixels(300), height: Pixels(300))
    }
    let content = try harnessWindow(size: sz(300, 300)) {
        ProposalScrollView {
            List(selection: model.textBinding()) {
                ForEach(["c0", "c1", "c2", "c3"], id: \.self) { n in PhaseCard(name: n, log: log).equatable() }
            }
        }
    }
    let table = try harnessWindow(size: sz(800, 600)) {
        Table(CountingRows(12), selection: model.manyBinding()) { phaseColumns(log) }.tableRowHeight(Pixels(24))
    }
    model.one = 2; model.text = "c1"; model.many = [3]
    for w in [flat, content, table] { try await idle(w) }
    for (name, w, selected, other) in [("f2", flat, "f2", "f1"), ("c1", content, "c1", "c0"), ("t3", table, "t3", "t2")] {
        #expect(log.last[selected + ".prepaint"] == .increased && log.last[selected + ".paint"] == .increased,
                "\(name): prepaint \(String(describing: log.last[selected + ".prepaint"])) paint \(String(describing: log.last[selected + ".paint"]))")
        #expect(log.last[other + ".prepaint"] == .standard && log.last[other + ".paint"] == .standard, "\(name) neighbour")
        #expect(redRects(w) == 1, "\(name): red rects \(redRects(w))")
    }
    model.one = 5; model.text = "c3"; model.many = [6]
    for w in [flat, content, table] { try await idle(w) }
    #expect(log.last["f5.paint"] == .increased && log.last["f2.paint"] == .standard)
    #expect(log.last["c3.paint"] == .increased && log.last["c1.paint"] == .standard)
    #expect(log.last["t6.paint"] == .increased && log.last["t3.paint"] == .standard)
    for w in [flat, content, table] { #expect(redRects(w) == 1) }
}

// MARK: - Outline rows (the content form)

/// A content `List` over an outline: folders `a` and `b`, each open with the children `a/x`, `a/y`, `a/z`, a label per row.
@MainActor private func outlineWindow(model: PSelection, log: ProminenceLog, folders: [String] = ["a", "b"]) throws -> TestWindow {
    try harnessWindow(size: sz(300, 400)) {
        ProposalScrollView {
            List(selection: model.textBinding()) {
                ForEach(folders, id: \.self) { folder in
                    DisclosureGroup(isExpanded: .constant(true)) {
                        ForEach(["x", "y", "z"].map { "\(folder)/\($0)" }, id: \.self) { leaf in PLabel(name: leaf, log: log).equatable() }
                    } label: { PLabel(name: folder, log: log).equatable() }
                }
            }
        }
    }
}

/// The y of the `index`th row of a content list: 32 high, the first 10 below the top.
private func outlineY(_ index: Int) -> Float { 10 + 32 * Float(index) + 16 }

/// **P8** (probe arms `BP11` header and leaf, `BP15` an outline row) In a content `List`, a selected leaf and a selected disclosure header read `.increased` in their labels and nothing
/// else does; a click on another row moves it. Mutation: drop `engine.unitIncreased` in `ListContentEngine.requestLayout`.
@Test @MainActor func aSelectedOutlineRowReadsIncreasedWhetherALeafOrAHeader() async throws {
    let model = PSelection(), log = ProminenceLog()
    model.text = "a/y"
    let w = try outlineWindow(model: model, log: log)
    try await idle(w)
    #expect(log.last["a/y"] == .increased, "leaf: \(String(describing: log.last["a/y"]))")
    for name in ["a", "a/x", "a/z", "b", "b/x"] { #expect(log.last[name] == .standard, "\(name) \(String(describing: log.last[name]))") }
    model.text = "b"; try await idle(w)
    #expect(log.last["b"] == .increased && log.last["a/y"] == .standard, "header: \(String(describing: log.last["b"]))")
    // Row 2 is `a/y`, row 6 is `b/x` (a, a/x, a/y, a/z, b, b/x): a click selects it and the header gives it up.
    w.click(at: pt(150, outlineY(5))); try await idle(w)
    #expect(model.text == "b/x")
    #expect(log.last["b/x"] == .increased && log.last["b"] == .standard)
}

/// **P9** The pin on the content form: 60 folders of three leaves behind `.equatable()` labels, selection moved between two
/// visible leaves, runs exactly the two labels. Mutation: as `P5`, in `LazyStackEngine.requestLayout`.
@Test @MainActor func movingAnOutlineSelectionRunsOnlyTheOldAndTheNewLabel() async throws {
    let model = PSelection(), log = ProminenceLog()
    model.text = "f0/x"
    let folders = (0..<60).map { "f\($0)" }
    let w = try outlineWindow(model: model, log: log, folders: folders)
    try await idle(w)
    #expect(log.runs.count > 6, "realised labels \(log.runs.count)")
    log.resetRuns(); w.resetFrameWork()
    model.text = "f1/y"
    try await idle(w)
    print("OG-Q outline: label runs \(log.total) \(log.runs.keys.sorted())")
    #expect(log.total == 2 && Set(log.runs.keys) == ["f0/x", "f1/y"], "runs \(log.runs)")
}

// MARK: - Table rows

@MainActor @TableColumnBuilder<RowRef, Never> private func prominenceColumns(_ log: ProminenceLog) -> TableColumnGroup<RowRef, Never> {
    TableColumn("A") { r in PLabel(name: "t\(r.id)", log: log).equatable() }.width(Pixels(100))
}

/// **P10** (probe arm `BP16`) A selected `Table` row's cell reads `.increased` (the probe: a `Table` row reads it as a `List` row does) and the
/// others `.standard`; moving the selection re-runs the two rows' labels. Mutation: drop `row.increased = !cellOn`.
@Test @MainActor func aSelectedTableRowReadsIncreased() async throws {
    let model = PSelection(), log = ProminenceLog()
    model.many = [2]
    let w = try harnessWindow(size: sz(800, 600)) {
        Table(CountingRows(50), selection: model.manyBinding()) { prominenceColumns(log) }.tableRowHeight(Pixels(24))
    }
    try await idle(w)
    #expect(log.last["t2"] == .increased && log.last["t1"] == .standard && log.last["t3"] == .standard)
    log.resetRuns()
    w.click(at: rowPoint(4)); try await idle(w)
    #expect(model.many == [4])
    #expect(log.last["t4"] == .increased && log.last["t2"] == .standard)
    #expect(log.total == 2 && Set(log.runs.keys) == ["t2", "t4"], "runs \(log.runs)")
}

/// **P11** A table in cell mode paints the unemphasised fill under a selected row, so its cells read `.standard`.
/// Mutation: set `row.increased = true` whatever the mode.
@Test @MainActor func aCellModeTablesSelectedRowReadsStandard() async throws {
    let model = PSelection(), log = ProminenceLog()
    let cells = CellModel()
    model.many = [2]
    let w = try harnessWindow(size: sz(800, 600)) {
        Table(CountingRows(50), selection: model.manyBinding()) { prominenceColumns(log) }
            .tableRowHeight(Pixels(24)).tableActiveCell(cells.activeBinding())
    }
    try await idle(w)
    #expect(log.last["t2"] == .standard, "cell mode: \(String(describing: log.last["t2"]))")
}
