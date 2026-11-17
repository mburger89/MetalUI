import Testing
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// Ruling `KF-AJ`: `CodeView.builtInKeyBindings(platform:)`, the code view's key table read back as claims.

private func shortcut(_ key: KeyEquivalent, _ modifiers: EventModifiers = []) -> KeyboardShortcut {
    KeyboardShortcut(key, modifiers: modifiers)
}

private func claim(_ list: [ClaimedShortcut], _ key: KeyEquivalent, _ modifiers: EventModifiers = []) -> ClaimedShortcut? {
    list.first { $0.shortcut == shortcut(key, modifiers) }
}

private func editingPlatform(_ platform: KeyboardShortcut.Platform) -> TextEditing.Platform {
    platform == .macOS ? .mac : .other
}

private func event(_ shortcut: KeyboardShortcut) -> KeyEvent {
    let characters = String(shortcut.key.character)
    return KeyEvent(charactersIgnoringModifiers: characters, characters: characters,
                    modifiers: shortcut.modifiers, timestamp: 0)
}

/// The list's size per platform. Mutation: delete one `case` of `CodeEditing.command(for:platform:)` (for example
/// `case "y"`, or Page Up) and the count falls; a platform-blind `mac` constant in the builder moves the Linux count.
@Test func theListHasAFixedSizePerPlatform() {
    #expect(CodeView.builtInKeyBindings(platform: .macOS).count == 63)
    #expect(CodeView.builtInKeyBindings(platform: .linux).count == 46)
    #expect(CodeView.builtInKeyBindings(platform: .windows).count == 46)
}

/// Every listed key is a key the view's own table maps to a command, and no key is listed twice. Mutations:
/// build the Mac list with the `.other` table (21 entries the Mac table refuses redden this) and map `.windows`
/// to the Mac list (38 entries redden).
@Test(arguments: KeyboardShortcut.Platform.allCases)
func everyEntryRoundTripsThroughTheKeyTable(platform: KeyboardShortcut.Platform) {
    let list = CodeView.builtInKeyBindings(platform: platform)
    for entry in list {
        #expect(entry.source == .codeView)
        #expect(CodeEditing.command(for: event(entry.shortcut), platform: editingPlatform(platform)) != nil,
                "\(entry.title) \(entry.shortcut.displayText(for: platform))")
    }
    #expect(Set(list.map(\.shortcut)).count == list.count, "no key twice")
}

/// A sweep over a different key set than the builder's (every printable ASCII character and every named key,
/// every modifier combination) finds no key the table claims that the list leaves out. Mutations: build
/// modifiers `0..<8` (drops the ⌘ keys: 32 issues) or drop `z` from the builder's letters (16 issues). The
/// punctuation and digit sets are not covered by a mutation: the table claims no such key.
@Test(arguments: KeyboardShortcut.Platform.allCases)
func noClaimedKeyIsMissingFromTheList(platform: KeyboardShortcut.Platform) {
    let list = Set(CodeView.builtInKeyBindings(platform: platform).map(\.shortcut))
    var characters: [Character] = (0x20...0x7E).map { Character(Unicode.Scalar($0)!) }
    characters += ["\r", "\t", "\u{1b}", "\u{7f}", "\u{f728}", "\u{f700}", "\u{f701}", "\u{f702}", "\u{f703}",
                   "\u{f729}", "\u{f72b}", "\u{f72c}", "\u{f72d}", "\u{f739}"]
    for character in characters {
        for bits in 0..<16 as Range<UInt8> {
            let modifiers = Modifiers(rawValue: bits)
            let probe = KeyEvent(charactersIgnoringModifiers: String(character), characters: String(character),
                                 modifiers: modifiers, timestamp: 0)
            guard CodeEditing.command(for: probe, platform: editingPlatform(platform)) != nil else { continue }
            // The base-key form: letters lower-cased (an upper-case letter is the same key with ⇧).
            let base = Character(String(character).lowercased())
            #expect(list.contains(shortcut(KeyEquivalent(base), modifiers)),
                    "missing \(shortcut(KeyEquivalent(base), modifiers).displayText(for: platform))")
        }
    }
}

