/// A terminal emulator: bytes in, a grid of compact rows out.
///
/// Not `Sendable`: confine an emulator to one serial queue chosen by the caller. Phase 1.3 gives the screen its
/// full semantics (`TRM-Z`, `TRM-AA`..`TRM-AD`): cursor addressing with scroll regions and origin mode, erase,
/// insert and delete, tab stops, save and restore, the alternate screen, the DEC graphics sets, SGR, and the
/// replies a program waits on (delivered by ``drainEvents()``). Phase 1.4 adds OSC 0/2/7/8/10/11 (`TRM-AE`..
/// `TRM-AH`); DCS and APC are parsed and dropped.
public final class TerminalEmulator {
    var cols: Int
    var rows: Int
    var screen: [TerminalRow]
    /// The screen that is not showing: the primary while the alternate is up, and the alternate otherwise.
    var offscreen: [TerminalRow]
    var dirty: [Bool]
    var needsFullFrame = true
    var scrollback: ScrollbackRing
    /// Rows that have left the screen (kept or evicted): the absolute number of the screen's first row.
    var scrolledOff = 0
    /// Counts the resizes that changed the width and so renumbered absolute rows (`TRM-AM`).
    public internal(set) var reflowGeneration = 0

    var cursorRow = 0
    var cursorCol = 0
    var pendingWrap = false
    var pen = TerminalAttributes()
    var currentModes = TerminalModes()
    /// The scroll region, 0-based and inclusive.
    var regionTop = 0
    var regionBottom: Int
    var tabStops: [Bool]
    var charsets: [Charset] = [.ascii, .ascii, .ascii, .ascii]
    var glSet = 0
    /// True when the active GL set is not plain ASCII: printable bytes take the slow translating path.
    var translating = false
    var insertMode = false
    var onAlternate = false
    var lastPrinted: UInt32 = 0
    var savedCursors: [SavedCursor?] = [nil, nil]
    var events: [TerminalEvent] = []
    /// OSC 8 state (`TRM-AE`): the targets by id, the ids of explicit-id links, and the next id.
    var links: [UInt32: String] = [:]
    var linkIDs: [LinkKey: UInt32] = [:]
    var nextLinkID: UInt32 = 1
    /// Set when `links` gained an entry since the last publish.
    var linksChanged = false
    /// The colours an OSC 10/11 query is answered with; nil leaves a query unanswered (`TRM-AF`).
    package var queryColors: (foreground: (UInt8, UInt8, UInt8), background: (UInt8, UInt8, UInt8))?

    var parser: VTParser
    private var version: UInt64 = 0
    private var published: (cursor: TerminalCursor, modes: TerminalModes, selection: TerminalSelection?)?
    /// The selection as stored (``selection`` validates it), the reflow generation it was taken in, and the
    /// selected rows that were on the screen when it was last checked (`TRM-AQ`).
    var selectionStorage: TerminalSelection?
    var selectionGeneration = 0
    var selectionWitness: [Int: TerminalRow] = [:]
    /// How many rows the viewport is scrolled back from the live bottom (`TRM-AR`).
    var viewportOffset = 0
    private var publishedOffset = 0

    /// Creates an emulator of `cols` x `rows` (clamped to at least 2 x 1) that keeps up to `scrollback` rows
    /// and drops OSC, DCS and APC payloads longer than `payloadCap` bytes.
    public init(cols: Int, rows: Int, scrollback: Int = 10_000, payloadCap: Int = 4096) {
        let size = TerminalSize(cols: cols, rows: rows)
        self.cols = size.cols
        self.rows = size.rows
        screen = Array(repeating: TerminalRow(columns: size.cols), count: size.rows)
        offscreen = screen
        dirty = Array(repeating: true, count: size.rows)
        regionBottom = size.rows - 1
        tabStops = Self.defaultTabStops(size.cols)
        self.scrollback = ScrollbackRing(capacity: scrollback)
        parser = VTParser(payloadCap: payloadCap)
    }

    static func defaultTabStops(_ cols: Int) -> [Bool] { (0..<cols).map { $0 % 8 == 0 && $0 > 0 } }

    /// The oldest retained absolute row.
    public var firstRow: Int { scrolledOff - scrollback.count }

    /// The modes in force.
    public var modes: TerminalModes { currentModes }

    /// Takes the events raised since the last call, oldest first, and empties the queue. A `.reply` MUST be
    /// written to the child by the caller (`TRM-C`). At most 1 024 events queue between drains; a host that
    /// never drains loses the newest.
    public func drainEvents() -> [TerminalEvent] {
        let out = events
        events.removeAll(keepingCapacity: true)
        return out
    }

    /// Feeds bytes from the child. Any split of a stream into calls gives the same state; a UTF-8 sequence or
    /// escape sequence cut by the end of a call completes on the next.
    public func feed(_ bytes: UnsafeRawBufferPointer) {
        guard bytes.count > 0 else { return }
        parser.feed(bytes.bindMemory(to: UInt8.self), self)
    }

