import Foundation
import MetalUICore
import MetalUILayout

// `HSplitView` / `VSplitView` (rulings `HS-A`...; `docs/superpowers/2026-10-30-split-view-decisions.md`).
// Panes in a row or column with a draggable divider between each pair. The pane
// limits are the panes' own `.frame(minWidth:idealWidth:maxWidth:)` answers, read
// by the layout at three proposals (0, nil, infinity); the sizes the user chose
// are one `@State` array written only by the divider's drag handler (`HS-D`).

// MARK: - The autosave seam

/// Where a split view keeps its pane sizes between runs (MetalUI-only, ruling `HS-G`).
///
/// ``HSplitView/splitViewAutosaveName(_:store:)`` names the entry; the store holds
/// the sizes in points, one per pane in declaration order. The default is
/// `UserDefaults.standard` under the key `MetalUI.SplitView.<name>`. A test passes
/// an in-memory conformer.
@MainActor
public protocol SplitViewAutosaveStore: AnyObject {
    /// The sizes stored under `name`, or `nil` when none were saved.
    func paneSizes(forName name: String) -> [Double]?
    /// Stores `sizes` under `name`, replacing any earlier entry.
    func setPaneSizes(_ sizes: [Double], forName name: String)
}

/// `UserDefaults.standard` under `MetalUI.SplitView.<name>` (`HS-G`).
@MainActor
final class UserDefaultsSplitViewStore: SplitViewAutosaveStore {
    static let shared = UserDefaultsSplitViewStore()

    static func key(_ name: String) -> String { "MetalUI.SplitView.\(name)" }

    func paneSizes(forName name: String) -> [Double]? {
        UserDefaults.standard.array(forKey: Self.key(name)) as? [Double]
    }

    func setPaneSizes(_ sizes: [Double], forName name: String) {
        UserDefaults.standard.set(sizes, forKey: Self.key(name))
    }
}

// MARK: - The solver (pure)

/// One pane's answers to the three limit proposals, along the split axis.
struct SplitPaneLimits: Equatable {
    var minimum: Double
    var ideal: Double
    var maximum: Double

    /// Orders the three: a maximum below the minimum rises to it, the ideal clamps between.
    init(minimum: Double, ideal: Double, maximum: Double) {
        let low = minimum.isFinite ? Swift.max(0, minimum) : 0
        let high = maximum.isFinite ? Swift.max(low, maximum) : .infinity
        self.minimum = low
        self.maximum = high
        self.ideal = Swift.min(Swift.max(ideal.isFinite ? ideal : low, low), high)
    }
}

/// Splits `available` points among panes (`HS-B`, `HS-C`).
enum SplitSolver {
    /// Each pane starts at its preferred size (the user's, when `preferred` has one entry per
    /// pane) else its ideal, clamped to its limits. A surplus then goes to the panes with an
    /// unbounded maximum, equally; a pane that reaches its maximum drops out and the rest take its
    /// share; what those cannot take goes to the bounded panes the same way. A deficit comes off
    /// the same groups in the same order, never below a minimum (minimums that do not fit overflow).
    static func solve(_ panes: [SplitPaneLimits], preferred: [Double]?, available: Double) -> [Double] {
        guard !panes.isEmpty else { return [] }
        let usePreferred = preferred?.count == panes.count
        var sizes = panes.indices.map { index -> Double in
            let want = usePreferred ? preferred![index] : panes[index].ideal
            return Swift.min(Swift.max(want, panes[index].minimum), panes[index].maximum)
        }
        var delta = available - sizes.reduce(0, +)
        guard delta.isFinite, abs(delta) > 1e-9 else { return sizes }
        let unbounded = panes.indices.filter { panes[$0].maximum.isInfinite }
        let bounded = panes.indices.filter { !panes[$0].maximum.isInfinite }
        func spread(over group: [Int]) {
            var active = group
            while abs(delta) > 1e-9, !active.isEmpty {
                let share = delta / Double(active.count)
                var next: [Int] = []
                var consumed = 0.0
                for index in active {
                    let wanted = sizes[index] + share
                    let clamped = Swift.min(Swift.max(wanted, panes[index].minimum), panes[index].maximum)
                    consumed += clamped - sizes[index]
                    sizes[index] = clamped
                    if clamped == wanted { next.append(index) }
                }
                delta -= consumed
                if next.count == active.count { break }
                active = next
            }
        }
        spread(over: unbounded)
        spread(over: bounded)
        return sizes
    }

