import MetalUICodeBuffer
import MetalUICore
import MetalUILayout
import MetalUITextSystem

/// What a `CodeView` keeps between frames (`CV-O`): the scroll anchor, the pending wheel travel, the
/// horizontal offset and the width measured so far. Equatable, so a settled view re-stores what is there
/// through a **compared** write that bumps no version.
struct CodeViewState: Equatable {
    /// The top row as a byte offset and the version it was taken at: mapped through the edits since by
    /// `CodeBuffer.map`, so lines inserted above do not move what the reader is looking at.
    var anchorOffset = 0
    var anchorVersion: UInt64?
    /// The anchor row as of the last write: the fallback when the buffer's edit log no longer reaches back.
    var anchorRow = 0
    /// Device pixels scrolled into the anchor row.
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
}

/// Rows of the display, in order. Today every display row is a buffer row; the map exists so that rows
/// that are not (read-only virtual rows) can be added without changing the geometry code.
struct CodeRowMap {
    enum Row { case buffer(Int) }
    let bufferRows: Int
    var displayRowCount: Int { bufferRows }
    func displayRow(ofBufferRow row: Int) -> Int { row }
    func row(atDisplay display: Int) -> Row { .buffer(display) }
}

/// One frame's geometry and laid-out rows (`CV-N`): built in prepaint, read by paint and by the pointer
/// handlers, which keep the plan of the frame they were registered in.
final class CodeViewPlan {
    struct Row {
        let display: Int
        let buffer: Int
        /// The row's top, in absolute device pixels of the view's coordinate space.
        let top: Int
        let range: Range<Int>
        let layout: CodeLineLayout
        let styling: CodeDecorations.LineStyling
        let label: CodeLineLayout?
        let labelWidthPx: Int
    }

    var scale: Float = 1
    var snapshot: CodeSnapshot
    var rows: [Row] = []
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

