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
}
