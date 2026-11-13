import MetalUICodeBuffer
import Observation

/// A registered style of a `CodeDecorations`' table; zero is the first registered style.
public struct CodeStyleID: Hashable, Sendable {
    /// The table index.
    public let rawValue: UInt16

    /// The style at `rawValue` in the table that issued it.
    public init(rawValue: UInt16) { self.rawValue = rawValue }
}

/// A line drawn under a highlight run: a straight line in one of ``Text/LineStyle/Pattern``'s patterns, or the
/// wavy squiggle an editor shows under a diagnostic (`CV-AM`, `CV-AN`).
///
/// It never changes where glyphs go, so a style that differs only in its underline reshapes no line. Where
/// layers overlap, the highest layer's underline wins per stretch. A run with no characters (a diagnostic at
/// an offset) draws one character wide; at the end of a line it draws one space advance past the last glyph.
public struct CodeUnderline: Hashable, Sendable {
    /// What the line looks like.
    public enum Shape: Hashable, Sendable {
        /// A straight line in `pattern`, at the face's own underline position and thickness; a dashed
        /// pattern's cycle starts at the line's first column, so it does not shimmer as the view scrolls.
        case line(Text.LineStyle.Pattern)
        /// A squiggle about 1.5 points high and 4 points per period at a 12-point face (both scale with the
        /// font size), 1 point thick, its phase anchored at the line's first column.
        case wavy
    }

    /// The line's shape.
    public var shape: Shape
    /// The line's colour; `nil` is the colour of the text the line starts under.
    public var color: Color?

    /// An underline of `shape`, coloured `color` (`nil`: the text's colour).
    public init(_ shape: Shape = .line(.solid), color: Color? = nil) {
        self.shape = shape
        self.color = color
    }

    /// A squiggle coloured `color` (`nil`: the text's colour).
    public static func wavy(_ color: Color? = nil) -> CodeUnderline { CodeUnderline(.wavy, color: color) }

    /// The straight underline `style` names: its pattern and colour.
    public init(_ style: Text.LineStyle) {
        self.init(.line(style.pattern), color: style.color)
    }
}

/// What a highlight run looks like: a text colour, a background, an underline, or any of them. Colour and lines
/// only: v1 has no weight or slope, because a different face would change where glyphs go (`CV-L`).
public struct CodeStyle: Hashable, Sendable {
    /// The glyph colour; `nil` keeps the layer below's, else the theme's.
    public var foreground: Color?
    /// A background painted under the run's text; `nil` paints none.
    public var background: Color?
    /// A line drawn under the run's text; `nil` draws none. Never part of what a cached line layout depends
    /// on (`CV-AM`).
    public var underline: CodeUnderline?

    /// A style of `foreground` text over `background`, underlined by `underline`.
    public init(foreground: Color? = nil, background: Color? = nil, underline: CodeUnderline? = nil) {
        self.foreground = foreground
        self.background = background
        self.underline = underline
    }
}

/// `style` over the UTF-8 byte `range` of the buffer's text.
public struct CodeStyleRun: Sendable {
    /// The bytes the style covers.
    public var range: Range<Int>
    /// The style, from ``CodeDecorations/register(_:)``.
    public var style: CodeStyleID

    /// A run.
    public init(range: Range<Int>, style: CodeStyleID) {
        self.range = range
        self.style = style
    }
}

/// A tint and a gutter bar over buffer rows (a diff hunk, an author, a diagnostic).
public struct CodeLineDecoration: Sendable {
    /// The rows (0-based buffer rows), as of the `asOf` version they are given at.
    public var lines: Range<Int>
    /// The colour of a thin bar in the gutter beside the rows; `nil` draws none.
    public var gutterBar: Color?
    /// A tint across the rows' full width; `nil` draws none.
    public var background: Color?
    /// An app-defined identifier handed back in the ``CodeGutterHit`` of a click or context menu on this
    /// decoration's gutter bar (an edit's id, say); `nil` for none. Decorations with different tags never
    /// merge into one hit range.
    public var tag: UInt64?

    /// A decoration of `lines`.
    public init(lines: Range<Int>, gutterBar: Color? = nil, background: Color? = nil, tag: UInt64? = nil) {
        self.lines = lines
        self.gutterBar = gutterBar
        self.background = background
        self.tag = tag
    }
}

/// An ordered family of highlight runs. A later layer's foreground wins; backgrounds are painted in layer
/// order, so `annotations` (authorship tints, say) sit under the syntax text colours (`CV-K`).
public enum CodeHighlightLayer: Int, Comparable, CaseIterable, Sendable {
    /// Per-range background tints the app computes (authorship, blame), drawn under the other layers.
    case annotations
    /// The language's syntax colours; the layer the provider fills.
    case syntax
    /// Semantic tokens from a language server.
    case semantic
    /// Diagnostics.
    case diagnostics

    /// Layers compare by drawing order.
    public static func < (a: CodeHighlightLayer, b: CodeHighlightLayer) -> Bool { a.rawValue < b.rawValue }
}

/// The colours a `CodeView` draws with when a style names none.
public struct CodeTheme: Equatable, Sendable {
    /// The text colour of a run no layer colours.
    public var foreground: Color
    /// The view's fill.
    public var background: Color
    /// The selection rectangles.
    public var selection: Color
    /// The caret; `nil` draws it in ``foreground``.
    public var caret: Color?
    /// The line numbers.
    public var gutterForeground: Color
    /// The gutter's fill; `nil` shows the view's.
    public var gutterBackground: Color?
    /// The background of every find match (``CodeDecorations/findMatches``), under the selection.
    public var findMatch: Color
    /// The background of the current find match (``CodeDecorations/currentMatch``); distinct from ``findMatch``.
    public var currentFindMatch: Color
    /// A tint across the row of the caret while nothing is selected; `nil` (the default) draws none.
    public var currentLine: Color?

