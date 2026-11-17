import Observation

/// One edit event reduced to the lines it touched (`CV-BL`): where it started, the line it ended on before
/// the edit, how many line breaks it added, and whether it was a pure insertion at column 0.
struct FoldLineEdit: Equatable {
    var startRow: Int
    var startColumn: Int
    /// The row the replaced range ended on, before the edit.
    var endRow: Int
    var addedBreaks: Int
    /// Whether the replaced range was empty.
    var isInsertion: Bool

    /// The change in line count.
    var delta: Int { addedBreaks - (endRow - startRow) }

    init(startRow: Int, startColumn: Int, endRow: Int, addedBreaks: Int, isInsertion: Bool) {
        self.startRow = startRow; self.startColumn = startColumn; self.endRow = endRow
        self.addedBreaks = addedBreaks; self.isInsertion = isInsertion
    }

    init(_ e: CodeEdit) {
        self.init(startRow: e.startPoint.row, startColumn: e.startPoint.column, endRow: e.oldEndPoint.row,
                  addedBreaks: e.newEndPoint.row - e.startPoint.row, isInsertion: e.range.isEmpty)
    }
}

/// Sorted line ranges (by start, then longer first) with a running maximum of their ends, so "is this line
/// inside one" and "which is the first range an edit can touch" are binary searches (`CV-BL`).
struct FoldRangeSet {
    private(set) var ranges: [Range<Int>] = []
    /// `maxEnd[i]` is the largest `upperBound` of `ranges[0...i]`.
    private(set) var maxEnd: [Int] = []
    /// Ranges and binary-search probes looked at by `apply` so far (a counted test reads it).
    var visited = 0

    init() {}

    /// `input` sorted, de-duplicated, with ranges of fewer than 2 lines dropped and ends clamped to `lineCount`.
    init(normalizing input: [Range<Int>], lineCount: Int?) {
        var xs: [Range<Int>] = []
        xs.reserveCapacity(input.count)
        for r in input {
            let lo = max(0, r.lowerBound)
            let hi = lineCount.map { min(r.upperBound, $0) } ?? r.upperBound
            if hi - lo >= 2 { xs.append(lo..<hi) }
        }
        xs.sort { $0.lowerBound != $1.lowerBound ? $0.lowerBound < $1.lowerBound : $0.upperBound > $1.upperBound }
        var out: [Range<Int>] = []
        out.reserveCapacity(xs.count)
        for r in xs where out.last != r { out.append(r) }
        ranges = out
        rebuildMax(from: 0)
    }

    var isEmpty: Bool { ranges.isEmpty }

    private mutating func rebuildMax(from i: Int) {
        maxEnd.removeSubrange(min(i, maxEnd.count)...)
        var m = i > 0 ? maxEnd[i - 1] : Int.min
        for j in i..<ranges.count { m = max(m, ranges[j].upperBound); maxEnd.append(m) }
    }

    /// The number of ranges starting before `line`.
    private func countStarting(before line: Int) -> Int {
        var lo = 0, hi = ranges.count
        while lo < hi { let mid = (lo + hi) / 2; if ranges[mid].lowerBound < line { lo = mid + 1 } else { hi = mid } }
        return lo
    }

    /// Whether `line` is one of the hidden rows `lowerBound+1 ..< upperBound` of some range.
    func hides(_ line: Int) -> Bool {
        let k = countStarting(before: line)
        return k > 0 && maxEnd[k - 1] > line
    }

    func contains(_ r: Range<Int>) -> Bool {
        var lo = 0, hi = ranges.count
        while lo < hi {
            let mid = (lo + hi) / 2
            let m = ranges[mid]
            if m.lowerBound < r.lowerBound || (m.lowerBound == r.lowerBound && m.upperBound > r.upperBound) { lo = mid + 1 } else { hi = mid }
        }
        return lo < ranges.count && ranges[lo] == r
    }

    /// Inserts `r` (at least 2 lines); false when already present.
    mutating func insert(_ r: Range<Int>) -> Bool {
        var lo = 0, hi = ranges.count
        while lo < hi {
            let mid = (lo + hi) / 2
            let m = ranges[mid]
            if m.lowerBound < r.lowerBound || (m.lowerBound == r.lowerBound && m.upperBound > r.upperBound) { lo = mid + 1 } else { hi = mid }
        }
        if lo < ranges.count, ranges[lo] == r { return false }
        ranges.insert(r, at: lo)
        rebuildMax(from: lo)
        return true
    }

