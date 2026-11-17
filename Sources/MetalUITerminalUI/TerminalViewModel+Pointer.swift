import Foundation
import MetalUI
import MetalUIPlatform
import MetalUITerminal

/// A link under a ⌘-hovered pointer (`TRM-BD`): the host's answer, or an OSC 8 run the view found itself.
struct TerminalLinkHit: Equatable {
    /// The absolute row.
    var row: Int
    /// The columns underlined on that row.
    var columns: Range<Int>
    /// The host's payload, or the OSC 8 URI.
    var payload: String
    /// True when `onLink` answered it (activation asks the host again); false for an OSC 8 run (activation opens the URL).
    var fromHost: Bool
}

/// What the view keeps about the pointer between events (`TRM-BD`). One value, so the model's stored state is one field.
struct TerminalPointerState {
    /// The press under way, if any: what it does.
    enum Drag: Equatable {
        /// The program has mouse reporting on: the press, its drags and its release are reported; `last` is the cell
        /// last reported (viewport coordinates), so a drag within a cell reports once.
        case reporting(last: TerminalPosition)
        /// A local selection from `anchor` (absolute) to the pointer; nothing is selected until the pointer leaves the
        /// anchor's cell (`moved`).
        case selecting(anchor: TerminalPosition, block: Bool, moved: Bool, last: TerminalPosition?)
        /// A ⌘-press on a link (absolute cell): activates on release over the same cell.
        case link(cell: TerminalPosition)
        /// A press that does nothing more: a double or triple click (already selected) or a button the view ignores.
        case inert
    }

    /// The edge scroll of a selection drag held past the view's top or bottom.
    struct Autoscroll: Equatable {
        /// 1 scrolls back (the pointer is above the view), -1 forward.
        var direction: Int
        /// Rows per step.
        var rows: Int
        /// The column the selection's end keeps.
        var column: Int
        /// The frame time of the last step.
        var lastStep = -Double.infinity
    }

    var drag: Drag?
    var dragButton: TerminalMouseEvent.Button?
    var modifiers: Modifiers = []
    var hoverPoint: Point<Pixels>?
    /// The cell last reported as plain motion (viewport), so mode 1003 reports a cell once.
    var motionCell: TerminalPosition?
    /// The absolute cell `onLink(.hover)` was last asked about, and its row text for the `.exit`.
    var queried: TerminalPosition?
    var queriedText = ""
    var link: TerminalLinkHit?
    var wheelX = 0.0
    var wheelY = 0.0
    var autoscroll: Autoscroll?
    /// The selected text, with the selection it belongs to; what Copy writes.
    var text: (selection: TerminalSelection, text: String?)?
    /// A fetch of the text is on its way.
    var fetching = false
}

extension TerminalModifiers {
    /// The terminal's spelling of the window's modifiers.
    init(_ modifiers: Modifiers) {
        var out: TerminalModifiers = []
        if modifiers.contains(.shift) { out.insert(.shift) }
        if modifiers.contains(.control) { out.insert(.control) }
        if modifiers.contains(.option) { out.insert(.option) }
        if modifiers.contains(.command) { out.insert(.command) }
        self = out
    }
}

/// Carries the main-actor model through the emulator queue's `@Sendable` closure; it is only touched back on the main
/// actor (`TerminalSnapshotSource` does the same with its event hop).
private struct ModelBox: @unchecked Sendable {
    let model: TerminalViewModel
}

extension TerminalViewModel {
    /// The rows one line of a wheel mouse moves: the "lines x 10" a non-precise `ScrollEvent` carries are lines, and each
    /// line is three rows, as xterm's scroll amount and Terminal.app do (`TRM-BD`).
    static let rowsPerWheelLine = 3
    /// The most reports or arrows one wheel event sends.
    static let wheelEventLimit = 64
    /// The edge scroll's step, in milliseconds, and its largest rows per step.
    static let autoscrollMilliseconds = 50
    static let autoscrollLimit = 10

    /// The key whose press means "link" while hovering or clicking: ⌘ on Apple platforms, Ctrl elsewhere.
    static var linkModifier: Modifiers { Modifiers.primary }
    /// Whether Ctrl+Shift+C is Copy: where ⌘ is not the primary modifier, Ctrl+C is the child's.
    static var copiesWithControlShiftC: Bool { Modifiers.primary != .command }

    // MARK: Geometry

