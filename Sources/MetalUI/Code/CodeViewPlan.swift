import MetalUICodeBuffer
import MetalUICore
import MetalUILayout
import MetalUITextSystem

/// What a `CodeView` keeps between frames (`CV-O`): the scroll anchor, the pending wheel travel, the
/// horizontal offset and the width measured so far. Equatable, so a settled view re-stores what is there
/// through a **compared** write that bumps no version.
struct CodeViewState: Equatable {
    /// The top buffer row as a byte offset and the version it was taken at: mapped through the edits since by
    /// `CodeBuffer.map`, so lines inserted above do not move what the reader is looking at.
    var anchorOffset = 0
    var anchorVersion: UInt64?
    /// The anchor row as of the last write: the fallback when the buffer's edit log no longer reaches back.
    var anchorRow = 0
    /// Device pixels scrolled from the anchor row's top to the view's top. Positive: into the row and the
    /// virtual lines after it; negative: the view's top is in the virtual lines before the anchor row.
    var remainderPx = 0
    /// Wheel travel not yet folded into the anchor, in points (a function of input, never of a phase).
    var pendingY = 0.0
    var pendingX = 0.0
    /// The horizontal offset, whole device pixels.
    var scrollXPx = 0
    /// The widest line laid out so far, device pixels; only grows (`CV-O`).
    var measuredWidthPx = 0
    /// When the wheel last moved the view: the scroll indicators fade from it.
    var lastScrollTime = -Double.infinity
    /// The `revealSerial` last honoured; `nil` before the first frame, which honours none.
    var revealSeen: UInt64?
    /// The scroll position last reported to the `CodeScrollState` / `onScroll` (device pixels); `nil` before
    /// the first frame. A frame whose position differs reports it after the build (`CV-T`).
    var reportedTopPx: Int?
    var reportedXPx = 0
    /// The `CodeScrollState.revision` last adopted; `nil` before the first frame, which adopts the state's value.
    var scrollRevisionSeen: UInt64?
}

/// One frame's geometry and laid-out rows (`CV-N`): built in prepaint, read by paint and by the pointer
/// handlers, which keep the plan of the frame they were registered in.
final class CodeViewPlan {
    struct Row {
        let display: Int
        /// The buffer row; for a virtual line, the buffer row it sits before (`lineCount` after the last).
        let buffer: Int
        let isVirtual: Bool
        /// The row's top, in absolute device pixels of the view's coordinate space.
        let top: Int
        /// The line's bytes in the buffer; for a virtual line an empty range at the offset of its gap, which
        /// is what a press on it resolves to (virtual lines cannot be selected, `CV-S`).
        let range: Range<Int>
        /// The byte offset the layout's x origin and the styling's ranges count from.
        let textStart: Int
        let layout: CodeLineLayout
        let styling: CodeDecorations.LineStyling
        let tint: Color?
        let bar: Color?
        let label: CodeLineLayout?
        let labelWidthPx: Int
        let labelColor: Color?
        /// A virtual line's text (accessibility); `nil` for a buffer row.
        let virtualText: String?
    }

    var scale: Float = 1
    var snapshot: CodeSnapshot
    var rows: [Row] = []
    /// The rows that intersect the viewport (the rest are overscan, shaped and not painted).
    var shownFrom = 0, shownTo = 0
    var font: FontKey
    var pitchPx = 1
    var originX = 0, originY = 0, widthPx = 0, heightPx = 0
    var gutterPx = 0, padPx = 0
    var topPx = 0, maxTopPx = 0
    var scrollXPx = 0, maxScrollXPx = 0
    var selection: Range<Int> = 0..<0
    var spaceAdvance = 0.0

    init(snapshot: CodeSnapshot, font: FontKey) {
        self.snapshot = snapshot
        self.font = font
    }

    /// The x of the text origin (column 0 of every line), absolute device pixels.
    var textOriginX: Int { originX + gutterPx + padPx - scrollXPx }

    // MARK: Hit testing

