import Testing
import Foundation
import MetalUI
import MetalUIScene
import MetalUITesting

// The ⌥-click caret toggle and the ⌥-drag column selection (`CV-BK`, record 353): a ⌥ press waits for the release
// (toggle a caret) or the drag (a column selection that replaces every selection). PLAIN imports; the harness text
// system; counters, never a clock.

private let shortLines = "0123456789abcdef\nab\n\n0123456789abcdef\n0123456789abcdef\n"

private struct OptionFixture {
    var window: TestWindow
    var buffer: CodeBuffer
    var geometry: CodeViewGeometry
    var pitch: Float
    var advance: Float
    var folds: CodeFoldState?

    /// A point on `row` at `column` characters from the text origin (past a short line's end too, monospace).
    @MainActor func point(_ row: Int, _ column: Float) -> Point<Pixels> {
        let origin = geometry.rects(for: buffer.snapshot().lineRange(row).lowerBound..<buffer.snapshot().lineRange(row).lowerBound)[0]
        return pt(origin.origin.x.value + column * advance + 0.5, origin.origin.y.value + pitch / 2)
    }
    @MainActor func offset(_ row: Int, _ column: Int) -> Int { buffer.snapshot().offset(of: CodePoint(row: row, column: column)) }
}

@MainActor private func optionFixture(_ text: String = shortLines, lines: Int? = nil, height: Float = 200,
                                      virtual: [CodeVirtualRow] = [], clicks: Cell<Int>? = nil,
                                      handler: EventModifiers? = nil, folded: [Range<Int>] = []) throws -> OptionFixture {
    let buffer = CodeBuffer(lines.map { codeText(lines: $0) } ?? text)
    let folds = folded.isEmpty ? nil : CodeFoldState(selectionState: buffer.selectionState, folded: folded)
    let decorations = CodeDecorations(buffer: buffer)
    if !virtual.isEmpty { decorations.setVirtualRows(virtual, asOf: buffer.version) }
    let geometry = CodeViewGeometry()
    let window = try harnessWindow(size: sz(400, height)) {
        if let handler, let clicks {
            CodeView(buffer: buffer, decorations: decorations).font(size: 12).showsLineNumbers(false).codeCaretBlink(.off)
                .geometry(geometry).onTextClick(modifiers: handler) { _ in clicks.value += 1 }
        } else if let folds {
            CodeView(buffer: buffer, decorations: decorations).font(size: 12).showsLineNumbers(false).codeCaretBlink(.off)
                .geometry(geometry).foldState(folds)
        } else {
            CodeView(buffer: buffer, decorations: decorations).font(size: 12).showsLineNumbers(false).codeCaretBlink(.off)
                .geometry(geometry)
        }
    }
    window.click(at: pt(60, 6))
    buffer.selections = [CodeSelection(caret: 0)]
    window.window.setNeedsRedraw(); window.tick()
    let a = geometry.rects(for: 0..<0)[0].origin.x.value
    let b = geometry.rects(for: 1..<1)[0].origin.x.value
    return OptionFixture(window: window, buffer: buffer, geometry: geometry, pitch: codePitch(scale: 1), advance: b - a, folds: folds)
}

// MARK: Toggle

/// **1** A ⌥-click on text adds a caret there, which becomes the primary; the old selection stays. **Mutation:** the
/// press falling through to a plain press (the old caret is replaced, one selection) or `primary: 0` (the new caret
/// is not the primary).
@Test @MainActor func anOptionClickAddsACaretAndMakesItThePrimary() throws {
    let f = try optionFixture()
    f.window.click(at: f.point(3, 4), modifierFlags: .option)
    #expect(f.buffer.selections == [CodeSelection(caret: 0), CodeSelection(caret: f.offset(3, 4))])
    #expect(f.buffer.selectionState.primaryIndex == 1)
    f.window.click(at: f.point(0, 6), modifierFlags: .option)
    #expect(f.buffer.selections.map(\.head) == [0, f.offset(0, 6), f.offset(3, 4)])
    #expect(f.buffer.selectionState.primaryIndex == 1, "the newest caret is the primary")
}

