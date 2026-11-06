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
        let regions = fixture.backdropRegions.map(Self.region)
        let flat = FlatFrame(root: FixtureBody(rects: fixture.rects, glyphs: fixture.glyphs, images: fixture.images,
                                               transforms: fixture.transforms, runs: runs ?? fixture.runs),
                             groups: fixture.groups, groupTextureBase: UInt32(fixture.textures.count))
        return try flat.rects.withUnsafeBytes { rects in
            try flat.glyphs.withUnsafeBytes { glyphs in
                try flat.images.withUnsafeBytes { images in
                  try flat.transforms.withUnsafeBytes { transforms in
                   try fixture.backdrops.withUnsafeBytes { backdrops in
                    try draw(width: fixture.width, height: fixture.height, rects: rects, glyphs: glyphs,
                             images: images, transforms: transforms, backdrops: backdrops, regions: regions,
                             textures: fixture.textures.map { ($0.width, $0.height, $0.pixels) },
                             runs: flat.runs, mainRunCount: flat.mainRunCount, groups: flat.groups,
                             atlas: fixture.atlas,
                             atlasWidth: fixture.atlasWidth, atlasHeight: fixture.atlasHeight,
                             projection: fixture.projection)
                   }
                  }
                }
            }
        }
    }

    /// A region as the bridge reads it: `width` 0 where nothing is left (the
    /// record then draws its flat tint, ruling `BB-I`).
    private static func region(_ region: Scene.BackdropRegion?) -> ReplayRegion {
        guard let region else { return ReplayRegion(x: 0, y: 0, width: 0, height: 0) }
        return ReplayRegion(x: Int32(region.x), y: Int32(region.y), width: Int32(region.width), height: Int32(region.height))
    }

    /// Draws a finalized scene straight from its arrays, no copy (a scene with offscreen groups is flattened with
    /// them, `GO-F`).
    public func render(_ scene: Scene, atlas: GlyphAtlas, width: Int, height: Int,
                       projection: [Float], runs: [FixtureRun]? = nil) throws -> [UInt8] {
        let regions = (0..<scene.backdrops.count).map { Self.region(scene.backdropRegion($0, target: (width, height))) }
        var shared = scene.textures
        let tree = FixtureGroupTree(scene) { texture in
            if let index = shared.firstIndex(where: { $0 === texture }) { return UInt32(index) }
            shared.append(texture)
            return UInt32(shared.count - 1)
        }
        let imageCount = scene.images.count
        let sceneRuns = runs ?? scene.drawList.map { run -> FixtureRun in
            var fixtureRun = FixtureRun(scene: run)
            if run.kind == .group { fixtureRun.start += UInt32(imageCount) }
            return fixtureRun
        }
        let flat = FlatFrame(root: FixtureBody(rects: scene.rects.withUnsafeBytes { Array($0) },
                                               glyphs: scene.glyphs.withUnsafeBytes { Array($0) },
                                               images: scene.images.withUnsafeBytes { Array($0) } + tree.rootQuads.withUnsafeBytes { Array($0) },
                                               transforms: scene.transforms.withUnsafeBytes { Array($0) },
                                               runs: sceneRuns),
                             groups: tree.groups, groupTextureBase: UInt32(shared.count))
        return try flat.rects.withUnsafeBytes { rects in
            try flat.glyphs.withUnsafeBytes { glyphs in
                try flat.images.withUnsafeBytes { images in
                  try flat.transforms.withUnsafeBytes { transforms in
                   try scene.backdrops.withUnsafeBytes { backdrops in
                    try draw(width: UInt32(width), height: UInt32(height), rects: rects, glyphs: glyphs,
                             images: images, transforms: transforms, backdrops: backdrops, regions: regions,
                             textures: shared.map { (UInt32($0.width), UInt32($0.height), $0.pixels) },
                             runs: flat.runs, mainRunCount: flat.mainRunCount, groups: flat.groups,
                             atlas: atlas.pixels,
                             atlasWidth: UInt32(atlas.width), atlasHeight: UInt32(atlas.height),
                             projection: projection)
                   }
                  }
                }
            }
        }
    }

    /// Shows the most recent render in a window for at most `seconds`.
    public func show(seconds: UInt32) throws {
        guard replay_show(gpu, seconds) else { throw ReplayError("SDL window: \(String(cString: replay_error()))") }
    }

    private func draw(width: UInt32, height: UInt32, rects: UnsafeRawBufferPointer, glyphs: UnsafeRawBufferPointer,
                      images: UnsafeRawBufferPointer, transforms: UnsafeRawBufferPointer,
                      backdrops: UnsafeRawBufferPointer, regions: [ReplayRegion],
                      textures: [(UInt32, UInt32, [UInt8])],
                      runs: [FixtureRun], mainRunCount: Int, groups: [FlatGroup],
                      atlas: [UInt8], atlasWidth: UInt32, atlasHeight: UInt32,
                      projection: [Float]) throws -> [UInt8] {
        precondition(projection.count == 16, "projection must be a 4x4 matrix")
        let cRuns = runs.map { ReplayRun(kind: $0.kind.rawValue, start: $0.start, count: $0.count) }
        let cGroups = groups.map {
            ReplayGroup(x: $0.x, y: $0.y, width: $0.width, height: $0.height, run_start: $0.runStart, run_count: $0.runCount)
        }
        var output = [UInt8](repeating: 0, count: Int(width) * Int(height) * 4)
        // Each texture's bytes pinned for the call: `replay_render` copies them.
        func withTextures<R>(_ index: Int, _ built: [ReplayTexture],
                             _ body: ([ReplayTexture]) -> R) -> R {
            guard index < textures.count else { return body(built) }
            let (w, h, pixels) = textures[index]
            return pixels.withUnsafeBufferPointer { bytes in
                withTextures(index + 1, built + [ReplayTexture(rgba: bytes.baseAddress, width: w, height: h)], body)
            }
        }
        let ok = withTextures(0, []) { cTextures in
            cRuns.withUnsafeBufferPointer { runBuffer in
                atlas.withUnsafeBufferPointer { atlasBuffer in
                    projection.withUnsafeBufferPointer { matrix in
                        cTextures.withUnsafeBufferPointer { textureBuffer in
                          regions.withUnsafeBufferPointer { regionBuffer in
                           cGroups.withUnsafeBufferPointer { groupBuffer in
                            replay_render(gpu, width, height,
                                rects.baseAddress, UInt32(rects.count), glyphs.baseAddress, UInt32(glyphs.count),
                                images.baseAddress, UInt32(images.count),
                                transforms.baseAddress, UInt32(transforms.count),
                                backdrops.baseAddress, UInt32(backdrops.count),
                                regionBuffer.baseAddress, UInt32(regionBuffer.count),
                                textureBuffer.baseAddress, UInt32(cTextures.count),
                                runBuffer.baseAddress, UInt32(cRuns.count),
                                atlasBuffer.baseAddress, atlasWidth, atlasHeight,
                                groupBuffer.baseAddress, UInt32(cGroups.count), UInt32(mainRunCount),
                                matrix.baseAddress, &output)
                           }
                          }
                        }
                    }
                }
            }
        }
        guard ok else { throw ReplayError("SDL render: \(String(cString: replay_error()))") }
        return output
    }
}
