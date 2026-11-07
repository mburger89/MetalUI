import Testing
import Foundation
import MetalUI
import MetalUIScene
import MetalUITesting

// Editing in `CodeView` (rulings `CV-W`..`CV-Z`, record 228 run 1): the window's session seam, keys, clipboard,
// caret. PLAIN imports; the harness text system, so every number is the same on macOS, Linux and Windows. The
// keys use the host platform's conventions (`codePrimary`, `codeWord`); `CodeEditingKeysTests` runs the key
// table for both. Perf pins count work (`FrameWork`, `RopeStats`), never a clock.

#if os(macOS)
let codeWord: EventModifiers = .option
#else
let codeWord: EventModifiers = .control
#endif

/// A focused, editable view of `text`, the caret at the start.
@MainActor func editingWindow(_ text: String, height: Float = 200, numbers: Bool = false) throws -> (TestWindow, CodeBuffer) {
    let buffer = CodeBuffer(text)
    let window = try codeWindow(buffer: buffer, decorations: CodeDecorations(buffer: buffer), height: height, numbers: numbers)
    window.click(at: pt(60, 6))
    buffer.selections = [CodeSelection(caret: 0)]
    window.window.setNeedsRedraw(); window.tick()
    return (window, buffer)
}

@MainActor func caret(_ buffer: CodeBuffer, _ row: Int, _ column: Int) {
    buffer.selections = [CodeSelection(caret: buffer.snapshot().offset(of: CodePoint(row: row, column: column)))]
}

@MainActor func head(_ buffer: CodeBuffer) -> CodePoint { buffer.snapshot().point(at: buffer.primarySelection.head) }

/// The one-point-wide bars the height of a row: the caret.
@MainActor func caretBars(_ window: TestWindow) -> [MUIRect] {
    let pitch = codePitch(scale: 1)
    return window.scene.rects.filter { $0.bounds.size.width == 1 && $0.bounds.size.height == pitch }
}

// MARK: Typing and the seam

/// 8.1 — typing reaches the buffer through the window's text stage: `.textInput` is a `replaceSelections`, the
/// caret follows, a selection is replaced, and the caret is drawn (a bar the height of the pitch).
/// **Mutation:** the `.textInput` early branch removed sends the text to `TextEditing` over a `TextEditState`
/// the code view does not own, so the buffer stays unchanged.
@Test @MainActor func typingEditsTheBufferAndTheCaretFollows() throws {
    let (window, buffer) = try editingWindow("hello\nworld\n")
    window.typeText("ab")
    #expect(buffer.snapshot().text == "abhello\nworld\n")
    #expect(buffer.primarySelection == CodeSelection(caret: 2))
    #expect(caretBars(window).count == 1, "one caret bar: \(window.scene.rects.map(\.bounds))")
    buffer.selections = [CodeSelection(anchor: 2, head: 5)]
    window.typeText("X")
    #expect(buffer.snapshot().text == "abXlo\nworld\n", "typing over a selection replaces it")
    #expect(buffer.primarySelection == CodeSelection(caret: 3))
}

