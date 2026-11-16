/// Row edits for erase and insert/delete (`TRM-AA`): in-place truncation or byte splicing on the common ASCII
/// paths, and a column-slot rebuild for everything else (wide cells, attribute spans).
extension TerminalRow {
    /// One column as the rebuild sees it. A wide cell is a width-2 head followed by a width-0 continuation.
    fileprivate struct Slot {
        /// Byte range of the cell's text in the old `bytes`; `start` is -1 for a blank space.
        var start: Int32
        var end: Int32
        /// 0 (second column of a wide cell), 1 or 2.
        var width: UInt8
        var attributes: TerminalAttributes

        static func blank(_ attributes: TerminalAttributes) -> Slot {
            Slot(start: -1, end: -1, width: 1, attributes: attributes)
        }
    }

    /// A row of `columns` blanks that all carry `attributes` (a background-colour erase).
    init(columns: Int, blank attributes: TerminalAttributes) {
        self.init(columns: columns)
        guard attributes != TerminalAttributes() else { return }
        bytes = [UInt8](repeating: 0x20, count: columns)
        runs = [Run(count: Int32(columns), attributes: attributes)]
        used = Int32(columns)
    }

    /// A row of `columns` copies of the ASCII byte `byte` in the default rendition.
    init(columns: Int, filledWith byte: UInt8) {
        self.init(columns: columns)
        bytes = [UInt8](repeating: byte, count: columns)
        used = Int32(columns)
    }

    private var isPlainText: Bool { isASCII && runs.isEmpty }

    // MARK: Erase

    /// Replaces the cells in `range` with blanks carrying `attributes`. A wide cell the range cuts in half is
    /// blanked whole. Erasing to the end of the row ends any soft wrap.
    mutating func erase(_ range: Range<Int>, attributes: TerminalAttributes) {
        let lower = max(0, range.lowerBound)
        let upper = min(columns, range.upperBound)
        guard lower < upper else { return }
        if upper == columns { wrapsToNext = false }
        let plain = attributes == TerminalAttributes()
        if plain && lower >= usedColumns { return }
        if plain && upper == columns {
            var cutColumn = lower
            var cutByte = lower
            if !isASCII, let cell = locate(lower) {
                cutColumn = cell.column
                cutByte = cell.byteStart
            }
            bytes.removeSubrange(cutByte...)
            used = Int32(cutColumn)
            trimRuns(to: cutColumn)
            return
        }
        var slots = makeSlots()
        for index in lower..<upper { slots[index] = .blank(attributes) }
        rebuild(slots)
    }

    private mutating func trimRuns(to column: Int) {
        guard !runs.isEmpty else { return }
        var kept: [Run] = []
        var covered = 0
        for run in runs {
            guard covered < column else { break }
            let take = min(Int(run.count), column - covered)
            kept.append(Run(count: Int32(take), attributes: run.attributes))
            covered += take
        }
        if kept.count == 1 && kept[0].attributes == TerminalAttributes() { kept = [] }
        runs = kept
    }

    // MARK: Insert and delete

    /// ICH: shifts the cells from `column` right by `count`, dropping what leaves the row, and puts blanks
    /// carrying `attributes` in the gap.
    mutating func insertBlanks(at column: Int, count: Int, attributes: TerminalAttributes) {
        guard column >= 0, column < columns else { return }
        let n = min(count, columns - column)
        guard n > 0 else { return }
        let plain = attributes == TerminalAttributes()
        if column >= usedColumns {
            if !plain { erase(column..<(column + n), attributes: attributes) }
            return
        }
        if plain && isPlainText {
            bytes.insert(contentsOf: repeatElement(0x20, count: n), at: column)
            used += Int32(n)
            if usedColumns > columns {
                bytes.removeLast(usedColumns - columns)
                used = Int32(columns)
            }
            return
        }
        var slots = makeSlots()
        slots.insert(contentsOf: repeatElement(Slot.blank(attributes), count: n), at: column)
        slots.removeLast(n)
        rebuild(slots)
    }

