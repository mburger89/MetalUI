/// One row of a terminal grid, stored compactly.
///
/// A row is the UTF-8 text of its cells (one grapheme cluster per cell, a wide character once, covering two
/// columns) plus run-length attribute spans; it never holds a struct per cell. A row of default-attribute text
/// has no spans at all, and cells past the stored text are blank. `TerminalRow` is a value type whose arrays are
/// copy-on-write, so copying a row shares its storage until one copy changes (`TRM-F`).
public struct TerminalRow: Sendable, Hashable {
    /// A run of `count` columns sharing one rendition.
    struct Run: Sendable, Hashable {
        var count: Int32
        var attributes: TerminalAttributes
    }

    /// The UTF-8 text of the stored cells, in column order.
    var bytes: [UInt8] = []
    /// Attribute spans covering exactly `used` columns, or empty when every cell has the default rendition.
    var runs: [Run] = []
    /// The width of the grid this row belongs to.
    public internal(set) var columns: Int
    /// The columns the stored text covers; later columns are blank.
    var used: Int32 = 0
    /// True when `bytes` holds no byte at or above 0x80, so column and byte offset coincide.
    var isASCII = true
    /// True when the text continues on the next row because it wrapped at the last column.
    var wrapsToNext = false

    package init(columns: Int) { self.columns = columns }

    var usedColumns: Int { Int(used) }

    // MARK: Reading

    /// The row's text with trailing blanks removed (`TRM-F`).
    public var text: String {
        var end = bytes.count
        while end > 0 && bytes[end - 1] == 0x20 { end -= 1 }
        return String(decoding: bytes[0..<end], as: UTF8.self)
    }

    /// The cell covering `column`; the second column of a wide cell answers with that same cell. Columns past
    /// the stored text, and columns outside the grid, answer a blank default cell.
    public func cell(at column: Int) -> TerminalCell {
        guard column >= 0, column < usedColumns, let located = locate(column) else {
            return TerminalCell(grapheme: " ", width: 1, attributes: TerminalAttributes())
        }
        return makeCell(located)
    }

    /// The stored cells in order, each wide cell once. Trailing blank cells are not listed.
    public var graphemes: [TerminalCell] {
        var out: [TerminalCell] = []
        out.reserveCapacity(usedColumns)
        var offset = 0
        var column = 0
        while offset < bytes.count {
            let cell = cellStarting(at: offset, column: column)
            out.append(makeCell(cell))
            offset = cell.byteEnd
            column += cell.width
        }
        return out
    }

    struct Located {
        var byteStart: Int
        var byteEnd: Int
        var column: Int
        var width: Int
    }

    func attributes(at column: Int) -> TerminalAttributes {
        var start = 0
        for run in runs {
            let end = start + Int(run.count)
            if column < end { return run.attributes }
            start = end
        }
        return TerminalAttributes()
    }

    private func makeCell(_ located: Located) -> TerminalCell {
        let grapheme = String(decoding: bytes[located.byteStart..<located.byteEnd], as: UTF8.self).first ?? " "
        return TerminalCell(grapheme: grapheme, width: located.width, attributes: attributes(at: located.column))
    }

    /// The cell that starts at `offset` (which must be a cell boundary) in column `column`.
    func cellStarting(at offset: Int, column: Int) -> Located {
        if isASCII { return Located(byteStart: offset, byteEnd: offset + 1, column: column, width: 1) }
        var end = offset
        var width = 1
        var first = true
        while end < bytes.count {
            let (scalar, length) = decodeScalar(at: end)
            let w = CharacterWidth.of(scalar)
            if first {
                width = max(w, 1)
                first = false
            } else if w != 0 {
                break
            }
            end += length
        }
        return Located(byteStart: offset, byteEnd: end, column: column, width: width)
    }

