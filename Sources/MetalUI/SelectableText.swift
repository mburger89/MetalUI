import MetalUICore
import MetalUIPlatform
import MetalUITextSystem

// A selectable `Text` (rulings `TXS-B`…`TXS-H`, decisions `docs/superpowers/2026-11-23-text-selectability-decisions.md`,
// design `docs/superpowers/specs/2026-11-23-text-selectability-design.md`): the grapheme tables and line geometry a press
// maps a point through, the window's one session, and the frame's region list. The API and the environment field are in
// `TextSelectability.swift`; the window stage, ⌘C/⌘A and the right-click menu are at the foot of this file.

// MARK: - The string's tables

/// A string's graphemes and the UTF-16 offset of each boundary, built once per session (`TXS-D`): the unit
/// `TextEditing` selects in is the grapheme, the unit the text system's line ranges and an accessibility client's range
/// are in is UTF-16.
struct SelectableTextIndex {
    let characters: [Character]
    /// The UTF-16 offset of every grapheme boundary: `characters.count + 1` values, the first 0.
    let utf16: [Int]

    init(_ string: String) {
        let characters = Array(string)
        var offsets: [Int] = []
        offsets.reserveCapacity(characters.count + 1)
        var running = 0
        offsets.append(0)
        for character in characters {
            running += character.utf16.count
            offsets.append(running)
        }
        self.characters = characters
        self.utf16 = offsets
    }

    var count: Int { characters.count }

    /// The boundary at or before UTF-16 `unit` (the largest grapheme boundary not past it).
    func grapheme(atUTF16 unit: Int) -> Int {
        var low = 0, high = utf16.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if utf16[mid] <= unit { low = mid } else { high = mid - 1 }
        }
        return low
    }

    /// The graphemes `range` covers, as a string.
    func string(_ range: Range<Int>) -> String { String(characters[range]) }

    /// The UTF-16 range of the graphemes `range` covers.
    func utf16Range(_ range: Range<Int>) -> Range<Int> { utf16[range.lowerBound]..<utf16[range.upperBound] }

    /// The paragraph (the graphemes between hard breaks, the break excluded) around boundary `index`.
    func paragraph(around index: Int) -> Range<Int> {
        var lower = min(max(index, 0), count), upper = lower
        while lower > 0, !characters[lower - 1].isNewline { lower -= 1 }
        while upper < count, !characters[upper].isNewline { upper += 1 }
        return lower..<upper
    }
}

// MARK: - Line geometry (`TXS-D`)

/// Where a laid-out `Text`'s lines and grapheme boundaries are, in points from the glyph box's top-leading corner
/// (`Text.glyphBox`'s origin): built at the first prepaint after a press from the styled measurement paint draws with, so a
/// boundary found here is a boundary on screen. Cached by the box it was built for.
struct SelectableTextGeometry {
    struct Line {
        /// The line's graphemes, its hard break excluded.
        var range: Range<Int>
        var top: Double
        var height: Double
        /// The line's alignment offset (`TextLineBox.offsetX`).
        var originX: Double
        /// `caretOffsets` of the line's text, run by run: `range.count + 1` values, the first 0, each at most the line's width.
        var offsets: [Double]
    }

    var lines: [Line]
    let width: Double
    let height: Double
    let graphemeCount: Int

    /// The geometry of `resolved` wrapped at `width` in a box `height` tall — the lines `Text.paint` draws
    /// (`styledTextLines`, the call paint and layout share), each boundary's x from the text system's `caretOffsets`
    /// over the line's runs.
    @MainActor
    static func make(_ resolved: ResolvedRichText, index: SelectableTextIndex, wrappingAt width: Double, height: Double,
                     system: any TextSystem) -> SelectableTextGeometry {
        let laid = styledTextLines(resolved, system: system, wrappingAt: width, height: height)
        let runBounds = resolved.text.runBoundaries
        var lines: [Line] = []
        lines.reserveCapacity(laid.measured.lines.count)
        for box in laid.measured.lines {
            let lower = index.grapheme(atUTF16: box.range.lowerBound)
            var upper = index.grapheme(atUTF16: box.range.upperBound)
            if upper > lower, index.characters[upper - 1].isNewline { upper -= 1 }
            lines.append(Line(range: lower..<upper, top: box.top, height: box.height, originX: box.offsetX,
                              offsets: offsets(of: lower..<upper, runBounds: runBounds, resolved: resolved, index: index,
                                               limit: box.width, system: system)))
        }
        return SelectableTextGeometry(lines: lines, width: width, height: height, graphemeCount: index.count)
    }

