import Foundation
import MetalUI
import MetalUIDemoContent
import MetalUITesting
#if PROF_TINT
@testable import MetalUI
#endif

func px(_ v: Float) -> Pixels { Pixels(v) }
func now() -> Double { var t = timespec(); clock_gettime(CLOCK_MONOTONIC, &t); return Double(t.tv_sec) * 1000 + Double(t.tv_nsec) / 1e6 }
func median(_ xs: [Double]) -> Double { let s = xs.sorted(); return s[s.count / 2] }
func workLine(_ w: FrameWork) -> String {
    "builds=\(w.builds) measure=\(w.layoutMeasureCalls) hits=\(w.layoutCacheHits) miss=\(w.layoutCacheMisses) rects=\(w.rects) glyphs=\(w.glyphs) images=\(w.images) elPaints=\(w.elementPaints) retHit=\(w.retainedHits) retMiss=\(w.retainedMisses)"
}

let real = ProcessInfo.processInfo.environment["PROF_HARNESS"] == nil   // default: realistic (no AX client, no layout recording)
let opts = HeadlessPlatformWindow.Options(accessibilityClientActive: !real)
let rec = !real
struct Row: Identifiable { let id: Int }
struct Card: Component {
    let i: Int
    var content: some ElementGroup {
        VStack(spacing: 4) {
            Text("Card \(i)")
            Text("Second line of text in the card")
            Color.blue.frame(width: px(80), height: px(20))
        }
        .padding(Edges(all: px(8)))
        .background(Color.gray, in: RoundedRectangle(cornerRadius: px(10)))
        .shadow(radius: px(8), x: px(0), y: px(4))
    }
}
struct MatCard: Component {
    let i: Int
    var content: some ElementGroup {
        VStack(spacing: 4) { Text("Glass \(i)"); Text("backdrop") }
            .padding(Edges(all: px(10)))
            .background(.regularMaterial)
    }
}
struct RichRow: Component {
    let i: Int
    var content: some ElementGroup {
        Text("Row \(i): **bold** and *italic* with `code` and a [link](https://x.y) in a longer sentence that wraps maybe")
    }
}

/// P4 (record 124): a 6 x 4 grid of shadowed, blurred and radial-gradient cards in a clipped region.
final class OverscanModel { var panX: Float = 0; var panY: Float = 0; var dragW: Float = 60 }
struct OverscanCard: Component {
    let i: Int
    let width: Float
    var content: some ElementGroup {
        switch i % 3 {
        case 0:
            ZStack { Color.blue.frame(width: px(width), height: px(50)) }
                .shadow(radius: px(10), x: px(0), y: px(4))
        case 1:
            Color.orange.frame(width: px(width), height: px(50)).blur(radius: px(6))
        default:
            Rectangle().fill(RadialGradient(colors: [.red, .purple], center: .center, startRadius: px(0), endRadius: px(50)))
                .frame(width: px(width), height: px(50))
        }
    }
}
@MainActor func overscanGrid(_ m: OverscanModel, moving: Bool) -> some Element {
    ZStack(alignment: .topLeading) {
        VStack(spacing: 24) {
            ForEach(Array(0..<4), id: \.self) { r in
                HStack(spacing: 24) {
                    ForEach(Array(0..<6), id: \.self) { c in
                        OverscanCard(i: r * 6 + c, width: moving && r == 1 && c == 2 ? m.dragW : 60)
                    }
                }
            }
        }
        .offset(x: px(m.panX), y: px(m.panY))
    }
    .frame(width: px(420), height: px(260), alignment: .topLeading).clipped()
    .frame(width: px(460), height: px(300), alignment: .center)
}

