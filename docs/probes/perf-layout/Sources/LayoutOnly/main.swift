import Foundation
import MetalUICore
import MetalUILayout

// Layout-kernel-only cost: `LayoutTree.computeNativeLayout` over record 07's two
// shapes (depth 12 branch 2 = 8,191 nodes; depth 10 branch 3 = 88,573), alternating
// horizontal and vertical linear stacks over 10x10 leaves, at an 800x600 proposal.
// Output TSV: scenario, metric, value. The work counts are the pins; time is dated.

func now() -> Double {
    var t = timespec(); clock_gettime(CLOCK_MONOTONIC, &t)
    return Double(t.tv_sec) * 1000 + Double(t.tv_nsec) / 1e6
}
func median(_ xs: [Double]) -> Double { let s = xs.sorted(); return s[s.count / 2] }

func build(_ tree: LayoutTree, depth: Int, branch: Int, horizontal: Bool) -> LayoutNodeID {
    if depth == 0 {
        return tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }
    }
    let kids = (0..<branch).map { _ in build(tree, depth: depth - 1, branch: branch, horizontal: !horizontal) }
    return tree.newNativeLinearStack(children: kids, axis: horizontal ? .horizontal : .vertical)
}

func scenario(_ name: String, depth: Int, branch: Int, nodes: Int, reps: Int) {
    let tree = LayoutTree(generation: 0)
    let t0 = now()
    let root = build(tree, depth: depth, branch: branch, horizontal: true)
    let buildMs = now() - t0
    var times: [Double] = []
    for _ in 0..<reps {
        let t = now()
        tree.computeNativeLayout(root: root, proposal: ProposedSize(width: 800, height: 600),
                                 centredIn: LayoutRect(x: 0, y: 0, width: 800, height: 600))
        times.append(now() - t)
    }
    let w = tree.lastNativeLayoutWork
    print("\(name)\tnodes\t\(nodes)")
    print("\(name)\ttree_build_ms\t\(String(format: "%.3f", buildMs))")
    print("\(name)\tlayout_ms_median\t\(String(format: "%.3f", median(times)))")
    print("\(name)\tlayout_ms_min\t\(String(format: "%.3f", times.min()!))")
    print("\(name)\tlayout_us_per_node_median\t\(String(format: "%.3f", median(times) * 1000 / Double(nodes)))")
    print("\(name)\twork\tmeasureCalls=\(w.measureCalls) cacheHits=\(w.cacheHits) cacheMisses=\(w.cacheMisses)")
}

let quick = CommandLine.arguments.contains("--quick")
scenario("layout_d12_b2", depth: 12, branch: 2, nodes: 8191, reps: quick ? 5 : 21)
scenario("layout_d10_b3", depth: 10, branch: 3, nodes: 88573, reps: quick ? 3 : 9)