/// 8.2 — a read-only view (`codeViewEditable(false)`, or a read-only buffer) selects, moves its caret and copies,
/// and changes nothing: typed text, delete, Return, paste and cut leave the buffer, and Tab still moves focus.
/// **Mutation:** `isEditable` ignoring the view flag (or `buffer.isReadOnly`) lets the keys edit.
@Test @MainActor func aReadOnlyViewSelectsAndCopiesButDoesNotEdit() throws {
    for viaBuffer in [false, true] {
        let buffer = CodeBuffer("hello\nworld\n")
        buffer.isReadOnly = viaBuffer
        let window = try harnessWindow(size: sz(400, 200)) {
            VStack(spacing: 0) {
                CodeView(buffer: buffer, decorations: CodeDecorations(buffer: buffer)).font(size: 12)
                    .codeViewEditable(viaBuffer ? true : false).frame(height: Pixels(100))
                Box().frame(width: Pixels(20), height: Pixels(20)).focusable().id("next")
            }
        }
        window.click(at: pt(60, 6))
        let focusedBefore = window.window.focusedElement
        window.typeText("zz")
        window.typeKey(.delete)
        window.typeKey(.return)
        window.setClipboard(text: "pasted")
        window.typeKey("v", modifierFlags: codePrimary)
        window.typeKey("x", modifierFlags: codePrimary)
        #expect(buffer.snapshot().text == "hello\nworld\n", "read-only (buffer flag \(viaBuffer)): \(buffer.snapshot().text.debugDescription)")
        buffer.selections = [CodeSelection(anchor: 0, head: 5)]
        window.setClipboard(text: "")
        window.typeKey("c", modifierFlags: codePrimary)
        #expect(window.platformWindow.clipboard == "hello", "a read-only view copies")
        window.typeKey(.rightArrow)
        #expect(buffer.primarySelection == CodeSelection(caret: 5), "and moves its caret")
        window.typeKey(.tab)
        #expect(buffer.snapshot().text == "hello\nworld\n", "Tab does not insert")
        #expect(window.window.focusedElement != focusedBefore, "Tab moved focus on")
    }
}

// MARK: Keys

/// 8.3 — arrows move by grapheme (a ZWJ family is one step), across line breaks (CRLF is one), with the selection
/// collapsing to its edge, and shift extends.
/// **Mutation:** stepping one scalar instead of one grapheme stops inside the family; a CRLF counted as two steps
/// parks the caret between `\r` and `\n`.
@Test @MainActor func arrowsMoveByGraphemeAndAcrossBreaks() throws {
    let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"
    let (window, buffer) = try editingWindow("a\(family)b\r\nline two\n")
    window.typeKey(.rightArrow)
    #expect(head(buffer) == CodePoint(row: 0, column: 1))
    window.typeKey(.rightArrow)
    #expect(head(buffer) == CodePoint(row: 0, column: 1 + family.utf8.count), "the family is one step")
    window.typeKey(.rightArrow)
    window.typeKey(.rightArrow)
    #expect(head(buffer) == CodePoint(row: 1, column: 0), "right at the end of a CRLF line goes to the next row")
    window.typeKey(.leftArrow)
    #expect(head(buffer) == CodePoint(row: 0, column: 2 + family.utf8.count), "left at column 0 goes to the previous row's end")
    window.typeKey(.leftArrow, modifierFlags: .shift)
    #expect(buffer.primarySelection.range.count == 1 && buffer.primarySelection.head < buffer.primarySelection.anchor)
    window.typeKey(.rightArrow)
    #expect(buffer.primarySelection.isEmpty, "an arrow with a selection collapses it")
    #expect(head(buffer) == CodePoint(row: 0, column: 2 + family.utf8.count), "to the selection's right edge")
}

/// 8.4 — word motion uses `TextEditing`'s word characters on the line: it skips a run of symbols and then a word,
/// stops at the line's ends and crosses to the next row from them.
/// **Mutation:** word motion stepping by grapheme, or by whitespace only, moves `foo_bar` and `(x)` differently.
@Test @MainActor func wordMotionUsesTheTextEditingPredicates() throws {
    let (window, buffer) = try editingWindow("foo_bar  (x) baz\nsecond\n")
    window.typeKey(.rightArrow, modifierFlags: codeWord)
    #expect(head(buffer).column == 7, "after foo_bar: \(head(buffer))")
    window.typeKey(.rightArrow, modifierFlags: codeWord)
    #expect(head(buffer).column == 11, "over the spaces and the paren, then x: \(head(buffer))")
    window.typeKey(.leftArrow, modifierFlags: codeWord)
    #expect(head(buffer).column == 10, "before x: \(head(buffer))")
    window.typeKey(.leftArrow, modifierFlags: codeWord)
    #expect(head(buffer).column == 0)
    window.typeKey(.rightArrow, modifierFlags: [codeWord, .shift])
    #expect(buffer.primarySelection.range == 0..<7)
    caret(buffer, 0, 16)
    window.typeKey(.rightArrow, modifierFlags: codeWord)
    #expect(head(buffer) == CodePoint(row: 1, column: 0), "from the line's end to the next row")
}