    /// The cell under `point` (view-local points) before it is clamped to the grid: a row above the view is negative.
    func rawCell(at point: Point<Pixels>) -> (row: Int, col: Int)? {
        guard let cell = cellSize, cell.width > 0, cell.height > 0 else { return nil }
        return (Int((Double(point.y.value) / cell.height).rounded(.down)), Int((Double(point.x.value) / cell.width).rounded(.down)))
    }

    /// The viewport cell under `point` (view-local points), clamped to the grid; nil before the first paint and snapshot
    /// (`TRM-BD`).
    func hitTest(_ point: Point<Pixels>) -> TerminalPosition? {
        guard let raw = rawCell(at: point), let size = snapshot?.size, size.cols > 0, size.rows > 0 else { return nil }
        return TerminalPosition(row: min(max(raw.row, 0), size.rows - 1), col: min(max(raw.col, 0), size.cols - 1))
    }

    /// `cell` (viewport) in absolute rows.
    func absolute(_ cell: TerminalPosition) -> TerminalPosition {
        TerminalPosition(row: (snapshot?.topRow ?? 0) + cell.row, col: cell.col)
    }

    private func rowText(viewport row: Int) -> String {
        row >= 0 && row < rows.count ? (rows[row]?.text ?? "") : ""
    }

    private func sendMouse(_ kind: TerminalMouseEvent.Kind, _ button: TerminalMouseEvent.Button, _ modifiers: Modifiers,
                           at cell: TerminalPosition, repeating count: Int = 1) {
        let event = TerminalMouseEvent(kind: kind, button: button, modifiers: TerminalModifiers(modifiers))
        let modes = self.modes
        var bytes: [UInt8] = []
        for _ in 0..<max(1, count) { bytes += TerminalEncoder.encodeMouse(event, at: cell, modes: modes) }
        send(bytes)
    }

    // MARK: Buttons

    /// A button's drag value arrived: the press at the first one, then the moves.
    func pointerChanged(_ value: DragGesture.Value, button: TerminalMouseEvent.Button) {
        if pointer.drag == nil { press(value, button: button) } else if pointer.dragButton == button { drag(value, button: button) }
    }

    /// A button's release.
    func pointerEnded(_ value: DragGesture.Value, button: TerminalMouseEvent.Button) {
        if pointer.drag == nil { press(value, button: button) }   // a release with no change before it
        guard pointer.dragButton == button, let state = pointer.drag else { return }
        pointer.drag = nil
        pointer.dragButton = nil
        let cell = hitTest(value.location)
        switch state {
        case .reporting:
            if let cell { sendMouse(.release, button, value.modifiers, at: cell) }
        case .selecting(_, _, let moved, _):
            pointer.autoscroll = nil
            if moved { fetchSelectionText() }
        case .link(let pressed):
            if let cell, absolute(cell) == pressed, let link = pointer.link, link.row == pressed.row,
               link.columns.contains(pressed.col) {
                activate(link, at: pressed)
            }
        case .inert:
            break
        }
        updateLink(point: pointer.hoverPoint ?? value.location, modifiers: value.modifiers)
    }

    private func press(_ value: DragGesture.Value, button: TerminalMouseEvent.Button) {
        // Any primary press focuses the terminal (`TRM-BE`), whatever it then does: the pointer gesture claims the press
        // ahead of the focusable's own click-to-focus, so the model asks for focus itself, also for a reported or ⌘-link press.
        if button == .left { requestFocus() }
        guard let cell = hitTest(value.location) else { return }
        let mods = value.modifiers
        let absoluteCell = absolute(cell)
        pointer.dragButton = button
        // ⌘ on a link beats both reporting and selection (Terminal.app opens links under a mouse-mode program too).
        if button == .left, mods.contains(Self.linkModifier) {
            updateLink(point: value.location, modifiers: mods)
            if let link = pointer.link, link.row == absoluteCell.row, link.columns.contains(absoluteCell.col) {
                pointer.drag = .link(cell: absoluteCell)
                return
            }
        }
        if modes.mouseTracking != .off, !mods.contains(.shift) {
            pointer.drag = .reporting(last: cell)
            sendMouse(.press, button, mods, at: cell)
            return
        }
        guard button == .left else { pointer.drag = .inert; return }
        if value.clickCount >= 3 {
            pointer.drag = .inert
            setSelection(fetchText: true) { e in e.lineRange(at: absoluteCell).map { .linear($0) } }
        } else if value.clickCount == 2 {
            pointer.drag = .inert
            setSelection(fetchText: true) { e in e.wordRange(at: absoluteCell).map { .linear($0) } }
        } else if mods.contains(.shift), let current = snapshot?.selection {
            // ⇧-click extends: the end of the selection nearer the click moves to it, the far end stays the anchor.
            let (range, block) = Self.parts(current)
            let low = min(range.lowerBound, range.upperBound), high = max(range.lowerBound, range.upperBound)
            let anchor = Self.distance(absoluteCell, low) > Self.distance(absoluteCell, high) ? low : high
            pointer.drag = .selecting(anchor: anchor, block: block, moved: true, last: absoluteCell)
            applyRange(anchor, absoluteCell, block: block, fetchText: false)
        } else {
            if snapshot?.selection != nil { setSelection(fetchText: true) { _ in nil } }
            pointer.drag = .selecting(anchor: absoluteCell, block: mods.contains(.option), moved: false, last: nil)
        }
    }