    mutating func remove(_ r: Range<Int>) -> Bool {
        guard contains(r), let i = ranges.firstIndex(of: r) else { return false }
        ranges.remove(at: i)
        rebuildMax(from: i)
        return true
    }

    /// Removes every range hiding `line`; whether any went.
    mutating func removeHiding(_ line: Int) -> Bool {
        let k = countStarting(before: line)
        guard k > 0, maxEnd[k - 1] > line else { return false }
        var first = k
        var i = k - 1
        while i >= 0 && maxEnd[i] > line { if ranges[i].upperBound > line { first = i }; i -= 1 }
        // Keep what does not hide `line` among the candidates.
        var kept: [Range<Int>] = []
        for j in first..<k where ranges[j].upperBound <= line { kept.append(ranges[j]) }
        ranges.replaceSubrange(first..<k, with: kept)
        rebuildMax(from: first)
        return true
    }

    mutating func removeAll() { ranges.removeAll(); maxEnd.removeAll() }

    /// Moves the ranges over `edits` (ascending, non-overlapping, in the coordinates of the text before the
    /// first of them), by the rules of `CV-BL`; a range an edit opens is dropped. Starts at the first range an
    /// edit can touch (binary search) and adjusts the tail after it. Returns whether anything changed.
    mutating func apply(_ edits: [FoldLineEdit]) -> Bool {
        guard !ranges.isEmpty, let firstEdit = edits.first else { return false }
        let s0 = firstEdit.startRow
        var lo = 0, hi = ranges.count
        while lo < hi { visited += 1; let mid = (lo + hi) / 2; if maxEnd[mid] > s0 { hi = mid } else { lo = mid + 1 } }
        guard lo < ranges.count else { return false }
        var cum = [0]
        cum.reserveCapacity(edits.count + 1)
        for e in edits { cum.append(cum[cum.count - 1] + e.delta) }
        var w = lo
        var running = lo > 0 ? maxEnd[lo - 1] : Int.min
        var changed = false
        var oldPrefix = lo > 0 ? maxEnd[lo - 1] : Int.min
        for i in lo..<ranges.count {
            visited += 1
            let h = ranges[i].lowerBound, u = ranges[i].upperBound
            let oldHere = maxEnd[i]
            defer { oldPrefix = oldHere }
            // Edits ending above the header shift it.
            var a = 0, b = edits.count
            while b > a { let mid = (a + b) / 2; if edits[mid].endRow < h { a = mid + 1 } else { b = mid } }
            // Every edit is above this range and they cancel: it and the rest stay put, and their running
            // maxima are still right unless a range before changed the maximum.
            if a == edits.count, cum[a] == 0, w == i, running == oldPrefix { w = ranges.count; break }
            var newH = h + cum[a]
            var newU = u + cum[a]
            var opens = false
            var j = a
            while j < edits.count, edits[j].startRow < u {
                let e = edits[j]
                if e.startRow < h {
                    opens = true
                } else if e.startRow == h {
                    if e.endRow != h { opens = true }
                    else if e.addedBreaks == 0 { /* confined to the header line: keep */ }
                    else if e.isInsertion && e.startColumn == 0 { newH += e.addedBreaks; newU += e.addedBreaks }
                    else { opens = true }
                } else if e.endRow <= u - 1 {
                    newU += e.delta
                } else {
                    opens = true
                }
                if opens { break }
                j += 1
            }
            if opens { changed = true; continue }
            if newH != h || newU != u { changed = true }
            ranges[w] = newH..<newU
            running = max(running, newU)
            maxEnd[w] = running
            w += 1
        }
        if w < ranges.count { ranges.removeSubrange(w...); maxEnd.removeSubrange(w...) }
        return changed
    }
}

struct WeakFold { weak var state: CodeFoldState? }

