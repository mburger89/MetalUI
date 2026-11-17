import Testing
import Foundation
import MetalUI
import MetalUIScene
import MetalUITesting

// The keys and paint of a snippet session in `CodeView` (`CV-BR`, record 377): Tab and Shift-Tab step the
// placeholders, Escape ends the session before it collapses, the view's indent unit reaches the state, the
// non-current placeholders are tinted, and a keystroke in a session costs a plain keystroke. PLAIN imports; the
// harness text system. Counters, never a clock.
//
// Mutations run against this file (each reddened the named tests, then was restored):
//  - `.indent` not asking the session first: `tabAndShiftTabStepAndDollarZeroEnds`, `theKeyOrderIsPopoverThenOnKeyPressThenSnippetThenCollapse`.
//  - ⇧Tab at the first stop not declining (returning true): `shiftTabAtFirstFallsToOutdent`.
//  - `.collapseSelections where isSnippetActive` removed: `escEndsThenSecondEscCollapses`.
//  - the plan not writing `viewIndentSpaces`: `theViewsIndentUnitIsUsedWhenNoneIsGiven`.
//  - the paint tinting the current group too: `nonCurrentPlaceholdersAreTinted`.
//  - the paint tint read from the wrong theme field (`currentLine`): `nonCurrentPlaceholdersAreTinted`.
//  - the plan copying the session with no `isSnippetActive` check (observed read removed): `endingTheSessionRedraws`.
//  - a per-placeholder element or a retention taint in the paint: `aKeystrokeInASessionCostsAPlainKeystroke`.

private let tintAlpha: Float = 0.37

private func theme() -> CodeTheme {
    var theme = CodeTheme()
    theme.snippetPlaceholder = Color(red: 0, green: 1, blue: 0).opacity(Double(tintAlpha))
    return theme
}

private struct Cost: Equatable, CustomStringConvertible {
    var requests = 0, hits = 0, misses = 0, ineligible = 0, frames = 0
    init(requests: Int, hits: Int, misses: Int, ineligible: Int, frames: Int) {
        self.requests = requests; self.hits = hits; self.misses = misses; self.ineligible = ineligible; self.frames = frames
    }
    /// The same work per frame (off Darwin the frames a keystroke spans depend on the main-actor hop).
    func perFrameEquals(_ o: Cost) -> Bool {
        frames > 0 && o.frames > 0
            && requests * o.frames == o.requests * frames && hits * o.frames == o.hits * frames
            && misses * o.frames == o.misses * frames && ineligible * o.frames == o.ineligible * frames
    }
    var description: String { "requests \(requests) hits \(hits) misses \(misses) ineligible \(ineligible) frames \(frames)" }
    init(_ f: FrameWork, frames: Int) {
        requests = f.elementRequests; hits = f.retainedHits; misses = f.retainedMisses; ineligible = f.retainedIneligible
        self.frames = frames
    }
}

private struct Card: Component, @MainActor Equatable {
    let buffer: CodeBuffer
    let decorations: CodeDecorations
    var spaces: Int?
    var content: some ElementGroup {
        if let spaces {
            CodeView(buffer: buffer, decorations: decorations).font(size: 12).showsLineNumbers(false).codeCaretBlink(.off)
                .tabWidth(spaces).indentUsingSpaces(true)
        } else {
            CodeView(buffer: buffer, decorations: decorations).font(size: 12).showsLineNumbers(false).codeCaretBlink(.off)
        }
    }
    static func == (l: Card, r: Card) -> Bool { l.buffer === r.buffer && l.decorations === r.decorations && l.spaces == r.spaces }
}

/// A focused view of `text`; the decorations carry the tint theme.
@MainActor private func snippetWindow(_ text: String, spaces: Int? = nil, height: Float = 200)
    throws -> (TestWindow, CodeBuffer, CodeDecorations) {
    let buffer = CodeBuffer(text)
    let decorations = CodeDecorations(buffer: buffer)
    decorations.theme = theme()
    let w = try harnessWindow(size: sz(400, height)) {
        Card(buffer: buffer, decorations: decorations, spaces: spaces).equatable().frame(width: Pixels(400), height: Pixels(height))
    }
    w.click(at: pt(60, 6))
    buffer.selections = [CodeSelection(caret: 0)]
    w.window.setNeedsRedraw(); w.tick()
    return (w, buffer, decorations)
}

