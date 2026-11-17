import Testing
import Foundation
import MetalUI
import MetalUIScene
import MetalUITesting

// Drawing every caret (`CV-BG`, record 340): a caret for every visible empty selection, all in one blink phase; the
// highlight of every visible selection; the selections found by binary search so offscreen ones cost nothing; the
// primary alone drives the reveal and the marked text. PLAIN imports; the harness text system.

private let activeAlpha: Float = 0.31
private let inactiveAlpha: Float = 0.17

@MainActor private func marked(_ decorations: CodeDecorations) {
    decorations.theme.selection = Color(red: 0, green: 0, blue: 1).opacity(Double(activeAlpha))
    decorations.theme.inactiveSelection = Color(red: 1, green: 0, blue: 0).opacity(Double(inactiveAlpha))
}

@MainActor private func offset(_ buffer: CodeBuffer, _ row: Int, _ column: Int) -> Int {
    buffer.snapshot().offset(of: CodePoint(row: row, column: column))
}

@MainActor private func set(_ buffer: CodeBuffer, _ sels: [CodeSelection], primary: Int = 0) {
    buffer.selectionState.setSelections(sels, primary: primary)
}

/// A focused 400 x 200 view of `buffer`; the harness frames settle before it returns.
@MainActor private func open(_ buffer: CodeBuffer, blink: CodeCaretBlink = .off, decorations: CodeDecorations? = nil,
                             scroll: CodeScrollState? = nil) async throws -> TestWindow {
    let decorations = decorations ?? CodeDecorations(buffer: buffer)
    let w = try harnessWindow(size: sz(400, 200)) {
        if let scroll {
            CodeView(buffer: buffer, decorations: decorations).font(size: 12).showsLineNumbers(false).codeCaretBlink(blink).scrollState(scroll)
        } else {
            CodeView(buffer: buffer, decorations: decorations).font(size: 12).showsLineNumbers(false).codeCaretBlink(blink)
        }
    }
    w.click(at: pt(60, 6))
    w.window.setNeedsRedraw(); try await w.runUntilIdle()
    return w
}

@MainActor private func redraw(_ w: TestWindow) async throws { w.window.setNeedsRedraw(); try await w.runUntilIdle() }

/// The rows' tops of the carets drawn, ascending.
@MainActor private func caretTops(_ w: TestWindow) -> [Float] { caretBars(w).map { $0.bounds.origin.y }.sorted() }

private let lines = String(repeating: "abcdefgh\n", count: 60)

// MARK: Carets

/// **1** Every visible empty selection has a caret, at its own row and column, and all blink on the one epoch: on
/// together for the first half second, off together for the next, with the one wake a second (two frames a second, no
/// active animation). Selections off screen have none. **Mutation:** drawing only the primary's caret (1, not 3);
/// a caret per selection with its own blink epoch is not expressible, but `caretIsShown` called per caret would add
/// a deadline each (the frame count below); a caret drawn for each selection in `selections` instead of the visible
/// range draws the offscreen one's bar outside the clip (the row count stays, the top check pins the position).
@Test @MainActor func everyVisibleCaretIsDrawnInPhase() async throws {
    let buffer = CodeBuffer(lines)
    let w = try await open(buffer, blink: .on)
    defer { withExtendedLifetime(w) {} }
    set(buffer, [CodeSelection(caret: offset(buffer, 1, 2)), CodeSelection(caret: offset(buffer, 3, 5)),
                 CodeSelection(caret: offset(buffer, 5, 0)), CodeSelection(caret: offset(buffer, 40, 1))], primary: 1)
    try await redraw(w)
    let pitch = codePitch(scale: 1)
    #expect(caretTops(w) == [1 * pitch, 3 * pitch, 5 * pitch], "three visible carets, one per row: \(caretTops(w))")
    let xs = caretBars(w).map { $0.bounds.origin.x }
    #expect(xs.count == 3 && Set(xs).count == 3, "at three columns: \(xs)")
    let frames = w.framesDrawn
    var shown: [Int] = []
    for _ in 0..<8 {   // two seconds in quarter-second ticks
        w.advance(by: 0.25)
        shown.append(caretBars(w).count)
        #expect(!w.window.hasActiveAnimations, "the blink keeps no display link running")
    }
    #expect(shown == [3, 0, 0, 3, 3, 0, 0, 3], "all three on 0.5 s, all three off 0.5 s: \(shown)")
    #expect(w.framesDrawn - frames == 4, "two frames a second however many carets: \(w.framesDrawn - frames)")
}

