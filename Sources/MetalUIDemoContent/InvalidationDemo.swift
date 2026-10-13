import MetalUI
import Observation
import Foundation

/// The content-memo demo (spec `2026-10-13-incremental-invalidation-design.md` §9,
/// rulings `IV-B`…`IV-D`), reached with `METALUI_INVALIDATION_DEMO=1 swift run
/// MetalUIDemo`: two copies of one 81-cell tree side by side, the left built with
/// `.equatable()` and the right the same components whose `==` is always false (so
/// each evaluates every frame, as an unmemoized component does). "Bump a cell"
/// writes one observed cell; the counter under each tree reads how many `content`
/// getters the bump's frame evaluated: **1** on the left, **121** on the right. Both
/// draw identically. The readout is the last element of the tree, so it shows its own
/// build's counts (the counters are `@ObservationIgnored`: a getter that counted into an
/// observed property would fire the sessions of the getters that ran before it).
///
/// Nothing here is in the default demo, so the fourteen offscreen images and
/// `Expected.swift` do not move. Each part is its own function passed to a generic
/// composer (the Windows 1 MB stack rule); built on a 1 MB thread by
/// `everyProductionTreeBuildsOnAOneMegabyteThread`.
@MainActor
public func invalidationDemoContent() -> some Element {
    invalidationRoot(header: invalidationHeader(), left: invalidationTree(memo: true),
                     right: invalidationTree(memo: false), readout: InvalidationReadout())
}

/// One observed cell; a leaf reads only its own.
@MainActor
@Observable
public final class InvalidationDemoCell {
    /// The value the leaf draws.
    public var value = 0
    /// A cell.
    public init() {}
}

/// The demo's state, written only from input.
@MainActor
@Observable
public final class InvalidationDemoModel {
    /// The 81 cells both trees read.
    public let cells: [InvalidationDemoCell] = (0..<81).map { _ in InvalidationDemoCell() }
    /// The next cell to bump.
    @ObservationIgnored var next = 0
    /// Getters evaluated since the last snapshot, by side (left, right).
    @ObservationIgnored var counts = [0, 0]
    /// The last snapshot, as drawn.
    @ObservationIgnored var shown = [0, 0]

    /// A fresh model.
    public init() {}

    /// Writes one cell.
    public func bump() {
        cells[next].value += 1
        next = (next + 7) % cells.count
    }

    /// Takes the counts of the build in progress; called by the readout, the last
    /// element of the tree.
    func snapshot() {
        shown = counts
        counts = [0, 0]
    }
}

/// The one model the demo and its tests share.
@MainActor public let invalidationDemoModel = InvalidationDemoModel()

private struct InvalidationLeaf: Component, @MainActor Equatable {
    let cell: InvalidationDemoCell
    let memo: Bool
    var content: some ElementGroup {
        let _ = invalidationDemoModel.counts[memo ? 0 : 1] += 1
        Text("\(cell.value)").font(size: 11).frame(width: Pixels(28), height: Pixels(14))
    }
    static func == (l: InvalidationLeaf, r: InvalidationLeaf) -> Bool {
        l.memo && r.memo && l.cell === r.cell
    }
}

private struct InvalidationBranch: Component, @MainActor Equatable {
    let level: Int
    let first: Int
    let memo: Bool
    var content: some ElementGroup {
        let _ = invalidationDemoModel.counts[memo ? 0 : 1] += 1
        InvalidationRow(level: level, first: first, memo: memo)
    }
    static func == (l: InvalidationBranch, r: InvalidationBranch) -> Bool {
        l.memo && r.memo && l.level == r.level && l.first == r.first
    }
}

/// A branch's three children, in a row at odd levels and a column at even.
@MainActor @ElementBuilder
private func InvalidationRow(level: Int, first: Int, memo: Bool) -> some ElementGroup {
    let span = [27, 9, 3, 1][min(3, level)]
    if level % 2 == 0 {
        HStack(spacing: 2) {
            ForEach(Array(0..<3), id: \.self) { i in invalidationChild(level: level, first: first + i * span, memo: memo) }
        }
    } else {
        VStack(spacing: 2) {
            ForEach(Array(0..<3), id: \.self) { i in invalidationChild(level: level, first: first + i * span, memo: memo) }
        }
    }
}

@MainActor @ElementBuilder
private func invalidationChild(level: Int, first: Int, memo: Bool) -> some ElementGroup {
    if level == 3 {
        InvalidationLeaf(cell: invalidationDemoModel.cells[first], memo: memo).equatable()
    } else {
        InvalidationBranch(level: level + 1, first: first, memo: memo).equatable()
    }
}

@MainActor
private func invalidationTree(memo: Bool) -> some ElementGroup {
    InvalidationBranch(level: 0, first: 0, memo: memo).equatable()
}

/// The two readouts, taking the previous build's counts at the start of this one.
struct InvalidationReadout: Component {
    var content: some ElementGroup {
        let model = invalidationDemoModel
        let _ = model.snapshot()
        HStack(spacing: 40) {
            Text("equatable(): \(model.shown[0]) getters in the last bump's frame").font(size: 12)
            Text("plain: \(model.shown[1]) getters in the last bump's frame").font(size: 12)
        }
    }
}

@MainActor
private func invalidationHeader() -> some Element {
    Text("Content memo — bump a cell: the left tree evaluates 1 getter, the right 121 (the same components, == always false)")
        .font(size: 13)
}

@MainActor
private func invalidationRoot(header: some Element, left: some ElementGroup, right: some ElementGroup,
                              readout: some ElementGroup) -> some Element {
    Column(gap: Pixels(16)) {
        header
        Button("Bump a cell") { invalidationDemoModel.bump() }
        Row(gap: Pixels(40)) {
            left
            right
        }
        readout
    }
    .alignItems(.flexStart)
    .padding(Pixels(24))
    .frame(maxWidth: Pixels(.infinity), maxHeight: Pixels(.infinity), alignment: .topLeading)
    .background(.surface)
}