    /// The byte offset nearest `point` (view-local points). A virtual line resolves to the start of the buffer
    /// row it sits before: it is not text of the buffer.
    func offset(at point: Point<Pixels>) -> Int {
        guard !rows.isEmpty else { return 0 }
        let y = originY + Int((Double(point.y.value) * Double(scale)).rounded(.down))
        var index = 0
        if y >= rows[0].top {
            index = rows.count - 1
            var i = 0
            while i < rows.count {
                if y >= rows[i].top && y < rows[i].top + pitchPx { index = i; break }
                i += 1
            }
        }
        let row = rows[index]
        let x = originX + Int((Double(point.x.value) * Double(scale)).rounded(.down))
        let local = Double(x - textOriginX) / Double(scale)
        let byte = min(max(0, row.layout.byte(atX: local)), row.range.count)
        return row.range.lowerBound + byte
    }

    /// Whether `point` is in the gutter.
    func isInGutter(_ point: Point<Pixels>) -> Bool {
        gutterPx > 0 && Int((Double(point.x.value) * Double(scale)).rounded(.down)) < gutterPx
    }

    /// The word, whitespace run or single symbol at `offset`, as a byte range.
    func unit(atWord offset: Int) -> Range<Int> {
        let row = snapshot.point(at: offset).row
        let line = snapshot.lineRange(row)
        let characters = Array(snapshot.text(in: line))
        var starts = [0]
        for character in characters { starts.append(starts[starts.count - 1] + character.utf8.count) }
        let rel = min(max(0, offset - line.lowerBound), line.count)
        guard !characters.isEmpty else { return line }
        var index = 0
        while index + 1 < characters.count, starts[index + 1] <= rel { index += 1 }
        func kind(_ c: Character) -> Int { TextEditing.isWordCharacter(c) ? 1 : c.isWhitespace ? 2 : 0 }
        let k = kind(characters[index])
        var lo = index, hi = index + 1
        if k != 0 {
            while lo > 0, kind(characters[lo - 1]) == k { lo -= 1 }
            while hi < characters.count, kind(characters[hi]) == k { hi += 1 }
        }
        return (line.lowerBound + starts[lo])..<(line.lowerBound + starts[hi])
    }

    /// The line at `offset`, its terminator included (so a triple-click selects the break too).
    func unit(atLine offset: Int) -> Range<Int> {
        let row = snapshot.point(at: offset).row
        let line = snapshot.lineRange(row)
        let end = row + 1 < snapshot.lineCount ? snapshot.offset(of: CodePoint(row: row + 1, column: 0)) : snapshot.utf8Count
        return line.lowerBound..<end
    }

    /// Applies a press-and-drag from `start` to `end` to the buffer's selection: by character, by word
    /// for a double click and by line for a triple click or a press in the gutter.
    @MainActor
    func select(from start: Point<Pixels>, to end: Point<Pixels>, clickCount: Int, in buffer: CodeBuffer) {
        let a = offset(at: start), b = offset(at: end)
        let byLine = isInGutter(start) || clickCount >= 3
        let first: Range<Int>, last: Range<Int>
        if byLine {
            first = unit(atLine: a); last = unit(atLine: b)
        } else if clickCount == 2 {
            first = unit(atWord: a); last = unit(atWord: b)
        } else {
            buffer.selections = [CodeSelection(anchor: a, head: b)]
            return
        }
        let forward = b >= a
        buffer.selections = [forward ? CodeSelection(anchor: first.lowerBound, head: max(first.upperBound, last.upperBound))
                                     : CodeSelection(anchor: first.upperBound, head: min(first.lowerBound, last.lowerBound))]
    }

    // MARK: Accessibility

    /// Most bytes of text the accessibility node carries (`CV-U`).
    static let accessibilityCapBytes = 64 * 1024

    /// The text of the rows in the viewport, one line each, capped at 64 KB: what a screen reader is given
    /// as the view's value. Built only while a client is present, never the whole document.
    func accessibilityText() -> String {
        CodeViewStats.accessibilityTextBuilds += 1
        var out = ""
        var bytes = 0
        var i = shownFrom
        while i < shownTo {
            let row = rows[i]
            let line = row.virtualText ?? snapshot.text(in: row.range)
            let room = Self.accessibilityCapBytes - bytes
            if line.utf8.count + 1 > room {
                // Cut on a scalar boundary and stop.
                var used = 0
                for scalar in line.unicodeScalars {
                    let width = String(scalar).utf8.count
                    if used + width > max(0, room) { break }
                    out.unicodeScalars.append(scalar)
                    used += width
                }
                break
            }
            out += line
            out += "\n"
            bytes += line.utf8.count + 1
            i += 1
        }
        return out
    }
}

