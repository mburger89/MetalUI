import MetalUICore
import MetalUILayout

// `LazyVGrid` and `LazyHGrid` (item L1, lane 2; rulings `LZ-A`, `LZ-K`, `LZ-L`, `LZ-M`, `LZ-O`, `LZ-W`;
// spec 3.4; probe `docs/probes/swiftui-lazy-containers.swift` arms C1-C17, G1, G2).
//
// **Lines are rows** (columns for a `LazyHGrid`): `unitsPerLine` cells, over lane 1's planner and the SAME
// `RowExtentIndex` (a line's key is its first cell's). The tracks are resolved TWICE: at build time only
// for their COUNT, from the width last frame's prepaint stored (`LazyOrigin.crossExtent`; a fixed or
// flexible item's count is static, an adaptive one's is floor-derived), and at layout from the real bounds
// by `GridTrackSolver`; when the two counts differ prepaint asks for one more frame (`LZ-L`). A grid's
// lines are whole: the window is `plan.window * unitsPerLine` cells, the last line possibly short.

/// A grid layout's one cross-frame fact: how many tracks the last placement resolved, read by prepaint
/// (`LZ-L`). A class so the layout value stays a value; written in `placeSubviews`, read once after.
final class LazyGridProbe: @unchecked Sendable {
    /// The tracks the last placement resolved, `nil` when it did not run.
    var resolvedCount: Int?
}

/// A lazy grid's realised cells as a `ProposalLayout` (`LZ-F`, `LZ-R`): the SAME arithmetic for both
/// axes, over `axis` (the LINE axis: `.vertical` is a `LazyVGrid`, whose lines are rows).
///
/// - **Tracks**: `GridTrackSolver` over the offered cross extent; with none, over the extent the first
///   line's cells ask for (probe LZ4, C12). The grid answers `max(offered, tracks)` across (C5) and its
///   lines down: `anchorOffset` + the realised lines from the anchor down (each as tall as its tallest cell
///   plus `lineSpacing`, a line with no node adding nothing) + `trailingExtent`, less the last gap.
/// - **A cell** is one realised unit: its nodes stacked along the line axis with the platform spacing
///   (divergence 635), in its track by the item's alignment else the grid's, in its line by the same
///   alignment (C9, C10); a cell wider than its track overflows by that alignment.
/// - **Placement** is lane 1's: the anchor line at `anchorOffset`, later lines after it, earlier ones
///   before it, so a re-measured line above the anchor moves only lines above it (`VL-G` item 1).
///
/// **Not `Hashable`, so it taints exactly its ancestors for the layout memo** (`IV-`, `LZ-F`, `LZ-R`).
struct LazyGridLayout: ProposalLayout {
    var axis: ProposalStackAxis
    var specs: [GridTrackSpec]
    /// Each declared item's own alignment (`nil`: the grid's).
    var itemAlignments: [ProposalAlignment?]
    /// The grid's alignment: the tracks' place in the extent, and the default cell alignment.
    var alignment: ProposalAlignment
    var lineSpacing: Double
    /// Cells per line as built.
    var perLine: Int
    /// Nodes each realised cell registered, in order (0, 1 or several).
    var unitNodeCounts: [Int]
    /// The realised lines before the anchor line.
    var anchorLine: Int
    var anchorOffset: Double
    var trailingExtent: Double
    var probe: LazyGridProbe

    private var vertical: Bool { axis == .vertical }
    private var trackFactor: Double { vertical ? alignment.horizontalFactor : alignment.verticalFactor }

    private func across(_ size: SizeD) -> Double { vertical ? size.width : size.height }
    private func along(_ size: SizeD) -> Double { vertical ? size.height : size.width }

    private func proposal(track: Double) -> ProposedSize {
        vertical ? ProposedSize(width: track, height: nil) : ProposedSize(width: nil, height: track)
    }

    /// One realised cell, measured in its track.
    private struct Measured {
        var firstNode: Int
        var sizes: [SizeD]
        var across: Double
        var along: Double
        var track: Int
    }

