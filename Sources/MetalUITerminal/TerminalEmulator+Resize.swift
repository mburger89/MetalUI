/// Resize and reflow (`TRM-AM`..`TRM-AP`): the primary screen and its scrollback rewrap to the new width and
/// follow the cursor; the alternate screen clips.
extension TerminalEmulator {
    /// A cell position the reflow carries across: `row` indexes the physical rows (scrollback then screen).
    fileprivate struct Point {
        var row: Int
        var col: Int
        var pending: Bool
        var newRow = 0
        var newCol = 0
        var newPending = false
    }

    /// Resizes the grid to `cols` x `rows` (clamped to at least 2 x 1). A no-op when the size is unchanged.
    ///
    /// The primary screen and its scrollback are reflowed (soft-wrapped lines rejoin and rewrap, the cursor stays
    /// on its character, a wide character never splits at the edge); the alternate screen clips. Publishes a full
    /// frame next. See `TRM-AM`..`TRM-AP` for what happens to the scroll region, tab stops, saved cursors and
    /// absolute row numbers.
    public func resize(cols newCols: Int, rows newRows: Int) {
        let size = TerminalSize(cols: newCols, rows: newRows)
        guard size.cols != cols || size.rows != rows else { return }
        let width = size.cols
        let height = size.rows
        let oldCols = cols
        let oldRows = rows
        let oldFirstRow = firstRow
        let capacity = scrollback.capacity

        // The primary screen's rows and the positions to follow through the rewrap.
        let primary = onAlternate ? offscreen : screen
        let history = scrollback.rows
        let historyCount = history.count
        var points: [Point] = []
        var cursorIndex: Int?
        var savedIndex: Int?
        if !onAlternate {
            cursorIndex = points.count
            points.append(Point(row: historyCount + cursorRow, col: cursorCol, pending: pendingWrap))
        }
        if let saved = savedCursors[0] {
            savedIndex = points.count
            points.append(Point(row: historyCount + saved.row, col: saved.col, pending: saved.pendingWrap))
            if onAlternate { cursorIndex = savedIndex }
        }
        var all = history
        all.append(contentsOf: primary)

        // The content ends at the last row holding anything or a tracked position; the blank tail is re-made.
        var end = all.count
        while end > historyCount && all[end - 1].isBlankHard { end -= 1 }
        for point in points where point.row < all.count { end = max(end, point.row + 1) }
        while end < all.count && end > 0 && all[end - 1].wrapsToNext { end += 1 }
        let topIndex = points.count
        if historyCount < end { points.append(Point(row: historyCount, col: 0, pending: false)) }
        let hasTop = historyCount < end
        // Points in the blank tail are clamped rather than followed.
        let followed = points.indices.filter { points[$0].row < end }
        var tracked = followed.map { points[$0] }
        var content = Array(all[0..<end])

        if width != oldCols {
            content = Self.reflow(content, from: oldCols, to: width, points: &tracked)
        } else {
            for index in tracked.indices {
                tracked[index].newRow = tracked[index].row
                tracked[index].newCol = tracked[index].col
                tracked[index].newPending = tracked[index].pending
            }
        }
        func result(_ original: Int) -> Point? {
            followed.firstIndex(of: original).map { tracked[$0] }
        }

        // Which content row is the screen's top.
        let topRow = hasTop ? result(topIndex)!.newRow : content.count
        let cursorNew = cursorIndex.flatMap { result($0) }
        var top = max(0, topRow - max(0, height - oldRows))
        let reference = cursorNew?.newRow ?? max(content.count - 1, 0)
        top = max(top, min(content.count - height, reference))
        top = min(top, content.count)

        // Scrollback keeps the newest rows that fit; the rest are evicted and the oldest absolute row moves on.
        var kept = Array(content[0..<top])
        let evicted = max(0, kept.count - capacity)
        if evicted > 0 { kept.removeFirst(evicted) }
        for index in kept.indices where kept[index].usedColumns > 0 || !kept[index].runs.isEmpty { kept[index].compact() }
        var newScreen: [TerminalRow] = []
        newScreen.reserveCapacity(height)
        for index in 0..<height {
            newScreen.append(top + index < content.count ? content[top + index] : TerminalRow(columns: width))
        }
        scrollback = ScrollbackRing(capacity: capacity, keeping: kept)
        scrolledOff = oldFirstRow + evicted + kept.count

        // The alternate screen's rows (showing or not) are clipped, never rewrapped.
        let other = Self.clip(onAlternate ? screen : offscreen, columns: width, rows: height)
        if onAlternate {
            offscreen = newScreen
            screen = other
        } else {
            screen = newScreen
            offscreen = other
        }

        // Cursors.
        if let cursorNew, !onAlternate {
            cursorRow = min(max(cursorNew.newRow - top, 0), height - 1)
            cursorCol = min(cursorNew.newCol, width - 1)
            pendingWrap = cursorNew.newPending
        } else {
            cursorRow = min(cursorRow, height - 1)
            cursorCol = min(cursorCol, width - 1)
            pendingWrap = false
        }
        if var saved = savedCursors[0] {
            if let savedIndex, let moved = result(savedIndex) {
                saved.row = min(max(moved.newRow - top, 0), height - 1)
                saved.col = min(moved.newCol, width - 1)
                saved.pendingWrap = moved.newPending
            } else {
                saved.row = min(saved.row, height - 1)
                saved.col = min(saved.col, width - 1)
                saved.pendingWrap = false
            }
            savedCursors[0] = saved
        }
        if var saved = savedCursors[1] {
            saved.row = min(saved.row, height - 1)
            saved.col = min(saved.col, width - 1)
            saved.pendingWrap = false
            savedCursors[1] = saved
        }

        // Region, tab stops and damage.
        cols = width
        rows = height
        regionTop = 0
        regionBottom = height - 1
        tabStops = (0..<width).map { $0 < oldCols ? tabStops[$0] : ($0 % 8 == 0 && $0 > 0) }
        dirty = Array(repeating: true, count: height)
        needsFullFrame = true
        if width != oldCols { reflowGeneration += 1 }
    }