/// 8.5 — smart Home goes to the first non-blank and then to column 0; End goes to the line's end; the document
/// keys go to the ends; shift extends each.
/// **Mutation:** Home always going to column 0 never visits the first non-blank.
@Test @MainActor func smartHomeAndTheLineAndDocumentEnds() throws {
    let (window, buffer) = try editingWindow("first\n    indented text\nlast")
    caret(buffer, 1, 9)
    window.typeKey(.home)
    #expect(head(buffer) == CodePoint(row: 1, column: 4), "first non-blank")
    window.typeKey(.home)
    #expect(head(buffer) == CodePoint(row: 1, column: 0), "then column 0")
    window.typeKey(.home)
    #expect(head(buffer) == CodePoint(row: 1, column: 4), "and back")
    window.typeKey(.end)
    #expect(head(buffer) == CodePoint(row: 1, column: 17))
    window.typeKey(.end, modifierFlags: codePrimary)
    #expect(head(buffer) == CodePoint(row: 2, column: 4), "document end")
    window.typeKey(.home, modifierFlags: [codePrimary, .shift])
    #expect(buffer.primarySelection.range == 0..<buffer.snapshot().offset(of: CodePoint(row: 2, column: 4))
            && buffer.primarySelection.head == 0, "selected to the start")
}

/// 8.6 — vertical motion keeps the column across a short line (the remembered x), starts a new memory after any
/// other key, and goes to the document ends past the first and last rows.
/// **Mutation:** dropping `goalX` leaves the caret at the short line's column after the second Down.
@Test @MainActor func verticalMotionRemembersItsColumn() throws {
    let (window, buffer) = try editingWindow("abcdefghij\nab\nabcdefghij\n")
    caret(buffer, 0, 8)
    window.typeKey(.downArrow)
    #expect(head(buffer) == CodePoint(row: 1, column: 2), "clamped to the short line")
    window.typeKey(.downArrow)
    #expect(head(buffer) == CodePoint(row: 2, column: 8), "the remembered column is back: \(head(buffer))")
    window.typeKey(.upArrow)
    window.typeKey(.leftArrow)
    window.typeKey(.downArrow)
    #expect(head(buffer).row == 2 && head(buffer).column <= 2, "a horizontal move forgets it: \(head(buffer))")
    caret(buffer, 0, 3)
    window.typeKey(.upArrow)
    #expect(buffer.primarySelection == CodeSelection(caret: 0), "up from the first row goes to the start")
    buffer.selections = [CodeSelection(caret: buffer.utf8Count - 1)]
    window.typeKey(.downArrow); window.typeKey(.downArrow)
    #expect(buffer.primarySelection.head == buffer.utf8Count)
}

/// 8.7 — page keys move the caret by the visible rows less one and scroll to keep it in view.
/// **Mutation:** a page of one row (or a page that does not reveal) moves the caret one row, or leaves it off screen.
@Test @MainActor func pageKeysMoveTheCaretAndTheView() throws {
    let (window, buffer) = try editingWindow(codeText(lines: 500))
    let pitch = codePitch(scale: 1)
    let visible = Int((200 / pitch).rounded(.down))
    window.typeKey(.pageDown)
    #expect(head(buffer).row == visible - 1, "a page is the visible rows less one: \(head(buffer).row) vs \(visible - 1)")
    for _ in 0..<3 { window.typeKey(.pageDown) }
    let row = head(buffer).row
    #expect(row == 4 * (visible - 1))
    let bar = try #require(caretBars(window).first, "the caret is drawn, so its row is in the view")
    #expect(bar.bounds.origin.y >= 0 && bar.bounds.origin.y + pitch <= 200 + 0.5, "caret at y \(bar.bounds.origin.y)")
    window.typeKey(.pageUp)
    #expect(head(buffer).row == row - (visible - 1))
}