@MainActor private func redraw(_ w: TestWindow) { w.window.setNeedsRedraw(); w.tick() }
@MainActor private func tints(_ w: TestWindow) -> [MUIRect] { tintRects(w, alpha: tintAlpha) }
@MainActor private func slice(_ buffer: CodeBuffer, _ range: Range<Int>) -> String { buffer.snapshot().text(in: range) }

/// **1** Tab selects the next placeholder (every mirror of it), Shift-Tab the previous; reaching `$0` puts the
/// caret there and ends the session; the moves are selection writes, so the insertion is the one undo step.
/// **Mutation:** `.indent` not asking the session (Tab indents); `$0` not ending the session.
@Test @MainActor func tabAndShiftTabStepAndDollarZeroEnds() throws {
    let (w, buffer, _) = try snippetWindow("")
    let state = buffer.selectionState
    state.insertSnippet(CodeSnippet(parsing: "f(${1:a}, ${2:b}, ${1:a})$0!"), replacing: 0..<0)
    redraw(w)
    #expect(buffer.snapshot().text == "f(a, b, a)!")
    #expect(buffer.selections.map(\.range) == [2..<3, 8..<9])
    w.typeKey(.tab)
    #expect(buffer.selections.map(\.range) == [5..<6] && state.isSnippetActive, "\(buffer.selections)")
    w.typeKey(.tab, modifierFlags: .shift)
    #expect(buffer.selections.map(\.range) == [2..<3, 8..<9])
    w.typeText("Q")
    #expect(buffer.snapshot().text == "f(Q, b, Q)!", "the mirrors edit together: \(buffer.snapshot().text)")
    w.typeKey(.tab)
    w.typeKey(.tab)
    #expect(buffer.selections == [CodeSelection(caret: 10)] && !state.isSnippetActive, "$0 places the caret and ends: \(buffer.selections)")
    #expect(buffer.snapshot().text == "f(Q, b, Q)!", "Tab inserted nothing")
    w.typeKey(.tab)
    #expect(buffer.snapshot().text == "f(Q, b, Q)\t!", "with no session Tab indents again")
    state.undo(); state.undo()   // the indent, then the typing (one step per mirror pair)
    #expect(buffer.snapshot().text == "f(a, b, a)!", "the Tab moves were no undo steps: \(buffer.snapshot().text.debugDescription)")
    state.undo()
    #expect(buffer.snapshot().text == "", "the insertion is one step")
}

/// **2** Shift-Tab at the first placeholder is declined and outdents, keeping the session; at a later one it goes back.
/// **Mutation:** the previous-placeholder call answering `true` at the first stop (no outdent).
@Test @MainActor func shiftTabAtFirstFallsToOutdent() throws {
    let (w, buffer, _) = try snippetWindow("\t\n")
    let state = buffer.selectionState
    state.insertSnippet(CodeSnippet(parsing: "f(${1:a}, ${2:b})$0"), replacing: 1..<1)
    redraw(w)
    #expect(buffer.snapshot().text == "\tf(a, b)\n")
    w.typeKey(.tab, modifierFlags: .shift)
    #expect(buffer.snapshot().text == "f(a, b)\n", "outdented: \(buffer.snapshot().text.debugDescription)")
    #expect(state.isSnippetActive && buffer.selections.map(\.range) == [2..<3], "the session follows the outdent: \(buffer.selections)")
    w.typeKey(.tab)
    w.typeKey(.tab, modifierFlags: .shift)
    #expect(buffer.snapshot().text == "f(a, b)\n" && buffer.selections.map(\.range) == [2..<3], "from the second stop it goes back, no outdent")
}

