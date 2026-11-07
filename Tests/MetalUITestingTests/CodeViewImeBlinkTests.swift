import Testing
import Foundation
import MetalUI
import MetalUIPlatform
import MetalUIScene
import MetalUITesting

// IME and marked text, the caret blink, drag-select autoscroll and the gutter-bar callbacks of `CodeView`
// (rulings `CV-AA`..`CV-AD`, record 228 run 2). PLAIN imports; the harness text system and a simulated clock, so
// every number is the same on macOS, Linux and Windows. Pins count work (`FrameWork`, `framesDrawn`,
// `hasActiveAnimations`), never a clock.

@MainActor func glyphCount(_ window: TestWindow) -> Int { window.scene.glyphs.count }

// MARK: IME

/// 11.1 — marked text is the view's, not the buffer's (`CV-AA`): it is drawn at the caret (more glyphs, an
/// underline), the buffer's `version` and text do not move however the composition changes, only the caret's line is
/// shaped for it (one line, then none), the input method's area follows the marked text, and a commit through the
/// real path (`commitMarkedText(_:)`) inserts the candidate exactly once. **Mutation:** the commit inserting the
/// composition and then the committed text (twice); the composition written into the buffer.
@Test @MainActor func markedTextIsDrawnAtTheCaretAndNeverReachesTheBufferUntilItIsCommitted() throws {
    let (window, buffer) = try editingWindow("hello\nworld\n")
    caret(buffer, 0, 2)
    window.window.setNeedsRedraw(); window.tick()
    let version = buffer.version
    let glyphsBefore = glyphCount(window)
    let areaBefore = try #require(window.platformWindow.textInputAreas.last ?? nil)
    window.resetFrameWork()
    #expect(window.setMarkedText("かな"))
    #expect(buffer.version == version && buffer.snapshot().text == "hello\nworld\n", "marked text is not buffer text")
    #expect(window.markedText == "かな" && window.markedSelection == 2..<2)
    #expect(glyphCount(window) == glyphsBefore + 2, "drawn: \(glyphCount(window)) vs \(glyphsBefore)")
    #expect(totalWork(window).codeLinesShaped == 1, "only the caret's line was laid out again: \(totalWork(window).codeLinesShaped)")
    let areaAfter = try #require(window.platformWindow.textInputAreas.last ?? nil)
    #expect(areaAfter.origin.x > areaBefore.origin.x && areaAfter.origin.y == areaBefore.origin.y, "the input method's area follows the caret: \(areaBefore) -> \(areaAfter)")
    window.resetFrameWork()
    window.tick()
    #expect(totalWork(window).codeLinesShaped == 0, "a still composition shapes nothing")
    // The composition changes (a longer clause, the selection inside it): still not the buffer's.
    #expect(window.setMarkedText("かなかん", selectedRange: 0..<2))
    #expect(buffer.version == version && window.markedSelection == 0..<2)
    #expect(caretBars(window).count == 1, "the caret is drawn beside the marked text")
    #expect(window.commitMarkedText("仮名"))
    #expect(buffer.snapshot().text == "he仮名llo\nworld\n", "one insert: \(buffer.snapshot().text.debugDescription)")
    #expect(buffer.version == version + 1 && window.markedText == "" && window.window.testingComposition == nil)
    #expect(buffer.primarySelection == CodeSelection(caret: 2 + "仮名".utf8.count))
    // Committing the marked text as it stands (AppKit's `unmarkText`).
    #expect(window.setMarkedText("かな"))
    #expect(window.commitMarkedText())
    #expect(buffer.snapshot().text == "he仮名かなllo\nworld\n", Comment(rawValue: buffer.snapshot().text))
    #expect(buffer.version == version + 2)
}

/// 11.2 — cancelling leaves the text and the selection as they were, and a composition over a selection leaves it
/// to the commit, which replaces it. **Mutation:** cancel committing the marked text.
@Test @MainActor func cancellingACompositionChangesNothingAndACommitReplacesTheSelection() throws {
    let (window, buffer) = try editingWindow("hello\nworld\n")
    buffer.selections = [CodeSelection(anchor: 1, head: 4)]
    window.window.setNeedsRedraw(); window.tick()
    let version = buffer.version
    #expect(window.setMarkedText("ni"))
    #expect(window.cancelMarkedText())
    #expect(buffer.version == version && buffer.primarySelection == CodeSelection(anchor: 1, head: 4) && window.markedText == "")
    #expect(window.setMarkedText("ni"))
    #expect(buffer.version == version && buffer.primarySelection == CodeSelection(anchor: 1, head: 4), "the selection waits for the commit")
    #expect(window.commitMarkedText("你"))
    #expect(buffer.snapshot().text == "h你o\nworld\n")
}