    private func measured(tracks: [GridTrack], measure: (Int, ProposedSize) -> SizeD) -> [Measured] {
        var cells: [Measured] = []
        cells.reserveCapacity(unitNodeCounts.count)
        var node = 0
        for (unit, count) in unitNodeCounts.enumerated() {
            let track = Swift.min(unit % Swift.max(perLine, 1), tracks.count - 1)
            let offer = proposal(track: tracks[track].size)
            var sizes: [SizeD] = []
            for offset in 0..<count { sizes.append(measure(node + offset, offer)) }
            var width = 0.0, length = 0.0
            for size in sizes {
                width = Swift.max(width, across(size))
                length += along(size)
            }
            if count > 1 { length += Double(count - 1) * ProposalSpacing.platformDefault }
            cells.append(Measured(firstNode: node, sizes: sizes, across: width, along: length, track: track))
            node += count
        }
        return cells
    }

    /// Each realised line's extent (its tallest cell) and whether it holds a node.
    private func lines(of cells: [Measured]) -> [(extent: Double, hasNodes: Bool)] {
        guard perLine > 0 else { return [] }
        var result: [(extent: Double, hasNodes: Bool)] = []
        var start = 0
        while start < cells.count {
            let end = Swift.min(start + perLine, cells.count)
            var extent = 0.0
            var has = false
            for cell in cells[start..<end] where !cell.sizes.isEmpty {
                extent = Swift.max(extent, cell.along)
                has = true
            }
            result.append((extent, has))
            start = end
        }
        return result
    }

    func sizeThatFits(proposal offer: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
        guard !specs.isEmpty, perLine > 0 else { return LayoutMeasurement(size: .zero) }
        let offered = vertical ? offer.width : offer.height
        let available: Double
        if let offered, offered.isFinite {
            available = offered
        } else {
            // The first line's cells, one per declared item (an adaptive item is one track).
            var widths: [Double] = []
            var node = 0
            for (unit, count) in unitNodeCounts.enumerated() where unit < specs.count {
                var width = 0.0
                for offset in 0..<count {
                    width = Swift.max(width, across(subviews[node + offset].sizeThatFits(.unspecified).size))
                }
                widths.append(width)
                node += count
            }
            available = GridTrackSolver.availableForUnspecified(specs, firstLine: widths)
        }
        let resolution = GridTrackSolver.resolve(specs, available: available, alignment: trackFactor)
        guard !resolution.tracks.isEmpty else { return LayoutMeasurement(size: .zero) }
        let cells = measured(tracks: resolution.tracks) { subviews[$0].sizeThatFits($1).size }
        var below = 0.0
        for line in lines(of: cells).dropFirst(Swift.min(anchorLine, lines(of: cells).count)) where line.hasNodes {
            below += line.extent + lineSpacing
        }
        let extent = Swift.max(0, anchorOffset + below + trailingExtent - lineSpacing)
        return LayoutMeasurement(size: vertical ? SizeD(width: resolution.width, height: extent)
                                                : SizeD(width: extent, height: resolution.width))
    }

