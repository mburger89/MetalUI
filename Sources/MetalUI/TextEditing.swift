import MetalUIPlatform

/// A text field's editing state (ruling TI-B): kept in the window's
/// `StateTable` under the field's id and written from input only. Offsets are
/// Character (grapheme) offsets into the field's text.
struct TextEditState: Equatable, Sendable {
    /// Where a selection started; equal to `head` when nothing is selected.
    var anchor = 0
    /// The caret — the end of the selection that moves.
    var head = 0
    /// An input method's marked text, shown at the caret until committed.
    var composition: TextComposition = .none
    /// How far the text is scrolled left so the caret stays visible.
    var scrollX = 0.0
    /// The granularity the last press selected at, so a drag after a double
    /// click extends by words (ruling TI-D).
    var dragGranularity: TextEditing.Granularity = .character
    /// The selection the press that started a word or all drag made, which a
    /// drag always keeps.
    var dragOrigin: Range<Int> = 0..<0

    var selection: Range<Int> { min(anchor, head)..<max(anchor, head) }

    /// The same state with both ends clamped into `0...count` — the caller's
    /// text may have changed under it (a controlled field).
    func clamped(to count: Int) -> TextEditState {
        var copy = self
        copy.anchor = min(max(anchor, 0), count)
        copy.head = min(max(head, 0), count)
        return copy
    }
}

/// Text editing as pure functions over `(text, TextEditState)` (ruling TI-D):
/// no window, no clipboard, no frame — the window hands in what an operation
/// needs and applies what it returns.
enum TextEditing {
    /// The key conventions in force (TI-D's table and its off-Apple row).
    enum Platform: Sendable { case mac, other }

    #if os(macOS) || os(iOS) || os(tvOS) || os(visionOS) || os(watchOS)
    static let platform = Platform.mac
    #else
    static let platform = Platform.other
    #endif

    enum Granularity: Sendable { case character, word, all }

    /// What a key did.
    struct KeyOutcome: Equatable {
        var state: TextEditState
        /// The new text, if the key changed it.
        var text: String?
        /// Text to put on the clipboard (copy, cut).
        var copied: String?
        /// Return was pressed.
        var submitted = false
        /// Whether the field claimed the key; an unclaimed key keeps bubbling.
        var handled: Bool
    }

    // AppKit's characters for the keys the table names (`SP-C`).
    static let leftArrow = "\u{f702}", rightArrow = "\u{f703}"
    static let upArrow = "\u{f700}", downArrow = "\u{f701}"
    static let home = "\u{f729}", end = "\u{f72b}"
    static let deleteBackward = "\u{7f}", deleteForward = "\u{f728}"

    // MARK: Keys

