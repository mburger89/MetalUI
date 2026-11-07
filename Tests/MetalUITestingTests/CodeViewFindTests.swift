import Testing
import Foundation
import MetalUI
import MetalUIScene
import MetalUITesting

// Find in `CodeView` (rulings `CV-AE`, record 229): the matches the app's find bar found, painted as a background
// layer and stepped with ⌘G / ⇧⌘G. PLAIN imports; the harness text system. Perf pins count work
// (`FrameWork.codeFindMatchesVisited`, `RopeStats`), never a clock.

private extension Double { var log2Ceiling: Double { Foundation.log2(self).rounded(.up) } }

private let findAlpha: Float = 0.31
private let currentAlpha: Float = 0.43
private let lineAlpha: Float = 0.27

/// A theme whose find colours are told apart by alpha alone.
@MainActor private func findTheme() -> CodeTheme {
    var theme = CodeTheme()
    theme.findMatch = Color(red: 1, green: 1, blue: 0).opacity(Double(findAlpha))
    theme.currentFindMatch = Color(red: 1, green: 0.5, blue: 0).opacity(Double(currentAlpha))
    return theme
}

@MainActor private func findWindow(_ text: String, height: Float = 200, numbers: Bool = false)
    throws -> (TestWindow, CodeBuffer, CodeDecorations) {
    let buffer = CodeBuffer(text)
    let decorations = CodeDecorations(buffer: buffer)
    decorations.theme = findTheme()
    let window = try codeWindow(buffer: buffer, decorations: decorations, height: height, numbers: numbers)
    window.click(at: pt(60, 6))
    buffer.selections = [CodeSelection(caret: 0)]
    window.window.setNeedsRedraw(); window.tick()
    return (window, buffer, decorations)
}

@MainActor private func redraw(_ window: TestWindow) { window.window.setNeedsRedraw(); window.tick() }

@MainActor private func matchRects(_ window: TestWindow) -> [MUIRect] { tintRects(window, alpha: findAlpha) }
@MainActor private func currentRects(_ window: TestWindow) -> [MUIRect] { tintRects(window, alpha: currentAlpha) }