    /// A theme; the defaults follow the window's theme.
    public init(foreground: Color = .textPrimary,
                background: Color = Color(.surface),
                selection: Color = Color.accentColor.opacity(0.3),
                gutterForeground: Color = Color.textPrimary.opacity(0.4),
                gutterBackground: Color? = nil,
                caret: Color? = nil,
                findMatch: Color = Color.yellow.opacity(0.35),
                currentFindMatch: Color = Color.orange.opacity(0.65),
                currentLine: Color? = nil) {
        self.findMatch = findMatch
        self.currentFindMatch = currentFindMatch
        self.currentLine = currentLine
        self.caret = caret
        self.foreground = foreground
        self.background = background
        self.selection = selection
        self.gutterForeground = gutterForeground
        self.gutterBackground = gutterBackground
    }
}

/// Answers for rows a `CodeView` showed or is about to show whose highlights are unknown or stale.
///
/// MetalUI calls it after a frame, outside every phase, at most once per frame and not again for the
/// same rows until the buffer or the decorations change. Answer now or later with
/// ``CodeDecorations/setHighlights(_:in:layer:asOf:)``; until then the rows draw their old, shifted runs.
@MainActor
public protocol CodeHighlightProvider: AnyObject {
    /// `rows` (buffer rows) need highlights in ``CodeHighlightLayer/syntax``. `snapshot` is the text now.
    ///
    /// Answer with a range covering the rows: either `lineRange(rows.lowerBound).lowerBound ..< lineRange(rows.upperBound - 1).upperBound`
    /// (newline of the last row left out) or one through its newline is fine, and a blank last row counts as
    /// answered by the first. See ``CodeDecorations/setHighlights(_:in:layer:asOf:)``.
    func decorations(_ decorations: CodeDecorations, needHighlightsForRows rows: Range<Int>, in snapshot: CodeSnapshot)
}

/// What a highlight layer holds for a stretch of bytes.
struct HighlightPayload: Equatable {
    enum State: UInt8 { case unknown, stale, valid }
    var style: CodeStyleID?
    var state: State
    static let unknown = HighlightPayload(style: nil, state: .unknown)
}

/// What the line-decoration tree holds for a stretch of rows.
package struct LineDecorationPayload: Equatable {
    package var gutterBar: Color?
    package var background: Color?
    /// The app's tag (`CodeLineDecoration.tag`); part of the payload so differently tagged neighbours stay apart.
    package var tag: UInt64?
    var isEmpty: Bool { gutterBar == nil && background == nil }
}

/// One edit's effect on rows, kept so decorations given `asOf` an older version can be shifted forward.
private struct RowDelta {
    let version: UInt64
    let afterRow: Int
    let removed: Int
    let inserted: Int
}

/// The highlights and line decorations of a ``CodeBuffer`` (`CV-K`).
///
/// It follows the buffer's edits itself: every read first drains an edit cursor and shifts its runs and
/// decorations, in O(log n) per edit, so typing never flashes unstyled text. A run given for an older
/// version (`asOf`) is mapped forward through the edits since. Observable: assigning ``theme``, registering
/// a style and every `set…`/`invalidate…` call redraws the views showing it.
@MainActor @Observable
public final class CodeDecorations {
    /// The buffer these decorations belong to.
    @ObservationIgnored public let buffer: CodeBuffer
    /// The colours used where a style names none.
    public var theme: CodeTheme
    /// Asked for rows whose highlights are unknown or stale. Not retained.
    @ObservationIgnored public weak var highlightProvider: (any CodeHighlightProvider)?
    /// Bumped by every change the views must redraw for; the one observed stamp.
    private(set) var revision: UInt64 = 0

    @ObservationIgnored private var styles: [CodeStyle] = []
    @ObservationIgnored private var styleIDs: [CodeStyle: CodeStyleID] = [:]
    @ObservationIgnored private var layers: [RunTree<HighlightPayload>]
    /// Whether a layer has ever been given a styled run since its last reset: a layer that has not is skipped.
    @ObservationIgnored private var layerHasStyles: [Bool]
    @ObservationIgnored private var anyLayerHasStyles = false
    /// Whether any layer has ever been given a run whose style underlines: until then no line asks for underlines.
    @ObservationIgnored private var anyLayerHasUnderlines = false
    @ObservationIgnored private var lines: RunTree<LineDecorationPayload>
    /// The display rows: buffer rows and the read-only virtual lines between them (`CV-S`).
    @ObservationIgnored let rowMap: CodeRowMap
    @ObservationIgnored private var cursor: CodeEditCursor
    @ObservationIgnored private var deltas: [RowDelta] = []
    @ObservationIgnored private var deltaBase: UInt64
    @ObservationIgnored private var lastRequest: (rows: Range<Int>, version: UInt64, revision: UInt64)?
    @ObservationIgnored package var lineCache = CodeLineCache()
    /// Whether any run given to a layer underlines: until then no row asks for underlines or their metrics (`CV-AM`).
    package var hasUnderlines: Bool { anyLayerHasUnderlines }
    /// The bytes of text the line cache has shaped since creation (test observability, `CV-M`).
    package var shapedBytes: Int { lineCache.shapedBytesTotal }
    /// How many highlight runs ``stylingOfLine(_:)`` visited since reset (a counter, `CV-N`).
    @ObservationIgnored package var runsVisited = 0
    /// How many times a line's styling was computed rather than answered from the row cache (a counter, `CV-AH`).
    @ObservationIgnored package var stylingComputations = 0
    /// How many times ``rowsNeedingHighlights(in:snapshot:)`` scanned rows rather than answered from its cache (`CV-AH`).
    @ObservationIgnored package var needingHighlightScans = 0
    /// The buffer version the layers reflect: set by ``sync()``.
    @ObservationIgnored private var appliedVersion: UInt64 = 0
    @ObservationIgnored private var rowCacheKey: (version: UInt64, revision: UInt64)?
    @ObservationIgnored private var stylingCache: [Range<Int>: LineStyling] = [:]
    @ObservationIgnored private var needingCache: (rows: Range<Int>, result: Range<Int>?)?
    private static let rowCacheLimit = 512
    /// The find matches: sorted, disjoint, in the coordinates of the buffer's version at the last ``sync()`` (`CV-AE`).
    @ObservationIgnored private var matches: [Range<Int>] = []
    @ObservationIgnored private var currentIndex: Int?
    /// How many matches ``findSpan(in:)`` and the edit mapping looked at (a counter, `CV-AE`).
    @ObservationIgnored package var findMatchesVisited = 0

