import Testing
import Foundation
import Observation
import MetalUI
import MetalUIScene
import MetalUITesting

// Per-view selections of `CodeView` (`CV-AY`, `CV-AZ`, record 329): `selectionState(_:)` over the 's
// `CodeSelectionState` (record 327). PLAIN imports; the harness text system; every pin counts work or reads state,
// never a clock. Two views of one buffer side by side in a 400 x 200 window: A is the left 200, B the right.

@MainActor private func viewOf(_ buffer: CodeBuffer, _ decorations: CodeDecorations, state: CodeSelectionState?,
                               scroll: CodeScrollState? = nil, geometry: CodeViewGeometry? = nil) -> CodeView {
    var view = CodeView(buffer: buffer, decorations: decorations).font(size: 12).showsLineNumbers(false).codeCaretBlink(.off)
    if let state { view = view.selectionState(state) }
    if let scroll { view = view.scrollState(scroll) }
    if let geometry { view = view.geometry(geometry) }
    return view
}

/// Two views of one buffer, each with its own selection state, scroll state and geometry unless said otherwise.
@MainActor private final class Split {
    let buffer: CodeBuffer
    let decoA: CodeDecorations, decoB: CodeDecorations
    let stateA: CodeSelectionState, stateB: CodeSelectionState
    let scrollA = CodeScrollState(), scrollB = CodeScrollState()
    let geometryA = CodeViewGeometry(), geometryB = CodeViewGeometry()
    let window: TestWindow
    let pitch = codePitch(scale: 1)

    init(_ text: String, statelessB: Bool = false) throws {
        let buffer = CodeBuffer(text)
        let decoA = CodeDecorations(buffer: buffer), decoB = CodeDecorations(buffer: buffer)
        let stateA = CodeSelectionState(buffer: buffer), stateB = CodeSelectionState(buffer: buffer)
        let scrollA = self.scrollA, scrollB = self.scrollB, geometryA = self.geometryA, geometryB = self.geometryB
        self.buffer = buffer; self.decoA = decoA; self.decoB = decoB; self.stateA = stateA; self.stateB = stateB
        window = try harnessWindow(size: sz(400, 200)) {
            HStack(spacing: 0) {
                viewOf(buffer, decoA, state: stateA, scroll: scrollA, geometry: geometryA)
                viewOf(buffer, decoB, state: statelessB ? nil : stateB, scroll: scrollB, geometry: geometryB)
            }
        }
        window.window.setNeedsRedraw(); window.tick()
    }

    /// A press in the first row of A (`b == false`) or B, at `row`.
    func click(_ b: Bool, row: Int = 0, x: Float = 60) {
        window.click(at: pt((b ? 200 : 0) + x, 6 + Float(row) * pitch))
    }
    func frame() { window.window.setNeedsRedraw(); window.tick() }
    func offset(row: Int, column: Int = 0) -> Int { buffer.snapshot().offset(of: CodePoint(row: row, column: column)) }
    func row(of offset: Int) -> Int { buffer.snapshot().point(at: offset).row }
}

private let threeLines = "hello\nworld\nthird\n"

/// **1** Two views each keep their own caret: a press in A and a press in B land in their own state and leave the
/// buffer's default state alone. **Mutation:** the session writing `buffer.selections` (the default state) leaves both
/// states at 0.
@Test @MainActor func twoViewsKeepTheirOwnCarets() throws {
    let s = try Split(threeLines)
    s.click(false, row: 0)
    s.click(true, row: 2)
    #expect(s.row(of: s.stateA.primarySelection.head) == 0 && s.stateA.primarySelection.head > 0, "A: \(s.stateA.primarySelection)")
    #expect(s.row(of: s.stateB.primarySelection.head) == 2, "B: \(s.stateB.primarySelection)")
    #expect(s.buffer.primarySelection == CodeSelection(caret: 0), "the default state is untouched")
    s.click(false, row: 1)
    #expect(s.row(of: s.stateA.primarySelection.head) == 1 && s.row(of: s.stateB.primarySelection.head) == 2, "B did not follow A's press")
}