/// 9.1 — every match is a background rect behind its row's text, the current one in its own colour, and nothing
/// is painted for a view with no matches. The rect is one row tall and as wide as the match.
/// **Mutation:** the current index ignored in paint draws every match in the plain colour; the painting loop
/// removed draws none.
@Test @MainActor func matchesPaintInTheirColoursAndTheCurrentOneApart() throws {
    let (window, buffer, decorations) = try findWindow("foo bar foo\nbaz foo\nnone\n")
    #expect(matchRects(window).isEmpty && currentRects(window).isEmpty)
    let matches = buffer.snapshot().ranges(of: "foo")
    #expect(matches.count == 3)
    decorations.findMatches = matches
    decorations.currentMatch = 1
    redraw(window)
    let pitch = codePitch(scale: 1)
    let plain = matchRects(window), current = currentRects(window)
    try #require(plain.count == 2, "two plain matches: \(plain.map(\.bounds))")
    try #require(current.count == 1, "one current match: \(current.map(\.bounds))")
    for rect in plain + current { #expect(rect.bounds.size.height == pitch && rect.bounds.size.width > 0) }
    #expect(current[0].bounds.origin.y == 0, "the current match (index 1) is the second foo of the first row")
    #expect(plain.map(\.bounds.origin.y).sorted() == [0, pitch], "the others: the first foo of row 0 and the one of row 1")
    #expect(current[0].bounds.origin.x > plain.filter { $0.bounds.origin.y == 0 }[0].bounds.origin.x)
    decorations.findMatches = []
    redraw(window)
    #expect(matchRects(window).isEmpty && currentRects(window).isEmpty, "no matches, no rects")
}

/// 9.2 — matches follow the buffer's edits: a line inserted above shifts them (and their rects) down a row, an edit
/// that touches a match drops it, and `currentMatch` follows its match or becomes `nil` when that one is dropped.
/// **Mutation:** the mapping removed leaves the matches at their old offsets (stale coordinates) and the rects on
/// the old rows, over other text.
@Test @MainActor func matchesShiftWithAnEditAboveAndDropWhenTouched() throws {
    let (window, buffer, decorations) = try findWindow("one foo\ntwo foo\nthree foo\n")
    decorations.findMatches = buffer.snapshot().ranges(of: "foo")
    decorations.currentMatch = 2
    redraw(window)
    let pitch = codePitch(scale: 1)
    #expect(matchRects(window).map(\.bounds.origin.y).sorted() == [0, pitch])
    buffer.replace(0..<0, with: "zero\n")
    redraw(window)
    #expect(matchRects(window).map(\.bounds.origin.y).sorted() == [pitch, 2 * pitch], "shifted down one row: \(matchRects(window).map(\.bounds))")
    #expect(currentRects(window).map(\.bounds.origin.y) == [3 * pitch])
    for match in decorations.findMatches { #expect(buffer.snapshot().text(in: match) == "foo", "every match still names foo") }
    #expect(decorations.currentMatch == 2)
    // An edit inside the second match drops it; the current one (the third) becomes index 1.
    let second = decorations.findMatches[1]
    buffer.replace((second.lowerBound + 1)..<(second.lowerBound + 2), with: "0")
    #expect(decorations.findMatches.count == 2 && decorations.currentMatch == 1)
    for match in decorations.findMatches { #expect(buffer.snapshot().text(in: match) == "foo") }
    // An edit that removes the current match leaves no current.
    let last = decorations.findMatches[1]
    buffer.replace((last.lowerBound - 1)..<last.upperBound, with: "")
    #expect(decorations.findMatches.count == 1 && decorations.currentMatch == nil)
    // Typing at a match's edges keeps it: after its end, and before its start (which shifts it).
    let only = decorations.findMatches[0]
    buffer.replace(only.upperBound..<only.upperBound, with: "!")
    #expect(decorations.findMatches == [only])
    buffer.replace(only.lowerBound..<only.lowerBound, with: "??")
    #expect(decorations.findMatches == [(only.lowerBound + 2)..<(only.upperBound + 2)])
    #expect(buffer.snapshot().text(in: decorations.findMatches[0]) == "foo")
}

/// 9.3 — ⌘G (⌃G off Apple) selects the next match and ⇧⌘G the previous, both wrapping; from a caret between
/// matches it takes the next one after it; the selection is the match and `currentMatch` is its index.
/// **Mutations:** no wrap (index clamped) fails the last-to-first step; the direction flipped fails the first
/// forward step.
@Test @MainActor func nextAndPreviousStepWithWrap() throws {
    let (window, buffer, decorations) = try findWindow("x foo foo foo y\n")
    let matches = buffer.snapshot().ranges(of: "foo")
    #expect(matches.count == 3)
    decorations.findMatches = matches
    window.typeKey("g", modifierFlags: codePrimary)
    #expect(buffer.primarySelection.range == matches[0] && decorations.currentMatch == 0, "from the caret at 0 to the first")
    window.typeKey("g", modifierFlags: codePrimary)
    #expect(buffer.primarySelection.range == matches[1] && decorations.currentMatch == 1)
    window.typeKey("g", modifierFlags: codePrimary)
    window.typeKey("g", modifierFlags: codePrimary)
    #expect(buffer.primarySelection.range == matches[0] && decorations.currentMatch == 0, "wrapped from the last to the first")
    window.typeKey("g", modifierFlags: [codePrimary, .shift])
    #expect(buffer.primarySelection.range == matches[2] && decorations.currentMatch == 2, "backwards from the first wraps to the last")
    window.typeKey("g", modifierFlags: [codePrimary, .shift])
    #expect(buffer.primarySelection.range == matches[1])
    // From a caret between two matches (not on one): the next after it, the previous before it.
    buffer.selections = [CodeSelection(caret: matches[1].upperBound)]
    decorations.currentMatch = nil
    window.typeKey("g", modifierFlags: codePrimary)
    #expect(buffer.primarySelection.range == matches[2])
    buffer.selections = [CodeSelection(caret: matches[1].upperBound)]
    window.typeKey("g", modifierFlags: [codePrimary, .shift])
    #expect(buffer.primarySelection.range == matches[1], "previous from a caret at a match's end is that match")
    // A caret inside a match steps past it.
    buffer.selections = [CodeSelection(caret: matches[0].lowerBound + 1)]
    decorations.currentMatch = nil
    window.typeKey("g", modifierFlags: codePrimary)
    #expect(buffer.primarySelection.range == matches[1])
}

/// 9.4 — with no matches the key is not claimed (an app's own ⌘G still sees it), and a read-only view steps too.
/// **Mutation:** claiming the key with no matches swallows the app's handler.
@Test @MainActor func theKeyIsClaimedOnlyWhileMatchesExist() throws {
    let buffer = CodeBuffer("a foo b foo\n")
    let decorations = CodeDecorations(buffer: buffer)
    var seen = 0
    let window = try harnessWindow(size: sz(400, 200)) {
        CodeView(buffer: buffer, decorations: decorations).font(size: 12).codeViewEditable(false)
            .onKey { _ in seen += 1; return true }
    }
    window.click(at: pt(60, 6))
    window.typeKey("g", modifierFlags: codePrimary)
    #expect(buffer.primarySelection.isEmpty && seen == 1, "nothing to step to: the key travelled on to the app's handler")
    decorations.findMatches = buffer.snapshot().ranges(of: "foo")
    window.typeKey("g", modifierFlags: codePrimary)
    #expect(buffer.snapshot().ranges(of: "foo").contains(buffer.primarySelection.range), "a read-only view steps: \(buffer.primarySelection.range)")
    #expect(seen == 1, "with matches the view claims the key: the app's handler did not see it again")
}

/// 9.5 — stepping to a match far outside the viewport centres its row in the very next frame (`CV-V`), in a view
/// of 1 000 lines, from the top and from far below.
/// **Mutation:** the reveal left out (`select(_:reveal: false)`) leaves the match off screen after the frame.
@Test @MainActor func steppingCentresAMatchBeyondTheViewportInOneFrame() throws {
    let buffer = CodeBuffer(codeText(lines: 1000))
    let decorations = CodeDecorations(buffer: buffer)
    decorations.theme = findTheme()
    let window = try codeWindow(buffer: buffer, decorations: decorations)
    window.click(at: pt(60, 6))
    buffer.selections = [CodeSelection(caret: 0)]
    redraw(window)
    decorations.findMatches = buffer.snapshot().ranges(of: "let value21 ") + buffer.snapshot().ranges(of: "let value700 ")
    let ordered = decorations.findMatches
    #expect(ordered.count == 2)
    let pitch = codePitch(scale: 1)
    let middle = (200 - pitch) / 2
    window.resetFrameWork()
    window.typeKey("g", modifierFlags: codePrimary)   // one key, one frame
    #expect(window.frameWork.count == 1, "one frame: \(window.frameWork.count)")
    var current = try #require(currentRects(window).first, "the current match is on screen after the one frame")
    #expect(abs(current.bounds.origin.y - middle) <= pitch, "row 21 centred: y \(current.bounds.origin.y), middle \(middle)")
    #expect(buffer.primarySelection.range == ordered[0])
    window.typeKey("g", modifierFlags: codePrimary)
    current = try #require(currentRects(window).first)
    #expect(abs(current.bounds.origin.y - middle) <= pitch, "row 700, far below, centred: \(current.bounds.origin.y)")
    #expect(buffer.primarySelection.range == ordered[1])
    window.typeKey("g", modifierFlags: codePrimary)
    current = try #require(currentRects(window).first)
    #expect(abs(current.bounds.origin.y - middle) <= pitch, "wrapped back up to row 21, centred: \(current.bounds.origin.y)")
}

/// 9.6 — a view of 10 000 matches looks at the matches of its shown rows only: the count is a few per row plus a
/// logarithm, far below 10 000, and it does not grow with the matches' number beyond that logarithm. A warm
/// frame, a scroll frame and an unchanged-matches redraw never scan the buffer (`RopeStats` does not move).
/// **Red before:** painting every match visits 10 000. **Mutation:** the span lookup replaced by a loop over all
/// matches.
@Test(arguments: [1_000, 10_000]) @MainActor func manyMatchesPaintOnlyTheVisibleOnes(lines: Int) throws {
    var text = ""
    text.reserveCapacity(lines * 24)
    for i in 0..<lines { text += "let foo\(i) = \(i)\n" }
    let buffer = CodeBuffer(text)
    let decorations = CodeDecorations(buffer: buffer)
    decorations.theme = findTheme()
    let window = try codeWindow(buffer: buffer, decorations: decorations)
    decorations.findMatches = buffer.snapshot().ranges(of: "foo")
    #expect(decorations.findMatches.count == lines)
    decorations.currentMatch = lines / 2
    window.resetFrameWork()
    redraw(window)
    let first = totalWork(window)
    let visible = Int((200 / codePitch(scale: 1)).rounded(.up)) + 1
    let bound = visible * (Int(Double(lines).log2Ceiling) + 3)   // rows x (log2 m + the row's own matches)
    #expect(first.codeFindMatchesVisited > 0)
    #expect(first.codeFindMatchesVisited <= bound, "\(lines) matches: visited \(first.codeFindMatchesVisited) (bound \(bound))")
    #expect(matchRects(window).count + currentRects(window).count <= visible, "painted \(matchRects(window).count) of \(lines)")
    #expect(matchRects(window).count >= visible - 2, "the shown rows' matches are painted")
    window.resetFrameWork()
    window.scroll(at: pt(60, 60), byDeltaX: 0, deltaY: -40)
    redraw(window)
    let scroll = totalWork(window)
    #expect(scroll.codeFindMatchesVisited <= 2 * bound, "a scroll: visited \(scroll.codeFindMatchesVisited)")
}

/// 9.7 — find work is O(n) per query and none per frame: one `ranges(of:)` visits rope nodes in proportion to the
/// text (10 times the text, about 10 times the nodes), and a frame painting 10 000 matches visits exactly the rope
/// nodes the same frame visits with no matches at all (the find adds none; it never re-runs the search).
/// **Mutation:** a view that re-ran the search per frame (`ranges(of:)` in the plan) moves `RopeStats` by a query
/// per frame.
@Test @MainActor func findWorkIsLinearPerQueryAndZeroPerFrame() throws {
    func measure(lines: Int) throws -> (query: Int, withMatches: Int, without: Int) {
        var text = ""
        for i in 0..<lines { text += "let foo\(i) = \(i)\n" }
        let buffer = CodeBuffer(text)
        let decorations = CodeDecorations(buffer: buffer)
        decorations.theme = findTheme()
        let window = try codeWindow(buffer: buffer, decorations: decorations)
        func frameNodes() -> Int {
            redraw(window)   // warm
            let before = RopeStats.nodesVisited
            redraw(window)
            redraw(window)
            return RopeStats.nodesVisited - before
        }
        let without = frameNodes()
        let snap = buffer.snapshot()
        let before = RopeStats.nodesVisited
        let matches = snap.ranges(of: "foo")
        let query = RopeStats.nodesVisited - before
        decorations.findMatches = matches
        decorations.currentMatch = lines / 2
        window.resetFrameWork()
        let withMatches = frameNodes()
        #expect(totalWork(window).codeFindMatchesVisited > 0 && matches.count == lines)
        return (query, withMatches, without)
    }
    let small = try measure(lines: 1_000), large = try measure(lines: 10_000)
    #expect(small.query > 0, "the query visits rope nodes")
    #expect(large.query >= 5 * small.query && large.query <= 20 * small.query, "linear: \(small.query) at 1k, \(large.query) at 10k")
    #expect(small.withMatches == small.without && large.withMatches == large.without,
            "a frame with matches visits the nodes a frame without them does: \(small), \(large)")
}

/// 9.8 — the current-line highlight: off by default, on with `CodeTheme.currentLine`, on the caret's row only,
/// and absent while a range is selected.
/// **Mutation:** painting it for a selection, or for every row, changes the count.
@Test @MainActor func theCurrentLineIsOffByDefaultAndFollowsTheCaret() throws {
    let buffer = CodeBuffer("one\ntwo\nthree\n")
    let decorations = CodeDecorations(buffer: buffer)
    #expect(decorations.theme.currentLine == nil)
    let window = try codeWindow(buffer: buffer, decorations: decorations, numbers: false)
    window.click(at: pt(60, 6))
    let pitch = codePitch(scale: 1)
    buffer.selections = [CodeSelection(caret: 5)]
    redraw(window)
    #expect(tintRects(window, alpha: lineAlpha).isEmpty)
    decorations.theme.currentLine = Color(red: 0, green: 0, blue: 1).opacity(Double(lineAlpha))
    redraw(window)
    let rects = tintRects(window, alpha: lineAlpha)
    #expect(rects.count == 1 && rects[0].bounds.origin.y == pitch && rects[0].bounds.size.height == pitch, "\(rects.map(\.bounds))")
    #expect(rects[0].bounds.size.width == 400)
    buffer.selections = [CodeSelection(caret: 10)]
    redraw(window)
    #expect(tintRects(window, alpha: lineAlpha).map(\.bounds.origin.y) == [2 * pitch])
    buffer.selections = [CodeSelection(anchor: 4, head: 7)]
    redraw(window)
    #expect(tintRects(window, alpha: lineAlpha).isEmpty, "none while text is selected")
}