    /// The cell covering `column`, or nil when the stored text does not reach it.
    func locate(_ column: Int) -> Located? {
        guard column >= 0, column < usedColumns else { return nil }
        if isASCII { return Located(byteStart: column, byteEnd: column + 1, column: column, width: 1) }
        var offset = 0
        var col = 0
        while offset < bytes.count {
            let cell = cellStarting(at: offset, column: col)
            if column < col + cell.width { return cell }
            offset = cell.byteEnd
            col += cell.width
        }
        return nil
    }

    /// Decodes the scalar at `offset` of the (always valid) stored UTF-8.
    func decodeScalar(at offset: Int) -> (Unicode.Scalar, Int) {
        let b0 = UInt32(bytes[offset])
        if b0 < 0x80 { return (Unicode.Scalar(UInt8(b0)), 1) }
        let length = b0 >= 0xF0 ? 4 : b0 >= 0xE0 ? 3 : 2
        var value = b0 & (length == 2 ? 0x1F : length == 3 ? 0x0F : 0x07)
        for k in 1..<length { value = (value << 6) | (UInt32(bytes[offset + k]) & 0x3F) }
        return (Unicode.Scalar(value) ?? "\u{FFFD}", length)
    }

    // MARK: Writing

    /// Pads the stored text with default blanks up to `column`.
    private mutating func pad(to column: Int) {
        guard column > usedColumns else { return }
        let old = usedColumns
        bytes.append(contentsOf: repeatElement(0x20, count: column - old))
        used = Int32(column)
        if !runs.isEmpty { setAttributes(TerminalAttributes(), in: old..<column) }
    }

    /// Writes ASCII printable bytes at `column`, one cell each. The caller guarantees the run fits the grid.
    mutating func writeASCII(_ run: UnsafeBufferPointer<UInt8>, at column: Int, attributes: TerminalAttributes) {
        let count = run.count
        guard count > 0 else { return }
        if column > usedColumns { pad(to: column) }
        if isASCII {
            if column == usedColumns {
                bytes.append(contentsOf: run)
                used += Int32(count)
                extendTail(by: count, attributes: attributes)
            } else {
                let overlap = min(count, usedColumns - column)
                for k in 0..<overlap { bytes[column + k] = run[k] }
                if overlap < count {
                    bytes.append(contentsOf: UnsafeBufferPointer(rebasing: run[overlap...]))
                    used = Int32(column + count)
                }
                setAttributes(attributes, in: column..<(column + count))
            }
        } else {
            for k in 0..<count { put(Unicode.Scalar(run[k]), width: 1, at: column + k, attributes: attributes) }
        }
    }

    /// Records `count` columns appended at the end of the stored text with `attributes`.
    private mutating func extendTail(by count: Int, attributes: TerminalAttributes) {
        if runs.isEmpty {
            if attributes == TerminalAttributes() { return }
            let before = usedColumns - count
            if before > 0 { runs.append(Run(count: Int32(before), attributes: TerminalAttributes())) }
            runs.append(Run(count: Int32(count), attributes: attributes))
        } else if runs[runs.count - 1].attributes == attributes {
            runs[runs.count - 1].count += Int32(count)
        } else {
            runs.append(Run(count: Int32(count), attributes: attributes))
        }
    }

