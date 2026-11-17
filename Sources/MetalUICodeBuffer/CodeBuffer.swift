import Observation

/// One reversible step: replace `range` (in the text just after the step it undoes) with `text`.
struct CodeInverse: Equatable {
    var range: Range<Int>
    var text: String

    /// The inverse of two consecutive steps of one kind as a single step, when they are adjacent.
    static func merged(_ previous: CodeInverse, _ next: CodeInverse, kind: CodeCoalesceKind) -> CodeInverse? {
        switch kind {
        case .typing:
            // The second removes text typed right after the first insertion (or after the text the first
            // replaced), so the pair is one replacement of the first's span plus the second's.
            guard next.text.isEmpty, previous.range.upperBound == next.range.lowerBound else { return nil }
            return CodeInverse(range: previous.range.lowerBound..<next.range.upperBound, text: previous.text)
        case .deletion:
            // Both reinsert deleted text at a point.
            guard previous.range.isEmpty, next.range.isEmpty else { return nil }
            let p = previous.range.lowerBound, n = next.range.lowerBound
            if n + next.text.utf8.count == p { return CodeInverse(range: n..<n, text: next.text + previous.text) } // backspace
            if n == p { return CodeInverse(range: p..<p, text: previous.text + next.text) } // forward delete
            return nil
        }
    }
}

enum CodeCoalesceKind { case typing, deletion }

/// An undo step: the inverse of one transaction (or a run of coalesced typing) and the selections to
/// restore on either side of it.
struct CodeUndoGroup {
    var id: CodeTransactionID
    /// Chronological: the step that undid the first edit comes first; undo applies them last to first.
    var inverse: [CodeInverse]
    var undoSelections: [CodeSelection]
    var redoSelections: [CodeSelection]
    /// The primary's index in each side's selections (`CV-BE`).
    var undoPrimary = 0
    var redoPrimary = 0

    var bytes: Int { inverse.reduce(64) { $0 + $1.text.utf8.count + 16 } }
}

private struct WeakCursor {
    weak var cursor: CodeEditCursor?
}

private struct WeakSelectionState {
    weak var state: CodeSelectionState?
}

/// A text buffer for code: a copy-on-write rope of UTF-8 chunks with snapshots, an edit stream, undo,
/// selections, external edits and a find engine (`CV-A`..`CV-H`).
///
/// All offsets are UTF-8 byte offsets. Every edit is reported to the observers of `version`, to cursors
/// and to the `map` log in the coordinates of the text just before it. The buffer is main-actor
/// isolated; read it from another thread through `snapshot()`, which is `Sendable`.
@MainActor @Observable
public final class CodeBuffer {
    /// The number of edit events so far. It rises by exactly 1 per event and is observable.
    public private(set) var version: UInt64 = 0
    /// Rises each time `select(_:reveal:)` asks views to scroll the selection into view. This is the
    /// default state's serial (`selectionState`).
    public var revealSerial: UInt64 { selectionState.revealSerial }
    /// The line ending Return inserts; detected from the text at creation.
    public var lineEnding: CodeLineEnding = .lf
    /// Whether the buffer refuses edits. A read-only buffer still selects and snapshots.
    public var isReadOnly = false
    /// Whether the bytes given to `init(utf8:)` were not valid UTF-8 (invalid sequences became U+FFFD).
    /// An app can refuse to save such a file.
    public let hadInvalidUTF8: Bool
    /// The most bytes of text the undo stack keeps; the oldest steps go first.
    @ObservationIgnored public var undoByteLimit = 8 << 20

    @ObservationIgnored var rope: Rope
    /// The built-in selection state; the buffer's own selection API forwards to it (`CV-AV`).
    @ObservationIgnored public lazy var selectionState = CodeSelectionState(defaultFor: self)
    @ObservationIgnored private var selectionStates: [WeakSelectionState] = []
    /// The state whose API call is running an edit (`nil` outside one and during external edits).
    @ObservationIgnored private weak var acting: CodeSelectionState?
    @ObservationIgnored private weak var openState: CodeSelectionState?
    /// How many states edit events have moved so far, summed over events (one per live state per event).
    @ObservationIgnored package private(set) var stateMoveCount = 0
    /// Test hook: move states event by event, as before batching (`CV-BF`), so a batched result can be
    /// compared with the sequential one.
    @ObservationIgnored package var sequentialMoves = false
    /// How many states are alive and registered (the default state included).
    @ObservationIgnored package var registeredStateCount: Int { selectionStates.count }
    @ObservationIgnored package var liveStateCount: Int { selectionStates.reduce(0) { $0 + ($1.state == nil ? 0 : 1) } }
    @ObservationIgnored private var nextTransaction: UInt64 = 0
    @ObservationIgnored private var transactionDepth = 0
    @ObservationIgnored private var currentTransaction = CodeTransactionID(rawValue: 0)
    @ObservationIgnored private var building: CodeUndoGroup?
    @ObservationIgnored private(set) var undoStack: [CodeUndoGroup] = []
    @ObservationIgnored private(set) var redoStack: [CodeUndoGroup] = []
    @ObservationIgnored private var openKind: CodeCoalesceKind?
    @ObservationIgnored private var log: [CodeEdit] = []
    @ObservationIgnored private var logHead = 0
    @ObservationIgnored private var logBase: UInt64 = 0
    @ObservationIgnored private var logBytes = 0
    @ObservationIgnored private var cursors: [WeakCursor] = []
    /// The most bytes of inserted text the edit log keeps for lagging cursors (`CV-E`).
    @ObservationIgnored package var editLogByteLimit = 4 << 20
    /// The log keeps at least this many recent events when the byte limit allows, so `map` reaches back
    /// a little even with no cursor alive.
    @ObservationIgnored package var editLogMinimumEvents = 256