    private func drag(_ value: DragGesture.Value, button: TerminalMouseEvent.Button) {
        guard let state = pointer.drag else { return }
        switch state {
        case .reporting(let last):
            guard let cell = hitTest(value.location), cell != last else { return }
            pointer.drag = .reporting(last: cell)
            sendMouse(.move, button, value.modifiers, at: cell)
        case .selecting(let anchor, let block, let moved, let last):
            guard let raw = rawCell(at: value.location), let size = snapshot?.size, size.rows > 0, size.cols > 0 else { return }
            let col = min(max(raw.col, 0), size.cols - 1), row = min(max(raw.row, 0), size.rows - 1)
            let over = raw.row < 0 ? raw.row : (raw.row >= size.rows ? raw.row - (size.rows - 1) : 0)
            if over != 0 {
                let previous = pointer.autoscroll
                pointer.autoscroll = TerminalPointerState.Autoscroll(direction: over < 0 ? 1 : -1,
                                                                    rows: min(abs(over), Self.autoscrollLimit), column: col,
                                                                    lastStep: previous?.lastStep ?? -Double.infinity)
                trigger.requestRedraw(after: .milliseconds(Self.autoscrollMilliseconds))
            } else {
                pointer.autoscroll = nil
            }
            let end = absolute(TerminalPosition(row: row, col: col))
            if !moved, end == anchor, over == 0 { return }
            if moved, end == last, over == 0 { return }
            pointer.drag = .selecting(anchor: anchor, block: block, moved: true, last: end)
            applyRange(anchor, end, block: block, fetchText: false)
        case .link, .inert:
            break
        }
    }

    private static func parts(_ selection: TerminalSelection) -> (TerminalRange, Bool) {
        switch selection {
        case .linear(let range): return (range, false)
        case .block(let range): return (range, true)
        }
    }

    private static func distance(_ a: TerminalPosition, _ b: TerminalPosition) -> Int {
        abs(a.row - b.row) * 100_000 + abs(a.col - b.col)
    }

    // MARK: Selection

    /// Sets the selection on the emulator's queue (nil clears it); with `fetchText` the queue also reads the selected text
    /// and hands it back for Copy.
    private func setSelection(fetchText: Bool, _ make: @escaping @Sendable (TerminalEmulator) -> TerminalSelection?) {
        guard let source else { return }
        pointer.text = nil
        pointer.fetching = fetchText
        let box = ModelBox(model: self)
        source.perform { e in
            e.selection = make(e)
            guard fetchText else { return }
            let selection = e.selection
            let text = selection == nil ? nil : e.selectedText()
            DispatchQueue.main.async { MainActor.assumeIsolated { box.model.selectionFetched(selection, text) } }
        }
    }

    private func applyRange(_ a: TerminalPosition, _ b: TerminalPosition, block: Bool, fetchText: Bool) {
        let range = TerminalRange(lowerBound: a, upperBound: b)
        setSelection(fetchText: fetchText) { _ in block ? .block(range) : .linear(range) }
    }

    /// Reads the selected text for Copy once a selection stands (a drag's release, or a selection that changed under the
    /// view: scrollback eviction clipped it).
    func fetchSelectionText() {
        guard let source else { return }
        pointer.fetching = true
        let box = ModelBox(model: self)
        source.perform { e in
            let selection = e.selection
            let text = selection == nil ? nil : e.selectedText()
            DispatchQueue.main.async { MainActor.assumeIsolated { box.model.selectionFetched(selection, text) } }
        }
    }

    private func selectionFetched(_ selection: TerminalSelection?, _ text: String?) {
        pointer.fetching = false
        if let selection { pointer.text = (selection, text) } else { pointer.text = nil }
    }