/// 11.3 — a character the input method commits is not offered to `onKeyPress` (`KF-Q`: "an input method's
/// compositions ... are its own"), where the same character typed with no composition is. This is the arm the
/// session's `isComposing` feeds. **Mutation:** the typed-key-press stage asking a code target's `TextEditState`
/// (always empty) instead of the session: the committed `q` is swallowed and never typed.
@Test @MainActor func aCommittedCharacterOfAnInputMethodIsNotOfferedToOnKeyPress() throws {
    let buffer = CodeBuffer("hello\n")
    var offered = 0
    let window = try harnessWindow(size: sz(400, 200)) {
        CodeView(buffer: buffer, decorations: CodeDecorations(buffer: buffer)).font(size: 12)
            .onKeyPress("q") { offered += 1; return .handled }
    }
    window.click(at: pt(60, 6))
    buffer.selections = [CodeSelection(caret: 0)]
    window.window.setNeedsRedraw(); window.tick()
    window.typeText("q")
    #expect(offered == 1 && buffer.snapshot().text == "hello\n", "typed: offered and swallowed")
    #expect(window.setMarkedText("q"))
    #expect(window.commitMarkedText())
    #expect(offered == 1, "a composition's commit is not offered")
    #expect(buffer.snapshot().text == "qhello\n", Comment(rawValue: buffer.snapshot().text))
}

/// 11.4 — a composition does not survive its view losing focus (`IM-I`) or a press, and an edit that lands in the
/// buffer meanwhile moves it with the text. **Mutation:** `focusedElement.didSet` not dropping it.
@Test @MainActor func aCompositionEndsWithFocusAndAPressAndFollowsAnEditAbove() throws {
    let buffer = CodeBuffer("one\ntwo\nthree\n")
    let window = try harnessWindow(size: sz(400, 300)) {
        VStack(spacing: 0) {
            Box().frame(width: Pixels(20), height: Pixels(20)).focusable().id("other")
            CodeView(buffer: buffer, decorations: CodeDecorations(buffer: buffer)).font(size: 12)
                .frame(height: Pixels(200)).id("code")
        }
    }
    let other = try window.frame(ofID: "other")
    let codeTop = Float(try window.frame(ofID: "code").origin.y.value)
    window.click(at: pt(60, codeTop + 4))
    caret(buffer, 1, 1)
    window.window.setNeedsRedraw(); window.tick()
    #expect(window.setMarkedText("かな"))
    // An external edit above shifts the composition with the text, which is still not in the buffer.
    buffer.replace(0..<0, with: "zero\n", origin: .programmatic)
    window.window.setNeedsRedraw(); window.tick()
    #expect(window.markedText == "かな" && !buffer.snapshot().text.contains("かな"))
    #expect(window.commitMarkedText("X"))
    #expect(buffer.snapshot().text == "zero\none\ntXwo\nthree\n", Comment(rawValue: buffer.snapshot().text.debugDescription))
    // Focus lost.
    #expect(window.setMarkedText("かな"))
    window.click(at: pt(Float(other.origin.x.value) + 5, Float(other.origin.y.value) + 5))
    #expect(window.window.focusedElement != nil)
    window.click(at: pt(60, codeTop + 4))   // focus back: the composition did not come with it
    #expect(window.window.testingComposition == nil, "focus loss ended the composition")
    // A press.
    #expect(window.setMarkedText("かな"))
    window.click(at: pt(80, codeTop + 40))
    #expect(window.window.testingComposition == nil, "a press ended the composition")
    #expect(buffer.snapshot().text == "zero\none\ntXwo\nthree\n")
}

// MARK: Blink

/// A focused view of a few lines whose caret blinks (`CV-AC`).
@MainActor func blinkingWindow(_ blink: CodeCaretBlink = .on) throws -> (TestWindow, CodeBuffer) {
    let buffer = CodeBuffer("hello\nworld\n")
    let window = try harnessWindow(size: sz(400, 200)) {
        CodeView(buffer: buffer, decorations: CodeDecorations(buffer: buffer)).font(size: 12)
            .showsLineNumbers(false).codeCaretBlink(blink)
    }
    window.click(at: pt(60, 6))
    buffer.selections = [CodeSelection(caret: 0)]
    window.window.setNeedsRedraw(); window.tick()
    return (window, buffer)
}

