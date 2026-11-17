/// Search and the word and line boundaries a selection gesture needs (`TRM-AS`, `TRM-AT`).
extension TerminalEmulator {
    /// Finds `needle` in the scrollback and the screen, case-sensitively, with soft-wrapped rows searched as one
    /// line so a match can span a wrap. A match is a run of whole cells; the returned range runs from its first
    /// cell to the last column of its last cell, so it can be assigned to ``selection`` as it is.
    ///
    /// Forward finds the first match whose `lowerBound` is at or after `from`; backwards finds the last match
    /// whose `upperBound` is before `from`. A search never wraps around: nil means no match in that direction,
    /// and the caller decides whether to start again from the other end. An empty needle, or one with a line
    /// break, never matches. To find the next match, pass the previous match's `lowerBound` advanced by one
    /// column (forward) or its `lowerBound` (backwards).
    public func search(_ needle: String, from: TerminalPosition, backwards: Bool) -> TerminalRange? {
        let target = Array(needle.utf8)
        guard !target.isEmpty, !target.contains(0x0A), !target.contains(0x0D) else { return nil }
        let last = scrolledOff + rows - 1
        if backwards {
            var start = min(from.row, last)
            let origin = from.row > last ? TerminalPosition(row: last, col: Int.max) : from
            if start < firstRow { return nil }
            while true {
                let first = lineStart(of: start)
                if let hit = matches(of: target, inLineFrom: first).last(where: { $0.upperBound < origin }) {
                    return hit
                }
                if first <= firstRow { return nil }
                start = first - 1
            }
        }
        if from.row > last { return nil }
        let origin = from.row < firstRow ? TerminalPosition(row: firstRow, col: 0) : from
        var first = lineStart(of: origin.row)
        while first <= last {
            if let hit = matches(of: target, inLineFrom: first).first(where: { $0.lowerBound >= origin }) {
                return hit
            }
            first = lineEnd(of: first) + 1
        }
        return nil
    }

    /// The first row of the logical line `row` belongs to.
    func lineStart(of row: Int) -> Int {
        var row = row
        while row > firstRow, self.row(at: row - 1)?.wrapsToNext == true { row -= 1 }
        return row
    }

    /// The last row of the logical line starting at or containing `row`.
    func lineEnd(of row: Int) -> Int {
        var row = row
        let last = scrolledOff + rows - 1
        while row < last, self.row(at: row)?.wrapsToNext == true { row += 1 }
        return row
    }

    /// Every match of `target` (UTF-8) in the logical line that starts at row `first`, in order, as cell ranges.
    private func matches(of target: [UInt8], inLineFrom first: Int) -> [TerminalRange] {
        let end = lineEnd(of: first)
        var bytes: [UInt8] = []
        var bases: [Int] = []
        for row in first...end {
            bases.append(bytes.count)
            if let stored = self.row(at: row) { bytes += stored.bytes }
        }
        guard bytes.count >= target.count else { return [] }
        var out: [TerminalRange] = []
        var index = 0
        let limit = bytes.count - target.count
        while index <= limit {
            if bytes[index] == target[0] && bytes[index..<(index + target.count)].elementsEqual(target),
               let lower = cell(inLineFrom: first, bases: bases, byte: index, wantsStart: true),
               let upper = cell(inLineFrom: first, bases: bases, byte: index + target.count - 1, wantsStart: false) {
                out.append(TerminalRange(lowerBound: lower, upperBound: upper))
            }
            index += 1
        }
        return out
    }