    func placeSubviews(in bounds: LayoutRect, proposal offer: ProposedSize, subviews: PlacementSubviews) {
        guard !specs.isEmpty, perLine > 0 else { return }
        let crossBounds = vertical ? bounds.width : bounds.height
        let resolution = GridTrackSolver.resolve(specs, available: crossBounds, alignment: trackFactor)
        probe.resolvedCount = resolution.tracks.count
        guard !resolution.tracks.isEmpty else { return }
        let cells = measured(tracks: resolution.tracks) { subviews[$0].sizeThatFits($1).size }
        let measuredLines = lines(of: cells)
        var trackStarts: [Double] = []
        var cursor = resolution.origin
        for track in resolution.tracks {
            trackStarts.append(cursor)
            cursor += track.size + track.gapAfter
        }
        let crossOrigin = vertical ? bounds.x : bounds.y
        let lineOrigin = vertical ? bounds.y : bounds.x

        func place(line: Int, at lineStart: Double) {
            let first = line * perLine
            let last = Swift.min(first + perLine, cells.count)
            let extent = measuredLines[line].extent
            for unit in first..<last {
                let cell = cells[unit]
                guard !cell.sizes.isEmpty else { continue }
                let track = resolution.tracks[cell.track]
                let cellAlignment = itemAlignments[track.item] ?? alignment
                let acrossFactor = vertical ? cellAlignment.horizontalFactor : cellAlignment.verticalFactor
                let alongFactor = vertical ? cellAlignment.verticalFactor : cellAlignment.horizontalFactor
                let cellStart = crossOrigin + trackStarts[cell.track] + (track.size - cell.across) * acrossFactor
                var nodeStart = lineStart + (extent - cell.along) * alongFactor
                for (offset, size) in cell.sizes.enumerated() {
                    let nodeAcross = cellStart + (cell.across - across(size)) * acrossFactor
                    let point = vertical ? Point(x: nodeAcross, y: nodeStart) : Point(x: nodeStart, y: nodeAcross)
                    subviews[cell.firstNode + offset].place(at: point, anchor: .topLeading,
                                                            proposal: self.proposal(track: track.size))
                    nodeStart += along(size) + ProposalSpacing.platformDefault
                }
            }
        }

        let start = Swift.min(anchorLine, measuredLines.count)
        var cursorAlong = lineOrigin + anchorOffset
        for line in start..<measuredLines.count {
            place(line: line, at: cursorAlong)
            if measuredLines[line].hasNodes { cursorAlong += measuredLines[line].extent + lineSpacing }
        }
        cursorAlong = lineOrigin + anchorOffset
        for line in stride(from: start - 1, through: 0, by: -1) {
            if measuredLines[line].hasNodes { cursorAlong -= measuredLines[line].extent + lineSpacing }
            place(line: line, at: cursorAlong)
        }
    }
}

/// What a lazy grid's layout phase hands to prepaint and paint.
struct LazyGridState<Content: ProposalElementGroup> {
    var node: LayoutNodeID
    var table: LazyUnitTable?
    var boxes: [LazyUnitBox] = []
    var eager: Content.GroupLayout?
    var plan: LazyLinePlan?
    var perLine: Int = 1
    var lineSpacing: Double = 0
    var probe: LazyGridProbe
}

/// What prepaint hands to paint.
struct LazyGridPrepaint<Content: ProposalElementGroup> {
    var eager: Content.GroupPrepaint?
}

/// The one implementation behind `LazyVGrid` and `LazyHGrid`.
@MainActor
struct LazyGridEngine<Content: ProposalElementGroup> {
    var content: Content
    var items: [GridItem]
    var spacing: Pixels?
    /// The LINE axis: `.vertical` for a `LazyVGrid`.
    var axis: ProposalStackAxis
    var alignment: ProposalAlignment

    private var scrollAxis: ScrollAxis { axis == .vertical ? .vertical : .horizontal }
    private var specs: [GridTrackSpec] { items.map(\.spec) }
    private var hasAdaptive: Bool { items.contains { if case .adaptive = $0.size { true } else { false } } }

    private func layout(perLine: Int, counts: [Int], anchorLine: Int, anchorOffset: Double, trailing: Double,
                        lineSpacing: Double, probe: LazyGridProbe) -> LazyGridLayout {
        LazyGridLayout(axis: axis, specs: specs, itemAlignments: items.map(\.alignment), alignment: alignment,
                       lineSpacing: lineSpacing, perLine: perLine, unitNodeCounts: counts,
                       anchorLine: anchorLine, anchorOffset: anchorOffset, trailingExtent: trailing, probe: probe)
    }

    /// Cells per line as built (`LZ-L`): static unless an adaptive item packs by the stored width.
    private func builtColumns(storedWidth: Double) -> Int {
        let specs = self.specs
        guard hasAdaptive, storedWidth > 0 else { return specs.count }
        return GridTrackSolver.resolve(specs, available: storedWidth, alignment: 0.5).tracks.count
    }

    mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (ProposalNodeID, LazyGridState<Content>) {
        let lineSpacing = spacing.map { Double($0.value) } ?? ProposalSpacing.platformDefault
        let probe = LazyGridProbe()
        let stored = pass.frame.stateTable.peek(id, as: LazyOrigin.self)
        let perLine = builtColumns(storedWidth: stored?.crossExtent ?? 0)
        guard let sources = lazyFlatten(content) else {
            // `LZ-B`, divergence 636: a member that is not a unit source makes the container eager. Every
            // node is then a cell (SwiftUI's rule: each view is a cell).
            var cursor = 0
            let (children, contentLayout) = pass.frame.withStackAxis(.vertical) {
                content.requestProposalGroupLayout(under: id, at: &cursor, pass: &pass)
            }
            pass.frame.lazyWork.unbounded += 1
            pass.frame.lazyWork.unitsRealized += children.count
            pass.frame.lazyWork.linesRealized += perLine > 0 ? (children.count + perLine - 1) / perLine : 0
            let node = pass.requestNativeLayout(
                layout(perLine: perLine, counts: children.map { _ in 1 }, anchorLine: 0, anchorOffset: 0,
                       trailing: 0, lineSpacing: lineSpacing, probe: probe),
                children: children)
            return (node, LazyGridState(node: node.layoutNodeID, table: nil, eager: contentLayout,
                                        perLine: perLine, lineSpacing: lineSpacing, probe: probe))
        }
        let table = LazyUnitTable(sources)
        let unitCount = perLine > 0 ? table.count : 0
        let lineCount = perLine > 0 ? (unitCount + perLine - 1) / perLine : 0
        let plan = LazyLinePlanner.plan(lineCount: lineCount, key: { table.key($0 * perLine) }, stored: stored,
                                        origin: stored?.offset ?? 0, context: pass.scrollContext, axis: scrollAxis)
        table.begin(parent: id, pass: &pass)
        let cells = (plan.window.lowerBound * perLine)..<Swift.min(plan.window.upperBound * perLine, unitCount)
        var boxes: [LazyUnitBox] = []
        boxes.reserveCapacity(cells.count)
        var seen = Set<AnyHashable>()
        var nodes: [ProposalNodeID] = []
        var counts: [Int] = []
        var realised = 0
        pass.frame.withStackAxis(.vertical) {
            for unit in cells {
                // `LZ-G`: duplicate ids dedupe within the realised window only, first wins; an empty cell
                // keeps its slot so the columns of the line stay aligned.
                guard seen.insert(table.key(unit)).inserted else {
                    boxes.append(LazyUnitBox(unit: unit, key: table.key(unit), nodes: [], prepaint: { _ in }, paint: { _ in }))
                    counts.append(0)
                    continue
                }
                let box = table.realize(unit, parent: id, pass: &pass)
                boxes.append(box)
                nodes.append(contentsOf: box.nodes)
                counts.append(box.nodes.count)
                realised += 1
            }
        }
        if plan.mode == .unbounded { pass.frame.lazyWork.unbounded += 1 }
        pass.frame.lazyWork.unitsRealized += realised
        pass.frame.lazyWork.linesRealized += plan.window.count
        let node = pass.requestNativeLayout(
            layout(perLine: perLine, counts: counts, anchorLine: Swift.max(0, plan.anchorLine - plan.window.lowerBound),
                   anchorOffset: plan.anchorOffset, trailing: plan.trailing, lineSpacing: lineSpacing, probe: probe),
            children: nodes)
        return (node, LazyGridState(node: node.layoutNodeID, table: table, boxes: boxes, eager: nil, plan: plan,
                                    perLine: perLine, lineSpacing: lineSpacing, probe: probe))
    }