/// 12.1 — the caret is a function of the frame's time since it last moved: drawn for the first half second, hidden
/// for the next, and typing restarts it; its frames come from the timeline store's one wake (a deadline at each
/// toggle), so a focused, idle view draws exactly two frames a second and **never notes an active animation**
/// (`hasActiveAnimations` stays false: the display link stays asleep). **Mutation:** the blink calling
/// `noteActiveAnimation()` (60 frames a second and `hasActiveAnimations`); no deadline (the caret never turns off).
@Test @MainActor func theCaretBlinksTwiceASecondFromTheOneWakeAndNeverKeepsTheLinkRunning() throws {
    let (window, _) = try blinkingWindow()
    #expect(caretBars(window).count == 1, "drawn at the start")
    let frames = window.framesDrawn
    var shown: [Int] = []
    for _ in 0..<8 {   // two seconds in quarter-second ticks
        window.advance(by: 0.25)
        shown.append(caretBars(window).count)
        #expect(!window.window.hasActiveAnimations, "the blink keeps no display link running")
    }
    #expect(window.framesDrawn - frames == 4, "two frames a second: \(window.framesDrawn - frames) in two seconds")
    #expect(shown == [1, 0, 0, 1, 1, 0, 0, 1], "on 0.5 s, off 0.5 s: \(shown)")
}

/// 12.2 — typing restarts the blink (the caret is solid right after a key), and `.codeCaretBlink(.off)` is a solid
/// caret that costs no frames at all. **Mutation:** the epoch not restarting on an edit.
@Test @MainActor func typingRestartsTheBlinkAndOffIsSolidAndFree() throws {
    let (window, _) = try blinkingWindow()
    window.advance(by: 0.5)
    #expect(caretBars(window).count == 0, "in the off half")
    window.typeText("a")
    #expect(caretBars(window).count == 1, "a keystroke shows the caret")
    window.advance(by: 0.5)
    #expect(caretBars(window).count == 0)
    let (steady, _) = try blinkingWindow(.off)
    let frames = steady.framesDrawn
    for _ in 0..<8 {
        steady.advance(by: 0.25)
        #expect(caretBars(steady).count == 1)
    }
    #expect(steady.framesDrawn == frames, "a solid caret draws no frame by itself")
}

// MARK: Autoscroll

/// A 400 x 200 view of 400 lines whose scroll the test reads.
@MainActor func autoscrollWindow() throws -> (TestWindow, CodeBuffer, CodeScrollState) {
    let buffer = CodeBuffer(codeText(lines: 400))
    let state = CodeScrollState()
    let window = try harnessWindow(size: sz(400, 300)) {
        VStack(spacing: 0) {
            CodeView(buffer: buffer, decorations: CodeDecorations(buffer: buffer)).font(size: 12).showsLineNumbers(false)
                .codeCaretBlink(.off).scrollState(state).frame(height: Pixels(200)).id("code")
            Box().frame(width: Pixels(20), height: Pixels(20))
        }
    }
    return (window, buffer, state)
}

@MainActor func mouseEvent(_ window: TestWindow, _ x: Float, _ y: Float) -> MouseEvent {
    MouseEvent(position: pt(x, y), modifiers: [], clickCount: 1, buttonNumber: 0, timestamp: window.now)
}

/// 13.1 — a drag held below the view scrolls it by the frame's time and extends the selection with it (`CV-AD`):
/// the offset after one second is the same whether the frames came 60 or 4 a second (a function of the timestamp,
/// not a step per frame), the selection's head is on the last visible row, and the release makes it the buffer's.
/// **Mutation:** the offset taken as a step per frame (the two cadences differ).
@Test @MainActor func aDragHeldBelowTheViewScrollsByTheFrameTimeAndSelectsAlong() throws {
    var rows: [Double] = []
    for cadence in [60, 4] {
        let (window, buffer, state) = try autoscrollWindow()
        let top = Float(try window.frame(ofID: "code").origin.y.value)
        window.click(at: pt(60, top + 6)); window.window.setNeedsRedraw(); window.tick()
        buffer.selections = [CodeSelection(caret: 0)]
        _ = window.send(.mouseDown(mouseEvent(window, 60, top + 6)))
        window.tick()
        _ = window.send(.mouseDragged(mouseEvent(window, 60, top + 220)))   // 20 points below the view
        for _ in 0..<cadence {
            window.advance(by: 1.0 / Double(cadence))
        }
        rows.append(state.position.row)
        let live = buffer.snapshot().point(at: buffer.primarySelection.head).row
        _ = window.send(.mouseUp(mouseEvent(window, 60, top + 220)))
        window.tick()
        let folded = buffer.snapshot().point(at: buffer.primarySelection.head).row
        #expect(buffer.snapshot().point(at: buffer.primarySelection.anchor).row == 0 && folded > 10, "released: the selection reaches row \(folded) (while held: \(live))")
        let first = Int(state.position.row)
        #expect(folded >= first + 8 && folded <= first + 14, "the head is on a visible row: head \(folded), top \(first)")
    }
    #expect(rows[0] > 20 && abs(rows[0] - rows[1]) <= 1.0, "after a second: \(rows)")
}

