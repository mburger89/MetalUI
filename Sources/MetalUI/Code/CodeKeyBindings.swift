import MetalUICore
import MetalUIPlatform

// Ruling `KF-AJ` — the keys a `CodeView` takes, as data. `CodeEditing.command(for:platform:)` is the one table
// the view runs; this reads it back by asking it about every key and modifier combination, so the list cannot
// drift from the behaviour. MetalUI-only (class M).

extension CodeView {
    /// The keys a code view takes on `platform` (`KF-AJ`), each titled by what it does in English
    /// (`"Move Word Left"`, `"Select to Line Start"`, `"Delete Word Backward"`, `"Insert Newline"`, `"Indent"`,
    /// `"Undo"`, `"Find Next"`, `"Collapse Selections"`), with source ``ClaimedShortcut/Source/codeView``.
    ///
    /// It is built by asking the view's own key table (`CodeEditing.command(for:platform:)`) about every named key
    /// (Return, Escape, Space, Tab, Delete, forward delete, the arrows, Home, End, Page Up/Down, Clear), `a` to `z`,
    /// `0` to `9` and the ASCII punctuation, in that order, each with the 16 modifier combinations in ascending bit
    /// order (none, ⇧, ⌃, ⇧⌃, ⌥, ...). Windows and Linux give the same list. The list is the same for every code
    /// view and is computed once per platform family, so calling it is cheap.
    ///
    /// Shortcuts are in the base-key form (`KF-AL`): letters lower-cased, ⇧Tab as Tab with ⇧.
    ///
    /// **Some claims are conditional** (``ClaimedShortcut/isConditional``; the key is reported either way):
    /// - Escape ("Collapse Selections"): `"only with several selections; ends a snippet"` (`CV-BR`: Escape also ends a
    ///   running snippet session first, even with one selection).
    /// - Tab ("Indent") and Shift-Tab ("Outdent"): `"editable only; next placeholder in a snippet"` and
    ///   `"editable only; previous placeholder in a snippet"` (`CV-BR`).
    /// - ⌘G and ⇧⌘G, Ctrl+G and Ctrl+Shift+G ("Find Next", "Find Previous"): `"only with find matches"`.
    /// - Every other command that changes the text (Insert Newline, the deletes, Cut, Paste, Undo,
    ///   Redo): `"editable only"`, because a read-only view does not take the key.
    ///
    /// Movement, selection (including Select All) and Copy are unconditional. The multi-caret keys other than
    /// Escape (⌥-click and ⌥-drag, `CV-BK`) are pointer gestures and not keys.
    public nonisolated static func builtInKeyBindings(platform: KeyboardShortcut.Platform = .current) -> [ClaimedShortcut] {
        switch platform {
        case .macOS: CodeKeyBindingTable.mac
        case .linux, .windows: CodeKeyBindingTable.other
        }
    }
}

/// The two lists, each built on first use.
private enum CodeKeyBindingTable {
    static let mac = build(.mac)
    static let other = build(.other)

    /// Every key the list asks about, in order.
    static let keys: [Character] = {
        let named = [KeyEquivalent.return, .escape, .space, .tab, .delete, .deleteForward, .upArrow, .downArrow,
                     .leftArrow, .rightArrow, .home, .end, .pageUp, .pageDown, .clear].map(\.character)
        let letters = "abcdefghijklmnopqrstuvwxyz"
        let digits = "0123456789"
        let punctuation = "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"
        return named + Array(letters) + Array(digits) + Array(punctuation)
    }()

    static func build(_ platform: TextEditing.Platform) -> [ClaimedShortcut] {
        var claims: [ClaimedShortcut] = []
        for key in keys {
            for bits in 0..<16 {
                let modifiers = Modifiers(rawValue: UInt8(bits))
                let event = KeyEvent(charactersIgnoringModifiers: String(key), characters: String(key),
                                     modifiers: modifiers, timestamp: 0)
                guard let command = CodeEditing.command(for: event, platform: platform) else { continue }
                let (isConditional, condition) = conditionality(of: command)
                claims.append(ClaimedShortcut(title: title(of: command),
                                              shortcut: KeyboardShortcut(KeyEquivalent(key), modifiers: modifiers),
                                              source: .codeView, isConditional: isConditional, condition: condition))
            }
        }
        return claims
    }

    static func conditionality(of command: CodeCommand) -> (Bool, String?) {
        switch command {
        case .collapseSelections: (true, "only with several selections; ends a snippet")
        case .findNext, .findPrevious: (true, "only with find matches")
        case .indent: (true, "editable only; next placeholder in a snippet")
        case .outdent: (true, "editable only; previous placeholder in a snippet")
        case .delete, .newline, .cut, .paste, .undo, .redo: (true, "editable only")
        case .move, .selectAll, .copy: (false, nil)
        }
    }

    static func title(of command: CodeCommand) -> String {
        switch command {
        case let .move(motion, extend):
            let verb = extend ? "Select" : "Move"
            switch motion {
            case .left: return "\(verb) Left"
            case .right: return "\(verb) Right"
            case .wordLeft: return "\(verb) Word Left"
            case .wordRight: return "\(verb) Word Right"
            case .up: return "\(verb) Up"
            case .down: return "\(verb) Down"
            case .lineStart: return "\(verb) to Line Start"
            case .lineEnd: return "\(verb) to Line End"
            case .documentStart: return "\(verb) to Document Start"
            case .documentEnd: return "\(verb) to Document End"
            case .pageUp: return "\(verb) Page Up"
            case .pageDown: return "\(verb) Page Down"
            }
        case let .delete(deletion):
            switch deletion {
            case .backward: return "Delete Backward"
            case .forward: return "Delete Forward"
            case .wordBackward: return "Delete Word Backward"
            case .wordForward: return "Delete Word Forward"
            case .toLineStart: return "Delete to Line Start"
            case .toLineEnd: return "Delete to Line End"
            }
        case .newline: return "Insert Newline"
        case .indent: return "Indent"
        case .outdent: return "Outdent"
        case .selectAll: return "Select All"
        case .copy: return "Copy"
        case .cut: return "Cut"
        case .paste: return "Paste"
        case .undo: return "Undo"
        case .redo: return "Redo"
        case .findNext: return "Find Next"
        case .findPrevious: return "Find Previous"
        case .collapseSelections: return "Collapse Selections"
        }
    }
}
