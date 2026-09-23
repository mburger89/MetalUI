// Replays recorded MetalUI frames through SDL3 GPU and compares each with the
// Metal renderer's pixels stored in the fixture. Imports no Apple framework
// and no MetalUI module: the fixtures are its only link to the renderer.
//
//   PortableReplay <fixture-dir> [--driver metal|vulkan|direct3d12]
//                  [--shaders <dir>] [--dump <dir>] [--expect <n>] [--nearest] [--show]
import Foundation  // swift-corelibs-foundation off Apple platforms
import ReplayFixture
import SDLReplay

func option(_ name: String) -> String? {
    let arguments = CommandLine.arguments
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

func run() throws {
    let positional = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("--") }
    let optionValues = Set(["--driver", "--shaders", "--dump", "--expect"].compactMap(option))
    guard let directory = positional.first(where: { !optionValues.contains($0) }) else {
        throw ReplayError("usage: PortableReplay <fixture-dir> [--driver metal|vulkan|direct3d12] [--shaders dir] [--dump dir] [--show]")
    }
    let driver = option("--driver") ?? "metal"
    let shaders = option("--shaders") ?? "Shaders/compiled"

    let names = try FileManager.default.contentsOfDirectory(atPath: directory)
        .filter { $0.hasSuffix(".muireplay") }.sorted()
    guard !names.isEmpty else { throw ReplayError("no .muireplay fixtures in \(directory)") }
    // --expect <n>: CI states how many frames the recorder writes, so a frame
    // that stops being recorded — frame 4, the portable-text one (PT-G) — fails
    // the replay instead of silently shrinking it.
    if let expected = option("--expect") {
        guard Int(expected) == names.count else {
            throw ReplayError("expected \(expected) fixtures, found \(names.count): \(names)")
        }
    }
    let fixtures = try names.map { name -> ReplayFixture in
        let path = directory + "/" + name
        guard let data = FileManager.default.contents(atPath: path) else { throw ReplayError("cannot read \(path)") }
        do { return try ReplayFixture(decoding: [UInt8](data)) }
        catch { throw ReplayError("\(name): \(error)") }
    }

    let replayer = try SDLReplayer(shaderDirectory: shaders, driver: driver)
    // --nearest: diagnostic arm; output no longer matches the linear-filtered reference.
    if CommandLine.arguments.contains("--nearest") {
        try replayer.useNearestFilter()
        print("atlas filter: nearest (diagnostic)")
    }
    print("SDL GPU driver: \(replayer.driver); fixtures: \(names.count) from \(directory)")

    var parityFailures = 0
    for (name, fixture) in zip(names, fixtures) {
        let pixels = try replayer.render(fixture)
        // --dump <dir>: raw BGRA8 of this backend's output, for offline diffing.
        if let dump = option("--dump") {
            guard FileManager.default.createFile(atPath: dump + "/" + name + ".bgra", contents: Data(pixels)) else {
                throw ReplayError("cannot write \(dump)/\(name).bgra")
            }
        }
        let parity = fixture.parity(of: pixels)
        let line = "\(name) \(fixture.width)x\(fixture.height): \(fixture.rectCount) rects, \(fixture.glyphCount) glyphs, \(fixture.runs.count) runs; outside glyphs: \(parity.outside.pixels) px, max Δ\(parity.outside.maxDelta) (≤\(ParityTolerance.outsideGlyphs)); inside glyphs: \(parity.inside.pixels) px, max Δ\(parity.inside.maxDelta) (≤\(ParityTolerance.insideGlyphs))"
        print(line)
        if !parity.passes {
            parityFailures += 1
            if option("--dump") == nil { throw ReplayError("parity failed: \(line)") }
        }
    }
    // Positive control: the same comparison must see a backend that breaks painter order.
    let last = fixtures[fixtures.count - 1]
    let mutant = try replayer.render(last, runs: last.orderMutatedRuns)
    // Count only pixels no rounding explains: a backend may differ by one
    // step on every edge (llvmpipe does, on ~11k pixels a frame).
    let delta = pixelDifference(last.reference, mutant, above: 16)
    guard delta.pixels > 100 else {
        throw ReplayError("broken comparison: draw-order mutation moved \(delta.pixels) pixels, max delta \(delta.maxDelta)")
    }
    let control = "draw-order mutation: pixels off by >16=\(delta.pixels), max channel delta=\(delta.maxDelta) (detected)"
    print(control)

    if CommandLine.arguments.contains("--show") {
        _ = try replayer.render(last)
        try replayer.show(seconds: 30)
    }
    // --dump reports every frame instead of stopping at the first failure.
    print(parityFailures == 0 ? "PASS" : "FAIL: \(parityFailures) frame(s) over tolerance")
    if parityFailures > 0 { exit(1) }
}

do { try run() } catch {
    print("ERROR: \(error)")
    exit(1)
}