    /// The new sizes when divider `index` (between panes `index` and `index + 1`) is dragged by
    /// `translation` from the sizes in `start` (`HS-D`): the pair keeps its total, each clamped to
    /// its limits; every other pane keeps its size.
    static func dragged(_ start: SplitDragSnapshot, by translation: Double) -> [Double] {
        let a = start.index, b = start.index + 1
        guard start.sizes.indices.contains(b) else { return start.sizes }
        let total = start.sizes[a] + start.sizes[b]
        let low = Swift.max(start.minimums[a], total - start.maximums[b])
        let high = Swift.min(start.maximums[a], total - start.minimums[b])
        var sizes = start.sizes
        guard low <= high else { return sizes }
        sizes[a] = Swift.min(Swift.max(start.sizes[a] + translation, low), high)
        sizes[b] = total - sizes[a]
        return sizes
    }
}

/// What a drag keeps from its first event: the sizes and limits the layout last placed.
struct SplitDragSnapshot: Equatable {
    var index: Int
    var sizes: [Double]
    var minimums: [Double]
    var maximums: [Double]
}

/// A split view's `@State` (`HS-D`): the sizes the user chose, and the drag in progress.
struct SplitModel {
    var sizes: [Double]?
    var drag: SplitDragSnapshot?
}

/// The sizes and limits the layout placed last, for the divider handlers registered with it.
/// The layout writes it and only input handlers read it (`HS-E`).
final class SplitReport: @unchecked Sendable {
    var sizes: [Double] = []
    var minimums: [Double] = []
    var maximums: [Double] = []

    func snapshot(at index: Int) -> SplitDragSnapshot? {
        guard sizes.indices.contains(index + 1) else { return nil }
        return SplitDragSnapshot(index: index, sizes: sizes, minimums: minimums, maximums: maximums)
    }
}

// MARK: - The layout

/// Panes first, then the dividers between them (`paneCount - 1` of them), along `axis`.
///
/// Not `Hashable`: it holds the report the layout writes, so it taints exactly its ancestors for
/// the layout memo (as `LazyStackLayout`) and runs every layout.
struct SplitLayout: ProposalLayout {
    var axis: ProposalStackAxis
    var paneCount: Int
    var preferred: [Double]?
    var thickness: Double
    var report: SplitReport

    private var horizontal: Bool { axis == .horizontal }

    private func proposal(main: Double?, cross: Double?) -> ProposedSize {
        horizontal ? ProposedSize(width: main, height: cross) : ProposedSize(width: cross, height: main)
    }

    private func mainOf(_ size: SizeD) -> Double { horizontal ? size.width : size.height }
    private func crossOf(_ size: SizeD) -> Double { horizontal ? size.height : size.width }

    private func limits(_ measure: (Int, ProposedSize) -> SizeD, cross: Double?) -> [SplitPaneLimits] {
        (0..<paneCount).map { index in
            SplitPaneLimits(minimum: mainOf(measure(index, proposal(main: 0, cross: cross))),
                            ideal: mainOf(measure(index, proposal(main: nil, cross: cross))),
                            maximum: mainOf(measure(index, proposal(main: .infinity, cross: cross))))
        }
    }

    private var dividersExtent: Double { Double(Swift.max(0, paneCount - 1)) * thickness }

