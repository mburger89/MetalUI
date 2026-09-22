// Replays recorded MetalUI frames through SDL3 GPU and compares each with the
// Metal renderer's pixels stored in the fixture. Imports no Apple framework
// and no MetalUI module: the fixtures are its only link to the renderer.
//
//   PortableReplay <fixture-dir> [--driver metal|vulkan|direct3d12]
//                  [--shaders <dir>] [--dump <dir>] [--nearest] [--show]
import Foundation  // swift-corelibs-foundation off Apple platforms
import ReplayFixture
import SDLBridge

struct ReplayError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

func option(_ name: String) -> String? {
    let arguments = CommandLine.arguments
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

func render(_ fixture: ReplayFixture, runs: [FixtureRun], gpu: OpaquePointer) throws -> [UInt8] {
    let cRuns = runs.map { ReplayRun(kind: $0.kind.rawValue, start: $0.start, count: $0.count) }
    var output = [UInt8](repeating: 0, count: fixture.reference.count)
    let ok = fixture.rects.withUnsafeBytes { rects in
        fixture.glyphs.withUnsafeBytes { glyphs in
            cRuns.withUnsafeBufferPointer { runBuffer in
                fixture.atlas.withUnsafeBufferPointer { atlas in
                    fixture.projection.withUnsafeBufferPointer { projection in
                        replay_render(gpu, fixture.width, fixture.height,
                            rects.baseAddress, UInt32(rects.count), glyphs.baseAddress, UInt32(glyphs.count),
                            runBuffer.baseAddress, UInt32(cRuns.count),
                            atlas.baseAddress, fixture.atlasWidth, fixture.atlasHeight,
                            projection.baseAddress, &output)
                    }
                }
            }
        }
    }
    guard ok else { throw ReplayError("SDL render: \(String(cString: replay_error()))") }
    return output
}

func run() throws {
    let positional = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("--") }
    let optionValues = Set(["--driver", "--shaders", "--dump"].compactMap(option))
    guard let directory = positional.first(where: { !optionValues.contains($0) }) else {
        throw ReplayError("usage: PortableReplay <fixture-dir> [--driver metal|vulkan|direct3d12] [--shaders dir] [--dump dir] [--show]")
    }
    let driver = option("--driver") ?? "metal"
    let shaders = option("--shaders") ?? "Shaders/compiled"

    let names = try FileManager.default.contentsOfDirectory(atPath: directory)
        .filter { $0.hasSuffix(".muireplay") }.sorted()
    guard !names.isEmpty else { throw ReplayError("no .muireplay fixtures in \(directory)") }
    let fixtures = try names.map { name -> ReplayFixture in
        let path = directory + "/" + name
        guard let data = FileManager.default.contents(atPath: path) else { throw ReplayError("cannot read \(path)") }
        do { return try ReplayFixture(decoding: [UInt8](data)) }
        catch { throw ReplayError("\(name): \(error)") }
    }

    guard let gpu = shaders.withCString({ replay_create_portable($0, driver) }) else {
        throw ReplayError("SDL create: \(String(cString: replay_error()))")
    }
    defer { replay_destroy(gpu) }
    // --nearest: diagnostic arm; output no longer matches the linear-filtered reference.
    if CommandLine.arguments.contains("--nearest") {
        guard replay_use_nearest_filter(gpu) else { throw ReplayError("nearest sampler: \(String(cString: replay_error()))") }
        print("atlas filter: nearest (diagnostic)")
    }
    print("SDL GPU driver: \(String(cString: replay_driver(gpu))); fixtures: \(names.count) from \(directory)")

    var parityFailures = 0
    for (name, fixture) in zip(names, fixtures) {
        let pixels = try render(fixture, runs: fixture.runs, gpu: gpu)
        // --dump <dir>: raw BGRA8 of this backend's output, for offline diffing.
        if let dump = option("--dump") {
            FileManager.default.createFile(atPath: dump + "/" + name + ".bgra", contents: Data(pixels))
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
    let mutant = try render(last, runs: last.orderMutatedRuns, gpu: gpu)
    // Count only pixels no rounding explains: a backend may differ by one
    // step on every edge (llvmpipe does, on ~11k pixels a frame).
    let delta = pixelDifference(last.reference, mutant, above: 16)
    guard delta.pixels > 100 else {
        throw ReplayError("broken comparison: draw-order mutation moved \(delta.pixels) pixels, max delta \(delta.maxDelta)")
    }
    let control = "draw-order mutation: pixels off by >16=\(delta.pixels), max channel delta=\(delta.maxDelta) (detected)"
    print(control)

    if CommandLine.arguments.contains("--show") {
        _ = try render(last, runs: last.runs, gpu: gpu)
        guard replay_show(gpu, 30) else { throw ReplayError("SDL window: \(String(cString: replay_error()))") }
    }
    // --dump reports every frame instead of stopping at the first failure.
    print(parityFailures == 0 ? "PASS" : "FAIL: \(parityFailures) frame(s) over tolerance")
    if parityFailures > 0 { exit(1) }
}

do { try run() } catch {
    print("ERROR: \(error)")
    exit(1)
}