/// **2** A selection with a range has a highlight and no caret at its head (Xcode, Alloy's answer 1); a caret
/// beside it has its bar; the highlight of each selection is what that selection paints alone. **Mutation:** a caret
/// at every selection's head (3 bars, not 2); a highlight for the primary only (1 rect, not 2).
@Test @MainActor func onlyEmptySelectionsDrawCaretsAndEverySelectionIsHighlighted() async throws {
    let buffer = CodeBuffer(lines)
    let decorations = CodeDecorations(buffer: buffer)
    marked(decorations)
    let w = try await open(buffer, decorations: decorations)
    defer { withExtendedLifetime(w) {} }
    let ranges = [CodeSelection(anchor: offset(buffer, 1, 1), head: offset(buffer, 1, 4)),
                  CodeSelection(anchor: offset(buffer, 4, 6), head: offset(buffer, 4, 2))]
    func highlights() -> [[Float]] {
        w.scene.rects.filter { abs($0.background.a - activeAlpha) < 0.001 }.map { [$0.bounds.origin.y, $0.bounds.origin.x, $0.bounds.size.width, $0.bounds.size.height] }.sorted { $0[0] < $1[0] }
    }
    var alone: [[Float]] = []
    for range in ranges {   // each range painted by itself, through the scalar path
        set(buffer, [range]); try await redraw(w)
        alone += highlights()
    }
    set(buffer, ranges + [CodeSelection(caret: offset(buffer, 3, 3))]); try await redraw(w)
    #expect(highlights() == alone && alone.count == 2, "both ranges paint what each paints alone: \(highlights()) vs \(alone)")
    #expect(caretTops(w) == [3 * codePitch(scale: 1)], "one caret, the empty selection's; none at a range's head: \(caretTops(w))")
    set(buffer, [CodeSelection(caret: offset(buffer, 3, 3))] + ranges, primary: 2); try await redraw(w)   // the primary a range
    #expect(highlights() == alone && caretBars(w).count == 1, "the order of the input does not matter: \(highlights().count) rects, \(caretBars(w).count) bars")
}

/// **3** The selections touching the shown rows are found by two binary searches, so offscreen selections cost
/// nothing: with 10 000 selections the paint looks at the visible ones plus at most `2 log n` probes, and with every
/// selection below the view, at most the probes. **Mutation:** a linear scan of `selections` (10 000 visited).
@Test @MainActor func offscreenSelectionsCostNothing() async throws {
    let rows = 10_000
    let buffer = CodeBuffer(String(repeating: "abcdefgh\n", count: rows))
    let w = try await open(buffer)
    defer { withExtendedLifetime(w) {} }
    set(buffer, (0..<rows).map { CodeSelection(caret: $0 * 9 + 3) })
    w.resetFrameWork()
    try await redraw(w)
    let visited = totalWork(w).codeSelectionsVisited
    let visible = caretBars(w).count
    #expect(visible >= 10 && visible <= 20, "carets drawn: \(visible)")
    let probes = 2 * 14   // 2 * ceil(log2 10 001)
    #expect(visited > 0 && visited <= visible + probes, "visited \(visited), visible \(visible), bound \(visible + probes)")
    // All below the view: nothing drawn, only the probes.
    set(buffer, (5_000..<rows).map { CodeSelection(caret: $0 * 9 + 3) })
    w.resetFrameWork()
    try await redraw(w)
    #expect(caretBars(w).isEmpty, "carets drawn: \(caretBars(w).count)")
    #expect(totalWork(w).codeSelectionsVisited <= probes, "visited \(totalWork(w).codeSelectionsVisited), bound \(probes)")
}

/// **4** Only the primary is revealed: typing with the primary at the top of the text and another selection far
/// below leaves the view at the top; with the primary the far one, the view scrolls to it. **Mutation:** revealing
/// the last (or the first) selection instead of the primary reverses the two results.
@Test @MainActor func onlyThePrimaryIsRevealed() async throws {
    for primaryFar in [false, true] {
        let buffer = CodeBuffer(String(repeating: "abcdefgh\n", count: 300))
        let scroll = CodeScrollState()
        let w = try await open(buffer, scroll: scroll)
        let near = CodeSelection(caret: offset(buffer, 0, 3)), far = CodeSelection(caret: offset(buffer, 250, 3))
        set(buffer, primaryFar ? [near, far] : [far, near], primary: 1)   // the second of the input: far, or near
        try await redraw(w)
        #expect(scroll.position.row == 0, "setting the selections scrolls nothing: \(scroll.position.row)")
        w.typeText("x")
        try await w.runUntilIdle()
        if primaryFar {
            #expect(scroll.position.row > 200, "the far primary was revealed: row \(scroll.position.row)")
        } else {
            #expect(scroll.position.row == 0, "the far non-primary was not: row \(scroll.position.row)")
        }
        withExtendedLifetime(w) {}
    }
}

// MARK: Colour, blink, composition

