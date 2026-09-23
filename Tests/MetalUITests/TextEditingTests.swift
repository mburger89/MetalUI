import Testing
import MetalUIPlatform
@testable import MetalUI

// TI-D: text editing as a pure function. Every row of the spec's key table,
// on both platforms' conventions, plus text, composition and the pointer.

private let left = TextEditing.leftArrow, right = TextEditing.rightArrow
private let up = TextEditing.upArrow, down = TextEditing.downArrow
private let home = TextEditing.home, end = TextEditing.end
private let back = TextEditing.deleteBackward, forward = TextEditing.deleteForward

private func key(_ name: String, _ modifiers: Modifiers = []) -> KeyEvent {
    KeyEvent(charactersIgnoringModifiers: name, characters: name, modifiers: modifiers, timestamp: 0)
}

private func state(_ anchor: Int, _ head: Int) -> TextEditState {
    var s = TextEditState()
    s.anchor = anchor
    s.head = head
    return s
}

/// `(text after, anchor, head, handled)` for one key.
private func press(_ name: String, _ modifiers: Modifiers = [], on text: String, _ anchor: Int, _ head: Int,
                   platform: TextEditing.Platform = .mac, clipboard: String? = nil)
    -> (String, Int, Int, Bool) {
    let outcome = TextEditing.key(key(name, modifiers), text: text, state: state(anchor, head),
                                  clipboard: { clipboard }, platform: platform)
    return (outcome.text ?? text, outcome.state.anchor, outcome.state.head, outcome.handled)
}

private func same(_ a: (String, Int, Int, Bool), _ b: (String, Int, Int, Bool)) -> Bool {
    a.0 == b.0 && a.1 == b.1 && a.2 == b.2 && a.3 == b.3
}

@Test func arrowsMoveCollapseAndExtend() {
    let t = "hello world"
    #expect(same(press(left, on: t, 3, 3), (t, 2, 2, true)))
    #expect(same(press(right, on: t, 3, 3), (t, 4, 4, true)))
    #expect(same(press(left, on: t, 0, 0), (t, 0, 0, true)), "clamped at the start")
    #expect(same(press(right, on: t, 11, 11), (t, 11, 11, true)), "clamped at the end")
    // A selection collapses to its near end, whichever way it was made.
    #expect(same(press(left, on: t, 2, 7), (t, 2, 2, true)))
    #expect(same(press(right, on: t, 7, 2), (t, 7, 7, true)))
    // Shift moves the head and keeps the anchor.
    #expect(same(press(left, .shift, on: t, 5, 5), (t, 5, 4, true)))
    #expect(same(press(right, .shift, on: t, 5, 7), (t, 5, 8, true)))
}

@Test func wordAndEdgeMotionOnMac() {
    let t = "one two_three, four"
    #expect(same(press(right, .option, on: t, 0, 0), (t, 3, 3, true)), "to the end of the word")
    #expect(same(press(right, .option, on: t, 3, 3), (t, 13, 13, true)), "underscore joins a word")
    #expect(same(press(left, .option, on: t, 15, 15), (t, 4, 4, true)), "skips punctuation, then the word")
    #expect(same(press(left, [.option, .shift], on: t, 19, 19), (t, 19, 15, true)))
    #expect(same(press(left, .command, on: t, 9, 9), (t, 0, 0, true)))
    #expect(same(press(right, .command, on: t, 9, 9), (t, 19, 19, true)))
    #expect(same(press(right, [.command, .shift], on: t, 9, 9), (t, 9, 19, true)))
    #expect(same(press(up, on: t, 9, 9), (t, 0, 0, true)))
    #expect(same(press(down, on: t, 9, 9), (t, 19, 19, true)))
    #expect(same(press(home, on: t, 9, 9), (t, 0, 0, true)))
    #expect(same(press(end, [.shift], on: t, 9, 9), (t, 9, 19, true)))
}

