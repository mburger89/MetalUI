// SCRATCH (stage 6b design, LR-Q): the native recursion's stack ceiling per node
// kind on a 1 MB `Thread`, with `NativeLayoutRun.maxDepth` raised out of the way.
// Driven one depth per process by docs/probes/native-depth-ceiling.sh:
// METALUI_DEPTH_KIND, METALUI_DEPTH_N. Prints `DEPTH-OK <kind> <n>` when the
// chain completes; a stack overflow kills the process before that line.
import Testing
import Foundation
import MetalUICore
@testable import MetalUILayout

private struct PassesThrough6b: ProposalLayout {
    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
        subviews[0].sizeThatFits(proposal)
    }
    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize, subviews: PlacementSubviews) {
        subviews[0].place(at: Point(x: bounds.x, y: bounds.y), proposal: proposal)
    }
}

private final class Done6b: @unchecked Sendable { var ok = false }

@Test func zzDepthCeilingProbe() {
    let env = ProcessInfo.processInfo.environment
    guard let kind = env["METALUI_DEPTH_KIND"], let n = env["METALUI_DEPTH_N"].flatMap(Int.init) else { return }
    let done = Done6b()
    let t = Thread {
        let tree = LayoutTree(generation: 0)
        var node = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }
        for _ in 0..<n {
            switch kind {
            case "padding": node = tree.newNativePadding(child: node, insets: Edges(all: 1))
            case "frame": node = tree.newNativeFrame(child: node, width: 100, height: 100)
            case "flexframe": node = tree.newNativeFrame(child: node, minWidth: 0, maxWidth: .infinity,
                                                          minHeight: 0, maxHeight: .infinity)
            case "stack": node = tree.newNativeLinearStack(children: [node], axis: .vertical, spacing: nil)
            case "hstack": node = tree.newNativeLinearStack(children: [node], axis: .horizontal, spacing: nil)
            case "overlay": node = tree.newNativeOverlay(children: [node])
            case "custom": node = tree.newNativeLayout(PassesThrough6b(), children: [node])
            case "scroll": node = tree.newNativeScrollViewport(child: node, axis: .vertical)
            case "grid":
                let tall = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 1, height: 11)) }
                tree.markNativeGridRow([node, tall])
                node = tree.newNativeGrid(children: [node, tall])
            default: fatalError("unknown kind \(kind)")
            }
        }
        tree.computeNativeLayout(root: node, proposal: ProposedSize(width: 400, height: 400),
                                 in: LayoutRect(x: 0, y: 0, width: 400, height: 400))
        done.ok = true
    }
    t.stackSize = 1024 * 1024
    t.start()
    while !t.isFinished { usleep(1000) }
    if done.ok { print("DEPTH-OK \(kind) \(n)") }
}