    // MARK: Creation

    /// A buffer holding `text`. O(n).
    public init(_ text: String = "") {
        let built = Self.build(text)
        rope = built.0
        lineEnding = built.1
        hadInvalidUTF8 = false
    }

    /// A buffer holding `bytes` read as UTF-8. O(n). Invalid sequences are repaired to U+FFFD and
    /// `hadInvalidUTF8` is set.
    public init(utf8 bytes: some Collection<UInt8>) {
        let array = Array(bytes)
        let valid = array.withUnsafeBufferPointer { Self.isValidUTF8($0) }
        let source = valid ? array : Array(String(decoding: array, as: UTF8.self).utf8)
        let built = Self.build(bytes: source)
        rope = built.0
        lineEnding = built.1
        hadInvalidUTF8 = !valid
    }

    /// The rope and line ending of `text`. `nonisolated` so the closures are not main-actor closures: a model built
    /// off the main thread (the demo stack-budget test builds trees on a 1 MB thread) would trap on their
    /// dynamic isolation check.
    private nonisolated static func build(_ text: String) -> (Rope, CodeLineEnding) {
        var t = text
        return t.withUTF8 { (Rope(bytes: $0), detectLineEnding($0)) }
    }

    private nonisolated static func build(bytes: [UInt8]) -> (Rope, CodeLineEnding) {
        bytes.withUnsafeBufferPointer { (Rope(bytes: $0), detectLineEnding($0)) }
    }

    private nonisolated static func isValidUTF8(_ p: UnsafeBufferPointer<UInt8>) -> Bool {
        var iterator = p.makeIterator()
        var decoder = UTF8()
        while true {
            switch decoder.decode(&iterator) {
            case .scalarValue: continue
            case .emptyInput: return true
            case .error: return false
            }
        }
    }

    private nonisolated static func detectLineEnding(_ p: UnsafeBufferPointer<UInt8>) -> CodeLineEnding {
        for i in p.indices where p[i] == 0x0A { return i > 0 && p[i - 1] == 0x0D ? .crlf : .lf }
        return .lf
    }

    // MARK: Reading

    /// The number of bytes.
    public var utf8Count: Int { access(keyPath: \.version); return rope.summary.utf8 }
    /// The number of lines: one more than the number of `\n`.
    public var lineCount: Int { access(keyPath: \.version); return rope.summary.newlines + 1 }

    /// An immutable copy of the text as of now. O(1), `Sendable`, unaffected by later edits.
    public func snapshot() -> CodeSnapshot {
        access(keyPath: \.version)
        return CodeSnapshot(rope: rope, version: version)
    }

    // MARK: Selections

    /// The selections, sorted and merged: no two overlap and no two carets coincide. An edit moves them
    /// (`CV-D`); assigning replaces them and ends undo coalescing. A buffer always has at least one. These
    /// are the default state's (`selectionState`, `CV-AV`).
    public var selections: [CodeSelection] {
        get { selectionState.selections }
        set { selectionState.selections = newValue }
    }

    /// The primary selection, which views reveal and move (`CV-BE`).
    public var primarySelection: CodeSelection { selectionState.primarySelection }

    /// Replaces selection `i` with `texts[i]` as one edit (`CodeSelectionState.replaceSelections(withEach:origin:)`).
    @discardableResult
    public func replaceSelections(withEach texts: [String], origin: CodeEditOrigin = .paste) -> CodeTransactionID {
        asActing(actor) { performReplaceSelections(withEach: texts, origin: origin) }
    }

    /// Selects `range` (anchor at its start, head at its end), ending undo coalescing. With `reveal`, views
    /// scroll the selection into view: they observe `revealSerial`.
    public func select(_ range: Range<Int>, reveal: Bool = true) {
        selectionState.select(range, reveal: reveal)
    }

    /// Ends the current run of coalesced typing or deletion, so the next edit is its own undo step.
    public func breakUndoCoalescing() { openKind = nil; openState = nil }

    func register(_ state: CodeSelectionState) { selectionStates.append(WeakSelectionState(state: state)) }

    /// Runs `body` with `state` as the acting state (the one whose selections an edit records, sticks and
    /// coalesces by), restoring the previous one after.
    func asActing<T>(_ state: CodeSelectionState, _ body: () -> T) -> T {
        let previous = acting
        let before = version
        acting = state
        let result = body()
        acting = previous
        // After the outermost edit, every other state with a composing view commits it (`CV-AZ`).
        if previous == nil, version != before { notifyForeignEdit(by: state) }
        return result
    }

    private func notifyForeignEdit(by state: CodeSelectionState) {
        var due: [@MainActor () -> Void] = []
        for entry in selectionStates {
            guard let other = entry.state, other !== state, !other.foreignEditHandlers.isEmpty else { continue }
            due.append(contentsOf: other.foreignEditHandlers.values)
        }
        for handler in due { handler() }
    }