/// 8.8 — delete keys: backspace and forward delete by grapheme (a family is one), at a line's ends they remove the
/// break (CRLF whole), word deletes remove a word, a selection is deleted whole, and consecutive backspaces are
/// one undo step.
/// **Mutation:** backspace removing one scalar leaves a broken family; one byte of a CRLF leaves a lone `\r`.
@Test @MainActor func deleteKeysRemoveGraphemesBreaksWordsAndSelections() throws {
    let family = "\u{1F468}\u{200D}\u{1F469}"
    let (window, buffer) = try editingWindow("ab\(family)\r\ncd efg hij\n")
    caret(buffer, 0, 2 + family.utf8.count)
    window.typeKey(.delete)
    #expect(buffer.snapshot().line(0) == "ab", "the family went whole")
    window.typeKey(.deleteForward)
    #expect(buffer.snapshot().text == "abcd efg hij\n", "forward delete at the end removed the CRLF whole")
    caret(buffer, 0, 9)
    window.typeKey(.delete, modifierFlags: codeWord)
    #expect(buffer.snapshot().line(0) == "abcd hij", "word delete takes the space and efg: \(buffer.snapshot().line(0).debugDescription)")
    buffer.selections = [CodeSelection(anchor: 1, head: 3)]
    window.typeKey(.delete)
    #expect(buffer.snapshot().line(0) == "ad hij")
    caret(buffer, 0, 6)
    for _ in 0..<3 { window.typeKey(.delete) }
    #expect(buffer.snapshot().line(0) == "ad ")
    buffer.undo()
    #expect(buffer.snapshot().line(0) == "ad hij", "three backspaces are one undo step")
}

/// 8.9 — Return inserts the buffer's own line ending and the previous line's leading whitespace (up to the
/// caret), replaces a selection, and is its own undo step.
/// **Mutation:** a fixed `"\n"` breaks a CRLF file; the indent taken from the whole line copies text past the caret.
@Test @MainActor func returnKeepsTheLineEndingAndTheIndentation() throws {
    for ending in ["\n", "\r\n"] {
        let (window, buffer) = try editingWindow("    foo()\(ending)tail\(ending)")
        #expect(buffer.lineEnding.text == ending)
        caret(buffer, 0, 9)
        window.typeKey(.return)
        #expect(buffer.snapshot().text == "    foo()\(ending)    \(ending)tail\(ending)", "ending \(ending.debugDescription)")
        #expect(head(buffer) == CodePoint(row: 1, column: 4))
        caret(buffer, 0, 2)
        window.typeKey(.return)
        #expect(buffer.snapshot().line(0) == "  " && buffer.snapshot().line(1) == "    foo()",
                "the copied indent stops at the caret: \(buffer.snapshot().text.debugDescription)")
        buffer.undo()
        #expect(buffer.snapshot().line(0) == "    foo()", "Return undoes alone")
    }
}

/// 8.10 — Tab inserts a tab (or spaces to the next stop), indents every selected line, ⇧Tab outdents; Tab with
/// the platform's shortcut modifier is not consumed.
/// **Mutation:** indenting only the first line, or outdenting more than one unit.
@Test @MainActor func tabIndentsAndShiftTabOutdents() throws {
    let (window, buffer) = try editingWindow("one\n  two\n\nthree\n")
    window.typeKey(.tab)
    #expect(buffer.snapshot().line(0) == "\tone", "a tab at the caret")
    buffer.selections = [CodeSelection(anchor: 1, head: buffer.snapshot().offset(of: CodePoint(row: 3, column: 2)))]
    window.typeKey(.tab)
    #expect(buffer.snapshot().text == "\t\tone\n\t  two\n\n\tthree\n",
            "lines 0...3 indented, the blank one left alone: \(buffer.snapshot().text.debugDescription)")
    #expect(buffer.primarySelection.range.lowerBound == 2, "the selection start stays on the same character")
    window.typeKey(.tab, modifierFlags: .shift)
    #expect(buffer.snapshot().text == "\tone\n  two\n\nthree\n", "one unit removed from each")
    window.typeKey(.tab, modifierFlags: .shift)
    #expect(buffer.snapshot().text == "one\n  two\n\nthree\n".replacingOccurrences(of: "  two", with: "two"), "the second removes a tab and two spaces")
    let before = buffer.snapshot().text
    window.typeKey(.tab, modifierFlags: codePrimary)
    #expect(buffer.snapshot().text == before, "Tab with the shortcut modifier is not an indent")
}