    /// Writes one character (a base scalar of width 1 or 2) at `column`, replacing what it covers. A wide
    /// character that would overlap half of an existing wide cell turns that half into a blank.
    mutating func put(_ scalar: Unicode.Scalar, width: Int, at column: Int, attributes: TerminalAttributes) {
        var encoded: [UInt8] = []
        encoded.reserveCapacity(4)
        for byte in String(Character(scalar)).utf8 { encoded.append(byte) }
        if scalar.value < 0x80 && width == 1 && isASCII {
            encoded.withUnsafeBufferPointer { writeASCII($0, at: column, attributes: attributes) }
            return
        }
        if column > usedColumns { pad(to: column) }
        if column == usedColumns {
            bytes.append(contentsOf: encoded)
            if encoded.count > 1 || width > 1 { isASCII = false }
            if scalar.value >= 0x80 { isASCII = false }
            used += Int32(width)
            extendTail(by: width, attributes: attributes)
            return
        }
        // Overwrite inside the stored text: find the cells the new one covers.
        let wasASCII = isASCII
        let end = column + width
        var offset = 0
        var col = 0
        var spanStartByte = bytes.count
        var spanStartCol = usedColumns
        var spanEndByte = bytes.count
        var spanEndCol = usedColumns
        var found = false
        while offset < bytes.count {
            let cell = cellStarting(at: offset, column: col)
            if !found && column < col + cell.width {
                found = true
                spanStartByte = cell.byteStart
                spanStartCol = col
            }
            if found && col + cell.width >= end {
                spanEndByte = cell.byteEnd
                spanEndCol = col + cell.width
                break
            }
            offset = cell.byteEnd
            col += cell.width
        }
        var replacement: [UInt8] = []
        if spanStartCol < column { replacement.append(contentsOf: repeatElement(0x20, count: column - spanStartCol)) }
        replacement.append(contentsOf: encoded)
        if spanEndCol > end { replacement.append(contentsOf: repeatElement(0x20, count: spanEndCol - end)) }
        bytes.replaceSubrange(spanStartByte..<spanEndByte, with: replacement)
        used = Int32(max(usedColumns, max(spanEndCol, end)))
        isASCII = wasASCII && scalar.value < 0x80 && width == 1
        setAttributes(attributes, in: column..<end)
    }

    /// A copy with `text` laid over the cells from `column` (an input method's marked text, `TRM-BC`): every grapheme
    /// one cell, or two when wide, in `attributes`, clipped at the last column (a wide character that does not fit is
    /// dropped). `caretCharacter` is a character offset into `text`.
    ///
    /// - Returns: the row, the columns the text covers and the column `caretCharacter` falls on.
    package func overlaying(_ text: String, at column: Int, attributes: TerminalAttributes, caretCharacter: Int = 0)
        -> (row: TerminalRow, covered: Range<Int>, caret: Int) {
        var copy = self
        var at = max(0, column)
        var caret = at
        var index = 0
        for character in text {
            if index == caretCharacter { caret = at }
            index += 1
            var first = true
            var width = 1
            for scalar in character.unicodeScalars {
                let w = CharacterWidth.of(scalar)
                if first {
                    width = max(w, 1)
                    guard at + width <= columns else { break }
                    copy.put(scalar, width: width, at: at, attributes: attributes)
                    first = false
                } else if w == 0 {
                    copy.appendCombining(scalar, toCellAt: at)
                }
            }
            if !first { at += width } else { break }
        }
        if index <= caretCharacter { caret = at }
        return (copy, max(0, column)..<at, caret)
    }

    /// Appends a zero-width scalar to the cell covering `column`. Does nothing when no cell is stored there.
    mutating func appendCombining(_ scalar: Unicode.Scalar, toCellAt column: Int) {
        guard let cell = locate(column) else { return }
        var encoded: [UInt8] = []
        for byte in String(Character(scalar)).utf8 { encoded.append(byte) }
        bytes.insert(contentsOf: encoded, at: cell.byteEnd)
        isASCII = false
    }