/// Counters for the view's pins (`CV-U`): plain, single-threaded, meaningful in a test only.
package enum CodeViewStats {
    /// How many times a plan built the accessibility value.
    nonisolated(unsafe) package static var accessibilityTextBuilds = 0
}

extension CodeView {
    /// Long lines are shaped as a column window (`CV-M`): lines over this many bytes.
    static let longLineBytes = 4096

    // MARK: The plan

    @MainActor
    func makePlan(_ id: GlobalElementID, bounds: Bounds<Pixels>, stored: CodeViewState,
                  environment: EnvironmentValues, frame: Frame) -> (CodeViewPlan, CodeViewState) {
        let system = frame.textSystem
        let scale = frame.scaleFactor
        let scaleD = Double(scale)
        let font = resolvedFont(in: environment, system: system)
        decorations.sync()
        _ = decorations.revision     // observed: a decoration change redraws
        let snap = buffer.snapshot()   // observed: an edit redraws
        let cache = decorations.lineCache
        cache.begin(frame)
        let metrics = cache.metrics(of: font, system: system)
        let shapedBefore = cache.shapedTotal, runsBefore = decorations.runsVisited

        // Geometry in whole device pixels (`CV-N`).
        let pitchPx = max(1, Int((metrics.height * scaleD).rounded()))
        let plan = CodeViewPlan(snapshot: snap, font: font)
        plan.scale = scale
        plan.pitchPx = pitchPx
        plan.originX = Int((Double(bounds.origin.x.value) * scaleD).rounded())
        plan.originY = Int((Double(bounds.origin.y.value) * scaleD).rounded())
        plan.widthPx = Int((Double(bounds.size.width.value) * scaleD).rounded())
        plan.heightPx = Int((Double(bounds.size.height.value) * scaleD).rounded())
        plan.padPx = Int((6 * scaleD).rounded())
        plan.spaceAdvance = metrics.space
        let digits = max(2, String(snap.lineCount).count)
        let digitPx = Int((metrics.digit * scaleD).rounded(.up))
        plan.gutterPx = showsNumbers ? digits * digitPx + 2 * plan.padPx : 0
        plan.selection = buffer.primarySelection.range
        let textViewPx = max(1, plan.widthPx - plan.gutterPx - plan.padPx)

        var state = stored
        let map = decorations.rowMap   // the one place a display row becomes a buffer row or a virtual line (`CV-S`)
        let bufferRows = snap.lineCount
        let displayRows = map.displayRowCount
        plan.maxTopPx = max(0, displayRows * pitchPx - plan.heightPx)

        // The anchor (a buffer row), mapped through the edits since it was taken.
        var anchorRow = 0
        if let version = state.anchorVersion {
            if version == snap.version {
                anchorRow = snap.point(at: min(state.anchorOffset, snap.utf8Count)).row
            } else if let moved = buffer.map(state.anchorOffset, from: version, bias: .before) {   // text inserted at the anchor stays in view
                anchorRow = snap.point(at: min(moved, snap.utf8Count)).row
            } else {
                anchorRow = state.anchorRow
            }
        }
        anchorRow = min(max(0, anchorRow), max(0, bufferRows - 1))
        // A view that has not been laid out starts at the very top (virtual lines before the first row included).
        var topPx = state.anchorVersion == nil ? 0 : map.displayRow(ofBufferRow: anchorRow) * pitchPx + state.remainderPx

        // A position assigned to the scroll state is adopted before this frame's wheel travel (`CV-T`).
        var adopted = false
        if let scroll = scrollStateObject {
            let revision = scroll.revision   // observed: an assignment wakes the view, its own reports do not
            if state.scrollRevisionSeen != revision {
                let target = scroll.current
                topPx = Int((max(0, target.row) * Double(pitchPx)).rounded())
                state.scrollXPx = Int((max(0, target.x) * scaleD).rounded())
                state.pendingX = 0
                state.pendingY = 0
                state.scrollRevisionSeen = revision
                adopted = true
            }
        }

        // Wheel travel folds in; the fraction of a device pixel stays pending.
        let dy = state.pendingY * scaleD
        let wholeY = Int(dy.rounded(.towardZero))
        topPx += wholeY
        state.pendingY = (dy - Double(wholeY)) / scaleD
        let dx = state.pendingX * scaleD
        let wholeX = Int(dx.rounded(.towardZero))
        state.scrollXPx += wholeX
        state.pendingX = (dx - Double(wholeX)) / scaleD

        // `select(_:reveal: true)` centres the head's row (`CV-P`).
        let serial = buffer.revealSerial
        if let seen = state.revealSeen, seen != serial {
            let head = snap.point(at: min(buffer.primarySelection.head, snap.utf8Count)).row
            topPx = map.displayRow(ofBufferRow: head) * pitchPx - (plan.heightPx - pitchPx) / 2
        }
        state.revealSeen = serial
        topPx = min(max(0, topPx), plan.maxTopPx)
        plan.topPx = topPx
        let firstRow = topPx / pitchPx
        // The new anchor: the buffer row the first display row shows, or sits before.
        var anchorBuffer = 0
        switch map.row(atDisplay: firstRow) {
        case .buffer(let row): anchorBuffer = row
        case .virtual(_, _, let gap): anchorBuffer = min(gap, max(0, bufferRows - 1))
        }
        anchorBuffer = min(max(0, anchorBuffer), max(0, bufferRows - 1))
        state.anchorRow = anchorBuffer
        state.anchorOffset = snap.lineRange(anchorBuffer).lowerBound
        state.anchorVersion = snap.version
        state.remainderPx = topPx - map.displayRow(ofBufferRow: anchorBuffer) * pitchPx

        // Horizontal extent: estimated from the longest line, corrected upward by what was laid out.
        let estimate = Int((Double(snap.longestLineScalars) * metrics.space * scaleD).rounded(.up))
        plan.maxScrollXPx = max(0, max(estimate, state.measuredWidthPx) + plan.padPx - textViewPx)
        state.scrollXPx = min(max(0, state.scrollXPx), plan.maxScrollXPx)
        plan.scrollXPx = state.scrollXPx

        // The rows: the visible ones and one of overscan each side.
        let remainder = topPx % pitchPx
        let visible = (plan.heightPx + remainder + pitchPx - 1) / pitchPx
        let lower = max(0, firstRow - 1), upper = min(displayRows, firstRow + visible + 1)
        var widest = 0
        let advancePx = max(1.0, metrics.space * scaleD)
        let decorated = showsNumbers
        plan.rows.reserveCapacity(max(0, upper - lower))
        var display = lower
        while display < upper {
            let top = plan.originY + (display - firstRow) * pitchPx - remainder
            switch map.row(atDisplay: display) {
            case .buffer(let row):
                let range = snap.lineRange(row)
                let styling = decorations.stylingOfLine(range)
                let bytes = snap.utf8(in: range)
                let layout = lineLayout(bytes: bytes, knownHash: nil, parts: styling.foreground, digest: styling.digest,
                                        font: font, system: system, scale: scale, cache: cache, spaceAdvance: metrics.space,
                                        scrollXPx: state.scrollXPx, textViewPx: textViewPx, advancePx: advancePx)
                widest = max(widest, Int((layout.width * scaleD).rounded(.up)))
                var label: CodeLineLayout?
                var labelWidth = 0
                if decorated {
                    let made = cache.number(row + 1, font: font, system: system, scale: scale, spaceAdvance: metrics.space)
                    label = made
                    labelWidth = Int((made.width * scaleD).rounded())
                }
                let payload = decorations.lineDecoration(row: row)
                plan.rows.append(.init(display: display, buffer: row, isVirtual: false, top: top, range: range, textStart: range.lowerBound,
                                       layout: layout, styling: styling, tint: payload?.background, bar: payload?.gutterBar,
                                       label: label, labelWidthPx: labelWidth, labelColor: nil, virtualText: nil))
            case .virtual(let group, let lineIndex, let gap):
                let line = group.lines[lineIndex]
                let layout = lineLayout(bytes: line.bytes, knownHash: line.hash, parts: line.styling.foreground, digest: line.styling.digest,
                                        font: font, system: system, scale: scale, cache: cache, spaceAdvance: metrics.space,
                                        scrollXPx: state.scrollXPx, textViewPx: textViewPx, advancePx: advancePx)
                widest = max(widest, Int((layout.width * scaleD).rounded(.up)))
                var label: CodeLineLayout?
                var labelWidth = 0
                if decorated, let marker = line.marker, !marker.text.isEmpty {
                    let made = cache.marker(marker.text, font: font, system: system, scale: scale, spaceAdvance: metrics.space)
                    label = made
                    labelWidth = Int((made.width * scaleD).rounded())
                }
                let start = gap < bufferRows ? snap.lineRange(gap).lowerBound : snap.utf8Count
                plan.rows.append(.init(display: display, buffer: gap, isVirtual: true, top: top, range: start..<start, textStart: 0,
                                       layout: layout, styling: line.styling, tint: group.background, bar: group.gutterBar,
                                       label: label, labelWidthPx: labelWidth, labelColor: line.marker?.color, virtualText: line.text))
            }
            display += 1
        }
        state.measuredWidthPx = max(state.measuredWidthPx, widest)
        var from = 0
        while from < plan.rows.count, plan.rows[from].top + pitchPx <= plan.originY { from += 1 }
        var to = from
        while to < plan.rows.count, plan.rows[to].top < plan.originY + plan.heightPx { to += 1 }
        plan.shownFrom = from
        plan.shownTo = to

        frame.codeWork.linesShaped += cache.shapedTotal - shapedBefore
        frame.codeWork.highlightRunsVisited += decorations.runsVisited - runsBefore

        // The scroll position is reported after the build, outside every phase (`CV-T`).
        if scrollStateObject != nil || onScrollAction != nil {
            if state.reportedTopPx != topPx || state.reportedXPx != state.scrollXPx {
                let silent = adopted || state.reportedTopPx == nil
                state.reportedTopPx = topPx
                state.reportedXPx = state.scrollXPx
                let position = CodeScrollPosition(row: Double(topPx) / Double(pitchPx), x: Double(state.scrollXPx) / scaleD)
                let scroll = scrollStateObject, action = onScrollAction
                frame.animationStore.lifecycle.enqueue(LifecycleEvent(owner: id, action: {
                    MainActor.assumeIsolated {
                        scroll?.publish(position)
                        if !silent { action?(position) }
                    }
                }, departed: nil))
            }
        }

        // The provider is asked after the frame, outside every phase, for the rows shown or a viewport off.
        if decorations.highlightProvider != nil {
            let wanted = max(0, anchorBuffer - visible)..<min(snap.lineCount, anchorBuffer + 2 * visible + 1)
            if let rows = decorations.rowsNeedingHighlights(in: wanted, snapshot: snap), decorations.shouldRequest(rows) {
                let decorations = self.decorations
                frame.animationStore.lifecycle.enqueue(LifecycleEvent(owner: id, action: { [weak decorations] in
                    guard let decorations, let provider = decorations.highlightProvider else { return }
                    provider.decorations(decorations, needHighlightsForRows: rows, in: decorations.buffer.snapshot())
                }, departed: nil))
            }
        }
        return (plan, state)
    }