/// **2** The press alone changes nothing; the release toggles. **Mutation:** the toggle done on the press.
@Test @MainActor func anOptionPressWaitsForTheRelease() throws {
    let f = try optionFixture()
    let p = f.point(3, 4)
    let event = MouseEvent(position: p, modifiers: .option, clickCount: 1, buttonNumber: 0, timestamp: f.window.now)
    _ = f.window.send(.mouseDown(event))
    #expect(f.buffer.selections == [CodeSelection(caret: 0)], "nothing before the release")
    _ = f.window.send(.mouseUp(event))
    #expect(f.buffer.selections.count == 2)
}

/// **3** A ⌥-click inside a selection (a caret at its own offset, a range's edges) removes it, and never the last one;
/// removing the primary hands it to the selection before. **Mutation:** no `count > 1` guard (the last caret goes);
/// removing by row instead of by offset.
@Test @MainActor func anOptionClickInsideASelectionRemovesItButNeverTheLast() throws {
    let f = try optionFixture()
    f.buffer.selectionState.setSelections([CodeSelection(caret: f.offset(0, 1)), CodeSelection(anchor: f.offset(3, 2), head: f.offset(3, 9)),
                                           CodeSelection(caret: f.offset(4, 3))], primary: 2)
    f.window.click(at: f.point(3, 5), modifierFlags: .option)   // inside the range
    #expect(f.buffer.selections == [CodeSelection(caret: f.offset(0, 1)), CodeSelection(caret: f.offset(4, 3))])
    #expect(f.buffer.selectionState.primaryIndex == 1, "the primary keeps its selection")
    f.window.click(at: f.point(4, 3), modifierFlags: .option)   // the primary caret itself
    #expect(f.buffer.selections == [CodeSelection(caret: f.offset(0, 1))])
    #expect(f.buffer.selectionState.primaryIndex == 0)
    f.window.click(at: f.point(0, 1), modifierFlags: .option)   // the last one stays
    #expect(f.buffer.selections == [CodeSelection(caret: f.offset(0, 1))])
}

/// **4** ⌥⌘ (the platform primary) with an `onTextClick(.primary)` handler is a ⌥-click, not the handler's; a
/// handler for exactly ⌥ takes the press first. **Mutation:** the toggle checked before the handler, or the handler
/// matched with `contains`.
@Test @MainActor func optionWithThePrimaryIsAnOptionClickWhenTheHandlerWantsOnlyThePrimary() throws {
    let clicks = Cell(0)
    let f = try optionFixture(clicks: clicks, handler: .primary)
    f.window.click(at: f.point(3, 4), modifierFlags: [.option, .primary])
    #expect(clicks.value == 0)
    #expect(f.buffer.selections.count == 2)
    f.window.click(at: f.point(4, 4), modifierFlags: .primary)
    #expect(clicks.value == 1 && f.buffer.selections.count == 2, "a bare primary is still the handler's")
    let g = try optionFixture(clicks: clicks, handler: .option)
    g.window.click(at: g.point(3, 4), modifierFlags: .option)
    #expect(clicks.value == 2 && g.buffer.selections == [CodeSelection(caret: 0)], "a ⌥ handler takes the press first")
}

// MARK: Column selection

/// **5** A ⌥-drag selects a column: one selection per row, the anchor at the press x and the head at the pointer x,
/// each clamped to the line (a short and an empty line clamp), replacing the old selections; the pointer's row is the
/// primary. **Mutation:** no clamp (offsets past a line's end bleed into the next line); the old selections kept.
@Test @MainActor func anOptionDragSelectsAColumnClampedToShortLines() throws {
    let f = try optionFixture()
    f.buffer.selectionState.setSelections([CodeSelection(caret: f.offset(4, 0)), CodeSelection(caret: f.offset(4, 5))], primary: 0)
    f.window.drag(from: f.point(0, 8), to: f.point(3, 12), modifierFlags: .option)
    let expected = [CodeSelection(anchor: f.offset(0, 8), head: f.offset(0, 12)),
                    CodeSelection(caret: f.offset(1, 2)), CodeSelection(caret: f.offset(2, 0)),
                    CodeSelection(anchor: f.offset(3, 8), head: f.offset(3, 12))]
    #expect(f.buffer.selections == expected, "\(f.buffer.selections)")
    #expect(f.buffer.selectionState.primaryIndex == 3, "the pointer's row is the primary")
}