/// 13.2 — at the end of the text the autoscroll rests: no frames are requested while the view cannot move, and
/// the view stays where it is once the pointer comes back inside. **Mutation:** `noteActiveAnimation()` called
/// with the view at its limit.
@Test @MainActor func anAutoscrollAtTheLimitRestsAndTheViewStopsWhenThePointerReturns() throws {
    let buffer = CodeBuffer(codeText(lines: 30))
    let state = CodeScrollState()
    let window = try harnessWindow(size: sz(400, 300)) {
        VStack(spacing: 0) {
            CodeView(buffer: buffer, decorations: CodeDecorations(buffer: buffer)).font(size: 12).showsLineNumbers(false)
                .codeCaretBlink(.off).scrollState(state).frame(height: Pixels(200)).id("code")
            Box().frame(width: Pixels(20), height: Pixels(20))
        }
    }
    let top = Float(try window.frame(ofID: "code").origin.y.value)
    window.click(at: pt(60, top + 6)); window.tick()
    _ = window.send(.mouseDown(mouseEvent(window, 60, top + 6)))
    window.tick()
    _ = window.send(.mouseDragged(mouseEvent(window, 60, top + 260)))
    for _ in 0..<40 { window.advance(by: 0.1) }
    let end = state.position.row
    #expect(end > 0)
    #expect(!window.window.hasActiveAnimations, "at the end of the text the view rests")
    let frames = window.framesDrawn
    for _ in 0..<10 { window.advance(by: 0.1) }
    #expect(window.framesDrawn == frames && state.position.row == end, "no frame while it cannot move")
    _ = window.send(.mouseDragged(mouseEvent(window, 60, top + 100)))   // back inside
    window.advance(by: 0.5)
    #expect(state.position.row == end, "the pointer is inside again: the view stays where it is")
    #expect(!window.window.hasActiveAnimations)
    _ = window.send(.mouseUp(mouseEvent(window, 60, top + 100)))
}

// MARK: Gutter bars

/// A view of 40 lines with a tagged line decoration (rows 10..<20, bar), a bar-less tint (rows 25..<28), and a tagged
/// virtual row (two removed lines before row 5, bar) in a window with gutter numbers.
@MainActor func gutterFixture(clicks: Cell<[CodeGutterHit]>, menus: Cell<[CodeGutterHit]>) throws -> (TestWindow, CodeBuffer) {
    let buffer = CodeBuffer(codeText(lines: 40))
    let decorations = CodeDecorations(buffer: buffer)
    decorations.setLineDecorations([
        CodeLineDecoration(lines: 10..<20, gutterBar: .red, background: nil, tag: 7),
        CodeLineDecoration(lines: 25..<28, background: .green, tag: 8),
    ], asOf: buffer.version)
    decorations.setVirtualRows([
        CodeVirtualRow(anchor: .before(line: 5), lines: ["removed one", "removed two"], gutterBar: .blue, tag: 9),
    ], asOf: buffer.version)
    let window = try harnessWindow(size: sz(400, 600)) {
        CodeView(buffer: buffer, decorations: decorations).font(size: 12).codeCaretBlink(.off)
            .onGutterBarClick { clicks.value.append($0) }
            .gutterBarContextMenu { hit in
                Button("Revert \(hit.tag ?? 0)") { menus.value.append(hit) }
            }
    }
    return (window, buffer)
}

/// A mutable cell for closures in a test.
@MainActor final class Cell<Value> {
    var value: Value
    init(_ value: Value) { self.value = value }
}

/// The gutter bars as drawn: x of their middle and the vertical middle of each, top to bottom.
@MainActor func gutterBars(_ window: TestWindow) -> [(x: Float, y: Float)] {
    var bars: [(x: Float, y: Float)] = []
    for rect in window.scene.rects where rect.bounds.size.width == 3 {
        let top = rect.bounds.origin.y, height = rect.bounds.size.height
        bars.append((x: rect.bounds.origin.x + 1, y: top + height / 2))
    }
    return bars.sorted { $0.y < $1.y }
}