/// 8.11 — with spaces: Tab pads to the next multiple of the tab width, counting a tab before the caret as a stop,
/// and a multi-line indent adds that many spaces to each line.
/// **Mutation:** a fixed width of spaces instead of the distance to the stop.
@Test @MainActor func tabWithSpacesPadsToTheNextStop() throws {
    let buffer = CodeBuffer("ab\n\tc\nxyz\nuvw\n")
    let window = try harnessWindow(size: sz(400, 200)) {
        CodeView(buffer: buffer, decorations: CodeDecorations(buffer: buffer)).font(size: 12).tabWidth(4).indentUsingSpaces(true)
    }
    window.click(at: pt(60, 6))
    caret(buffer, 0, 2)
    window.typeKey(.tab)
    #expect(buffer.snapshot().line(0) == "ab  ", "two spaces to column 4")
    caret(buffer, 1, 2)
    window.typeKey(.tab)
    #expect(buffer.snapshot().line(1) == "\tc   ", "the tab is a stop at 4; 'c' is column 5; three spaces to 8")
    buffer.selections = [CodeSelection(anchor: buffer.snapshot().offset(of: CodePoint(row: 2, column: 1)),
                                       head: buffer.snapshot().offset(of: CodePoint(row: 3, column: 2)))]
    window.typeKey(.tab)
    #expect(buffer.snapshot().line(2) == "    xyz" && buffer.snapshot().line(3) == "    uvw", "both lines indented by four spaces")
    window.typeKey(.tab, modifierFlags: .shift)
    #expect(buffer.snapshot().line(2) == "xyz" && buffer.snapshot().line(3) == "uvw")
}

/// 8.12 — Tab arriving at a code view selects nothing (the caret stays where it was; `TextEditor` selects all),
/// Tab inside an editable one indents, and ⌃Tab (⌃⇧Tab back) is how focus leaves it: the traversal stage lets
/// Control through for a code view, where it ignores it for every other element.
/// **Mutation:** the traversal's select-all running for a code target selects the whole buffer; the Control
/// exemption removed leaves ⌃Tab with no effect and the view a focus trap.
@Test @MainActor func tabbingIntoACodeViewDoesNotSelectAllAndControlTabLeaves() throws {
    let buffer = CodeBuffer("some code\nmore\n")
    let window = try harnessWindow(size: sz(400, 200)) {
        VStack(spacing: 0) {
            Box().frame(width: Pixels(20), height: Pixels(20)).focusable().id("first")
            CodeView(buffer: buffer, decorations: CodeDecorations(buffer: buffer)).font(size: 12).frame(height: Pixels(100)).id("code")
            Box().frame(width: Pixels(20), height: Pixels(20)).focusable().id("last")
        }
    }
    buffer.selections = [CodeSelection(caret: 4)]
    window.click(at: pt(10, 10))   // the first box
    let first = window.window.focusedElement
    window.typeKey(.tab)           // into the code view
    #expect(window.window.focusedElement != first)
    #expect(buffer.primarySelection == CodeSelection(caret: 4), "selection after Tab-in: \(buffer.primarySelection)")
    window.typeKey(.tab)
    #expect(buffer.snapshot().line(0) == "some\t code", "Tab in an editable view indents")
    let inCode = window.window.focusedElement
    window.typeKey(.tab, modifierFlags: .control)
    #expect(window.window.focusedElement != inCode, "Control-Tab leaves")
    #expect(buffer.snapshot().line(0) == "some\t code")
    window.typeKey(.tab, modifierFlags: .shift)
    #expect(window.window.focusedElement == inCode, "and Shift-Tab comes back")
    #expect(buffer.primarySelection == CodeSelection(caret: 5), "to the caret it had")
}