/// **3** Escape ends the session and keeps the selections; the next Escape is the multi-caret collapse (`CV-BI`).
/// With one selection the first Escape still ends the session, and the second travels on.
/// **Mutation:** the session check removed from `.collapseSelections` (the first Escape collapses, the session lingers).
@Test @MainActor func escEndsThenSecondEscCollapses() throws {
    let (w, buffer, _) = try snippetWindow("")
    let state = buffer.selectionState
    state.insertSnippet(CodeSnippet(parsing: "<${1:a}|${1:a}>$0"), replacing: 0..<0)
    redraw(w)
    #expect(buffer.selections.count == 2)
    w.typeKey(.escape)
    #expect(!state.isSnippetActive && buffer.selections.count == 2, "the session ended, both selections kept")
    w.typeKey(.escape)
    #expect(buffer.selections.count == 1, "the second Escape collapses")
    // One selection: Escape ends the session and is claimed; the next one is not the view's.
    state.insertSnippet(CodeSnippet(parsing: "(${1:z})$0"), replacing: 0..<0)
    redraw(w)
    #expect(state.isSnippetActive && buffer.selections.count == 1)
    let before = buffer.snapshot().text
    w.typeKey(.escape)
    #expect(!state.isSnippetActive && buffer.snapshot().text == before)
}

/// **4** A press outside every placeholder ends the session; one inside keeps it.
/// **Mutation:** the check in `setSelections` removed.
@Test @MainActor func aPressOutsideEnds() throws {
    let (w, buffer, _) = try snippetWindow("\n\nsecond line\n")
    let state = buffer.selectionState
    state.insertSnippet(CodeSnippet(parsing: "f(${1:abcdef})$0"), replacing: 0..<0)
    redraw(w)
    #expect(state.isSnippetActive)
    let pitch = codePitch(scale: 1)
    w.click(at: pt(14, 6))   // inside the first row's `abcdef`
    #expect(state.isSnippetActive, "\(buffer.selections)")
    w.click(at: pt(14, 6 + 2 * pitch))   // the third row
    #expect(!state.isSnippetActive)
}

/// **5** The order of the keys: an `onKeyPress` that handles Tab or Escape wins over the session, the session ends
/// before the collapse (`CV-BI`) takes the key. **Mutation:** the snippet step moved ahead of `onKeyPress`
/// dispatch (Tab moves although the handler took it).
@Test @MainActor func theKeyOrderIsOnKeyPressThenSnippetThenCollapse() throws {
    nonisolated(unsafe) var seen: [String] = []
    nonisolated(unsafe) var consumes = true
    let buffer = CodeBuffer("")
    let decorations = CodeDecorations(buffer: buffer)
    let w = try harnessWindow(size: sz(400, 200)) {
        CodeView(buffer: buffer, decorations: decorations).font(size: 12).showsLineNumbers(false).codeCaretBlink(.off)
            .onKeyPress(keys: [.tab, .escape]) { press in
                seen.append(press.key == .tab ? "tab" : "esc")
                return consumes ? .handled : .ignored
            }
    }
    w.click(at: pt(60, 6))
    let state = buffer.selectionState
    state.insertSnippet(CodeSnippet(parsing: "f(${1:a}, ${2:b})$0"), replacing: 0..<0)
    redraw(w)
    w.typeKey(.tab)
    #expect(seen == ["tab"] && buffer.selections.map(\.range) == [2..<3] && state.isSnippetActive, "the handler took Tab: \(buffer.selections)")
    w.typeKey(.escape)
    #expect(state.isSnippetActive, "and Escape")
    consumes = false
    w.typeKey(.tab)
    #expect(buffer.selections.map(\.range) == [5..<6], "ignored: the session takes it")
    w.typeKey(.escape)
    #expect(!state.isSnippetActive && seen == ["tab", "esc", "tab", "esc"])
}

