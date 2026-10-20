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
/// Thread CPU time in milliseconds: what the frame cost the main thread, unaffected by other processes taking the core.
func cpuNow() -> Double {
    var t = timespec(); clock_gettime(CLOCK_THREAD_CPUTIME_ID, &t)
    return Double(t.tv_sec) * 1000 + Double(t.tv_nsec) / 1e6
}
func median(_ xs: [Double]) -> Double { let s = xs.sorted(); return s[s.count / 2] }
func report(_ scenario: String, _ metric: String, _ value: String) { print("\(scenario)\t\(metric)\t\(value)") }
func ms(_ v: Double) -> String { String(format: "%.3f", v) }

func workLine(_ w: FrameWork) -> String {
    "builds=\(w.builds) measureCalls=\(w.layoutMeasureCalls) cacheHits=\(w.layoutCacheHits) cacheMisses=\(w.layoutCacheMisses) rects=\(w.rects) glyphs=\(w.glyphs) images=\(w.images) elementPaints=\(w.elementPaints) retainedHits=\(w.retainedHits) retainedMisses=\(w.retainedMisses) retainedIneligible=\(w.retainedIneligible) elementRequests=\(w.elementRequests) elementPrepaints=\(w.elementPrepaints) skippedPrepaints=\(w.retainedSkippedPrepaints) prepaintHits=\(w.retainedPrepaintHits) prepaintIneligible=\(w.retainedPrepaintIneligible) redos=\(w.retainedRedos) translated=\(w.retainedTranslated) grafts=\(w.retainedGrafts) graftIneligible=\(w.retainedGraftIneligible) skippedRequests=\(w.retainedSkippedRequests) graftedNodes=\(w.retainedGraftedNodes) placeGlyphs=\(w.glyphs) rasterizedPixels=\(w.rasterizedPixels) uploadPixels=\(w.atlasUploadPixels) contentEvaluations=\(w.contentEvaluations) reasons=\(w.retainedIneligibleReasons.sorted { $0.key < $1.key })"
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


// MARK: The bracket window's node drag (C14b, fixture BracketFixture.swift copied in by perf-baselines.sh)

@MainActor func bracketScenario(arm: BracketArm, name: String, reps: Int) throws {
    let model = BracketModel(), viewport = BracketViewport()
    let w = try TestWindow(size: bracketWindowSize, colorScheme: .dark, scaleFactor: 2) {
        bracketRoot(arm: arm, model: model, viewport: viewport)
    }
    for _ in 0..<5 { w.window.setNeedsRedraw(); w.tick() }
    let steps = 20
    var perFrame: [Double] = []
    for rep in 0..<reps {
        let sign: Float = rep % 2 == 0 ? 1 : -1
        let startX: Float = rep % 2 == 0 ? 20 : 20 + 2 * Float(steps)
        let t0 = now()
        w.drag(from: Point(x: px(startX), y: px(400)), to: Point(x: px(startX + sign * 2 * Float(steps)), y: px(400)), steps: steps)
        perFrame.append((now() - t0) / Double(steps + 2))
    }
    report(name, "drag_frame_ms_median", ms(median(perFrame)))
    report(name, "drag_frame_ms_min", ms(perFrame.min()!))
    report(name, "last_frame_work", workLine(w.lastFrameWork))
}

/// The same drag with prepaint replay off (`METALUI_RETAINED_PREPAINT=0`, read when each window is made) and on,
/// alternating inside one process so the two see the same machine (`RK-J`'s gate reading): per-frame median over
/// every round's frames, and the last frame's work.
@MainActor func bracketABScenario(arm: BracketArm, name: String, rounds: Int, reps: Int, variable: String = "METALUI_RETAINED_PREPAINT") throws {
    var frames: [String: [Double]] = ["off": [], "on": []]
    var cpu: [String: [Double]] = ["off": [], "on": []]
    var work: [String: FrameWork] = [:]
    for round in 0..<rounds {
        for mode in (round % 2 == 0 ? ["off", "on"] : ["on", "off"]) {
            setenv(variable, mode == "off" ? "0" : "1", 1)
            let model = BracketModel(), viewport = BracketViewport()
            let w = try TestWindow(size: bracketWindowSize, colorScheme: .dark, scaleFactor: 2) {
                bracketRoot(arm: arm, model: model, viewport: viewport)
            }
            for _ in 0..<5 { w.window.setNeedsRedraw(); w.tick() }
            let steps = 20
            for rep in 0..<reps {
                let sign: Float = rep % 2 == 0 ? 1 : -1
                let startX: Float = rep % 2 == 0 ? 20 : 20 + 2 * Float(steps)
                let t0 = now(), c0 = cpuNow()
                w.drag(from: Point(x: px(startX), y: px(400)), to: Point(x: px(startX + sign * 2 * Float(steps)), y: px(400)), steps: steps)
                frames[mode, default: []].append((now() - t0) / Double(steps + 2))
                cpu[mode, default: []].append((cpuNow() - c0) / Double(steps + 2))
            }
            work[mode] = w.lastFrameWork
        }
    }
    for mode in ["off", "on"] {
        report(name + "_" + mode, "drag_frame_ms_median", ms(median(frames[mode]!)))
        report(name + "_" + mode, "drag_frame_ms_min", ms(frames[mode]!.min()!))
        report(name + "_" + mode, "drag_frame_cpu_ms_median", ms(median(cpu[mode]!)))
        report(name + "_" + mode, "last_frame_work", workLine(work[mode]!))
    }
}

/// C14-c (`EE-J`): the node drag of the `.value`, `.environment` and `.environmentObject` arms alternating inside one
/// process (so the three see the same machine; the ratio to `.value` is the reading): wall and thread-CPU medians and
/// minima over every round's frames, and the last frame's work. Retention on (the default).
@MainActor func bracketEnvScenario(rounds: Int, reps: Int) throws {
    let arms: [(String, BracketArm)] = [("value", .value), ("environment", .environment), ("environmentObject", .environmentObject)]
    var wall: [String: [Double]] = [:], cpu: [String: [Double]] = [:], work: [String: FrameWork] = [:]
    for round in 0..<rounds {
        for (name, arm) in (round % 2 == 0 ? arms : arms.reversed()) {
            let model = BracketModel(), viewport = BracketViewport()
            let w = try TestWindow(size: bracketWindowSize, colorScheme: .dark, scaleFactor: 2) {
                bracketRoot(arm: arm, model: model, viewport: viewport)
            }
            for _ in 0..<5 { w.window.setNeedsRedraw(); w.tick() }
            let steps = 20
            for rep in 0..<reps {
                let sign: Float = rep % 2 == 0 ? 1 : -1
                let startX: Float = rep % 2 == 0 ? 20 : 20 + 2 * Float(steps)
                let t0 = now(), c0 = cpuNow()
                w.drag(from: Point(x: px(startX), y: px(400)), to: Point(x: px(startX + sign * 2 * Float(steps)), y: px(400)), steps: steps)
                wall[name, default: []].append((now() - t0) / Double(steps + 2))
                cpu[name, default: []].append((cpuNow() - c0) / Double(steps + 2))
            }
            work[name] = w.lastFrameWork
        }
    }
    var load = [Double](repeating: 0, count: 3); getloadavg(&load, 3)
    report("bracketenv", "load_average", String(format: "%.1f %.1f %.1f", load[0], load[1], load[2]))
    for (name, _) in arms {
        report("bracketenv_" + name, "drag_frame_ms_median", ms(median(wall[name]!)))
        report("bracketenv_" + name, "drag_frame_ms_min", ms(wall[name]!.min()!))
        report("bracketenv_" + name, "drag_frame_cpu_ms_median", ms(median(cpu[name]!)))
        report("bracketenv_" + name, "drag_frame_cpu_ms_min", ms(cpu[name]!.min()!))
        report("bracketenv_" + name, "last_frame_work", workLine(work[name]!))
    }
}

/// C14b-3 (`RW-`): the orbit with panels. The `.panels` arm with nothing in the panels changing: each frame bumps the viewport
/// token (what a 3D viewport orbit does) and draws. Retention, prepaint replay and the graft on (the defaults). Wall and thread-CPU
/// medians and minima over every round's frames, the last frame's work, the load average. Run it from the base commit and from the
/// head (`git archive`) alternately, three times each: a dated measurement, never a pin.
@MainActor func bracketOrbitScenario(rounds: Int, frames: Int) throws {
    var wall: [Double] = [], cpu: [Double] = []
    var work = FrameWork()
    for _ in 0..<rounds {
        let model = BracketModel(), viewport = BracketViewport()
        let w = try TestWindow(size: bracketWindowSize, colorScheme: .dark, scaleFactor: 2) {
            bracketRoot(arm: .panels, model: model, viewport: viewport)
        }
        for _ in 0..<5 { viewport.token += 1; w.window.setNeedsRedraw(); w.tick() }
        for _ in 0..<frames {
            let t0 = now(), c0 = cpuNow()
            viewport.token += 1
            w.window.setNeedsRedraw(); w.tick()
            wall.append(now() - t0); cpu.append(cpuNow() - c0)
        }
        work = w.lastFrameWork
    }
    var load = [Double](repeating: 0, count: 3); getloadavg(&load, 3)
    report("bracketorbit", "load_average", String(format: "%.1f %.1f %.1f", load[0], load[1], load[2]))
    report("bracketorbit_panels", "orbit_frame_ms_median", ms(median(wall)))
    report("bracketorbit_panels", "orbit_frame_ms_min", ms(wall.min()!))
    report("bracketorbit_panels", "orbit_frame_cpu_ms_median", ms(median(cpu)))
    report("bracketorbit_panels", "orbit_frame_cpu_ms_min", ms(cpu.min()!))
    report("bracketorbit_panels", "last_frame_work", workLine(work))
}

// MARK: C14-d (`FS-`, record 126): a layout shift and a scroll

/// A card of the shift-and-scroll scenario: a value-equal `.equatable()` row (two swatches and a label).
struct SSCard: Component, @MainActor Equatable {
    let id: Int
    var content: some ElementGroup {
        HStack(spacing: 4) {
            Color(red: 0.2, green: 0.4, blue: 0.8).frame(width: px(10), height: px(10))
            Text("Card \(id)")
            Color(red: 0.8, green: 0.4, blue: 0.2).frame(width: px(10), height: px(10))
        }
        .frame(height: px(20))
    }
}

@MainActor final class SSModel { var header: Float = 10 }

struct SSRoot: Component {
    let model: SSModel
    var content: some ElementGroup {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                VStack(spacing: 2) {
                    Color(red: 0.5, green: 0.5, blue: 0.5).frame(height: px(model.header))
                    ForEach(Array(0..<60), id: \.self) { SSCard(id: $0).equatable() }
                }
            }
            .frame(width: px(300), height: px(400))
        }
    }
}

