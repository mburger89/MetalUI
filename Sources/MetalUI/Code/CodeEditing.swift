import MetalUICore
import MetalUIPlatform

// The keys of an editable `CodeView` as data (`CV-W`, `CV-X`): which command a key event is on a platform, apart
// from running it. The mapping is the only place that differs between macOS and the rest (`TextEditing.platform`),
// so it is a pure function a test can run for both.

/// Where a caret motion goes.
enum CodeMotion: Equatable {
    case left, right, wordLeft, wordRight, up, down
    /// The first non-blank of the line, or the line's start when the caret is already there (smart Home).
    case lineStart
    case lineEnd
    case documentStart, documentEnd
    case pageUp, pageDown
}

/// What a delete key removes, from the caret or (with a selection) the selection.
enum CodeDeletion: Equatable {
    case backward, forward, wordBackward, wordForward, toLineStart, toLineEnd
}

/// One editing command.
enum CodeCommand: Equatable {
    case move(CodeMotion, extend: Bool)
    case delete(CodeDeletion)
    case newline
    case indent, outdent
    case selectAll, copy, cut, paste, undo, redo
    /// ⌘G / ⇧⌘G: the next or previous find match (`CV-AE`).
    case findNext, findPrevious
}

enum CodeEditing {
    /// The command `key` is on `platform`, or `nil` when the view does not claim the key (so it keeps
    /// travelling: a Tab with ⌃ or ⌘ is not an indent and can still move focus, `KF-C`).
    ///
    /// ⌘ is the shortcut modifier on a Mac and ⌃ elsewhere; ⌥ is the word modifier on a Mac and ⌃ elsewhere
    /// (`TextEditing`'s table). A key with a modifier the table does not name is left alone.
    static func command(for key: KeyEvent, platform: TextEditing.Platform) -> CodeCommand? {
        let mods = key.modifiers
        let mac = platform == .mac
        let shift = mods.contains(.shift)
        let shortcut: Modifiers = mac ? .command : .control
        let wordModifier: Modifiers = mac ? .option : .control
        // The modifiers other than shift this key carries; anything not in the platform's pair is foreign.
        let held = mods.subtracting(.shift)
        let hasShortcut = held.contains(shortcut)
        let hasWord = held.contains(wordModifier)
        let foreign = held.subtracting([shortcut, wordModifier])
        guard foreign.isEmpty else { return nil }
        let keyName = key.charactersIgnoringModifiers

        // Off Apple ⌃ is both the shortcut and the word modifier: with an arrow it is the word, with a letter the shortcut.
        let named = [TextEditing.leftArrow, TextEditing.rightArrow, TextEditing.upArrow, TextEditing.downArrow,
                     TextEditing.home, TextEditing.end, TextEditing.pageUp, TextEditing.pageDown,
                     TextEditing.deleteBackward, TextEditing.deleteForward]
        if named.contains(keyName) {
            if mac && hasShortcut && hasWord { return nil }
            switch keyName {
            case TextEditing.leftArrow:
                if mac && hasShortcut { return .move(.lineStart, extend: shift) }
                return .move(hasWord ? .wordLeft : .left, extend: shift)
            case TextEditing.rightArrow:
                if mac && hasShortcut { return .move(.lineEnd, extend: shift) }
                return .move(hasWord ? .wordRight : .right, extend: shift)
            case TextEditing.upArrow:
                if mac && hasShortcut { return .move(.documentStart, extend: shift) }
                return held.isEmpty ? .move(.up, extend: shift) : nil
            case TextEditing.downArrow:
                if mac && hasShortcut { return .move(.documentEnd, extend: shift) }
                return held.isEmpty ? .move(.down, extend: shift) : nil
            case TextEditing.home:
                return .move(held.isEmpty ? .lineStart : .documentStart, extend: shift)
            case TextEditing.end:
                return .move(held.isEmpty ? .lineEnd : .documentEnd, extend: shift)
            case TextEditing.pageUp:
                return held.isEmpty ? .move(.pageUp, extend: shift) : nil
            case TextEditing.pageDown:
                return held.isEmpty ? .move(.pageDown, extend: shift) : nil
            case TextEditing.deleteBackward:
                if mac && hasShortcut { return .delete(.toLineStart) }
                return .delete(hasWord ? .wordBackward : .backward)
            default:   // forward delete
                if mac && hasShortcut { return .delete(.toLineEnd) }
                return .delete(hasWord ? .wordForward : .forward)
            }
        }
        switch keyName {
        case "\r", "\u{3}":
            // ⌘↩ / ⌃↩ is not an editing key (`KF-Z` item 2): it passes on to `onKey` and the commands.
            return hasShortcut ? nil : .newline
        case "\t":
            return held.isEmpty ? (shift ? .outdent : .indent) : nil
        case "\u{19}":   // AppKit's backtab character
            return held.isEmpty ? .outdent : nil
        default:
            break
        }
        guard hasShortcut, !(mac && hasWord) else { return nil }
        switch keyName.lowercased() {
        case "a": return shift ? nil : .selectAll
        case "c": return shift ? nil : .copy
        case "x": return shift ? nil : .cut
        case "v": return shift ? nil : .paste
        case "g": return shift ? .findPrevious : .findNext
        case "z": return shift ? .redo : .undo
        case "y": return !mac && !shift ? .redo : nil
        default: return nil
        }
    }

    /// `text` with every line break (`\r\n`, `\r`, `\n`) replaced by `ending`: what a paste and committed text
    /// are made of before they reach the buffer, so a file keeps one ending.
    static func normalizingLineBreaks(_ text: String, to ending: String) -> String {
        guard text.utf8.contains(where: { $0 == 0x0A || $0 == 0x0D }) else { return text }
        var out = ""
        out.reserveCapacity(text.utf8.count)
        var previousWasReturn = false
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\r":
                out += ending
                previousWasReturn = true
            case "\n":
                if !previousWasReturn { out += ending }
                previousWasReturn = false
            default:
                out.unicodeScalars.append(scalar)
                previousWasReturn = false
            }
        }
        return out
    }
}