/// **6** A snippet inserted with no `indentUnit` takes the view's: its tab, or the `tabWidth` spaces of
/// `indentUsingSpaces`. **Mutation:** the plan not writing the unit (a tab is left in the text).
@Test @MainActor func theViewsIndentUnitIsUsedWhenNoneIsGiven() throws {
    let (w, buffer, _) = try snippetWindow("  ", spaces: 3)
    buffer.selectionState.insertSnippet(CodeSnippet(parsing: "{\n\t${1:x}\n}$0"), replacing: 2..<2)
    redraw(w)
    #expect(buffer.snapshot().text == "  {\n     x\n  }", "indent 2 + 3 spaces: \(buffer.snapshot().text.debugDescription)")
    let (w2, buffer2, _) = try snippetWindow("")
    buffer2.selectionState.insertSnippet(CodeSnippet(parsing: "{\n\t${1:x}\n}$0"), replacing: 0..<0)
    redraw(w2)
    #expect(buffer2.snapshot().text == "{\n\tx\n}", "a tab view keeps the tab")
    // An explicit unit wins over the view's.
    let (w3, buffer3, _) = try snippetWindow("", spaces: 3)
    buffer3.selectionState.insertSnippet(CodeSnippet(parsing: "{\n\t${1:x}\n}$0"), replacing: 0..<0, indentUnit: "--")
    redraw(w3)
    #expect(buffer3.snapshot().text == "{\n--x\n}")
}