/// 14.1 — a press on a gutter bar reports the bar's hit and does nothing else (`CV-AB`): for a line decoration the
/// whole row range of the bar, its tag and `.lineDecoration`; for a virtual row (the removed lines of a diff, where
/// Revert lives) its anchor line as a one-line range, its tag and `.virtualRow`. The range follows an edit inside it.
/// A press in the gutter where there is no bar, or only a tint, still selects the line. **Mutation:** the hit
/// test skipping virtual rows (the removed lines cannot be reverted); the press selecting the line too.
@Test @MainActor func aPressOnAGutterBarReportsItsHitAndABarlessGutterRowKeepsLineSelect() throws {
    let clicks = Cell<[CodeGutterHit]>([]), menus = Cell<[CodeGutterHit]>([])
    let (window, buffer) = try gutterFixture(clicks: clicks, menus: menus)
    let pitch = codePitch(scale: 1)
    let bars = gutterBars(window)
    #expect(bars.count == 2, "a bar for the virtual row and one for the decoration: \(bars)")
    let x = bars[0].x
    buffer.selections = [CodeSelection(caret: 0)]
    // The virtual row's bar (display rows 5 and 6).
    window.click(at: pt(x, 5.5 * pitch))
    #expect(clicks.value == [CodeGutterHit(lines: 5..<6, tag: 9, source: .virtualRow, displayRow: 5)], "\(clicks.value)")
    window.click(at: pt(x, 6.5 * pitch))
    #expect(clicks.value.last == CodeGutterHit(lines: 5..<6, tag: 9, source: .virtualRow, displayRow: 6))
    #expect(buffer.primarySelection == CodeSelection(caret: 0), "a bar press neither moves the caret nor selects")
    // The decoration's bar: buffer row 12 sits at display row 14.
    window.click(at: pt(x, 14.5 * pitch))
    #expect(clicks.value.last == CodeGutterHit(lines: 10..<20, tag: 7, source: .lineDecoration, displayRow: 14), "\(clicks.value.last as Any)")
    // An edit inside the range splits the stored run; the hit is still the whole bar.
    let at = buffer.snapshot().offset(of: CodePoint(row: 15, column: 0))
    buffer.replace(at..<at, with: "new\n", origin: .programmatic)
    window.window.setNeedsRedraw(); window.tick()
    window.click(at: pt(x, 14.5 * pitch))
    #expect(clicks.value.last?.lines == 10..<21 && clicks.value.last?.tag == 7, "\(clicks.value.last as Any)")
    // No bar: line select as before. Row 3 (display 3) has nothing; rows 26 (display 29 after the insert) only a tint.
    let count = clicks.value.count
    window.click(at: pt(x, 3.5 * pitch))
    #expect(clicks.value.count == count, "no bar, no callback")
    #expect(buffer.snapshot().text(in: buffer.primarySelection.range) == buffer.snapshot().line(3) + "\n", "line select: \(buffer.primarySelection)")
    window.click(at: pt(x, 29.5 * pitch))
    #expect(clicks.value.count == count, "a tint without a bar is not a hit")
    #expect(buffer.primarySelection.range.count > 0 && buffer.snapshot().point(at: buffer.primarySelection.head).row >= 25)
}

/// 14.2 — a secondary press on a bar opens the menu the app built for its hit, on the real menu path, and an item
/// runs in input; a secondary press anywhere else opens nothing. **Mutation:** the menu built with the first
/// hit of the frame (the virtual row's tag for the decoration's bar).
@Test @MainActor func aContextMenuOnAGutterBarPresentsTheItemsOfItsHit() throws {
    let clicks = Cell<[CodeGutterHit]>([]), menus = Cell<[CodeGutterHit]>([])
    let (window, _) = try gutterFixture(clicks: clicks, menus: menus)
    let pitch = codePitch(scale: 1)
    let x = try #require(gutterBars(window).first).x
    window.rightClick(at: pt(x, 5.5 * pitch))
    #expect(window.presentedMenu?.items.map(\.title) == ["Revert 9"], "\(window.presentedMenu?.items.map(\.title) as Any)")
    try window.chooseMenuItem("Revert 9")
    #expect(menus.value == [CodeGutterHit(lines: 5..<6, tag: 9, source: .virtualRow, displayRow: 5)])
    window.rightClick(at: pt(x, 14.5 * pitch))
    #expect(window.presentedMenu?.items.map(\.title) == ["Revert 7"])
    try window.dismissMenu()
    window.rightClick(at: pt(200, 8.5 * pitch))
    #expect(window.presentedMenu == nil, "off a bar: no menu")
    window.rightClick(at: pt(x, 3.5 * pitch))
    #expect(window.presentedMenu == nil, "a bar-less gutter row: no menu")
    #expect(clicks.value.isEmpty, "a secondary press is not a click")
}