    /// DCH: removes `count` cells at `column`, shifting the rest left and filling the right end with blanks
    /// carrying `attributes`.
    mutating func deleteCharacters(at column: Int, count: Int, attributes: TerminalAttributes) {
        guard column >= 0, column < columns else { return }
        let n = min(count, columns - column)
        guard n > 0 else { return }
        let plain = attributes == TerminalAttributes()
        if plain && column >= usedColumns { return }
        if plain && isPlainText {
            let removed = min(n, usedColumns - column)
            bytes.removeSubrange(column..<(column + removed))
            used -= Int32(removed)
            return
        }
        var slots = makeSlots()
        slots.removeSubrange(column..<(column + n))
        slots.append(contentsOf: repeatElement(Slot.blank(attributes), count: n))
        rebuild(slots)
    }

    // MARK: Slots

    /// One slot per grid column.
    private func makeSlots() -> [Slot] {
        var out: [Slot] = []
        out.reserveCapacity(columns)
        let plain = TerminalAttributes()
        var runIndex = 0
        var runStart = 0
        var offset = 0
        var column = 0
        while offset < bytes.count && column < columns {
            let cell = cellStarting(at: offset, column: column)
            while runIndex < runs.count && column >= runStart + Int(runs[runIndex].count) {
                runStart += Int(runs[runIndex].count)
                runIndex += 1
            }
            let attributes = runIndex < runs.count ? runs[runIndex].attributes : plain
            out.append(Slot(start: Int32(cell.byteStart), end: Int32(cell.byteEnd), width: UInt8(cell.width),
                            attributes: attributes))
            if cell.width == 2 { out.append(Slot(start: -1, end: -1, width: 0, attributes: attributes)) }
            offset = cell.byteEnd
            column += cell.width
        }
        while out.count < columns { out.append(.blank(plain)) }
        if out.count > columns { out.removeLast(out.count - columns) }
        return out
    }

    /// Makes `slots` (exactly `columns` of them) the row: halves of wide cells whose partner is gone become
    /// blanks, trailing default blanks are dropped, and equal neighbouring attributes merge into one span.
    private mutating func rebuild(_ input: [Slot]) {
        var slots = input
        for index in 0..<slots.count {
            if slots[index].width == 2 && !(index + 1 < slots.count && slots[index + 1].width == 0) {
                slots[index] = .blank(slots[index].attributes)
            } else if slots[index].width == 0 && !(index > 0 && slots[index - 1].width == 2) {
                slots[index] = .blank(slots[index].attributes)
            }
        }
        let plain = TerminalAttributes()
        var limit = slots.count
        while limit > 0 {
            let slot = slots[limit - 1]
            let isBlank = slot.width == 1 && slot.attributes == plain
                && (slot.start < 0 || (slot.end - slot.start == 1 && bytes[Int(slot.start)] == 0x20))
            if !isBlank { break }
            limit -= 1
        }
        var newBytes: [UInt8] = []
        newBytes.reserveCapacity(limit + 8)
        var newRuns: [Run] = []
        var ascii = true
        var anyAttributes = false
        for index in 0..<limit {
            let slot = slots[index]
            if slot.width == 0 { continue }
            if slot.start < 0 {
                newBytes.append(0x20)
            } else {
                for k in Int(slot.start)..<Int(slot.end) {
                    let byte = bytes[k]
                    if byte >= 0x80 { ascii = false }
                    newBytes.append(byte)
                }
            }
            if slot.attributes != plain { anyAttributes = true }
            if let last = newRuns.last, last.attributes == slot.attributes {
                newRuns[newRuns.count - 1].count += Int32(slot.width)
            } else {
                newRuns.append(Run(count: Int32(slot.width), attributes: slot.attributes))
            }
        }
        bytes = newBytes
        runs = anyAttributes ? newRuns : []
        used = Int32(limit)
        isASCII = ascii
    }
}
