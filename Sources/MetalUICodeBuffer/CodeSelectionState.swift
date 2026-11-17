import Observation

/// One view's selections over a `CodeBuffer` (`CV-AV`). A buffer holds its states weakly and moves every
/// live one on every edit, so two views of one buffer can each have a caret. The buffer's own
/// `selections`, `select(_:reveal:)` and friends are the **default state**, `CodeBuffer.selectionState`;
/// a view with no state of its own uses that one.
///
/// Edits made through a state make it the *acting state*: its selections are recorded in the undo step, it
/// keeps its caret after typed or pasted text, and typing coalesces per state. Every other state follows the
/// text by the AppKit rule (`CV-AW`). `undo()` and `redo()` write the step's selections into the state
/// that called them (`CV-AX`).
@MainActor @Observable
public final class CodeSelectionState {
    @ObservationIgnored private weak var weakBuffer: CodeBuffer?
    @ObservationIgnored private var retainedBuffer: CodeBuffer?
    @ObservationIgnored var stored = [CodeSelection(caret: 0)]
    @ObservationIgnored var storedPrimary = 0
    /// The fold states over this state (`CV-BL`); an explicit selection write opens the folds hiding its ends.
    @ObservationIgnored var folds: [WeakFold] = []

    /// Rises each time the stored selections or the primary change (`CV-BG`): what a view compares to restart its
    /// caret blink when any selection moved, where comparing the array would cost O(n) a frame. Never observed.
    @ObservationIgnored package private(set) var mutationSerial: UInt64 = 0

    /// The most selections a helper (add next occurrence, select all occurrences, a column selection) will
    /// make (`CV-BE`). Assigning more is not refused.
    public static let selectionLimit = 10_000

    /// What runs, once, after an edit made through another state completes (`CV-AZ`): a view with marked text
    /// registers one to commit it. Keyed by the view; empty unless an input method is composing, so a frame never
    /// reads it.
    @ObservationIgnored package var foreignEditHandlers: [AnyHashable: @MainActor () -> Void] = [:]

    /// Rises each time `select(_:reveal:)` asks views to scroll this selection into view.
    public private(set) var revealSerial: UInt64 = 0

    /// Rises each time a selection helper (`addNextOccurrence()`, `addCaret(lineDelta:)`, ...) asks views to
    /// scroll the primary selection into view by the **least** distance, not centred (`CV-BJ`, `CV-X`'s rule).
    package private(set) var nearestRevealSerial: UInt64 = 0

    /// The visible column `addCaret(lineDelta:)` aims for, kept across short lines; `nil` once any other selection
    /// write or edit moved the selections (`CV-BJ`). Never observed.
    @ObservationIgnored package var goalColumn: Int?
    /// The `mutationSerial` the last helper left, while the selections are still the word it selected: the next
    /// add searches whole words only (`CV-BJ`).
    @ObservationIgnored private var wordSearchSerial: UInt64?

    /// The `revealSerial` a view has last taken in, and the frame it did so in (`CV-BA`): a view mounting with
    /// `revealSerial` ahead of this, or in that same frame, honours the reveal on its first laid-out frame; any
    /// later mount finds it handled and starts at the top. Never observed: writing it wakes nothing.
    @ObservationIgnored package var revealHandledSerial: UInt64 = 0
    @ObservationIgnored package weak var revealHandledFrame: AnyObject?

    /// A state over `buffer`, selecting `selections` (clamped, sorted and merged; at least one). The buffer
    /// holds it weakly: keep the state alive as long as the view uses it.
    public init(buffer: CodeBuffer, selections: [CodeSelection] = [CodeSelection(caret: 0)]) {
        retainedBuffer = buffer
        weakBuffer = buffer
        (stored, storedPrimary) = CodeBuffer.normalize(selections, limit: buffer.rope.summary.utf8, primary: 0)
        buffer.register(self)
    }

    /// The buffer's own state: it does not retain the buffer, which retains it.
    init(defaultFor buffer: CodeBuffer) {
        weakBuffer = buffer
        buffer.register(self)
    }

    /// The buffer this state selects in.
    public var buffer: CodeBuffer { retainedBuffer ?? weakBuffer! }

    /// The selections, sorted and merged: no two overlap and no two carets coincide, at least one. An
    /// edit moves them; assigning replaces them, makes the input's **first** element the primary
    /// (`CV-BE`, tracked through sorting and merging) and ends undo coalescing.
    public var selections: [CodeSelection] {
        get { access(keyPath: \.selections); return stored }
        set { setSelections(newValue, primary: 0) }
    }