/// **5** The inactive selection colour (`CV-BB`) applies to every selection: three visible ranges in a view that is
/// not the focused element draw three inactive rectangles, then three active ones when it has focus, and three
/// inactive ones again in a window that is not key. **Mutation:** choosing the colour for the primary only (1 + 2).
@Test @MainActor func theInactiveSelectionColourAppliesToEverySelection() async throws {
    let buffer = CodeBuffer(lines)
    let decorations = CodeDecorations(buffer: buffer)
    marked(decorations)
    let w = try harnessWindow(size: sz(400, 200)) {
        HStack(spacing: 0) {   // the box takes the initial focus
            Color.gray.frame(width: Pixels(20), height: Pixels(20)).focusable()
            CodeView(buffer: buffer, decorations: decorations).font(size: 12).showsLineNumbers(false).codeCaretBlink(.off)
        }
    }
    defer { withExtendedLifetime(w) {} }
    let three = [CodeSelection(anchor: offset(buffer, 0, 1), head: offset(buffer, 0, 4)),
                 CodeSelection(anchor: offset(buffer, 2, 1), head: offset(buffer, 2, 4)),
                 CodeSelection(anchor: offset(buffer, 4, 1), head: offset(buffer, 4, 4))]
    func painted() -> (active: Int, inactive: Int) {
        (w.scene.rects.filter { abs($0.background.a - activeAlpha) < 0.001 }.count,
         w.scene.rects.filter { abs($0.background.a - inactiveAlpha) < 0.001 }.count)
    }
    w.click(at: pt(10, 100))   // the box has the focus
    set(buffer, three, primary: 1); try await redraw(w)
    #expect(painted() == (0, 3), "unfocused: \(painted())")
    w.click(at: pt(120, 150))   // below the text: the view takes focus, its selections stay
    set(buffer, three, primary: 1); try await redraw(w)
    #expect(painted() == (3, 0), "focused: \(painted())")
    w.setControlActiveState(.inactive); try await redraw(w)
    #expect(painted() == (0, 3), "window not key: \(painted())")
    w.setControlActiveState(.key); try await redraw(w)
    #expect(painted() == (3, 0), "key again: \(painted())")
}

/// **6** Any selection moving restarts the blink, not only the primary: in the hidden half second, moving another
/// selection shows every caret again. **Mutation:** the restart comparing the primary only (the carets stay hidden);
/// `mutationSerial` not bumped on a change.
@Test @MainActor func movingAnotherSelectionRestartsTheBlink() async throws {
    let buffer = CodeBuffer(lines)
    let w = try await open(buffer, blink: .on)
    defer { withExtendedLifetime(w) {} }
    set(buffer, [CodeSelection(caret: offset(buffer, 1, 1)), CodeSelection(caret: offset(buffer, 3, 1))], primary: 0)
    try await redraw(w)
    #expect(caretBars(w).count == 2)
    w.advance(by: 0.5)
    #expect(caretBars(w).isEmpty, "the hidden half")
    set(buffer, [CodeSelection(caret: offset(buffer, 1, 1)), CodeSelection(caret: offset(buffer, 3, 4))], primary: 0)
    try await redraw(w)
    #expect(caretBars(w).count == 2, "the second selection moved: both shown again")
    w.advance(by: 0.5)
    #expect(caretBars(w).isEmpty)
}

/// **7** A composition is drawn at the primary only: two carets, marked text at the primary adds its glyphs once and
/// the other caret keeps its bar; the commit goes to every selection. **Mutation:** the marked text drawn at every
/// selection (4 extra glyphs, not 2); the commit replacing the primary only; the second caret placed in the marked text (one bar x, not two).
@Test @MainActor func aCompositionIsDrawnAtThePrimaryOnlyAndCommittedAtEverySelection() async throws {
    let buffer = CodeBuffer("hello\nworld\n")
    let w = try await open(buffer)
    defer { withExtendedLifetime(w) {} }
    set(buffer, [CodeSelection(caret: 2), CodeSelection(caret: 4)], primary: 0)   // one row, so the second caret sits after the marked text
    try await redraw(w)
    let glyphs = w.scene.glyphs.count
    #expect(w.setMarkedText("かな"))
    try await w.runUntilIdle()
    #expect(w.scene.glyphs.count == glyphs + 2, "the composition once: \(w.scene.glyphs.count) vs \(glyphs)")
    let xs = caretBars(w).map { $0.bounds.origin.x }
    #expect(xs.count == 2 && Set(xs).count == 2, "both carets drawn, the second after the marked text: \(xs)")
    #expect(w.commitMarkedText("X"))
    try await w.runUntilIdle()
    #expect(buffer.snapshot().text == "heXllXo\nworld\n", Comment(rawValue: buffer.snapshot().text))
    #expect(buffer.selections.count == 2)
}