    /// The text of absolute row `row` with trailing blanks removed; nil for an evicted or not-yet-existing row.
    /// While the alternate screen shows, rows below the scrollback answer the alternate screen's.
    public func rowText(_ row: Int) -> String? {
        self.row(at: row)?.text
    }

    /// The stored row with absolute number `row`: scrollback below the screen, the showing screen from there.
    func row(at row: Int) -> TerminalRow? {
        if row < firstRow { return nil }
        if row < scrolledOff { return scrollback[row - firstRow] }
        let index = row - scrolledOff
        return index < rows ? screen[index] : nil
    }

    /// Takes the damage since the previous publish. Costs O(damaged rows): rows are copied by sharing storage.
    public func publishSnapshot() -> TerminalSnapshot {
        validateSelection()
        let offset = clampedViewportOffset(viewportOffset)
        viewportOffset = offset
        let cursor = TerminalCursor(row: cursorRow + offset, col: cursorCol,
                                    visible: currentModes.cursorVisible && cursorRow + offset < rows,
                                    pendingWrap: pendingWrap)
        let anyDirty = dirty.contains(true)
        let full = needsFullFrame || offset != publishedOffset || (offset > 0 && anyDirty)
        var damaged: [TerminalDamagedRow] = []
        if offset == 0 {
            for index in 0..<rows where full || dirty[index] {
                damaged.append(TerminalDamagedRow(index: index, row: screen[index]))
            }
        } else if full {
            let top = scrolledOff - offset
            for index in 0..<rows {
                if let row = row(at: top + index) { damaged.append(TerminalDamagedRow(index: index, row: row)) }
            }
        }
        let selection = selectionStorage
        let changed = full || !damaged.isEmpty || linksChanged || published?.cursor != cursor
            || published?.modes != currentModes || published?.selection != selection
        if changed { version += 1 }
        published = (cursor, currentModes, selection)
        publishedOffset = offset
        needsFullFrame = false
        linksChanged = false
        for index in 0..<rows { dirty[index] = false }
        return TerminalSnapshot(version: version, size: TerminalSize(cols: cols, rows: rows), viewportOffset: offset,
                                damagedRows: damaged, isFullFrame: full, cursor: cursor, modes: currentModes,
                                selection: selection, links: links, reflowGeneration: reflowGeneration,
                                topRow: scrolledOff - offset)
    }

    func emit(_ event: TerminalEvent) {
        if events.count >= 1024 { return }
        if case .bell = event, let last = events.last, last == .bell { return }
        events.append(event)
    }

    func reply(_ text: String) { emit(.reply(Array(text.utf8))) }

    // MARK: Printing

    func wrap() {
        screen[cursorRow].wrapsToNext = true
        cursorCol = 0
        pendingWrap = false
        lineFeed()
    }

    func printASCIIRun(_ buf: UnsafeBufferPointer<UInt8>) {
        if translating || insertMode {
            for byte in buf { printScalar(translate(byte)) }
            return
        }
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
        if let last = buf.last { lastPrinted = UInt32(last) }
    }

    func printScalar(_ scalar: Unicode.Scalar) {
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
        if insertMode {
            screen[cursorRow].insertBlanks(at: cursorCol, count: width, attributes: blankAttributes)
        }
        screen[cursorRow].put(scalar, width: width, at: cursorCol, attributes: pen)
        dirty[cursorRow] = true
        lastPrinted = scalar.value
        if cursorCol + width >= cols {
            cursorCol = cols - 1
            pendingWrap = currentModes.autowrap
        } else {
            cursorCol += width
        }
    }

    // MARK: Cursor

    func moveCursor(row: Int? = nil, col: Int? = nil) {
        if let row { cursorRow = min(max(row, 0), rows - 1) }
        if let col { cursorCol = min(max(col, 0), cols - 1) }
        pendingWrap = false
    }

    func count(_ p: CSIParameters, _ index: Int = 0) -> Int {
        index < p.values.count && p.values[index] > 0 ? Int(p.values[index]) : 1
    }

    /// A parameter with its own default (0 for the erase modes), where an omitted or zero one is `fallback`.
    func parameter(_ p: CSIParameters, _ index: Int = 0, default fallback: Int = 0) -> Int {
        index < p.values.count && p.values[index] >= 0 ? Int(p.values[index]) : fallback
    }

    /// Everything beyond the grid that the next byte could depend on, for the chunk-split tests.
    var debugState: String {
        "region=\(regionTop)...\(regionBottom) tabs=\(tabStops.enumerated().filter { $0.element }.map(\.offset)) "
            + "pen=\(pen) charsets=\(charsets)/\(glSet) insert=\(insertMode) alt=\(onAlternate) "
            + "last=\(lastPrinted) saved=\(savedCursors) events=\(events) links=\(links.sorted { $0.key < $1.key }) "
            + "offscreen=\(offscreen.map(\.text))"
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

    func osc(_ payload: [UInt8]) { handleOSC(payload) }
    func dcs(_ parameters: CSIParameters, final: UInt8, payload: [UInt8]) {}
    func apc(_ payload: [UInt8]) {}
}
