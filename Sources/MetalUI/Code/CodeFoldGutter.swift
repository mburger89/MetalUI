import MetalUICodeBuffer
import MetalUICore
import MetalUILayout

// The fold chevron lane of a `CodeView` (`CV-BN`, G6): a lane two space advances wide between the line numbers and the
// text, with a ▾ on each line that starts a `CodeFoldState.foldableRanges` entry and a ▸ on one whose fold is closed.
// The two glyphs are shaped once per font (the gutter marker cache) and drawn by translation; a row stores one byte.

/// What ``CodeView/foldGutter(showsOnHover:onToggle:)`` stores.
struct CodeFoldGutter {
    let showsOnHover: Bool
    let onToggle: (@MainActor (Int) -> Void)?
}

extension CodeViewStats {
    /// How many `fold-chevron-<line>` accessibility nodes were recorded (only while a client is present).
    nonisolated(unsafe) package static var foldChevronNodes = 0
}

extension CodeViewPlan {
    /// The index in `ranges` (sorted by start, longer first) of the innermost range starting at `line`: the last of
    /// those that start there; `nil` when none does. O(log n).
    static func foldableIndex(startingAt line: Int, in ranges: [Range<Int>]) -> Int? {
        var lo = 0, hi = ranges.count
        while lo < hi { let mid = (lo + hi) / 2; if ranges[mid].lowerBound <= line { lo = mid + 1 } else { hi = mid } }
        return lo > 0 && ranges[lo - 1].lowerBound == line ? lo - 1 : nil
    }

    /// The chevron's cell on `row` (the whole lane, a row high), in the plan's (bounds) space, points.
    func foldChevronBounds(_ row: Row) -> Bounds<Pixels>? {
        guard row.chevron != 0, chevronPx > 0 else { return nil }
        return Bounds(origin: Point(x: Pixels(Float(originX + gutterPx - chevronPx) / scale), y: Pixels(Float(row.top) / scale)),
                      size: Size(width: Pixels(Float(chevronPx) / scale), height: Pixels(Float(pitchPx) / scale)))
    }

    /// The buffer line whose chevron cell is under `point` (the plan's space), `nil` elsewhere.
    func foldChevronLine(at point: Point<Pixels>) -> Int? {
        guard chevronPx > 0, !rows.isEmpty else { return nil }
        let x = Int((Double(point.x.value) * Double(scale)).rounded(.down))
        let y = Int((Double(point.y.value) * Double(scale)).rounded(.down))
        guard x >= originX + gutterPx - chevronPx, x < originX + gutterPx, y >= originY, y < originY + heightPx else { return nil }
        var i = shownFrom
        while i < shownTo {
            let row = rows[i]
            i += 1
            guard y >= row.top, y < row.top + pitchPx else { continue }
            return !row.isVirtual && row.chevron != 0 ? row.buffer : nil
        }
        return nil
    }

    /// Opens the folds that start at `line`, else folds the innermost foldable range that does; the press of a chevron.
    @MainActor func toggleFold(atLine line: Int) {
        guard let state = foldState else { return }
        let closed = state.folded.filter { $0.lowerBound == line }
        if !closed.isEmpty {
            for range in closed { state.unfold(range) }
            return
        }
        let ranges = state.foldableRanges
        if let k = Self.foldableIndex(startingAt: line, in: ranges) { state.fold(ranges[k]) }
    }

    /// One `.button` node per chevron in the viewport, identified `fold-chevron-<line>`, valued `expanded` or
    /// `collapsed`; built only while an accessibility client is present (`CV-U`, `CV-BN`).
    @MainActor func recordFoldChevrons(_ id: GlobalElementID, frame: Frame) {
        var i = shownFrom
        while i < shownTo {
            let row = rows[i]
            i += 1
            guard !row.isVirtual, let bounds = foldChevronBounds(row) else { continue }
            var node = AXNode(role: .button, label: row.chevron == 2 ? "Unfold line \(row.buffer + 1)" : "Fold line \(row.buffer + 1)")
            node.value = row.chevron == 2 ? "collapsed" : "expanded"
            node.declarations.identifier = "fold-chevron-\(row.buffer)"
            let child = GlobalElementID.child(of: id, at: row.buffer, name: ElementID("fold-chevron-\(row.buffer)"))
            CodeViewStats.foldChevronNodes += 1
            frame.recordAccessibility(text: nil, declared: node, at: bounds, id: child)
        }
    }
}

extension CodeViewPlan {
    /// The pointer style over `point` (bounds space) (`CV-BO`): an arrow in the gutter (numbers, marker lane, bars) and
    /// on a virtual row, the pointing hand on a fold chevron that acts, on a folded header's `⋯` and, with
    /// `plainClickTargets` (an `onTextClick` whose modifiers are none), on a character of text; the I-beam elsewhere
    /// in the text area, past a line's end and below the last row included, as NSTextView's.
    func regionCursor(at point: Point<Pixels>, plainClickTargets: Bool) -> PointerStyle {
        if foldChevronLine(at: point) != nil { return .link }
        if rows.isEmpty { return isInGutter(point) ? .default : .horizontalText }
        let hit = hit(at: point)
        switch hit.region {
        case .gutter, .virtualRow: return .default
        case .text: return plainClickTargets ? .link : .horizontalText
        case .pastLineEnd: return hit.foldedLines != nil ? .link : .horizontalText
        }
    }
}
