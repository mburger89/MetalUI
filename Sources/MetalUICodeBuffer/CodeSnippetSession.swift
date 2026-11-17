/// A running snippet: the placeholders of an inserted ``CodeSnippet`` as live ranges, and which group of them is
/// current (`CV-BQ`). A value held by the ``CodeSelectionState`` that inserted it; every edit moves it inside the
/// same pass that moves the state's selections, so the ranges follow the text however it changed.
///
/// While a group is current, the state's selections **are** that group's ranges, so linked mirrors are several
/// selections and typing, deleting and undo coalescing work as they do for any multi-caret edit.
package struct SnippetSession {
    /// One placeholder: a tab stop's live range.
    package struct Placeholder {
        /// The stop's number; the placeholders of one index are mirrors, 0 is the final stop.
        package var index: Int
        package var range: Range<Int>
        /// An edit covered the whole of it (typing over its parent's default text): Tab skips it.
        package var removed = false
        /// The enclosing placeholder's position in `placeholders`, or -1. Fixed at creation: the nesting never changes.
        let parent: Int
    }

    /// Sorted by start, an enclosing placeholder before the ones inside it (the snippet's own order).
    package private(set) var placeholders: [Placeholder]
    /// The distinct indices, ascending, 0 last.
    let groups: [Int]
    /// The group whose ranges the selections are (the one that grows when text is typed at its edges).
    package private(set) var current: Int
    /// The insertion's transaction: undoing that undo group ends the session.
    package let transaction: CodeTransactionID

    /// A session over `stops` (absolute ranges, nested or disjoint), starting at the lowest group.
    init(stops: [(index: Int, range: Range<Int>)], transaction: CodeTransactionID) {
        let order = stops.indices.sorted {
            let a = stops[$0].range, b = stops[$1].range
            if a.lowerBound != b.lowerBound { return a.lowerBound < b.lowerBound }
            if a.upperBound != b.upperBound { return a.upperBound > b.upperBound }
            return $0 < $1
        }
        var list: [Placeholder] = []
        var open: [Int] = []   // positions of the placeholders still enclosing the cursor
        for i in order {
            let range = stops[i].range
            while let top = open.last, list[top].range.upperBound <= range.lowerBound {
                open.removeLast()
            }
            list.append(Placeholder(index: stops[i].index, range: range, parent: open.last ?? -1))
            open.append(list.count - 1)
        }
        placeholders = list
        var seen = Set(list.map(\.index))
        let zero = seen.remove(0) != nil
        groups = seen.sorted() + (zero ? [0] : [])
        current = groups.first ?? 0
        self.transaction = transaction
    }

    /// The ranges of the non-removed placeholders of `group`, in text order.
    func ranges(of group: Int) -> [Range<Int>] {
        placeholders.compactMap { $0.index == group && !$0.removed ? $0.range : nil }
    }

    /// Whether `group` still has a placeholder an edit has not covered.
    func isLive(_ group: Int) -> Bool { placeholders.contains { $0.index == group && !$0.removed } }

    /// The next group after the current one that is still live, `nil` when none is.
    func nextGroup() -> Int? {
        guard let at = groups.firstIndex(of: current) else { return nil }
        return groups[(at + 1)...].first(where: isLive)
    }

    /// The previous live group, `nil` at the first (⇧Tab then declines).
    func previousGroup() -> Int? {
        guard let at = groups.firstIndex(of: current) else { return nil }
        return groups[..<at].last(where: isLive)
    }

    package mutating func setCurrent(_ group: Int) { current = group }

    /// Whether `range` lies inside one non-removed placeholder, bounds included (VS Code's `isSelectionWithinPlaceholders`).
    func contains(_ range: Range<Int>) -> Bool {
        placeholders.contains { !$0.removed && $0.range.lowerBound <= range.lowerBound && range.upperBound <= $0.range.upperBound }
    }

    /// The innermost non-removed placeholder holding `range`, bounds included.
    func innermost(containing range: Range<Int>) -> Int? {
        placeholders.lastIndex { !$0.removed && $0.range.lowerBound <= range.lowerBound && range.upperBound <= $0.range.upperBound }
    }

    /// Moves the ranges over one edit: `start..<end` replaced by `newLength` bytes. The current group grows
    /// when text is typed at its edges; any other placeholder holds its edges, and an empty one at the insertion
    /// point stays on the side of the current group it touches. A placeholder the edit covers entirely is removed.
    mutating func move(start s: Int, end e: Int, newLength n: Int) {
        let delta = n - (e - s)
        let old = placeholders
        // The current placeholders an insertion at `s` lands in.
        var absorbers: [Int] = []
        if s == e {
            for (i, p) in old.enumerated() where p.index == current && !p.removed && p.range.lowerBound <= s && s <= p.range.upperBound {
                absorbers.append(i)
            }
        }
        func isDescendant(_ child: Int, of ancestor: Int) -> Bool {
            var at = old[child].parent
            while at >= 0 { if at == ancestor { return true }; at = old[at].parent }
            return false
        }
        for i in old.indices {
            let p = old[i]
            let a = p.range.lowerBound, b = p.range.upperBound
            var lo = a, hi = b
            if s == e {
                if s < a {
                    lo += delta; hi += delta
                } else if s <= b {
                    if p.index == current && !p.removed {
                        hi += delta
                    } else if a == b {
                        if absorbers.contains(where: { $0 < i && old[$0].range.upperBound == s }) { lo += delta; hi += delta }
                    } else if absorbers.contains(where: { isDescendant($0, of: i) }) {
                        hi += delta   // encloses a placeholder the text lands in
                    } else if s == a {
                        lo += delta; hi += delta
                    } else if s < b {
                        hi += delta
                    }
                }
            } else if e <= a {
                lo += delta; hi += delta
            } else if s >= b {
                // unchanged
            } else if s >= a && e <= b {
                hi += delta
            } else if s <= a && e >= b {
                lo = s + n; hi = s + n
                placeholders[i].removed = true
            } else if s < a {
                lo = s + n; hi += delta
            } else {
                hi = s
            }
            placeholders[i].range = lo..<max(lo, hi)
        }
    }

    /// Calls `body` for each tinted placeholder that overlaps `window`: not the current group, not removed, not the
    /// final stop, not empty. A binary search finds the placeholders that start inside the window; the ones that
    /// start before it and run into it are an ancestor chain, walked up from the last placeholder before it.
    package func forEachTinted(in window: Range<Int>, _ body: (Range<Int>) -> Void) {
        func visit(_ p: Placeholder) {
            guard !p.removed, p.index != current, p.index != 0, !p.range.isEmpty,
                  p.range.upperBound > window.lowerBound, p.range.lowerBound < window.upperBound else { return }
            body(p.range)
        }
        // The first placeholder starting at or after the window.
        var lo = 0, hi = placeholders.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if placeholders[mid].range.lowerBound >= window.lowerBound { hi = mid } else { lo = mid + 1 }
        }
        var chain = lo - 1
        while chain >= 0 {
            visit(placeholders[chain])
            chain = placeholders[chain].parent
        }
        var i = lo
        while i < placeholders.count, placeholders[i].range.lowerBound < window.upperBound {
            visit(placeholders[i])
            i += 1
        }
    }
}