/// **6** Dragging up and to the left: the heads are left of the anchors, the pointer's (top) row is the primary.
/// **Mutation:** the primary taken as the last in the order of the rows visited.
@Test @MainActor func aReversedColumnDragKeepsThePointersRowAsPrimary() throws {
    let f = try optionFixture()
    f.window.drag(from: f.point(4, 12), to: f.point(0, 3), modifierFlags: .option)
    let sels = f.buffer.selections
    #expect(sels.count == 5)
    #expect(sels[0] == CodeSelection(anchor: f.offset(0, 12), head: f.offset(0, 3)))
    #expect(sels[4] == CodeSelection(anchor: f.offset(4, 12), head: f.offset(4, 3)))
    #expect(f.buffer.selectionState.primaryIndex == 0)
}

/// **7** Virtual rows are no rows of the column: a drag over a virtual row has one selection per buffer row.
/// **Mutation:** one selection per display row (a fifth, sitting on a gap).
@Test @MainActor func aColumnDragSkipsVirtualRows() throws {
    let f = try optionFixture(virtual: [CodeVirtualRow(anchor: .before(line: 2), lines: ["- removed"])])
    f.window.drag(from: f.point(0, 4), to: f.point(3, 4), modifierFlags: .option)   // the pointer's display row is row 3's
    let rows = f.buffer.selections.map { f.buffer.snapshot().point(at: $0.head).row }
    #expect(rows == [0, 1, 2, 3], "\(rows)")
}

/// **8** A drag that stays inside the grapheme it began in is still a toggle. **Mutation:** a column on any move.
@Test @MainActor func aOptionPressThatBarelyMovesIsStillAToggle() throws {
    let f = try optionFixture()
    let p = f.point(3, 4)
    f.window.drag(from: p, to: pt(p.x.value + 0.2, p.y.value), steps: 2, modifierFlags: .option)
    #expect(f.buffer.selections == [CodeSelection(caret: 0), CodeSelection(caret: f.offset(3, 4))])
}

/// **9** A column drag held below the view scrolls and extends the column with it (`CV-AD`), and the release makes the
/// live column the buffer's. **Mutation:** the live column not recomputed in the frames (the selections stay at the
/// row the pointer last moved over).
@Test @MainActor func aColumnDragHeldBelowTheViewAutoscrollsTheColumn() throws {
    let state = CodeScrollState()
    let buffer = CodeBuffer(codeText(lines: 400))
    let window = try harnessWindow(size: sz(400, 300)) {
        VStack(spacing: 0) {
            CodeView(buffer: buffer, decorations: CodeDecorations(buffer: buffer)).font(size: 12).showsLineNumbers(false)
                .codeCaretBlink(.off).scrollState(state).frame(height: Pixels(200)).id("code")
            Box().frame(width: Pixels(20), height: Pixels(20))
        }
    }
    let top = Float(try window.frame(ofID: "code").origin.y.value)
    window.click(at: pt(60, top + 6)); window.tick()
    func event(_ y: Float, _ mods: EventModifiers) -> MouseEvent {
        MouseEvent(position: pt(60, y), modifiers: mods, clickCount: 1, buttonNumber: 0, timestamp: window.now)
    }
    _ = window.send(.mouseDown(event(top + 6, .option)))
    _ = window.send(.mouseDragged(event(top + 220, .option)))
    for _ in 0..<60 { window.advance(by: 1.0 / 60) }
    let live = buffer.selections.count
    _ = window.send(.mouseUp(event(top + 220, .option)))
    window.tick()
    #expect(state.position.row > 10)
    #expect(buffer.selections.count > live && buffer.selections.count > 15, "released: \(buffer.selections.count) (while held \(live))")
    let rows = buffer.selections.map { buffer.snapshot().point(at: $0.head).row }
    #expect(rows == Array(0..<rows.count), "one selection per row, the first at the press row")
    #expect(buffer.selectionState.primaryIndex == rows.count - 1)
}