    private var actor: CodeSelectionState { acting ?? selectionState }

    nonisolated static func normalize(_ input: [CodeSelection], limit: Int) -> [CodeSelection] {
        normalize(input, limit: limit, primary: 0).0
    }

    /// Clamps, sorts and merges `input`, and returns where `input[primary]` ended up (`CV-BE`).
    nonisolated static func normalize(_ input: [CodeSelection], limit: Int, primary: Int) -> ([CodeSelection], Int) {
        var xs = input.map { CodeSelection(anchor: max(0, min($0.anchor, limit)), head: max(0, min($0.head, limit))) }
        if xs.isEmpty { return ([CodeSelection(caret: 0)], 0) }
        func joins(_ x: CodeSelection, _ last: CodeSelection) -> Bool {
            x.range.lowerBound < last.range.upperBound || (x.range.lowerBound == last.range.upperBound && (x.isEmpty || last.isEmpty))
        }
        var ordered = true
        for i in 1..<xs.count where joins(xs[i], xs[i - 1]) { ordered = false; break }
        if ordered { return (xs, primary) }
        var order = Array(xs.indices)
        order.sort {
            let a = xs[$0].range, b = xs[$1].range
            if a.lowerBound != b.lowerBound { return a.lowerBound < b.lowerBound }
            if a.upperBound != b.upperBound { return a.upperBound < b.upperBound }
            return $0 < $1
        }
        var out: [CodeSelection] = []
        var newPrimary = 0
        for i in order {
            let x = xs[i]
            if let last = out.last, joins(x, last) {
                let lo = last.range.lowerBound, hi = max(last.range.upperBound, x.range.upperBound)
                out[out.count - 1] = last.head < last.anchor ? CodeSelection(anchor: hi, head: lo) : CodeSelection(anchor: lo, head: hi)
            } else { out.append(x) }
            if i == primary { newPrimary = out.count - 1 }
        }
        xs = out
        return (xs, newPrimary)
    }

    /// Where `offset` goes when `start..<end` is replaced by `newLength` bytes: before it, unchanged;
    /// after it, shifted; inside it, `start + min(offset - start, newLength)`, which keeps the offset's
    /// distance into the span (`CV-D`). An offset at the point of a pure insertion stays in front of the
    /// text unless `sticky`.
    nonisolated static func mapSelectionOffset(_ o: Int, start: Int, end: Int, newLength: Int, sticky: Bool) -> Int {
        if o < start { return o }
        if start == end { return o == start ? (sticky ? start + newLength : start) : o + newLength }
        if o <= start { return o }
        if o < end { return start + min(o - start, newLength) }
        return o + newLength - (end - start)
    }

    /// Where a selection of a state that did NOT make the edit goes when `start..<end` is replaced by
    /// `newLength` bytes (`CV-AW`, from the AppKit probe). A caret or range start at an insertion point moves
    /// after the insertion; an insertion at a range's end or later, or an edit wholly after it, changes
    /// nothing; an edit wholly before shifts it; any edit that overlaps a range's interior (inside it, over
    /// it or across one end) collapses it to a caret at the deletion's start or the replacement's/insertion's
    /// end. Ranges go one by one (AppKit collapses a whole multi-selection; this does not).
    nonisolated static func mapOtherSelection(_ s: CodeSelection, start: Int, end: Int, newLength: Int) -> CodeSelection {
        let lo = s.range.lowerBound, hi = s.range.upperBound
        func shifted(_ d: Int) -> CodeSelection { CodeSelection(anchor: s.anchor + d, head: s.head + d) }
        if start == end {
            if start <= lo { return shifted(newLength) }
            if start >= hi { return s }
            return CodeSelection(caret: start + newLength)
        }
        if end <= lo { return shifted(newLength - (end - start)) }
        if start >= hi { return s }
        return CodeSelection(caret: start + newLength)
    }

    // MARK: Editing

    private func newTransaction() -> CodeTransactionID {
        nextTransaction += 1
        return CodeTransactionID(rawValue: nextTransaction)
    }

    private func validate(_ range: Range<Int>) -> Bool {
        let n = rope.summary.utf8
        guard range.lowerBound >= 0, range.upperBound <= n else { return false }
        for o in [range.lowerBound, range.upperBound] where o < n && isContinuation(rope.byte(at: o)) { return false }
        return true
    }

    /// Replaces `range` with `text` and returns the transaction the edit belongs to (the enclosing one
    /// inside `transaction`). On a read-only buffer nothing happens. Selections move with the edit; a
    /// caret at the point of an insertion made by `.typing` or `.paste` ends up after the text.
    /// `range` must lie in the text and on scalar boundaries.
    @discardableResult
    public func replace(_ range: Range<Int>, with text: String, origin: CodeEditOrigin = .programmatic) -> CodeTransactionID {
        asActing(actor) { performReplace(range, with: text, origin: origin) }
    }