/// **7** The non-current placeholders are tinted with ``CodeTheme/snippetPlaceholder``: the current one (the
/// selection) and `$0` are not, and ending the session removes the tint. **Mutation:** the current group tinted too
/// (3 rects, not 1); the tint read from another field.
@Test @MainActor func nonCurrentPlaceholdersAreTinted() throws {
    let (w, buffer, decorations) = try snippetWindow("")
    let state = buffer.selectionState
    #expect(tints(w).isEmpty)
    state.insertSnippet(CodeSnippet(parsing: "f(${1:aaa}, ${2:bbbb}, ${3:cc}) $0"), replacing: 0..<0)
    redraw(w)
    let pitch = codePitch(scale: 1)
    let first = tints(w)
    #expect(first.count == 2, "stops 2 and 3: \(first.map(\.bounds))")
    for r in first { #expect(r.bounds.size.height == pitch && r.bounds.size.width > 0 && r.bounds.origin.y == 0) }
    #expect(first[0].bounds.size.width > first[1].bounds.size.width, "bbbb is wider than cc")
    w.typeKey(.tab)
    let second = tints(w)
    #expect(second.count == 2 && second[0].bounds.size.width != first[0].bounds.size.width, "now stops 1 and 3: \(second.map(\.bounds))")
    w.typeKey(.escape)
    #expect(tints(w).isEmpty, "Escape ends the session and the tint")
    // A nil colour paints nothing.
    state.insertSnippet(CodeSnippet(parsing: "(${1:a} ${2:b})$0"), replacing: 0..<0)
    redraw(w)
    #expect(tints(w).count == 1)
    decorations.theme.snippetPlaceholder = nil
    redraw(w)
    #expect(tints(w).isEmpty)
}

/// **8** A placeholder across rows is tinted on each row it reaches. **Mutation:** the clamp to the row removed (a
/// rect is as wide as the whole placeholder) or the parent chain of the binary search dropped (a placeholder
/// that starts above the first row and runs into it is not tinted).
@Test @MainActor func aMultiRowPlaceholderIsTintedPerRow() throws {
    let (w, buffer, _) = try snippetWindow("")
    let state = buffer.selectionState
    state.insertSnippet(CodeSnippet(parsing: "${1:a}\n${2:one\ntwo\nthree}\n${3:z}$0"), replacing: 0..<0)
    redraw(w)
    let rects = tints(w)
    let pitch = codePitch(scale: 1)
    #expect(rects.map(\.bounds.origin.y).sorted() == [pitch, 2 * pitch, 3 * pitch, 4 * pitch], "stop 2 on rows 1-3, stop 3 on row 4: \(rects.map(\.bounds))")
}

/// **9** Ending the session by Escape (no selection change) still redraws: the view observes `isSnippetActive`.
/// **Mutation:** the plan reading `source.snippet` without the observed flag leaves the tint on.
@Test @MainActor func endingTheSessionRedraws() throws {
    let (w, buffer, _) = try snippetWindow("")
    buffer.selectionState.insertSnippet(CodeSnippet(parsing: "(${1:a} ${2:b})$0"), replacing: 0..<0)
    redraw(w)
    #expect(tints(w).count == 1)
    buffer.selectionState.endSnippet()
    w.tick()
    #expect(tints(w).isEmpty, "a plain tick, no explicit redraw request")
}

/// **10** Cost. A keystroke in a session costs what a keystroke over the same selection costs with no session
/// (literal on Apple platforms, per frame elsewhere), and a keystroke in a three-mirror session what three plain
/// carets cost. **Mutation:** a per-placeholder element in the paint or a retention taint (requests or ineligible move).
@Test @MainActor func aKeystrokeInASessionCostsAPlainKeystroke() async throws {
    func keystroke(session: Bool, mirrors: Int) async throws -> Cost {
        let (w, buffer, _) = try snippetWindow(codeText(lines: 60), height: 150)
        defer { withExtendedLifetime(w) {} }
        let state = buffer.selectionState
        if session {
            let stops = (0..<mirrors).map { _ in "${1:q}" }.joined(separator: "\n")
            state.insertSnippet(CodeSnippet(parsing: "\(stops)\n${2:other}$0"), replacing: 0..<0)
        } else {
            let snap = buffer.snapshot()
            buffer.selectionState.setSelections((0..<mirrors).map {
                let o = snap.offset(of: CodePoint(row: $0, column: 0))
                return CodeSelection(anchor: o, head: o + 1)
            }, primary: 0)
        }
        for _ in 0..<4 { redraw(w); try await w.runUntilIdle() }
        #expect(buffer.selections.count == mirrors)
        w.resetFrameWork()
        w.typeText("a")
        try await w.runUntilIdle()
        return Cost(totalWork(w), frames: w.frameWork.count)
    }
    let plainOne = try await keystroke(session: false, mirrors: 1), sessionOne = try await keystroke(session: true, mirrors: 1)
    let plainThree = try await keystroke(session: false, mirrors: 3), sessionThree = try await keystroke(session: true, mirrors: 3)
    #if canImport(Darwin)
    let literal = Cost(requests: 1, hits: 0, misses: 1, ineligible: 0, frames: 1)
    #expect(plainOne == literal, "plain \(plainOne)")
    #expect(sessionOne == literal, "session \(sessionOne)")
    #expect(sessionThree == plainThree, "three mirrors \(sessionThree) vs three carets \(plainThree)")
    #expect(plainThree == literal, "\(plainThree)")
    #else
    #expect(sessionOne.perFrameEquals(plainOne), "session \(sessionOne) vs plain \(plainOne)")
    #expect(sessionThree.perFrameEquals(plainThree), "three mirrors \(sessionThree) vs three carets \(plainThree)")
    #endif
}

/// **11** An idle view with a session running costs nothing: no frame, no request (the tint is a function of state).
/// **Mutation:** the paint noting a deadline or an animation for the session.
@Test @MainActor func anIdleViewInASessionCostsNothing() async throws {
    let (w, buffer, _) = try snippetWindow(codeText(lines: 60), height: 150)
    defer { withExtendedLifetime(w) {} }
    buffer.selectionState.insertSnippet(CodeSnippet(parsing: "${1:a} ${2:b} ${3:c}$0"), replacing: 0..<0)
    for _ in 0..<4 { redraw(w); try await w.runUntilIdle() }
    w.resetFrameWork()
    let frames = w.framesDrawn
    for _ in 0..<8 { w.advance(by: 0.25) }
    try await w.runUntilIdle()
    #expect(w.framesDrawn == frames && totalWork(w).elementRequests == 0 && !w.window.hasActiveAnimations)
}