    /// `range`'s boundary x offsets: one `caretOffsets` call per run the range crosses, each piece starting where the
    /// last ended (a one-run text is one call).
    @MainActor
    private static func offsets(of range: Range<Int>, runBounds: [Int], resolved: ResolvedRichText,
                                index: SelectableTextIndex, limit: Double, system: any TextSystem) -> [Double] {
        var result = [0.0]
        result.reserveCapacity(range.count + 1)
        var cursor = range.lowerBound
        var run = 0
        while cursor < range.upperBound, run < resolved.text.runs.count {
            let end = min(max(index.grapheme(atUTF16: runBounds[run + 1]), cursor), range.upperBound)
            if end > cursor {
                let local = system.caretOffsets(index.string(cursor..<end), font: resolved.text.runs[run].style.font)
                let base = result[result.count - 1]
                for i in 1..<local.count { result.append(min(base + local[i], max(limit, base))) }
                cursor = end
            }
            run += 1
        }
        // Rounding at a run boundary can leave graphemes unmeasured: they sit at the line's end.
        while result.count < range.count + 1 { result.append(result[result.count - 1]) }
        return result
    }

    /// The grapheme boundary under `point` (local to the glyph box): on the line under `y` (above the first line is the
    /// text's start, below the last its end), nearest `x`.
    func boundary(at point: Point<Pixels>) -> Int {
        guard let first = lines.first, let last = lines.last else { return 0 }
        let y = Double(point.y.value), x = Double(point.x.value)
        if y < first.top { return first.range.lowerBound }
        if y >= last.top + last.height { return last.range.upperBound }
        var low = 0, high = lines.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lines[mid].top <= y { low = mid } else { high = mid - 1 }
        }
        let line = lines[low]
        return line.range.lowerBound + TextEditing.boundary(nearest: x - line.originX, offsets: line.offsets)
    }

    /// The visual line under `point`'s y (clamped to the first and last), its hard break excluded: a triple click's unit,
    /// provisional (`HC-TXS-2`).
    func lineRange(at point: Point<Pixels>) -> Range<Int> {
        guard !lines.isEmpty else { return 0..<0 }
        let y = Double(point.y.value)
        var low = 0, high = lines.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lines[mid].top <= y { low = mid } else { high = mid - 1 }
        }
        return lines[low].range
    }

    /// One rect per line `range` touches, in points from the glyph box's top-leading corner.
    func rects(for range: Range<Int>) -> [Bounds<Pixels>] {
        var result: [Bounds<Pixels>] = []
        guard !range.isEmpty else { return result }
        for line in lines {
            let lower = max(range.lowerBound, line.range.lowerBound), upper = min(range.upperBound, line.range.upperBound)
            guard lower < upper else { continue }
            let x0 = line.originX + line.offsets[lower - line.range.lowerBound]
            let x1 = line.originX + line.offsets[upper - line.range.lowerBound]
            result.append(Bounds(origin: Point(x: Pixels(Float(x0)), y: Pixels(Float(line.top))),
                                 size: Size(width: Pixels(Float(max(x1 - x0, 0))), height: Pixels(Float(line.height)))))
        }
        return result
    }
}

// MARK: - The session (`TXS-B`)

/// One selectable `Text`'s selection: the window's only one (`TXS-B`; never a `StateTable` entry, a read of which would
/// create one). Held by `Window` and handed to each frame; **the press is deferred to the first prepaint of the pressed
/// `Text`** (the geometry needs its environment and text system, which a region deliberately does not carry: an idle
/// selectable `Text` registers one hitbox and nothing else).
@MainActor
final class TextSelectionSession {
    /// A pointer operation recorded at event time, in the pressed `Text`'s local space.
    enum Operation {
        case press(Point<Pixels>, clickCount: Int, extend: Bool)
        case drag(Point<Pixels>)
    }

    let id: GlobalElementID
    /// The string the selection is of; a different string drops the session (`TXS-F`, divergence: SwiftUI keeps a stale range).
    let string: String
    let index: SelectableTextIndex
    /// Anchor and head, in graphemes of ``string``.
    var state = TextEditState()
    var geometry: SelectableTextGeometry?
    var pending: [Operation] = []
    /// How many times the geometry was built for this session (test observability: a press builds it once, a drag never).
    private(set) var geometryBuilds = 0
    /// A primary press is down on this `Text`: drags extend.
    var isDragging = false
    /// Whether the last frame's prepaint produced this `Text` with its string unchanged; the window drops a session that
    /// was not (`TXS-F`: the `Text` left the tree, lost its modifier, or its string changed).
    var producedThisFrame = false
    var isDropped = false