    func performReplace(_ range: Range<Int>, with text: String, origin: CodeEditOrigin) -> CodeTransactionID {
        precondition(validate(range), "CodeBuffer.replace: range \(range) is out of bounds or inside a scalar")
        if transactionDepth > 0 {
            if isReadOnly || (range.isEmpty && text.isEmpty) { return currentTransaction }
            let inverse = applyEvent(range, text, origin: origin, transaction: currentTransaction)
            if Self.isUndoable(origin) { building?.inverse.append(inverse) }
            return currentTransaction
        }
        let tx = newTransaction()
        if isReadOnly || (range.isEmpty && text.isEmpty) { return tx }
        let before = actor.stored, beforePrimary = actor.storedPrimary
        let inverse = applyEvent(range, text, origin: origin, transaction: tx)
        recordUndo(inverse, origin: origin, transaction: tx, before: before, beforePrimary: beforePrimary)
        return tx
    }

    /// Runs `body`, whose edits are one transaction: one undo step, one transaction id on every event.
    /// A transaction inside a transaction joins the outer one.
    @discardableResult
    public func transaction(_ body: (CodeBuffer) -> Void) -> CodeTransactionID {
        asActing(actor) { performTransaction(body) }
    }

    func performTransaction(_ body: (CodeBuffer) -> Void) -> CodeTransactionID {
        if transactionDepth > 0 { body(self); return currentTransaction }
        let tx = newTransaction()
        transactionDepth = 1
        currentTransaction = tx
        building = CodeUndoGroup(id: tx, inverse: [], undoSelections: actor.stored, redoSelections: actor.stored,
                                 undoPrimary: actor.storedPrimary, redoPrimary: actor.storedPrimary)
        body(self)
        transactionDepth = 0
        if var group = building, !group.inverse.isEmpty {
            group.redoSelections = actor.stored
            group.redoPrimary = actor.storedPrimary
            openKind = nil
            openState = nil
            pushUndo(group)
        }
        building = nil
        return tx
    }

    /// Replaces every selection with `text` as one edit and leaves a caret after each insertion. This is
    /// what typing and pasting do; consecutive `.typing` calls at a caret coalesce into one undo step.
    @discardableResult
    public func replaceSelections(with text: String, origin: CodeEditOrigin = .typing) -> CodeTransactionID {
        asActing(actor) { performReplaceSelections(with: text, origin: origin) }
    }

    func performReplaceSelections(with text: String, origin: CodeEditOrigin) -> CodeTransactionID {
        performReplaceSelections(origin: origin) { _ in text }
    }

    func performReplaceSelections(withEach texts: [String], origin: CodeEditOrigin) -> CodeTransactionID {
        precondition(texts.count == actor.stored.count, "CodeSelectionState.replaceSelections(withEach:): \(texts.count) texts for \(actor.stored.count) selections")
        return performReplaceSelections(origin: origin) { texts[$0] }
    }

    private func performReplaceSelections(origin: CodeEditOrigin, text: (Int) -> String) -> CodeTransactionID {
        let state = actor
        let sels = state.stored
        let primary = state.storedPrimary
        var carets: [CodeSelection] = []
        var edits: [(range: Range<Int>, text: String)] = []
        var shift = 0
        for (i, s) in sels.enumerated() {
            let t = text(i)
            let length = t.utf8.count
            carets.append(CodeSelection(caret: s.range.lowerBound + shift + length))
            shift += length - s.range.count
            edits.append((s.range, t))
        }
        if sels.count == 1 {
            let before = version
            let tx = performReplace(edits[0].range, with: edits[0].text, origin: origin)
            if version != before {
                state.setInternal(carets, primary: 0)
                if Self.isUndoable(origin), !undoStack.isEmpty {
                    undoStack[undoStack.count - 1].redoSelections = state.stored
                    undoStack[undoStack.count - 1].redoPrimary = state.storedPrimary
                }
            }
            return tx
        }
        if transactionDepth > 0 {
            applyBatchInTransaction(edits, origin: origin)
            if !isReadOnly { state.setInternal(carets, primary: primary) }
            return currentTransaction
        }
        let tx = newTransaction()
        if isReadOnly { return tx }
        let before = state.stored
        let inverses = applyBatch(live(edits), origin: origin, transaction: tx)
        if inverses.isEmpty { return tx }
        state.setInternal(carets, primary: primary)
        recordBatchUndo(inverses, origin: origin, transaction: tx, before: before, beforePrimary: primary)
        return tx
    }

    /// The edits that change anything, highest first.
    private func live(_ edits: [(range: Range<Int>, text: String)]) -> [(range: Range<Int>, text: String)] {
        var previousEnd = 0
        for e in edits {
            precondition(validate(e.range) && e.range.lowerBound >= previousEnd, "CodeBuffer: batch range \(e.range) is out of bounds, inside a scalar or overlaps another")
            previousEnd = e.range.upperBound
        }
        return edits.filter { !($0.range.isEmpty && $0.text.isEmpty) }.reversed()
    }

    /// Applies `edits` (ascending, non-overlapping, in the current coordinates) inside the running transaction
    /// as one batch (`CV-BF`): the events are logged highest first and every state moves once.
    func applyBatchInTransaction(_ edits: [(range: Range<Int>, text: String)], origin: CodeEditOrigin) {
        precondition(transactionDepth > 0)
        let steps = live(edits)
        if isReadOnly { return }
        let inverses = applyBatch(steps, origin: origin, transaction: currentTransaction)
        if Self.isUndoable(origin) { building?.inverse.append(contentsOf: inverses) }
    }

