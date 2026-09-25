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
    /// Undo and redo (ruling TI-G).
    var history = TextEditHistory()
    /// A multi-line field's remembered x for up and down (ruling TI-H): the
    /// column a run of vertical moves keeps returning to across short lines.
    var goalX: Double?
    /// A multi-line field's vertical scroll, and whether the next frame must
    /// scroll the caret into view — set by every edit and caret move, left
    /// clear by the mouse wheel so a wheel scroll is not snapped back.
    var scrollY = 0.0
    var revealsCaret = true

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

/// A field's undo and redo stacks (ruling TI-G): snapshots of the text and
/// selection before each edit group. Consecutive typing, consecutive deletes
/// backward and consecutive deletes forward each coalesce into one group;
/// moving the caret, a click, a selection change or any other edit ends the
/// group. Because a field is controlled, the history is only valid for the
/// text its last edit produced: if the caller's text differs from it, someone
/// else changed the text, and the history is dropped rather than replayed
/// over a text it never saw.
struct TextEditHistory: Equatable, Sendable {
    struct Snapshot: Equatable, Sendable {
        var text: String
        var anchor: Int
        var head: Int
    }

    enum EditKind: Equatable, Sendable { case typing, deleteBackward, deleteForward, other }

    /// The deepest either stack grows; the oldest group falls off.
    static let depth = 100

    var undo: [Snapshot] = []
    var redo: [Snapshot] = []
    /// The kind of the group still open for coalescing, if any.
    var openGroup: EditKind?
    /// The text the last edit, undo or redo produced.
    var lastText: String?
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
    static let pageUp = "\u{f72c}", pageDown = "\u{f72d}"

    // MARK: Keys