    func sizeThatFits(proposal offer: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
        let offeredMain = horizontal ? offer.width : offer.height
        let offeredCross = horizontal ? offer.height : offer.width
        let cross = offeredCross.flatMap { $0.isFinite ? $0 : nil }
        let measure: (Int, ProposedSize) -> SizeD = { subviews[$0].sizeThatFits($1).size }
        let paneLimits = limits(measure, cross: cross)
        let main: Double
        if let offeredMain, offeredMain.isFinite {
            main = offeredMain
        } else {
            main = paneLimits.map(\.ideal).reduce(0, +) + dividersExtent
        }
        let sizes = SplitSolver.solve(paneLimits, preferred: preferred, available: main - dividersExtent)
        let answerCross: Double
        if let cross {
            answerCross = cross
        } else {
            answerCross = sizes.indices.map {
                crossOf(measure($0, proposal(main: sizes[$0], cross: nil)))
            }.max() ?? 0
        }
        return LayoutMeasurement(size: horizontal ? SizeD(width: main, height: answerCross)
                                                  : SizeD(width: answerCross, height: main))
    }

    func placeSubviews(in bounds: LayoutRect, proposal offer: ProposedSize, subviews: PlacementSubviews) {
        let origin = horizontal ? bounds.x : bounds.y
        let main = horizontal ? bounds.width : bounds.height
        let cross = horizontal ? bounds.height : bounds.width
        let measure: (Int, ProposedSize) -> SizeD = { subviews[$0].sizeThatFits($1).size }
        let paneLimits = limits(measure, cross: cross)
        let sizes = SplitSolver.solve(paneLimits, preferred: preferred, available: main - dividersExtent)
        report.sizes = sizes
        report.minimums = paneLimits.map(\.minimum)
        report.maximums = paneLimits.map(\.maximum)
        var along = origin
        for index in 0..<paneCount {
            let at = horizontal ? Point(x: along, y: bounds.y) : Point(x: bounds.x, y: along)
            subviews[index].place(at: at, anchor: .topLeading, proposal: proposal(main: sizes[index], cross: cross))
            along += sizes[index]
            if index < paneCount - 1 {
                let divider = horizontal ? Point(x: along, y: bounds.y) : Point(x: bounds.x, y: along)
                subviews[paneCount + index].place(at: divider, anchor: .topLeading,
                                                  proposal: proposal(main: thickness, cross: cross))
                along += thickness
            }
        }
    }
}

// MARK: - The divider

/// One divider: a 1-point `.separator` line with a 6-point hit area centred on it that takes the
/// resize pointer and the drag (`HS-F`). The hit area is an overlay, so it takes no layout room and
/// overlaps the neighbouring panes by 2.5 points each side; the dividers register after the panes
/// and so rank above them.
struct SplitDivider: Component, ProposalElementGroup {
    nonisolated static let thickness: Double = 1
    nonisolated static let hitExtent: Float = 6

    var axis: ProposalStackAxis
    var onChanged: @MainActor (DragGesture.Value) -> Void
    var onEnded: @MainActor (DragGesture.Value) -> Void
    var onCancelled: @MainActor () -> Void

    var content: some ProposalElementGroup {
        let vertical = axis == .horizontal   // a row of panes has vertical dividers
        let drag = DragGesture(minimumDistance: Pixels(0))
            .onChanged(onChanged).onEnded(onEnded).onCancelled(onCancelled)
        return Color(.separator)
            .frame(width: vertical ? Pixels(Float(Self.thickness)) : nil,
                   height: vertical ? nil : Pixels(Float(Self.thickness)))
            .overlay {
                Color.clear
                    .frame(width: vertical ? Pixels(Self.hitExtent) : nil,
                           height: vertical ? nil : Pixels(Self.hitExtent))
                    .gesture(drag)
                    .pointerStyle(vertical ? .columnResize : .rowResize)
            }
    }
}

// MARK: - The engine both public types share

/// The one implementation behind `HSplitView` and `VSplitView`.
@MainActor
struct SplitEngine<Content: ProposalElementGroup> {
    var panes: Content
    var axis: ProposalStackAxis
    var autosaveName: String?
    var store: (any SplitViewAutosaveStore)?
    var dividers = ArrayGroup<SplitDivider>([])

    struct Layout {
        var node: ProposalNodeID
        var panes: Content.GroupLayout
        var dividers: ArrayGroup<SplitDivider>.GroupLayout
    }

