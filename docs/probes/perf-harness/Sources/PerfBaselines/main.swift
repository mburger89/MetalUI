import Foundation
import MetalUI
import MetalUIDemoContent
import MetalUITesting

// Record 105 timing harness. Wall-clock figures are dated measurements, never
// test pins; the counts printed beside them are the durable observables.
// Output: one TSV line per measurement, `scenario<TAB>metric<TAB>value`.

func px(_ v: Float) -> Pixels { Pixels(v) }
func now() -> Double {
    var t = timespec(); clock_gettime(CLOCK_MONOTONIC, &t)
    return Double(t.tv_sec) * 1000 + Double(t.tv_nsec) / 1e6
}
func median(_ xs: [Double]) -> Double { let s = xs.sorted(); return s[s.count / 2] }
func report(_ scenario: String, _ metric: String, _ value: String) { print("\(scenario)\t\(metric)\t\(value)") }
func ms(_ v: Double) -> String { String(format: "%.3f", v) }

func workLine(_ w: FrameWork) -> String {
    "builds=\(w.builds) measureCalls=\(w.layoutMeasureCalls) cacheHits=\(w.layoutCacheHits) cacheMisses=\(w.layoutCacheMisses) rects=\(w.rects) glyphs=\(w.glyphs) images=\(w.images)"
}

// MARK: Synthetic branching trees (record 07's shapes: depth 12 branch 2 = 8,191; depth 10 branch 3 = 88,573)

/// One node of a branching tree: a stack of `b` children, the leaves 10x10 colours. A `Component` per
/// interior node (identity-opaque, one cursor index) because `AnyElement` is not an `Element`; every
/// element count below is of these Components plus leaves.
struct Branch: Component {
    var depth: Int
    var b: Int
    var row: Bool
    var content: some ElementGroup {
        if depth == 0 {
            Color.blue.frame(width: px(10), height: px(10))
        } else if row {
            HStack(spacing: 0) { ForEach(Array(0..<b), id: \.self) { _ in Branch(depth: depth - 1, b: b, row: false) } }
        } else {
            VStack(spacing: 0) { ForEach(Array(0..<b), id: \.self) { _ in Branch(depth: depth - 1, b: b, row: true) } }
        }
    }
}

@MainActor func treeScenario(name: String, depth: Int, b: Int, nodes: Int, reps: Int) throws {
    let size = Size(width: px(800), height: px(600))
    var colds: [Double] = []
    var window: TestWindow?
    for _ in 0..<max(1, reps / 2) {
        let t0 = now()
        window = try TestWindow(size: size, scaleFactor: 2) { VStack(spacing: 0) { Branch(depth: depth, b: b, row: true) } }
        colds.append(now() - t0)
    }
    report(name, "elements", "\(nodes)")
    report(name, "cold_frame_ms_median", ms(median(colds)))
    let w = window!
    report(name, "cold_work", workLine(w.lastFrameWork))
    var warms: [Double] = []
    for _ in 0..<reps {
        w.window.setNeedsRedraw()
        let t0 = now(); w.tick(); warms.append(now() - t0)
    }
    report(name, "warm_frame_ms_median", ms(median(warms)))
    report(name, "warm_frame_ms_min", ms(warms.min()!))
    report(name, "warm_us_per_element_median", String(format: "%.3f", median(warms) * 1000 / Double(nodes)))
    report(name, "warm_work", workLine(w.lastFrameWork))
}

// MARK: The real demo tree (920x560, scale 2, dark)

@MainActor func demoScenario(reps: Int) throws {
    let size = Size(width: px(920), height: px(560))
    var colds: [Double] = []
    var window: TestWindow?
    for _ in 0..<max(1, reps / 10) {
        let t0 = now()
        window = try TestWindow(size: size, colorScheme: .dark, scaleFactor: 2) { demoContent() }
        colds.append(now() - t0)
    }
    let w = window!
    for _ in 0..<10 { w.window.setNeedsRedraw(); w.tick() }
    var warms: [Double] = []
    for _ in 0..<reps {
        w.window.setNeedsRedraw()
        let t0 = now(); w.tick(); warms.append(now() - t0)
    }
    report("demo", "cold_frame_ms_median", ms(median(colds)))
    report("demo", "warm_frame_ms_median", ms(median(warms)))
    report("demo", "warm_frame_ms_min", ms(warms.min()!))
    report("demo", "warm_work", workLine(w.lastFrameWork))
}