    /// One key, per TI-D's table; with `lines` the field is multi-line
    /// (ruling TI-H): return inserts a line break, up and down move between
    /// display lines at a remembered x, and the line keys work on the display
    /// line.
    static func key(_ key: KeyEvent, text: String, state: TextEditState,
                    clipboard: () -> String?, platform: Platform = platform,
                    lines: TextLineModel? = nil) -> KeyOutcome {
        let characters = Array(text)
        var state = synced(state.clamped(to: characters.count), with: text)
        let goalX = state.goalX
        state.goalX = nil
        state.revealsCaret = true
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
                state.history.openGroup = nil
                return KeyOutcome(state: state, handled: true)
            case "z":
                let restored = shift ? redo(text: text, state: state) : undo(text: text, state: state)
                return KeyOutcome(state: restored.state, text: restored.text, handled: true)
            case "y" where platform == .other:
                let restored = redo(text: text, state: state)
                return KeyOutcome(state: restored.state, text: restored.text, handled: true)
            case "c":
                let selected = String(characters[state.selection])
                return KeyOutcome(state: state, copied: selected.isEmpty ? nil : selected, handled: true)
            case "x":
                guard !state.selection.isEmpty else { return KeyOutcome(state: state, handled: true) }
                let selected = String(characters[state.selection])
                let (newText, newState) = replace(state.selection, with: "", in: characters, state: state)
                return KeyOutcome(state: recording(.other, from: text, state, to: newText, newState),
                                  text: newText, copied: selected, handled: true)
            case "v":
                guard let pasted = clipboard(), !pasted.isEmpty else { return KeyOutcome(state: state, handled: true) }
                let (newText, newState) = replace(state.selection,
                                                  with: lines == nil ? singleLine(pasted) : lineBreaksNormalized(pasted),
                                                  in: characters, state: state)
                return KeyOutcome(state: recording(.other, from: text, state, to: newText, newState),
                                  text: newText, handled: true)
            default:
                break
            }
        }

        let byWord = mods.contains(wordModifier)
        let toEdge = platform == .mac && mods.contains(.command)

        func move(to target: Int) -> KeyOutcome {
            state.head = target
            if !shift { state.anchor = target }
            state.history.openGroup = nil
            return KeyOutcome(state: state, handled: true)
        }

        if let lines {
            let current = lines.lineIndex(of: state.head)
            func vertical(_ step: Int) -> KeyOutcome {
                let x = goalX ?? lines.x(of: state.head)
                let target = current + step
                // Past the first or last line the caret goes to the text's
                // start or end, and the column is forgotten, as AppKit does.
                if target < 0 { return move(to: 0) }
                if target >= lines.lines.count { return move(to: characters.count) }
                var kept = move(to: lines.boundary(inLine: target, nearest: x))
                kept.state.goalX = x
                return kept
            }
            let lineStart = lines.lines[current].range.lowerBound
            let lineEnd = lines.visibleEnd(ofLine: current)
            switch keyName {
            case upArrow where toEdge: return move(to: 0)
            case downArrow where toEdge: return move(to: characters.count)
            case upArrow: return vertical(-1)
            case downArrow: return vertical(1)
            // Page keys (ruling TI-I). A page is the visible height less one
            // line, so a line of context stays in view. On a Mac they scroll
            // and leave the caret, as NSTextView does; elsewhere they move
            // the caret a page at its column, as Windows' and GTK's do.
            case pageUp, pageDown:
                let sign = keyName == pageUp ? -1.0 : 1.0
                if platform == .mac {
                    state.scrollY = min(max(state.scrollY + sign * lines.pageHeight, 0), lines.maxScrollY)
                    state.revealsCaret = false
                    state.goalX = goalX
                    return KeyOutcome(state: state, handled: true)
                }
                return vertical(Int(sign) * lines.linesPerPage)
            case leftArrow where toEdge, home: return move(to: lineStart)
            case rightArrow where toEdge, end: return move(to: lineEnd)
            case deleteBackward where toEdge && state.selection.isEmpty:
                guard lineStart < state.head else { return KeyOutcome(state: state, handled: true) }
                let (newText, newState) = replace(lineStart..<state.head, with: "", in: characters, state: state)
                return KeyOutcome(state: recording(.other, from: text, state, to: newText, newState),
                                  text: newText, handled: true)
            case "\r", "\u{3}":
                let (newText, newState) = replace(state.selection, with: "\n", in: characters, state: state)
                if !state.selection.isEmpty { state.history.openGroup = nil }
                return KeyOutcome(state: recording(.typing, from: text, state, to: newText, newState),
                                  text: newText, handled: true)
            default:
                break
            }
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
            let single = range.isEmpty && !toEdge && !byWord
            if range.isEmpty {
                let from: Int
                if toEdge { from = 0 }
                else if byWord { from = wordStart(before: state.head, in: characters) }
                else { from = max(0, state.head - 1) }
                range = from..<state.head
            }
            guard !range.isEmpty else { return KeyOutcome(state: state, handled: true) }
            let (newText, newState) = replace(range, with: "", in: characters, state: state)
            return KeyOutcome(state: recording(single ? .deleteBackward : .other, from: text, state,
                                               to: newText, newState),
                              text: newText, handled: true)
        case deleteForward:
            var range = state.selection
            let single = range.isEmpty && !byWord
            if range.isEmpty {
                let to = byWord ? wordEnd(after: state.head, in: characters)
                    : min(characters.count, state.head + 1)
                range = state.head..<to
            }
            guard !range.isEmpty else { return KeyOutcome(state: state, handled: true) }
            let (newText, newState) = replace(range, with: "", in: characters, state: state)
            return KeyOutcome(state: recording(single ? .deleteForward : .other, from: text, state,
                                               to: newText, newState),
                              text: newText, handled: true)
        case "\r", "\u{3}":
            return KeyOutcome(state: state, submitted: true, handled: true)
        default:
            return unhandled
        }
    }

    // MARK: Text

    /// Committed text replaces the selection and ends any composition.
    static func insert(_ inserted: String, text: String, state: TextEditState,
                       multiline: Bool = false) -> (String, TextEditState) {
        let characters = Array(text)
        var state = synced(state.clamped(to: characters.count), with: text)
        state.composition = .none
        state.goalX = nil
        state.revealsCaret = true
        // One typed grapheme with nothing selected continues a typing group;
        // typing over a selection starts one; anything longer (an input
        // method's commit) is a group of its own.
        let kind: TextEditHistory.EditKind = inserted.count == 1 ? .typing : .other
        if !state.selection.isEmpty { state.history.openGroup = nil }
        let (newText, newState) = replace(state.selection,
                                          with: multiline ? lineBreaksNormalized(inserted) : singleLine(inserted),
                                          in: characters, state: state)
        return (newText, recording(kind, from: text, state, to: newText, newState))
    }

    // MARK: Undo and redo (ruling TI-G)

    /// `state` with its history dropped if `text` is not what the history's
    /// last edit produced — the caller changed the text itself.
    static func synced(_ state: TextEditState, with text: String) -> TextEditState {
        guard let last = state.history.lastText, last != text else { return state }
        var state = state
        state.history = TextEditHistory()
        return state
    }

    /// `after` with the edit from `(text, before)` recorded: a new undo group
    /// unless it continues the open one, and redo cleared.
    static func recording(_ kind: TextEditHistory.EditKind, from text: String, _ before: TextEditState,
                          to newText: String, _ after: TextEditState) -> TextEditState {
        var state = after
        var history = before.history
        if kind == .other || history.openGroup != kind {
            history.undo.append(.init(text: text, anchor: before.anchor, head: before.head))
            if history.undo.count > TextEditHistory.depth { history.undo.removeFirst() }
        }
        history.redo = []
        history.openGroup = kind == .other ? nil : kind
        history.lastText = newText
        state.history = history
        return state
    }

    /// The last group undone: `(text, state)`, `text` nil if there was nothing
    /// to undo.
    static func undo(text: String, state: TextEditState) -> (text: String?, state: TextEditState) {
        var state = state
        guard let snapshot = state.history.undo.popLast() else { return (nil, state) }
        state.history.redo.append(.init(text: text, anchor: state.anchor, head: state.head))
        return (snapshot.text, restored(snapshot, into: state))
    }

    /// The last undo redone.
    static func redo(text: String, state: TextEditState) -> (text: String?, state: TextEditState) {
        var state = state
        guard let snapshot = state.history.redo.popLast() else { return (nil, state) }
        state.history.undo.append(.init(text: text, anchor: state.anchor, head: state.head))
        return (snapshot.text, restored(snapshot, into: state))
    }

    private static func restored(_ snapshot: TextEditHistory.Snapshot, into state: TextEditState) -> TextEditState {
        var state = state
        state.anchor = snapshot.anchor
        state.head = snapshot.head
        state.history.openGroup = nil
        state.history.lastText = snapshot.text
        return state
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
        state.history.openGroup = nil
        state.goalX = nil
        state.revealsCaret = true
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
        state.history.openGroup = nil
        state.goalX = nil
        state.revealsCaret = true
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

    /// Every line break a paste or an input method can carry (CR LF, CR,
    /// U+2028…) as `\n`, the one break a multi-line field stores.
    static func lineBreaksNormalized(_ string: String) -> String {
        String(string.map { $0.isNewline ? "\n" : $0 })
    }

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

    // A multi-line field's (ruling TI-H); `lines` is nil for a `TextField`.
    var lines: TextLineModel? = nil
    /// Window y of line 0's top — the content's top minus the scroll.
    var originY = 0.0
    var lineHeight = 0.0
    /// How far the content can scroll: its height past the field's.
    var maxScrollY = 0.0

    /// The grapheme boundary under a window point: on the line under `y`
    /// (clamped to the first and last), nearest `x`.
    func boundary(atWindowX x: Double, y: Double) -> Int {
        guard let lines, lineHeight > 0 else {
            return TextEditing.boundary(nearest: x - originX, offsets: caretOffsets)
        }
        let index = min(max(Int(((y - originY) / lineHeight).rounded(.down)), 0), lines.lines.count - 1)
        return lines.boundary(inLine: index, nearest: x - originX)
    }
}

