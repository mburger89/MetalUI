import Foundation
import MetalUI
import MetalUIPlatform
import MetalUIScene
import MetalUITerminal
import MetalUITextSystem

/// The colours of one paint, resolved at the view's position (`TRM-BA`).
struct ResolvedTerminalColors: Equatable {
    var scheme: TerminalColorScheme
    var cursor: TerminalRGB
    var cursorText: TerminalRGB
    var selection: TerminalRGB
    var selectionAlpha: Float
}

/// Everything a ``TerminalView`` keeps between frames and its surface's draw reads (`TRM-BA`): the retained rows,
/// the glyph cache and painter, the drawn cursor and selection, the blink clock and the redraw trigger. It lives
/// in the view's `@State` slot, so it outlives the view value; the surface's `draw` closure captures it, so a
/// surface-only frame (which re-runs `draw` and no build) reaches the current state.
///
/// **The redraw policy** (`TRM-BA` item 2) is in ``draw(into:time:isNewTarget:clear:)``: a new target, a
/// scale, font, palette or reflow-generation change, or a size change redraws every row; otherwise only the rows
/// the snapshot damaged, the cursor's old and new rows when the cursor, its shape, its blink phase or the focus
/// changed, and the rows the old and new selection cover when the selection or the viewport moved.
@MainActor
final class TerminalViewModel {
    /// What the draw did, for tests.
    struct Statistics: Equatable {
        /// Draws run.
        var draws = 0
        /// Draws that redrew every row.
        var fullRedraws = 0
        /// Rows recorded over all draws.
        var rowsDrawn = 0
        /// The rows the last draw recorded, in order.
        var lastRows: [Int] = []
        /// Snapshots taken from the source.
        var snapshotsTaken = 0
        /// Cursor records over all draws.
        var cursorsDrawn = 0
        /// Rows drawn with marked text laid over them, over all draws.
        var markedDraws = 0
        /// The columns the last marked text covered.
        var lastMarkedColumns: Range<Int>?
    }

    /// The blink half period: the cursor toggles every 500 ms, so a blinking cursor costs two surface frames a
    /// second and a full cycle takes one second (`TRM-BA` item 4).
    static let blinkHalfPeriod = 0.5
    /// How long after the last output or input a blinking cursor keeps blinking when `blinkStopsAfterIdle`.
    static let idleLimit = 30.0

    let trigger = SurfaceRedrawTrigger()

    /// The most recently made model, for tests that read what a view drew.
    nonisolated(unsafe) static weak var latestForTesting: TerminalViewModel?

    // The view's parameters, rewritten by every build.
    var source: TerminalSnapshotSource? { didSet { if source !== oldValue { bind() } } }
    var onResize: (TerminalSize) -> Void = { _ in }
    var cursorBlink = true
    var blinkStopsAfterIdle = true
    var onInput: ([UInt8]) -> Void = { _ in }
    var optionAsMeta = false
    var exceptions: [KeyboardShortcut] = []
    var onLink: (TerminalLinkQuery) -> TerminalLinkTarget? = { _ in nil }
    var openURL: (URL) -> Void = { _ in }
    /// The pointer's state: the press under way, the wheel's remainders, the link, the selected text (`TRM-BD`).
    var pointer = TerminalPointerState()

    /// The text target the platform's input method talks to: committed text goes to the child, marked text is drawn
    /// in place at the cursor (`TRM-BC`).
    let input = ExternalTextInput()
    /// The surface's bounds in window points, set by the last paint.
    var bounds: Bounds<Pixels>?

    // The paint's findings.
    var focused = false
    var windowActive = true
    var colors: ResolvedTerminalColors?
    var boldIsBrightFlag = false

    private(set) var cache: TerminalGlyphCache?
    private var painter: TerminalRowPainter?
    private var cacheKey: CacheKey?
    private struct CacheKey: Equatable {
        var system: ObjectIdentifier
        var font: FontDescriptor
        var scale: Float
    }