    /// Sets the rendition of `range` (clamped to the stored columns), merging equal
    /// neighbours and dropping the spans entirely when every cell is default.
    mutating func setAttributes(_ attributes: TerminalAttributes, in range: Range<Int>) {
        let total = usedColumns
        let lower = min(range.lowerBound, total)
        let upper = min(range.upperBound, total)
        guard lower < upper else { return }
        let plain = TerminalAttributes()
        if runs.isEmpty && attributes == plain { return }
        // Edited in place (`TRM-BL`): the spans are spliced where the range falls, so an overwrite allocates nothing
        // once the array has the capacity it needs.
        if runs.isEmpty { runs.append(Run(count: Int32(total), attributes: plain)) }
        var covered = 0
        for run in runs { covered += Int(run.count) }
        if covered < total {
            // Text was just appended past the spans: extend with default blanks.
            if runs[runs.count - 1].attributes == plain {
                runs[runs.count - 1].count += Int32(total - covered)
            } else {
                runs.append(Run(count: Int32(total - covered), attributes: plain))
            }
        }
        // The spans the range touches: first..<after.
        var first = 0
        var start = 0
        while first < runs.count, start + Int(runs[first].count) <= lower {
            start += Int(runs[first].count)
            first += 1
        }
        var after = first
        var lastStart = start
        var lastEnd = start
        while after < runs.count, lastStart < upper {
            lastEnd = lastStart + Int(runs[after].count)
            if lastEnd >= upper { after += 1; break }
            lastStart = lastEnd
            after += 1
        }
        guard first < after else { return }
        // Up to three pieces replace them: what is left of the first span, the new span, what is left of the last.
        let firstAttributes = runs[first].attributes
        let lastAttributes = runs[after - 1].attributes
        let head = lower - start
        let tail = lastEnd - upper
        var pieces = 0
        func place(_ count: Int, _ attrs: TerminalAttributes) {
            let slot = first + pieces
            pieces += 1
            let run = Run(count: Int32(count), attributes: attrs)
            if slot < after { runs[slot] = run } else { runs.insert(run, at: slot) }
        }
        let wasAfter = after
        if head > 0 { place(head, firstAttributes) }
        place(upper - lower, attributes)
        if tail > 0 { place(tail, lastAttributes) }
        if first + pieces < wasAfter { runs.removeSubrange((first + pieces)..<wasAfter) }
        mergeEqualNeighbours()
        if runs.count == 1 && runs[0].attributes == plain { runs.removeAll(keepingCapacity: true) }
    }

    /// Joins adjacent spans of equal rendition, in place.
    private mutating func mergeEqualNeighbours() {
        guard runs.count > 1 else { return }
        var write = 0
        for read in 1..<runs.count {
            if runs[read].attributes == runs[write].attributes {
                runs[write].count += runs[read].count
            } else {
                write += 1
                if write != read { runs[write] = runs[read] }
            }
        }
        if write + 1 < runs.count { runs.removeSubrange((write + 1)...) }
    }

    /// Drops trailing default blanks and shrinks both arrays to a tight size, in place. Called when a row leaves
    /// the screen for scrollback (`TRM-F`); an array that already wastes under 16 bytes is kept as it is. A row
    /// that wraps to the next keeps its blanks: they are text of a longer line (`TRM-AN`).
    mutating func compact() {
        var end = bytes.count
        if runs.isEmpty && !wrapsToNext { while end > 0 && bytes[end - 1] == 0x20 { end -= 1 } }
        used -= Int32(bytes.count - end)
        if bytes.capacity - end > 16 {
            var tight: [UInt8] = []
            tight.reserveCapacity(end)
            tight.append(contentsOf: bytes[0..<end])
            bytes = tight
        } else if end < bytes.count {
            bytes.removeLast(bytes.count - end)
        }
        if !runs.isEmpty && runs.capacity - runs.count > 1 {
            var tight: [Run] = []
            tight.reserveCapacity(runs.count)
            tight.append(contentsOf: runs)
            runs = tight
        }
    }

    /// A compacted copy; the receiver is untouched.
    func compacted() -> TerminalRow {
        var row = self
        row.compact()
        return row
    }

    /// Heap bytes this row's two arrays hold, for the byte census (header plus capacity, 16-byte granules).
    var heapByteCount: Int {
        func block(_ capacity: Int, _ stride: Int) -> Int {
            capacity == 0 ? 0 : (32 + capacity * stride + 15) / 16 * 16
        }
        return block(bytes.capacity, 1) + block(runs.capacity, MemoryLayout<Run>.stride)
    }
}
