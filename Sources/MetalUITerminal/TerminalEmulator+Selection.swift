/// Selection, selected text and the viewport (`TRM-AQ`, `TRM-AR`).
extension TerminalEmulator {
    /// The selection, in absolute rows; nil for none.
    ///
    /// Setting stores the range as given, clamped to the rows that exist (a range wholly outside them becomes
    /// nil), so an end may come before the other end. Reading re-checks it: a selection is cleared when a reflow
    /// has renumbered the rows, when output changes the text under it, when the alternate screen switches, and
    /// is clipped or cleared when scrollback evicts its rows (`TRM-AQ`).
    public var selection: TerminalSelection? {
        get {
            validateSelection()
            return selectionStorage
        }
        set {
            selectionStorage = newValue
            selectionGeneration = reflowGeneration
            selectionWitness = [:]
            validateSelection()
        }
    }

    /// The selected text: trailing blanks trimmed per row, a wide character once. A linear selection joins a
    /// soft-wrapped row to the next without a newline (the row keeps its trailing blanks, they are text of the
    /// longer line) and every other row break is `"\n"`; a block selection takes the same columns of every row
    /// and joins the rows with `"\n"`. Nil without a selection.
    public func selectedText() -> String? {
        guard let selection = self.selection else { return nil }
        let geometry = SelectionGeometry(selection, cols: cols)
        var out = ""
        for row in geometry.rows {
            guard let stored = self.row(at: row) else { continue }
            let span = geometry.span(row: row)
            let text = Self.spanText(stored, span)
            let joins = !geometry.isBlock && row < geometry.rows.upperBound - 1 && stored.wrapsToNext
            out += joins ? text : Self.trimmed(text)
            if row < geometry.rows.upperBound - 1 && !joins { out += "\n" }
        }
        return out
    }

    /// Scrolls the viewport to `rows` rows back from the live bottom (0 is live). The offset clamps to the
    /// retained scrollback, and to 0 on the alternate screen, which has none. A change makes the next snapshot
    /// a full frame carrying the new `viewportOffset`. While scrolled back, new output that pushes rows into
    /// scrollback moves the offset with it so the same rows stay in view (`TRM-AR`).
    public func scrollViewport(toOffset rows: Int) {
        let target = clampedViewportOffset(rows)
        guard target != viewportOffset else { return }
        viewportOffset = target
        needsFullFrame = true
    }

    func clampedViewportOffset(_ rows: Int) -> Int {
        onAlternate ? 0 : min(max(rows, 0), scrollback.count)
    }

    // MARK: Validation

    /// Applies the lifecycle rules of `TRM-AQ` to the stored selection.
    func validateSelection() {
        guard let stored = selectionStorage else { return }
        guard selectionGeneration == reflowGeneration else { return clearSelection() }
        let (range, isBlock) = Self.parts(stored)
        let last = scrolledOff + rows - 1
        guard max(range.lowerBound.row, range.upperBound.row) >= firstRow,
              min(range.lowerBound.row, range.upperBound.row) <= last else { return clearSelection() }
        let a = clamp(range.lowerBound, last: last, isBlock: isBlock)
        let b = clamp(range.upperBound, last: last, isBlock: isBlock)
        let next = TerminalRange(lowerBound: a, upperBound: b)
        let clamped: TerminalSelection = isBlock ? .block(next) : .linear(next)
        if clamped != stored { selectionStorage = clamped }
        let geometry = SelectionGeometry(clamped, cols: cols)
        for (row, before) in selectionWitness where geometry.rows.contains(row) {
            guard let now = self.row(at: row) else { return clearSelection() }
            if now == before { continue }
            let span = geometry.span(row: row)
            if Self.trimmed(Self.spanText(now, span)) != Self.trimmed(Self.spanText(before, span)) {
                return clearSelection()
            }
        }
        selectionWitness = [:]
        let screenStart = max(geometry.rows.lowerBound, scrolledOff)
        if screenStart < geometry.rows.upperBound {
            for row in screenStart..<geometry.rows.upperBound {
                if let stored = self.row(at: row) { selectionWitness[row] = stored }
            }
        }
    }

    private func clearSelection() {
        selectionStorage = nil
        selectionWitness = [:]
    }

    private func clamp(_ position: TerminalPosition, last: Int, isBlock: Bool) -> TerminalPosition {
        var out = position
        if out.row < firstRow {
            out.row = firstRow
            if !isBlock { out.col = 0 }
        } else if out.row > last {
            out.row = last
            if !isBlock { out.col = cols - 1 }
        }
        out.col = min(max(out.col, 0), cols - 1)
        return out
    }

    private static func parts(_ selection: TerminalSelection) -> (TerminalRange, Bool) {
        switch selection {
        case .linear(let range): return (range, false)
        case .block(let range): return (range, true)
        }
    }

    // MARK: Text of a span

    /// The stored text of `row` for the columns `span` (inclusive), a wide cell included once when either of
    /// its columns is in the span. Cells past the stored text are not listed.
    static func spanText(_ row: TerminalRow, _ span: ClosedRange<Int>) -> String {
        guard span.lowerBound < row.usedColumns else { return "" }
        if row.isASCII {
            let end = min(span.upperBound + 1, row.bytes.count)
            return String(decoding: row.bytes[span.lowerBound..<end], as: UTF8.self)
        }
        var out: [UInt8] = []
        var offset = 0
        var column = 0
        while offset < row.bytes.count && column <= span.upperBound {
            let cell = row.cellStarting(at: offset, column: column)
            if column + cell.width > span.lowerBound { out.append(contentsOf: row.bytes[offset..<cell.byteEnd]) }
            offset = cell.byteEnd
            column += cell.width
        }
        return String(decoding: out, as: UTF8.self)
    }

    static func trimmed(_ text: String) -> String {
        var scalars = text.unicodeScalars[...]
        while scalars.last == " " { scalars = scalars.dropLast() }
        return String(scalars)
    }
}

/// The rows and per-row columns a selection covers, with its ends put in order.
struct SelectionGeometry {
    let isBlock: Bool
    let low: TerminalPosition
    let high: TerminalPosition
    let cols: Int
    private let blockColumns: ClosedRange<Int>

    init(_ selection: TerminalSelection, cols: Int) {
        self.cols = cols
        let range: TerminalRange
        switch selection {
        case .linear(let r): range = r; isBlock = false
        case .block(let r): range = r; isBlock = true
        }
        low = min(range.lowerBound, range.upperBound)
        high = max(range.lowerBound, range.upperBound)
        blockColumns = min(range.lowerBound.col, range.upperBound.col)...max(range.lowerBound.col, range.upperBound.col)
    }

    /// The absolute rows from the first to one past the last.
    var rows: Range<Int> {
        isBlock ? min(low.row, high.row)..<(max(low.row, high.row) + 1) : low.row..<(high.row + 1)
    }

    /// The columns selected on `row`.
    func span(row: Int) -> ClosedRange<Int> {
        if isBlock { return blockColumns }
        return (row == low.row ? low.col : 0)...(row == high.row ? high.col : cols - 1)
    }
}