    private(set) var rows: [TerminalRow?] = []
    private(set) var snapshot: TerminalSnapshot?
    private var lastSize: TerminalSize?
    private var lastSizeReported: TerminalSize?
    private var drawnColors: ResolvedTerminalColors?
    private var drawnReflow = -1
    private var drawnFocus = false
    private var needsFull = true
    private var drawnCursor: DrawnCursor?
    private var drawnSelection: (selection: TerminalSelection?, top: Int)?
    private var drawnLink: TerminalLinkHit?
    private var activityTime: Double?
    private(set) var statistics = Statistics()

    private struct DrawnCursor: Equatable {
        var row: Int
        var col: Int
        var shape: TerminalRowPainter.CursorShape?
    }

    init() {
        input.caret = { [weak self] in self?.caretRect() }
        input.commit = { [weak self] text in self?.send(Array(text.utf8)) }
        input.compose = { [weak self] _ in self?.trigger.requestRedraw() }
    }

    /// The modes a key encodes with: the newest the source has, so a mode the program set a moment ago and the view
    /// has not drawn yet already applies.
    var modes: TerminalModes { source?.pendingModes ?? snapshot?.modes ?? TerminalModes() }

    /// Sends `bytes` to the host and counts it as input for the blink's idle clock (`TRM-BC`); nothing for none.
    func send(_ bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }
        onInput(bytes)
        noteActivity()
    }

    /// A key press while focused: the paste chord, else the key encoded with the current modes. `.ignored` when it
    /// encodes to nothing, so ⌘-keys reach menus (`TRM-D`).
    func handle(_ press: KeyPress, clipboard: Clipboard) -> KeyPress.Result {
        // The layer's own handler is offered a key the capture skipped (an exception, or marked text composing): those
        // belong to the app and to the input method, so they are left alone (`TRM-D`, `TRM-V`).
        if !input.composition.text.isEmpty || exceptions.contains(where: { $0.matches(press) }) { return .ignored }
        if Self.copiesWithControlShiftC, press.modifiers == [.control, .shift], press.key.character.lowercased() == "c" {
            copy(to: clipboard)
            return .handled
        }
        if Self.pastesWithControlShiftV, press.modifiers == [.control, .shift], press.key.character.lowercased() == "v" {
            if let text = clipboard.read(String.self) { paste(text) }
            return .handled
        }
        let bytes = TerminalEncoder.encodeKey(press, modes: modes, optionAsMeta: optionAsMeta)
        guard !bytes.isEmpty else { return .ignored }
        send(bytes)
        return .handled
    }

    /// Whether Ctrl+Shift+V is paste: where the platform's primary modifier is not Command, Ctrl+V is the child's
    /// and ⌘V does not exist (`TRM-BC`).
    static var pastesWithControlShiftV: Bool { Modifiers.primary != .command }

    /// Pasted text, bracketed when the program asked for it, with every ESC stripped (`encodePaste`).
    func paste(_ text: String) {
        guard !text.isEmpty else { return }
        send(TerminalEncoder.encodePaste(text, modes: modes))
    }

    /// Focus in or out of the view (or its window): `ESC [ I` or `ESC [ O` when the program set mode 1004.
    func focusChanged(to focused: Bool) {
        send(TerminalEncoder.encodeFocus(focused, modes: modes))
    }

    /// Where the input method's candidate window goes: the cursor's cell (two cells for a wide character, the
    /// marked text's width while composing), in window points; nil before the first paint and snapshot.
    func caretRect() -> Bounds<Pixels>? {
        guard let cache, let snapshot, let bounds else { return nil }
        let scale = Double(cache.metrics.scale)
        let cw = Double(cache.metrics.cellWidth) / scale, ch = Double(cache.metrics.cellHeight) / scale
        let cursor = snapshot.cursor
        var cells = 1
        if let marked = markedDraw(for: snapshot) {
            cells = max(1, marked.cells)
        } else if cursor.row >= 0, cursor.row < rows.count, let row = rows[cursor.row] {
            cells = max(1, row.cell(at: min(cursor.col, snapshot.size.cols - 1)).width)
        }
        return Bounds(origin: Point(x: Pixels(Float(Double(bounds.origin.x.value) + Double(cursor.col) * cw)),
                                    y: Pixels(Float(Double(bounds.origin.y.value) + Double(cursor.row) * ch))),
                      size: Size(width: Pixels(Float(Double(cells) * cw)), height: Pixels(Float(ch))))
    }

    /// The marked text as it lays over the cursor's row.
    struct MarkedDraw: Equatable {
        var composition: TextComposition
        var row: Int
        var col: Int
        var cells: Int
    }

    private var drawnMarked: MarkedDraw?

    private func markedDraw(for snapshot: TerminalSnapshot) -> MarkedDraw? {
        let composition = input.composition
        guard !composition.text.isEmpty, snapshot.cursor.row >= 0, snapshot.cursor.row < snapshot.size.rows else { return nil }
        let blank = TerminalRow(columns: snapshot.size.cols)
        let (_, covered, _) = blank.overlaying(composition.text, at: min(snapshot.cursor.col, snapshot.size.cols - 1),
                                              attributes: TerminalAttributes())
        return MarkedDraw(composition: composition, row: snapshot.cursor.row,
                          col: min(snapshot.cursor.col, snapshot.size.cols - 1), cells: covered.count)
    }

    /// The cell size in points, once the glyph cache exists.
    var cellSize: (width: Double, height: Double)? {
        guard let cache else { return nil }
        let s = Double(cache.metrics.scale)
        return (Double(cache.metrics.cellWidth) / s, Double(cache.metrics.cellHeight) / s)
    }

    // MARK: Build time

    /// Makes the glyph cache for `system`, `font` and `scale` unless it is current; a new cache redraws every row.
    func prepare(system: any TextSystem, font: FontDescriptor, scale: Float) {
        Self.latestForTesting = self
        let key = CacheKey(system: ObjectIdentifier(system), font: font, scale: scale)
        guard key != cacheKey else { return }
        cacheKey = key
        let made = TerminalGlyphCache(system: system, family: font.family, size: font.size, scale: scale,
                                      design: font.design)
        cache = made
        painter = nil
        needsFull = true
    }

    /// The grid a view of `points` points fits (`TRM-BA` item 1): the drawable's own whole-pixel size over the
    /// cell's, clamped to 2 x 1.
    func grid(forPoints width: Double, _ height: Double) -> TerminalSize {
        guard let cache else { return TerminalSize(cols: 2, rows: 1) }
        let scale = Double(cache.metrics.scale)
        let pixelsWide = Int((width * scale).rounded()), pixelsHigh = Int((height * scale).rounded())
        return TerminalSize(cols: pixelsWide / cache.metrics.cellWidth, rows: pixelsHigh / cache.metrics.cellHeight)
    }

    /// A laid-out size changed the grid: the source resizes the emulator and the host's `onResize` follows
    /// (`TRM-BA` item 1).
    func gridChanged(to size: TerminalSize) {
        guard size != lastSizeReported else { return }
        lastSizeReported = size
        source?.resize(size)
        onResize(size)
    }

    /// An input or other activity at the next draw's time restarts the blink and its idle clock.
    func noteActivity() {
        activityTime = nil
        trigger.requestRedraw()
    }

    private func bind() {
        needsFull = true
        snapshot = nil
        rows = []
        guard let source else { return }
        let trigger = self.trigger
        source.onWake = { trigger.requestRedraw() }
        // A source that already holds a snapshot has woken before this view existed: ask for one wake.
        source.perform { _ in }
    }

    // MARK: Draw time

    /// What the surface's `draw` runs. `sink` is nil on a context with no grid sink (a headless test window): the
    /// whole policy runs and is counted, nothing is recorded.
    func draw(into sink: SurfaceTextSink?, time: Double, isNewTarget: Bool,
              clear: (Float, Float, Float, Float) -> Void) {
        statistics.draws += 1
        guard let cache, let colors else { return }
        let scheme = colors.scheme
        if painter == nil || painter?.scheme != scheme {
            if painter == nil { painter = TerminalRowPainter(cache: cache, scheme: scheme) } else { painter?.scheme = scheme }
        }
        painter?.selectionColor = colors.selection
        painter?.selectionAlpha = colors.selectionAlpha
        stepAutoscroll(time: time)
        let background = scheme.background
        if isNewTarget {
            needsFull = true
            clear(Float(background.r) / 255, Float(background.g) / 255, Float(background.b) / 255, 1)
        }
        if drawnColors != colors { needsFull = true }

        // Take what the source published since the last draw.
        var damaged: [TerminalDamagedRow] = []
        if let taken = source?.takeSnapshot() {
            statistics.snapshotsTaken += 1
            activityTime = nil
            if taken.size != lastSize {
                needsFull = true
                rows = Array(repeating: nil, count: taken.size.rows)
            }
            if taken.reflowGeneration != drawnReflow { needsFull = true }
            for d in taken.damagedRows where d.index < rows.count { rows[d.index] = d.row }
            damaged = taken.damagedRows
            snapshot = taken
            lastSize = taken.size
        }
        guard let snapshot else {
            statistics.lastRows = []
            return
        }
        let now = time
        if drawnFocus != focused { activityTime = nil; drawnFocus = focused }
        if activityTime == nil { activityTime = now }
        let activity = activityTime ?? now

        // The cursor: the shape it draws in, or none while hidden, in its blink-off half or scrolled out.
        let blinks = cursorBlink && snapshot.modes.cursorStyle.blinking
        let idle = blinksStopped(now: now, activity: activity)
        let elapsed = max(0, now - activity)
        let phaseOn = !blinks || idle || Int((elapsed + 1e-6) / Self.blinkHalfPeriod) % 2 == 0
        var shape: TerminalRowPainter.CursorShape?
        let cursor = snapshot.cursor
        if cursor.visible, cursor.row >= 0, cursor.row < snapshot.size.rows {
            if !focused || !windowActive {
                shape = .hollow
            } else if phaseOn {
                switch snapshot.modes.cursorStyle.shape {
                case .block: shape = .block
                case .bar: shape = .bar
                case .underline: shape = .underline
                }
            }
        }
        let cursorNow = DrawnCursor(row: cursor.row, col: cursor.col, shape: shape)
        let markedNow = markedDraw(for: snapshot)

        // Which rows.
        var redraw = Set<Int>()
        let all = needsFull
        if all {
            redraw = Set(0..<snapshot.size.rows)
        } else {
            for d in damaged { redraw.insert(d.index) }
            if let old = drawnCursor, old != cursorNow {
                redraw.insert(old.row)
                redraw.insert(cursorNow.row)
            } else if drawnCursor == nil {
                redraw.insert(cursorNow.row)
            }
            if drawnMarked != markedNow {
                if let old = drawnMarked { redraw.insert(old.row) }
                if let new = markedNow { redraw.insert(new.row) }
            }
            if drawnLink != pointer.link {
                for hit in [drawnLink, pointer.link] {
                    if let hit { redraw.insert(hit.row - snapshot.topRow) }
                }
            }
            let selection = (snapshot.selection, snapshot.topRow)
            if let old = drawnSelection {
                if old.selection != selection.0 || old.top != selection.1 {
                    for r in selectedRows(old.selection, top: old.top, rows: snapshot.size.rows) { redraw.insert(r) }
                    for r in selectedRows(selection.0, top: selection.1, rows: snapshot.size.rows) { redraw.insert(r) }
                }
            } else {
                for r in selectedRows(selection.0, top: selection.1, rows: snapshot.size.rows) { redraw.insert(r) }
            }
        }

        // Record them, row by row in order, each over its own opaque background (`TRM-AV`).
        let ordered = redraw.filter { $0 >= 0 && $0 < snapshot.size.rows }.sorted()
        let columns = snapshot.size.cols
        let blank = TerminalRow(columns: columns)
        for index in ordered {
            var row = index < rows.count ? (rows[index] ?? blank) : blank
            var cursorColumn = min(cursor.col, columns - 1)
            if let marked = markedNow, marked.row == index {
                // Marked text lies over the cursor's cells, underlined (a thicker underline for the clause the input
                // method has selected), and is never sent until committed (`TRM-BC`).
                var attributes = TerminalAttributes()
                attributes.underlineStyle = .single
                let text = marked.composition.text
                let characters = Array(text)
                let selected = marked.composition.selection
                let before = String(characters[0..<min(selected.lowerBound, characters.count)])
                let clause = String(characters[min(selected.lowerBound, characters.count)..<min(selected.upperBound, characters.count)])
                let after = String(characters[min(selected.upperBound, characters.count)...])
                var plain = attributes
                var laid = row.overlaying(before, at: marked.col, attributes: plain)
                var next = laid.covered.upperBound
                plain.underlineStyle = .double
                if !clause.isEmpty {
                    laid = laid.row.overlaying(clause, at: next, attributes: plain)
                    next = laid.covered.upperBound
                }
                plain.underlineStyle = .single
                laid = laid.row.overlaying(after, at: next, attributes: plain)
                row = laid.row
                statistics.markedDraws += 1
                statistics.lastMarkedColumns = marked.col..<laid.covered.upperBound
                cursorColumn = min(marked.col + row.overlaying(before, at: marked.col, attributes: attributes).covered.count,
                                   columns - 1)
            }
            if let sink, let painter {
                let range = selectedColumns(snapshot.selection, top: snapshot.topRow, row: index, columns: columns)
                var link: Range<Int>?
                if let hit = pointer.link, hit.row == snapshot.topRow + index { link = hit.columns }
                painter.draw(row, at: index, columns: columns, origin: (0, 0), into: sink, selection: range, link: link)
                if let shape, cursor.row == index {
                    painter.drawCursor(shape, row: row, column: cursorColumn, columns: columns, at: index,
                                       origin: (0, 0), color: colors.cursor, textColor: colors.cursorText, into: sink)
                }
            }
            if shape != nil, cursor.row == index { statistics.cursorsDrawn += 1 }
        }
        statistics.rowsDrawn += ordered.count
        statistics.lastRows = ordered
        if all { statistics.fullRedraws += 1 }
        needsFull = false
        drawnColors = colors
        drawnReflow = snapshot.reflowGeneration
        drawnCursor = cursorNow
        drawnSelection = (snapshot.selection, snapshot.topRow)
        drawnLink = pointer.link
        syncSelectionText()
        drawnMarked = markedNow

        // The next blink toggle: one timed request at the coming half-period boundary, none while unfocused,
        // steady, hidden or past the idle limit (`TRM-BA` item 4).
        if blinks, focused, windowActive, cursor.visible, !idle {
            let boundary = (floor((elapsed + 1e-6) / Self.blinkHalfPeriod) + 1) * Self.blinkHalfPeriod
            var wait = boundary - elapsed
            if blinkStopsAfterIdle { wait = min(wait, max(Self.idleLimit - elapsed, 0)) }
            trigger.requestRedraw(after: .milliseconds(max(1, Int((wait * 1000).rounded(.up)))))
        }
    }

    private func blinksStopped(now: Double, activity: Double) -> Bool {
        blinkStopsAfterIdle && now - activity >= Self.idleLimit - 1e-6
    }

    // MARK: Selection geometry

    /// The viewport rows `selection` touches.
    private func selectedRows(_ selection: TerminalSelection?, top: Int, rows count: Int) -> Range<Int> {
        guard let range = Self.range(of: selection) else { return 0..<0 }
        let lo = max(0, range.lowerBound.row - top), hi = min(count, range.upperBound.row - top + 1)
        return lo < hi ? lo..<hi : 0..<0
    }

    private static func range(of selection: TerminalSelection?) -> TerminalRange? {
        switch selection {
        case .linear(let r)?, .block(let r)?:
            return r.lowerBound <= r.upperBound ? r : TerminalRange(lowerBound: r.upperBound, upperBound: r.lowerBound)
        case nil:
            return nil
        }
    }

    /// The half-open columns of viewport row `row` that `selection` covers, or nil.
    func selectedColumns(_ selection: TerminalSelection?, top: Int, row: Int, columns: Int) -> Range<Int>? {
        guard let selection, let r = Self.range(of: selection) else { return nil }
        let absolute = top + row
        guard absolute >= r.lowerBound.row, absolute <= r.upperBound.row else { return nil }
        switch selection {
        case .linear:
            let start = absolute == r.lowerBound.row ? r.lowerBound.col : 0
            let end = absolute == r.upperBound.row ? r.upperBound.col + 1 : columns
            return start < end ? max(0, start)..<min(columns, end) : nil
        case .block:
            let a = min(r.lowerBound.col, r.upperBound.col), b = max(r.lowerBound.col, r.upperBound.col)
            return max(0, a)..<min(columns, b + 1)
        }
    }
}
