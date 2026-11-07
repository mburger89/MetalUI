import MetalUICodeBuffer
import MetalUICore
import MetalUIPlatform

// The editing session of a `CodeView` (`CV-W`..`CV-Z`): what `Window` calls instead of `TextEditing` when the
// focused text target is a code view's. Built in prepaint over the frame's plan, carried on the target's hooks
// box, run in **input** only: it edits the live buffer (the buffer is the model, so there is no `editedText`
// to compose) and writes the view's `CodeViewState` (caret reveal, the vertical motion's remembered x, the
// drag's origin), never anything from a phase.

/// A line's characters and where each starts, for motion by grapheme and by word (`TextEditing`'s predicates on
/// the line's `Character`s). Built per motion, O(the line).
struct CodeLineText {
    let characters: [Character]
    /// The UTF-8 offset, from the line's start, of each character and of the end (`characters.count + 1` values).
    let starts: [Int]

    init(_ line: String) {
        let characters = Array(line)
        var starts = [0]
        starts.reserveCapacity(characters.count + 1)
        var offset = 0
        var i = 0
        while i < characters.count {
            offset += characters[i].utf8.count
            starts.append(offset)
            i += 1
        }
        self.characters = characters
        self.starts = starts
    }

    /// The index of the character that starts at or before byte `relative`.
    func index(atOrBefore relative: Int) -> Int {
        var lo = 0, hi = starts.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if starts[mid] <= relative { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    /// The first index whose start is at or after byte `relative`.
    func index(atOrAfter relative: Int) -> Int {
        let before = index(atOrBefore: relative)
        return starts[before] == relative ? before : min(before + 1, characters.count)
    }
}

/// What a key did in a code view.
struct CodeKeyOutcome {
    var handled: Bool
    /// Text for the clipboard (copy, cut).
    var copied: String?
}

@MainActor
final class CodeEditSession {
    let buffer: CodeBuffer
    let id: GlobalElementID
    let table: StateTable
    let plan: CodeViewPlan
    /// Whether the view (not the buffer) allows edits.
    let viewEditable: Bool
    let indentUsingSpaces: Bool
    let tabColumns: Int

    init(buffer: CodeBuffer, id: GlobalElementID, table: StateTable, plan: CodeViewPlan,
         editable: Bool, indentUsingSpaces: Bool, tabColumns: Int) {
        self.buffer = buffer
        self.id = id
        self.table = table
        self.plan = plan
        self.viewEditable = editable
        self.indentUsingSpaces = indentUsingSpaces
        self.tabColumns = tabColumns
    }

    /// Whether edits apply: the view allows them and the buffer is not read-only.
    var isEditable: Bool { viewEditable && !buffer.isReadOnly }

    /// Whether an input method has marked text (run 2: the composition lives in `CodeViewState`).
    var isComposing: Bool { false }

    private func update(_ body: (inout CodeViewState) -> Void) {
        table.withState(id, initial: CodeViewState(), body)
    }

    private func state() -> CodeViewState {
        var copy = CodeViewState()
        table.withState(id, initial: CodeViewState()) { copy = $0 }
        return copy
    }

    // MARK: Focus and composition

    /// The view lost focus: a composition does not survive it (`IM-I`). Run 2 stores one; today there is none.
    func dropComposition() {
        // TODO(run 2): clear `CodeViewState.composition`.
    }

    /// Marked text from the input method. TODO(run 2): shown at the caret and committed through `insert`.
    func compose(_ composition: TextComposition) {
        _ = composition
    }

    // MARK: Pointer

    /// A primary press at a view-local point: places the caret, selects a word (two clicks) or a line (three,
    /// or a press in the gutter); shift extends from the current anchor.
    func press(at point: Point<Pixels>, clickCount: Int, extend: Bool) {
        let offset = plan.offset(at: point)
        var origin = offset..<offset
        var granularity: UInt8 = 0
        if plan.isInGutter(point) || clickCount >= 3 {
            origin = plan.unit(atLine: offset)
            granularity = 2
        } else if clickCount == 2 {
            origin = plan.unit(atWord: offset)
            granularity = 1
        }
        if granularity == 0 {
            let anchor = extend ? buffer.primarySelection.anchor : offset
            origin = anchor..<anchor
            buffer.selections = [CodeSelection(anchor: anchor, head: offset)]
        } else {
            buffer.selections = [CodeSelection(anchor: origin.lowerBound, head: origin.upperBound)]
        }
        update {
            $0.dragOriginLower = origin.lowerBound
            $0.dragOriginUpper = origin.upperBound
            $0.dragGranularity = granularity
            $0.goalX = nil
            $0.revealsCaret = false
        }
    }

    /// The pointer moved with the button down: extends from the press by the press's unit.
    func drag(to point: Point<Pixels>) {
        let st = state()
        let offset = plan.offset(at: point)
        let origin = st.dragOriginLower..<st.dragOriginUpper
        switch st.dragGranularity {
        case 0:
            buffer.selections = [CodeSelection(anchor: origin.lowerBound, head: offset)]
        default:
            let unit = st.dragGranularity == 1 ? plan.unit(atWord: offset) : plan.unit(atLine: offset)
            buffer.selections = unit.lowerBound < origin.lowerBound
                ? [CodeSelection(anchor: origin.upperBound, head: unit.lowerBound)]
                : [CodeSelection(anchor: origin.lowerBound, head: max(origin.upperBound, unit.upperBound))]
        }
    }

    // MARK: Text

    /// Committed text replaces the selection. Line breaks become the buffer's.
    func insert(_ text: String) {
        guard isEditable, !text.isEmpty else { return }
        let normalized = CodeEditing.normalizingLineBreaks(text, to: buffer.lineEnding.text)
        buffer.replaceSelections(with: normalized, origin: text.count == 1 ? .typing : .paste)
        update { $0.goalX = nil; $0.revealsCaret = true }
    }

    // MARK: Keys

    /// Runs the key if it is one of the view's. An edit key on a read-only view is not claimed, so it keeps
    /// travelling (Tab still moves focus).
    func key(_ event: KeyEvent, clipboard: () -> String?,
             platform: TextEditing.Platform = TextEditing.platform) -> CodeKeyOutcome {
        guard let command = CodeEditing.command(for: event, platform: platform) else {
            return CodeKeyOutcome(handled: false)
        }
        return run(command, clipboard: clipboard)
    }

    func run(_ command: CodeCommand, clipboard: () -> String?) -> CodeKeyOutcome {
        let snap = buffer.snapshot()
        let selection = buffer.primarySelection
        switch command {
        case .move(let motion, let extend):
            move(motion, extend: extend, snap: snap, selection: selection)
            return CodeKeyOutcome(handled: true)
        case .selectAll:
            buffer.selections = [CodeSelection(anchor: 0, head: snap.utf8Count)]
            update { $0.goalX = nil; $0.revealsCaret = false }
            return CodeKeyOutcome(handled: true)
        case .copy:
            let text = selection.isEmpty ? wholeLine(of: selection.head, snap: snap).text : snap.text(in: selection.range)
            return CodeKeyOutcome(handled: true, copied: text)
        default:
            break
        }
        guard isEditable else {
            // Cut and paste are claimed (nothing happens); keys that only edit travel on.
            switch command {
            case .cut, .paste: return CodeKeyOutcome(handled: true)
            default: return CodeKeyOutcome(handled: false)
            }
        }
        var copied: String?
        switch command {
        case .delete(let deletion):
            delete(deletion, snap: snap, selection: selection)
        case .newline:
            let text = buffer.lineEnding.text + leadingWhitespace(before: selection.range.lowerBound, snap: snap)
            buffer.breakUndoCoalescing()
            buffer.replaceSelections(with: text, origin: .typing)
            buffer.breakUndoCoalescing()
        case .indent:
            indent(snap: snap, selection: selection)
        case .outdent:
            outdent(snap: snap, selection: selection)
        case .cut:
            if selection.isEmpty {
                let line = wholeLine(of: selection.head, snap: snap)
                copied = line.text
                buffer.replace(line.range, with: "", origin: .deletion)
                buffer.breakUndoCoalescing()
            } else {
                copied = snap.text(in: selection.range)
                buffer.replace(selection.range, with: "", origin: .deletion)
                buffer.breakUndoCoalescing()
            }
        case .paste:
            guard let pasted = clipboard(), !pasted.isEmpty else { return CodeKeyOutcome(handled: true) }
            buffer.replaceSelections(with: CodeEditing.normalizingLineBreaks(pasted, to: buffer.lineEnding.text), origin: .paste)
        case .undo:
            buffer.undo()
        case .redo:
            buffer.redo()
        default:
            break
        }
        update { $0.goalX = nil; $0.revealsCaret = true }
        return CodeKeyOutcome(handled: true, copied: copied)
    }

    // MARK: Motion

    private func move(_ motion: CodeMotion, extend: Bool, snap: CodeSnapshot, selection: CodeSelection) {
        var goal: Double?
        let head = selection.head
        let target: Int
        switch motion {
        case .up, .down, .pageUp, .pageDown:
            let rows = motion == .up || motion == .down ? 1 : max(1, plan.heightPx / max(1, plan.pitchPx) - 1)
            let step = (motion == .up || motion == .pageUp) ? -rows : rows
            let x = state().goalX ?? caretX(head, snap: snap)
            let row = snap.point(at: head).row + step
            if row < 0 {
                target = 0
            } else if row >= snap.lineCount {
                target = snap.utf8Count
            } else {
                target = offset(inRow: row, atX: x, snap: snap)
                goal = x
            }
        default:
            target = destination(motion, selection: selection, extend: extend, snap: snap)
        }
        buffer.selections = [CodeSelection(anchor: extend ? selection.anchor : target, head: target)]
        update { $0.goalX = goal; $0.revealsCaret = true }
    }

    /// Where the horizontal and absolute motions go from `selection.head`.
    func destination(_ motion: CodeMotion, selection: CodeSelection, extend: Bool, snap: CodeSnapshot) -> Int {
        let head = selection.head
        let row = snap.point(at: head).row
        let line = snap.lineRange(row)
        let relative = head - line.lowerBound
        func text() -> CodeLineText { CodeLineText(snap.text(in: line)) }
        switch motion {
        case .left:
            if !extend && !selection.isEmpty { return selection.range.lowerBound }
            if head <= line.lowerBound { return row > 0 ? snap.lineRange(row - 1).upperBound : head }
            let t = text()
            return line.lowerBound + t.starts[max(0, t.index(atOrAfter: relative) - 1)]
        case .right:
            if !extend && !selection.isEmpty { return selection.range.upperBound }
            if head >= line.upperBound { return row + 1 < snap.lineCount ? snap.lineRange(row + 1).lowerBound : head }
            let t = text()
            return line.lowerBound + t.starts[min(t.characters.count, t.index(atOrBefore: relative) + 1)]
        case .wordLeft:
            if head <= line.lowerBound { return row > 0 ? snap.lineRange(row - 1).upperBound : head }
            let t = text()
            let at = TextEditing.wordStart(before: t.index(atOrBefore: relative), in: t.characters)
            return line.lowerBound + t.starts[at]
        case .wordRight:
            if head >= line.upperBound { return row + 1 < snap.lineCount ? snap.lineRange(row + 1).lowerBound : head }
            let t = text()
            let at = TextEditing.wordEnd(after: t.index(atOrAfter: relative), in: t.characters)
            return line.lowerBound + t.starts[at]
        case .lineStart:
            let first = line.lowerBound + firstNonBlank(snap.text(in: line))
            return head == first ? line.lowerBound : first
        case .lineEnd:
            return line.upperBound
        case .documentStart:
            return 0
        case .documentEnd:
            return snap.utf8Count
        case .up, .down, .pageUp, .pageDown:
            return head
        }
    }

    /// The byte offset of the first character of `line` that is not a space or a tab (the line's length when all are).
    private func firstNonBlank(_ line: String) -> Int {
        var n = 0
        for byte in line.utf8 {
            if byte != 0x20 && byte != 0x09 { break }
            n += 1
        }
        return n
    }

    /// The x, in points from the text origin, at which the caret at `offset` is drawn.
    func caretX(_ offset: Int, snap: CodeSnapshot) -> Double {
        let row = snap.point(at: offset).row
        let layout = plan.layoutRow(row, snap)
        let local = offset - snap.lineRange(row).lowerBound
        return layout.x(ofByte: local) ?? (local < layout.windowStart ? layout.caretX.first : layout.caretX.last) ?? 0
    }

    /// The byte offset on `row` nearest `x` points from the text origin.
    func offset(inRow row: Int, atX x: Double, snap: CodeSnapshot) -> Int {
        let line = snap.lineRange(row)
        let layout = plan.layoutRow(row, snap)
        return line.lowerBound + min(max(0, layout.byte(atX: x)), line.count)
    }

    // MARK: Editing

    /// The line at `offset` with its break, as the clipboard carries it for an empty selection, and the range a cut removes.
    private func wholeLine(of offset: Int, snap: CodeSnapshot) -> (text: String, range: Range<Int>) {
        let row = snap.point(at: offset).row
        let line = snap.lineRange(row)
        let end = row + 1 < snap.lineCount ? snap.lineRange(row + 1).lowerBound : line.upperBound
        return (snap.text(in: line) + buffer.lineEnding.text, line.lowerBound..<end)
    }

    /// The spaces and tabs from the start of `offset`'s line up to `offset` (and no further than the first character).
    private func leadingWhitespace(before offset: Int, snap: CodeSnapshot) -> String {
        let line = snap.lineRange(snap.point(at: offset).row)
        let text = snap.text(in: line.lowerBound..<min(offset, line.upperBound))
        var n = 0
        for byte in text.utf8 {
            if byte != 0x20 && byte != 0x09 { break }
            n += 1
        }
        return String(text.prefix(n))
    }

    private func delete(_ deletion: CodeDeletion, snap: CodeSnapshot, selection: CodeSelection) {
        var range = selection.range
        // Only a lone character delete coalesces with its neighbours into one undo step.
        let coalesces = range.isEmpty && (deletion == .backward || deletion == .forward)
        if range.isEmpty {
            let head = selection.head
            let row = snap.point(at: head).row
            let line = snap.lineRange(row)
            switch deletion {
            case .backward, .wordBackward:
                if head <= line.lowerBound {
                    guard row > 0 else { return }
                    range = snap.lineRange(row - 1).upperBound..<line.lowerBound
                } else {
                    let t = CodeLineText(snap.text(in: line))
                    let relative = head - line.lowerBound
                    let at = deletion == .backward
                        ? max(0, t.index(atOrAfter: relative) - 1)
                        : TextEditing.wordStart(before: t.index(atOrBefore: relative), in: t.characters)
                    range = (line.lowerBound + t.starts[at])..<head
                }
            case .forward, .wordForward:
                if head >= line.upperBound {
                    guard row + 1 < snap.lineCount else { return }
                    range = line.upperBound..<snap.lineRange(row + 1).lowerBound
                } else {
                    let t = CodeLineText(snap.text(in: line))
                    let relative = head - line.lowerBound
                    let at = deletion == .forward
                        ? min(t.characters.count, t.index(atOrBefore: relative) + 1)
                        : TextEditing.wordEnd(after: t.index(atOrAfter: relative), in: t.characters)
                    range = head..<(line.lowerBound + t.starts[at])
                }
            case .toLineStart:
                range = line.lowerBound..<head
            case .toLineEnd:
                range = head..<line.upperBound
            }
        }
        guard !range.isEmpty else { return }
        buffer.replace(range, with: "", origin: .deletion)
        if !coalesces { buffer.breakUndoCoalescing() }
    }

    /// The indent unit's text at a caret on a line whose text before the caret is `prefix`.
    private func indentText(forPrefix prefix: String) -> String {
        guard indentUsingSpaces else { return "\t" }
        var column = 0
        for scalar in prefix.unicodeScalars {
            column = scalar == "\t" ? (column / tabColumns + 1) * tabColumns : column + 1
        }
        return String(repeating: " ", count: tabColumns - column % tabColumns)
    }

    /// The buffer rows a Tab or ⇧Tab touches: the rows of the selection, less the last when the selection ends at its start.
    private func touchedRows(snap: CodeSnapshot, selection: CodeSelection) -> ClosedRange<Int> {
        let range = selection.range
        let first = snap.point(at: range.lowerBound).row
        var last = snap.point(at: range.upperBound).row
        if last > first && range.upperBound == snap.lineRange(last).lowerBound { last -= 1 }
        return first...last
    }

    private func indent(snap: CodeSnapshot, selection: CodeSelection) {
        let rows = touchedRows(snap: snap, selection: selection)
        if rows.count == 1 && (selection.isEmpty || snap.point(at: selection.range.lowerBound).row == snap.point(at: selection.range.upperBound).row) {
            let start = selection.range.lowerBound
            let line = snap.lineRange(snap.point(at: start).row)
            buffer.breakUndoCoalescing()
            buffer.replaceSelections(with: indentText(forPrefix: snap.text(in: line.lowerBound..<start)), origin: .typing)
            buffer.breakUndoCoalescing()
            return
        }
        let unit = indentUsingSpaces ? String(repeating: " ", count: tabColumns) : "\t"
        buffer.transaction { buffer in
            var row = rows.upperBound
            while row >= rows.lowerBound {
                let at = snap.lineRange(row).lowerBound
                // Blank lines are left as they are, as editors do.
                if !snap.lineRange(row).isEmpty { buffer.replace(at..<at, with: unit, origin: .programmatic) }
                row -= 1
            }
        }
    }

    private func outdent(snap: CodeSnapshot, selection: CodeSelection) {
        let rows = touchedRows(snap: snap, selection: selection)
        buffer.transaction { buffer in
            var row = rows.upperBound
            while row >= rows.lowerBound {
                let line = snap.lineRange(row)
                var remove = 0
                if !line.isEmpty {
                    if snap.byte(at: line.lowerBound) == 0x09 {
                        remove = 1
                    } else {
                        while remove < tabColumns, line.lowerBound + remove < line.upperBound,
                              snap.byte(at: line.lowerBound + remove) == 0x20 { remove += 1 }
                    }
                }
                if remove > 0 { buffer.replace(line.lowerBound..<(line.lowerBound + remove), with: "", origin: .programmatic) }
                row -= 1
            }
        }
    }
}
