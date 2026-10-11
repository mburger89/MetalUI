// The shadow-cache measurement — the TEST half (C13 / PERF-a, ruling `PF-F`
// item 3; spec `docs/superpowers/specs/2026-10-09-shadow-cache-design.md` §7).
// **Report only, never pinned**: wall-clock time is not a test (CLAUDE.md:
// performance tests count work); the counted work is pinned by
// `RasterAnchorTests` instead.
//
// **Not part of the suite.** `run.sh measure` copies it into a `git archive`
// of each commit at `Tests/MetalUITests/ZZShadowCacheMeasure.swift`, builds in
// release with testing enabled, and runs the one test with
// `METALUI_SHADOW_MEASURE=1`. Without the variable it returns at once. It
// spells only API present at 2155f1e (textures made are counted from the
// scene's texture identities, not `RasterCache.lastTexturesMade`).
//
// MetalCreator's shape (PERF-a): a headless frame loop over a 20-node graph
// at 2× in a 1440 × 900 window, each node a nine-leaf container under
// `.shadow(color:radius: 10)`, one node moving 2 points per frame (whole
// device pixels), 60 frames after one warm-up. Prints the median and mean ms
// per frame and, per frame, the pixels blurred and rasterized and the
// textures made (identities the frame before did not draw).

import Testing
import Foundation
import MetalUICore
import MetalUILayout
@testable import MetalUI

@MainActor private func zzMeasureNode(_ i: Int, moved: Float) -> some Element {
    VStack(spacing: Pixels(2)) {
        RoundedRectangle(cornerRadius: 4).fill(.accent).frame(width: Pixels(110), height: Pixels(16))
        Color(.separator).frame(width: Pixels(100), height: Pixels(8))
        Color(.separator).frame(width: Pixels(80), height: Pixels(8))
        Color(.separator).frame(width: Pixels(100), height: Pixels(8))
        Color(.separator).frame(width: Pixels(60), height: Pixels(8))
        Color(.separator).frame(width: Pixels(90), height: Pixels(8))
        Color(.separator).frame(width: Pixels(50), height: Pixels(8))
        Circle().fill(.accent).frame(width: Pixels(14), height: Pixels(14))
        Text("Node \(i)").font(size: 12)
    }
    .shadow(color: Color(red: 0, green: 0, blue: 0, opacity: 0.3), radius: Pixels(10))
    .padding(Edges(top: Pixels(Float(40 + (i / 5) * 200)), right: Pixels(0), bottom: Pixels(0),
                   left: Pixels(Float(40 + (i % 5) * 270) + moved)))
    .frame(width: Pixels(1440), height: Pixels(900), alignment: .topLeading)
}

@MainActor private func zzMeasureGraph(frame: Int) -> some Element {
    ZStack(alignment: .topLeading) {
        ForEach(0..<20, id: \.self) { i in zzMeasureNode(i, moved: i == 7 ? Float(2 * frame) : 0) }
    }
    .frame(width: Pixels(1440), height: Pixels(900), alignment: .topLeading)
}

@Test @MainActor func zzMeasureShadowCache() throws {
    guard ProcessInfo.processInfo.environment["METALUI_SHADOW_MEASURE"] == "1" else { return }
    let table = StateTable(), store = AnimationStore(), surfaces = SurfaceRegistry()
    var previous: Set<ObjectIdentifier> = []
    var times: [Double] = [], blurred: [Int] = [], rasterized: [Int] = [], made: [Int] = []
    let clock = ContinuousClock()
    for f in 0...60 {
        var root = zzMeasureGraph(frame: f)
        let start = clock.now
        let frame = Frame(contentSize: Size(width: Pixels(1440), height: Pixels(900)), scaleFactor: 2,
                          stateTable: table, timestamp: Double(f) / 60, transaction: nil, animationStore: store,
                          surfaceRegistry: surfaces, collectsAccessibility: false)
        frame.render(&root)
        let elapsed = clock.now - start
        let ids = Set(frame.scene.textures.map { ObjectIdentifier($0) })
        if f > 0 {
            let c = elapsed.components
            times.append(Double(c.seconds) * 1000 + Double(c.attoseconds) / 1e15)
            blurred.append(store.rasters.lastBlurredPixels)
            rasterized.append(store.rasters.lastRasterizedPixels)
            made.append(ids.subtracting(previous).count)
        }
        previous = ids
    }
    let sorted = times.sorted()
    let median = (sorted[29] + sorted[30]) / 2
    let mean = times.reduce(0, +) / Double(times.count)
    print("SHADOWMEASURE frames \(times.count) median \(String(format: "%.2f", median)) ms mean \(String(format: "%.2f", mean)) ms")
    print("SHADOWMEASURE per frame (frames 2…): blurred \(Set(blurred.dropFirst()).sorted()) rasterized \(Set(rasterized.dropFirst()).sorted()) made \(Set(made.dropFirst()).sorted())")
    print("SHADOWMEASURE frame 1: blurred \(blurred[0]) rasterized \(rasterized[0]) made \(made[0])")
}