    static func key(_ key: KeyEvent, text: String, state: TextEditState,
                    clipboard: () -> String?, platform: Platform = platform) -> KeyOutcome {
        let characters = Array(text)
        var state = state.clamped(to: characters.count)
        let unhandled = KeyOutcome(state: state, handled: false)
        // An input method owns the keys while it composes.
        if !state.composition.text.isEmpty { return KeyOutcome(state: state, handled: true) }

        let mods = key.modifiers
        let shift = mods.contains(.shift)
        let shortcut: Modifiers = platform == .mac ? .command : .control
        let wordModifier: Modifiers = platform == .mac ? .option : .control
        let keyName = key.charactersIgnoringModifiers

        // Shortcuts: select all, copy, cut, paste.
        if mods.contains(shortcut) {
            switch keyName.lowercased() {
            case "a":
                state.anchor = 0
                state.head = characters.count
                return KeyOutcome(state: state, handled: true)
            case "c":
                let selected = String(characters[state.selection])
                return KeyOutcome(state: state, copied: selected.isEmpty ? nil : selected, handled: true)
            case "x":
                guard !state.selection.isEmpty else { return KeyOutcome(state: state, handled: true) }
                let selected = String(characters[state.selection])
                let (newText, newState) = replace(state.selection, with: "", in: characters, state: state)
                return KeyOutcome(state: newState, text: newText, copied: selected, handled: true)
            case "v":
                guard let pasted = clipboard(), !pasted.isEmpty else { return KeyOutcome(state: state, handled: true) }
                let (newText, newState) = replace(state.selection, with: singleLine(pasted),
                                                  in: characters, state: state)
                return KeyOutcome(state: newState, text: newText, handled: true)
            default:
                break
            }
        }

        let byWord = mods.contains(wordModifier)
        let toEdge = platform == .mac && mods.contains(.command)

        func move(to target: Int) -> KeyOutcome {
            state.head = target
            if !shift { state.anchor = target }
            return KeyOutcome(state: state, handled: true)
        }

        switch keyName {
        case leftArrow:
            if !shift && !state.selection.isEmpty && !byWord && !toEdge { return move(to: state.selection.lowerBound) }
            if toEdge { return move(to: 0) }
            if byWord { return move(to: wordStart(before: state.head, in: characters)) }
            return move(to: max(0, state.head - 1))
        case rightArrow:
            if !shift && !state.selection.isEmpty && !byWord && !toEdge { return move(to: state.selection.upperBound) }
            if toEdge { return move(to: characters.count) }
            if byWord { return move(to: wordEnd(after: state.head, in: characters)) }
            return move(to: min(characters.count, state.head + 1))
        case upArrow where platform == .mac, home:
            return move(to: 0)
        case downArrow where platform == .mac, end:
            return move(to: characters.count)
        case deleteBackward:
            var range = state.selection
            if range.isEmpty {
                let from: Int
                if toEdge { from = 0 }
                else if byWord { from = wordStart(before: state.head, in: characters) }
                else { from = max(0, state.head - 1) }
                range = from..<state.head
            }
            guard !range.isEmpty else { return KeyOutcome(state: state, handled: true) }
            let (newText, newState) = replace(range, with: "", in: characters, state: state)
            return KeyOutcome(state: newState, text: newText, handled: true)
        case deleteForward:
            var range = state.selection
            if range.isEmpty {
                let to = byWord ? wordEnd(after: state.head, in: characters)
                    : min(characters.count, state.head + 1)
                range = state.head..<to
            }
            guard !range.isEmpty else { return KeyOutcome(state: state, handled: true) }
            let (newText, newState) = replace(range, with: "", in: characters, state: state)
            return KeyOutcome(state: newState, text: newText, handled: true)
        case "\r", "\u{3}":
            return KeyOutcome(state: state, submitted: true, handled: true)
        default:
            return unhandled
        }
    }

    // MARK: Text

    /// Committed text replaces the selection and ends any composition.
    static func insert(_ inserted: String, text: String, state: TextEditState) -> (String, TextEditState) {
        let characters = Array(text)
        var state = state.clamped(to: characters.count)
        state.composition = .none
        return replace(state.selection, with: singleLine(inserted), in: characters, state: state)
    }

    /// Marked text is shown at the caret; the text itself does not change
    /// until it is committed. A composition over a selection replaces it
    /// once committed, as AppKit's own fields do.
    static func compose(_ composition: TextComposition, state: TextEditState) -> TextEditState {
        var state = state
        state.composition = TextComposition(text: singleLine(composition.text), selection: composition.selection)
        return state
    }

    // MARK: Pointer

    /// A press at grapheme boundary `index` (TI-D): one click places the
    /// caret, two select the word, three select everything; shift extends.
    static func press(at index: Int, clickCount: Int, extend: Bool,
                      text: String, state: TextEditState) -> TextEditState {
        let characters = Array(text)
        var state = state.clamped(to: characters.count)
        let index = min(max(index, 0), characters.count)
        state.composition = .none
        if extend {
            state.head = index
            state.dragGranularity = .character
            state.dragOrigin = state.anchor..<state.anchor
            return state
        }
        switch clickCount {
        case ...1:
            state.anchor = index
            state.head = index
            state.dragGranularity = .character
        case 2:
            let word = wordRange(at: index, in: characters)
            state.anchor = word.lowerBound
            state.head = word.upperBound
            state.dragGranularity = .word
        default:
            state.anchor = 0
            state.head = characters.count
            state.dragGranularity = .all
        }
        state.dragOrigin = state.selection
        return state
    }