/// Which lines of a `CodeBuffer` are folded: a header line stays shown and the lines after it, up to the end
/// of the range, are hidden (`CV-BL`). The model only; a view draws it in a later change.
///
/// A range is 0-based **lines**: `lowerBound` is the header and rows `lowerBound+1 ..< upperBound` are hidden.
/// A range of fewer than 2 lines is ignored. Folds may nest; the hidden rows are the union.
///
/// The buffer holds a fold state weakly and moves it over every edit by line deltas: an edit above shifts it;
/// one confined to the header line without a line break keeps it; one wholly inside the hidden rows keeps it
/// and moves its end; anything else opens it. Undo never re-creates a fold. Every explicit selection write on
/// the state (assigning `selections`, `select`, undo and redo) unfolds the folds hiding a selection end; edits
/// never do.
@MainActor @Observable
public final class CodeFoldState {
    @ObservationIgnored private let selection: CodeSelectionState
    @ObservationIgnored private var foldedSet = FoldRangeSet()
    @ObservationIgnored private var foldableSet = FoldRangeSet()
    /// Rises when the folded set changes (for a later layout cache); not observed.
    @ObservationIgnored package private(set) var foldRevision: UInt64 = 0
    /// Folds looked at by edit tracking so far (a counted test reads it).
    @ObservationIgnored package var foldsVisited: Int { foldedSet.visited }
    /// Edit events (or batches) that moved this state.
    @ObservationIgnored package private(set) var moveCount = 0

    /// A fold state over `selectionState`'s buffer, starting with `folded` (normalised). The buffer and the
    /// selection state hold it weakly: keep it alive as long as the view uses it.
    public init(selectionState: CodeSelectionState, folded: [Range<Int>] = []) {
        selection = selectionState
        let buffer = selectionState.buffer
        foldedSet = FoldRangeSet(normalizing: folded, lineCount: buffer.rope.summary.newlines + 1)
        buffer.register(self)
        selectionState.register(self)
    }

    /// The buffer folded.
    public var buffer: CodeBuffer { selection.buffer }

    /// The selection state whose carets folding moves out of hidden rows and whose explicit writes open folds.
    public var selectionState: CodeSelectionState { selection }

    /// The folded ranges, sorted by start. Assigning restores them: normalised (sorted, de-duplicated, ends
    /// clamped to the line count, ranges under 2 lines dropped), and the selection state's carets in the
    /// rows they hide move to the end of their header line, as `fold(_:)` does.
    public var folded: [Range<Int>] {
        get { access(keyPath: \.folded); return foldedSet.ranges }
        set {
            let new = FoldRangeSet(normalizing: newValue, lineCount: lineCount)
            guard new.ranges != foldedSet.ranges else { return }
            withMutation(keyPath: \.folded) { foldedSet = new; foldRevision &+= 1 }
            evictSelections()
        }
    }

    /// The ranges a view may offer a fold chevron for (same line convention). Edit-tracked like `folded`
    /// (a range an edit opens is dropped); an app gives them from its syntax pass with
    /// `setFoldableRanges(_:asOf:)`. Assigning replaces them, normalised.
    public var foldableRanges: [Range<Int>] {
        get { access(keyPath: \.foldableRanges); return foldableSet.ranges }
        set {
            let new = FoldRangeSet(normalizing: newValue, lineCount: lineCount)
            guard new.ranges != foldableSet.ranges else { return }
            withMutation(keyPath: \.foldableRanges) { foldableSet = new }
        }
    }

    /// Replaces `foldableRanges` with ranges computed off the main thread against the text at buffer version
    /// `version`: they are moved through every edit since by the edit rules (ranges an edit opens are dropped),
    /// never applied raw. Returns false, changing nothing, when the buffer's edit log no longer reaches back
    /// to `version` (or it is from the future).
    @discardableResult
    public func setFoldableRanges(_ ranges: [Range<Int>], asOf version: UInt64) -> Bool {
        guard let edits = buffer.lineEdits(since: version) else { return false }
        var set = FoldRangeSet(normalizing: ranges, lineCount: nil)
        for e in edits { _ = set.apply([e]) }
        let new = FoldRangeSet(normalizing: set.ranges, lineCount: lineCount)
        guard new.ranges != foldableSet.ranges else { return true }
        withMutation(keyPath: \.foldableRanges) { foldableSet = new }
        return true
    }

    private var lineCount: Int { buffer.rope.summary.newlines + 1 }