    /// Decorations of `buffer`, with no highlights.
    public init(buffer: CodeBuffer) {
        self.buffer = buffer
        self.theme = CodeTheme()
        let count = buffer.utf8Count
        // Loops, not `map { }`: a main-actor closure traps its dynamic isolation check when a model is built off the
        // main thread (the demo stack-budget test builds trees on a 1 MB thread).
        var made: [RunTree<HighlightPayload>] = []
        var styled: [Bool] = []
        for _ in 0..<CodeHighlightLayer.allCases.count {
            made.append(RunTree(total: count, payload: .unknown))
            styled.append(false)
        }
        layers = made
        layerHasStyles = styled
        lines = RunTree(total: buffer.lineCount, payload: LineDecorationPayload())
        rowMap = CodeRowMap(rowCount: buffer.lineCount)
        cursor = buffer.makeEditCursor()
        deltaBase = buffer.version
    }

    // MARK: Styles

    /// The id of `style`, registering it on first use. Equal styles share an id.
    public func register(_ style: CodeStyle) -> CodeStyleID {
        if let id = styleIDs[style] { return id }
        precondition(styles.count < Int(UInt16.max), "CodeDecorations: too many styles")
        let id = CodeStyleID(rawValue: UInt16(styles.count))
        styles.append(style)
        styleIDs[style] = id
        revision &+= 1
        return id
    }

    /// The style `id` names; an id this table did not issue reads as the empty style.
    public func style(_ id: CodeStyleID) -> CodeStyle {
        Int(id.rawValue) < styles.count ? styles[Int(id.rawValue)] : CodeStyle()
    }

    // MARK: Following the buffer

    /// Brings the runs and decorations up to the buffer's version. Called before every read; it writes
    /// only unobserved storage, so a phase may call it.
    package func sync() {
        switch cursor.drain() {
        case .edits(let edits):
            for edit in edits { apply(edit) }
        case .resync(let snapshot):
            for layer in layers { layer.reset(total: snapshot.utf8Count, payload: .unknown) }
            layerHasStyles = layerHasStyles.map { _ in false }
            anyLayerHasStyles = false
            anyLayerHasUnderlines = false
            lines.reset(total: snapshot.lineCount, payload: LineDecorationPayload())
            rowMap.reset(rowCount: snapshot.lineCount)
            matches.removeAll()   // the log no longer reaches back: the matches' coordinates are unknown (`CV-AE`)
            currentIndex = nil
            deltas.removeAll()
            deltaBase = snapshot.version
        }
        appliedVersion = buffer.version
    }

    private func apply(_ edit: CodeEdit) {
        let removed = edit.range.count, added = edit.newText.utf8.count
        mapFindMatches(through: edit, removed: removed, added: added)
        for layer in layers {
            layer.splice(at: edit.range.lowerBound, removing: removed, inserting: added, empty: .unknown)
            // The run an edit lands in is stale; it keeps its colour until the provider answers.
            let grown = edit.range.lowerBound..<(edit.range.lowerBound + added)
            if added > 0 {
                for (sub, payload) in layer.runs(in: grown) where payload.state == .valid {
                    layer.set(sub, to: HighlightPayload(style: payload.style, state: .stale))
                }
            } else if edit.range.lowerBound < layer.total {
                let at = edit.range.lowerBound..<(edit.range.lowerBound + 1)
                for (sub, payload) in layer.runs(in: at) where payload.state == .valid {
                    layer.set(sub, to: HighlightPayload(style: payload.style, state: .stale))
                }
            }
        }
        let startRow = edit.startPoint.row
        let removedRows = edit.oldEndPoint.row - startRow
        let insertedRows = edit.newEndPoint.row - startRow
        if removedRows > 0 || insertedRows > 0 {
            lines.splice(at: min(startRow + 1, lines.total), removing: min(removedRows, max(0, lines.total - startRow - 1)),
                         inserting: insertedRows, empty: LineDecorationPayload())
            rowMap.splice(at: min(startRow + 1, rowMap.rowCount),
                          removing: min(removedRows, max(0, rowMap.rowCount - startRow - 1)), inserting: insertedRows)
            deltas.append(RowDelta(version: edit.version, afterRow: startRow + 1, removed: removedRows, inserted: insertedRows))
            if deltas.count > 4096 {
                let drop = deltas.count - 4096
                deltaBase = deltas[drop - 1].version
                deltas.removeFirst(drop)
            }
        }
    }

    // MARK: Find matches