    /// Replaces the selections like assigning `selections`, but makes `selections[primary]` (of the input,
    /// before sorting) the primary (`CV-BE`). An out-of-range `primary` is clamped.
    public func setSelections(_ selections: [CodeSelection], primary: Int) {
        let buffer = buffer
        let p = selections.isEmpty ? 0 : min(max(primary, 0), selections.count - 1)
        withMutation(keyPath: \.selections) {
            (stored, storedPrimary) = CodeBuffer.normalize(selections, limit: buffer.rope.summary.utf8, primary: p)
            mutationSerial &+= 1
        }
        goalColumn = nil
        buffer.breakUndoCoalescing()
        openFolds()
    }

    /// The index in `selections` of the primary selection: the one assigned first, or the one an edit
    /// merged it into (`CV-BE`). Always a valid index.
    public var primaryIndex: Int { access(keyPath: \.selections); return storedPrimary }

    /// The primary selection, which views reveal and move; `selections[primaryIndex]` (`CV-BE`).
    public var primarySelection: CodeSelection { access(keyPath: \.selections); return stored[storedPrimary] }

    /// Selects `range` (anchor at its start, head at its end), ending undo coalescing. With `reveal`, the
    /// views using this state scroll it into view: they observe `revealSerial`.
    public func select(_ range: Range<Int>, reveal: Bool = true) {
        selections = [CodeSelection(anchor: range.lowerBound, head: range.upperBound)]
        if reveal { revealSerial &+= 1 }
    }

    /// Replaces every selection of this state with `text`, leaving a caret after each insertion; what
    /// typing and pasting do. This state is the acting state.
    @discardableResult
    public func replaceSelections(with text: String, origin: CodeEditOrigin = .typing) -> CodeTransactionID {
        let buffer = buffer
        return buffer.asActing(self) { buffer.performReplaceSelections(with: text, origin: origin) }
    }

    /// Replaces selection `i` (in `selections` order) with `texts[i]`, all as one edit, leaving a caret after
    /// each insertion and keeping the primary; what a paste of as many lines as selections does (`CV-BE`).
    /// Typing-origin calls coalesce like `replaceSelections(with:)`. This state is the acting state.
    /// `texts.count` must equal `selections.count`.
    @discardableResult
    public func replaceSelections(withEach texts: [String], origin: CodeEditOrigin = .paste) -> CodeTransactionID {
        let buffer = buffer
        return buffer.asActing(self) { buffer.performReplaceSelections(withEach: texts, origin: origin) }
    }

    /// Replaces each of `edits` (ascending, non-overlapping, in the current text's coordinates) as one
    /// batched edit (`CV-BF`); the sequential equivalent is `replace` highest first inside a transaction.
    @discardableResult
    package func replaceBatch(_ edits: [(range: Range<Int>, text: String)], origin: CodeEditOrigin) -> CodeTransactionID {
        let buffer = buffer
        return buffer.asActing(self) { buffer.performTransaction { $0.applyBatchInTransaction(edits, origin: origin) } }
    }

    /// `CodeBuffer.replace(_:with:origin:)` with this state as the acting state.
    @discardableResult
    public func replace(_ range: Range<Int>, with text: String, origin: CodeEditOrigin = .programmatic) -> CodeTransactionID {
        let buffer = buffer
        return buffer.asActing(self) { buffer.performReplace(range, with: text, origin: origin) }
    }

    /// `CodeBuffer.transaction(_:)` with this state as the acting state: its selections are the step's.
    @discardableResult
    public func transaction(_ body: (CodeBuffer) -> Void) -> CodeTransactionID {
        let buffer = buffer
        return buffer.asActing(self) { buffer.performTransaction(body) }
    }

    /// Reverts the buffer's latest undo step (one stack per buffer) and puts the step's before-selections
    /// into **this** state, whichever state made the edit; every other state follows the text. Returns
    /// whether anything was reverted.
    @discardableResult
    public func undo() -> Bool {
        let buffer = buffer
        return buffer.asActing(self) { buffer.performUndo() }
    }

    /// Reapplies the step `undo()` reverted and puts the step's after-selections into this state.
    @discardableResult
    public func redo() -> Bool {
        let buffer = buffer
        return buffer.asActing(self) { buffer.performRedo() }
    }

