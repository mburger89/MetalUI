extension TerminalRow {
    /// Visits every stored cell in column order, each wide cell once, with the UTF-8 bytes of its grapheme
    /// cluster and its rendition (`TRM-AZ`, the view's draw loop). Blank columns past the stored text are not
    /// visited: they are default blanks. One pass over the bytes and the runs, no allocation per cell (the
    /// bytes are a slice of the row's own storage), so a row of cached ASCII costs the view no heap work.
    package func forEachCell(
        _ body: (_ column: Int, _ width: Int, _ bytes: ArraySlice<UInt8>, _ attributes: TerminalAttributes) -> Void
    ) {
        var offset = 0
        var column = 0
        var runIndex = 0
        var runLeft = runs.isEmpty ? 0 : Int(runs[0].count)
        let plain = TerminalAttributes()
        while offset < bytes.count {
            let cell = cellStarting(at: offset, column: column)
            while runLeft <= 0, runIndex + 1 < runs.count {
                runIndex += 1
                runLeft = Int(runs[runIndex].count)
            }
            body(column, cell.width, bytes[cell.byteStart..<cell.byteEnd],
                 runIndex < runs.count && runLeft > 0 ? runs[runIndex].attributes : plain)
            runLeft -= cell.width
            offset = cell.byteEnd
            column += cell.width
        }
    }

    /// ``forEachCell(_:)`` with the index of the run each cell belongs to instead of its attributes: `-1` for a default
    /// cell (no run), else an index into the row's runs, whose attributes ``attributes(ofRun:)`` answers. Cells of one
    /// run share the index, so a caller resolves a run once rather than every cell (`TRM-BL`).
    package func forEachCellByRun(
        _ body: (_ column: Int, _ width: Int, _ bytes: ArraySlice<UInt8>, _ run: Int) -> Void
    ) {
        var offset = 0
        var column = 0
        var runIndex = 0
        var runLeft = runs.isEmpty ? 0 : Int(runs[0].count)
        let count = bytes.count
        while offset < count {
            let cell = cellStarting(at: offset, column: column)
            while runLeft <= 0, runIndex + 1 < runs.count {
                runIndex += 1
                runLeft = Int(runs[runIndex].count)
            }
            body(column, cell.width, bytes[cell.byteStart..<cell.byteEnd], runIndex < runs.count && runLeft > 0 ? runIndex : -1)
            runLeft -= cell.width
            offset = cell.byteEnd
            column += cell.width
        }
    }

    /// How many runs ``forEachCellByRun(_:)`` can report (their indices are `0..<runCount`).
    package var runCount: Int { runs.count }

    /// The attributes of run `run` of ``forEachCellByRun(_:)``; the default rendition for `-1`.
    package func attributes(ofRun run: Int) -> TerminalAttributes {
        run >= 0 && run < runs.count ? runs[run].attributes : TerminalAttributes()
    }
}