@Test func wordAndEdgeMotionOffApple() {
    let t = "one two three"
    #expect(same(press(right, .control, on: t, 0, 0, platform: .other), (t, 3, 3, true)))
    #expect(same(press(left, .control, on: t, 8, 8, platform: .other), (t, 4, 4, true)))
    // ⌥ is not the word key, and ⌘ is not the edge key, off Apple.
    #expect(same(press(right, .option, on: t, 0, 0, platform: .other), (t, 1, 1, true)))
    #expect(same(press(right, .command, on: t, 0, 0, platform: .other), (t, 1, 1, true)))
    // Up and down are not claimed off Apple; Home and End are the edges.
    #expect(press(up, on: t, 5, 5, platform: .other).3 == false)
    #expect(same(press(home, on: t, 5, 5, platform: .other), (t, 0, 0, true)))
    #expect(same(press(end, on: t, 5, 5, platform: .other), (t, 13, 13, true)))
}

@Test func deletion() {
    #expect(same(press(back, on: "abc", 2, 2), ("ac", 1, 1, true)))
    #expect(same(press(back, on: "abc", 0, 0), ("abc", 0, 0, true)), "nothing before the caret")
    #expect(same(press(forward, on: "abc", 1, 1), ("ac", 1, 1, true)))
    #expect(same(press(forward, on: "abc", 3, 3), ("abc", 3, 3, true)))
    #expect(same(press(back, on: "abcdef", 1, 4), ("aef", 1, 1, true)), "a selection, whichever key")
    #expect(same(press(forward, on: "abcdef", 4, 1), ("aef", 1, 1, true)))
    #expect(same(press(back, .option, on: "one two", 7, 7), ("one ", 4, 4, true)))
    #expect(same(press(back, .command, on: "one two", 5, 5), ("wo", 0, 0, true)))
    #expect(same(press(forward, .option, on: "one two", 3, 3), ("one", 3, 3, true)))
    #expect(same(press(back, .control, on: "one two", 7, 7, platform: .other), ("one ", 4, 4, true)))
    // A grapheme is one step: an emoji with a skin tone, an accented letter.
    #expect(same(press(back, on: "a👍🏽b", 2, 2), ("ab", 1, 1, true)))
    #expect(same(press(forward, on: "e\u{301}x", 0, 0), ("x", 0, 0, true)))
}

@Test func shortcutsSelectCopyCutAndPaste() {
    #expect(same(press("a", .command, on: "hello", 2, 2), ("hello", 0, 5, true)))
    #expect(same(press("a", .control, on: "hello", 2, 2, platform: .other), ("hello", 0, 5, true)))
    // ⌘ is not the shortcut key off Apple, and control is not on a Mac.
    #expect(press("a", .command, on: "hello", 2, 2, platform: .other).3 == false)
    #expect(press("a", .control, on: "hello", 2, 2).3 == false)

    let copy = TextEditing.key(key("c", .command), text: "hello", state: state(1, 4), clipboard: { nil })
    #expect(copy.copied == "ell" && copy.text == nil && copy.handled)
    let emptyCopy = TextEditing.key(key("c", .command), text: "hello", state: state(2, 2), clipboard: { nil })
    #expect(emptyCopy.copied == nil && emptyCopy.handled, "copying nothing leaves the clipboard alone")
    let cut = TextEditing.key(key("x", .command), text: "hello", state: state(4, 1), clipboard: { nil })
    #expect(cut.copied == "ell" && cut.text == "ho" && cut.state.head == 1 && cut.state.anchor == 1)
    #expect(same(press("v", .command, on: "hello", 1, 4, clipboard: "ipp"), ("hippo", 4, 4, true)))
    #expect(same(press("v", .command, on: "ab", 1, 1, clipboard: "x\ny"), ("ax yb", 4, 4, true)),
            "a pasted newline becomes a space: one line")
    #expect(same(press("v", .command, on: "ab", 1, 1, clipboard: nil), ("ab", 1, 1, true)))
    // An unbound shortcut is not claimed, so the app's own handler sees it.
    #expect(press("s", .command, on: "ab", 1, 1).3 == false)
}

@Test func returnSubmitsAndOtherKeysBubble() {
    let enter = TextEditing.key(key("\r"), text: "ab", state: state(1, 1), clipboard: { nil })
    #expect(enter.submitted && enter.handled && enter.text == nil)
    #expect(press("\t", on: "ab", 1, 1).3 == false, "tab is not the field's")
    #expect(press("\u{1b}", on: "ab", 1, 1).3 == false, "escape is not the field's")
    #expect(press("q", on: "ab", 1, 1).3 == false, "a printable key is text, not a key (TI-A)")
}