    /// Replaces the selections without ending coalescing or revealing (a buffer moving a state over an
    /// edit). A state whose selections did not change is not mutated, so its observers do not wake; the
    /// default state is the exception and is always mutated, as the buffer's selection was before states
    /// existed (`versionAndSelectionsAreObservable` pins it).
    func setInternal(_ new: [CodeSelection], primary: Int? = nil, normalizing: Bool = true) {
        if !normalizing {
            // A run of edits moving the selections event by event: they are normalised once, after the last (`CV-BF`).
            withMutation(keyPath: \.selections) { stored = new; mutationSerial &+= 1 }
            return
        }
        let (normalized, p) = CodeBuffer.normalize(new, limit: buffer.rope.summary.utf8, primary: min(primary ?? storedPrimary, max(new.count - 1, 0)))
        guard normalized != stored || p != storedPrimary || retainedBuffer == nil else { return }
        withMutation(keyPath: \.selections) { stored = normalized; storedPrimary = p; mutationSerial &+= 1 }
        goalColumn = nil
    }

    // MARK: Selection helpers (`CV-BJ`)

    /// Whether `range` overlaps a selection of this state other than index `ignoring`.
    private func isSelected(_ range: Range<Int>, ignoring: Int? = nil) -> Bool {
        var lo = 0, hi = stored.count   // the first selection ending after `range` starts (selections are sorted and disjoint)
        while lo < hi {
            let mid = (lo + hi) / 2
            if stored[mid].range.upperBound > range.lowerBound { hi = mid } else { lo = mid + 1 }
        }
        var i = lo
        while i < stored.count, stored[i].range.lowerBound <= range.upperBound {
            if i != ignoring {
                let r = stored[i].range
                if r.lowerBound < range.upperBound && range.lowerBound < r.upperBound || r == range { return true }
            }
            i += 1
        }
        return false
    }

    /// The text and options the next occurrence search uses: the primary's text exactly (case-sensitive), or the
    /// word at a caret / a word the last helper selected, whole-word. `nil` when there is nothing to search for.
    private func occurrenceQuery(_ snapshot: CodeSnapshot) -> (range: Range<Int>, wordSelected: Bool, query: String, options: CodeFindOptions)? {
        let p = stored[storedPrimary]
        if p.isEmpty {
            guard let word = snapshot.wordRange(at: p.head) else { return nil }
            return (word, true, snapshot.text(in: word), [.wholeWord])
        }
        let whole = wordSearchSerial == mutationSerial
        return (p.range, false, snapshot.text(in: p.range), whole ? [.wholeWord] : [])
    }

    private func finishHelper(_ selections: [CodeSelection], primary: Int, wordSearch: Bool) {
        setSelections(selections, primary: primary)
        wordSearchSerial = wordSearch ? mutationSerial : nil
        nearestRevealSerial &+= 1
    }

    /// Adds the next occurrence of the primary selection's text as a selection and makes it the primary (⌘D,
    /// `CV-BJ`). With a caret, selects the word there instead (the find engine's `.wholeWord` word), and later calls
    /// add whole-word matches; with a non-empty selection, matches its text exactly and case-sensitively. Searches
    /// from the end of the primary, wrapping, skipping ranges already selected; no match or no word changes
    /// nothing. Undo-neutral; views reveal the new primary with the least scroll. Returns `false` only when
    /// `limit` selections already exist.
    @discardableResult
    public func addNextOccurrence(limit: Int = CodeSelectionState.selectionLimit) -> Bool {
        guard stored.count < limit else { return false }
        let snapshot = buffer.snapshot()
        guard let q = occurrenceQuery(snapshot) else { return true }
        if q.wordSelected {
            var next = stored
            next[storedPrimary] = CodeSelection(anchor: q.range.lowerBound, head: q.range.upperBound)
            finishHelper(next, primary: storedPrimary, wordSearch: true)
            return true
        }
        let wholeWord = q.options.contains(.wholeWord)
        guard let match = snapshot.firstRange(of: q.query, options: q.options, from: q.range.upperBound, accept: { !self.isSelected($0) }) else { return true }
        finishHelper(stored + [CodeSelection(anchor: match.lowerBound, head: match.upperBound)], primary: stored.count, wordSearch: wholeWord)
        return true
    }

