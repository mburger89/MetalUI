import Foundation
import MetalUITesting
import MetalUIPlatform
import MetalUITerminal
import Testing
@testable import MetalUI
@testable import MetalUITerminalUI

// Terminal phase 4.2 (`TRM-BJ`): the key events the SDL backend delivers (Insert, F13-F20, the keypad, ⌃Space, ⌃`),
// spelled exactly as `SDLKeys.keyEvent` produces them (AppKit's private-use function-key characters, the keypad's
// plain character with `isKeypad`), through the focused view to the bytes the program reads. The SDL side of the
// seam (scancode, keycode and modifiers to this event) is `SDLTerminalKeysTests` in the SDL package.
// Each test names the mutation it was shown red against (`docs/practices/verifying-tests-can-fail.md`).

private func esc(_ s: String) -> [UInt8] { [0x1B] + Array(s.utf8) }

/// **1** Insert, F13-F20 and their ⇧ forms (xterm's `~` numbers 25 26 28 29 31 32 33 34, parameter 2 for ⇧).
/// Mutation: drop F17 from the encoder's number table, or Insert from `specialKey` (their rows fail).
@MainActor @Test func insertAndF13ToF20SendXtermSequences() async throws {
    let rig = try TermRig()
    await rig.settle()
    await rig.focusTerminal()
    var rows: [(String, String, Modifiers, [UInt8])] = [
        ("insert", "\u{F727}", [], esc("[2~")), ("shift-insert", "\u{F727}", .shift, esc("[2;2~")),
        ("ctrl-insert", "\u{F727}", .control, esc("[2;5~")),
    ]
    let numbers = [25, 26, 28, 29, 31, 32, 33, 34]
    for (index, number) in numbers.enumerated() {
        let character = String(try #require(UnicodeScalar(0xF710 + UInt32(index))))
        rows.append(("F\(13 + index)", character, [], esc("[\(number)~")))
        rows.append(("shift-F\(13 + index)", character, .shift, esc("[\(number);2~")))
    }
    for (name, characters, modifiers, expected) in rows {
        rig.log.inputs = []
        rig.key(characters, modifiers)
        #expect(rig.sent == [expected], "\(name): \(rig.sent)")
    }
}

/// **2** The keypad under DECKPAM sends `ESC O p`..`y` for 0-9, `j k m n o` for `* + - . /`, `ESC O X` for `=` and
/// `ESC O M` for Enter; without DECKPAM the characters and CR. A main-row digit is not the keypad.
/// Mutation: ignore `isKeypad` in the encoder (the DECKPAM rows fail for the main-row digit), or send the digit
/// whatever DECKPAM says (the application rows fail).
@MainActor @Test func theKeypadSendsApplicationSequencesOnlyUnderDECKPAM() async throws {
    let rig = try TermRig()
    await rig.settle()
    await rig.focusTerminal()
    let rows: [(String, String)] = [
        ("0", "p"), ("1", "q"), ("2", "r"), ("3", "s"), ("4", "t"), ("5", "u"), ("6", "v"), ("7", "w"), ("8", "x"),
        ("9", "y"), ("*", "j"), ("+", "k"), ("-", "m"), (".", "n"), ("/", "o"), ("=", "X"), ("\r", "M"),
    ]
    for (character, final) in rows {
        rig.log.inputs = []
        rig.key(character, keypad: true)
        #expect(rig.sent == [Array(character.utf8)], "plain keypad \(character.debugDescription): \(rig.sent)")
    }
    await rig.feedModes("\u{1B}=")
    for (character, final) in rows {
        rig.log.inputs = []
        rig.key(character, keypad: true)
        #expect(rig.sent == [esc("O\(final)")], "application keypad \(character.debugDescription): \(rig.sent)")
    }
    rig.log.inputs = []
    rig.key("5")
    #expect(rig.sent == [[0x35]], "a main-row 5 stays a 5: \(rig.sent)")
    await rig.feedModes("\u{1B}>")
}

/// **3** ⌃Space and ⌃` are NUL, with or without ⇧, and the other ⌃-forms of the same row stay (⌃@ NUL, ⌃[ ESC).
/// Mutation: drop 0x20 or 0x60 from the encoder's NUL case (its row fails).
@MainActor @Test func controlSpaceAndControlBacktickAreNUL() async throws {
    let rig = try TermRig()
    await rig.settle()
    await rig.focusTerminal()
    let rows: [(String, String, Modifiers, [UInt8])] = [
        ("ctrl-space", " ", .control, [0x00]), ("ctrl-shift-space", " ", [.control, .shift], [0x00]),
        ("ctrl-backtick", "`", .control, [0x00]), ("ctrl-[", "[", .control, [0x1B]),
    ]
    for (name, characters, modifiers, expected) in rows {
        rig.log.inputs = []
        rig.key(characters, modifiers)
        #expect(rig.sent == [expected], "\(name): \(rig.sent)")
    }
}