/// **2** Typing in A moves B's caret and not B's scroll: B is scrolled to row 400 with its caret off screen at row
/// 450; A types a character; B's caret moves one byte and B stays at row 400. **Mutation:** a plan that reveals the
/// caret on every version change (`revealsCaret` forced true) scrolls B to its caret.
@Test @MainActor func typingInAMovesBsCaretNotBsScroll() throws {
    let s = try Split(codeText(lines: 1000))
    s.click(false)
    s.scrollB.position = CodeScrollPosition(row: 400)
    s.stateB.selections = [CodeSelection(caret: s.offset(row: 450, column: 2))]
    s.frame(); s.frame()
    #expect(s.scrollB.position.row == 400)
    let before = s.stateB.primarySelection.head
    s.window.typeText("x")
    s.frame()
    #expect(s.stateB.primarySelection.head == before + 1, "B's caret followed the text: \(before) -> \(s.stateB.primarySelection.head)")
    #expect(s.scrollB.position.row == 400, "B did not scroll: \(s.scrollB.position.row)")
    #expect(s.row(of: s.stateA.primarySelection.head) == 0 && s.stateA.primarySelection.head > 0)
}

/// **3** A view with no state follows the buffer: a press in it moves `buffer.selections`, typing in it edits at the
/// buffer's caret, and A (own state) is moved over the text only. **Mutation:** a stateless view reading a state of
/// its own leaves `buffer.primarySelection` at 0.
@Test @MainActor func aViewWithoutAStateFollowsTheBuffer() throws {
    let s = try Split(threeLines, statelessB: true)
    s.click(false, row: 0, x: 80)
    let a = s.stateA.primarySelection.head
    s.click(true, row: 2)
    #expect(s.row(of: s.buffer.primarySelection.head) == 2, "B's press is the buffer's: \(s.buffer.primarySelection)")
    #expect(s.stateA.primarySelection.head == a)
    s.window.typeText("Q")
    #expect(s.buffer.snapshot().text.contains("Qthird") || s.buffer.snapshot().text.contains("Q"), "\(s.buffer.snapshot().text)")
    #expect(s.stateA.primarySelection.head == a, "A's caret is on row 0, before the edit")
    s.buffer.select(s.offset(row: 1)..<s.offset(row: 1), reveal: false)
    #expect(s.buffer.primarySelection.head == s.offset(row: 1))
}

/// **4** `select(_:reveal: true)` on a state centres the line in the views using that state only. A is at row 500's
/// centre, B stays at the top. **Mutation:** the plan reading `buffer.revealSerial` (the default state's) scrolls
/// neither; reading every state's scrolls both.
@Test @MainActor func revealCentresOnlyTheViewsOfThatState() throws {
    let s = try Split(codeText(lines: 1000))
    s.frame()
    let at = s.offset(row: 500)
    s.stateA.select(at..<at, reveal: true)
    s.frame(); s.frame()
    #expect(s.scrollA.position.row > 480 && s.scrollA.position.row < 500, "A centred: \(s.scrollA.position.row)")
    #expect(s.scrollB.position.row == 0, "B untouched: \(s.scrollB.position.row)")
    let later = s.offset(row: 800)
    s.stateB.select(later..<later, reveal: true)
    s.frame(); s.frame()
    #expect(s.scrollB.position.row > 780 && s.scrollA.position.row < 500)
}

@MainActor @Observable private final class StateHolder {
    var state: CodeSelectionState
    init(_ state: CodeSelectionState) { self.state = state }
}

/// **5** Giving a view another state reveals nothing, even when that state has a pending reveal the old one did not:
/// the view stays where it is, and the new state's next `select` reveals as usual. **Mutation:** dropping the
/// reveal-source comparison (`revealSource == sourceID`) scrolls the view to the new state's earlier reveal.
@Test @MainActor func swappingAViewsStateRevealsNothing() throws {
    let buffer = CodeBuffer(codeText(lines: 1000))
    let deco = CodeDecorations(buffer: buffer)
    let first = CodeSelectionState(buffer: buffer), second = CodeSelectionState(buffer: buffer)
    let holder = StateHolder(first)
    let scroll = CodeScrollState()
    let window = try harnessWindow(size: sz(400, 200)) { viewOf(buffer, deco, state: holder.state, scroll: scroll) }
    window.window.setNeedsRedraw(); window.tick()
    let at = buffer.snapshot().offset(of: CodePoint(row: 500, column: 0))
    second.select(at..<at, reveal: true)   // a reveal the view's first state never had
    holder.state = second
    for _ in 0..<3 { window.window.setNeedsRedraw(); window.tick() }
    #expect(scroll.position.row == 0, "swapping scrolled to \(scroll.position.row)")
    let later = buffer.snapshot().offset(of: CodePoint(row: 700, column: 0))
    second.select(later..<later, reveal: true)
    for _ in 0..<3 { window.window.setNeedsRedraw(); window.tick() }
    #expect(scroll.position.row > 680, "the new state reveals: \(scroll.position.row)")
}

