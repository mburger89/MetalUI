import MetalUI
import MetalUIScene
import MetalUITesting
import MetalUITextSystem
import Observation
import Testing

// C14 lane 0 (IV-A): the counted baseline of what ONE observed change costs in a
// branching tree of Components, before any incremental work. Counted at user
// code (Component bodies), at the layout run (`FrameWork`) and at the text seam
// (`CountingTextSystem`, SurfaceTextOverlayCostTests). Counts, never time.
// Every number below is the whole-window rebuild's; the IV- spec names the
// target values the implementation lanes' pins will assert.

/// One observed cell: a leaf reads `value`, nothing else does.
@Observable @MainActor final class IVCell {
    var value = 0
}

/// Body evaluations by kind, reset by the test.
@MainActor enum IVStats {
    static var branches = 0
    static var leaves = 0
    static func reset() { branches = 0; leaves = 0 }
}

private struct IVLeaf: Component {
    let cell: IVCell
    var content: some ElementGroup {
        let _ = IVStats.leaves += 1
        Text("v\(cell.value)").frame(width: Pixels(60), height: Pixels(14))
    }
}

private struct IVBranch<Child: Component>: Component {
    let children: [Child]
    var content: some ElementGroup {
        let _ = IVStats.branches += 1
        VStack(spacing: 0) {
            ForEach(Array(children.indices), id: \.self) { children[$0] }
        }
    }
}

@MainActor private func ivWindow(levels: Int, counting: CountingTextSystem) throws -> (TestWindow, [IVCell]) {
    let cells = (0..<Int(pow3(levels))).map { _ in IVCell() }
    let window = try TestWindow(size: sz(400, 600), textSystem: { counting }) {
        VStack(spacing: 0) {
            switch levels {
            case 2: IVBranch(children: (0..<3).map { b in
                IVBranch(children: (0..<3).map { IVLeaf(cell: cells[b * 3 + $0]) }) })
            case 3: IVBranch(children: (0..<3).map { a in
                IVBranch(children: (0..<3).map { b in
                    IVBranch(children: (0..<3).map { IVLeaf(cell: cells[a * 9 + b * 3 + $0]) }) }) })
            default: IVBranch(children: (0..<3).map { a in
                IVBranch(children: (0..<3).map { b in
                    IVBranch(children: (0..<3).map { c in
                        IVBranch(children: (0..<3).map { IVLeaf(cell: cells[a * 27 + b * 9 + c * 3 + $0]) }) }) }) })
            }
        }
    }
    return (window, cells)
}

private func pow3(_ n: Int) -> Double { var r = 1.0; for _ in 0..<n { r *= 3 }; return r }

/// 1.1 — the C14 baseline (`IV-A`): one leaf's `@Observable` write rebuilds the
/// whole window. Per changed frame: 1 build, every Component body re-evaluated
/// (leaves 3^L, branches (3^L − 1)/2 ... counted), every leaf measured, every
/// leaf's text shaped and placed. **Expected to change when C14 lands; the
/// change is the result.** Mutation: a second `ForEach` row in `IVBranch`.
@Test(arguments: [2, 3, 4]) @MainActor func oneObservedLeafChangeRebuildsTheWholeWindow(levels: Int) throws {
    let counting = CountingTextSystem(harnessTextSystem())
    let (window, cells) = try ivWindow(levels: levels, counting: counting)
    let leaves = cells.count
    let branches = (leaves - 1) / 2   // 3-ary tree: internal nodes above the leaf parents
    for _ in 0..<2 { cells[0].value += 1; window.tick() }   // warm
    counting.reset(); IVStats.reset(); window.resetFrameWork()
    let frames = 4
    for f in 0..<frames { cells[leaves - 1].value += 1 + f; window.tick() }
    let w = window.frameWork
    try #require(w.count == frames)
    let sum = w.dropFirst().reduce(w[0], +)
    print("IV baseline L=\(levels): \(sum) leafBodies=\(IVStats.leaves) branchBodies=\(IVStats.branches) measures=\(counting.measures) places=\(counting.places) glyphs=\(sum.glyphs)")
    #expect(sum.builds == frames)
    #expect(IVStats.leaves == frames * leaves)
    #expect(IVStats.branches == frames * (branches))
}
