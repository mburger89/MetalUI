import MetalUICodeBuffer
import MetalUICore
import MetalUILayout

// Hidden rows in a `CodeView` (`CV-BM`, G5 layout): a per-view overlay on the shared row map. The row map turns a
// display row into a buffer row or a virtual line; this overlay removes the display rows a fold hides, so the view's
// rows are the **shown** display rows. It holds the outermost folded spans with prefix sums of the hidden *display*
// rows (a span's count is read from the row map at both of its ends, so a virtual line inside a fold is hidden with
// it), cached on the fold state by its fold revision and the row map's revision. Both directions are
// O(log F + log G); with no fold state a view does one nil check and nothing else.

extension CodeViewStats {
    /// How many fold layouts were built (a counted test pins the cache).
    nonisolated(unsafe) package static var foldLayoutBuilds = 0
    /// How many `fold-placeholder-<line>` accessibility nodes were recorded (only while a client is present).
    nonisolated(unsafe) package static var foldPlaceholderNodes = 0
}

final class CodeFoldLayout {
    /// The outermost spans (buffer rows).
    let spans: FoldSpans
    /// `hiddenDisplay[i]`: the display rows hidden by spans `0..<i`.
    let hiddenDisplay: [Int]
    /// The shown display row of each span's header.
    let headerShown: [Int]
    private let fold: UInt64, mapRevision: UInt64, mapID: ObjectIdentifier

    private init(spans: FoldSpans, map: CodeRowMap, fold: UInt64) {
        self.spans = spans
        self.fold = fold
        mapRevision = map.revision
        mapID = ObjectIdentifier(map)
        var hidden = [0]
        var shown: [Int] = []
        hidden.reserveCapacity(spans.count + 1)
        shown.reserveCapacity(spans.count)
        for i in 0..<spans.count {
            let header = spans.headers[i]
            let last = min(spans.ends[i], map.rowCount) - 1
            let top = map.displayRow(ofBufferRow: header)
            shown.append(top - hidden[i])
            // The header's display row stays; everything up to the last hidden buffer row's goes.
            hidden.append(hidden[i] + max(0, map.displayRow(ofBufferRow: max(header, last)) - top))
        }
        hiddenDisplay = hidden
        headerShown = shown
    }

    /// The layout of `state`'s folds over `map`, from the cache on the state while neither changed; `nil` when
    /// nothing is folded.
    @MainActor static func of(_ state: CodeFoldState, map: CodeRowMap) -> CodeFoldLayout? {
        let revision = state.foldRevision
        if let cached = state.layoutCache as? CodeFoldLayout, cached.fold == revision, cached.mapRevision == map.revision,
           cached.mapID == ObjectIdentifier(map) {
            return cached.spans.isEmpty ? nil : cached
        }
        CodeViewStats.foldLayoutBuilds += 1
        let built = CodeFoldLayout(spans: state.spans, map: map, fold: revision)
        state.layoutCache = built
        return built.spans.isEmpty ? nil : built
    }

    /// Display rows left after the hidden ones.
    func shownCount(of map: CodeRowMap) -> Int { map.displayRowCount - hiddenDisplay[spans.count] }

    /// The shown display row of buffer row `row`; a hidden row is its header's.
    func shownRow(ofBufferRow row: Int, in map: CodeRowMap) -> Int {
        let line = spans.shownLine(row)
        var lo = 0, hi = spans.count
        while lo < hi { let mid = (lo + hi) / 2; if spans.headers[mid] < line { lo = mid + 1 } else { hi = mid } }
        return map.displayRow(ofBufferRow: line) - hiddenDisplay[lo]
    }

    /// What shown display row `display` shows.
    func row(atShown display: Int, in map: CodeRowMap) -> CodeRowMap.Row {
        var lo = 0, hi = spans.count
        while lo < hi { let mid = (lo + hi) / 2; if headerShown[mid] < display { lo = mid + 1 } else { hi = mid } }
        return map.row(atDisplay: display + hiddenDisplay[lo])
    }
}

/// The display rows a view lays out: the row map's, less a fold layout's hidden ones. The one place `makePlan` asks
/// (`CV-S`, `CV-BM`); with no fold layout each call is the row map's own.
struct CodeRowSpace {
    let map: CodeRowMap
    let fold: CodeFoldLayout?

    init(_ map: CodeRowMap, fold: CodeFoldLayout?) { self.map = map; self.fold = fold }

    var displayRowCount: Int { fold.map { $0.shownCount(of: map) } ?? map.displayRowCount }

    func displayRow(ofBufferRow row: Int) -> Int { fold?.shownRow(ofBufferRow: row, in: map) ?? map.displayRow(ofBufferRow: row) }

    func row(atDisplay display: Int) -> CodeRowMap.Row { fold?.row(atShown: display, in: map) ?? map.row(atDisplay: display) }
}

/// The `⋯` after a folded header's last glyph (`CV-BM`), placed from the text origin so it scrolls with the line.
final class CodeFoldMark {
    /// The folded range a press on the placeholder unfolds (`CodeHit/foldedLines`).
    let lines: Range<Int>
    let glyphs: CodeLineLayout
    /// From the text origin to the placeholder's left edge, device pixels.
    let offsetPx: Int
    /// The padding around the glyph (half each side), one space advance.
    let gapPx: Int
    let glyphWidthPx: Int

    init(lines: Range<Int>, glyphs: CodeLineLayout, offsetPx: Int, gapPx: Int, glyphWidthPx: Int) {
        self.lines = lines; self.glyphs = glyphs; self.offsetPx = offsetPx; self.gapPx = gapPx; self.glyphWidthPx = glyphWidthPx
    }

    /// The whole placeholder's width, padding included.
    var widthPx: Int { glyphWidthPx + gapPx }
}

extension CodeViewPlan {
    /// The placeholder's rectangle on `row`, in the plan's (bounds) space, points.
    func foldPlaceholderBounds(_ row: Row) -> Bounds<Pixels>? {
        guard let mark = row.fold else { return nil }
        return Bounds(origin: Point(x: Pixels(Float(textOriginX + mark.offsetPx) / scale), y: Pixels(Float(row.top) / scale)),
                      size: Size(width: Pixels(Float(mark.widthPx) / scale), height: Pixels(Float(pitchPx) / scale)))
    }

    /// The folded range whose placeholder is under `point` (the plan's space), `nil` elsewhere.
    func foldedLines(at point: Point<Pixels>) -> Range<Int>? {
        guard foldLayout != nil, !rows.isEmpty else { return nil }
        let hit = hit(at: point)
        return hit.foldedLines
    }

    /// One `.button` node per folded header in the viewport, identified `fold-placeholder-<line>`; built only while
    /// an accessibility client is present (`CV-U`, `CV-BM`).
    @MainActor func recordFoldPlaceholders(_ id: GlobalElementID, frame: Frame) {
        var i = shownFrom
        while i < shownTo {
            let row = rows[i]
            i += 1
            guard row.fold != nil, let bounds = foldPlaceholderBounds(row) else { continue }
            var node = AXNode(role: .button, label: "Folded lines \(row.buffer + 2) to \(row.fold!.lines.upperBound)")
            node.declarations.identifier = "fold-placeholder-\(row.buffer)"
            let child = GlobalElementID.child(of: id, at: row.buffer, name: ElementID("fold-placeholder-\(row.buffer)"))
            CodeViewStats.foldPlaceholderNodes += 1
            frame.recordAccessibility(text: nil, declared: node, at: bounds, id: child)
        }
    }
}