    /// The ranges the app's find found, as UTF-8 offsets into the text **now**, left to right (`CV-AE`). The view
    /// paints them under the selection in ``CodeTheme/findMatch`` and follows every edit itself: a match entirely
    /// before an edit stays, one after it shifts by the edit's delta, and one the edit touches is dropped, so a match
    /// is never drawn at coordinates from before an edit. A value is sorted and thinned to disjoint ranges on the
    /// way in (``CodeSnapshot/ranges(of:options:limit:)`` already gives that). The find bar stays the app's: it runs
    /// the search (O(n), when the query changes) and assigns the result here.
    public var findMatches: [Range<Int>] {
        get {
            sync()
            _ = revision
            return matches
        }
        set {
            sync()
            let current = currentIndex.flatMap { $0 < matches.count ? matches[$0] : nil }
            var sorted = newValue
            var ordered = true
            var i = 1
            while i < sorted.count { if sorted[i].lowerBound < sorted[i - 1].lowerBound { ordered = false; break }; i += 1 }
            if !ordered { sorted.sort { $0.lowerBound < $1.lowerBound } }
            var kept: [Range<Int>] = []
            kept.reserveCapacity(sorted.count)
            let total = buffer.utf8Count
            i = 0
            while i < sorted.count {
                let m = sorted[i]
                i += 1
                guard m.lowerBound >= 0, !m.isEmpty, m.upperBound <= total else { continue }
                if let last = kept.last, m.lowerBound < last.upperBound { continue }
                kept.append(m)
            }
            matches = kept
            currentIndex = current.flatMap { index(of: $0) }
            revision &+= 1
        }
    }

    /// The index in ``findMatches`` of the current match, which the view draws in ``CodeTheme/currentFindMatch``
    /// and ⌘G / ⇧⌘G move; `nil` for none. An index outside the matches reads as `nil`. Follows edits with the
    /// matches (it becomes `nil` when an edit drops the match it names).
    public var currentMatch: Int? {
        get {
            sync()
            _ = revision
            return currentIndex
        }
        set {
            sync()
            currentIndex = newValue.flatMap { $0 >= 0 && $0 < matches.count ? $0 : nil }
            revision &+= 1
        }
    }

    /// The index of exactly `range` in the matches, `nil` when it is not one.
    private func index(of range: Range<Int>) -> Int? {
        let at = firstMatch(endingAfter: range.lowerBound)
        return at < matches.count && matches[at] == range ? at : nil
    }

    /// The first match whose end is past `offset` (the sorted, disjoint matches have sorted ends): O(log m).
    private func firstMatch(endingAfter offset: Int) -> Int {
        var lo = 0, hi = matches.count
        while lo < hi {
            let mid = (lo + hi) / 2
            findMatchesVisited += 1
            if matches[mid].upperBound > offset { hi = mid } else { lo = mid + 1 }
        }
        return lo
    }

    /// The matches that touch `bytes` (one row), as indices into the matches: O(log m) to find the first and the
    /// number of matches in the row to walk (`CV-AE`). Paint calls it per shown row, never for all matches.
    package func findSpan(in bytes: Range<Int>) -> Range<Int> {
        guard !matches.isEmpty else { return 0..<0 }
        let first = firstMatch(endingAfter: bytes.lowerBound)
        var end = first
        while end < matches.count && matches[end].lowerBound < bytes.upperBound {
            end += 1
            findMatchesVisited += 1
        }
        return first..<end
    }

    /// The match at `index` (from ``findSpan(in:)``).
    package func match(at index: Int) -> Range<Int> { matches[index] }

    /// Moves the current match to the next (or previous) one from `selection`, wrapping, and returns its range.
    /// From the current match when the selection is exactly it; otherwise from the selection: the first match
    /// starting at or after its end (the last one ending at or before its start). `nil` when there are none.
    package func stepCurrentMatch(forward: Bool, from selection: Range<Int>) -> Range<Int>? {
        sync()
        guard !matches.isEmpty else { return nil }
        let count = matches.count
        var target: Int
        if let current = currentIndex, current < count, matches[current] == selection {
            target = forward ? current + 1 : current - 1
        } else if forward {
            // The first match starting at or after the selection's end (one around a caret is behind it).
            target = firstMatch(endingAfter: selection.upperBound)
            while target < count && matches[target].lowerBound < selection.upperBound { target += 1 }
        } else {
            // The last match ending at or before the selection's start.
            target = firstMatch(endingAfter: selection.lowerBound) - 1
        }
        target = (target % count + count) % count
        currentIndex = target
        revision &+= 1
        return matches[target]
    }

    /// Follows one edit: a match ending at or before it stays, one starting at or after its end shifts by the
    /// delta, the rest (the edit touches them) are dropped, and the current index follows. O(log m) to find the
    /// span and O(matches after it) to shift, once per edit and never per frame.
    private func mapFindMatches(through edit: CodeEdit, removed: Int, added: Int) {
        guard !matches.isEmpty else { return }
        let start = edit.range.lowerBound, end = edit.range.upperBound
        let delta = added - removed
        let first = firstMatch(endingAfter: start)   // the first match not entirely before the edit
        var after = first
        while after < matches.count && matches[after].lowerBound < end { after += 1; findMatchesVisited += 1 }
        // An insertion at a match's start leaves it after the edit (`lowerBound >= end` with an empty range).
        let dropped = after - first
        if dropped > 0 {
            matches.removeSubrange(first..<after)
            if let current = currentIndex {
                currentIndex = current < first ? current : (current < after ? nil : current - dropped)
            }
        }
        if delta != 0 {
            var i = first
            while i < matches.count {
                matches[i] = (matches[i].lowerBound + delta)..<(matches[i].upperBound + delta)
                i += 1
                findMatchesVisited += 1
            }
        }
    }

