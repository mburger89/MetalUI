/// Cursor motion within margins, scrolling, erase, insert/delete, tab stops, save/restore and the alternate
/// screen (`TRM-Z`, `TRM-AA`, `TRM-AB`).
extension TerminalEmulator {
    /// A blank cell as an erase leaves it: default rendition but the pen's background (background colour erase).
    var blankAttributes: TerminalAttributes {
        var attributes = TerminalAttributes()
        attributes.background = pen.background
        return attributes
    }

    func newBlankRow() -> TerminalRow { TerminalRow(columns: cols, blank: blankAttributes) }

    func markAllDirty() {
        for index in 0..<rows { dirty[index] = true }
    }

    // MARK: Line feed and scrolling

    /// LF, VT, FF, IND: down one row, scrolling the region when the cursor is on its bottom row.
    func lineFeed() {
        pendingWrap = false
        if cursorRow == regionBottom {
            scrollRegionUp(count: 1)
        } else if cursorRow < rows - 1 {
            cursorRow += 1
        }
    }

    /// RI: up one row, scrolling the region down when the cursor is on its top row.
    func reverseIndex() {
        pendingWrap = false
        if cursorRow == regionTop {
            scrollRegionDown(count: 1)
        } else if cursorRow > 0 {
            cursorRow -= 1
        }
    }

    /// Scrolls the region up. Rows leave to scrollback only when the region is the whole primary screen
    /// (`TRM-AA`); in any other case they are dropped.
    func scrollRegionUp(count: Int) {
        let n = min(count, regionBottom - regionTop + 1)
        guard n > 0 else { return }
        let toScrollback = regionTop == 0 && regionBottom == rows - 1 && !onAlternate
        for _ in 0..<n {
            var out = screen.remove(at: regionTop)
            if toScrollback {
                out.compact()
                scrollback.append(out)
                scrolledOff += 1
                if viewportOffset > 0 { viewportOffset += 1 }
            }
            screen.insert(newBlankRow(), at: regionBottom)
        }
        for index in regionTop...regionBottom { dirty[index] = true }
    }

    func scrollRegionDown(count: Int) {
        let n = min(count, regionBottom - regionTop + 1)
        guard n > 0 else { return }
        for _ in 0..<n {
            screen.remove(at: regionBottom)
            screen.insert(newBlankRow(), at: regionTop)
        }
        for index in regionTop...regionBottom { dirty[index] = true }
    }

    /// IL: inserts blank rows at the cursor row inside the region, pushing the rest down.
    func insertLines(_ count: Int) {
        guard cursorRow >= regionTop && cursorRow <= regionBottom else { return }
        let n = min(count, regionBottom - cursorRow + 1)
        for _ in 0..<n {
            screen.remove(at: regionBottom)
            screen.insert(newBlankRow(), at: cursorRow)
        }
        for index in cursorRow...regionBottom { dirty[index] = true }
        cursorCol = 0
        pendingWrap = false
    }

    /// DL: removes rows at the cursor row inside the region, pulling the rest up.
    func deleteLines(_ count: Int) {
        guard cursorRow >= regionTop && cursorRow <= regionBottom else { return }
        let n = min(count, regionBottom - cursorRow + 1)
        for _ in 0..<n {
            screen.remove(at: cursorRow)
            screen.insert(newBlankRow(), at: regionBottom)
        }
        for index in cursorRow...regionBottom { dirty[index] = true }
        cursorCol = 0
        pendingWrap = false
    }

    // MARK: Addressing

    /// CUP/HVP/VPA's row: 1-based, relative to the region in origin mode and then kept inside it.
    func setRow(oneBased row: Int) {
        var target = row - 1
        if currentModes.originMode {
            target = min(target + regionTop, regionBottom)
        } else {
            target = min(target, rows - 1)
        }
        cursorRow = max(target, 0)
        pendingWrap = false
    }

    /// The cursor's home: the region's top-left in origin mode, the screen's otherwise.
    func home() {
        cursorRow = currentModes.originMode ? regionTop : 0
        cursorCol = 0
        pendingWrap = false
    }