// MARK: Clipboard and undo

/// 8.13 — copy takes the selection; with none it takes the whole line with its break; cut does the same and
/// removes it; the last line without a break is copied with the buffer's ending.
/// **Mutation:** an empty selection copying nothing (the TextEditor spelling) leaves the clipboard unwritten.
@Test @MainActor func copyAndCutTakeTheWholeLineWhenNothingIsSelected() throws {
    let (window, buffer) = try editingWindow("first\nsecond\nthird")
    caret(buffer, 1, 3)
    window.typeKey("c", modifierFlags: codePrimary)
    #expect(window.platformWindow.clipboard == "second\n", "whole-line copy: \(String(describing: window.platformWindow.clipboard))")
    #expect(buffer.snapshot().text == "first\nsecond\nthird")
    window.typeKey("x", modifierFlags: codePrimary)
    #expect(window.platformWindow.clipboard == "second\n")
    #expect(buffer.snapshot().text == "first\nthird", "the line and its break are gone")
    buffer.selections = [CodeSelection(anchor: 1, head: 4)]
    window.typeKey("x", modifierFlags: codePrimary)
    #expect(window.platformWindow.clipboard == "irs" && buffer.snapshot().text == "ft\nthird")
    window.typeKey("z", modifierFlags: codePrimary)
    #expect(buffer.snapshot().text == "first\nthird", "cut undoes as one step")
}

/// 8.14 — paste replaces the selection and normalizes every line break to the buffer's (CRLF into an LF buffer,
/// LF and a lone CR into a CRLF buffer), the caret ends after it, and one undo removes it.
/// **Mutation:** pasting `\r\n` verbatim into an LF file leaves a mixed-ending buffer.
@Test @MainActor func pasteNormalizesLineEndingsToTheBuffers() throws {
    let (window, buffer) = try editingWindow("ab\ncd\n")
    window.setClipboard(text: "x\r\ny\rz\nw")
    buffer.selections = [CodeSelection(anchor: 1, head: 2)]
    window.typeKey("v", modifierFlags: codePrimary)
    #expect(buffer.snapshot().text == "ax\ny\nz\nw\ncd\n", "LF buffer: \(buffer.snapshot().text.debugDescription)")
    #expect(buffer.primarySelection == CodeSelection(caret: 8))
    buffer.undo()
    #expect(buffer.snapshot().text == "ab\ncd\n")
    let (window2, crlf) = try editingWindow("ab\r\ncd\r\n")
    window2.setClipboard(text: "x\ny\rz\r\nw")
    window2.typeKey("v", modifierFlags: codePrimary)
    #expect(crlf.snapshot().text == "x\r\ny\r\nz\r\nwab\r\ncd\r\n", "CRLF buffer: \(crlf.snapshot().text.debugDescription)")
}

/// 8.15 — undo and redo through the keys restore the selections the buffer recorded: typing, undo, and the
/// selection is back; redo puts the text and the caret after it. ⌃Y redoes off Apple.
/// **Mutation:** an undo that does not restore the selection leaves the caret at the end of the removed text.
@Test @MainActor func undoAndRedoKeysRestoreTheSelections() throws {
    let (window, buffer) = try editingWindow("hello world\n")
    buffer.selections = [CodeSelection(anchor: 0, head: 5)]
    window.typeText("bye")
    #expect(buffer.snapshot().line(0) == "bye world")
    window.typeKey("z", modifierFlags: codePrimary)
    #expect(buffer.snapshot().line(0) == "hello world")
    #expect(buffer.primarySelection == CodeSelection(anchor: 0, head: 5), "the selection before the edit is back")
    window.typeKey("z", modifierFlags: [codePrimary, .shift])
    #expect(buffer.snapshot().line(0) == "bye world" && buffer.primarySelection == CodeSelection(caret: 3))
    #if !os(macOS)
    window.typeKey("z", modifierFlags: codePrimary)
    window.typeKey("y", modifierFlags: codePrimary)
    #expect(buffer.snapshot().line(0) == "bye world", "Ctrl-Y redoes")
    #endif
}