    init(id: GlobalElementID, string: String) {
        self.id = id
        self.string = string
        self.index = SelectableTextIndex(string)
    }

    var selection: Range<Int> { state.selection }
    var isEmpty: Bool { state.selection.isEmpty }

    /// The selected text — the whole string's graphemes, whatever a line limit shows (`TXS-D`, probe `T1`).
    var selectedText: String? { isEmpty ? nil : index.string(selection.clamped(to: 0..<(index.count + 1))) }

    /// The selection in UTF-16 units, for an accessibility client.
    var selectedUTF16: Range<Int>? {
        isEmpty ? nil : index.utf16Range(selection.clamped(to: 0..<(index.count + 1)))
    }

    func noteGeometryBuilt() { geometryBuilds += 1 }

    func selectAll() {
        state.anchor = 0
        state.head = index.count
        state.dragGranularity = .character
        state.dragOrigin = 0..<index.count
    }

    /// Applies `operation` now when the geometry is built, else at the next prepaint of the `Text`.
    func enqueue(_ operation: Operation) {
        if let geometry { apply(operation, geometry) } else { pending.append(operation) }
    }

    /// Applies what was recorded before the geometry existed, in order.
    func drainPending() {
        guard let geometry, !pending.isEmpty else { return }
        let operations = pending
        pending = []
        for operation in operations { apply(operation, geometry) }
    }

    private func apply(_ operation: Operation, _ geometry: SelectableTextGeometry) {
        switch operation {
        case .press(let point, let clickCount, let extend):
            let boundary = geometry.boundary(at: point)
            if !extend, clickCount >= 3 {
                // Provisional (HC-TXS-2): a triple click selects the visual line, a fourth click its paragraph.
                let unit = clickCount == 3 ? geometry.lineRange(at: point) : index.paragraph(around: boundary)
                state.anchor = unit.lowerBound
                state.head = unit.upperBound
                state.dragGranularity = .character
                state.dragOrigin = unit
            } else {
                state = TextEditing.press(at: boundary, clickCount: clickCount, extend: extend,
                                          characters: index.characters, state: state)
            }
        case .drag(let point):
            state = TextEditing.drag(to: geometry.boundary(at: point), characters: index.characters, state: state)
        }
    }
}

private extension Range where Bound == Int {
    func clamped(to limits: Range<Int>) -> Range<Int> {
        let lower = Swift.min(Swift.max(lowerBound, limits.lowerBound), limits.upperBound)
        let upper = Swift.min(Swift.max(upperBound, lower), limits.upperBound)
        return lower..<upper
    }
}

// MARK: - The frame's regions (`TXS-C`)

/// One selectable `Text` the frame registered: the element, the index of its hitbox in the frame's list, and its string.
/// A struct of three references and an `Int`, appended to an array reserved from the last frame's count — no class box, no
/// closure, so an idle selectable `Text` allocates nothing (`TXS-H`).
struct SelectableTextRegion {
    let id: GlobalElementID
    let hitbox: Int
    let string: String
}

extension Frame {
    /// Registers a selectable `Text` (`TXS-C`) — called from `Text.prepaint` inside the decoration's scope, so the render
    /// effects and the clip are the `Text`'s own — and, while a client collects, marks its accessibility record
    /// selectable (`TXS-G`).
    ///
    /// **The provisional rule for a `Text` with handlers of its own is here and only here** (`TXS-C`, `HC-TXS-4`): the
    /// selection hitbox is opaque and registered after the `Text`'s own, so it wins over a tap on the `Text` or an ancestor
    /// (probe `G1`/`G2`). If a real click turns out to fire the tap, `skipsRegistration(forHandlers:)` returns true for a
    /// `Text` with pointer handlers and nothing else changes.
    @MainActor
    func registerSelectableText(id: GlobalElementID, box: (origin: Point<Pixels>, width: Double, height: Double),
                                string: String, handlers: Handlers) {
        if collectsAccessibility {
            markAccessibilitySelectable(id, selected: textSelection.flatMap { $0.id == id && !$0.isDropped && $0.string == string
                ? $0.selectedUTF16 : nil })
        }
        guard !string.isEmpty, environmentTop.isEnabled, registersPointerHitboxes,
              !Self.skipsRegistration(forHandlers: handlers) else { return }

        let bounds = Bounds(origin: box.origin, size: Size(width: Pixels(Float(box.width)), height: Pixels(Float(box.height))))
        let hitbox = insertHitbox(bounds, id: id, opaque: true, origin: box.origin)
        selectableTextRegions.append(SelectableTextRegion(id: id, hitbox: hitbox.index, string: string))
        // An occurrence holding a selectable `Text` prepaints in full (no prepaint ledger): the region list is not a journal
        // channel, and replaying its hitbox alone would orphan the region (`TXS-C`, record).
        prepaintLog?.taint("textSelection")
    }