@Test func insertionReplacesTheSelectionAndCountsGraphemes() {
    var (text, s) = TextEditing.insert("X", text: "abc", state: state(1, 2))
    #expect(text == "aXc" && s.anchor == 2 && s.head == 2)
    (text, s) = TextEditing.insert("line\nbreak", text: "", state: state(0, 0))
    #expect(text == "line break" && s.head == 10)
    // A combining mark joins the letter before it: one grapheme, caret after it.
    (text, s) = TextEditing.insert("\u{301}", text: "e", state: state(1, 1))
    #expect(text == "e\u{301}" && text.count == 1 && s.head == 1)
    // Stale offsets from a text the caller changed are clamped, not trapped on.
    (text, s) = TextEditing.insert("!", text: "ab", state: state(9, 9))
    #expect(text == "ab!" && s.head == 3)
}

@Test func compositionIsShownUntilCommitted() {
    var s = TextEditing.compose(TextComposition(text: "にほ", selection: 2..<2), state: state(1, 1))
    #expect(s.composition.text == "にほ")
    // The input method owns the keys while it composes.
    let during = TextEditing.key(key(left), text: "ab", state: s, clipboard: { nil })
    #expect(during.handled && during.state.head == 1 && during.text == nil)
    let (text, committed) = TextEditing.insert("日本", text: "ab", state: s)
    #expect(text == "a日本b" && committed.head == 3 && committed.composition == .none)
    s = TextEditing.compose(.none, state: s)
    #expect(s.composition.text.isEmpty)
}

@Test func pressesClicksAndDrags() {
    let t = "one two three"
    var s = TextEditing.press(at: 5, clickCount: 1, extend: false, text: t, state: TextEditState())
    #expect(s.anchor == 5 && s.head == 5)
    s = TextEditing.press(at: 9, clickCount: 1, extend: true, text: t, state: s)
    #expect(s.selection == 5..<9, "shift-click extends")
    s = TextEditing.press(at: 5, clickCount: 2, extend: false, text: t, state: s)
    #expect(s.selection == 4..<7, "a double click selects the word")
    s = TextEditing.drag(to: 10, text: t, state: s)
    #expect(s.selection == 4..<13, "a drag after a double click extends by words")
    s = TextEditing.drag(to: 1, text: t, state: s)
    #expect(s.selection == 0..<7 && s.head == 0, "backwards, keeping the first word")
    s = TextEditing.press(at: 3, clickCount: 2, extend: false, text: t, state: s)
    #expect(s.selection == 3..<4, "a double click on a space selects the spaces")
    s = TextEditing.press(at: 5, clickCount: 3, extend: false, text: t, state: s)
    #expect(s.selection == 0..<13, "a triple click selects everything")
    s = TextEditing.press(at: 2, clickCount: 1, extend: false, text: t, state: s)
    s = TextEditing.drag(to: 6, text: t, state: s)
    #expect(s.anchor == 2 && s.head == 6)
}

@Test func theNearestBoundaryAndTheScrollThatKeepsTheCaretVisible() {
    let offsets: [Double] = [0, 10, 20, 35]
    #expect(TextEditing.boundary(nearest: -5, offsets: offsets) == 0)
    #expect(TextEditing.boundary(nearest: 14, offsets: offsets) == 1)
    #expect(TextEditing.boundary(nearest: 16, offsets: offsets) == 2)
    #expect(TextEditing.boundary(nearest: 99, offsets: offsets) == 3)
    #expect(TextEditing.boundary(nearest: 0, offsets: []) == 0)
    // Caret inside: no scroll. Past the right edge: scroll just enough.
    #expect(TextEditing.scroll(keeping: 30, visibleIn: 50, textWidth: 100, current: 0) == 0)
    #expect(TextEditing.scroll(keeping: 80, visibleIn: 50, textWidth: 100, current: 0) == 31)
    // Left of the view: scroll back to the caret.
    #expect(TextEditing.scroll(keeping: 10, visibleIn: 50, textWidth: 100, current: 40) == 10)
    // Never past the end, and never negative.
    #expect(TextEditing.scroll(keeping: 20, visibleIn: 50, textWidth: 30, current: 25) == 0)
}