    /// One line's layout, from the cache or shaped (a long line only in its column window). `knownHash` is the
    /// hash of `bytes` when the caller has it (a virtual line's).
    @MainActor
    private func lineLayout(bytes: [UInt8], knownHash: UInt64?, parts partsIn: [(bytes: Int, style: CodeStyleID?)], digest digestIn: UInt64,
                            font: FontKey, system: any TextSystem, scale: Float, cache: CodeLineCache,
                            spaceAdvance: Double, scrollXPx: Int, textViewPx: Int, advancePx: Double) -> CodeLineLayout {
        var windowStart = 0, windowEnd = bytes.count
        var windowX = 0.0
        var parts = partsIn
        var digest = digestIn
        if bytes.count > Self.longLineBytes {
            let first = max(0, Int(Double(scrollXPx) / advancePx) - 256) / 256 * 256
            let last = (Int(Double(scrollXPx + textViewPx) / advancePx) + 2 + 256 + 255) / 256 * 256
            var column = 0
            var start = bytes.count, end = bytes.count
            for index in bytes.indices where bytes[index] & 0xC0 != 0x80 {
                if column == first { start = index }
                if column == last { end = index; break }
                column += 1
            }
            if first == 0 { start = 0 }
            windowStart = start
            windowEnd = max(start, end)
            windowX = (Double(first) * spaceAdvance * Double(scale)).rounded() / Double(scale)
            parts = CodeDecorations.slice(parts, windowStart..<windowEnd)
            digest = CodeDecorations.digest(of: parts)
        }
        let whole = windowStart == 0 && windowEnd == bytes.count
        let hash = whole ? (knownHash ?? codeHash(bytes, windowStart, windowEnd)) : codeHash(bytes, windowStart, windowEnd)
        let key = CodeLineKey(textHash: hash, byteCount: windowEnd - windowStart, styleDigest: digest, font: font,
                              scaleBits: scale.bitPattern, tabColumns: tabColumns, system: ObjectIdentifier(system),
                              windowStart: whole ? 0 : windowStart, windowEnd: whole ? 0 : windowEnd)
        let tabs = tabColumns
        return cache.layout(key) {
            buildCodeLine(bytes: bytes[windowStart..<windowEnd], windowStart: windowStart, windowX: windowX, parts: parts, partOffset: 0,
                          font: font, scale: scale, tabColumns: tabs, spaceAdvance: spaceAdvance, system: system)
        }
    }