    /// The position of the cell holding byte `byte` of a line's joined text: its first column when `wantsStart`
    /// (and then the byte must begin the cell), else its last column (and the byte must end the cell). Nil when
    /// the byte falls inside a cell, so a needle never matches half a grapheme.
    private func cell(inLineFrom first: Int, bases: [Int], byte: Int, wantsStart: Bool) -> TerminalPosition? {
        var segment = 0
        while segment + 1 < bases.count && bases[segment + 1] <= byte { segment += 1 }
        guard let stored = row(at: first + segment) else { return nil }
        let local = byte - bases[segment]
        if stored.isASCII { return TerminalPosition(row: first + segment, col: local) }
        var offset = 0
        var column = 0
        while offset < stored.bytes.count {
            let cell = stored.cellStarting(at: offset, column: column)
            if local < cell.byteEnd {
                guard wantsStart ? local == offset : local + 1 == cell.byteEnd else { return nil }
                return TerminalPosition(row: first + segment, col: wantsStart ? column : column + cell.width - 1)
            }
            offset = cell.byteEnd
            column += cell.width
        }
        return nil
    }

    // MARK: Word and line boundaries (Phase 5 gestures)

    /// The default word characters besides letters and digits, as Terminal.app's double-click uses them.
    package static let defaultWordCharacters = "_-.~/:"

    /// The range a double-click at `position` selects: the run of cells of the same kind around it, along the
    /// logical line (so across soft wraps). Kinds: a word cell (a letter or digit of any script, or one of
    /// `wordCharacters`), a blank cell (a space, or a cell past the text), and any other character, which
    /// selects the run of that same character. Nil when `position` is not on an existing row or column.
    package func wordRange(at position: TerminalPosition,
                           wordCharacters: String = TerminalEmulator.defaultWordCharacters) -> TerminalRange? {
        guard position.col >= 0, position.col < cols, row(at: position.row) != nil else { return nil }
        let extra = Set(wordCharacters)
        let first = lineStart(of: position.row)
        var cells: [(row: Int, col: Int, width: Int, kind: Int, character: Character)] = []
        var hit = 0
        for row in first...lineEnd(of: position.row) {
            guard let stored = self.row(at: row) else { continue }
            var column = 0
            for grapheme in stored.graphemes {
                cells.append((row, column, grapheme.width, Self.kind(grapheme.grapheme, extra), grapheme.grapheme))
                column += grapheme.width
            }
            // A wrapped row ends where its text does (a wide character that did not fit leaves a gap column).
            if !stored.wrapsToNext { cells.append(contentsOf: Self.blankCells(row: row, from: column, to: cols)) }
        }
        for (index, cell) in cells.enumerated() where cell.row == position.row && cell.col <= position.col
            && position.col < cell.col + cell.width { hit = index }
        func same(_ a: Int, _ b: Int) -> Bool {
            cells[a].kind == cells[b].kind && (cells[a].kind != 2 || cells[a].character == cells[b].character)
        }
        var lower = hit
        while lower > 0 && same(lower - 1, hit) { lower -= 1 }
        var upper = hit
        while upper + 1 < cells.count && same(upper + 1, hit) { upper += 1 }
        return TerminalRange(lowerBound: TerminalPosition(row: cells[lower].row, col: cells[lower].col),
                             upperBound: TerminalPosition(row: cells[upper].row,
                                                          col: cells[upper].col + cells[upper].width - 1))
    }

    /// The range a triple-click at `position` selects: the whole logical line, first column of its first row to
    /// last column of its last row. Trailing blanks drop out of ``selectedText()``. Nil for a row that does not
    /// exist.
    package func lineRange(at position: TerminalPosition) -> TerminalRange? {
        guard row(at: position.row) != nil else { return nil }
        return TerminalRange(lowerBound: TerminalPosition(row: lineStart(of: position.row), col: 0),
                             upperBound: TerminalPosition(row: lineEnd(of: position.row), col: cols - 1))
    }

    private static func kind(_ character: Character, _ extra: Set<Character>) -> Int {
        if character == " " { return 1 }
        if extra.contains(character) || character.isLetter || character.isNumber { return 0 }
        return 2
    }

    private static func blankCells(row: Int, from: Int, to: Int)
        -> [(row: Int, col: Int, width: Int, kind: Int, character: Character)] {
        guard from < to else { return [] }
        return (from..<to).map { (row, $0, 1, 1, " ") }
    }
}