    /// Stores the width a grid was laid out at, for the next build's column count (`LZ-L`), when the
    /// planner did not (no scroller on the line axis).
    private func noteWidth(_ id: GlobalElementID, bounds: Bounds<Pixels>, pass: PrepaintPass) {
        guard hasAdaptive else { return }
        let cross = Double(axis == .vertical ? bounds.size.width.value : bounds.size.height.value)
        pass.withState(id, initial: LazyOrigin(), unchanged: LazyOrigin.sameEntry) { $0.crossExtent = cross }
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout LazyGridState<Content>,
                           pass: inout PrepaintPass) -> LazyGridPrepaint<Content> {
        let probe = layout.probe
        defer {
            // `LZ-L`: the count the layout resolved is not the count the build used.
            if let resolved = probe.resolvedCount, resolved != layout.perLine, !specs.isEmpty {
                pass.frame.requestAnotherFrame()
            }
        }
        guard let table = layout.table, let plan = layout.plan else {
            noteWidth(id, bounds: bounds, pass: pass)
            guard var eager = layout.eager else { return LazyGridPrepaint(eager: nil) }
            let prepaint = content.prepaintGroup(layout: &eager, pass: &pass)
            layout.eager = eager
            return LazyGridPrepaint(eager: prepaint)
        }
        let vertical = axis == .vertical
        let perLine = layout.perLine
        let lineSpacing = layout.lineSpacing
        let lineCount = perLine > 0 ? (table.count + perLine - 1) / perLine : 0
        // Each realised line's extent as the index records it: its tallest cell plus the gap, 0 with no node.
        var extents: [Int: Double] = [:]
        for box in layout.boxes where !box.nodes.isEmpty {
            var length = 0.0
            for node in box.nodes {
                let size = pass.bounds(of: node.layoutNodeID).size
                length += Double(vertical ? size.height.value : size.width.value)
            }
            length += Double(box.nodes.count - 1) * ProposalSpacing.platformDefault
            let line = box.unit / perLine
            extents[line] = Swift.max(extents[line] ?? 0, length + lineSpacing)
        }
        let realised: [(line: Int, extent: Double)] = plan.window.map { ($0, extents[$0] ?? 0) }
        let outcome = LazyLinePlanner.prepaint(id, bounds: bounds, axis: scrollAxis, lineCount: lineCount,
                                               made: plan.index, key: { table.key($0 * perLine) }, realised: realised,
                                               builtWindow: plan.window, builtCold: plan.mode == .cold,
                                               anchor: plan.anchor, pass: pass)
        if outcome.index == nil { noteWidth(id, bounds: bounds, pass: pass) }
        if pass.frame.hasUnresolvedScrollRequests {
            let boxes = layout.boxes
            LazyLinePlanner.resolveScrollRequests(
                id, bounds: bounds, axis: scrollAxis, unitCount: table.count, line: { $0 / Swift.max(perLine, 1) },
                rawID: table.rawID, index: outcome.index, adjustment: outcome.adjustment,
                realisedBounds: { unit in
                    guard let box = boxes.first(where: { $0.unit == unit }), let node = box.nodes.first
                    else { return nil }
                    return pass.bounds(of: node.layoutNodeID)
                }, pass: pass)
        }
        for box in layout.boxes { box.prepaint(&pass) }
        return LazyGridPrepaint(eager: nil)
    }

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout LazyGridState<Content>,
                        prepaint: inout LazyGridPrepaint<Content>, pass: inout PaintPass) {
        if layout.table == nil {
            guard var eager = layout.eager, var held = prepaint.eager else { return }
            content.paintGroup(layout: &eager, prepaint: &held, pass: &pass)
            layout.eager = eager
            prepaint.eager = held
            return
        }
        for box in layout.boxes { box.paint(&pass) }
    }
}

/// SwiftUI's `LazyVGrid`: a grid of fixed, flexible or adaptive columns whose rows are realised only as
/// a scroller along its axis brings them near the viewport (item L1).
///
/// ```swift
/// ProposalScrollView {
///     LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 12) {
///         ForEach(photos) { photo in PhotoCell(photo) }
///     }
/// }
/// ```
///
/// **Columns** are `GridItem`s, resolved by the offered width (``GridItem`` has the rules); the grid is as
/// wide as the larger of the proposal and its tracks, and with no proposed width the columns come from the
/// first row's cells. **Rows** are as tall as their tallest cell; `spacing` is the gap between rows
/// (default 8) and each item's `spacing` the gap after its column.
///
/// **What is windowed.** Inside a scroller scrolling vertically, only the rows within the viewport plus two
/// on each side are built, laid out and prepainted each frame (divergence 637); a row's extent is measured
/// when it is realised and an unrealised row counts as the mean of the measured ones, with the row on top
/// kept in place as extents are learned (the `RowExtentIndex` that `LazyVStack` and `List` share). Outside a
/// scroller, in a horizontal one or when the content holds an `if`, `switch` or `for` member (divergence 636)
/// every cell is realised. The column count an adaptive item packs is read from the width of the last frame,
/// so a width change shows one frame at the old count and the next at the new (`LZ-L`).
///
/// **A cell** is one `ForEach` element or one static child: an element that produces several views is ONE cell
/// holding them in a vertical stack (divergence 635; SwiftUI makes each view a cell). Identity, state and
/// accessibility are `LazyVStack`'s. `pinnedViews:` and `Section` are not offered.
public struct LazyVGrid<Content: ProposalElementGroup>: Element {
    var engine: LazyGridEngine<Content>