    /// Applies `steps` in order (each in the coordinates of the text at that moment) and returns the inverse
    /// of each. When the steps are all below the previous one or all after it, the states move once for the
    /// whole run, otherwise once per step (`CV-BF`).
    private func applyBatch(_ steps: [(range: Range<Int>, text: String)], origin: CodeEditOrigin, transaction tx: CodeTransactionID) -> [CodeInverse] {
        let shape = steps.map { (range: $0.range, newLength: $0.text.utf8.count) }
        guard steps.count > 1 else {
            return steps.map { applyEvent($0.range, $0.text, origin: origin, transaction: tx) }
        }
        guard !sequentialMoves, let descending = CodeEditRun.order(of: shape) else {
            // One move per event, the selections left as the events move them and normalised once at the end.
            let inverses = steps.map { applyEvent($0.range, $0.text, origin: origin, transaction: tx, normalizing: false) }
            for entry in selectionStates { entry.state?.setInternal(entry.state!.stored) }
            return inverses
        }
        // Many edits close together: one splice of their span instead of one rope edit each.
        let spanLo = steps.last!.range.lowerBound, spanHi = steps.first!.range.upperBound
        let inverses: [CodeInverse]
        if descending, steps.count >= 32, spanHi - spanLo <= steps.count * 256 {
            inverses = applySpliced(steps, origin: origin, transaction: tx)
        } else {
            inverses = steps.map { applyEvent($0.range, $0.text, origin: origin, transaction: tx, movesStates: false) }
        }
        moveStates(CodeEditRun(steps: shape, descending: descending), origin: origin)
        return inverses
    }

    /// The effect of applying `steps` (descending: each wholly below the previous) one by one, with one rope
    /// splice over their span: every event's position, old text and log entry are read from the text before
    /// the splice, which is what each saw in turn (an edit only changes the text above it).
    private func applySpliced(_ steps: [(range: Range<Int>, text: String)], origin: CodeEditOrigin, transaction tx: CodeTransactionID) -> [CodeInverse] {
        let spanLo = steps.last!.range.lowerBound, spanHi = steps.first!.range.upperBound
        let original = CodeSnapshot(rope: rope, version: version)
        var spliced: [UInt8] = []
        spliced.reserveCapacity(spanHi - spanLo + 64)
        var cursor = spanLo
        var inverses: [CodeInverse] = []
        inverses.reserveCapacity(steps.count)
        var edits: [CodeEdit] = []
        edits.reserveCapacity(steps.count)
        let first = version
        for (j, step) in steps.reversed().enumerated() {
            let lo = step.range.lowerBound, hi = step.range.upperBound
            if lo > cursor { spliced.append(contentsOf: original.utf8(in: cursor..<lo)) }
            cursor = hi
            var t = step.text
            var newlines = 0, afterLastNewline = 0
            let length = t.withUTF8 { bytes -> Int in
                for i in bytes.indices where bytes[i] == 0x0A { newlines += 1; afterLastNewline = i + 1 }
                spliced.append(contentsOf: bytes)
                return bytes.count
            }
            let ps = rope.prefix(utf8: lo)
            let pe = hi == lo ? ps : rope.prefix(utf8: hi)
            let startPoint = CodePoint(row: ps.newlines, column: ps.lastLineBytes)
            let newEnd = newlines == 0
                ? CodePoint(row: startPoint.row, column: startPoint.column + length)
                : CodePoint(row: startPoint.row + newlines, column: length - afterLastNewline)
            inverses.append(CodeInverse(range: lo..<lo + length, text: hi > lo ? original.text(in: step.range) : ""))
            edits.append(CodeEdit(version: first + UInt64(steps.count - j), transaction: tx, origin: origin, range: step.range,
                                  scalarRange: ps.scalars..<pe.scalars, startPoint: startPoint,
                                  oldEndPoint: CodePoint(row: pe.newlines, column: pe.lastLineBytes),
                                  newEndPoint: newEnd, newText: step.text))
        }
        if spanHi > cursor { spliced.append(contentsOf: original.utf8(in: cursor..<spanHi)) }
        spliced.withUnsafeBufferPointer { rope.replace(spanLo, spanHi, with: $0) }
        version += UInt64(steps.count)
        // Applied highest first: the highest edit is the first event; `edits` is ascending.
        for e in edits.reversed() {
            log.append(e)
            logBytes += e.newText.utf8.count + 96
        }
        trimLog()
        // `inverses` was built ascending; the events ran highest first.
        return inverses.reversed()
    }

    /// `merged` for a whole batch: the i-th inverse of `previous` with the i-th of `next`, whose coordinates are
    /// taken back over the length changes of the lower carets' earlier edits (the run is highest first).
    nonisolated static func mergedBatch(_ previous: [CodeInverse], _ next: [CodeInverse], kind: CodeCoalesceKind) -> [CodeInverse]? {
        guard previous.count == next.count else { return nil }
        var below = Array(repeating: 0, count: previous.count)
        var sum = 0
        for i in stride(from: previous.count - 1, through: 0, by: -1) {
            below[i] = sum
            sum += previous[i].range.count - previous[i].text.utf8.count
        }
        var out: [CodeInverse] = []
        for i in previous.indices {
            var n = next[i]
            n.range = (n.range.lowerBound - below[i])..<(n.range.upperBound - below[i])
            guard let m = CodeInverse.merged(previous[i], n, kind: kind) else { return nil }
            out.append(m)
        }
        return out
    }

