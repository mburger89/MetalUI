import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUI

// Variable-height `List`, lane 1 (ruling `VL-Q`, spec §3.3): the realised
// rows' `ProposalLayout`, driven directly under a `ProposalLayoutContainer` —
// no `List`. `VariableRowsLayout(anchorSlot:anchorY:trailingExtent:)` measures
// each row at `(width, nil)`, answers `anchorY + Σ h[anchorSlot...] +
// trailingExtent`, and places the anchor row at `anchorY`, later rows downward
// and earlier rows upward from it.
//
// The root is centred at its own answer (`CN-J`), so each absolute literal is
// the container's offset plus the row's; both are derived in the comments.
// Red-before: the layout first lands placing every row at y 0, height 0
// (record §82 §3).

private func bounds(_ x: Float, _ y: Float, _ width: Float, _ height: Float) -> Bounds<Pixels> {
    Bounds(origin: Point(x: Pixels(x), y: Pixels(y)),
           size: Size(width: Pixels(width), height: Pixels(height)))
}

/// A row of a fixed `height`, as wide as offered (50 at a nil width).
private struct FixedRow: ProposalElement {
    let height: Double
    let name: String
    let log: LeafBoundsLog

    func requestProposalLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (ProposalNodeID, Void) {
        let height = height
        return (pass.requestNativeLeaf { proposal in
            LayoutMeasurement(size: SizeD(width: proposal.width ?? 50, height: height))
        }, ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                  pass: inout PrepaintPass) {
        log.byName[name] = bounds
    }

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
               prepaint: inout Void, pass: inout PaintPass) {}
}

/// **1.16.** Rows 10/20/30/40, `anchorSlot` 2, `anchorY` 100, `trailingExtent`
/// 50, in a 100 × 300 frame. The container answers 100 × (100 + 30 + 40 + 50)
/// = 220 and is centred: y (300 − 220) / 2 = 40. Row 2 (the anchor) at 40 +
/// 100 = 140, row 3 below it at 170, row 1 above it at 140 − 20 = 120, row 0 at
/// 120 − 10 = 110 — the spec's 70/80/100/130 plus 40. Mutation: place every row
/// downward from slot 0 at `anchorY` (row 0 reads 140).
@MainActor
@Test func variableRowsPlaceTheAnchorAtItsOffsetAndTheRestAroundIt() {
    let log = LeafBoundsLog()
    var root = ProposalLayoutContainer(VariableRowsLayout(anchorSlot: 2, anchorY: 100,
                                                          trailingExtent: 50)) {
        FixedRow(height: 10, name: "r0", log: log)
        FixedRow(height: 20, name: "r1", log: log)
        FixedRow(height: 30, name: "r2", log: log)
        FixedRow(height: 40, name: "r3", log: log)
    }
    Frame(contentSize: Size(width: Pixels(100), height: Pixels(300)), scaleFactor: 1).render(&root)
    #expect(log.byName["r0"] == bounds(0, 110, 100, 10))
    #expect(log.byName["r1"] == bounds(0, 120, 100, 20))
    #expect(log.byName["r2"] == bounds(0, 140, 100, 30))
    #expect(log.byName["r3"] == bounds(0, 170, 100, 40))
}

/// **1.17.** Two `AreaLeaf(4000)` rows, anchor slot 0 at 0, no trailing
/// extent. At width 200 each is 4000 / 200 = 20: the container is 200 × 40,
/// centred at y (300 − 40) / 2 = 130 — rows at 130 and 150. At width 400 each
/// is 10: 400 × 20 at y 140 — rows at 140 and 150. Mutation: propose rows
/// `(nil, nil)` (each 4000 / 100 = 40 tall at both widths).
@MainActor
@Test func variableRowsAreMeasuredAtTheProposedWidth() {
    for (width, expected) in [(Float(200), [bounds(0, 130, 200, 20), bounds(0, 150, 200, 20)]),
                              (Float(400), [bounds(0, 140, 400, 10), bounds(0, 150, 400, 10)])] {
        let log = LeafBoundsLog()
        var root = ProposalLayoutContainer(VariableRowsLayout(anchorSlot: 0, anchorY: 0,
                                                              trailingExtent: 0)) {
            AreaLeaf(4000, name: "a", log: log)
            AreaLeaf(4000, name: "b", log: log)
        }
        Frame(contentSize: Size(width: Pixels(width), height: Pixels(300)), scaleFactor: 1).render(&root)
        #expect(log.byName["a"] == expected[0], "width \(width)")
        #expect(log.byName["b"] == expected[1], "width \(width)")
    }
}

/// **1.18.** A nil width (`.fixedSize(horizontal: true, vertical: false)`):
/// rows of natural width 100 and 200 — the layout is the widest, 200, and each
/// row is measured at it, 4000 / 200 = 20. The container is 200 × 40, centred
/// in 400 × 300 at (100, 130): rows (100, 130, 200, 20) and (100, 150, 200,
/// 20). Mutation: measure heights at `(nil, nil)` (row a reads 40 tall).
@MainActor
@Test func variableRowsAtANilWidthTakeTheWidestRow() {
    let log = LeafBoundsLog()
    var root = ProposalLayoutContainer(VariableRowsLayout(anchorSlot: 0, anchorY: 0,
                                                          trailingExtent: 0)) {
        AreaLeaf(4000, naturalWidth: 100, name: "a", log: log)
        AreaLeaf(4000, naturalWidth: 200, name: "b", log: log)
    }.fixedSize(horizontal: true, vertical: false)
    Frame(contentSize: Size(width: Pixels(400), height: Pixels(300)), scaleFactor: 1).render(&root)
    #expect(log.byName["a"] == bounds(100, 130, 200, 20))
    #expect(log.byName["b"] == bounds(100, 150, 200, 20))
}
