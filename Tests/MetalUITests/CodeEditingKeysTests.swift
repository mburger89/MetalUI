import Testing
import MetalUIPlatform
@testable import MetalUI

// The key table of an editable `CodeView` (`CV-X`), run for both platforms' conventions on every host: ⌘ and ⌥ on a
// Mac, ⌃ elsewhere (`TextEditing.platform`). Pure: a key event in, a command out.

private func key(_ characters: String, _ modifiers: Modifiers = []) -> KeyEvent {
    KeyEvent(charactersIgnoringModifiers: characters, characters: characters, modifiers: modifiers, timestamp: 0)
}

private let left = TextEditing.leftArrow, right = TextEditing.rightArrow, up = TextEditing.upArrow, down = TextEditing.downArrow

/// 11.1 — Mac: ⌘ is the shortcut and the line/document modifier, ⌥ the word modifier; shift extends.
/// **Mutation:** swapping the word and shortcut modifiers moves ⌥← to the line start.
@Test func theMacKeyTable() {
    let mac = TextEditing.Platform.mac
    #expect(CodeEditing.command(for: key(left), platform: mac) == .move(.left, extend: false))
    #expect(CodeEditing.command(for: key(left, .option), platform: mac) == .move(.wordLeft, extend: false))
    #expect(CodeEditing.command(for: key(right, [.option, .shift]), platform: mac) == .move(.wordRight, extend: true))
    #expect(CodeEditing.command(for: key(left, .command), platform: mac) == .move(.lineStart, extend: false))
    #expect(CodeEditing.command(for: key(right, [.command, .shift]), platform: mac) == .move(.lineEnd, extend: true))
    #expect(CodeEditing.command(for: key(up, .command), platform: mac) == .move(.documentStart, extend: false))
    #expect(CodeEditing.command(for: key(down, [.command, .shift]), platform: mac) == .move(.documentEnd, extend: true))
    #expect(CodeEditing.command(for: key(TextEditing.home), platform: mac) == .move(.lineStart, extend: false))
    #expect(CodeEditing.command(for: key(TextEditing.end, .command), platform: mac) == .move(.documentEnd, extend: false))
    #expect(CodeEditing.command(for: key(TextEditing.deleteBackward, .option), platform: mac) == .delete(.wordBackward))
    #expect(CodeEditing.command(for: key(TextEditing.deleteBackward, .command), platform: mac) == .delete(.toLineStart))
    #expect(CodeEditing.command(for: key(TextEditing.deleteForward), platform: mac) == .delete(.forward))
    #expect(CodeEditing.command(for: key("c", .command), platform: mac) == .copy)
    #expect(CodeEditing.command(for: key("z", [.command, .shift]), platform: mac) == .redo)
    #expect(CodeEditing.command(for: key("y", .command), platform: mac) == nil, "⌘Y is not redo on a Mac")
    #expect(CodeEditing.command(for: key("a", .control), platform: mac) == nil, "⌃A is not claimed on a Mac")
    #expect(CodeEditing.command(for: key("\t", .control), platform: mac) == nil)
    #expect(CodeEditing.command(for: key("\t", .command), platform: mac) == nil)
    #expect(CodeEditing.command(for: key("\t"), platform: mac) == .indent)
    #expect(CodeEditing.command(for: key("\t", .shift), platform: mac) == .outdent)
    #expect(CodeEditing.command(for: key("\r", .command), platform: mac) == nil, "⌘↩ passes on (KF-Z)")
    #expect(CodeEditing.command(for: key("\r", .shift), platform: mac) == .newline)
}