    struct Prepaint {
        var panes: Content.GroupPrepaint
        var dividers: ArrayGroup<SplitDivider>.GroupPrepaint
    }

    private var effectiveStore: any SplitViewAutosaveStore { store ?? UserDefaultsSplitViewStore.shared }

    mutating func requestLayout(_ id: GlobalElementID, model: Binding<SplitModel>,
                                pass: inout LayoutPass) -> (ProposalNodeID, Layout) {
        var cursor = 0
        let stackAxis: ProposalStackAxis = axis
        let (paneNodes, paneLayout) = pass.frame.withStackAxis(stackAxis) {
            panes.requestProposalGroupLayout(under: id, at: &cursor, pass: &pass)
        }
        let report = SplitReport()
        let name = autosaveName
        let store = effectiveStore
        let axis = self.axis
        dividers = ArrayGroup((0..<Swift.max(0, paneNodes.count - 1)).map { index in
            SplitDivider(axis: axis,
                         onChanged: { Self.dragChanged($0, index: index, axis: axis, report: report, model: model) },
                         onEnded: { Self.dragEnded($0, axis: axis, name: name, store: store, model: model) },
                         onCancelled: { var m = model.wrappedValue; m.drag = nil; model.wrappedValue = m })
        })
        let (dividerNodes, dividerLayout) = dividers.requestProposalGroupLayout(under: id, at: &cursor, pass: &pass)
        var preferred = model.wrappedValue.sizes
        if preferred == nil, let name { preferred = store.paneSizes(forName: name) }
        let layout = SplitLayout(axis: axis, paneCount: paneNodes.count, preferred: preferred,
                                 thickness: SplitDivider.thickness, report: report)
        let node = pass.requestNativeLayout(layout, children: paneNodes + dividerNodes)
        return (node, Layout(node: node, panes: paneLayout, dividers: dividerLayout))
    }

    /// Writes state from input only (the first event keeps the snapshot, later ones the sizes).
    private static func dragChanged(_ value: DragGesture.Value, index: Int, axis: ProposalStackAxis,
                                    report: SplitReport, model: Binding<SplitModel>) {
        var state = model.wrappedValue
        let snapshot: SplitDragSnapshot
        if let held = state.drag, held.index == index {
            snapshot = held
        } else {
            guard let fresh = report.snapshot(at: index) else { return }
            snapshot = fresh
            state.drag = fresh
        }
        let translation = Double(axis == .horizontal ? value.translation.width.value : value.translation.height.value)
        if translation != 0 { state.sizes = SplitSolver.dragged(snapshot, by: translation) }
        model.wrappedValue = state
    }

    private static func dragEnded(_ value: DragGesture.Value, axis: ProposalStackAxis, name: String?,
                                  store: any SplitViewAutosaveStore, model: Binding<SplitModel>) {
        var state = model.wrappedValue
        state.drag = nil
        model.wrappedValue = state
        let moved = (axis == .horizontal ? value.translation.width.value : value.translation.height.value) != 0
        if moved, let name, let sizes = state.sizes { store.setPaneSizes(sizes, forName: name) }
    }

    mutating func prepaint(layout: inout Layout, pass: inout PrepaintPass) -> Prepaint {
        Prepaint(panes: panes.prepaintGroup(layout: &layout.panes, pass: &pass),
                 dividers: dividers.prepaintGroup(layout: &layout.dividers, pass: &pass))
    }

    mutating func paint(layout: inout Layout, prepaint: inout Prepaint, pass: inout PaintPass) {
        panes.paintGroup(layout: &layout.panes, prepaint: &prepaint.panes, pass: &pass)
        dividers.paintGroup(layout: &layout.dividers, prepaint: &prepaint.dividers, pass: &pass)
    }
}

// MARK: - The public views