    /// A grid of `columns` over `content`, SwiftUI's `LazyVGrid(columns:alignment:spacing:pinnedViews:content:)`
    /// without `pinnedViews`.
    ///
    /// - Parameters:
    ///   - columns: One item per column (an adaptive item makes several).
    ///   - alignment: Where the columns sit in the grid's width, and the default alignment of a cell in its
    ///     column (default `.center`).
    ///   - spacing: The gap between rows; `nil` is 8.
    ///   - content: The cells.
    public init(columns: [GridItem], alignment: HorizontalAlignment = .center, spacing: Pixels? = nil,
                @ProposalContentBuilder content: () -> Content) {
        engine = LazyGridEngine(content: content(), items: columns, spacing: spacing, axis: .vertical,
                                alignment: alignment.proposalAlignment)
    }

    /// What the layout phase hands to prepaint and paint.
    public struct Layout {
        var state: LazyGridState<Content>
    }

    public mutating func requestProposalLayout(_ id: GlobalElementID,
                                               pass: inout LayoutPass) -> (ProposalNodeID, Layout) {
        let (node, state) = engine.requestLayout(id, pass: &pass)
        return (node, Layout(state: state))
    }

    /// What prepaint hands to paint.
    public struct Prepaint {
        var state: LazyGridPrepaint<Content>
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                                  pass: inout PrepaintPass) -> Prepaint {
        Prepaint(state: engine.prepaint(id, bounds: bounds, layout: &layout.state, pass: &pass))
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                               prepaint: inout Prepaint, pass: inout PaintPass) {
        engine.paint(id, bounds: bounds, layout: &layout.state, prepaint: &prepaint.state, pass: &pass)
    }
}

extension LazyVGrid: ProposalElement {}

/// SwiftUI's `LazyHGrid`: `LazyVGrid` along the horizontal axis (item L1).
///
/// Its `rows` are the tracks, filled a column at a time; the columns are the lines, windowed against a
/// scroller scrolling horizontally, each as wide as its widest cell. The height is the proposed one (at least
/// the tracks'), else the first column's cells'. See ``LazyVGrid`` for the realisation, identity and
/// cell rules, which are the same.
public struct LazyHGrid<Content: ProposalElementGroup>: Element {
    var engine: LazyGridEngine<Content>

    /// A grid of `rows` over `content`, SwiftUI's `LazyHGrid(rows:alignment:spacing:pinnedViews:content:)`
    /// without `pinnedViews`.
    ///
    /// - Parameters:
    ///   - rows: One item per row (an adaptive item makes several).
    ///   - alignment: Where the rows sit in the grid's height, and the default alignment of a cell in its
    ///     row (default `.center`).
    ///   - spacing: The gap between columns; `nil` is 8.
    ///   - content: The cells.
    public init(rows: [GridItem], alignment: VerticalAlignment = .center, spacing: Pixels? = nil,
                @ProposalContentBuilder content: () -> Content) {
        engine = LazyGridEngine(content: content(), items: rows, spacing: spacing, axis: .horizontal,
                                alignment: alignment.proposalAlignment)
    }

    /// What the layout phase hands to prepaint and paint.
    public struct Layout {
        var state: LazyGridState<Content>
    }

    public mutating func requestProposalLayout(_ id: GlobalElementID,
                                               pass: inout LayoutPass) -> (ProposalNodeID, Layout) {
        let (node, state) = engine.requestLayout(id, pass: &pass)
        return (node, Layout(state: state))
    }

    /// What prepaint hands to paint.
    public struct Prepaint {
        var state: LazyGridPrepaint<Content>
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                                  pass: inout PrepaintPass) -> Prepaint {
        Prepaint(state: engine.prepaint(id, bounds: bounds, layout: &layout.state, pass: &pass))
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                               prepaint: inout Prepaint, pass: inout PaintPass) {
        engine.paint(id, bounds: bounds, layout: &layout.state, prepaint: &prepaint.state, pass: &pass)
    }
}

extension LazyHGrid: ProposalElement {}