/// The 60 retained cards of a scroller under a header that grows and shrinks by 4 points (K1: every card's layout origin moves)
/// and under a wheel of 30 points (K2: the scroll offset moves), alternating, retention, prepaint replay and the graft on (the
/// defaults). Wall and thread-CPU medians per movement and the last frame's work. Run it from the base commit and from the head
/// (`git archive`) alternately, three times each: a dated measurement, never a pin (`FS-I`).
@MainActor func shiftScrollScenario(rounds: Int, frames: Int) throws {
    var wall: [String: [Double]] = ["header": [], "scroll": []], cpu: [String: [Double]] = ["header": [], "scroll": []]
    var work: [String: FrameWork] = [:]
    for _ in 0..<rounds {
        let model = SSModel()
        let w = try TestWindow(size: Size(width: px(320), height: px(420)), scaleFactor: 2) { VStack(spacing: 0) { SSRoot(model: model) } }
        for _ in 0..<12 { w.window.setNeedsRedraw(); w.tick() }
        for frame in 0..<frames {
            let kind = frame % 2 == 0 ? "header" : "scroll"
            let t0 = now(), c0 = cpuNow()
            if kind == "header" {
                model.header += (frame / 2) % 2 == 0 ? 4 : -4
                w.window.setNeedsRedraw(); w.tick()
            } else {
                w.scroll(at: Point(x: px(160), y: px(200)), byDeltaX: 0, deltaY: (frame / 2) % 2 == 0 ? -30 : 30)
            }
            wall[kind]!.append(now() - t0); cpu[kind]!.append(cpuNow() - c0)
            work[kind] = w.lastFrameWork
        }
    }
    var load = [Double](repeating: 0, count: 3); getloadavg(&load, 3)
    report("shiftscroll", "load_average", String(format: "%.1f %.1f %.1f", load[0], load[1], load[2]))
    for kind in ["header", "scroll"] {
        report("shiftscroll_" + kind, "frame_ms_median", ms(median(wall[kind]!)))
        report("shiftscroll_" + kind, "frame_ms_min", ms(wall[kind]!.min()!))
        report("shiftscroll_" + kind, "frame_cpu_ms_median", ms(median(cpu[kind]!)))
        report("shiftscroll_" + kind, "frame_cpu_ms_min", ms(cpu[kind]!.min()!))
        report("shiftscroll_" + kind, "last_frame_work", workLine(work[kind]!))
    }
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
        if which == "bracketab" {
            let rounds = quick ? 3 : 8
            try bracketABScenario(arm: .value, name: "bracketab_value", rounds: rounds, reps: quick ? 6 : 14)
            try bracketABScenario(arm: .panels, name: "bracketab_panels", rounds: rounds, reps: quick ? 6 : 14)
        }
        if which == "shiftscroll" { try shiftScrollScenario(rounds: quick ? 3 : 8, frames: quick ? 20 : 40) }
        if which == "bracketorbit" { try bracketOrbitScenario(rounds: quick ? 3 : 8, frames: quick ? 20 : 40) }
        if which == "bracketenv" { try bracketEnvScenario(rounds: quick ? 3 : 8, reps: quick ? 6 : 14) }
        if which == "bracketgraft" {
            // C14b-2 lane 2: the node drag with the graft off (prepaint replay on) and on, alternating (`METALUI_RETAINED_GRAFT`).
            let rounds = quick ? 3 : 8
            try bracketABScenario(arm: .value, name: "bracketgraft_value", rounds: rounds, reps: quick ? 6 : 14, variable: "METALUI_RETAINED_GRAFT")
            try bracketABScenario(arm: .panels, name: "bracketgraft_panels", rounds: rounds, reps: quick ? 6 : 14, variable: "METALUI_RETAINED_GRAFT")
        }
        if which == "all" || which == "bracket" {
            try bracketScenario(arm: .value, name: "bracket_value", reps: quick ? 6 : 30)
            try bracketScenario(arm: .environment, name: "bracket_environment", reps: quick ? 6 : 30)
            try bracketScenario(arm: .panels, name: "bracket_panels", reps: quick ? 6 : 30)
        }
    } catch { print("error: \(error)") }
}