/// A multi-line field's display lines in graphemes (ruling TI-H): what up and
/// down, the line keys, a press and the caret's position read. Built by
/// `TextEditor` from `TextSystem.lineRanges` and `caretOffsets`, so the lines
/// the caret moves over are the lines it draws.
struct TextLineModel: Equatable {
    struct Line: Equatable {
        /// The line's graphemes, its hard break excluded.
        var range: Range<Int>
        /// `caretOffsets` of the line's text: `range.count + 1` values.
        var offsets: [Double]
        /// Whether a hard break ends it (the next line starts after the
        /// break); otherwise it wrapped, or it is the last line.
        var endsInHardBreak: Bool
    }

    /// Never empty: an empty text is one empty line.
    var lines: [Line]
    /// The line height and the field's visible height, for the page keys
    /// (ruling TI-I); 0 when unknown, which makes a page one line.
    var lineHeight = 0.0
    var visibleHeight = 0.0

    /// A page: the visible height less one line, never under one line.
    var pageHeight: Double { max(lineHeight, visibleHeight - lineHeight) }
    var linesPerPage: Int { lineHeight > 0 ? max(1, Int(pageHeight / lineHeight)) : 1 }
    /// How far the content can scroll.
    var maxScrollY: Double { max(0, Double(lines.count) * lineHeight - visibleHeight) }

    /// The line a boundary's caret is drawn on. A boundary where a line
    /// wrapped belongs to the next line (the caret after a wrapped line's last
    /// space is drawn at the start of the next).
    func lineIndex(of boundary: Int) -> Int {
        for (index, line) in lines.enumerated() where boundary >= line.range.lowerBound {
            if boundary < line.range.upperBound { return index }
            if boundary == line.range.upperBound && (line.endsInHardBreak || index == lines.count - 1) {
                return index
            }
        }
        return lines.count - 1
    }

    /// The x of a boundary on its line.
    func x(of boundary: Int) -> Double {
        let line = lines[lineIndex(of: boundary)]
        let local = min(max(boundary - line.range.lowerBound, 0), line.offsets.count - 1)
        return line.offsets[local]
    }

    /// The last boundary a caret can sit at on line `index` and still be
    /// drawn there: its end, or — for a line that wrapped — before its last
    /// grapheme, whose end is the next line's start.
    func visibleEnd(ofLine index: Int) -> Int {
        let line = lines[index]
        let wrapped = !line.endsInHardBreak && index < lines.count - 1 && !line.range.isEmpty
        return wrapped ? line.range.upperBound - 1 : line.range.upperBound
    }

    /// The boundary on line `index` nearest `x`.
    func boundary(inLine index: Int, nearest x: Double) -> Int {
        let line = lines[index]
        let local = TextEditing.boundary(nearest: x, offsets: line.offsets)
        return min(line.range.lowerBound + local, visibleEnd(ofLine: index))
    }
}