    private func recordBatchUndo(_ inverses: [CodeInverse], origin: CodeEditOrigin, transaction tx: CodeTransactionID,
                                 before: [CodeSelection], beforePrimary: Int) {
        guard Self.isUndoable(origin) else { return }
        let kind: CodeCoalesceKind? = switch origin { case .typing: .typing; case .deletion: .deletion; default: nil }
        let state = actor
        if let kind, openKind == kind, openState === state, var top = undoStack.last,
           let merged = Self.mergedBatch(top.inverse, inverses, kind: kind) {
            top.inverse = merged
            top.redoSelections = state.stored
            top.redoPrimary = state.storedPrimary
            undoStack[undoStack.count - 1] = top
            return
        }
        pushUndo(CodeUndoGroup(id: tx, inverse: inverses, undoSelections: before, redoSelections: state.stored,
                               undoPrimary: beforePrimary, redoPrimary: state.storedPrimary))
        openKind = kind
        openState = kind == nil ? nil : state
    }

    private static func isUndoable(_ origin: CodeEditOrigin) -> Bool {
        switch origin {
        case .external, .undo, .redo: false
        default: true
        }
    }

    private func recordUndo(_ inverse: CodeInverse, origin: CodeEditOrigin, transaction tx: CodeTransactionID,
                            before: [CodeSelection], beforePrimary: Int) {
        guard Self.isUndoable(origin) else { return }
        let kind: CodeCoalesceKind? = switch origin { case .typing: .typing; case .deletion: .deletion; default: nil }
        let state = actor
        if let kind, openKind == kind, openState === state, var top = undoStack.last, let last = top.inverse.last,
           let merged = CodeInverse.merged(last, inverse, kind: kind) {
            top.inverse[top.inverse.count - 1] = merged
            top.redoSelections = state.stored
            top.redoPrimary = state.storedPrimary
            undoStack[undoStack.count - 1] = top
            return
        }
        pushUndo(CodeUndoGroup(id: tx, inverse: [inverse], undoSelections: before, redoSelections: state.stored,
                               undoPrimary: beforePrimary, redoPrimary: state.storedPrimary))
        openKind = kind
        openState = kind == nil ? nil : state
    }

    private func pushUndo(_ group: CodeUndoGroup) {
        undoStack.append(group)
        redoStack.removeAll()
        trimUndo()
    }

    private func trimUndo() {
        var total = undoStack.reduce(0) { $0 + $1.bytes }
        var drop = 0
        while total > undoByteLimit && drop < undoStack.count - 1 {
            total -= undoStack[drop].bytes
            drop += 1
        }
        if drop > 0 { undoStack.removeFirst(drop) }
    }

    /// Applies one replacement: updates the tree, the version, the log and the selections, and returns the
    /// step that reverses it.
    private func applyEvent(_ range: Range<Int>, _ text: String, origin: CodeEditOrigin, transaction tx: CodeTransactionID,
                            movesStates: Bool = true, normalizing: Bool = true) -> CodeInverse {
        let lo = range.lowerBound, hi = range.upperBound
        let ps = rope.prefix(utf8: lo)
        let pe = hi == lo ? ps : rope.prefix(utf8: hi)
        let old = hi > lo ? CodeSnapshot(rope: rope, version: version).text(in: range) : ""
        var t = text
        var newlines = 0
        var afterLastNewline = 0
        let length = t.withUTF8 { bytes -> Int in
            for i in bytes.indices where bytes[i] == 0x0A { newlines += 1; afterLastNewline = i + 1 }
            rope.replace(lo, hi, with: bytes)
            return bytes.count
        }
        let startPoint = CodePoint(row: ps.newlines, column: ps.lastLineBytes)
        let newEnd = newlines == 0
            ? CodePoint(row: startPoint.row, column: startPoint.column + length)
            : CodePoint(row: startPoint.row + newlines, column: length - afterLastNewline)
        version += 1
        let edit = CodeEdit(version: version, transaction: tx, origin: origin, range: range,
                            scalarRange: ps.scalars..<pe.scalars, startPoint: startPoint,
                            oldEndPoint: CodePoint(row: pe.newlines, column: pe.lastLineBytes),
                            newEndPoint: newEnd, newText: text)
        log.append(edit)
        logBytes += length + 96
        trimLog()
        if movesStates { moveStates(start: lo, end: hi, newLength: length, origin: origin, normalizing: normalizing) }
        return CodeInverse(range: lo..<lo + length, text: old)
    }

    /// Moves every live state over one edit: the acting state by the typing/paste rule (`CV-D`), every other
    /// state by `mapOtherSelection` (`CV-AW`). An external edit has no acting state and moves all of them
    /// by the `CV-D` rule without stickiness, so a buffer used through its default state alone moves exactly
    /// as before states existed.
    private func moveStates(start: Int, end: Int, newLength: Int, origin: CodeEditOrigin, normalizing: Bool) {
        let sticky: Bool = switch origin { case .typing, .paste: true; default: false }
        let isExternal: Bool = if case .external = origin { true } else { false }
        let current = actor
        for entry in selectionStates {
            guard let state = entry.state else { continue }
            stateMoveCount += 1
            if isExternal || state === current {
                state.setInternal(state.stored.map {
                    CodeSelection(anchor: Self.mapSelectionOffset($0.anchor, start: start, end: end, newLength: newLength, sticky: sticky && !isExternal),
                                  head: Self.mapSelectionOffset($0.head, start: start, end: end, newLength: newLength, sticky: sticky && !isExternal))
                }, normalizing: normalizing)
            } else {
                state.setInternal(state.stored.map { Self.mapOtherSelection($0, start: start, end: end, newLength: newLength) }, normalizing: normalizing)
            }
        }
    }