/// Panes side by side with a draggable divider between each pair — SwiftUI's `HSplitView`.
///
/// Each pane's limits are its own `.frame(minWidth:idealWidth:maxWidth:)`; the panes start at
/// their ideal widths, panes with an unbounded maximum take the surplus or deficit when the
/// split view resizes. A 1-point `.separator` divider with a 6-point hit area sits between
/// panes, shows the column-resize pointer on hover, and resizes its two neighbours when
/// dragged, within their limits. The sizes are view state and survive a rebuild; name them
/// with ``splitViewAutosaveName(_:store:)`` to keep them between runs.
public struct HSplitView<Content: ProposalElementGroup>: Element, ProposalElement {
    var engine: SplitEngine<Content>
    @State var model = SplitModel()

    /// A split view of `content`'s panes, left to right (SwiftUI's `HSplitView.init(content:)`).
    public init(@ProposalContentBuilder content: () -> Content) {
        engine = SplitEngine(panes: content(), axis: .horizontal)
    }

    /// Saves the pane sizes under `name` when a divider drag ends and restores them when the view
    /// is built (MetalUI-only, ruling `HS-G`). `store` defaults to `UserDefaults.standard` under
    /// the key `MetalUI.SplitView.<name>`; pass an in-memory conformer in a test. Write it
    /// directly on the split view, before other modifiers.
    public func splitViewAutosaveName(_ name: String, store: (any SplitViewAutosaveStore)? = nil) -> Self {
        var copy = self
        copy.engine.autosaveName = name
        copy.engine.store = store
        return copy
    }

    /// The split view's layout record.
    public struct Layout { var engine: SplitEngine<Content>.Layout }
    /// The split view's prepaint record.
    public struct Prepaint { var engine: SplitEngine<Content>.Prepaint }

    public mutating func requestProposalLayout(_ id: GlobalElementID,
                                               pass: inout LayoutPass) -> (ProposalNodeID, Layout) {
        let (node, layout) = engine.requestLayout(id, model: $model, pass: &pass)
        return (node, Layout(engine: layout))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                                  pass: inout PrepaintPass) -> Prepaint {
        Prepaint(engine: engine.prepaint(layout: &layout.engine, pass: &pass))
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                               prepaint: inout Prepaint, pass: inout PaintPass) {
        engine.paint(layout: &layout.engine, prepaint: &prepaint.engine, pass: &pass)
    }
}

/// Panes stacked with a draggable divider between each pair — SwiftUI's `VSplitView`.
///
/// ``HSplitView`` turned a quarter: limits come from `.frame(minHeight:idealHeight:maxHeight:)`,
/// the dividers are horizontal and show the row-resize pointer.
public struct VSplitView<Content: ProposalElementGroup>: Element, ProposalElement {
    var engine: SplitEngine<Content>
    @State var model = SplitModel()

    /// A split view of `content`'s panes, top to bottom (SwiftUI's `VSplitView.init(content:)`).
    public init(@ProposalContentBuilder content: () -> Content) {
        engine = SplitEngine(panes: content(), axis: .vertical)
    }

    /// As ``HSplitView/splitViewAutosaveName(_:store:)``.
    public func splitViewAutosaveName(_ name: String, store: (any SplitViewAutosaveStore)? = nil) -> Self {
        var copy = self
        copy.engine.autosaveName = name
        copy.engine.store = store
        return copy
    }

    /// The split view's layout record.
    public struct Layout { var engine: SplitEngine<Content>.Layout }
    /// The split view's prepaint record.
    public struct Prepaint { var engine: SplitEngine<Content>.Prepaint }

    public mutating func requestProposalLayout(_ id: GlobalElementID,
                                               pass: inout LayoutPass) -> (ProposalNodeID, Layout) {
        let (node, layout) = engine.requestLayout(id, model: $model, pass: &pass)
        return (node, Layout(engine: layout))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                                  pass: inout PrepaintPass) -> Prepaint {
        Prepaint(engine: engine.prepaint(layout: &layout.engine, pass: &pass))
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                               prepaint: inout Prepaint, pass: inout PaintPass) {
        engine.paint(layout: &layout.engine, prepaint: &prepaint.engine, pass: &pass)
    }
}