    /// `rows` clipped to `columns` x `rows` (cells past the edge are cut, a wide cell cut in half is blanked)
    /// and padded with blank rows.
    fileprivate static func clip(_ source: [TerminalRow], columns: Int, rows: Int) -> [TerminalRow] {
        var out: [TerminalRow] = []
        out.reserveCapacity(rows)
        for index in 0..<rows {
            guard index < source.count else {
                out.append(TerminalRow(columns: columns))
                continue
            }
            var row = source[index]
            if columns < row.columns { row.erase(columns..<row.columns, attributes: TerminalAttributes()) }
            row.columns = columns
            out.append(row)
        }
        return out
    }

    // MARK: Rewrap

    /// Rewraps `rows` (physical rows from `oldCols` wide) to `width`, following `points`.
    fileprivate static func reflow(_ rows: [TerminalRow], from oldCols: Int, to width: Int,
                                   points: inout [Point]) -> [TerminalRow] {
        var out: [TerminalRow] = []
        out.reserveCapacity(rows.count + rows.count / 8)
        var start = 0
        while start < rows.count {
            var last = start
            while rows[last].wrapsToNext && last + 1 < rows.count { last += 1 }
            let line = points.indices.filter { points[$0].row >= start && points[$0].row <= last }
            reflowLine(rows, start...last, from: oldCols, to: width, points: &points, line: line, into: &out)
            start = last + 1
        }
        return out
    }