    /// Moves every live state over a whole run of edits at once (`CV-BF`): the same result as `moveStates`
    /// once per edit, in O(edits + selections) per state, counted once per state.
    private func moveStates(_ batch: CodeEditRun, origin: CodeEditOrigin) {
        let sticky: Bool = switch origin { case .typing, .paste: true; default: false }
        let isExternal: Bool = if case .external = origin { true } else { false }
        let current = actor
        for entry in selectionStates {
            guard let state = entry.state else { continue }
            stateMoveCount += 1
            if isExternal || state === current {
                state.setInternal(batch.moveActing(state.stored, sticky: sticky && !isExternal))
            } else {
                state.setInternal(batch.moveOther(state.stored))
            }
        }
    }

    // MARK: Undo and redo

    /// Whether `undo()` has a step to revert.
    public var canUndo: Bool { access(keyPath: \.version); return !isReadOnly && !undoStack.isEmpty }
    /// Whether `redo()` has a step to reapply.
    public var canRedo: Bool { access(keyPath: \.version); return !isReadOnly && !redoStack.isEmpty }

    /// Reverts the latest undo step and restores the selections from before it. The reverting edits are
    /// ordinary events with origin `.undo(id)`, `id` being the step's first transaction. Returns whether
    /// anything was reverted.
    @discardableResult
    public func undo() -> Bool {
        asActing(actor) { performUndo() }
    }

    func performUndo() -> Bool {
        guard !isReadOnly, let group = undoStack.popLast() else { return false }
        openKind = nil
        openState = nil
        let counterpart = replay(group, origin: .undo(group.id))
        redoStack.append(counterpart)
        actor.setInternal(group.undoSelections, primary: group.undoPrimary)
        return true
    }

    /// Reapplies the step `undo()` reverted and restores the selections from after it (origin `.redo(id)`).
    @discardableResult
    public func redo() -> Bool {
        asActing(actor) { performRedo() }
    }

    func performRedo() -> Bool {
        guard !isReadOnly, let group = redoStack.popLast() else { return false }
        openKind = nil
        openState = nil
        let counterpart = replay(group, origin: .redo(group.id))
        undoStack.append(counterpart)
        trimUndo()
        actor.setInternal(group.redoSelections, primary: group.redoPrimary)
        return true
    }

    private func replay(_ group: CodeUndoGroup, origin: CodeEditOrigin) -> CodeUndoGroup {
        let tx = newTransaction()
        let recorded = applyBatch(group.inverse.reversed().map { (range: $0.range, text: $0.text) }, origin: origin, transaction: tx)
        return CodeUndoGroup(id: group.id, inverse: recorded, undoSelections: group.undoSelections, redoSelections: group.redoSelections,
                             undoPrimary: group.undoPrimary, redoPrimary: group.redoPrimary)
    }

    // MARK: External edits

    /// Applies edits that came from outside the editor, given in the coordinates of the current text, as
    /// one transaction with origin `.external` that is not an undo step (`CV-F`). They are applied highest
    /// range first, so each event's coordinates are also its original ones. Edits at the same offset
    /// insert in array order. Selections and the undo stacks move with them: a step whose range touches
    /// an edited range is dropped, with every older step.
    ///
    /// - Throws: `.stale` when `expectingVersion` is not the current version, `.readOnly`, `.invalidRange`
    ///   for a range out of bounds, inside a scalar, or overlapping another edit. Nothing is applied then.
    @discardableResult
    public func applyExternalEdits(_ edits: [CodeTextEdit], expectingVersion: UInt64? = nil) throws(CodeBufferError) -> CodeTransactionID {
        if isReadOnly { throw .readOnly }
        if let expected = expectingVersion, expected != version { throw .stale(current: version) }
        return try applyValidated(edits)
    }

    /// Makes the text `text` as one external transaction by diffing: the common prefix and suffix are
    /// kept, a line diff of the middle gives the hunks, and each hunk is one event. O(n); meant for a
    /// reload or a `git checkout`, not for keystrokes. Returns `nil` when the text is already equal.
    @discardableResult
    public func applyExternalReplacement(_ text: String, expectingVersion: UInt64? = nil) throws(CodeBufferError) -> CodeTransactionID? {
        if isReadOnly { throw .readOnly }
        if let expected = expectingVersion, expected != version { throw .stale(current: version) }
        let hunks = ExternalDiff.hunks(old: snapshot().utf8(in: 0..<rope.summary.utf8), new: Array(text.utf8))
        if hunks.isEmpty { return nil }
        return try applyValidated(hunks)
    }