    /// A drag to boundary `index` extends from the press, by the granularity
    /// the press selected at.
    static func drag(to index: Int, text: String, state: TextEditState) -> TextEditState {
        let characters = Array(text)
        var state = state.clamped(to: characters.count)
        let index = min(max(index, 0), characters.count)
        let origin = state.dragOrigin.clamped(to: 0..<(characters.count + 1))
        switch state.dragGranularity {
        case .character:
            state.head = index
        case .word:
            let word = wordRange(at: index, in: characters)
            if index < origin.lowerBound {
                state.anchor = origin.upperBound
                state.head = word.lowerBound
            } else {
                state.anchor = origin.lowerBound
                state.head = max(word.upperBound, origin.upperBound)
            }
        case .all:
            state.anchor = 0
            state.head = characters.count
        }
        return state
    }

    /// The grapheme boundary nearest `x` among `offsets` (one per boundary).
    static func boundary(nearest x: Double, offsets: [Double]) -> Int {
        guard var best = offsets.indices.first else { return 0 }
        for index in offsets.indices where abs(offsets[index] - x) < abs(offsets[best] - x) { best = index }
        return best
    }

    // MARK: Scrolling

    /// The scroll that keeps `caretX` inside a field `width` wide, moving as
    /// little as possible from `current`, and never past the text's end.
    static func scroll(keeping caretX: Double, visibleIn width: Double, textWidth: Double,
                       current: Double) -> Double {
        let caretWidth = 1.0
        var scroll = current
        if caretX - scroll > width - caretWidth { scroll = caretX - width + caretWidth }
        if caretX - scroll < 0 { scroll = caretX }
        let maximum = max(0, textWidth + caretWidth - width)
        return min(max(scroll, 0), maximum)
    }

    // MARK: Helpers

    static func singleLine(_ string: String) -> String {
        String(string.map { $0.isNewline ? " " : $0 })
    }

    private static func replace(_ range: Range<Int>, with inserted: String, in characters: [Character],
                                state: TextEditState) -> (String, TextEditState) {
        var characters = characters
        let insertedCharacters = Array(inserted)
        characters.replaceSubrange(range, with: insertedCharacters)
        var state = state
        // Count graphemes in the result, not the pieces: an insertion can
        // merge with a neighbour (a combining mark after a letter).
        let text = String(characters)
        let prefix = String(characters[..<(range.lowerBound + insertedCharacters.count)])
        let caret = min(prefix.count, text.count)
        state.anchor = caret
        state.head = caret
        return (text, state)
    }

    static func isWordCharacter(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" }

    static func wordStart(before index: Int, in characters: [Character]) -> Int {
        var i = min(index, characters.count)
        while i > 0 && !isWordCharacter(characters[i - 1]) { i -= 1 }
        while i > 0 && isWordCharacter(characters[i - 1]) { i -= 1 }
        return i
    }

    static func wordEnd(after index: Int, in characters: [Character]) -> Int {
        var i = max(index, 0)
        while i < characters.count && !isWordCharacter(characters[i]) { i += 1 }
        while i < characters.count && isWordCharacter(characters[i]) { i += 1 }
        return i
    }

    /// The word around boundary `index` — or the run of non-word characters
    /// there, so a double click on spaces selects the spaces.
    static func wordRange(at index: Int, in characters: [Character]) -> Range<Int> {
        guard !characters.isEmpty else { return 0..<0 }
        let probe = index < characters.count ? index : characters.count - 1
        let isWord = isWordCharacter(characters[probe])
        var lower = probe, upper = probe + 1
        while lower > 0 && isWordCharacter(characters[lower - 1]) == isWord { lower -= 1 }
        while upper < characters.count && isWordCharacter(characters[upper]) == isWord { upper += 1 }
        return lower..<upper
    }
}

/// What `Window` needs to edit a `TextField` from input (ruling TI-B), built
/// by the field in `prepaint` and carried on its `Handlers`. Geometry is the
/// frame's: window points, scroll-view offsets applied.
struct TextInputTarget {
    /// The text the field was given (a controlled field: the caller owns it).
    var text: String
    /// `caretOffsets` of `text`, one per grapheme boundary.
    var caretOffsets: [Double]
    /// Window x of boundary 0 — the content's left edge minus the scroll.
    var originX: Double
    /// Where the caret was drawn, for the input method's candidate window.
    var caretRect: Bounds<Pixels>
    var onChange: @MainActor (String) -> Void
    var onSubmit: (@MainActor () -> Void)?

    /// The grapheme boundary under window x `x`.
    func boundary(atWindowX x: Double) -> Int {
        TextEditing.boundary(nearest: x - originX, offsets: caretOffsets)
    }
}