/// **6** Copy, cut and paste use the focused view's own selection. **Mutation:** copy reading the buffer's selection
/// copies the default state's (a whole line); cut or paste through the buffer edits the wrong place.
@Test @MainActor func copyCutAndPasteUseTheFocusedViewsSelection() throws {
    let s = try Split(threeLines)
    s.click(false)
    s.stateA.selections = [CodeSelection(anchor: 0, head: 5)]
    s.stateB.selections = [CodeSelection(anchor: 6, head: 11)]
    s.window.typeKey("c", modifierFlags: codePrimary)
    #expect(s.window.platformWindow.clipboard == "hello", "A copies its own: \(String(describing: s.window.platformWindow.clipboard))")
    #expect(s.window.clipboardRepresentations.last.map { String(decoding: $0.bytes, as: UTF8.self) } == "hello", "the copy handler too")
    // A view with an empty selection copies its line, not another state's selection (the default state's here).
    s.buffer.selections = [CodeSelection(anchor: 0, head: 5)]
    s.stateA.selections = [CodeSelection(caret: 8)]
    s.window.typeKey("c", modifierFlags: codePrimary)
    #expect(s.window.platformWindow.clipboard == "world\n", "A's empty selection copies its line: \(String(describing: s.window.platformWindow.clipboard))")
    s.buffer.selections = [CodeSelection(caret: 0)]
    s.click(true)
    s.stateA.selections = [CodeSelection(anchor: 0, head: 5)]
    s.stateB.selections = [CodeSelection(anchor: 6, head: 11)]
    s.window.typeKey("c", modifierFlags: codePrimary)
    #expect(s.window.platformWindow.clipboard == "world", "B copies its own: \(String(describing: s.window.platformWindow.clipboard))")
    s.window.typeKey("x", modifierFlags: codePrimary)
    #expect(s.buffer.snapshot().text == "hello\n\nthird\n" && s.window.platformWindow.clipboard == "world")
    #expect(s.stateA.primarySelection == CodeSelection(anchor: 0, head: 5), "A's range is before the cut")
    #expect(s.stateB.primarySelection == CodeSelection(caret: 6))
    s.click(false)
    s.stateA.selections = [CodeSelection(anchor: 0, head: 5)]
    s.window.setClipboard(text: "BYE")
    s.window.typeKey("v", modifierFlags: codePrimary)
    #expect(s.buffer.snapshot().text == "BYE\n\nthird\n", "\(s.buffer.snapshot().text)")
    #expect(s.stateA.primarySelection == CodeSelection(caret: 3))
    #expect(s.stateB.primarySelection == CodeSelection(caret: 4), "B followed the text: \(s.stateB.primarySelection)")
}

/// **7** ⌘G steps from the stepping view's own caret and centres only that view. **Mutation:** the session selecting
/// through the buffer (default state) centres neither view and leaves B's state where it was.
@Test @MainActor func findStepsAndCentresOnlyInTheSteppingView() throws {
    var text = codeText(lines: 1000)
    let first = text.range(of: "line 301")!.lowerBound
    text.replaceSubrange(first..<text.index(first, offsetBy: 8), with: "foo 301 ")
    let s = try Split(text)
    let matches = s.buffer.snapshot().ranges(of: "foo 301")
    #expect(matches.count == 1)
    s.decoA.findMatches = matches; s.decoB.findMatches = matches
    s.click(true)
    s.window.typeKey("g", modifierFlags: codePrimary)
    s.frame(); s.frame()
    #expect(s.stateB.primarySelection.range == matches[0], "B selected the match: \(s.stateB.primarySelection)")
    #expect(s.scrollB.position.row > 280 && s.scrollB.position.row < 300, "B centred: \(s.scrollB.position.row)")
    #expect(s.scrollA.position.row == 0, "A did not scroll: \(s.scrollA.position.row)")
    #expect(s.row(of: s.stateA.primarySelection.head) == 0 && s.stateA.primarySelection.isEmpty, "A's caret did not move")
}