/// macOS: ⌥← is "Move Word Left", ⌘← "Move to Line Start", ⌘G "Find Next" and conditional; no Ctrl+Y.
/// Mutation: swap the `mac` flag for `false` in the builder and ⌥← vanishes.
@Test func macOSHasItsWordAndLineKeys() throws {
    let list = CodeView.builtInKeyBindings(platform: .macOS)
    #expect(claim(list, .leftArrow, .option)?.title == "Move Word Left")
    #expect(claim(list, .leftArrow, .command)?.title == "Move to Line Start")
    #expect(claim(list, .leftArrow, [.command, .shift])?.title == "Select to Line Start")
    #expect(claim(list, .upArrow, .command)?.title == "Move to Document Start")
    #expect(claim(list, .delete, .option)?.title == "Delete Word Backward")
    #expect(claim(list, .return)?.title == "Insert Newline")
    #expect(claim(list, .tab)?.title == "Indent")
    #expect(claim(list, .tab, .shift)?.title == "Outdent")
    #expect(claim(list, "z", .command)?.title == "Undo")
    #expect(claim(list, "z", [.command, .shift])?.title == "Redo")
    let find = try #require(claim(list, "g", .command))
    #expect(find.title == "Find Next" && find.isConditional && find.condition == "only with find matches")
    #expect(claim(list, "y", .control) == nil && claim(list, "y", .command) == nil)
    #expect(claim(list, "k", .command) == nil, "⌘K is not the view's")
}

/// Linux: Ctrl+Y is "Redo" and editable only; Ctrl+↑ is not claimed (Ctrl is the word modifier, ↑ has none), Ctrl+←
/// is "Move Word Left". Mutation: drop `case "y"` and Ctrl+Y goes; make `.upArrow` accept ⌃ and Ctrl+↑ appears.
@Test func linuxHasCtrlYAndNoCtrlUp() throws {
    let list = CodeView.builtInKeyBindings(platform: .linux)
    let redo = try #require(claim(list, "y", .control))
    #expect(redo.title == "Redo" && redo.isConditional && redo.condition == "editable only")
    #expect(claim(list, .upArrow, .control) == nil)
    #expect(claim(list, .leftArrow, .control)?.title == "Move Word Left")
    #expect(claim(list, .leftArrow, .option) == nil, "Alt+← is not a word key off Apple")
    #expect(claim(list, "g", .control)?.title == "Find Next")
}

/// Windows and Linux are one list. Mutation: map `.windows` to a third build with a different table.
@Test func windowsIsTheSameListAsLinux() {
    #expect(CodeView.builtInKeyBindings(platform: .windows) == CodeView.builtInKeyBindings(platform: .linux))
}

/// The conditions: Escape (several selections), ⌘G and ⇧⌘G (find matches), editing keys (editable only), and the
/// unconditional rest. Mutation: return `(false, nil)` for `.collapseSelections` and the first expectation reddens;
/// make `.copy` conditional and the last does.
@Test func conditionalClaimsAreFlaggedWithTheirCondition() throws {
    let list = CodeView.builtInKeyBindings(platform: .macOS)
    let escape = try #require(claim(list, .escape))
    #expect(escape.title == "Collapse Selections" && escape.isConditional && escape.condition == "only with several selections")
    let previous = try #require(claim(list, "g", [.command, .shift]))
    #expect(previous.title == "Find Previous" && previous.condition == "only with find matches")
    for (key, modifiers) in [(KeyEquivalent.return, EventModifiers()), (.delete, []), (.tab, []), ("x", .command),
                             ("v", .command), ("z", .command)] as [(KeyEquivalent, EventModifiers)] {
        let entry = try #require(claim(list, key, modifiers))
        #expect(entry.isConditional && entry.condition == "editable only", "\(entry.title)")
    }
    for (key, modifiers) in [(KeyEquivalent.leftArrow, EventModifiers()), ("a", .command), ("c", .command),
                             (.pageDown, [])] as [(KeyEquivalent, EventModifiers)] {
        let entry = try #require(claim(list, key, modifiers))
        #expect(!entry.isConditional && entry.condition == nil, "\(entry.title)")
    }
    #expect(list.allSatisfy { $0.isConditional == ($0.condition != nil) })
}

/// The list is the same value on every call, and the default platform is `.current`.
@Test func theListIsStable() {
    #expect(CodeView.builtInKeyBindings(platform: .macOS) == CodeView.builtInKeyBindings(platform: .macOS))
    #expect(CodeView.builtInKeyBindings() == CodeView.builtInKeyBindings(platform: .current))
}