/// Each scenario returns (window, perFrame closure)
@MainActor func make(_ name: String) throws -> (TestWindow, (Int) -> Void) {
    let big = Size(width: px(920), height: px(560))
    switch name {
    case "bracket-value", "bracket-environment", "bracket-panels":
        let arm: BracketArm = name == "bracket-value" ? .value : name == "bracket-environment" ? .environment : .panels
        let model = BracketModel(), vp = BracketViewport()
        let w = try TestWindow(size: bracketWindowSize, colorScheme: .dark, scaleFactor: 2, options: opts, recordsLayout: rec) { bracketRoot(arm: arm, model: model, viewport: vp) }
        // drag loop: 20 steps per drag, handled as frames
        return (w, { i in
            let steps = 20
            let sign: Float = (i / (steps + 2)) % 2 == 0 ? 1 : -1
            _ = sign
            // one frame = one drag step; do a full drag on i % (steps+2)==0
            if i % (steps + 2) == 0 {
                let r = i / (steps + 2)
                let startX: Float = r % 2 == 0 ? 20 : 20 + 2 * Float(steps)
                let s: Float = r % 2 == 0 ? 1 : -1
                w.drag(from: Point(x: px(startX), y: px(400)), to: Point(x: px(startX + s * 2 * Float(steps)), y: px(400)), steps: steps)
            }
        })
    case "bracket-pan", "bracket-pan-panels", "bracket-orbit":
        let arm: BracketArm = name == "bracket-pan" ? .value : .panels
        let model = BracketModel(), vp = BracketViewport()
        let w = try TestWindow(size: bracketWindowSize, colorScheme: .dark, scaleFactor: 2, options: opts, recordsLayout: rec) { bracketRoot(arm: arm, model: model, viewport: vp) }
        return (w, { i in
            if name == "bracket-orbit" { vp.token += 1 } else {
                model.panX = -680 + Float(i % 40) * 3
                model.panY = 40 + Float(i % 30)
            }
            w.window.setNeedsRedraw(); w.tick()
        })
    case "shadow-pan", "shadow-drag":
        let m = OverscanModel()
        let moving = name == "shadow-drag"
        let w = try TestWindow(size: big, colorScheme: .dark, scaleFactor: 2, options: opts, recordsLayout: rec) { overscanGrid(m, moving: moving) }
        return (w, { i in
            if moving { m.dragW = 60 + Float(i % 40) } else { m.panX = -Float(i % 60) * 2; m.panY = Float(i % 20) }
            w.window.setNeedsRedraw(); w.tick()
        })
    case "demo":
        let w = try TestWindow(size: big, colorScheme: .dark, scaleFactor: 2, options: opts, recordsLayout: rec) { demoContent() }
        return (w, { _ in w.window.setNeedsRedraw(); w.tick() })
    case "demo-scroll":
        let w = try TestWindow(size: big, colorScheme: .dark, scaleFactor: 2, options: opts, recordsLayout: rec) { demoContent() }
        let pt = Point(x: px(Float(ProcessInfo.processInfo.environment["PROF_X"] ?? "400") ?? 400), y: px(Float(ProcessInfo.processInfo.environment["PROF_Y"] ?? "500") ?? 500))
        return (w, { i in w.scroll(at: pt, byDeltaX: 0, deltaY: i % 100 < 50 ? -60 : 60) })
    case "list-fixed":
        let w = try TestWindow(size: big, colorScheme: .dark, scaleFactor: 2, options: opts, recordsLayout: rec) {
            ScrollView(.vertical) { List((0..<5000).map(Row.init), rowHeight: px(28)) { r in Text("Row \(r.id + 1) - a scrollable list item with text") } }.frame(width: px(420), height: px(500))
        }
        return (w, { i in w.scroll(at: Point(x: px(460), y: px(280)), byDeltaX: 0, deltaY: i % 100 < 50 ? -15 : 15) })
    case "list-var":
        let w = try TestWindow(size: big, colorScheme: .dark, scaleFactor: 2, options: opts, recordsLayout: rec) {
            ScrollView(.vertical) { List((0..<2000).map(Row.init)) { r in Text("Row \(r.id + 1) - a variable list item with a longer text that will wrap onto more than one line at this width") } }.frame(width: px(420), height: px(500))
        }
        return (w, { i in w.scroll(at: Point(x: px(460), y: px(280)), byDeltaX: 0, deltaY: i % 100 < 50 ? -15 : 15) })
    case "rich":
        let w = try TestWindow(size: big, colorScheme: .dark, scaleFactor: 2, options: opts, recordsLayout: rec) {
            VStack(spacing: 2) { ForEach(Array(0..<30), id: \.self) { i in RichRow(i: i) } }.frame(width: px(500))
        }
        return (w, { _ in w.window.setNeedsRedraw(); w.tick() })
    case "shadows":
        let w = try TestWindow(size: big, colorScheme: .dark, scaleFactor: 2, options: opts, recordsLayout: rec) {
            VStack(spacing: 8) { ForEach(Array(0..<4), id: \.self) { r in HStack(spacing: 8) { ForEach(Array(0..<5), id: \.self) { c in Card(i: r * 5 + c) } } } }
        }
        return (w, { _ in w.window.setNeedsRedraw(); w.tick() })
    case "materials":
        let w = try TestWindow(size: big, colorScheme: .dark, scaleFactor: 2, options: opts, recordsLayout: rec) {
            ZStack(alignment: .topLeading) {
                Color.blue
                VStack(spacing: 8) { ForEach(Array(0..<4), id: \.self) { r in HStack(spacing: 8) { ForEach(Array(0..<5), id: \.self) { c in MatCard(i: r * 5 + c) } } } }
            }
        }
        return (w, { _ in w.window.setNeedsRedraw(); w.tick() })
    default: fatalError("unknown \(name)")
    }
}