/// **8** ⌘Z in B after A's typing brings B's caret to the change and A follows the text (`CV-AX`, Alloy's answer 3).
/// **Mutation:** the session calling `buffer.undo()` writes the step's selection into the default state, so B's
/// caret stays where it was.
@Test @MainActor func undoInTheOtherViewBringsItsCaretToTheChange() throws {
    let s = try Split(threeLines)
    s.click(false, row: 0, x: 80)
    let start = s.stateA.primarySelection.head
    s.window.typeText("xy")
    #expect(s.buffer.snapshot().text.hasPrefix("hel") && s.buffer.snapshot().text.count == threeLines.count + 2)
    s.click(true, row: 2)
    #expect(s.row(of: s.stateB.primarySelection.head) == 2)
    s.window.typeKey("z", modifierFlags: codePrimary)
    #expect(s.buffer.snapshot().text == threeLines, "\(s.buffer.snapshot().text)")
    #expect(s.stateB.primarySelection == CodeSelection(caret: start), "B is at the change: \(s.stateB.primarySelection) vs \(start)")
    #expect(s.stateA.primarySelection == CodeSelection(caret: start), "A followed the text: \(s.stateA.primarySelection)")
}

/// **9** Marked text in B ends, committed in place, when another state edits, whether the edit is away from the mark or
/// at it (`CV-AZ`): the composed text lands where B's caret then is, B's composition is gone, and A's own edit stands.
/// **Mutation:** dropping the handler registration keeps the composition and the buffer without the text; committing
/// at the old offset puts the text in front of A's insertion.
@Test @MainActor func aForeignEditEndsAndCommitsAMarkedTextInPlace() throws {
    for atTheMark in [false, true] {
        let s = try Split(threeLines)
        s.click(true, row: 1)
        s.stateB.selections = [CodeSelection(caret: 8)]
        #expect(s.window.setMarkedText("かな"))
        #expect(s.window.markedText == "かな" && s.buffer.snapshot().text == threeLines)
        let at = atTheMark ? 8 : 0
        s.stateA.replace(at..<at, with: "Q")
        #expect(s.window.markedText == "", "the composition ended (at the mark: \(atTheMark))")
        let expected = atTheMark ? "hello\nwoQかなrld\nthird\n" : "Qhello\nwoかなrld\nthird\n"
        #expect(s.buffer.snapshot().text == expected, "committed in place: \(s.buffer.snapshot().text.debugDescription)")
        #expect(s.stateB.primarySelection == CodeSelection(caret: 15), "B's caret is after the commit: \(s.stateB.primarySelection)")
        s.frame()
        #expect(s.window.markedText == "")
    }
}

/// **10** A caret-anchored overlay follows the view's own state: A's and B's caret rectangles are those of their own
/// carets and an arrow key in A moves only A's. **Mutation:** the plan taking the head from the buffer puts both
/// rectangles at the default state's caret.
@Test @MainActor func theCaretRectangleFollowsTheViewsState() throws {
    let s = try Split(threeLines)
    s.stateA.selections = [CodeSelection(caret: s.offset(row: 0, column: 3))]
    s.stateB.selections = [CodeSelection(caret: s.offset(row: 2, column: 1))]
    s.frame(); s.frame()
    let a = try #require(s.geometryA.caretRect()), b = try #require(s.geometryB.caretRect())
    #expect(a.origin.y.value < b.origin.y.value && a.origin.x.value > b.origin.x.value, "A \(a), B \(b)")
    s.click(false, row: 0, x: 80)
    s.window.typeKey(.rightArrow)
    s.frame()
    let moved = try #require(s.geometryA.caretRect())
    #expect(moved.origin.x.value > a.origin.x.value || moved.origin.y.value != a.origin.y.value)
    #expect(try #require(s.geometryB.caretRect()) == b, "B's caret rectangle did not move")
}