/// **10** A column is capped at `selectionLimit` selections, the pointer's row still the primary. **Mutation:** no cap.
@Test @MainActor func aColumnDragIsCappedAtTheSelectionLimit() throws {
    let state = CodeScrollState()
    let rowsTotal = CodeSelectionState.selectionLimit + 500
    let buffer = CodeBuffer(String(repeating: "abcdefgh\n", count: rowsTotal))
    let window = try harnessWindow(size: sz(400, 300)) {
        VStack(spacing: 0) {
            CodeView(buffer: buffer, decorations: CodeDecorations(buffer: buffer)).font(size: 12).showsLineNumbers(false)
                .codeCaretBlink(.off).scrollState(state).frame(height: Pixels(200)).id("code")
            Box().frame(width: Pixels(20), height: Pixels(20))
        }
    }
    let top = Float(try window.frame(ofID: "code").origin.y.value)
    window.click(at: pt(60, top + 6)); window.tick()
    func event(_ y: Float) -> MouseEvent {
        MouseEvent(position: pt(60, y), modifiers: .option, clickCount: 1, buttonNumber: 0, timestamp: window.now)
    }
    _ = window.send(.mouseDown(event(top + 6)))
    _ = window.send(.mouseDragged(event(top + 400)))   // far below: the fastest autoscroll
    var seconds = 0
    while state.position.row < Double(rowsTotal) - 20, seconds < 200 { window.advance(by: 1); seconds += 1 }
    _ = window.send(.mouseUp(event(top + 400)))
    window.tick()
    #expect(state.position.row > Double(CodeSelectionState.selectionLimit))
    #expect(buffer.selections.count == CodeSelectionState.selectionLimit, "\(buffer.selections.count)")
    #expect(buffer.selectionState.primaryIndex == CodeSelectionState.selectionLimit - 1)
    let last = buffer.snapshot().point(at: buffer.selections[CodeSelectionState.selectionLimit - 1].head).row
    #expect(last > CodeSelectionState.selectionLimit, "the pointer's row is kept (row \(last))")
}

/// **11** A plain press and drag still select a range after a ⌥ gesture (the ⌥ mode does not stick). **Mutation:**
/// `optionMode` not cleared by a plain press.
@Test @MainActor func aPlainDragAfterAnOptionGestureSelectsARange() throws {
    let f = try optionFixture()
    f.window.drag(from: f.point(0, 8), to: f.point(2, 8), modifierFlags: .option)
    f.window.drag(from: f.point(3, 2), to: f.point(3, 9))
    #expect(f.buffer.selections == [CodeSelection(anchor: f.offset(3, 2), head: f.offset(3, 9))])
    // A ⌥ press whose release never came: the next plain press is a plain press and its release is no toggle.
    _ = f.window.send(.mouseDown(MouseEvent(position: f.point(0, 3), modifiers: .option, clickCount: 1, buttonNumber: 0, timestamp: f.window.now)))
    f.window.click(at: f.point(4, 5))
    #expect(f.buffer.selections == [CodeSelection(caret: f.offset(4, 5))])
}

/// **13** Rows a fold hides are no rows of the column: the view lays out its fold state (`CV-BM`), so the pointer maps
/// through the shown rows and a one-jump drag never lands on a hidden row (nor opens the fold). **Mutation:** the
/// hidden test dropped (a selection on each hidden row), or the pointer mapped through the unfolded row map.
@Test @MainActor func aColumnDragPassesOverRowsAFoldHides() throws {
    let f = try optionFixture(folded: [1..<4])   // rows 2 and 3 are hidden
    f.window.drag(from: f.point(0, 4), to: f.point(4, 4), steps: 1, modifierFlags: .option)
    let rows = f.buffer.selections.map { f.buffer.snapshot().point(at: $0.head).row }
    #expect(rows == [0, 1, 4], "\(rows)")
    #expect(f.folds?.folded == [1..<4], "the fold stays closed")
}