    /// Called by every draw: drops the text of a selection output cleared, and fetches the text of one the view did not set
    /// (clipped by eviction) once no drag is in progress.
    func syncSelectionText() {
        guard let snapshot else { return }
        guard let current = snapshot.selection else { pointer.text = nil; return }
        if pointer.text?.selection == current || pointer.fetching { return }
        if case .selecting? = pointer.drag { return }
        fetchSelectionText()
    }

    /// What Copy writes: the selected text, or nothing.
    func copyItems() -> [String] {
        if let text = pointer.text?.text, !text.isEmpty { return [text] }
        return []
    }

    /// Ctrl+Shift+C (where ⌘C does not exist): the selection to the clipboard.
    func copy(to clipboard: Clipboard) {
        if let text = copyItems().first { _ = clipboard.write(text) }
    }

    /// One edge-scroll step, from the draw (a timed redraw drives it while the pointer rests past the edge): scrolls the
    /// viewport and keeps the selection's end on the edge row, both on the emulator's queue.
    func stepAutoscroll(time: Double) {
        guard var scroll = pointer.autoscroll, case .selecting(let anchor, let block, _, _)? = pointer.drag,
              let size = snapshot?.size, let source else {
            pointer.autoscroll = nil
            return
        }
        trigger.requestRedraw(after: .milliseconds(Self.autoscrollMilliseconds))
        guard time - scroll.lastStep >= Double(Self.autoscrollMilliseconds) / 1000 - 0.005 else { return }
        scroll.lastStep = time
        pointer.autoscroll = scroll
        let rows = scroll.rows * scroll.direction, edge = scroll.direction > 0 ? 0 : size.rows - 1, column = scroll.column
        source.perform { e in
            e.scrollViewport(byRows: rows)
            let range = TerminalRange(lowerBound: anchor, upperBound: TerminalPosition(row: e.viewportTopRow + edge, col: column))
            e.selection = block ? .block(range) : .linear(range)
        }
        pointer.drag = .selecting(anchor: anchor, block: block, moved: true, last: nil)
    }

    // MARK: Wheel

    /// A wheel or trackpad scroll over the view (`TRM-BD`): reports to a program that asked for the mouse (⇧ held bypasses
    /// that, as in xterm), else arrow keys on the alternate screen, else the viewport through scrollback. Returns whether it
    /// was taken.
    func wheel(_ event: ScrollEvent) -> Bool {
        guard let cell = hitTest(event.location) else { return false }
        if event.phase == .began { pointer.wheelX = 0; pointer.wheelY = 0 }
        let size = cellSize ?? (width: 8, height: 16)
        let rowsY = Self.wheelUnits(Double(event.delta.y.value), precise: event.isPrecise, cell: size.height, into: &pointer.wheelY)
        let colsX = Self.wheelUnits(Double(event.delta.x.value), precise: event.isPrecise, cell: size.width, into: &pointer.wheelX)
        guard rowsY != 0 || colsX != 0 else { return true }
        let modes = self.modes
        if modes.mouseTracking != .off, !event.modifiers.contains(.shift) {
            // One report per line of a wheel mouse and per row of a trackpad; the horizontal axis is buttons 66 and 67.
            if rowsY != 0 {
                sendMouse(rowsY > 0 ? .wheelUp : .wheelDown, .none, event.modifiers, at: cell,
                          repeating: min(abs(rowsY), Self.wheelEventLimit))
            }
            if colsX != 0 {
                sendMouse(colsX > 0 ? .wheelLeft : .wheelRight, .none, event.modifiers, at: cell,
                          repeating: min(abs(colsX), Self.wheelEventLimit))
            }
            return true
        }
        guard rowsY != 0 else { return true }
        let rows = event.isPrecise ? rowsY : rowsY * Self.rowsPerWheelLine
        if modes.alternateScreen {
            // The alternate screen has no scrollback: its wheel is the up and down arrow keys, as Terminal.app, VTE and
            // Alacritty do (xterm's mode 1007 defaults off; the spec says the wheel "goes to the program").
            let key = TerminalKey(key: rows > 0 ? "\u{F700}" : "\u{F701}", characters: "", modifiers: [])
            let one = TerminalEncoder.encodeKey(key, modes: modes, optionAsMeta: false)
            var bytes: [UInt8] = []
            for _ in 0..<min(abs(rows), Self.wheelEventLimit) { bytes += one }
            send(bytes)
            return true
        }
        if rows < 0, (snapshot?.viewportOffset ?? 0) == 0 { return true }
        source?.perform { e in e.scrollViewport(byRows: rows) }
        return true
    }

