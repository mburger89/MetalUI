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
    /// The selections this view edits through (`CV-AY`): its own state, else the buffer's default one.
    let selectionState: CodeSelectionState
    let id: GlobalElementID
    let table: StateTable
    let plan: CodeViewPlan
    /// Whether the view (not the buffer) allows edits.
    let viewEditable: Bool
    let indentUsingSpaces: Bool
    let tabColumns: Int
    /// The gutter-bar click callback (`CV-AB`), run from input.
    let gutterClick: (@MainActor (CodeGutterHit) -> Void)?
    /// The modifiers and action of ``CodeView/onTextClick(modifiers:perform:)`` (`CV-AL`).
    let textClick: (modifiers: EventModifiers, action: @MainActor (CodeHit) -> Void)?
    /// The decorations whose find matches ⌘G steps through (`CV-AE`).
    let decorations: CodeDecorations?
    /// The text hover's input side, which a press, a key and typed text end (`CV-AS`).
    let hover: CodeTextHoverRuntime?

    init(buffer: CodeBuffer, id: GlobalElementID, table: StateTable, plan: CodeViewPlan,
         editable: Bool, indentUsingSpaces: Bool, tabColumns: Int,
         gutterClick: (@MainActor (CodeGutterHit) -> Void)? = nil,
         textClick: (modifiers: EventModifiers, action: @MainActor (CodeHit) -> Void)? = nil,
         decorations: CodeDecorations? = nil, hover: CodeTextHoverRuntime? = nil,
         selectionState: CodeSelectionState? = nil) {
        self.selectionState = selectionState ?? buffer.selectionState
        self.hover = hover
        self.gutterClick = gutterClick
        self.textClick = textClick
        self.decorations = decorations
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

    /// Whether an input method has marked text (it lives in `CodeViewState`, never in the buffer, `CV-AA`).
    var isComposing: Bool { !state().composition.text.isEmpty }

    /// The marked text and its selection, `nil` when none.
    var composition: TextComposition? {
        let composition = state().composition
        return composition.text.isEmpty ? nil : composition
    }

    private func update(_ body: (inout CodeViewState) -> Void) {
        table.withState(id, initial: CodeViewState(), body)
    }

    private func state() -> CodeViewState {
        table.readState(id, initial: CodeViewState())   // a read, not a write (`RW-J`)
    }

    // MARK: Focus and composition

    /// The view lost focus (or a press, or an end): a composition does not survive it (`IM-I`). Nothing is
    /// written when there is none.
    func dropComposition() {
        guard isComposing else { return }
        update { $0.composition = .none }
        selectionState.foreignEditHandlers[id] = nil
    }

    /// Marked text from the input method (`CV-AA`): shown at the caret (the selection's start, which a commit
    /// replaces) through the caret line's layout alone, and never in the buffer or its edit stream until
    /// `insert` commits it. An empty composition ends it; a view that cannot edit takes none.
    func compose(_ composition: TextComposition) {
        hover?.hardEnd()
        guard isEditable else { return }
        let text = String(composition.text.map { $0.isNewline ? " " : $0 })
        guard !text.isEmpty else {
            dropComposition()
            return
        }
        let count = text.count
        let lower = min(max(composition.selection.lowerBound, 0), count)
        let upper = min(max(composition.selection.upperBound, lower), count)
        let version = buffer.version
        let anchor = selectionState.primarySelection.range.lowerBound
        update {
            if $0.composition.text.isEmpty || $0.compositionVersion != version {
                $0.compositionOffset = anchor
                $0.compositionVersion = version
            }
            $0.composition = TextComposition(text: text, selection: lower..<upper)
            $0.revealsCaret = true
        }
        // An edit made through another state ends this composition, committing the composed text through this view's
        // state (`CV-AZ`, from the AppKit probe). Registered with the state, run by the buffer after the edit.
        let id = id
        selectionState.foreignEditHandlers[id] = { [self] in   // this session's table and id outlive the frame; removed when it ends
            selectionState.foreignEditHandlers[id] = nil
            let composition = state().composition
            guard !composition.text.isEmpty else { return }
            update { $0.composition = .none; $0.goalX = nil; $0.goalXs = nil }
            let text = CodeEditing.normalizingLineBreaks(composition.text, to: buffer.lineEnding.text)
            selectionState.replaceSelections(with: text, origin: composition.text.count == 1 ? .typing : .paste)
        }
    }

    // MARK: Pointer

    /// A primary press at a view-local point: places the caret, selects a word (two clicks) or a line (three,
    /// or a press in the gutter); shift extends from the current anchor.
    func press(at point: Point<Pixels>, clickCount: Int, extend: Bool, modifiers: EventModifiers = []) {
        hover?.hardEnd()   // a press ends a hover (`CV-AS`)
        // A press whose modifiers are exactly the handler's, on text, is the app's (`CV-AL`): nothing else happens.
        if let click = textClick, modifiers == click.modifiers, !plan.rows.isEmpty {
            let hit = plan.hit(at: point)
            if hit.region == .text {
                update { $0.dragging = false }
                click.action(hit)
                return
            }
        }
        if let click = gutterClick, let hit = plan.gutterHit(at: point) {   // a bar's press is the app's (`CV-AB`)
            update { $0.dragging = false }
            click(hit)
            return
        }
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
            let anchor = extend ? selectionState.primarySelection.anchor : offset
            origin = anchor..<anchor
            selectionState.selections = [CodeSelection(anchor: anchor, head: offset)]
        } else {
            selectionState.selections = [CodeSelection(anchor: origin.lowerBound, head: origin.upperBound)]
        }
        selectionState.foreignEditHandlers[id] = nil
        update {
            $0.dragOriginLower = origin.lowerBound
            $0.dragOriginUpper = origin.upperBound
            $0.dragGranularity = granularity
            $0.dragging = true
            $0.autoscroll = nil
            $0.composition = .none   // a press ends a composition, as a text field's does
            $0.goalX = nil
            $0.goalXs = nil
            $0.revealsCaret = false
        }
    }

    /// Points a second an autoscroll never exceeds.
    static let autoscrollMaximum = 2400.0

    /// The pointer moved with the button down: extends from the press by the press's unit. Outside the view it
    /// also starts, retunes or ends the autoscroll (`CV-AD`): the scroll is `start`, the offsets then and a
    /// velocity written here from input, and every phase computes the offset from the frame's time.
    func drag(to point: Point<Pixels>, at time: Double) {
        let st = state()
        guard st.dragging else { return }
        let scale = Double(plan.scale)
        let top = Double(plan.originY) / scale, bottom = Double(plan.originY + plan.heightPx) / scale
        let left = Double(plan.originX) / scale, right = Double(plan.originX + plan.widthPx) / scale
        let x = Double(point.x.value), y = Double(point.y.value)
        func speed(_ distance: Double) -> Double {
            distance == 0 ? 0 : (distance < 0 ? -1 : 1) * min(Self.autoscrollMaximum, 60 + 20 * abs(distance))
        }
        let vy = speed(y < top ? y - top : (y > bottom ? y - bottom : 0))
        let vx = speed(x < left ? x - left : (x > right ? x - right : 0))
        let inside = Point(x: point.x, y: Pixels(Float(min(max(y, top), bottom - 1 / scale))))
        let offset = plan.offset(at: inside)
        selectionState.selections = [plan.dragSelection(to: offset, origin: st.dragOriginLower..<st.dragOriginUpper,
                                                granularity: st.dragGranularity)]
        let topPx = plan.topPx, scrollXPx = plan.scrollXPx
        update { state in
            if vy == 0 && vx == 0 {
                state.autoscroll = nil
            } else if var running = state.autoscroll, running.vy == vy, running.vx == vx {
                running.pointerX = x
                running.pointerY = y
                state.autoscroll = running
            } else {
                state.autoscroll = CodeViewState.Autoscroll(start: time, baseTopPx: topPx, baseXPx: scrollXPx, vy: vy, vx: vx,
                                                            pointerX: x, pointerY: y)
            }
        }
    }

    /// The button was released: an autoscroll ends and the selection it computed in the frames becomes the
    /// buffer's (until now only the view's picture had it).
    func endDrag() {
        let st = state()
        guard st.dragging else { return }
        if st.autoscroll != nil, let selection = plan.liveDragSelection { selectionState.selections = [selection] }
        update { $0.dragging = false; $0.autoscroll = nil }
    }

    // MARK: Text

    /// Committed text replaces the selection. Line breaks become the buffer's.
    func insert(_ text: String) {
        hover?.hardEnd()   // typed text ends a hover (`CV-AS`)
        guard isEditable, !text.isEmpty else { return }
        let normalized = CodeEditing.normalizingLineBreaks(text, to: buffer.lineEnding.text)
        selectionState.replaceSelections(with: normalized, origin: text.count == 1 ? .typing : .paste)
        update { $0.composition = .none; $0.goalX = nil; $0.goalXs = nil; $0.revealsCaret = true }   // a commit ends the composition (`CV-AA`)
        selectionState.foreignEditHandlers[id] = nil
    }

    // MARK: Keys

    /// Runs the key if it is one of the view's. An edit key on a read-only view is not claimed, so it keeps
    /// travelling (Tab still moves focus).
    func key(_ event: KeyEvent, clipboard: () -> String?,
             platform: TextEditing.Platform = TextEditing.platform) -> CodeKeyOutcome {
        hover?.hardEnd()   // a key ends a hover (`CV-AS`)
        guard let command = CodeEditing.command(for: event, platform: platform) else {
            return CodeKeyOutcome(handled: false)
        }
        return run(command, clipboard: clipboard)
    }

    func run(_ command: CodeCommand, clipboard: () -> String?) -> CodeKeyOutcome {
        let snap = buffer.snapshot()
        let selection = selectionState.primarySelection
        switch command {
        case .move(let motion, let extend):
            move(motion, extend: extend, snap: snap, selection: selection)
            return CodeKeyOutcome(handled: true)
        case .selectAll:
            selectionState.selections = [CodeSelection(anchor: 0, head: snap.utf8Count)]
            update { $0.goalX = nil; $0.goalXs = nil; $0.revealsCaret = false }
            return CodeKeyOutcome(handled: true)
        case .collapseSelections:
            // Escape (`CV-BI`): with several selections only the primary stays, keeping its range, and the key is
            // claimed; with one it is not the view's, so it keeps travelling to an app's own Escape.
            guard selectionState.selections.count > 1 else { return CodeKeyOutcome(handled: false) }
            selectionState.collapseToPrimary()
            update { $0.goalX = nil; $0.goalXs = nil; $0.revealsCaret = true }
            return CodeKeyOutcome(handled: true)
        case .findNext, .findPrevious:
            // Claimed only while matches exist, so the key keeps travelling for an app's own find (`CV-AE`).
            guard let decorations, let match = decorations.stepCurrentMatch(forward: command == .findNext, from: selection.range) else {
                return CodeKeyOutcome(handled: false)
            }
            selectionState.select(match, reveal: true)   // centres it in every view of the buffer (`CV-V`)
            update { $0.goalX = nil; $0.goalXs = nil; $0.revealsCaret = false }
            return CodeKeyOutcome(handled: true)
        case .copy:
            return CodeKeyOutcome(handled: true, copied: copiedText(selectionState.selections, snap: snap))
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
            delete(deletion, snap: snap)
        case .newline:
            // One line break and the indentation before each selection's start (`CV-BH`), one edit.
            let ending = buffer.lineEnding.text
            let texts = selectionState.selections.map { ending + leadingWhitespace(before: $0.range.lowerBound, snap: snap) }
            buffer.breakUndoCoalescing()
            selectionState.replaceSelections(withEach: texts, origin: .typing)
            buffer.breakUndoCoalescing()
        case .indent:
            indent(snap: snap)
        case .outdent:
            outdent(snap: snap)
        case .cut:
            // The text is every selection's, joined; the removal is each selection's range (an empty one's whole
            // line), the overlapping ones unioned, as one edit (`CV-BH`).
            let sels = selectionState.selections
            copied = copiedText(sels, snap: snap)
            let ranges = sels.map { $0.isEmpty ? wholeLine(of: $0.head, snap: snap).range : $0.range }
            selectionState.replaceEach(Self.union(ranges).map { (range: $0, text: "") }, origin: .deletion)
            buffer.breakUndoCoalescing()
        case .paste:
            guard let pasted = clipboard(), !pasted.isEmpty else { return CodeKeyOutcome(handled: true) }
            let text = CodeEditing.normalizingLineBreaks(pasted, to: buffer.lineEnding.text)
            let count = selectionState.selections.count
            if count > 1, let lines = Self.spreadLines(of: text, over: count, ending: buffer.lineEnding.text) {
                selectionState.replaceSelections(withEach: lines, origin: .paste)   // one line to each selection
            } else {
                selectionState.replaceSelections(with: text, origin: .paste)
            }
        case .undo:
            selectionState.undo()
        case .redo:
            selectionState.redo()
        default:
            break
        }
        update { $0.goalX = nil; $0.goalXs = nil; $0.revealsCaret = true }
        return CodeKeyOutcome(handled: true, copied: copied)
    }

    /// The lines of `text` (already in the buffer's line ending) when there are exactly `count` of them, ignoring
    /// one trailing break: VS Code's `multiCursorPaste: spread` (`CV-BH`). `nil` otherwise.
    static func spreadLines(of text: String, over count: Int, ending: String) -> [String]? {
        var body = Substring(text)
        if body.hasSuffix(ending) { body = body.dropLast(ending.count) }
        let lines = body.components(separatedBy: ending)
        return lines.count == count ? lines : nil
    }

    /// `ranges` ascending by start with every overlapping pair merged and empty ranges dropped (touching ranges stay
    /// apart, so a batch of them is still ascending and non-overlapping). `CV-BH`.
    static func union(_ ranges: [Range<Int>]) -> [Range<Int>] {
        var out: [Range<Int>] = []
        out.reserveCapacity(ranges.count)
        for range in ranges.filter({ !$0.isEmpty }).sorted(by: { $0.lowerBound < $1.lowerBound || ($0.lowerBound == $1.lowerBound && $0.upperBound < $1.upperBound) }) {
            if let last = out.last, range.lowerBound < last.upperBound {
                out[out.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                out.append(range)
            }
        }
        return out
    }

    /// What copy and cut put on the clipboard (`CV-BH`). One selection: its text, or for a caret its whole line with
    /// the break (a paste then lands as a line). Several: each selection's text in order, joined by the buffer's
    /// line ending; a caret contributes its line without the break, once per line, so the clipboard has one line to
    /// a selection and a paste over as many selections spreads it back.
    private func copiedText(_ sels: [CodeSelection], snap: CodeSnapshot) -> String {
        if sels.count == 1 {
            let selection = sels[0]
            return selection.isEmpty ? wholeLine(of: selection.head, snap: snap).text : snap.text(in: selection.range)
        }
        var pieces: [String] = []
        pieces.reserveCapacity(sels.count)
        var lastCaretRow = -1
        for selection in sels {
            if selection.isEmpty {
                let row = snap.point(at: selection.head).row
                if row == lastCaretRow { continue }
                lastCaretRow = row
                pieces.append(snap.text(in: snap.lineRange(row)))
            } else {
                pieces.append(snap.text(in: selection.range))
            }
        }
        return pieces.joined(separator: buffer.lineEnding.text)
    }

    // MARK: Motion

    /// Moves every selection's head by `motion` (`extend` keeps each anchor), then normalizes: selections that meet
    /// merge, and the primary stays the one it was. One selection takes the path it always had.
    private func move(_ motion: CodeMotion, extend: Bool, snap: CodeSnapshot, selection: CodeSelection) {
        let sels = selectionState.selections
        guard sels.count > 1 else {
            moveOne(motion, extend: extend, snap: snap, selection: selection)
            return
        }
        // The seam for hidden rows (`CV-BL`, G5 layout): the target row of a vertical step and the row a left/right
        // wrap lands on are where a hidden row would be skipped; nothing is hidden yet, so every row is a line.
        var next = sels
        var goals: [Double]?
        switch motion {
        case .up, .down, .pageUp, .pageDown:
            let rows = motion == .up || motion == .down ? 1 : max(1, plan.visibleHeightPx / max(1, plan.pitchPx) - 1)
            let step = (motion == .up || motion == .pageUp) ? -rows : rows
            let st = state()
            let previous = st.goalXs.flatMap { $0.count == sels.count && st.goalXsSerial == selectionState.mutationSerial ? $0 : nil }
            var out = [Double](repeating: .nan, count: sels.count)
            for (i, s) in sels.enumerated() {
                let row = snap.point(at: s.head).row + step
                let target: Int
                if row < 0 {
                    target = 0
                } else if row >= snap.lineCount {
                    target = snap.utf8Count
                } else {
                    let kept = previous?[i] ?? .nan
                    let x = kept.isNaN ? columnX(s.head, snap: snap) : kept
                    target = offsetInRow(row, atX: x, snap: snap)
                    out[i] = x
                }
                next[i] = CodeSelection(anchor: extend ? s.anchor : target, head: target)
            }
            goals = out
        default:
            for (i, s) in sels.enumerated() {
                let target = destination(motion, selection: s, extend: extend, snap: snap)
                next[i] = CodeSelection(anchor: extend ? s.anchor : target, head: target)
            }
        }
        selectionState.setSelections(next, primary: selectionState.primaryIndex)
        // Goals follow their selections only while none merged (the arrays stay parallel).
        let kept = selectionState.selections.count == sels.count ? goals : nil
        let serial = selectionState.mutationSerial
        update { $0.goalX = nil; $0.goalXs = kept; $0.goalXsSerial = serial; $0.revealsCaret = true }
    }

    private func moveOne(_ motion: CodeMotion, extend: Bool, snap: CodeSnapshot, selection: CodeSelection) {
        var goal: Double?
        let head = selection.head
        let target: Int
        switch motion {
        case .up, .down, .pageUp, .pageDown:
            let rows = motion == .up || motion == .down ? 1 : max(1, plan.visibleHeightPx / max(1, plan.pitchPx) - 1)
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
        selectionState.selections = [CodeSelection(anchor: extend ? selection.anchor : target, head: target)]
        update { $0.goalX = goal; $0.goalXs = nil; $0.revealsCaret = true }
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

    /// Whether the bytes of `range` are all printable ASCII, so each is one column of a monospaced face (no tab, no
    /// combining mark, no wide scalar).
    private func isPlainASCII(_ range: Range<Int>, snap: CodeSnapshot) -> Bool {
        for byte in snap.utf8(in: range) where byte < 0x20 || byte > 0x7E { return false }
        return true
    }

    /// `caretX(_:snap:)` for many selections (`CV-BH`): on a line whose text up to the caret is plain ASCII the x is
    /// the column times the face's advance, which `layoutRow` would return for a monospaced face, so 10 000 carets
    /// shape nothing; any other line goes through `plan.layoutRow` (the layout cache serves the visible ones).
    func columnX(_ offset: Int, snap: CodeSnapshot) -> Double {
        let line = snap.lineRange(snap.point(at: offset).row)
        let column = offset - line.lowerBound
        if plan.spaceAdvance > 0, isPlainASCII(line.lowerBound..<min(offset + 1, line.upperBound), snap: snap) {
            return Double(column) * plan.spaceAdvance
        }
        return caretX(offset, snap: snap)
    }

    /// `offset(inRow:atX:)` for many selections (`CV-BH`): the column nearest `x` (ties to the lower, as
    /// `CodeLineLayout.byte(atX:)`) when the line up to it is plain ASCII, else the layout's.
    func offsetInRow(_ row: Int, atX x: Double, snap: CodeSnapshot) -> Int {
        let line = snap.lineRange(row)
        let advance = plan.spaceAdvance
        if advance > 0 {
            let columns = max(0, x) / advance
            var column = Int(columns.rounded(.down))
            if columns - Double(column) > 0.5 { column += 1 }
            column = min(column, line.count)
            if isPlainASCII(line.lowerBound..<min(line.lowerBound + column + 1, line.upperBound), snap: snap) {
                return line.lowerBound + column
            }
        }
        return offset(inRow: row, atX: x, snap: snap)
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

    /// What `deletion` removes at `selection`: the selection when it has a range, else the span the key names from
    /// the caret; `nil` when there is nothing to remove (a backspace at the start of the document).
    private func deletionRange(_ deletion: CodeDeletion, selection: CodeSelection, snap: CodeSnapshot) -> Range<Int>? {
        guard selection.isEmpty else { return selection.range }
        let head = selection.head
        let row = snap.point(at: head).row
        let line = snap.lineRange(row)
        let range: Range<Int>
        switch deletion {
        case .backward, .wordBackward:
            if head <= line.lowerBound {
                guard row > 0 else { return nil }
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
                guard row + 1 < snap.lineCount else { return nil }
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
        return range
    }

    /// A delete key over every selection (`CV-BH`): a range for each, the overlapping ones unioned, applied as one edit.
    private func delete(_ deletion: CodeDeletion, snap: CodeSnapshot) {
        let sels = selectionState.selections
        // Only a lone character delete at carets coalesces with its neighbours into one undo step.
        let coalesces = (deletion == .backward || deletion == .forward) && sels.allSatisfy(\.isEmpty)
        let ranges = sels.compactMap { deletionRange(deletion, selection: $0, snap: snap) }
        let edits = Self.union(ranges).map { (range: $0, text: "") }
        guard !edits.isEmpty else { return }
        selectionState.replaceEach(edits, origin: .deletion)
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

    /// The rows every selection touches, ascending and each once.
    private func touchedRows(snap: CodeSnapshot, selections: [CodeSelection]) -> [Int] {
        var rows: [Int] = []
        var next = 0   // the first row not yet listed
        for selection in selections {
            let touched = touchedRows(snap: snap, selection: selection)
            var row = max(touched.lowerBound, next)
            while row <= touched.upperBound { rows.append(row); row += 1 }
            next = max(next, touched.upperBound + 1)
        }
        return rows
    }

    private func indent(snap: CodeSnapshot) {
        let sels = selectionState.selections
        // Each selection within one row takes the indent unit at its start in place of its text; any selection over
        // several rows makes the whole command a line indent of every touched row (`CV-BH`).
        let inRow = sels.allSatisfy { selection in
            touchedRows(snap: snap, selection: selection).count == 1
                && (selection.isEmpty || snap.point(at: selection.range.lowerBound).row == snap.point(at: selection.range.upperBound).row)
        }
        if inRow {
            let texts = sels.map { selection -> String in
                let start = selection.range.lowerBound
                let line = snap.lineRange(snap.point(at: start).row)
                return indentText(forPrefix: snap.text(in: line.lowerBound..<start))
            }
            buffer.breakUndoCoalescing()
            selectionState.replaceSelections(withEach: texts, origin: .typing)
            buffer.breakUndoCoalescing()
            return
        }
        let unit = indentUsingSpaces ? String(repeating: " ", count: tabColumns) : "\t"
        var edits: [(range: Range<Int>, text: String)] = []
        for row in touchedRows(snap: snap, selections: sels) {
            let line = snap.lineRange(row)
            // Blank lines are left as they are, as editors do.
            if !line.isEmpty { edits.append((line.lowerBound..<line.lowerBound, unit)) }
        }
        selectionState.replaceEach(edits, origin: .programmatic)
    }

    private func outdent(snap: CodeSnapshot) {
        var edits: [(range: Range<Int>, text: String)] = []
        for row in touchedRows(snap: snap, selections: selectionState.selections) {
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
            if remove > 0 { edits.append((line.lowerBound..<(line.lowerBound + remove), "")) }
        }
        selectionState.replaceEach(edits, origin: .programmatic)
    }
}