    fileprivate static func reflowLine(_ rows: [TerminalRow], _ span: ClosedRange<Int>, from oldCols: Int, to width: Int,
                                       points: inout [Point], line: [Int], into out: inout [TerminalRow]) {
        let base = out.count
        // A line of one row that still fits needs no rewrap.
        if span.count == 1 {
            let row = rows[span.lowerBound]
            let content = row.trimmedContent
            let fits = line.allSatisfy { points[$0].col + (points[$0].pending ? 1 : 0) < width }
            if content.columns <= width && fits {
                var copy = row
                if content.columns < copy.usedColumns { copy.truncate(columns: content.columns, bytes: content.bytes) }
                copy.columns = width
                copy.wrapsToNext = false
                for index in line {
                    points[index].newRow = base
                    points[index].newCol = points[index].col + (points[index].pending ? 1 : 0)
                    points[index].newPending = false
                }
                out.append(copy)
                return
            }
        }
        // Join the rows into one line of cells.
        var joined = TerminalRow(columns: 0)
        var runs: [TerminalRow.Run] = []
        var anyRuns = false
        var columns = 0
        let plain = TerminalAttributes()
        func addRun(_ count: Int, _ attributes: TerminalAttributes) {
            guard count > 0 else { return }
            if let last = runs.last, last.attributes == attributes {
                runs[runs.count - 1].count += Int32(count)
            } else {
                runs.append(TerminalRow.Run(count: Int32(count), attributes: attributes))
            }
        }
        var starts: [Int] = []
        for index in span {
            let row = rows[index]
            starts.append(columns)
            joined.bytes.append(contentsOf: row.bytes)
            if !row.isASCII { joined.isASCII = false }
            if row.runs.isEmpty {
                if anyRuns { addRun(row.usedColumns, plain) }
            } else {
                if !anyRuns {
                    anyRuns = true
                    addRun(columns, plain)
                }
                for run in row.runs { addRun(Int(run.count), run.attributes) }
            }
            columns += row.usedColumns
            if index != span.upperBound {
                var pad = oldCols - row.usedColumns
                // A wide character that did not fit at the edge left the last column empty: not a blank to carry.
                if pad == 1, rows[index + 1].startsWithWideCell { pad = 0 }
                if pad > 0 {
                    joined.bytes.append(contentsOf: repeatElement(0x20, count: pad))
                    if anyRuns { addRun(pad, plain) }
                    columns += pad
                }
            }
        }
        joined.runs = anyRuns ? runs : []
        joined.used = Int32(columns)
        let content = joined.trimmedContent
        if content.columns < columns { joined.truncate(columns: content.columns, bytes: content.bytes) }

        // The line is at least as long as the furthest tracked position.
        var extent = content.columns
        for index in line {
            let offset = starts[points[index].row - span.lowerBound] + points[index].col
            extent = max(extent, offset + 1)
        }
        if extent > joined.usedColumns {
            let pad = extent - joined.usedColumns
            joined.bytes.append(contentsOf: repeatElement(0x20, count: pad))
            if !joined.runs.isEmpty { joined.runs.append(TerminalRow.Run(count: Int32(pad), attributes: plain)) }
            joined.used = Int32(extent)
        }

        // Cut it into rows of `width`, never splitting a wide cell.
        var cuts: [(bytes: Range<Int>, columns: Range<Int>)] = []
        if joined.isASCII {
            var a = 0
            repeat {
                let b = min(a + width, extent)
                cuts.append((a..<b, a..<b))
                a = b
            } while a < extent
        } else {
            var offset = 0
            var column = 0
            var rowByte = 0
            var rowColumn = 0
            while offset < joined.bytes.count {
                let cell = joined.cellStarting(at: offset, column: column)
                if column - rowColumn + cell.width > width {
                    cuts.append((rowByte..<offset, rowColumn..<column))
                    rowByte = offset
                    rowColumn = column
                }
                offset = cell.byteEnd
                column += cell.width
            }
            cuts.append((rowByte..<offset, rowColumn..<column))
        }
        var cursor = RunCursor(runs: joined.runs)
        for (number, cut) in cuts.enumerated() {
            var row = TerminalRow(columns: width)
            // Blanks added only to hold a tracked position are not stored.
            let stored = min(max(content.columns, cut.columns.lowerBound), cut.columns.upperBound)
            let dropped = cut.columns.upperBound - stored
            row.bytes = Array(joined.bytes[cut.bytes.lowerBound..<(cut.bytes.upperBound - dropped)])
            row.used = Int32(stored - cut.columns.lowerBound)
            row.isASCII = joined.isASCII || !row.bytes.contains { $0 >= 0x80 }
            row.runs = cursor.take(cut.columns.count)
            if dropped > 0 { row.dropTrailingRunColumns(dropped) }
            row.wrapsToNext = number + 1 < cuts.count
            out.append(row)
        }
        for index in line {
            let point = points[index]
            let offset = starts[point.row - span.lowerBound] + point.col + (point.pending ? 1 : 0)
            if let number = cuts.firstIndex(where: { $0.columns.contains(offset) }) {
                points[index].newRow = base + number
                points[index].newCol = offset - cuts[number].columns.lowerBound
                points[index].newPending = false
            } else {
                // Just past the last cell: a pending wrap on a full row, the next column otherwise.
                let lastCut = cuts[cuts.count - 1]
                points[index].newRow = base + cuts.count - 1
                if lastCut.columns.count >= width {
                    points[index].newCol = width - 1
                    points[index].newPending = true
                } else {
                    points[index].newCol = lastCut.columns.count
                    points[index].newPending = false
                }
            }
        }
    }
}