    // MARK: Highlights

    /// Sets the highlights of `range` in `layer` to `runs`, all given as of `version` of the buffer; they
    /// are mapped forward through the edits since. The range's gaps become "no style, valid". If the edit
    /// log no longer reaches back to `version`, the call is dropped and the rows are asked for again.
    ///
    /// A row is answered when its content bytes (``CodeSnapshot/lineRange(_:)``, newline excluded) lie in
    /// `range`. A blank row has no content, so it is answered by a `range` that reaches through its newline, or
    /// ends at its start when it is the last row of the request in flight (the bounds
    /// `lineRange(first).lowerBound ..< lineRange(last - 1).upperBound`, an empty range at a blank row
    /// included). A `range` ending earlier leaves the later rows to be asked for again. A call that would change
    /// nothing (an empty range, or no runs over bytes already "no style, valid") neither redraws nor re-asks.
    public func setHighlights(_ runs: [CodeStyleRun], in range: Range<Int>, layer: CodeHighlightLayer = .syntax,
                              asOf version: UInt64) {
        sync()
        let tree = layers[layer.rawValue]
        guard let lower = buffer.map(range.lowerBound, from: version, bias: .after),
              let upper = buffer.map(range.upperBound, from: version, bias: .before) else { return }
        var mapped = lower..<max(lower, min(upper, tree.total))
        if mapped.isEmpty && !range.isEmpty { return }
        // An answer that ends where the last requested row's content ends covers that row, even when the row is
        // blank and its only byte is the newline `lineRange` leaves out (`CV-AG`).
        if let request = lastRequest, request.version == buffer.version, request.rows.upperBound > 0 {
            let snapshot = buffer.snapshot()
            let row = request.rows.upperBound - 1
            if row < snapshot.lineCount {
                let content = snapshot.lineRange(row)
                if content.isEmpty, mapped.lowerBound <= content.lowerBound, mapped.upperBound == content.upperBound,
                   content.upperBound < tree.total {
                    mapped = mapped.lowerBound..<(content.upperBound + 1)
                }
            }
        }
        // Nothing to store, or the stored bytes already read "no style, valid" and no run restyles them: no
        // change, so no redraw and no new ask (`CV-AG`).
        if mapped.isEmpty { return }
        if runs.isEmpty, tree.runs(in: mapped).allSatisfy({ $0.payload == HighlightPayload(style: nil, state: .valid) }) { return }
        tree.set(mapped, to: HighlightPayload(style: nil, state: .valid))
        if !runs.isEmpty { layerHasStyles[layer.rawValue] = true; anyLayerHasStyles = true }
        var snapshot: CodeSnapshot?
        for run in runs {
            guard let a = buffer.map(run.range.lowerBound, from: version, bias: .after),
                  let b = buffer.map(run.range.upperBound, from: version, bias: .before) else { continue }
            let underlines = style(run.style).underline != nil
            if underlines { anyLayerHasUnderlines = true }
            let clipped = max(a, mapped.lowerBound)..<min(max(a, b), mapped.upperBound)
            if !clipped.isEmpty {
                tree.set(clipped, to: HighlightPayload(style: run.style, state: .valid))
            } else if underlines, run.range.isEmpty {
                // A run with no characters would vanish from the tree: an underlining one is given the
                // character at its offset (the line break's first byte at a line's end), or the last
                // character at the end of the text (`CV-AM`).
                let text = snapshot ?? buffer.snapshot()
                snapshot = text
                if let width = Self.minimumUnderline(at: a, in: text, total: tree.total) {
                    tree.set(width, to: HighlightPayload(style: run.style, state: .valid))
                }
            }
        }
        revision &+= 1
    }

    /// The bytes an empty underlined run at `offset` occupies: the character there (a line break counts as one
    /// byte, so the run sits at the line's end), else the last character of the text; `nil` for an empty text.
    private static func minimumUnderline(at offset: Int, in text: CodeSnapshot, total: Int) -> Range<Int>? {
        guard total > 0 else { return nil }
        if offset < total {
            let lead = text.byte(at: offset)
            let length = lead == 0x0A || lead == 0x0D || lead < 0x80 ? 1 : lead < 0xE0 ? 2 : lead < 0xF0 ? 3 : 4
            return offset..<min(total, offset + length)
        }
        var start = total - 1
        while start > 0, text.byte(at: start) & 0xC0 == 0x80 { start -= 1 }
        return start..<total
    }

    /// Marks `range` of `layer` stale: the rows are asked from the provider again, drawing their old colours
    /// meanwhile.
    public func invalidateHighlights(in range: Range<Int>, layer: CodeHighlightLayer = .syntax) {
        sync()
        let tree = layers[layer.rawValue]
        let clipped = max(0, range.lowerBound)..<min(tree.total, range.upperBound)
        for (sub, payload) in tree.runs(in: clipped) {
            tree.set(sub, to: HighlightPayload(style: payload.style, state: .stale))
        }
        lastRequest = nil
        revision &+= 1
    }

    // MARK: Line decorations