    /// Drops the primary selection and adds the next occurrence in its place, as ``addNextOccurrence(limit:)``
    /// searches (⌘K ⌘D, `CV-BJ`). With a caret it selects the word, like ⌘D. Never grows the selection count.
    @discardableResult
    public func skipToNextOccurrence() -> Bool {
        let snapshot = buffer.snapshot()
        guard let q = occurrenceQuery(snapshot) else { return true }
        if q.wordSelected { return addNextOccurrence() }
        let primary = storedPrimary
        let match = snapshot.firstRange(of: q.query, options: q.options, from: q.range.upperBound,
                                        accept: { !self.isSelected($0, ignoring: primary) }) ?? q.range
        var next = stored
        next[primary] = CodeSelection(anchor: match.lowerBound, head: match.upperBound)
        finishHelper(next, primary: primary, wordSearch: q.options.contains(.wholeWord))
        return true
    }

    /// Selects every occurrence of the primary selection's text (⌘⇧L, `CV-BJ`), searched as
    /// ``addNextOccurrence(limit:)`` does, replacing the other selections; the primary stays on its own match.
    /// Returns `false` when there are more than `limit` matches: the first `limit` are selected.
    @discardableResult
    public func selectAllOccurrences(limit: Int = CodeSelectionState.selectionLimit) -> Bool {
        let snapshot = buffer.snapshot()
        guard let q = occurrenceQuery(snapshot) else { return true }
        let all = snapshot.ranges(of: q.query, options: q.options, limit: max(limit, 0) + 1)
        let capped = all.count > limit
        let matches = capped ? Array(all.prefix(max(limit, 0))) : all
        guard !matches.isEmpty else { return !capped }
        let primary = matches.firstIndex { $0.lowerBound >= q.range.lowerBound } ?? 0
        finishHelper(matches.map { CodeSelection(anchor: $0.lowerBound, head: $0.upperBound) }, primary: primary,
                     wordSearch: q.options.contains(.wholeWord))
        return !capped
    }

    /// Adds a caret `lineDelta` lines from the primary selection's head, at its visible column (graphemes, a tab
    /// counting to the next multiple of `tabWidth`), and makes it the primary (⌥⌘↑ / ⌥⌘↓, `CV-BJ`). The column
    /// is kept in `goalColumn` across short lines until another selection write. Rows hidden by a registered
    /// ``CodeFoldState`` are passed over; a target outside the text changes nothing. Returns `false` only when
    /// `selectionLimit` selections already exist.
    @discardableResult
    public func addCaret(lineDelta: Int, tabWidth: Int = 4, limit: Int = CodeSelectionState.selectionLimit) -> Bool {
        guard stored.count < limit else { return false }
        guard lineDelta != 0 else { return true }
        let snapshot = buffer.snapshot()
        let tab = max(tabWidth, 1)
        let head = min(stored[storedPrimary].head, snapshot.utf8Count)
        let row = snapshot.point(at: head).row
        var target = row + lineDelta
        let step = lineDelta > 0 ? 1 : -1
        func hidden(_ r: Int) -> Bool { folds.contains { $0.state?.isHidden(line: r) == true } }
        while target >= 0, target < snapshot.lineCount, hidden(target) { target += step }
        guard target >= 0, target < snapshot.lineCount else { return true }
        let start = snapshot.lineRange(row).lowerBound
        let goal = goalColumn ?? Self.visibleColumn(of: snapshot.text(in: start..<head), tabWidth: tab)
        let line = snapshot.lineRange(target)
        let offset = line.lowerBound + Self.byteOffset(ofColumn: goal, in: snapshot.text(in: line), tabWidth: tab)
        setSelections(stored + [CodeSelection(caret: offset)], primary: stored.count)
        goalColumn = goal
        wordSearchSerial = nil
        nearestRevealSerial &+= 1
        return true
    }

    /// Keeps only the primary selection (Escape, `CV-BJ`). Undo-neutral.
    public func collapseToPrimary() {
        setSelections([stored[storedPrimary]], primary: 0)
    }

    /// The visible column after `text`: one per grapheme, a tab advancing to the next multiple of `tabWidth`.
    package static func visibleColumn(of text: String, tabWidth: Int) -> Int {
        var column = 0
        for c in text { column = c == "\t" ? (column / tabWidth + 1) * tabWidth : column + 1 }
        return column
    }

    /// The byte offset in `line` of the boundary nearest visible column `column` (clamped to the line's end).
    package static func byteOffset(ofColumn column: Int, in line: String, tabWidth: Int) -> Int {
        var col = 0, bytes = 0
        for c in line {
            let next = c == "\t" ? (col / tabWidth + 1) * tabWidth : col + 1
            if next > column { return column - col > next - column ? bytes + c.utf8.count : bytes }
            col = next
            bytes += c.utf8.count
        }
        return bytes
    }
}
