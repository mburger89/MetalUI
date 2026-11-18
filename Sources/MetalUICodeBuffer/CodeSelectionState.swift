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

    /// The running snippet, `nil` when none (`CV-BQ`). Every edit moves it in the pass that moves the selections.
    @ObservationIgnored package var snippet: SnippetSession? {
        didSet { if (snippet != nil) != isSnippetActive { isSnippetActive = snippet != nil } }
    }
    /// The columns of the indent unit of the view showing this state, 0 for a tab: the view writes it each time it
    /// builds its plan, and a snippet inserted with no `indentUnit` reads it (`CV-BQ`). Never observed.
    @ObservationIgnored package var viewIndentSpaces = 0
    /// Whether a snippet session is running: Tab and Shift-Tab step its placeholders, Escape ends it, and a view
    /// tints the placeholders (`CV-BQ`). Observable.
    public internal(set) var isSnippetActive = false

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
        if snippet != nil { reconcileSnippetAfterWrite() }
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

    /// Replaces each of `edits` (ascending, non-overlapping, in the current text's coordinates) as one edit
    /// that coalesces by its `origin` like a keystroke's (`CV-BH`): the deletion of several carets is one undo
    /// step, and the next deletion joins it. Unlike `replaceBatch` it is not wrapped in a transaction.
    @discardableResult
    package func replaceEach(_ edits: [(range: Range<Int>, text: String)], origin: CodeEditOrigin) -> CodeTransactionID {
        let buffer = buffer
        return buffer.asActing(self) { buffer.performEdits(edits, origin: origin) }
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

    /// Whether a registered ``CodeFoldState`` hides buffer row `line` (`CV-BK`: a column drag passes hidden rows over).
    package func isFoldHidden(line: Int) -> Bool { folds.contains { $0.state?.isHidden(line: line) == true } }

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

// MARK: Snippets (`CV-BQ`)

extension CodeSelectionState {
    /// Inserts `snippet` in place of `range` as one undo step and starts a session at its first placeholder
    /// (`CV-BQ`): the selections become that placeholder's ranges (every mirror of it), and Tab and Shift-Tab in a
    /// ``CodeView`` step through the stops. This state is the acting state. A session already running ends first.
    ///
    /// Each line after the first takes the leading whitespace of the line the insertion starts on (up to the
    /// insertion). With `indentUnit` (or, when `nil`, the unit of the view showing this state: its tab, or its
    /// ``CodeView/tabWidth(_:)`` spaces under ``CodeView/indentUsingSpaces(_:)``), each leading tab of the
    /// snippet's own lines becomes that unit. Line breaks in the snippet become the buffer's. A snippet with
    /// only the final stop starts no session: the caret goes there. Nothing happens on a read-only buffer.
    ///
    /// - Returns: the transaction of the insertion.
    @discardableResult
    public func insertSnippet(_ snippet: CodeSnippet, replacing range: Range<Int>, indentUnit: String? = nil) -> CodeTransactionID {
        endSnippet()
        let buffer = buffer
        let snap = buffer.snapshot()
        let line = snap.lineRange(snap.point(at: range.lowerBound).row)
        let lead = String(snap.text(in: line.lowerBound..<min(range.lowerBound, line.upperBound))
            .utf8.prefix { $0 == 0x20 || $0 == 0x09 }.map { Character(Unicode.Scalar($0)) })
        let unit = indentUnit ?? (viewIndentSpaces > 0 ? String(repeating: " ", count: viewIndentSpaces) : nil)
        let (text, stops) = Self.adjusted(snippet, indent: lead, unit: unit, ending: buffer.lineEnding.text)
        let base = range.lowerBound
        var tx = CodeTransactionID(rawValue: 0)
        var started: SnippetSession?
        transaction { buf in
            tx = buf.replace(range, with: text, origin: .programmatic)
            guard !buf.isReadOnly else { return }
            let absolute = stops.map { (index: $0.index, range: ($0.range.lowerBound + base)..<($0.range.upperBound + base)) }
            let session = SnippetSession(stops: absolute, transaction: tx)
            // Only the final stop: no session, the caret goes there.
            placeSnippetSelections(session.ranges(of: session.current))
            if session.current != 0 { started = session }
        }
        if let started { self.snippet = started }
        return tx
    }

    /// Moves to the next placeholder of the running snippet and selects it (every mirror of it): Tab in a view.
    /// Reaching the final stop places the caret there and ends the session. Undo-neutral. Returns `false` when no
    /// session is running.
    @discardableResult
    public func nextSnippetPlaceholder() -> Bool {
        guard var session = snippet else { return false }
        guard let next = session.nextGroup() else { endSnippet(); return true }
        session.setCurrent(next)
        placeSnippetSelections(session.ranges(of: next))
        snippet = next == 0 ? nil : session   // the final stop ends the session
        return true
    }

    /// Moves to the previous placeholder and selects it: Shift-Tab in a view. Returns `false`, changing nothing,
    /// when no session is running or the current placeholder is the first (the key then outdents).
    @discardableResult
    public func previousSnippetPlaceholder() -> Bool {
        guard var session = snippet, let previous = session.previousGroup() else { return false }
        session.setCurrent(previous)
        placeSnippetSelections(session.ranges(of: previous))
        snippet = session
        return true
    }

    /// Ends the running snippet and keeps the selections: Escape in a view. The text stays as it is.
    public func endSnippet() {
        if snippet != nil { snippet = nil }
    }

    /// Selects `ranges` as the selections (the first the primary) without ending the session, ending undo
    /// coalescing and asking views to reveal the primary.
    private func placeSnippetSelections(_ ranges: [Range<Int>]) {
        let limited = ranges.prefix(Self.selectionLimit).map { CodeSelection(anchor: $0.lowerBound, head: $0.upperBound) }
        let limit = buffer.rope.summary.utf8
        withMutation(keyPath: \.selections) {
            (stored, storedPrimary) = CodeBuffer.normalize(limited, limit: limit, primary: 0)
            mutationSerial &+= 1
        }
        goalColumn = nil
        buffer.breakUndoCoalescing()
        openFolds()
        nearestRevealSerial &+= 1
    }

    /// After an explicit selection write (a press, a motion, any assignment): the session ends when a selection
    /// is outside every placeholder, bounds included; otherwise the current group follows the primary.
    private func reconcileSnippetAfterWrite() {
        guard var session = snippet else { return }
        for selection in stored where !session.contains(selection.range) {
            snippet = nil
            return
        }
        let primary = stored[storedPrimary].range
        if let at = session.innermost(containing: primary), session.placeholders[at].index != session.current,
           !session.placeholders.contains(where: { $0.index == session.current && !$0.removed && $0.range.lowerBound <= primary.lowerBound && primary.upperBound <= $0.range.upperBound }) {
            let group = session.placeholders[at].index
            if group == 0 { snippet = nil; return }
            session.setCurrent(group)
            snippet = session
        }
    }

    /// Moves the running snippet over one edit; the one call the buffer makes per state per event.
    func moveSnippet(start: Int, end: Int, newLength: Int) {
        snippet!.move(start: start, end: end, newLength: newLength)
    }

    /// The snippet with its text adjusted to the insertion: every line after the first prefixed with `indent`, a
    /// leading tab of any line after the first replaced by `unit`, line breaks as `ending`; and each stop's range
    /// mapped into the adjusted text. A snippet with no final stop gets one at its end.
    static func adjusted(_ snippet: CodeSnippet, indent: String, unit: String?, ending: String) -> (String, [CodeSnippet.TabStop]) {
        let src = Array(snippet.text.utf8)
        let n = src.count
        let indentBytes = Array(indent.utf8), unitBytes = unit.map { Array($0.utf8) }, endingBytes = Array(ending.utf8)
        var out: [UInt8] = []
        out.reserveCapacity(n + 16)
        var startMap = [Int](repeating: 0, count: n + 1), endMap = [Int](repeating: 0, count: n + 1)
        var i = 0
        var atLineStart = true, first = true, justStarted = false
        while i <= n {
            if atLineStart {
                atLineStart = false
                endMap[i] = out.count
                if !first { out.append(contentsOf: indentBytes) }
                startMap[i] = out.count
                var j = i
                while j < n, src[j] == 0x20 || src[j] == 0x09 {
                    if j > i { startMap[j] = out.count; endMap[j] = out.count }
                    if src[j] == 0x09, !first, let unitBytes { out.append(contentsOf: unitBytes) } else { out.append(src[j]) }
                    j += 1
                }
                if j > i { startMap[j] = out.count; endMap[j] = out.count }
                i = j
                justStarted = true
                continue
            }
            if !justStarted { startMap[i] = out.count; endMap[i] = out.count }
            justStarted = false
            if i == n { break }
            if src[i] == 0x0A {
                out.append(contentsOf: endingBytes)
                i += 1
                atLineStart = true
                first = false
            } else {
                out.append(src[i])
                i += 1
            }
        }
        var stops = snippet.tabStops.map { stop -> CodeSnippet.TabStop in
            let lo = startMap[stop.range.lowerBound]
            let hi = stop.range.isEmpty ? lo : max(lo, endMap[stop.range.upperBound])
            return CodeSnippet.TabStop(index: stop.index, range: lo..<hi)
        }
        if !stops.contains(where: { $0.index == 0 }) { stops.append(.init(index: 0, range: out.count..<out.count)) }
        return (String(decoding: out, as: UTF8.self), stops)
    }
}