    private func applyValidated(_ edits: [CodeTextEdit]) throws(CodeBufferError) -> CodeTransactionID {
        let sorted = edits.enumerated().sorted {
            let a = $0.element.range, b = $1.element.range
            if a.lowerBound != b.lowerBound { return a.lowerBound < b.lowerBound }
            if a.upperBound != b.upperBound { return a.upperBound < b.upperBound }
            return $0.offset < $1.offset
        }.map(\.element)
        var previousEnd = 0
        for e in sorted {
            guard validate(e.range), e.range.lowerBound >= previousEnd else { throw .invalidRange }
            previousEnd = e.range.upperBound
        }
        let tx = newTransaction()
        let live = sorted.filter { !($0.range.isEmpty && $0.text.isEmpty) }
        if live.isEmpty { return tx }
        openKind = nil
        openState = nil
        let shape = live.map { ExternalShape(range: $0.range, newLength: $0.text.utf8.count) }
        Self.rebase(&undoStack, over: shape)
        Self.rebase(&redoStack, over: shape)
        _ = applyBatch(live.reversed().map { (range: $0.range, text: $0.text) }, origin: .external, transaction: tx)
        return tx
    }

    struct ExternalShape {
        var range: Range<Int>
        var newLength: Int
    }

    /// Moves a stack's steps over external edits. `external` is in the coordinates of the text the stack's
    /// top step applies to; each step then moves it into the coordinates of the next one down.
    nonisolated static func rebase(_ stack: inout [CodeUndoGroup], over external: [ExternalShape]) {
        var current = external
        var i = stack.count - 1
        while i >= 0 {
            var group = stack[i]
            var conflict = false
            var idx = group.inverse.count - 1
            while idx >= 0 {
                let r = group.inverse[idx].range
                if current.contains(where: { r.lowerBound <= $0.range.upperBound && $0.range.lowerBound <= r.upperBound }) {
                    conflict = true
                    break
                }
                var shift = 0
                for e in current where e.range.upperBound < r.lowerBound { shift += e.newLength - e.range.count }
                group.inverse[idx].range = (r.lowerBound + shift)..<(r.upperBound + shift)
                let delta = group.inverse[idx].text.utf8.count - r.count
                for k in current.indices where current[k].range.lowerBound > r.upperBound {
                    current[k].range = (current[k].range.lowerBound + delta)..<(current[k].range.upperBound + delta)
                }
                idx -= 1
            }
            if conflict {
                stack.removeSubrange(0...i)
                return
            }
            let mapSel: (CodeSelection) -> CodeSelection = { s in
                func m(_ o: Int) -> Int {
                    var o = o
                    for e in external.reversed() {
                        o = mapSelectionOffset(o, start: e.range.lowerBound, end: e.range.upperBound, newLength: e.newLength, sticky: false)
                    }
                    return o
                }
                return CodeSelection(anchor: m(s.anchor), head: m(s.head))
            }
            group.undoSelections = group.undoSelections.map(mapSel)
            group.redoSelections = group.redoSelections.map(mapSel)
            stack[i] = group
            i -= 1
        }
    }

    // MARK: The edit stream

    /// A cursor positioned at the current version. Call `drain()` on it to collect the events since.
    public func makeEditCursor() -> CodeEditCursor {
        let cursor = CodeEditCursor(buffer: self, version: version)
        cursors.append(WeakCursor(cursor: cursor))
        return cursor
    }

    func drain(_ cursor: CodeEditCursor) -> CodeEditBatch {
        if cursor.version == version { return .edits([]) }
        defer {
            cursor.setVersion(version)
            trimLog()
        }
        if cursor.version < logBase { return .resync(snapshot()) }
        let first = logHead + Int(cursor.version - logBase)
        return .edits(Array(log[first...]))
    }

    private func trimLog() {
        cursors.removeAll { $0.cursor == nil }
        selectionStates.removeAll { $0.state == nil }
        var keepAfter = version > UInt64(editLogMinimumEvents) ? version - UInt64(editLogMinimumEvents) : 0
        if let slowest = cursors.compactMap({ $0.cursor?.version }).min() { keepAfter = min(keepAfter, slowest) }
        let available = log.count - logHead
        var drop = keepAfter > logBase ? min(Int(keepAfter - logBase), available) : 0
        var bytes = logBytes
        for i in 0..<drop { bytes -= log[logHead + i].newText.utf8.count + 96 }
        while bytes > editLogByteLimit && drop < available {
            bytes -= log[logHead + drop].newText.utf8.count + 96
            drop += 1
        }
        guard drop > 0 else { return }
        logBytes = bytes
        logHead += drop
        logBase += UInt64(drop)
        if logHead > 512 && logHead * 2 > log.count {
            log.removeFirst(logHead)
            logHead = 0
        }
    }

    /// Where `offset`, as of `version`, is now. An offset at the point of an insertion goes by `bias`; one
    /// inside replaced text collapses to the replacement's start (`.before`) or end (`.after`). `nil`
    /// when the log no longer reaches back to `version` (or it is from the future).
    public func map(_ offset: Int, from version: UInt64, bias: CodeBias) -> Int? {
        access(keyPath: \.version)
        guard version <= self.version, version >= logBase else { return nil }
        var o = offset
        var i = logHead + Int(version - logBase)
        while i < log.count {
            let e = log[i]
            let start = e.range.lowerBound, end = e.range.upperBound
            let length = e.newText.utf8.count
            if o < start { i += 1; continue }
            if o >= end && !(o == start && start == end) {
                o += length - (end - start)
            } else if start == end {
                o = bias == .after ? start + length : start
            } else if o == start {
                o = start
            } else {
                o = bias == .after ? start + length : start
            }
            i += 1
        }
        return o
    }
}