/// 8.16 — select all selects the whole buffer and the view stays where it was (the caret is at the end, but the
/// key does not reveal it).
/// **Mutation:** select-all revealing the caret scrolls a 1000-line buffer to its end.
@Test @MainActor func selectAllDoesNotScrollToTheEnd() throws {
    let (window, buffer) = try editingWindow(codeText(lines: 1000))
    window.typeKey("a", modifierFlags: codePrimary)
    #expect(buffer.primarySelection.range == 0..<buffer.utf8Count)
    let tint = window.scene.rects.filter { $0.bounds.size.width > 100 }
    #expect(tint.first.map { $0.bounds.origin.y } == 0, "the selection still starts at the top of the view: \(tint.map(\.bounds))")
}

// MARK: Counted work

/// 9.1 — a keystroke at 100 000 lines shapes exactly one line, lays out nothing outside the leaf, and visits
/// the rope in work that does not grow with the file.
/// **Red against** a spelling that rebuilds the string (`snapshot.text`) per key: it visits every chunk.
/// **Mutation:** `CodeEditSession.insert` reading `buffer.snapshot().text`.
@Test @MainActor func aKeystrokeShapesOneLineAndVisitsLogarithmicNodes() throws {
    var visitedAt: [Int] = []
    for lines in [1_000, 100_000] {
        let buffer = CodeBuffer(codeText(lines: lines))
        let decorations = CodeDecorations(buffer: buffer)
        let window = try harnessWindow(size: sz(400, 300)) {
            VStack(spacing: 0) {
                Text("title")
                CodeView(buffer: buffer, decorations: decorations).font(size: 12).frame(height: Pixels(200))
            }
        }
        window.click(at: pt(60, 40))
        buffer.selections = [CodeSelection(caret: 0)]
        window.typeText("a"); window.typeText("b")   // warm: the caches rotate
        window.resetFrameWork()
        let idleBefore = RopeStats.nodesVisited
        window.window.setNeedsRedraw(); window.tick()
        let idle = RopeStats.nodesVisited - idleBefore
        window.resetFrameWork()
        let before = RopeStats.nodesVisited
        window.typeText("c")
        let visited = RopeStats.nodesVisited - before
        let w = totalWork(window)
        #expect(w.codeLinesShaped == 1, "\(lines) lines: shaped \(w.codeLinesShaped)")
        #expect(w.layoutMeasureCalls == 0 && w.layoutMemoMisses == 0, "measure \(w.layoutMeasureCalls), memo misses \(w.layoutMemoMisses)")
        #expect(buffer.snapshot().line(0).hasPrefix("abc"))
        visitedAt.append(visited - idle)
        print("CV-W keystroke at \(lines) lines: frame \(visited) idle frame \(idle)")
    }
    #expect(visitedAt[1] - visitedAt[0] <= 40, "rope nodes the keystroke added over an idle frame: \(visitedAt) at 1k and 100k lines")
    #expect(visitedAt[1] < 200, "and not in proportion to the file: \(visitedAt)")
}

// MARK: The seam

