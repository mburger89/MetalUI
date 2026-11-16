/// A terminal emulator: bytes in, a grid of compact rows out.
///
/// Not `Sendable`: confine an emulator to one serial queue chosen by the caller. This is the Phase 1.2 surface:
/// printing with autowrap and pending wrap, the C0 movement controls, basic cursor movement and the mode flags
/// a snapshot carries. Everything else a program may send is parsed and dropped until the later phases give it
/// meaning (`TRM-H`).
public final class TerminalEmulator {
    private let cols: Int
    private let rows: Int
    var screen: [TerminalRow]
    private var dirty: [Bool]
    private var needsFullFrame = true
    var scrollback: ScrollbackRing
    /// Rows that have left the screen (kept or evicted): the absolute number of the screen's first row.
    private var scrolledOff = 0

    var cursorRow = 0
    var cursorCol = 0
    var pendingWrap = false
    var pen = TerminalAttributes()
    private var currentModes = TerminalModes()

    var parser: VTParser
    private var version: UInt64 = 0
    private var published: (cursor: TerminalCursor, modes: TerminalModes)?

    /// Creates an emulator of `cols` x `rows` (clamped to at least 2 x 1) that keeps up to `scrollback` rows
    /// and drops OSC, DCS and APC payloads longer than `payloadCap` bytes.
    public init(cols: Int, rows: Int, scrollback: Int = 10_000, payloadCap: Int = 4096) {
        let size = TerminalSize(cols: cols, rows: rows)
        self.cols = size.cols
        self.rows = size.rows
        screen = Array(repeating: TerminalRow(columns: size.cols), count: size.rows)
        dirty = Array(repeating: true, count: size.rows)
        self.scrollback = ScrollbackRing(capacity: scrollback)
        parser = VTParser(payloadCap: payloadCap)
    }

    /// The oldest retained absolute row.
    public var firstRow: Int { scrolledOff - scrollback.count }

    /// The modes in force.
    public var modes: TerminalModes { currentModes }

    /// Feeds bytes from the child. Any split of a stream into calls gives the same state; a UTF-8 sequence or
    /// escape sequence cut by the end of a call completes on the next.
    public func feed(_ bytes: UnsafeRawBufferPointer) {
        guard bytes.count > 0 else { return }
        parser.feed(bytes.bindMemory(to: UInt8.self), self)
    }

    /// The text of absolute row `row` with trailing blanks removed; nil for an evicted or not-yet-existing row.
    public func rowText(_ row: Int) -> String? {
        if row < firstRow { return nil }
        if row < scrolledOff { return scrollback[row - firstRow].text }
        let index = row - scrolledOff
        return index < rows ? screen[index].text : nil
    }

    /// Takes the damage since the previous publish. Costs O(damaged rows): rows are copied by sharing storage.
    public func publishSnapshot() -> TerminalSnapshot {
        let cursor = TerminalCursor(row: cursorRow, col: cursorCol, visible: currentModes.cursorVisible,
                                    pendingWrap: pendingWrap)
        let full = needsFullFrame
        var damaged: [TerminalDamagedRow] = []
        for index in 0..<rows where full || dirty[index] {
            damaged.append(TerminalDamagedRow(index: index, row: screen[index]))
        }
        let changed = full || !damaged.isEmpty || published?.cursor != cursor || published?.modes != currentModes
        if changed { version += 1 }
        published = (cursor, currentModes)
        needsFullFrame = false
        for index in 0..<rows { dirty[index] = false }
        return TerminalSnapshot(version: version, size: TerminalSize(cols: cols, rows: rows), viewportOffset: 0,
                                damagedRows: damaged, isFullFrame: full, cursor: cursor, modes: currentModes,
                                selection: nil, links: [:])
    }

    // MARK: Printing

    private func wrap() {
        screen[cursorRow].wrapsToNext = true
        cursorCol = 0
        pendingWrap = false
        lineFeed()
    }

    func lineFeed() {
        pendingWrap = false
        if cursorRow == rows - 1 { scrollUp() } else { cursorRow += 1 }
    }

    /// Scrolls the whole screen up one line; the top row joins scrollback.
    private func scrollUp() {
        var top = screen.removeFirst()
        top.compact()
        scrollback.append(top)
        scrolledOff += 1
        screen.append(TerminalRow(columns: cols))
        for index in 0..<rows { dirty[index] = true }
    }

    private func printASCIIRun(_ buf: UnsafeBufferPointer<UInt8>) {
        var rest = buf[...]
        while !rest.isEmpty {
            if pendingWrap {
                if currentModes.autowrap { wrap() } else { pendingWrap = false }
            }
            let room = cols - cursorCol
            let take = min(room, rest.count)
            screen[cursorRow].writeASCII(UnsafeBufferPointer(rebasing: rest.prefix(take)), at: cursorCol, attributes: pen)
            dirty[cursorRow] = true
            rest = rest.dropFirst(take)
            if take == room {
                cursorCol = cols - 1
                pendingWrap = currentModes.autowrap
            } else {
                cursorCol += take
            }
        }
    }