/// 11.2 — Elsewhere: ⌃ is both the shortcut (with a letter) and the word modifier (with an arrow); Home and End are
/// the line keys and ⌃Home/⌃End the document's; ⌃Y redoes; ⌘ (the Windows key) and ⌥ are left alone.
/// **Mutation:** ⌃← mapped to the line start (the Mac spelling) or ⌃Y absent.
@Test func theOtherPlatformsKeyTable() {
    let other = TextEditing.Platform.other
    #expect(CodeEditing.command(for: key(left, .control), platform: other) == .move(.wordLeft, extend: false))
    #expect(CodeEditing.command(for: key(right, [.control, .shift]), platform: other) == .move(.wordRight, extend: true))
    #expect(CodeEditing.command(for: key(TextEditing.home), platform: other) == .move(.lineStart, extend: false))
    #expect(CodeEditing.command(for: key(TextEditing.end, [.control, .shift]), platform: other) == .move(.documentEnd, extend: true))
    #expect(CodeEditing.command(for: key(up, .control), platform: other) == nil, "⌃↑ is not a line move off Apple")
    #expect(CodeEditing.command(for: key(TextEditing.deleteBackward, .control), platform: other) == .delete(.wordBackward))
    #expect(CodeEditing.command(for: key("a", .control), platform: other) == .selectAll)
    #expect(CodeEditing.command(for: key("v", .control), platform: other) == .paste)
    #expect(CodeEditing.command(for: key("z", .control), platform: other) == .undo)
    #expect(CodeEditing.command(for: key("y", .control), platform: other) == .redo)
    #expect(CodeEditing.command(for: key("c", .command), platform: other) == nil)
    #expect(CodeEditing.command(for: key(left, .option), platform: other) == nil)
    #expect(CodeEditing.command(for: key("\t", .control), platform: other) == nil, "⌃Tab leaves the view")
    #expect(CodeEditing.command(for: key("\u{19}"), platform: other) == .outdent, "AppKit's backtab character")
    #expect(CodeEditing.command(for: key("\r", .control), platform: other) == nil)
    #expect(CodeEditing.command(for: key("x"), platform: other) == nil, "a plain letter is text, not a key")
}

/// 11.3 — line breaks in pasted and committed text become the buffer's: CRLF is one break, a lone CR is one, an LF
/// after a CR is not a second, and text with none is returned untouched.
@Test func lineBreaksNormalize() {
    #expect(CodeEditing.normalizingLineBreaks("a\r\nb\rc\nd", to: "\n") == "a\nb\nc\nd")
    #expect(CodeEditing.normalizingLineBreaks("a\r\nb\rc\nd", to: "\r\n") == "a\r\nb\r\nc\r\nd")
    #expect(CodeEditing.normalizingLineBreaks("\r\n\r\n", to: "\n") == "\n\n")
    #expect(CodeEditing.normalizingLineBreaks("plain \u{1F600}", to: "\r\n") == "plain \u{1F600}")
}

/// 11.x — find stepping (`CV-AE`): ⌘G / ⇧⌘G on a Mac, ⌃G / ⌃⇧G elsewhere, and no other modifier.
/// **Mutation:** the shift cases swapped steps the wrong way.
@Test func theFindKeysFollowThePlatformConvention() {
    let mac = TextEditing.Platform.mac
    #expect(CodeEditing.command(for: key("g", .command), platform: mac) == .findNext)
    #expect(CodeEditing.command(for: key("g", [.command, .shift]), platform: mac) == .findPrevious)
    #expect(CodeEditing.command(for: key("G", [.command, .shift]), platform: mac) == .findPrevious)
    #expect(CodeEditing.command(for: key("g", .control), platform: mac) == nil, "⌃G is not claimed on a Mac")
    #expect(CodeEditing.command(for: key("g"), platform: mac) == nil, "a plain g is text")
    #expect(CodeEditing.command(for: key("g", [.command, .option]), platform: mac) == nil)
    let other = TextEditing.Platform.other
    #expect(CodeEditing.command(for: key("g", .control), platform: other) == .findNext)
    #expect(CodeEditing.command(for: key("g", [.control, .shift]), platform: other) == .findPrevious)
    #expect(CodeEditing.command(for: key("g", .command), platform: other) == nil)
}
