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

    init(columns: Int) { self.columns = columns }

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
        var old = runs
        if old.isEmpty { old = [Run(count: Int32(total), attributes: plain)] }
        // Spans cover exactly the stored columns; extend with default blanks when text was just appended past them.
        let covered = old.reduce(0) { $0 + Int($1.count) }
        if covered < total { old.append(Run(count: Int32(total - covered), attributes: plain)) }
        var out: [Run] = []
        out.reserveCapacity(old.count + 2)
        func emit(_ count: Int, _ attrs: TerminalAttributes) {
            guard count > 0 else { return }
            if let last = out.last, last.attributes == attrs {
                out[out.count - 1].count += Int32(count)
            } else {
                out.append(Run(count: Int32(count), attributes: attrs))
            }
        }
        var start = 0
        for run in old {
            let end = start + Int(run.count)
            emit(max(0, min(end, lower) - start), run.attributes)
            let a = max(start, lower)
            let b = min(end, upper)
            if a < b { emit(b - a, attributes) }
            emit(max(0, end - max(start, upper)), run.attributes)
            start = end
        }
        if out.count == 1 && out[0].attributes == plain { out = [] }
        runs = out
    }

    /// Drops trailing default blanks and shrinks both arrays to a tight size, in place. Called when a row leaves
    /// the screen for scrollback (`TRM-F`); an array that already wastes under 16 bytes is kept as it is.
    mutating func compact() {
        var end = bytes.count
        if runs.isEmpty { while end > 0 && bytes[end - 1] == 0x20 { end -= 1 } }
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