    /// Whether a `Text` with these handlers registers no selection region. **Provisionally never** (`TXS-C`, `HC-TXS-4`).
    static func skipsRegistration(forHandlers handlers: Handlers) -> Bool { false }

    /// The selected `Text`'s prepaint (`TXS-B`, `TXS-D`): marks the session produced, drops it on a string change, builds the
    /// geometry a recorded press or a highlight needs, and applies the pending operations.
    @MainActor
    func prepaintSelected(_ session: TextSelectionSession, string: String, box: (origin: Point<Pixels>, width: Double, height: Double),
                          resolve: () -> ResolvedRichText) {
        guard !session.isDropped else { return }
        guard session.string == string else {
            session.isDropped = true   // `TXS-F`, S1: SwiftUI keeps a stale range; MetalUI drops it
            return
        }
        session.producedThisFrame = true
        let width = Swift.max(box.width, smallestWrapWidth)
        if let geometry = session.geometry, geometry.width != width || geometry.height != box.height { session.geometry = nil }
        guard session.geometry == nil, !session.pending.isEmpty || !session.isEmpty else { return }
        session.geometry = SelectableTextGeometry.make(resolve(), index: session.index, wrappingAt: width,
                                                       height: box.height, system: textSystem)
        session.noteGeometryBuilt()
        session.drainPending()
    }

    /// Marks `id`'s accessibility record selectable, with the selected UTF-16 range or none (`TXS-G`).
    private func markAccessibilitySelectable(_ id: GlobalElementID, selected: Range<Int>?) {
        attachAccessibilityTextSelection(AccessibilityTextSelection(range: selected), to: id)
    }
}

// MARK: - The window stage (`TXS-B`, `TXS-E`, `TXS-F`)

extension Window {
    /// Drops the selection (focus moved to an element, another `Text` was pressed, the `Text` left the tree or its string
    /// changed: `TXS-F`).
    func dropTextSelection() {
        guard let session = textSelectionSession else { return }
        session.isDropped = true
        textSelectionSession = nil
        setNeedsRedraw()
    }

    /// The region under `point` — the topmost opaque hitbox is a selectable `Text`'s own selection hitbox.
    private func selectableRegion(at point: Point<Pixels>) -> (region: SelectableTextRegion, hitbox: Hitbox)? {
        guard !lastSelectableRegions.isEmpty,
              let index = topmostOpaqueHitbox(in: lastHitboxes, at: point),
              let region = lastSelectableRegions.first(where: { $0.hitbox == index }) else { return nil }
        return (region, lastHitboxes[index])
    }

    /// The press, drag and release of a selectable `Text`, right after the text-field stage (`TXS-F`). A press over a region
    /// blurs a focused element, starts (or continues, on the same `Text`) the session and claims the event — the opaque
    /// selection hitbox wins over a tap or a link on the `Text` (`TXS-C`, provisional until `HC-TXS-4`). A press elsewhere
    /// changes nothing here; a focus change drops the session (`focusedElement`'s observer).
    func dispatchTextSelection(_ event: InputEvent) -> Bool {
        switch event {
        case .mouseDown(let mouse):
            guard let (region, hitbox) = selectableRegion(at: mouse.position) else { return false }
            if focusedElement != nil { focus(nil) }   // `TXS-B`: the press blurs a focused field; the session owns ⌘C and ⌘A
            let session: TextSelectionSession
            if let existing = textSelectionSession, existing.id == region.id, existing.string == region.string {
                session = existing
            } else {
                dropTextSelection()
                session = TextSelectionSession(id: region.id, string: region.string)
                textSelectionSession = session
            }
            session.isDragging = true
            session.enqueue(.press(hitbox.elementLocalPoint(mouse.position), clickCount: mouse.clickCount,
                                   extend: mouse.modifiers.contains(.shift)))
            return true
        case .mouseDragged(let mouse):
            guard let session = textSelectionSession, session.isDragging else { return false }
            // The region's hitbox follows the `Text` through scrolling and effects; with none this frame the drag is dropped.
            guard let region = lastSelectableRegions.first(where: { $0.id == session.id }) else { return true }
            session.enqueue(.drag(lastHitboxes[region.hitbox].elementLocalPoint(mouse.position)))
            return true
        case .mouseUp:
            guard let session = textSelectionSession, session.isDragging else { return false }
            session.isDragging = false
            return true
        default:
            return false
        }
    }