    /// Replaces every line decoration with `decorations`, whose rows are as of `version`; they are shifted
    /// forward through the newlines added or removed since. Dropped if the edit log no longer reaches back.
    public func setLineDecorations(_ decorations: [CodeLineDecoration], asOf version: UInt64) {
        sync()
        guard version >= deltaBase || version == buffer.version else { return }
        // Build the tree at the rows of `version`, then replay what changed since.
        let sizeThen = lines.total - deltas.filter { $0.version > version }.reduce(0) { $0 + $1.inserted - $1.removed }
        let tree = RunTree(total: max(0, sizeThen), payload: LineDecorationPayload())
        for d in decorations where !d.lines.isEmpty {
            let r = max(0, d.lines.lowerBound)..<min(tree.total, d.lines.upperBound)
            if !r.isEmpty { tree.set(r, to: LineDecorationPayload(gutterBar: d.gutterBar, background: d.background, tag: d.tag)) }
        }
        for delta in deltas where delta.version > version {
            let at = min(delta.afterRow, tree.total)
            tree.splice(at: at, removing: min(delta.removed, max(0, tree.total - at)), inserting: delta.inserted,
                        empty: LineDecorationPayload())
        }
        lines = tree
        revision &+= 1
    }

    // MARK: Virtual rows

    /// Replaces every virtual row with `rows`, whose anchors are buffer rows as of `version`; they are shifted
    /// forward through the newlines added or removed since, like line decorations, in O(log n) per edit
    /// (`CV-S`). Dropped if the edit log no longer reaches back. A group anchored inside rows an edit removes
    /// goes with them; give the rows again after such an edit.
    public func setVirtualRows(_ rows: [CodeVirtualRow], asOf version: UInt64) {
        sync()
        guard version >= deltaBase || version == buffer.version else { return }
        let sizeThen = max(0, rowMap.rowCount - deltas.filter { $0.version > version }.reduce(0) { $0 + $1.inserted - $1.removed })
        let ordered = rows.enumerated().sorted { ($0.element.anchor.gap, $0.offset) < ($1.element.anchor.gap, $1.offset) }
        var groups: [(position: Int, group: VirtualGroup)] = []
        groups.reserveCapacity(ordered.count)
        for entry in ordered where !entry.element.lines.isEmpty {
            groups.append((min(entry.element.anchor.gap, sizeThen), resolveVirtualGroup(entry.element)))
        }
        rowMap.build(rowCount: sizeThen, groups: groups)
        for delta in deltas where delta.version > version {
            let at = min(delta.afterRow, rowMap.rowCount)
            rowMap.splice(at: at, removing: min(delta.removed, max(0, rowMap.rowCount - at)), inserting: delta.inserted)
        }
        revision &+= 1
    }

    /// The virtual lines now shown in all (test observability and the demo's readout).
    public var virtualLineCount: Int {
        sync()
        return rowMap.virtualCount
    }

