import MetalUICodeBuffer
import Observation

/// A registered style of a `CodeDecorations`' table; zero is the first registered style.
public struct CodeStyleID: Hashable, Sendable {
    /// The table index.
    public let rawValue: UInt16

    /// The style at `rawValue` in the table that issued it.
    public init(rawValue: UInt16) { self.rawValue = rawValue }
}

/// What a highlight run looks like: a text colour, a background, or both. Colour only: v1 has no weight
/// or slope, because a different face would change where glyphs go (`CV-L`).
public struct CodeStyle: Hashable, Sendable {
    /// The glyph colour; `nil` keeps the layer below's, else the theme's.
    public var foreground: Color?
    /// A background painted under the run's text; `nil` paints none.
    public var background: Color?

    /// A style of `foreground` text over `background`.
    public init(foreground: Color? = nil, background: Color? = nil) {
        self.foreground = foreground
        self.background = background
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

    /// A decoration of `lines`.
    public init(lines: Range<Int>, gutterBar: Color? = nil, background: Color? = nil) {
        self.lines = lines
        self.gutterBar = gutterBar
        self.background = background
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

    /// A theme; the defaults follow the window's theme.
    public init(foreground: Color = .textPrimary,
                background: Color = Color(.surface),
                selection: Color = Color.accentColor.opacity(0.3),
                gutterForeground: Color = Color.textPrimary.opacity(0.4),
                gutterBackground: Color? = nil,
                caret: Color? = nil) {
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
    @ObservationIgnored private var lines: RunTree<LineDecorationPayload>
    /// The display rows: buffer rows and the read-only virtual lines between them (`CV-S`).
    @ObservationIgnored let rowMap: CodeRowMap
    @ObservationIgnored private var cursor: CodeEditCursor
    @ObservationIgnored private var deltas: [RowDelta] = []
    @ObservationIgnored private var deltaBase: UInt64
    @ObservationIgnored private var lastRequest: (rows: Range<Int>, version: UInt64, revision: UInt64)?
    @ObservationIgnored package var lineCache = CodeLineCache()
    /// The bytes of text the line cache has shaped since creation (test observability, `CV-M`).
    package var shapedBytes: Int { lineCache.shapedBytesTotal }
    /// How many highlight runs ``stylingOfLine(_:)`` visited since reset (a counter, `CV-N`).
    @ObservationIgnored package var runsVisited = 0

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
            lines.reset(total: snapshot.lineCount, payload: LineDecorationPayload())
            rowMap.reset(rowCount: snapshot.lineCount)
            deltas.removeAll()
            deltaBase = snapshot.version
        }
    }

    private func apply(_ edit: CodeEdit) {
        let removed = edit.range.count, added = edit.newText.utf8.count
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

    // MARK: Highlights

    /// Sets the highlights of `range` in `layer` to `runs`, all given as of `version` of the buffer; they
    /// are mapped forward through the edits since. The range's gaps become "no style, valid". If the edit
    /// log no longer reaches back to `version`, the call is dropped and the rows are asked for again.
    public func setHighlights(_ runs: [CodeStyleRun], in range: Range<Int>, layer: CodeHighlightLayer = .syntax,
                              asOf version: UInt64) {
        sync()
        let tree = layers[layer.rawValue]
        guard let lower = buffer.map(range.lowerBound, from: version, bias: .after),
              let upper = buffer.map(range.upperBound, from: version, bias: .before) else { return }
        let mapped = lower..<max(lower, min(upper, tree.total))
        if mapped.isEmpty && !range.isEmpty { return }
        tree.set(mapped, to: HighlightPayload(style: nil, state: .valid))
        if !runs.isEmpty { layerHasStyles[layer.rawValue] = true; anyLayerHasStyles = true }
        for run in runs {
            guard let a = buffer.map(run.range.lowerBound, from: version, bias: .after),
                  let b = buffer.map(run.range.upperBound, from: version, bias: .before) else { continue }
            let clipped = max(a, mapped.lowerBound)..<min(max(a, b), mapped.upperBound)
            if !clipped.isEmpty { tree.set(clipped, to: HighlightPayload(style: run.style, state: .valid)) }
        }
        revision &+= 1
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
            if !r.isEmpty { tree.set(r, to: LineDecorationPayload(gutterBar: d.gutterBar, background: d.background)) }
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
                    position = hi
                }
                if position < bytes.count { add(bytes.count - position, nil) }
                styling.digest = Self.digest(of: styling.foreground)
            }
            lines.append(VirtualLine(text: String(decoding: bytes, as: UTF8.self), bytes: bytes, hash: codeHash(bytes),
                                     styling: styling, marker: row.gutterMarker))
        }
        return VirtualGroup(lines: lines, gutterBar: row.gutterBar, background: row.background)
    }

    /// The decoration of `row`, or `nil`.
    package func lineDecoration(row: Int) -> LineDecorationPayload? {
        guard let payload = lines.payload(at: row), !payload.isEmpty else { return nil }
        return payload
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
        /// A digest of the foreground partition: what a cached layout depends on.
        package var digest: UInt64 = 0xCBF2_9CE4_8422_2325
    }

    /// The styling of the bytes `range` (one line, as byte offsets in the whole text).
    package func stylingOfLine(_ range: Range<Int>) -> LineStyling {
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
    func rowsNeedingHighlights(in rows: Range<Int>, snapshot: CodeSnapshot) -> Range<Int>? {
        let tree = layers[CodeHighlightLayer.syntax.rawValue]
        var first: Int?, last = 0
        for row in max(0, rows.lowerBound)..<min(snapshot.lineCount, rows.upperBound) {
            let bytes = snapshot.lineRange(row)
            let probe = bytes.isEmpty ? bytes.lowerBound..<min(bytes.lowerBound + 1, tree.total) : bytes
            let missing = tree.runs(in: probe).contains { $0.payload.state != .valid }
            if missing {
                if first == nil { first = row }
                last = row
            }
        }
        return first.map { $0..<(last + 1) }
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