    /// CUU: stops at the top margin when the cursor starts inside the region.
    func cursorUp(_ n: Int) {
        let stop = cursorRow >= regionTop ? regionTop : 0
        cursorRow = max(cursorRow - n, stop)
        pendingWrap = false
    }

    /// CUD: stops at the bottom margin when the cursor starts inside the region.
    func cursorDown(_ n: Int) {
        let stop = cursorRow <= regionBottom ? regionBottom : rows - 1
        cursorRow = min(cursorRow + n, stop)
        pendingWrap = false
    }

    /// DECSTBM with 1-based, already defaulted arguments. An invalid region (top not above bottom) is ignored.
    func setRegion(top: Int, bottom: Int) {
        let t = max(top, 1)
        let b = min(bottom, rows)
        guard t < b else { return }
        regionTop = t - 1
        regionBottom = b - 1
        home()
    }

    // MARK: Tabs

    func nextTabStop(from column: Int, count: Int) -> Int {
        var col = column
        for _ in 0..<count {
            var next = col + 1
            while next < cols - 1 && !tabStops[next] { next += 1 }
            col = min(next, cols - 1)
        }
        return col
    }

    func previousTabStop(from column: Int, count: Int) -> Int {
        var col = column
        for _ in 0..<count {
            var prev = col - 1
            while prev > 0 && !tabStops[prev] { prev -= 1 }
            col = max(prev, 0)
        }
        return col
    }

    // MARK: Erase and edit

    func eraseCells(row: Int, _ range: Range<Int>) {
        screen[row].erase(range, attributes: blankAttributes)
        dirty[row] = true
    }

    func clearRow(_ row: Int) {
        let attributes = blankAttributes
        if attributes == TerminalAttributes() && screen[row].usedColumns == 0 && !screen[row].wrapsToNext { return }
        screen[row] = TerminalRow(columns: cols, blank: attributes)
        dirty[row] = true
    }

    /// ED (and DECSED, which is the same without protected cells).
    func eraseInDisplay(_ mode: Int) {
        switch mode {
        case 0:
            eraseCells(row: cursorRow, cursorCol..<cols)
            if cursorRow + 1 < rows { for row in (cursorRow + 1)..<rows { clearRow(row) } }
        case 1:
            for row in 0..<cursorRow { clearRow(row) }
            eraseCells(row: cursorRow, 0..<(cursorCol + 1))
        case 2:
            for row in 0..<rows { clearRow(row) }
        case 3:
            scrollback.removeAll()
        default:
            break
        }
    }

    /// EL (and DECSEL).
    func eraseInLine(_ mode: Int) {
        switch mode {
        case 0: eraseCells(row: cursorRow, cursorCol..<cols)
        case 1: eraseCells(row: cursorRow, 0..<(cursorCol + 1))
        case 2: eraseCells(row: cursorRow, 0..<cols)
        default: break
        }
    }

    func insertCharacters(_ n: Int) {
        screen[cursorRow].insertBlanks(at: cursorCol, count: n, attributes: blankAttributes)
        dirty[cursorRow] = true
        pendingWrap = false
    }

    func deleteCharacters(_ n: Int) {
        screen[cursorRow].deleteCharacters(at: cursorCol, count: n, attributes: blankAttributes)
        dirty[cursorRow] = true
        pendingWrap = false
    }

    func eraseCharacters(_ n: Int) {
        eraseCells(row: cursorRow, cursorCol..<min(cursorCol + n, cols))
        pendingWrap = false
    }

    /// REP: prints the last graphic character `n` more times.
    func repeatLast(_ n: Int) {
        guard lastPrinted != 0, let scalar = Unicode.Scalar(lastPrinted) else { return }
        for _ in 0..<min(n, 65_535) { printScalar(scalar) }
    }

    /// DECALN: fills the screen with E, clears the margins and homes the cursor.
    func screenAlignmentPattern() {
        for row in 0..<rows { screen[row] = TerminalRow(columns: cols, filledWith: 0x45) }
        regionTop = 0
        regionBottom = rows - 1
        cursorRow = 0
        cursorCol = 0
        pendingWrap = false
        markAllDirty()
    }