    /// Folds `lines` (clamped to the text). Returns false for a range under 2 lines or one already folded.
    /// Carets in the rows it hides move to the end of the header line.
    @discardableResult
    public func fold(_ lines: Range<Int>) -> Bool {
        let r = max(0, lines.lowerBound)..<min(lines.upperBound, lineCount)
        guard r.upperBound - r.lowerBound >= 2, !foldedSet.contains(r) else { return false }
        withMutation(keyPath: \.folded) { _ = foldedSet.insert(r); foldRevision &+= 1 }
        evictSelections()
        return true
    }

    /// Unfolds exactly `lines`. Returns whether it was folded.
    @discardableResult
    public func unfold(_ lines: Range<Int>) -> Bool {
        guard foldedSet.contains(lines) else { return false }
        withMutation(keyPath: \.folded) { _ = foldedSet.remove(lines); foldRevision &+= 1 }
        return true
    }

    /// Unfolds `lines` when folded, folds it otherwise. Returns whether anything changed.
    @discardableResult
    public func toggle(_ lines: Range<Int>) -> Bool {
        foldedSet.contains(lines) ? unfold(lines) : fold(lines)
    }

    /// Unfolds every fold hiding `line` (a header line, which stays shown, is not hidden by its own fold).
    public func unfold(containing line: Int) {
        guard foldedSet.hides(line) else { return }
        withMutation(keyPath: \.folded) { _ = foldedSet.removeHiding(line); foldRevision &+= 1 }
    }

    /// Unfolds everything.
    public func unfoldAll() {
        guard !foldedSet.isEmpty else { return }
        withMutation(keyPath: \.folded) { foldedSet.removeAll(); foldRevision &+= 1 }
    }

    /// Whether `line` is hidden by some fold (inside `lowerBound+1 ..< upperBound` of one).
    public func isHidden(line: Int) -> Bool {
        access(keyPath: \.folded)
        return foldedSet.hides(line)
    }

    // MARK: Selections

    /// Moves every selection end in a hidden row to the end of that fold's header line, then normalises.
    private func evictSelections() {
        guard !foldedSet.isEmpty else { return }
        let buffer = buffer
        let rope = buffer.rope
        let snapshot = CodeSnapshot(rope: rope, version: buffer.version)
        func moved(_ o: Int) -> Int {
            let row = rope.prefix(utf8: o).newlines
            guard foldedSet.hides(row) else { return o }
            // The outermost header hiding the row: the first range that starts before it and ends after it.
            var header = row
            for r in foldedSet.ranges where r.lowerBound < row && r.upperBound > row { header = min(header, r.lowerBound) }
            return snapshot.lineRange(header).upperBound
        }
        let old = selection.stored
        let new = old.map { CodeSelection(anchor: moved($0.anchor), head: moved($0.head)) }
        if new != old { selection.setInternal(new) }
    }

    /// Unfolds the folds hiding an end of any of `selections` (an explicit selection write).
    func revealSelections(_ selections: [CodeSelection]) {
        guard !foldedSet.isEmpty else { return }
        let rope = buffer.rope
        for s in selections {
            unfold(containing: rope.prefix(utf8: s.anchor).newlines)
            if s.head != s.anchor { unfold(containing: rope.prefix(utf8: s.head).newlines) }
            if foldedSet.isEmpty { break }
        }
    }

    // MARK: Edit tracking (called by the buffer)

    /// Moves both sets over `edits` (ascending, non-overlapping, in the coordinates before the first).
    func apply(_ edits: [FoldLineEdit]) {
        moveCount += 1
        if foldedSet.apply(edits) {
            withMutation(keyPath: \.folded) { foldRevision &+= 1 }
        }
        if foldableSet.apply(edits) {
            withMutation(keyPath: \.foldableRanges) {}
        }
    }
}

extension CodeSelectionState {
    func register(_ fold: CodeFoldState) {
        folds.removeAll { $0.state == nil }
        folds.append(WeakFold(state: fold))
    }

    /// An explicit selection write happened: open the folds hiding its ends.
    func openFolds() {
        guard !folds.isEmpty else { return }
        for f in folds { f.state?.revealSelections(stored) }
    }
}

extension CodeBuffer {
    func register(_ fold: CodeFoldState) { foldStates.append(WeakFold(state: fold)) }

    /// How many fold states are alive and registered.
    package var liveFoldStateCount: Int { foldStates.reduce(0) { $0 + ($1.state == nil ? 0 : 1) } }
}
