// One SDL GPU device drawing MetalUI frames: a live `Scene` with its
// `GlyphAtlas` (the Apple Replay, beside the Metal renderer), or a recorded
// `ReplayFixture` (PortableReplay, anywhere SDL3 builds). Both reach the same
// C entry point with the same bytes.
import MetalUIScene
import ReplayFixture
import SDLBridge

public struct ReplayError: Error, CustomStringConvertible {
    public let description: String
    public init(_ description: String) { self.description = description }
}

public final class SDLReplayer {
    private let gpu: OpaquePointer

    /// The portable shader stages in `shaderDirectory` (SPIR-V, MSL or DXIL,
    /// chosen by `driver`: `metal`, `vulkan` or `direct3d12`).
    public init(shaderDirectory: String, driver: String) throws {
        guard let gpu = shaderDirectory.withCString({ replay_create_portable($0, driver) }) else {
            throw ReplayError("SDL create: \(String(cString: replay_error()))")
        }
        self.gpu = gpu
    }

    /// SDL's Metal backend with MetalUI's own MSL, rebound for SDL.
    public init(msl: String) throws {
        guard let gpu = msl.withCString({ replay_create($0) }) else {
            throw ReplayError("SDL create: \(String(cString: replay_error()))")
        }
        self.gpu = gpu
    }

    deinit { replay_destroy(gpu) }

    public var driver: String { String(cString: replay_driver(gpu)) }

    /// Diagnostic arm: nearest atlas filtering, which no longer matches the
    /// linear-filtered Metal reference.
    public func useNearestFilter() throws {
        guard replay_use_nearest_filter(gpu) else {
            throw ReplayError("nearest sampler: \(String(cString: replay_error()))")
        }
    }

    /// Draws a recorded frame; `runs` overrides its draw list (the
    /// painter-order control).
    public func render(_ fixture: ReplayFixture, runs: [FixtureRun]? = nil) throws -> [UInt8] {
        try fixture.rects.withUnsafeBytes { rects in
            try fixture.glyphs.withUnsafeBytes { glyphs in
                try draw(width: fixture.width, height: fixture.height, rects: rects, glyphs: glyphs,
                         runs: runs ?? fixture.runs, atlas: fixture.atlas,
                         atlasWidth: fixture.atlasWidth, atlasHeight: fixture.atlasHeight,
                         projection: fixture.projection)
            }
        }
    }

    /// Draws a finalized scene straight from its arrays, no copy.
    public func render(_ scene: Scene, atlas: GlyphAtlas, width: Int, height: Int,
                       projection: [Float], runs: [FixtureRun]? = nil) throws -> [UInt8] {
        let sceneRuns = runs ?? scene.drawList.map {
            FixtureRun(kind: $0.kind == .glyph ? .glyph : .rect, start: UInt32($0.start), count: UInt32($0.count))
        }
        return try scene.rects.withUnsafeBytes { rects in
            try scene.glyphs.withUnsafeBytes { glyphs in
                try draw(width: UInt32(width), height: UInt32(height), rects: rects, glyphs: glyphs,
                         runs: sceneRuns, atlas: atlas.pixels,
                         atlasWidth: UInt32(atlas.width), atlasHeight: UInt32(atlas.height),
                         projection: projection)
            }
        }
    }

    /// Shows the most recent render in a window for at most `seconds`.
    public func show(seconds: UInt32) throws {
        guard replay_show(gpu, seconds) else { throw ReplayError("SDL window: \(String(cString: replay_error()))") }
    }

    private func draw(width: UInt32, height: UInt32, rects: UnsafeRawBufferPointer, glyphs: UnsafeRawBufferPointer,
                      runs: [FixtureRun], atlas: [UInt8], atlasWidth: UInt32, atlasHeight: UInt32,
                      projection: [Float]) throws -> [UInt8] {
        precondition(projection.count == 16, "projection must be a 4x4 matrix")
        let cRuns = runs.map { ReplayRun(kind: $0.kind.rawValue, start: $0.start, count: $0.count) }
        var output = [UInt8](repeating: 0, count: Int(width) * Int(height) * 4)
        let ok = cRuns.withUnsafeBufferPointer { runBuffer in
            atlas.withUnsafeBufferPointer { atlasBuffer in
                projection.withUnsafeBufferPointer { matrix in
                    replay_render(gpu, width, height,
                        rects.baseAddress, UInt32(rects.count), glyphs.baseAddress, UInt32(glyphs.count),
                        runBuffer.baseAddress, UInt32(cRuns.count),
                        atlasBuffer.baseAddress, atlasWidth, atlasHeight,
                        matrix.baseAddress, &output)
                }
            }
        }
        guard ok else { throw ReplayError("SDL render: \(String(cString: replay_error()))") }
        return output
    }
}
