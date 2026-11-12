import MetalUICodeBuffer
import MetalUICore
import MetalUILayout
import MetalUIPlatform
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
    /// Whether the next frame must scroll the caret into view: set by every key, edit and caret move from input,
    /// left clear by the wheel and by a press so a scroll is not snapped back (`CV-X`).
    var revealsCaret = false
    /// The x, in points from the text origin, a run of vertical moves keeps returning to across short lines.
    var goalX: Double?
    /// The unit the last press selected (0 character, 1 word, 2 line) and its range, which a drag keeps (`CV-Y`).
    var dragGranularity: UInt8 = 0
    var dragOriginLower = 0
    var dragOriginUpper = 0
    /// Whether a press began a drag that has not been released (`CV-AD`).
    var dragging = false
    /// The input method's marked text, shown at `compositionOffset` (a buffer byte as of `compositionVersion`) and
    /// never in the buffer or its edit stream until committed (`CV-AA`).
    var composition = TextComposition.none
    var compositionOffset = 0
    var compositionVersion: UInt64 = 0
    /// What the caret's blink restarted at (`CV-AC`): the epoch is the frame time at which the caret last moved,
    /// an edit landed or the view gained focus; the caret is drawn for the first half second of each second after it.
    var blinkEpoch = 0.0
    var blinkSelection = 0..<0
    var blinkHead = 0
    var blinkVersion: UInt64 = 0
    var blinkFocused = false
    var blinkComposition = ""
    /// A drag selection that left the view (`CV-AD`): written from input, a function of the frame time in every phase.
    var autoscroll: Autoscroll?

    /// Scrolling while a drag is held outside the view: from `baseTopPx` and `baseXPx` at `start`, at `vy` and `vx`
    /// points a second. The pointer (window points) keeps the selection's head under it.
    struct Autoscroll: Equatable {
        var start: Double
        var baseTopPx: Int
        var baseXPx: Int
        var vy: Double
        var vx: Double
        var pointerX: Double
        var pointerY: Double
    }
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
        /// The app's tag of the row's decoration or virtual group (`CodeLineDecoration.tag`, `CodeVirtualRow.tag`).
        var tag: UInt64? = nil
        /// A virtual line's anchor buffer line (`CodeGutterHit.lines`); the row itself for a buffer row.
        var anchorLine = 0
        /// Where the input method's marked text sits in this row's layout, when it is the composing row (`CV-AA`).
        var marked: Marked? = nil

        /// The marked text inserted into this row's layout for display.
        struct Marked {
            /// The byte offset in the buffer line where it was inserted, from the line's start.
            let at: Int
            let length: Int
            /// The bytes of the marked text before the input method's selection.
            let caretBytes: Int
            /// The marked text's selected bytes (empty for a caret), from the marked text's start.
            let selected: Range<Int>
        }

        /// A buffer byte (absolute) mapped to the byte of this row's layout: bytes after the marked text move.
        func layoutByte(_ byte: Int) -> Int {
            let local = byte - textStart
            guard let marked else { return local }
            return local > marked.at ? local + marked.length : local
        }
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
    /// The primary selection's moving end.
    var head = 0
    var spaceAdvance = 0.0
    /// One buffer row's layout from the text now, through the line cache: what a key's vertical motion and caret
    /// x read in input, where the frame's own rows may be older than the buffer (`CV-X`).
    var layoutRow: (Int, CodeSnapshot) -> CodeLineLayout = { _, _ in fatalError("CodeViewPlan.layoutRow is set by makePlan") }
    /// The rows and tag of the gutter bar over a buffer row (`CodeDecorations`), read at click time (`CV-AB`).
    var gutterBarOf: (Int) -> (lines: Range<Int>, tag: UInt64?)? = { _ in nil }
    /// The caret's blink: whether this frame draws it, and when the next toggle is (`CV-AC`).
    var caretVisible = true
    /// While a drag autoscrolls, the selection the frame computed from the pointer and the frame time (`CV-AD`).
    var liveDragSelection: CodeSelection?

    init(snapshot: CodeSnapshot, font: FontKey) {
        self.snapshot = snapshot
        self.font = font
    }

    /// The x of the text origin (column 0 of every line), absolute device pixels.
    var textOriginX: Int { originX + gutterPx + padPx - scrollXPx }

    // MARK: Hit testing

    /// The byte offset nearest `point`, in window points as the window's hit test hands them over (the rows and the
    /// origin are in the same space). A virtual line resolves to the start of the buffer
    /// row it sits before: it is not text of the buffer.
    func offset(at point: Point<Pixels>) -> Int {
        guard !rows.isEmpty else { return 0 }
        let y = Int((Double(point.y.value) * Double(scale)).rounded(.down))
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
        let x = Int((Double(point.x.value) * Double(scale)).rounded(.down))
        let local = Double(x - textOriginX) / Double(scale)
        var byte = max(0, row.layout.byte(atX: local))
        if let marked = row.marked {   // the layout has the marked text in it: a point in it is its start
            byte = byte >= marked.at + marked.length ? byte - marked.length : min(byte, marked.at)
        }
        return row.range.lowerBound + min(byte, row.range.count)
    }

    /// The device-pixel x of byte `byte` of `row`'s line, as the painter places it.
    func xPx(_ row: Row, byte: Int) -> Int {
        xPx(row, layoutByte: row.layoutByte(byte))
    }

    /// The device-pixel x of byte `local` of `row`'s layout (marked text included).
    func xPx(_ row: Row, layoutByte local: Int) -> Int {
        let points = row.layout.x(ofByte: local)
            ?? (local < row.layout.windowStart ? row.layout.caretX.first : row.layout.caretX.last) ?? 0
        return textOriginX + Int((points * Double(scale)).rounded())
    }

    /// Where the caret is drawn: its x and the top of its row, device pixels; `nil` when its row is not among
    /// the frame's rows.
    func caretPosition() -> (x: Int, top: Int)? {
        var i = 0
        while i < rows.count {
            let row = rows[i]
            i += 1
            if !row.isVirtual && row.range.lowerBound <= head && head <= row.range.upperBound {
                if let marked = row.marked { return (xPx(row, layoutByte: marked.at + marked.caretBytes), row.top) }
                return (xPx(row, byte: head), row.top)
            }
        }
        return nil
    }

    /// Whether `point` (window points) is in the gutter.
    func isInGutter(_ point: Point<Pixels>) -> Bool {
        gutterPx > 0 && Int((Double(point.x.value) * Double(scale)).rounded(.down)) - originX < gutterPx
    }

    /// The selection a drag has at `offset`, for the press's `origin` and unit (0 character, 1 word, 2 line).
    func dragSelection(to offset: Int, origin: Range<Int>, granularity: UInt8) -> CodeSelection {
        if granularity == 0 { return CodeSelection(anchor: origin.lowerBound, head: offset) }
        let unit = granularity == 1 ? self.unit(atWord: offset) : self.unit(atLine: offset)
        return unit.lowerBound < origin.lowerBound
            ? CodeSelection(anchor: origin.upperBound, head: unit.lowerBound)
            : CodeSelection(anchor: origin.lowerBound, head: max(origin.upperBound, unit.upperBound))
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

    // MARK: Gutter bars

    /// The gutter bar under `point` (window points), or `nil`: a point in the bar's column (the bar widened by four
    /// points towards the line numbers) on a row that has one, a buffer row's decoration or a virtual line's group
    /// (`CV-AB`). A virtual line's bar is hit like any other: that is where a removed hunk's Revert lives.
    func gutterHit(at point: Point<Pixels>) -> CodeGutterHit? {
        guard gutterPx > 0 else { return nil }
        let x = Int((Double(point.x.value) * Double(scale)).rounded(.down))
        let y = Int((Double(point.y.value) * Double(scale)).rounded(.down))
        let barWidth = max(1, Int((3 * Double(scale)).rounded()))
        let reach = Int((4 * Double(scale)).rounded())
        let textLeft = originX + gutterPx
        guard x >= textLeft - barWidth - reach - Int(Double(scale).rounded()), x < textLeft, y >= originY, y < originY + heightPx else { return nil }
        var i = shownFrom
        while i < shownTo {
            let row = rows[i]
            i += 1
            guard y >= row.top, y < row.top + pitchPx else { continue }
            guard row.bar != nil else { return nil }
            if row.isVirtual {
                return CodeGutterHit(lines: row.anchorLine..<(row.anchorLine + 1), tag: row.tag, source: .virtualRow, displayRow: row.display)
            }
            guard let bar = gutterBarOf(row.buffer) else { return nil }
            return CodeGutterHit(lines: bar.lines, tag: bar.tag, source: .lineDecoration, displayRow: row.display)
        }
        return nil
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
        let focused = frame.focusedElement == id
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
        let primary = buffer.primarySelection   // one read: each is an observed access
        plan.selection = primary.range
        plan.head = primary.head
        let textViewPx = max(1, plan.widthPx - plan.gutterPx - plan.padPx)

        var state = stored
        // The input method's marked text (`CV-AA`): mapped through edits that landed since, or dropped.
        var marked: (offset: Int, composition: TextComposition)?
        if !state.composition.text.isEmpty {
            var offset = state.compositionOffset
            var alive = true
            if state.compositionVersion != snap.version {
                if let moved = buffer.map(offset, from: state.compositionVersion, bias: .before) {
                    offset = moved
                    state.compositionOffset = moved
                    state.compositionVersion = snap.version
                } else {
                    alive = false
                }
            }
            if alive {
                marked = (min(max(0, offset), snap.utf8Count), state.composition)
                plan.selection = marked!.offset..<marked!.offset   // the selection a commit replaces is not drawn
                plan.head = marked!.offset
            } else {
                state.composition = .none
            }
        }
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

        // A drag held outside the view scrolls by the frame's time (`CV-AD`): the offsets are a pure function of
        // the state input wrote and `frame.timestamp`, so repeating a phase repeats its answer.
        let autoscroll = state.dragging ? state.autoscroll : nil
        if let auto = autoscroll {
            let elapsed = max(0, frame.timestamp - auto.start)
            topPx = auto.baseTopPx + Int((auto.vy * elapsed * scaleD).rounded())
            state.scrollXPx = auto.baseXPx + Int((auto.vx * elapsed * scaleD).rounded())
            state.pendingX = 0
            state.pendingY = 0
        }

        // `select(_:reveal: true)` centres the head's row (`CV-P`).
        let serial = buffer.revealSerial
        if let seen = state.revealSeen, seen != serial {
            let head = snap.point(at: min(primary.head, snap.utf8Count)).row
            topPx = map.displayRow(ofBufferRow: head) * pitchPx - (plan.heightPx - pitchPx) / 2
        }
        state.revealSeen = serial
        // A key or an edit asked for the caret to be in view (`CV-X`): the least scroll that shows its row.
        let revealsCaret = state.revealsCaret
        let headRow = snap.point(at: min(primary.head, snap.utf8Count)).row
        if revealsCaret {
            state.revealsCaret = false
            let rowTop = map.displayRow(ofBufferRow: headRow) * pitchPx
            if rowTop < topPx {
                topPx = rowTop
            } else if rowTop + pitchPx > topPx + plan.heightPx {
                topPx = rowTop + pitchPx - plan.heightPx
            }
        }
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

        // One buffer row's layout from the text now, through the cache: the rows below, the caret's reveal and
        // (kept on the plan) a key's vertical motion all go through it (`CV-X`).
        let advancePx = max(1.0, metrics.space * scaleD)
        let view = self
        func layoutOfRow(_ row: Int, _ snapshot: CodeSnapshot, _ scrollXPx: Int) -> CodeLineLayout {
            view.decorations.sync()
            let range = snapshot.lineRange(row)
            let styling = view.decorations.stylingOfLine(range)
            return view.lineLayout(bytes: snapshot.utf8(in: range), knownHash: nil, parts: styling.foreground, digest: styling.digest,
                                   font: font, system: system, scale: scale, cache: cache, spaceAdvance: metrics.space,
                                   scrollXPx: scrollXPx, textViewPx: textViewPx, advancePx: advancePx)
        }

        // Horizontal extent: estimated from the longest line, corrected upward by what was laid out.
        var revealX: Int?
        if revealsCaret {
            let layout = layoutOfRow(headRow, snap, state.scrollXPx)
            let local = min(primary.head, snap.utf8Count) - snap.lineRange(headRow).lowerBound
            let points = layout.x(ofByte: local) ?? (local < layout.windowStart ? layout.caretX.first : layout.caretX.last) ?? 0
            revealX = Int((points * scaleD).rounded())
            state.measuredWidthPx = max(state.measuredWidthPx, revealX! + 1)
        }
        let estimate = Int((Double(snap.longestLineScalars) * metrics.space * scaleD).rounded(.up))
        plan.maxScrollXPx = max(0, max(estimate, state.measuredWidthPx) + plan.padPx - textViewPx)
        if let x = revealX {
            let margin = Int((3 * advancePx).rounded())
            if x < state.scrollXPx + margin {
                state.scrollXPx = max(0, x - margin)
            } else if x > state.scrollXPx + textViewPx - margin {
                state.scrollXPx = x - textViewPx + margin
            }
        }
        state.scrollXPx = min(max(0, state.scrollXPx), plan.maxScrollXPx)
        plan.scrollXPx = state.scrollXPx
        if let auto = autoscroll {   // the display link keeps running while the view can still move; at a limit it rests
            let movingY = (auto.vy < 0 && topPx > 0) || (auto.vy > 0 && topPx < plan.maxTopPx)
            let movingX = (auto.vx < 0 && state.scrollXPx > 0) || (auto.vx > 0 && state.scrollXPx < plan.maxScrollXPx)
            if movingY || movingX { frame.noteActiveAnimation() }
        }
        let settledScrollX = state.scrollXPx
        plan.layoutRow = { row, snapshot in layoutOfRow(row, snapshot, settledScrollX) }
        let decorationsForHits = decorations
        plan.gutterBarOf = { row in decorationsForHits.gutterBar(overRow: row) }

        // The rows: the visible ones and one of overscan each side.
        let remainder = topPx % pitchPx
        let visible = (plan.heightPx + remainder + pitchPx - 1) / pitchPx
        let lower = max(0, firstRow - 1), upper = min(displayRows, firstRow + visible + 1)
        var widest = 0
        let decorated = showsNumbers
        plan.rows.reserveCapacity(max(0, upper - lower))
        // The buffer rows the window shows, found with one seek and a forward scan (`CV-AH`).
        var windowFirst = Int.max, windowLast = -1
        if lower < upper {
            for edge in [lower, upper - 1] {
                switch map.row(atDisplay: edge) {
                case .buffer(let row): windowFirst = min(windowFirst, row); windowLast = max(windowLast, row)
                case .virtual(_, _, let gap): windowFirst = min(windowFirst, gap); windowLast = max(windowLast, gap)
                }
            }
        }
        let windowRanges = windowLast >= windowFirst ? snap.lineRanges(rows: windowFirst..<(windowLast + 1)) : []
        func rangeOf(_ row: Int) -> Range<Int> {
            let at = row - windowFirst
            return at >= 0 && at < windowRanges.count ? windowRanges[at] : snap.lineRange(row)
        }
        var display = lower
        while display < upper {
            let top = plan.originY + (display - firstRow) * pitchPx - remainder
            switch map.row(atDisplay: display) {
            case .buffer(let row):
                let range = rangeOf(row)
                var styling = decorations.stylingOfLine(range)
                var bytes = snap.utf8(in: range)
                var rowMarked: CodeViewPlan.Row.Marked?
                // Only the composing row is laid out with the marked text in it: one cache miss (`CV-AA`).
                if let marked, marked.offset >= range.lowerBound, marked.offset <= range.upperBound, bytes.count <= Self.longLineBytes {
                    let at = marked.offset - range.lowerBound
                    let inserted = Array(marked.composition.text.utf8)
                    bytes.insert(contentsOf: inserted, at: at)
                    styling.foreground = Self.splittingParts(styling.foreground, at: at, inserting: inserted.count)
                    styling.digest = CodeDecorations.digest(of: styling.foreground)
                    let characters = marked.composition.text
                    let low = marked.composition.selection.lowerBound, high = marked.composition.selection.upperBound
                    let before = characters.prefix(low).utf8.count
                    rowMarked = .init(at: at, length: inserted.count, caretBytes: before,
                                      selected: before..<(before + characters.dropFirst(low).prefix(high - low).utf8.count))
                }
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
                                       label: label, labelWidthPx: labelWidth, labelColor: nil, virtualText: nil,
                                       tag: payload?.tag, anchorLine: row, marked: rowMarked))
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
                let start = gap < bufferRows ? rangeOf(gap).lowerBound : snap.utf8Count
                plan.rows.append(.init(display: display, buffer: gap, isVirtual: true, top: top, range: start..<start, textStart: 0,
                                       layout: layout, styling: line.styling, tint: group.background, bar: group.gutterBar,
                                       label: label, labelWidthPx: labelWidth, labelColor: line.marker?.color, virtualText: line.text,
                                       tag: group.tag, anchorLine: group.anchoredAfter ? max(0, gap - 1) : gap))
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
        // The selection a held drag has now, from the pointer and the scroll of this frame (`CV-AD`).
        if autoscroll != nil, state.dragging, let auto = autoscroll {
            let topPoint = Double(plan.originY), bottomPoint = Double(plan.originY + plan.heightPx - 1)
            let y = min(max(auto.pointerY * scaleD, topPoint), bottomPoint) / scaleD
            let offset = plan.offset(at: Point(x: Pixels(Float(auto.pointerX)), y: Pixels(Float(y))))
            let live = plan.dragSelection(to: offset, origin: state.dragOriginLower..<state.dragOriginUpper,
                                          granularity: state.dragGranularity)
            plan.liveDragSelection = live
            plan.selection = live.range
            plan.head = live.head
        }
        // The caret's blink restarts when it moves, an edit lands, the marked text changes or the view gains focus (`CV-AC`).
        if caretBlink == .on {
            let moved = state.blinkSelection != plan.selection || state.blinkHead != plan.head || state.blinkVersion != snap.version
                || state.blinkFocused != focused || state.blinkComposition != state.composition.text
            if moved {
                state.blinkSelection = plan.selection
                state.blinkHead = plan.head
                state.blinkVersion = snap.version
                state.blinkFocused = focused
                state.blinkComposition = state.composition.text
                state.blinkEpoch = frame.timestamp
            }
        }
        return (plan, state)
    }

    /// `parts` (a line's foreground partition) with an unstyled stretch of `length` bytes inserted at byte `at`.
    static func splittingParts(_ parts: [(bytes: Int, style: CodeStyleID?)], at: Int,
                               inserting length: Int) -> [(bytes: Int, style: CodeStyleID?)] {
        var out: [(bytes: Int, style: CodeStyleID?)] = []
        out.reserveCapacity(parts.count + 2)
        var position = 0
        var done = false
        for part in parts {
            if !done && at == position {
                out.append((length, nil))
                done = true
            }
            if !done && at < position + part.bytes {
                out.append((at - position, part.style))
                out.append((length, nil))
                out.append((position + part.bytes - at, part.style))
                done = true
            } else {
                out.append(part)
            }
            position += part.bytes
        }
        if !done { out.append((length, nil)) }
        return out
    }

    /// One line's layout, from the cache or shaped (a long line only in its column window). `knownHash` is the
    /// hash of `bytes` when the caller has it (a virtual line's).
    @MainActor
    func lineLayout(bytes: [UInt8], knownHash: UInt64?, parts partsIn: [(bytes: Int, style: CodeStyleID?)], digest digestIn: UInt64,
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

    /// Whether the blink draws the caret at this frame's time (`CV-AC`): a pure function of `frame.timestamp` and the
    /// epoch input and prepaint stored, so no state is written here. It also asks the timeline store for a frame at
    /// the next toggle, and keeps retained paint from replaying a caret frozen in one phase.
    @MainActor
    func caretIsShown(_ id: GlobalElementID, pass: inout PaintPass) -> Bool {
        guard caretBlink == .on else { return true }
        let now = pass.frame.timestamp
        let epoch = pass.readState(id, initial: CodeViewState()).blinkEpoch
        let elapsed = now - epoch
        guard elapsed >= 0 else { return true }
        let halves = (elapsed / CodeCaretBlink.halfPeriod).rounded(.down)
        let visible = Int(halves) % 2 == 0
        pass.frame.animationStore.timeline.noteDeadline(atTimestamp: epoch + (halves + 1) * CodeCaretBlink.halfPeriod, owner: id,
                                                              stateTable: pass.frame.stateTable)
        pass.frame.taintRetention("codeCaretBlink")
        return visible
    }

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
            // 2. The current line: the caret's row, while nothing is selected (`CV-AE`).
            if let currentLine = theme.currentLine, plan.selection.isEmpty {
                var r = from
                while r < to {
                    let row = plan.rows[r]
                    if !row.isVirtual && plan.head >= row.range.lowerBound && plan.head <= row.range.upperBound {
                        pass.fill(rect(plan.originX, row.top, textRight, row.top + plan.pitchPx), color: pass.resolve(currentLine))
                        break
                    }
                    r += 1
                }
            }
            let findVisitedBefore = decorations.findMatchesVisited
            defer { frame.codeWork.findMatchesVisited += decorations.findMatchesVisited - findVisitedBefore }
            // The text region: backgrounds of runs, the selection and the glyphs.
            pass.clipped(to: rect(textLeft, viewTop, textRight, viewBottom), offsetBy: zero) {
                let tokens = pass.resolve(theme.foreground)
                let selectionColor = pass.resolve(theme.selection)
                let findColor = pass.resolve(theme.findMatch), currentFindColor = pass.resolve(theme.currentFindMatch)
                let currentMatch = decorations.currentMatch
                var colors: [Hsla] = []
                var rowIndex = from
                while rowIndex < to {
                    let row = plan.rows[rowIndex]
                    rowIndex += 1
                    func x(_ byte: Int) -> Int {
                        let local = row.layoutByte(byte)
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
                    // 3. Find matches: only this row's, found by a binary search of the sorted matches (`CV-AE`).
                    if !row.isVirtual {
                        let span = decorations.findSpan(in: row.range)
                        var m = span.lowerBound
                        while m < span.upperBound {
                            let match = decorations.match(at: m)
                            let lo = max(match.lowerBound, row.range.lowerBound), hi = min(match.upperBound, row.range.upperBound)
                            if lo < hi {
                                pass.fill(rect(x(lo), row.top, x(hi), row.top + plan.pitchPx),
                                          color: m == currentMatch ? currentFindColor : findColor)
                            }
                            m += 1
                        }
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
                    // 6. The input method's marked text: underlined, the selected clause doubly.
                    if let marked = row.marked {
                        func xl(_ local: Int) -> Int {
                            let points = row.layout.x(ofByte: local)
                                ?? (local < row.layout.windowStart ? row.layout.caretX.first : row.layout.caretX.last) ?? 0
                            return plan.textOriginX + Int((points * scaleD).rounded())
                        }
                        let thickness = max(1, Int(scaleD.rounded()))
                        let bottom = row.top + plan.pitchPx
                        pass.fill(rect(xl(marked.at), bottom - thickness, xl(marked.at + marked.length), bottom), color: tokens)
                        if !marked.selected.isEmpty {
                            pass.fill(rect(xl(marked.at + marked.selected.lowerBound), bottom - 2 * thickness,
                                           xl(marked.at + marked.selected.upperBound), bottom), color: tokens)
                        }
                    }
                }
                // 7. The caret: a bar a point wide at the head, while the view has focus and nothing is selected.
                if plan.selection.isEmpty, pass.isFocused(id), let caret = plan.caretPosition(), caretIsShown(id, pass: &pass) {
                    let width = max(1, Int(scaleD.rounded()))
                    pass.fill(rect(caret.x, caret.top, caret.x + width, caret.top + plan.pitchPx),
                              color: pass.resolve(theme.caret ?? theme.foreground))
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
