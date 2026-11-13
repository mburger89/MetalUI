import Testing
import MetalUI
import MetalUITesting

// G33 (c) fixture: 50 rows, each wrapped in `depth` nested Component+VStack levels, a `@State` at every leaf. Every id in a row is ~2*depth
// components deep, so a lookup against an earlier frame's table walks the whole chain unless ids are interned. The performance harness
// carries its own copy (docs/probes/perf-harness); this one is read by `chainWalkSteps`, which only a debug build has.

struct G33DeepRow: Component {
    var depth: Int
    var content: some ElementGroup {
        if depth == 0 { G33DeepLeaf() } else { VStack(spacing: 0) { G33DeepRow(depth: depth - 1) } }
    }
}

struct G33DeepLeaf: Component {
    @State var n = 0
    var content: some ElementGroup { Text("row \(n)") }
}

@MainActor func g33DeepWindow(rows: Int = 50, depth: Int = 20) throws -> TestWindow {
    try TestWindow(size: Size(width: Pixels(800), height: Pixels(600)), scaleFactor: 2) {
        VStack(spacing: 0) { ForEach(Array(0..<rows), id: \.self) { _ in G33DeepRow(depth: depth) } }
    }
}

#if DEBUG
/// `chainWalkSteps` spent by each of `frames` full rebuilds, after three warm-up frames.
@MainActor func g33ChainWalkStepsPerFrame(_ window: TestWindow, frames: Int) -> [Int] {
    for _ in 0..<3 { window.window.setNeedsRedraw(); window.tick() }
    var steps: [Int] = []
    for _ in 0..<frames {
        let before = GlobalElementID.chainWalkSteps
        window.window.setNeedsRedraw(); window.tick()
        steps.append(GlobalElementID.chainWalkSteps - before)
    }
    return steps
}

/// The instrument: a rebuilt deep tree compares chains (the baseline G33 (c) removes), and prints the figure.
@Test @MainActor func aRebuiltDeepTreeSpendsChainWalkSteps() throws {
    let steps = g33ChainWalkStepsPerFrame(try g33DeepWindow(), frames: 3)
    print("G33CHAIN chainWalkSteps per frame: \(steps)")
    #expect(steps.allSatisfy { $0 > 0 }, "the counter is live: \(steps)")
}
#endif