    private func printScalar(_ scalar: Unicode.Scalar) {
        let width = CharacterWidth.of(scalar)
        if width == 0 {
            let target = pendingWrap ? cursorCol : cursorCol - 1
            if target >= 0 {
                screen[cursorRow].appendCombining(scalar, toCellAt: target)
                dirty[cursorRow] = true
            }
            return
        }
        if pendingWrap {
            if currentModes.autowrap { wrap() } else { pendingWrap = false }
        }
        if width == 2 && cursorCol == cols - 1 {
            guard currentModes.autowrap else { return }
            wrap()
        }
        screen[cursorRow].put(scalar, width: width, at: cursorCol, attributes: pen)
        dirty[cursorRow] = true
        if cursorCol + width >= cols {
            cursorCol = cols - 1
            pendingWrap = currentModes.autowrap
        } else {
            cursorCol += width
        }
    }

    // MARK: Cursor

    private func moveCursor(row: Int? = nil, col: Int? = nil) {
        if let row { cursorRow = min(max(row, 0), rows - 1) }
        if let col { cursorCol = min(max(col, 0), cols - 1) }
        pendingWrap = false
    }

    private func count(_ p: CSIParameters, _ index: Int = 0) -> Int {
        index < p.values.count && p.values[index] > 0 ? Int(p.values[index]) : 1
    }

    private func setPrivateMode(_ number: Int32, _ on: Bool) {
        switch number {
        case 1: currentModes.applicationCursorKeys = on
        case 7: currentModes.autowrap = on
        case 25: currentModes.cursorVisible = on
        case 9: currentModes.mouseTracking = on ? .x10 : .off
        case 1000: currentModes.mouseTracking = on ? .normal : .off
        case 1002: currentModes.mouseTracking = on ? .buttonEvent : .off
        case 1003: currentModes.mouseTracking = on ? .anyEvent : .off
        case 1004: currentModes.focusEvents = on
        case 1005: currentModes.mouseEncoding = on ? .utf8 : .legacy
        case 1006: currentModes.mouseEncoding = on ? .sgr : .legacy
        case 2004: currentModes.bracketedPaste = on
        default: break
        }
    }

    /// The columns the screen is wide, for tests.
    var columnCount: Int { cols }
    /// The rows the screen is high, for tests.
    var rowCount: Int { rows }
    /// Scrollback rows retained, for tests.
    var scrollbackCount: Int { scrollback.count }
}

extension TerminalEmulator: VTParserHandler {
    func printASCII(_ bytes: UnsafeBufferPointer<UInt8>) { printASCIIRun(bytes) }

    func print(_ scalar: Unicode.Scalar) {
        if scalar.value < 0x80 {
            withUnsafePointer(to: UInt8(scalar.value)) { printASCIIRun(UnsafeBufferPointer(start: $0, count: 1)) }
        } else {
            printScalar(scalar)
        }
    }

    func execute(_ code: UInt8) {
        switch code {
        case 0x08: moveCursor(col: cursorCol - 1)
        case 0x09: moveCursor(col: (cursorCol / 8 + 1) * 8)
        case 0x0A, 0x0B, 0x0C, 0x84: lineFeed()
        case 0x0D: moveCursor(col: 0)
        case 0x85:
            moveCursor(col: 0)
            lineFeed()
        default: break
        }
    }

    func csi(_ p: CSIParameters, final: UInt8) {
        if p.prefix == 0x3F && p.intermediates.isEmpty && (final == 0x68 || final == 0x6C) {
            for value in p.values where value >= 0 { setPrivateMode(value, final == 0x68) }
            return
        }
        guard p.prefix == 0 && p.intermediates.isEmpty else { return }
        switch final {
        case 0x41: moveCursor(row: cursorRow - count(p))  // CUU
        case 0x42: moveCursor(row: cursorRow + count(p))  // CUD
        case 0x43: moveCursor(col: cursorCol + count(p))  // CUF
        case 0x44: moveCursor(col: cursorCol - count(p))  // CUB
        case 0x45: moveCursor(row: cursorRow + count(p), col: 0)  // CNL
        case 0x46: moveCursor(row: cursorRow - count(p), col: 0)  // CPL
        case 0x47, 0x60: moveCursor(col: count(p) - 1)  // CHA, HPA
        case 0x64: moveCursor(row: count(p) - 1)  // VPA
        case 0x48, 0x66: moveCursor(row: count(p, 0) - 1, col: count(p, 1) - 1)  // CUP, HVP
        default: break
        }
    }

    func esc(intermediates: [UInt8], final: UInt8) {
        guard intermediates.isEmpty else { return }
        switch final {
        case 0x44: lineFeed()  // IND
        case 0x45:  // NEL
            moveCursor(col: 0)
            lineFeed()
        case 0x3D: currentModes.applicationKeypad = true  // DECKPAM
        case 0x3E: currentModes.applicationKeypad = false  // DECKPNM
        default: break
        }
    }

    func osc(_ payload: [UInt8]) {}
    func dcs(_ parameters: CSIParameters, final: UInt8, payload: [UInt8]) {}
    func apc(_ payload: [UInt8]) {}
}