    // MARK: Save, restore, reset

    func saveCursor() {
        savedCursors[onAlternate ? 1 : 0] = SavedCursor(
            row: cursorRow, col: cursorCol, pendingWrap: pendingWrap, pen: pen,
            originMode: currentModes.originMode, charsets: charsets, glSet: glSet)
    }

    /// DECRC. With nothing saved the cursor goes home with the default rendition and character sets.
    func restoreCursor() {
        let saved = savedCursors[onAlternate ? 1 : 0]
            ?? SavedCursor(row: 0, col: 0, pendingWrap: false, pen: TerminalAttributes(), originMode: false,
                           charsets: [.ascii, .ascii, .ascii, .ascii], glSet: 0)
        cursorRow = min(saved.row, rows - 1)
        cursorCol = min(saved.col, cols - 1)
        pendingWrap = saved.pendingWrap
        pen = saved.pen
        currentModes.originMode = saved.originMode
        charsets = saved.charsets
        glSet = saved.glSet
        updateTranslation()
    }

    func updateTranslation() { translating = charsets[glSet] != .ascii }

    func translate(_ byte: UInt8) -> Unicode.Scalar { charsets[glSet].translate(byte) }

    /// Shows the alternate screen. `clear` blanks it first (1049); otherwise its last contents come back (47).
    func enterAlternate(clear: Bool) {
        guard !onAlternate else { return }
        swap(&screen, &offscreen)
        onAlternate = true
        selectionStorage = nil
        viewportOffset = 0
        currentModes.alternateScreen = true
        if clear { for row in 0..<rows { screen[row] = TerminalRow(columns: cols) } }
        markAllDirty()
        needsFullFrame = true
    }

    func leaveAlternate(clear: Bool) {
        guard onAlternate else { return }
        if clear { for row in 0..<rows { screen[row] = TerminalRow(columns: cols) } }
        swap(&screen, &offscreen)
        onAlternate = false
        selectionStorage = nil
        viewportOffset = 0
        currentModes.alternateScreen = false
        markAllDirty()
        needsFullFrame = true
    }

    /// DECSTR: the terminal's own state goes back to its defaults; the screen's contents, the cursor position,
    /// the alternate screen, tab stops and the mouse, paste and focus modes stay (`TRM-AB`).
    func softReset() {
        currentModes.cursorVisible = true
        currentModes.originMode = false
        currentModes.autowrap = true
        currentModes.applicationCursorKeys = false
        currentModes.applicationKeypad = false
        programSetsCursorStyle = false
        currentModes.cursorStyle = userCursorStyle
        insertMode = false
        regionTop = 0
        regionBottom = rows - 1
        pen = TerminalAttributes()
        charsets = [.ascii, .ascii, .ascii, .ascii]
        glSet = 0
        updateTranslation()
        savedCursors = [nil, nil]
        pendingWrap = false
    }

    /// RIS: power-on state with a cleared screen. Scrollback is kept (`TRM-AB`).
    func hardReset() {
        let alternate = onAlternate
        if alternate { swap(&screen, &offscreen) }
        onAlternate = false
        selectionStorage = nil
        viewportOffset = 0
        screen = Array(repeating: TerminalRow(columns: cols), count: rows)
        offscreen = screen
        currentModes = TerminalModes()
        programSetsCursorStyle = false
        currentModes.cursorStyle = userCursorStyle
        insertMode = false
        cursorRow = 0
        cursorCol = 0
        pendingWrap = false
        pen = TerminalAttributes()
        regionTop = 0
        regionBottom = rows - 1
        tabStops = Self.defaultTabStops(cols)
        charsets = [.ascii, .ascii, .ascii, .ascii]
        glSet = 0
        updateTranslation()
        savedCursors = [nil, nil]
        lastPrinted = 0
        markAllDirty()
        needsFullFrame = true
    }
}