/// 10.1 — a code target reaches every text stage of the window by its early branch and not through `TextEditing`
/// (`CV-W`): a press places the caret (shift extends), a drag selects, a typed character is offered to `onKeyPress`
/// first (and a handled one is swallowed), an input method's marked text never reaches the buffer and its commit
/// is an insert, a key edits, Tab in does not select all, and losing focus leaves the view's own state alone.
/// **Mutation:** each early branch removed in turn, one test arm per stage: `.mouseDown` (the press falls to a
/// `TextEditState` over a string the target does not have), `.mouseDragged`, `.textInput`, `.textComposition`,
/// `dispatchTypedKeyPress` (the swallowed `q` is typed), `dispatchTextKey`, `dispatchFocusTraversal` (the
/// select-all), `focusedElement.didSet` (the view's scroll is replaced by a fresh `TextEditState`'s slot).
@Test @MainActor func aCodeTargetReachesEveryTextStage() throws {
    let buffer = CodeBuffer(codeText(lines: 300))
    let scroll = CodeScrollState()
    var typedOffered = 0
    let window = try harnessWindow(size: sz(400, 300)) {
        VStack(spacing: 0) {
            Box().frame(width: Pixels(20), height: Pixels(20)).focusable().id("other")
            CodeView(buffer: buffer, decorations: CodeDecorations(buffer: buffer)).font(size: 12).scrollState(scroll)
                .onKeyPress("q") { typedOffered += 1; return .handled }
                .frame(height: Pixels(200)).id("code")
        }
    }
    let pitch = codePitch(scale: 1)
    let top = Float(try window.frame(ofID: "code").origin.y.value)
    let otherBox = try window.frame(ofID: "other")
    let otherPoint = pt(Float(otherBox.origin.x.value) + 5, Float(otherBox.origin.y.value) + 5)
    // Stage .mouseDown: a press focuses and places the caret on the line pressed; shift extends from it.
    window.click(at: pt(60, top + 3 * pitch + 2))
    let pressed = buffer.primarySelection
    #expect(pressed.isEmpty && head(buffer).row == 3, "press: \(pressed), row \(head(buffer).row)")
    window.click(at: pt(120, top + 5 * pitch + 2), modifierFlags: .shift)
    #expect(buffer.primarySelection.anchor == pressed.head && head(buffer).row == 5, "shift-click extends: \(buffer.primarySelection)")
    // Stage .mouseDragged.
    window.drag(from: pt(60, top + 2 * pitch + 2), to: pt(140, top + 4 * pitch + 2))
    #expect(buffer.primarySelection.range.count > 0 && head(buffer).row == 4, "drag: \(buffer.primarySelection)")
    // Stage .textInput through dispatchTypedKeyPress: "q" is offered and swallowed, "w" is typed.
    caret(buffer, 3, 0)
    let version = buffer.version
    window.typeText("q")
    #expect(typedOffered == 1 && buffer.version == version, "a handled key press swallows the typed character")
    window.typeText("w")
    #expect(buffer.snapshot().line(3).hasPrefix("w") && typedOffered == 1, "only the key the handler names is offered")
    // Stage .textComposition: marked text never reaches the buffer; its commit is an insert.
    let before = buffer.version
    #expect(window.setMarkedText("かな"))
    #expect(buffer.version == before && window.window.testingComposition == nil, "marked text is not buffer text (run 2 draws it)")
    window.commitMarkedText("仮名")
    #expect(buffer.snapshot().line(3).hasPrefix("w仮名") || buffer.snapshot().line(3).hasPrefix("仮名w"), "the commit inserted: \(buffer.snapshot().line(3))")
    // Stage dispatchTextKey.
    window.typeKey("a", modifierFlags: codePrimary)
    #expect(buffer.primarySelection.range == 0..<buffer.utf8Count)
    // Stage focusedElement.didSet: losing focus leaves the view's state alone (the scroll it published).
    caret(buffer, 0, 0)
    window.scroll(at: pt(200, top + 100), byDeltaX: 0, deltaY: -pitch * 40)
    let scrolled = scroll.position.row
    #expect(scrolled > 30, "scrolled to \(scrolled)")
    window.click(at: otherPoint)
    window.window.setNeedsRedraw(); window.tick()
    #expect(scroll.position.row == scrolled, "blur left the scroll: \(scroll.position.row) vs \(scrolled)")
    // Stage dispatchFocusTraversal: Tab back in selects nothing.
    let at = buffer.primarySelection
    window.typeKey(.tab)
    #expect(buffer.primarySelection == at, "Tab-in selection \(buffer.primarySelection) vs \(at)")
}