    /// The whole rows (or columns) `delta` points moves: a wheel mouse's lines (a "lines x 10" delta, at least one per
    /// event), or a trackpad's points accumulated until they make a whole cell (the remainder stays; a reversal drops it).
    static func wheelUnits(_ delta: Double, precise: Bool, cell: Double, into remainder: inout Double) -> Int {
        guard delta != 0 else { return 0 }
        if !precise {
            remainder = 0
            let lines = max(1, Int((abs(delta) / 10).rounded(.up)))
            return delta > 0 ? lines : -lines
        }
        if remainder != 0, (remainder > 0) != (delta > 0) { remainder = 0 }
        remainder += delta / max(cell, 1)
        let whole = Int(remainder)
        remainder -= Double(whole)
        return whole
    }

    // MARK: Hover and links

    /// The pointer moved over the view: plain motion for mode 1003, and the link under it while ⌘ is held.
    func hoverMoved(to point: Point<Pixels>) {
        pointer.hoverPoint = point
        guard pointer.drag == nil else { return }
        if modes.mouseTracking == .anyEvent, !pointer.modifiers.contains(.shift), let cell = hitTest(point),
           cell != pointer.motionCell {
            pointer.motionCell = cell
            sendMouse(.move, .none, pointer.modifiers, at: cell)
        }
        updateLink(point: point, modifiers: pointer.modifiers)
    }

    /// The pointer left the view.
    func hoverEnded() {
        pointer.hoverPoint = nil
        pointer.motionCell = nil
        updateLink(point: nil, modifiers: pointer.modifiers)
    }

    /// The window's modifier keys changed (also with the pointer still).
    func modifiersChanged(to modifiers: Modifiers) {
        pointer.modifiers = modifiers
        guard pointer.drag == nil else { return }
        updateLink(point: pointer.hoverPoint, modifiers: modifiers)
    }

    /// Asks the host about the cell under `point` when ⌘ is held and the cell is not the one last asked about
    /// (`.hover`), sends `.exit` for the cell left, and makes the answer (the host's, else an OSC 8 run) the link shown.
    func updateLink(point: Point<Pixels>?, modifiers: Modifiers) {
        var cell: TerminalPosition?
        if let point, modifiers.contains(Self.linkModifier), let hit = hitTest(point) { cell = absolute(hit) }
        guard cell != pointer.queried else { return }
        if let old = pointer.queried {
            _ = onLink(TerminalLinkQuery(cell: old, rowText: pointer.queriedText, phase: .exit))
        }
        pointer.queried = cell
        guard let cell, let snapshot else {
            pointer.queriedText = ""
            setLink(nil)
            return
        }
        let viewportRow = cell.row - snapshot.topRow
        let text = rowText(viewport: viewportRow)
        pointer.queriedText = text
        var found: TerminalLinkHit?
        if let target = onLink(TerminalLinkQuery(cell: cell, rowText: text, phase: .hover)),
           target.columns.contains(cell.col) {
            found = TerminalLinkHit(row: cell.row, columns: target.columns, payload: target.payload, fromHost: true)
        } else {
            found = osc8(at: cell, viewportRow: viewportRow)
        }
        setLink(found)
    }

    /// The OSC 8 run under `cell`: the neighbouring cells of the row that carry the same link id.
    private func osc8(at cell: TerminalPosition, viewportRow: Int) -> TerminalLinkHit? {
        guard let snapshot, viewportRow >= 0, viewportRow < rows.count, let row = rows[viewportRow],
              let id = row.cell(at: cell.col).attributes.hyperlink, let uri = snapshot.links[id] else { return nil }
        var low = cell.col, high = cell.col
        while low > 0, row.cell(at: low - 1).attributes.hyperlink == id { low -= 1 }
        while high + 1 < snapshot.size.cols, row.cell(at: high + 1).attributes.hyperlink == id { high += 1 }
        return TerminalLinkHit(row: cell.row, columns: low..<(high + 1), payload: uri, fromHost: false)
    }

    private func setLink(_ link: TerminalLinkHit?) {
        guard link != pointer.link else { return }
        pointer.link = link
        trigger.requestRedraw()
    }

    private func activate(_ link: TerminalLinkHit, at cell: TerminalPosition) {
        if link.fromHost {
            _ = onLink(TerminalLinkQuery(cell: cell, rowText: pointer.queriedText, phase: .activate))
        } else if let url = URL(string: link.payload) {
            openURL(url)
        }
    }
}