    /// A group's lines with their colours resolved against the style table.
    private func resolveVirtualGroup(_ row: CodeVirtualRow) -> VirtualGroup {
        var lines: [VirtualLine] = []
        lines.reserveCapacity(row.lines.count)
        for (index, raw) in row.lines.enumerated() {
            var bytes = Array(raw.utf8)
            if let cut = bytes.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) { bytes.removeSubrange(cut...) }
            var styling = LineStyling()
            if !bytes.isEmpty {
                let runs = (index < row.styleRuns.count ? row.styleRuns[index] : []).sorted { $0.range.lowerBound < $1.range.lowerBound }
                var position = 0
                func add(_ count: Int, _ id: CodeStyleID?) {
                    if let last = styling.foreground.last, last.style == id {
                        styling.foreground[styling.foreground.count - 1].bytes += count
                    } else {
                        styling.foreground.append((count, id))
                    }
                }
                for run in runs {
                    let lo = max(run.range.lowerBound, position), hi = min(run.range.upperBound, bytes.count)
                    guard lo < hi else { continue }
                    if lo > position { add(lo - position, nil) }
                    let resolved = style(run.style)
                    add(hi - lo, resolved.foreground != nil ? run.style : nil)
                    if let background = resolved.background { styling.backgrounds.append((lo..<hi, background)) }
                    if let underline = resolved.underline {
                        anyLayerHasUnderlines = true
                        if let last = styling.underlines.last, last.underline == underline, last.range.upperBound == lo {
                            styling.underlines[styling.underlines.count - 1].range = last.range.lowerBound..<hi
                        } else {
                            styling.underlines.append((lo..<hi, underline))
                        }
                    }
                    position = hi
                }
                if position < bytes.count { add(bytes.count - position, nil) }
                styling.digest = Self.digest(of: styling.foreground)
            }
            lines.append(VirtualLine(text: String(decoding: bytes, as: UTF8.self), bytes: bytes, hash: codeHash(bytes),
                                     styling: styling, marker: row.gutterMarker))
        }
        return VirtualGroup(lines: lines, gutterBar: row.gutterBar, background: row.background, tag: row.tag, anchoredAfter: row.anchor.isAfter)
    }

    /// The decoration of `row`, or `nil`.
    package func lineDecoration(row: Int) -> LineDecorationPayload? {
        guard let payload = lines.payload(at: row), !payload.isEmpty else { return nil }
        return payload
    }

    /// The gutter bar over `row` and the whole row range it spans, with its tag: the neighbouring runs with the same
    /// bar colour and tag are one bar, however an edit has split them. `nil` when the row has no bar. Walks outward
    /// by doubling windows, so it costs the bar's runs and a logarithm, and is called at a click, never per frame.
    package func gutterBar(overRow row: Int) -> (lines: Range<Int>, tag: UInt64?)? {
        sync()
        guard let payload = lines.payload(at: row), payload.gutterBar != nil else { return nil }
        func same(_ other: LineDecorationPayload) -> Bool { other.gutterBar == payload.gutterBar && other.tag == payload.tag }
        var lower = row, upper = row + 1
        var step = 64
        outer: while lower > 0 {
            let from = max(0, lower - step)
            for run in lines.runs(in: from..<lower).reversed() {
                guard same(run.payload) else { break outer }
                lower = run.range.lowerBound
            }
            step *= 2
        }
        step = 64
        outer: while upper < lines.total {
            let to = min(lines.total, upper + step)
            for run in lines.runs(in: upper..<to) {
                guard same(run.payload) else { break outer }
                upper = run.range.upperBound
            }
            step *= 2
        }
        return (lower..<upper, payload.tag)
    }

    /// The decorated runs in `rows`, clipped, for painting: tints merge across equal neighbours.
    func lineDecorations(in rows: Range<Int>) -> [(range: Range<Int>, payload: LineDecorationPayload)] {
        lines.runs(in: max(0, rows.lowerBound)..<min(lines.total, rows.upperBound)).filter { !$0.payload.isEmpty }
    }

    /// The row count the line-decoration tree currently covers (test observability).
    var lineDecorationRowCount: Int { lines.total }

    // MARK: Styling a line

    /// How a line's text is coloured: the winning foreground per stretch, tiling the line's bytes, and
    /// the backgrounds in layer order.
    package struct LineStyling {
        package var foreground: [(bytes: Int, style: CodeStyleID?)] = []
        package var backgrounds: [(range: Range<Int>, color: Color)] = []
        /// The underlines, sorted and disjoint, in the coordinates of ``backgrounds``; the highest layer's wins per
        /// stretch (`CV-AM`). A range that reaches past the line's end (over its line break) draws one space advance
        /// past the last glyph. Not in ``digest``: an underline never reshapes a line.
        package var underlines: [(range: Range<Int>, underline: CodeUnderline)] = []
        /// A digest of the foreground partition: what a cached layout depends on.
        package var digest: UInt64 = 0xCBF2_9CE4_8422_2325
    }

    /// The styling of the bytes `range` (one line, as byte offsets in the whole text). Answered from the row
    /// cache while the synced version and the revision are the ones it was made at (`CV-AH`).
    package func stylingOfLine(_ range: Range<Int>) -> LineStyling {
        refreshRowCaches()
        if let hit = stylingCache[range] { return hit }
        let made = computeStylingOfLine(range)
        if stylingCache.count >= Self.rowCacheLimit { stylingCache.removeAll(keepingCapacity: true) }
        stylingCache[range] = made
        return made
    }

    /// Drops the row caches when the buffer version the layers are synced to, or the revision, moved.
    private func refreshRowCaches() {
        if rowCacheKey?.version != appliedVersion || rowCacheKey?.revision != revision {
            rowCacheKey = (appliedVersion, revision)
            stylingCache.removeAll(keepingCapacity: true)
            needingCache = nil
        }
    }

    private func computeStylingOfLine(_ range: Range<Int>) -> LineStyling {
        stylingComputations += 1
        var styling = computeForeground(of: range)
        if anyLayerHasUnderlines { styling.underlines = underlinesOfLine(range) }
        return styling
    }

    /// The underlines of the line `range`: per stretch the highest layer's, adjacent equal ones joined, and a
    /// run over the line break that starts at the line's end last (`CV-AM`).
    private func underlinesOfLine(_ range: Range<Int>) -> [(range: Range<Int>, underline: CodeUnderline)] {
        var perLayer: [[(range: Range<Int>, underline: CodeUnderline)]] = []
        var cuts: [Int] = [range.lowerBound, range.upperBound]
        var tail: CodeUnderline?
        let total = layers[0].total
        var layerIndex = 0
        while layerIndex < layers.count {
            var found: [(range: Range<Int>, underline: CodeUnderline)] = []
            if layerHasStyles[layerIndex] {
                for run in layers[layerIndex].runs(in: range) {
                    guard let id = run.payload.style, let underline = style(id).underline else { continue }
                    found.append((run.range, underline))
                    cuts.append(run.range.lowerBound)
                    cuts.append(run.range.upperBound)
                }
                // The line break's first byte: an underlined run that ends there and does not go on into the
                // next line is a run with no characters at the line's end.
                if range.upperBound < total {
                    let after = layers[layerIndex].runs(in: range.upperBound..<min(total, range.upperBound + 2))
                    if let first = after.first, first.range.lowerBound == range.upperBound, first.range.count == 1,
                       let id = first.payload.style, let underline = style(id).underline,
                       after.count == 2 || range.upperBound + 1 >= total {
                        tail = underline
                    }
                }
            }
            perLayer.append(found)
            layerIndex += 1
        }
        cuts.sort()
        var result: [(range: Range<Int>, underline: CodeUnderline)] = []
        var point = 0
        while point + 1 < cuts.count {
            let segment = cuts[point]..<cuts[point + 1]
            point += 1
            if segment.isEmpty { continue }
            var winner: CodeUnderline?
            for runs in perLayer {   // ascending layer order: the last underline wins
                if let run = runs.first(where: { $0.range.contains(segment.lowerBound) }) { winner = run.underline }
            }
            guard let winner else { continue }
            if let last = result.last, last.underline == winner, last.range.upperBound == segment.lowerBound {
                result[result.count - 1].range = last.range.lowerBound..<segment.upperBound
            } else {
                result.append((segment, winner))
            }
        }
        if let tail {
            if let last = result.last, last.underline == tail, last.range.upperBound == range.upperBound {
                result[result.count - 1].range = last.range.lowerBound..<(range.upperBound + 1)
            } else {
                result.append((range.upperBound..<(range.upperBound + 1), tail))
            }
        }
        return result
    }

    private func computeForeground(of range: Range<Int>) -> LineStyling {
        var styling = LineStyling()
        guard !range.isEmpty else { return styling }
        // No layer holds a styled run (the common case until a provider answers): one unstyled part, with
        // no tree walk and no scratch arrays.
        guard anyLayerHasStyles else {
            styling.foreground = [(range.count, nil)]
            styling.digest = Self.digest(ofUnstyled: range.count)
            return styling
        }
        var perLayer: [[(range: Range<Int>, payload: HighlightPayload)]] = []
        var cuts: [Int] = [range.lowerBound, range.upperBound]
        var layerIndex = 0
        while layerIndex < layers.count {
            let runs: [(range: Range<Int>, payload: HighlightPayload)] = layerHasStyles[layerIndex]
                ? layers[layerIndex].runs(in: range).filter { $0.payload.style != nil } : []
            runsVisited += runs.count
            perLayer.append(runs)
            var r = 0
            while r < runs.count {
                cuts.append(runs[r].range.lowerBound)
                cuts.append(runs[r].range.upperBound)
                r += 1
            }
            layerIndex += 1
        }
        cuts.sort()
        var point = 0
        while point + 1 < cuts.count {
            let segment = cuts[point]..<cuts[point + 1]
            point += 1
            if segment.isEmpty { continue }
            var winner: CodeStyleID?
            var l = 0
            while l < perLayer.count {   // ascending layer order: the last foreground wins
                let runs = perLayer[l]
                l += 1
                var k = 0
                while k < runs.count {
                    if runs[k].range.contains(segment.lowerBound) {
                        if let id = runs[k].payload.style, style(id).foreground != nil { winner = id }
                        break
                    }
                    k += 1
                }
            }
            if let last = styling.foreground.last, last.style == winner {
                styling.foreground[styling.foreground.count - 1].bytes += segment.count
            } else {
                styling.foreground.append((segment.count, winner))
            }
        }
        for runs in perLayer {
            for run in runs {
                guard let id = run.payload.style, let color = style(id).background else { continue }
                if let last = styling.backgrounds.last, last.color == color, last.range.upperBound == run.range.lowerBound {
                    styling.backgrounds[styling.backgrounds.count - 1].range = last.range.lowerBound..<run.range.upperBound
                } else {
                    styling.backgrounds.append((run.range, color))
                }
            }
        }
        styling.digest = Self.digest(of: styling.foreground)
        return styling
    }

    /// `digest(of:)` of the single unstyled part `[(bytes, nil)]`, without building the array.
    nonisolated static func digest(ofUnstyled bytes: Int) -> UInt64 {
        var digest: UInt64 = 0xCBF2_9CE4_8422_2325
        digest = (digest ^ UInt64(bytes)) &* 0x0000_0100_0000_01B3
        digest = (digest ^ 0) &* 0x0000_0100_0000_01B3
        return digest
    }

    /// A digest of a foreground partition: what a cached line layout depends on besides its text.
    nonisolated static func digest(of parts: [(bytes: Int, style: CodeStyleID?)]) -> UInt64 {
        var digest: UInt64 = 0xCBF2_9CE4_8422_2325
        var i = 0
        while i < parts.count {
            digest = (digest ^ UInt64(parts[i].bytes)) &* 0x0000_0100_0000_01B3
            digest = (digest ^ UInt64(parts[i].style.map { Int($0.rawValue) + 1 } ?? 0)) &* 0x0000_0100_0000_01B3
            i += 1
        }
        return digest
    }

    /// `parts` restricted to the bytes `window` (offsets from the line's start).
    nonisolated static func slice(_ parts: [(bytes: Int, style: CodeStyleID?)], _ window: Range<Int>) -> [(bytes: Int, style: CodeStyleID?)] {
        var result: [(bytes: Int, style: CodeStyleID?)] = []
        var position = 0
        for part in parts {
            let lo = max(position, window.lowerBound), hi = min(position + part.bytes, window.upperBound)
            if lo < hi { result.append((hi - lo, part.style)) }
            position += part.bytes
        }
        return result.isEmpty ? [(0, nil)] : result
    }

    // MARK: Asking the provider

    /// The buffer rows in `rows` that have a stretch unknown or stale in the syntax layer: the range from
    /// the first to the last, `nil` when every row is known.
    package func rowsNeedingHighlights(in rows: Range<Int>, snapshot: CodeSnapshot) -> Range<Int>? {
        refreshRowCaches()
        if let cached = needingCache, cached.rows == rows { return cached.result }
        needingHighlightScans += 1
        let tree = layers[CodeHighlightLayer.syntax.rawValue]
        var first: Int?, last = 0
        let lo = max(0, rows.lowerBound), hi = min(snapshot.lineCount, rows.upperBound)
        let ranges = snapshot.lineRanges(rows: lo..<max(lo, hi))
        for (offset, bytes) in ranges.enumerated() {
            let probe = bytes.isEmpty ? bytes.lowerBound..<min(bytes.lowerBound + 1, tree.total) : bytes
            let missing = tree.runs(in: probe).contains { $0.payload.state != .valid }
            if missing {
                if first == nil { first = lo + offset }
                last = lo + offset
            }
        }
        let result = first.map { $0..<(last + 1) }
        needingCache = (rows, result)
        return result
    }

    /// Whether the provider should be called for `rows` now: it has not been asked the same since the last
    /// change. Records the ask.
    func shouldRequest(_ rows: Range<Int>) -> Bool {
        guard highlightProvider != nil else { return false }
        let key = (rows: rows, version: buffer.version, revision: revision)
        if let last = lastRequest, last.rows == key.rows, last.version == key.version, last.revision == key.revision {
            return false
        }
        lastRequest = key
        return true
    }
}