// MARK: List rows (windowed): 40 / 500 / 100,000

struct Row: Identifiable { let id: Int }

@MainActor func listScenario(rows n: Int, reps: Int) throws {
    let size = Size(width: px(920), height: px(560))
    let t0 = now()
    let w = try TestWindow(size: size, colorScheme: .dark, scaleFactor: 2) {
        ScrollView(.vertical) {
            List((0..<n).map(Row.init), rowHeight: px(28)) { r in Text("Row \(r.id + 1) of \(n) - a scrollable list item") }
        }.frame(width: px(420), height: px(370))
    }
    let cold = now() - t0
    for _ in 0..<5 { w.window.setNeedsRedraw(); w.tick() }
    var warms: [Double] = []
    for _ in 0..<reps {
        w.window.setNeedsRedraw()
        let t = now(); w.tick(); warms.append(now() - t)
    }
    report("list\(n)", "cold_frame_ms", ms(cold))
    report("list\(n)", "warm_frame_ms_median", ms(median(warms)))
    report("list\(n)", "warm_work", workLine(w.lastFrameWork))
}

// MARK: Drag frame: N draggable nodes, one dragged (record 105: "20 nodes ~15 ms per drag frame")

@MainActor final class DragModel { var dx: Float = 0 }

@MainActor func dragScenario(nodes n: Int, reps: Int) throws {
    let model = DragModel()
    let w = try TestWindow(size: Size(width: px(800), height: px(600)), colorScheme: .dark, scaleFactor: 2) {
        ZStack(alignment: .topLeading) {
            ForEach(Array(0..<n), id: \.self) { i in
                VStack(spacing: 4) {
                    Text("Node \(i)")
                    Color.blue.frame(width: px(60), height: px(24))
                }
                .padding(Edges(all: px(6)))
                .background(Color.gray)
                .offset(x: px(Float(i % 5) * 150 + (i == 0 ? model.dx : 0)), y: px(Float(i / 5) * 100))
                .gesture(DragGesture().onChanged { v in if i == 0 { model.dx = Float(v.translation.width.value) } })
            }
        }
    }
    for _ in 0..<5 { w.window.setNeedsRedraw(); w.tick() }
    // One drag of node 0: a press, `reps` moves each followed by one frame, a release and one frame.
    let t0 = now()
    w.drag(from: Point(x: px(20), y: px(20)), to: Point(x: px(20 + Float(reps)), y: px(20)), steps: reps)
    let total = now() - t0
    report("drag\(n)", "per_frame_ms", ms(total / Double(reps + 1)))
    report("drag\(n)", "last_frame_work", workLine(w.lastFrameWork))
}

let args = CommandLine.arguments.dropFirst()
let which = args.first(where: { !$0.hasPrefix("--") }) ?? "all"
let quick = args.contains("--quick")
let reps = quick ? 5 : 21

MainActor.assumeIsolated {
    do {
        if which == "all" || which == "tree" {
            try treeScenario(name: "tree_d12_b2", depth: 12, b: 2, nodes: 8191, reps: reps)
            try treeScenario(name: "tree_d10_b3", depth: 10, b: 3, nodes: 88573, reps: max(5, reps / 4))
        }
        if which == "all" || which == "demo" { try demoScenario(reps: quick ? 20 : 200) }
        if which == "all" || which == "list" {
            try listScenario(rows: 40, reps: quick ? 20 : 200)
            try listScenario(rows: 500, reps: quick ? 20 : 200)
            try listScenario(rows: 100_000, reps: quick ? 5 : 21)
        }
        if which == "all" || which == "drag" { try dragScenario(nodes: 20, reps: quick ? 20 : 100) }
    } catch { print("error: \(error)") }
}