// MARK: Steady-frame cost and observation

private struct Card: Component, @MainActor Equatable {
    let buffer: CodeBuffer
    let decorations: CodeDecorations
    let state: CodeSelectionState?
    var content: some ElementGroup { viewOf(buffer, decorations, state: state) }
    static func == (l: Card, r: Card) -> Bool { l.buffer === r.buffer && l.decorations === r.decorations && l.state === r.state }
}

private struct Steady: Equatable { var requests = 0, hits = 0, misses = 0, ineligible = 0 }

/// One steady frame of `views` retained code views beside a focusable box (so the focus seat is not a code view).
@MainActor private func steady(views: Int, states: Bool) throws -> Steady {
    let buffer = CodeBuffer(codeText(lines: 60))
    let decorations = (0..<views).map { _ in CodeDecorations(buffer: buffer) }
    let owned = (0..<views).map { _ in CodeSelectionState(buffer: buffer) }
    let w = try harnessWindow(size: sz(400, 200)) {
        HStack(spacing: 0) {
            Box().frame(width: Pixels(20), height: Pixels(20)).focusable()
            ForEach(0..<views, id: \.self) { i in
                Card(buffer: buffer, decorations: decorations[i], state: states ? owned[i] : nil).equatable()
                    .frame(width: Pixels(180), height: Pixels(150))
            }
        }
    }
    for _ in 0..<4 { w.window.setNeedsRedraw(); w.tick() }
    w.resetFrameWork()
    w.window.setNeedsRedraw(); w.tick()
    let f = totalWork(w)
    return Steady(requests: f.elementRequests, hits: f.retainedHits, misses: f.retainedMisses, ineligible: f.retainedIneligible)
}

/// **11** A steady frame costs the same element requests, retention hits, misses and ineligible with and without
/// `selectionState(_:)`, and the same as master f7badefc (literals measured there). **Mutation:** wrapping the view
/// in a modifier element when a state is given adds a request per view.
@Test @MainActor func aSteadyFrameCostsNothingMoreWithOrWithoutAState() throws {
    let one = try steady(views: 1, states: false), oneState = try steady(views: 1, states: true)
    let two = try steady(views: 2, states: false), twoStates = try steady(views: 2, states: true)
    #expect(one == Steady(requests: 4, hits: 0, misses: 1, ineligible: 0), "\(one)")
    #expect(two == Steady(requests: 5, hits: 1, misses: 1, ineligible: 0), "\(two)")
    #expect(oneState == one, "with a state: \(oneState)")
    #expect(twoStates == two, "with states: \(twoStates)")
}

/// **12** A caret move in A replans A only: with a state each, the retained card of B hits and A's misses; sharing the
/// buffer's default state, both miss (the caret is shared). **Mutation:** `selectionSource` ignoring the
/// view's state (always the default one) makes the first arm two misses.
@Test @MainActor func anArrowKeyInOneViewDoesNotReplanTheOther() throws {
    func run(states: Bool) throws -> (hits: Int, misses: Int) {
        let buffer = CodeBuffer(codeText(lines: 60))
        let da = CodeDecorations(buffer: buffer), db = CodeDecorations(buffer: buffer)
        let sa = CodeSelectionState(buffer: buffer), sb = CodeSelectionState(buffer: buffer)
        let w = try harnessWindow(size: sz(400, 200)) {
            HStack(spacing: 0) {
                Card(buffer: buffer, decorations: da, state: states ? sa : nil).equatable().frame(width: Pixels(200), height: Pixels(150))
                Card(buffer: buffer, decorations: db, state: states ? sb : nil).equatable().frame(width: Pixels(200), height: Pixels(150))
            }
        }
        w.click(at: pt(60, 6))
        for _ in 0..<4 { w.window.setNeedsRedraw(); w.tick() }
        w.resetFrameWork()
        w.typeKey(.rightArrow)
        let f = totalWork(w)
        return (f.retainedHits, f.retainedMisses)
    }
    let own = try run(states: true), shared = try run(states: false)
    #expect(own.misses == 1 && own.hits == 1, "own states: A replans, B hits: \(own)")
    #expect(shared.misses == 2 && shared.hits == 0, "the shared default caret wakes both: \(shared)")
}