// MARK: Cost

private struct Cost: Equatable, CustomStringConvertible {
    var requests = 0, hits = 0, misses = 0, ineligible = 0, frames = 0
    init(_ f: FrameWork, frames: Int) {
        requests = f.elementRequests; hits = f.retainedHits; misses = f.retainedMisses; ineligible = f.retainedIneligible
        self.frames = frames
    }
    init(requests: Int, hits: Int, misses: Int, ineligible: Int, frames: Int) {
        self.requests = requests; self.hits = hits; self.misses = misses; self.ineligible = ineligible; self.frames = frames
    }
    func perFrameEquals(_ o: Cost) -> Bool {
        frames > 0 && o.frames > 0
            && requests * o.frames == o.requests * frames && hits * o.frames == o.hits * frames
            && misses * o.frames == o.misses * frames && ineligible * o.frames == o.ineligible * frames
    }
    var description: String { "requests \(requests) hits \(hits) misses \(misses) ineligible \(ineligible) frames \(frames)" }
}

private struct CostCard: Component, @MainActor Equatable {
    let buffer: CodeBuffer
    let decorations: CodeDecorations
    var content: some ElementGroup {
        CodeView(buffer: buffer, decorations: decorations).font(size: 12).showsLineNumbers(false).codeCaretBlink(.off)
    }
    static func == (l: CostCard, r: CostCard) -> Bool { l.buffer === r.buffer && l.decorations === r.decorations }
}

@MainActor private func gestureCost(_ modifiers: EventModifiers) async throws -> (press: Cost, steady: Cost, carets: Int) {
    let buffer = CodeBuffer(codeText(lines: 60))
    let decorations = CodeDecorations(buffer: buffer)
    let w = try harnessWindow(size: sz(400, 200)) {
        CostCard(buffer: buffer, decorations: decorations).equatable().frame(width: Pixels(180), height: Pixels(150))
    }
    defer { withExtendedLifetime(w) {} }
    w.click(at: pt(150, 31))   // the card is centred: origin (110, 25)
    for _ in 0..<4 { w.window.setNeedsRedraw(); try await w.runUntilIdle() }
    w.resetFrameWork()
    w.click(at: pt(150, 70), modifierFlags: modifiers)
    try await w.runUntilIdle()
    let press = Cost(totalWork(w), frames: w.frameWork.count)
    for _ in 0..<3 { w.window.setNeedsRedraw(); try await w.runUntilIdle() }
    w.resetFrameWork()
    w.window.setNeedsRedraw(); try await w.runUntilIdle()
    return (press, Cost(totalWork(w), frames: w.frameWork.count), buffer.selections.count)
}

/// **12** REQUIRED: a ⌥ press and release adds no element: the press frame costs what a plain click's costs, and the
/// steady frame after it (now with two carets) costs what the one-caret steady frame costs (1 request, 0/1/0; a plain click's press frame is the same).
/// **Mutation:** a state write through an element, or a ⌥ gesture invalidating the whole tree (the press frame's
/// requests or retention move).
@Test @MainActor func anOptionPressAndReleaseAddNoElement() async throws {
    let plain = try await gestureCost([]), option = try await gestureCost(.option)
    #expect(plain.carets == 1 && option.carets == 2, "carets \(plain.carets) \(option.carets); plain \(plain); option \(option)")
    #if canImport(Darwin)
    #expect(option.press == plain.press, "option \(option.press) vs plain \(plain.press)")
    #expect(option.steady == plain.steady, "option \(option.steady) vs plain \(plain.steady)")
    #expect(plain.steady == Cost(requests: 1, hits: 0, misses: 1, ineligible: 0, frames: 1), "\(plain.steady)")
    #expect(plain.press == Cost(requests: 1, hits: 0, misses: 1, ineligible: 0, frames: 1), "\(plain.press)")
    #else
    #expect(option.press.perFrameEquals(plain.press), "option \(option.press) vs plain \(plain.press)")
    #expect(option.steady.perFrameEquals(plain.steady), "option \(option.steady) vs plain \(plain.steady)")
    #endif
}