    /// The byte offset nearest `point` (view-local points).
    func offset(at point: Point<Pixels>) -> Int {
        guard !rows.isEmpty else { return 0 }
        let y = originY + Int((Double(point.y.value) * Double(scale)).rounded(.down))
        let row = rows.first(where: { y >= $0.top && y < $0.top + pitchPx }) ?? (y < rows[0].top ? rows[0] : rows[rows.count - 1])
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
        let map = CodeRowMap(bufferRows: snap.lineCount)
        let displayRows = map.displayRowCount
        plan.maxTopPx = max(0, displayRows * pitchPx - plan.heightPx)

        // The anchor, mapped through the edits since it was taken.
        var anchorRow = 0
        if let version = state.anchorVersion {
            if version == snap.version {
                anchorRow = snap.point(at: min(state.anchorOffset, snap.utf8Count)).row
            } else if let moved = buffer.map(state.anchorOffset, from: version, bias: .after) {
                anchorRow = snap.point(at: min(moved, snap.utf8Count)).row
            } else {
                anchorRow = state.anchorRow
            }
        }
        anchorRow = min(max(0, anchorRow), max(0, displayRows - 1))
        var topPx = map.displayRow(ofBufferRow: anchorRow) * pitchPx + (state.anchorVersion == nil ? 0 : state.remainderPx)

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
        state.anchorRow = firstRow
        state.anchorOffset = snap.lineRange(firstRow).lowerBound
        state.anchorVersion = snap.version
        state.remainderPx = topPx % pitchPx

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
        for display in lower..<max(lower, upper) {
            guard case .buffer(let row) = map.row(atDisplay: display) else { continue }
            let range = snap.lineRange(row)
            let styling = decorations.stylingOfLine(range)
            let layout = lineLayout(range, snapshot: snap, styling: styling, font: font, system: system, scale: scale,
                                    cache: cache, spaceAdvance: metrics.space, scrollXPx: state.scrollXPx,
                                    textViewPx: textViewPx, advancePx: advancePx)
            widest = max(widest, Int((layout.width * scaleD).rounded(.up)))
            var label: CodeLineLayout?
            var labelWidth = 0
            if showsNumbers {
                let digitsBytes = Array(String(row + 1).utf8)
                let key = CodeLineKey(textHash: codeHash(digitsBytes), byteCount: digitsBytes.count, styleDigest: 0, font: font,
                                      scaleBits: scale.bitPattern, tabColumns: 0, system: ObjectIdentifier(system),
                                      windowStart: 0, windowEnd: 0)
                let made = cache.layout(key, gutter: true) {
                    buildCodeLine(bytes: digitsBytes[...], windowStart: 0, windowX: 0, parts: [(digitsBytes.count, nil)], partOffset: 0,
                                  font: font, scale: scale, tabColumns: 0, spaceAdvance: metrics.space, system: system)
                }
                label = made
                labelWidth = Int((made.width * scaleD).rounded())
            }
            plan.rows.append(.init(display: display, buffer: row,
                                   top: plan.originY + (display - firstRow) * pitchPx - remainder,
                                   range: range, layout: layout, styling: styling, label: label, labelWidthPx: labelWidth))
        }
        state.measuredWidthPx = max(state.measuredWidthPx, widest)

        frame.codeWork.linesShaped += cache.shapedTotal - shapedBefore
        frame.codeWork.highlightRunsVisited += decorations.runsVisited - runsBefore

        // The provider is asked after the frame, outside every phase, for the rows shown or a viewport off.
        if decorations.highlightProvider != nil {
            let wanted = max(0, firstRow - visible)..<min(snap.lineCount, firstRow + 2 * visible + 1)
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

    /// One line's layout, from the cache or shaped (a long line only in its column window).
    @MainActor
    private func lineLayout(_ range: Range<Int>, snapshot: CodeSnapshot, styling: CodeDecorations.LineStyling,
                            font: FontKey, system: any TextSystem, scale: Float, cache: CodeLineCache,
                            spaceAdvance: Double, scrollXPx: Int, textViewPx: Int, advancePx: Double) -> CodeLineLayout {
        let bytes = snapshot.utf8(in: range)
        var windowStart = 0, windowEnd = bytes.count
        var windowX = 0.0
        var parts = styling.foreground
        var digest = styling.digest
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
        let slice = bytes[windowStart..<windowEnd]
        let whole = windowStart == 0 && windowEnd == bytes.count
        let key = CodeLineKey(textHash: codeHash(slice), byteCount: slice.count, styleDigest: digest, font: font,
                              scaleBits: scale.bitPattern, tabColumns: tabColumns, system: ObjectIdentifier(system),
                              windowStart: whole ? 0 : windowStart, windowEnd: whole ? 0 : windowEnd)
        return cache.layout(key) {
            buildCodeLine(bytes: slice, windowStart: windowStart, windowX: windowX, parts: parts, partOffset: 0, font: font,
                          scale: scale, tabColumns: tabColumns, spaceAdvance: spaceAdvance, system: system)
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
        let shown = plan.rows.filter { $0.top < viewBottom && $0.top + plan.pitchPx > viewTop }
        let frame = pass.frame
        frame.codeWork.linesPainted += shown.count

        pass.fill(bounds, color: pass.resolve(theme.background))
        pass.clipped(to: bounds, offsetBy: zero) {
            if let gutterBackground = theme.gutterBackground, plan.gutterPx > 0 {
                pass.fill(rect(plan.originX, viewTop, textLeft, viewBottom), color: pass.resolve(gutterBackground))
            }
            // 1. Line tints: consecutive rows with an equal decoration are one rectangle.
            var index = 0
            while index < shown.count {
                guard let payload = decorations.lineDecoration(row: shown[index].buffer), let color = payload.background else {
                    index += 1
                    continue
                }
                var end = index
                while end + 1 < shown.count, shown[end + 1].display == shown[end].display + 1,
                      decorations.lineDecoration(row: shown[end + 1].buffer) == payload { end += 1 }
                pass.fill(rect(plan.originX, shown[index].top, textRight, shown[end].top + plan.pitchPx), color: pass.resolve(color))
                index = end + 1
            }
            // The text region: backgrounds of runs, the selection and the glyphs.
            pass.clipped(to: rect(textLeft, viewTop, textRight, viewBottom), offsetBy: zero) {
                let tokens = pass.resolve(theme.foreground)
                let selectionColor = pass.resolve(theme.selection)
                for row in shown {
                    func x(_ byte: Int) -> Int {
                        let local = byte - row.range.lowerBound
                        let points = row.layout.x(ofByte: local)
                            ?? (local < row.layout.windowStart ? row.layout.caretX.first : row.layout.caretX.last) ?? 0
                        return plan.textOriginX + Int((points * scaleD).rounded())
                    }
                    for background in row.styling.backgrounds {
                        pass.fill(rect(x(background.range.lowerBound), row.top, x(background.range.upperBound), row.top + plan.pitchPx),
                                  color: pass.resolve(background.color))
                    }
                    // 4. The selection, with the line break's tail past the end of a selected line.
                    let selection = plan.selection
                    if !selection.isEmpty {
                        let lo = max(selection.lowerBound, row.range.lowerBound), hi = min(selection.upperBound, row.range.upperBound)
                        let breaks = selection.lowerBound <= row.range.upperBound && selection.upperBound > row.range.upperBound
                            && row.buffer + 1 < plan.snapshot.lineCount
                        if lo < hi || breaks {
                            let x0 = x(min(lo, hi)), x1 = x(max(lo, hi)) + (breaks ? Int((4 * scaleD).rounded()) : 0)
                            pass.fill(rect(x0, row.top, x1, row.top + plan.pitchPx), color: selectionColor)
                        }
                    }
                    // 5. The glyphs, translated by whole device pixels.
                    var colors: [Hsla] = []
                    for part in row.styling.foreground {
                        colors.append(part.style.flatMap { decorations.style($0).foreground }.map { pass.resolve($0) } ?? tokens)
                    }
                    if colors.isEmpty { colors = [tokens] }
                    let dx = plan.textOriginX
                    var emitted = 0
                    for (i, glyph) in row.layout.glyphs.enumerated() {
                        let px = glyph.pixelX + dx
                        if px < textLeft - 4 * plan.pitchPx || px > textRight { continue }
                        pass.draw(TextGlyph(key: glyph.key, pixelX: px, baselineY: glyph.baselineY + row.top),
                                  color: colors[min(Int(row.layout.glyphParts[i]), colors.count - 1)])
                        emitted += 1
                    }
                    frame.codeWork.glyphsEmitted += emitted
                }
            }
            // 8. The gutter: numbers, then the author bars.
            if plan.gutterPx > 0 {
                let numbers = pass.resolve(theme.gutterForeground)
                pass.clipped(to: rect(plan.originX, viewTop, textLeft, viewBottom), offsetBy: zero) {
                    for row in shown {
                        guard let label = row.label else { continue }
                        let dx = textLeft - plan.padPx - row.labelWidthPx
                        for glyph in label.glyphs {
                            pass.draw(TextGlyph(key: glyph.key, pixelX: glyph.pixelX + dx, baselineY: glyph.baselineY + row.top), color: numbers)
                        }
                    }
                    let barWidth = max(1, Int((3 * scaleD).rounded()))
                    var i = 0
                    while i < shown.count {
                        guard let payload = decorations.lineDecoration(row: shown[i].buffer), let bar = payload.gutterBar else {
                            i += 1
                            continue
                        }
                        var end = i
                        while end + 1 < shown.count, shown[end + 1].display == shown[end].display + 1,
                              decorations.lineDecoration(row: shown[end + 1].buffer) == payload { end += 1 }
                        pass.fill(rect(textLeft - barWidth - Int(scaleD.rounded()), shown[i].top, textLeft - Int(scaleD.rounded()),
                                       shown[end].top + plan.pitchPx), color: pass.resolve(bar))
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