/// Hands out consecutive column ranges of a row's attribute spans.
private struct RunCursor {
    let runs: [TerminalRow.Run]
    var index = 0
    var consumed = 0

    init(runs: [TerminalRow.Run]) { self.runs = runs }

    mutating func take(_ count: Int) -> [TerminalRow.Run] {
        guard !runs.isEmpty else { return [] }
        var need = count
        var out: [TerminalRow.Run] = []
        while need > 0 && index < runs.count {
            let run = runs[index]
            let n = min(Int(run.count) - consumed, need)
            if let last = out.last, last.attributes == run.attributes {
                out[out.count - 1].count += Int32(n)
            } else {
                out.append(TerminalRow.Run(count: Int32(n), attributes: run.attributes))
            }
            need -= n
            consumed += n
            if consumed == Int(run.count) {
                index += 1
                consumed = 0
            }
        }
        if out.count == 1 && out[0].attributes == TerminalAttributes() { return [] }
        return out
    }
}

extension TerminalRow {
    /// True for a row with nothing stored, no attributes and no soft wrap.
    fileprivate var isBlankHard: Bool { used == 0 && runs.isEmpty && !wrapsToNext }

    /// True when the first cell is a wide character.
    fileprivate var startsWithWideCell: Bool {
        !isASCII && !bytes.isEmpty && cellStarting(at: 0, column: 0).width == 2
    }

    /// The columns and bytes left when trailing blanks in the default rendition are dropped.
    fileprivate var trimmedContent: (columns: Int, bytes: Int) {
        var column = usedColumns
        var byte = bytes.count
        if runs.isEmpty {
            while byte > 0 && bytes[byte - 1] == 0x20 {
                byte -= 1
                column -= 1
            }
            return (column, byte)
        }
        let plain = TerminalAttributes()
        var index = runs.count - 1
        outer: while index >= 0 && runs[index].attributes == plain {
            var remaining = Int(runs[index].count)
            while remaining > 0 {
                guard byte > 0 && bytes[byte - 1] == 0x20 else { break outer }
                byte -= 1
                column -= 1
                remaining -= 1
            }
            index -= 1
        }
        return (column, byte)
    }

    /// Removes the last `count` columns from the attribute spans (their text is already gone).
    fileprivate mutating func dropTrailingRunColumns(_ count: Int) {
        guard !runs.isEmpty else { return }
        var left = count
        while left > 0, let last = runs.last {
            if Int(last.count) <= left {
                left -= Int(last.count)
                runs.removeLast()
            } else {
                runs[runs.count - 1].count -= Int32(left)
                left = 0
            }
        }
        if runs.count == 1 && runs[0].attributes == TerminalAttributes() { runs = [] }
    }

    /// Cuts the stored text to `columns` columns and `bytes` bytes (a cell boundary).
    fileprivate mutating func truncate(columns: Int, bytes count: Int) {
        bytes.removeSubrange(count...)
        used = Int32(columns)
        guard !runs.isEmpty else { return }
        var kept: [Run] = []
        var covered = 0
        for run in runs {
            guard covered < columns else { break }
            let take = min(Int(run.count), columns - covered)
            kept.append(Run(count: Int32(take), attributes: run.attributes))
            covered += take
        }
        if kept.count == 1 && kept[0].attributes == TerminalAttributes() { kept = [] }
        runs = kept
    }
}