let args = Array(CommandLine.arguments.dropFirst())
let name = args.first ?? "demo"
let iterLimit = (args.count > 1 && args[1].hasPrefix("n")) ? Int(args[1].dropFirst()) : nil
let seconds = iterLimit != nil ? 1e9 : (Double(args.count > 1 ? args[1] : "10") ?? 10)
MainActor.assumeIsolated {
    do {
        if name == "cold" {
            // repeated cold first frames of the bracket (panels) tree and of the demo
            let which = args.count > 2 ? args[2] : "bracket"
            var ts: [Double] = []
            let end = now() + seconds * 1000
            while now() < end {
                let t0 = now()
                if which == "demo" { _ = try TestWindow(size: Size(width: px(920), height: px(560)), colorScheme: .dark, scaleFactor: 2, options: opts, recordsLayout: rec) { demoContent() } }
                else { let m = BracketModel(), v = BracketViewport(); _ = try TestWindow(size: bracketWindowSize, colorScheme: .dark, scaleFactor: 2, options: opts, recordsLayout: rec) { bracketRoot(arm: .value, model: m, viewport: v) } }
                ts.append(now() - t0)
            }
            print("\(name) \(which) cold frames=\(ts.count) median_ms=\(String(format: "%.2f", median(ts)))")
        } else {
            let (w, f) = try make(name)
            if ProcessInfo.processInfo.environment["PROF_FNV"] != nil {
                for k in 0..<7 { f(k) }
                var h: UInt64 = 14695981039346656037
                for g in w.scene.glyphs { for b in "\(g)".utf8 { h = (h ^ UInt64(b)) &* 1099511628211 } }
                for r in w.scene.rects { for b in "\(r)".utf8 { h = (h ^ UInt64(b)) &* 1099511628211 } }
                print("\(name) glyphs=\(w.scene.glyphs.count) rects=\(w.scene.rects.count) fnv=\(h)")
                return
            }
            if ProcessInfo.processInfo.environment["PROF_CHECK"] != nil {
                let sig: @MainActor () -> Int = { var h = Hasher(); for g in w.scene.glyphs.prefix(400) { h.combine("\(g)") }; return h.finalize() }
                let a = sig(); for k in 0..<30 { f(k) }; let b = sig(); for k in 30..<60 { f(k) }; let c = sig()
                print("\(name) scene changes: \(a != b) \(b != c) glyphs=\(w.scene.glyphs.count)")
                return
            }
            for _ in 0..<10 { w.window.setNeedsRedraw(); w.tick() }
            if let n = ProcessInfo.processInfo.environment["PROF_RASTER_FRAMES"].flatMap({ Int($0) }) {
                // Work counters per frame (not time): rasterized px from FrameWork, tinted px and textures made from
                // RasterCache when built with -DPROF_TINT -enable-testing (HEAD only; 34491ff4 tints rasterized px).
                var rast = 0, tint = 0, made = 0, blur = 0
                #if PROF_TINT
                // every adopted frame (a drag draws one per step), after the harness's own observer
                let prior = w.window.onFrameAdopted
                nonisolated(unsafe) var tintSum = 0, madeSum = 0, blurSum = 0
                w.window.onFrameAdopted = { frame in
                    prior?(frame)
                    let r = w.window.animationStore.rasters; tintSum += r.lastTintedPixels; madeSum += r.lastTexturesMade; blurSum += r.lastBlurredPixels
                }
                #endif
                w.resetFrameWork()
                for k in 0..<n { f(k) }
                rast = w.frameWork.reduce(0) { $0 + $1.rasterizedPixels }
                let drawn = w.frameWork.count
                #if PROF_TINT
                tint = tintSum; made = madeSum; blur = blurSum
                #endif
                print("\(name) steps=\(n) framesDrawn=\(drawn) TOTAL rasterizedPx=\(rast) blurredPx=\(blur) tintedPx=\(tint) textures=\(made) | rasterizedPx/frame=\(rast / n) tintedPx/frame=\(tint / n) textures/frame=\(String(format: "%.2f", Double(made) / Double(n)))")
                return
            }
            var ts: [Double] = []
            var i = 0
            let allocOn = ProcessInfo.processInfo.environment["PROF_ALLOC"] != nil
            if allocOn { installMallocLogger() }
            let end = now() + seconds * 1000
            while now() < end && (iterLimit == nil || i < iterLimit!) {
                let t0 = now(); f(i); ts.append(now() - t0); i += 1
            }
            if allocOn {
                print("ALLOC iterations=\(ts.count) allocs=\(gAllocs) frees=\(gFrees) bytes=\(gBytes) sampledStacks=\(gSampled)")
                dumpAllocStacks(path: (ProcessInfo.processInfo.environment["PROF_OUT"] ?? NSTemporaryDirectory()) + "/\(name).allocstacks.tsv")
            }
            let per = name.hasPrefix("bracket-v") || name.hasPrefix("bracket-e") || name == "bracket-panels" ? 1.0 : 1.0
            _ = per
            print("\(name) iterations=\(ts.count) median_ms=\(String(format: "%.3f", median(ts))) mean_ms=\(String(format: "%.3f", ts.reduce(0,+)/Double(ts.count))) | \(workLine(w.lastFrameWork))")
        }
    } catch { print("error: \(error)") }
}