    // MARK: Paint

    @MainActor
    func paintContent(_ id: GlobalElementID, bounds: Bounds<Pixels>, plan: CodeViewPlan, pass: inout PaintPass) {
        let scale = plan.scale
        let scaleD = Double(scale)
        let theme = decorations.theme
        let zero = Point(x: Pixels(0), y: Pixels(0))
        func rect(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) -> Bounds<Pixels> {
            Bounds(origin: Point(x: Pixels(Float(x0) / scale), y: Pixels(Float(y0) / scale)),
                   size: Size(width: Pixels(Float(max(0, x1 - x0)) / scale), height: Pixels(Float(max(0, y1 - y0)) / scale)))
        }
        let viewTop = plan.originY, viewBottom = plan.originY + plan.heightPx
        let textLeft = plan.originX + plan.gutterPx
        let textRight = plan.originX + plan.widthPx
        let from = plan.shownFrom, to = plan.shownTo
        let frame = pass.frame
        frame.codeWork.linesPainted += to - from

        pass.fill(bounds, color: pass.resolve(theme.background))
        pass.clipped(to: bounds, offsetBy: zero) {
            if let gutterBackground = theme.gutterBackground, plan.gutterPx > 0 {
                pass.fill(rect(plan.originX, viewTop, textLeft, viewBottom), color: pass.resolve(gutterBackground))
            }
            // 1. Line tints: consecutive rows with an equal tint are one rectangle.
            var index = from
            while index < to {
                guard let color = plan.rows[index].tint else {
                    index += 1
                    continue
                }
                var end = index
                while end + 1 < to, plan.rows[end + 1].tint == color { end += 1 }
                pass.fill(rect(plan.originX, plan.rows[index].top, textRight, plan.rows[end].top + plan.pitchPx), color: pass.resolve(color))
                index = end + 1
            }
            // The text region: backgrounds of runs, the selection and the glyphs.
            pass.clipped(to: rect(textLeft, viewTop, textRight, viewBottom), offsetBy: zero) {
                let tokens = pass.resolve(theme.foreground)
                let selectionColor = pass.resolve(theme.selection)
                var colors: [Hsla] = []
                var rowIndex = from
                while rowIndex < to {
                    let row = plan.rows[rowIndex]
                    rowIndex += 1
                    func x(_ byte: Int) -> Int {
                        let local = byte - row.textStart
                        let points = row.layout.x(ofByte: local)
                            ?? (local < row.layout.windowStart ? row.layout.caretX.first : row.layout.caretX.last) ?? 0
                        return plan.textOriginX + Int((points * scaleD).rounded())
                    }
                    var b = 0
                    while b < row.styling.backgrounds.count {
                        let background = row.styling.backgrounds[b]
                        pass.fill(rect(x(background.range.lowerBound), row.top, x(background.range.upperBound), row.top + plan.pitchPx),
                                  color: pass.resolve(background.color))
                        b += 1
                    }
                    // 4. The selection, with the line break's tail past the end of a selected line (buffer rows only).
                    let selection = plan.selection
                    if !selection.isEmpty && !row.isVirtual {
                        let lo = max(selection.lowerBound, row.range.lowerBound), hi = min(selection.upperBound, row.range.upperBound)
                        let breaks = selection.lowerBound <= row.range.upperBound && selection.upperBound > row.range.upperBound
                            && row.buffer + 1 < plan.snapshot.lineCount
                        if lo < hi || breaks {
                            let x0 = x(min(lo, hi)), x1 = x(max(lo, hi)) + (breaks ? Int((4 * scaleD).rounded()) : 0)
                            pass.fill(rect(x0, row.top, x1, row.top + plan.pitchPx), color: selectionColor)
                        }
                    }
                    // 5. The glyphs, translated by whole device pixels.
                    colors.removeAll(keepingCapacity: true)
                    var p = 0
                    while p < row.styling.foreground.count {
                        let part = row.styling.foreground[p]
                        if let style = part.style, let foreground = decorations.style(style).foreground {
                            colors.append(pass.resolve(foreground))
                        } else {
                            colors.append(tokens)
                        }
                        p += 1
                    }
                    if colors.isEmpty { colors.append(tokens) }
                    let dx = plan.textOriginX
                    let glyphs = row.layout.glyphs, parts = row.layout.glyphParts
                    let lastColor = colors.count - 1
                    var emitted = 0
                    var g = 0
                    while g < glyphs.count {
                        let glyph = glyphs[g]
                        let px = glyph.pixelX + dx
                        if px >= textLeft - 4 * plan.pitchPx && px <= textRight {
                            pass.draw(TextGlyph(key: glyph.key, pixelX: px, baselineY: glyph.baselineY + row.top),
                                      color: colors[min(Int(parts[g]), lastColor)])
                            emitted += 1
                        }
                        g += 1
                    }
                    frame.codeWork.glyphsEmitted += emitted
                }
            }
            // 8. The gutter: numbers and markers, then the author bars.
            if plan.gutterPx > 0 {
                let numbers = pass.resolve(theme.gutterForeground)
                pass.clipped(to: rect(plan.originX, viewTop, textLeft, viewBottom), offsetBy: zero) {
                    var rowIndex = from
                    while rowIndex < to {
                        let row = plan.rows[rowIndex]
                        rowIndex += 1
                        guard let label = row.label else { continue }
                        let color = row.labelColor.map { pass.resolve($0) } ?? numbers
                        let dx = textLeft - plan.padPx - row.labelWidthPx
                        var g = 0
                        while g < label.glyphs.count {
                            let glyph = label.glyphs[g]
                            pass.draw(TextGlyph(key: glyph.key, pixelX: glyph.pixelX + dx, baselineY: glyph.baselineY + row.top), color: color)
                            g += 1
                        }
                    }
                    let barWidth = max(1, Int((3 * scaleD).rounded()))
                    var i = from
                    while i < to {
                        guard let bar = plan.rows[i].bar else {
                            i += 1
                            continue
                        }
                        var end = i
                        while end + 1 < to, plan.rows[end + 1].bar == bar { end += 1 }
                        pass.fill(rect(textLeft - barWidth - Int(scaleD.rounded()), plan.rows[i].top, textLeft - Int(scaleD.rounded()),
                                       plan.rows[end].top + plan.pitchPx), color: pass.resolve(bar))
                        i = end + 1
                    }
                }
            }
        }
        // 9. The scroll indicators: numeric extents, faded from the last wheel (`CV-O`).
        let lastScroll = pass.readState(id, initial: CodeViewState()).lastScrollTime
        let vertical = ScrollChrome(axis: .vertical, cornerRadius: Pixels(0), indicatorVisibility: .automatic)
        vertical.paintIndicator(bounds: bounds, offset: Double(plan.topPx) / scaleD,
                                content: Double(plan.maxTopPx + plan.heightPx) / scaleD, viewport: Double(plan.heightPx) / scaleD,
                                lastScroll: lastScroll, pass: &pass)
        let horizontal = ScrollChrome(axis: .horizontal, cornerRadius: Pixels(0), indicatorVisibility: .automatic)
        let textBounds = Bounds(origin: Point(x: Pixels(Float(textLeft) / scale), y: bounds.origin.y),
                                size: Size(width: Pixels(Float(textRight - textLeft) / scale), height: bounds.size.height))
        horizontal.paintIndicator(bounds: textBounds, offset: Double(plan.scrollXPx) / scaleD,
                                  content: Double(plan.maxScrollXPx + (textRight - textLeft)) / scaleD,
                                  viewport: Double(textRight - textLeft) / scaleD, lastScroll: lastScroll, pass: &pass)
    }
}