    /// ⌘C and ⌘A with a session, as the fallback after the focus chain and the clipboard handlers decline (`TXS-E`): copy
    /// writes the selection (declined when empty, so a later command binds the key), select-all selects the `Text`'s whole
    /// string, claimed while the session exists even when nothing is selected.
    func dispatchTextSelectionKey(_ event: InputEvent) -> Bool {
        guard let session = textSelectionSession, case .keyDown(let key) = event, key.modifiers == .primary else { return false }
        switch key.charactersIgnoringModifiers.lowercased() {
        case "c":
            return copyTextSelection()
        case "a":
            session.selectAll()
            return true
        default:
            return false
        }
    }

    /// Writes the selection to the clipboard; `false` when there is none.
    @discardableResult
    func copyTextSelection() -> Bool {
        guard let text = textSelectionSession?.selectedText else { return false }
        platformWindow.writeClipboard(text)
        return true
    }

    /// What the selection adds to the focus chain's clipboard commands (`TXS-E`): Copy while a range exists, Select All
    /// while the session does, empty or not (probe `D1p`).
    var textSelectionClipboardCommands: ClipboardCommands {
        guard let session = textSelectionSession, !session.isDropped else { return [] }
        return session.isEmpty ? [.selectAll] : [.selectAll, .copy]
    }

    /// Reads the frame's end for the session (`TXS-F`): the `Text` was not produced with its string, or the modifier left
    /// it — the session ends.
    func settleTextSelection() {
        guard let session = textSelectionSession else { return }
        if session.isDropped || !session.producedThisFrame { dropTextSelection() }
    }

    /// The right-click menu of a selectable `Text`: `[Copy, Select All]`, Copy off with no range (`TXS-E`, divergence: a
    /// declared `.contextMenu` wins, so this is asked only when `contextualTarget` found none).
    func openSelectionContextMenu(at mouse: MouseEvent) -> Bool {
        guard let (region, _) = selectableRegion(at: mouse.position) else { return false }
        let copyEnabled = textSelectionSession.map { $0.id == region.id && !$0.isEmpty } ?? false
        let attachment = ContextualAttachment(menu: { [weak self] in
            MenuItems([SelectionMenu(copyEnabled: copyEnabled,
                                     copy: { self?.copyTextSelection() },
                                     selectAll: { self?.selectAllText(in: region) })])
        }, help: nil)
        return openContextMenu(attachment, isEnabled: true, declaringID: region.id, at: mouse.position, openingPress: true)
    }

    /// Select All from the menu: the session of `region`'s `Text` (made if the press never made one), the whole string.
    private func selectAllText(in region: SelectableTextRegion) {
        if textSelectionSession?.id != region.id || textSelectionSession?.string != region.string {
            dropTextSelection()
            textSelectionSession = TextSelectionSession(id: region.id, string: region.string)
        }
        textSelectionSession?.selectAll()
        setNeedsRedraw()
    }
}

/// The two items a selectable `Text`'s right-click menu offers (`TXS-E`).
private struct SelectionMenu: MenuContent {
    let copyEnabled: Bool
    let copy: @MainActor () -> Void
    let selectAll: @MainActor () -> Void

    /// The two items. SPI: see `MenuContent`.
    @_spi(MenuInternals) public func _menuNodes(in context: _MenuContext) -> _MenuNodes {
        _MenuNodes([MenuNode(kind: .action, title: "Copy", isEnabled: copyEnabled, run: copy),
                    MenuNode(kind: .action, title: "Select All", isEnabled: true, run: selectAll)])
    }
}

// MARK: - Paint (`TXS-F`)

extension PaintPass {
    /// Fills a selected `Text`'s per-line rects, local to `origin`, before its glyphs: the accent at 0.3 as every field's
    /// selection is, and in a window that is not key a neutral `.separator` fill (the inactive colour, not measured:
    /// `HC-TXS-6`).
    func fillSelection(_ rects: [Bounds<Pixels>], at origin: Point<Pixels>) {
        var color: Hsla
        if frame.environmentTop.controlActiveState == .key {
            color = resolve(.accentColor)
            color.a *= 0.3
        } else {
            color = resolve(Color(.separator))
        }
        for rect in rects {
            fill(Bounds(origin: Point(x: Pixels(origin.x.value + rect.origin.x.value),
                                      y: Pixels(origin.y.value + rect.origin.y.value)), size: rect.size), color: color)
        }
    }
}
