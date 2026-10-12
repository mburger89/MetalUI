/// The work one presented frame did (ruling `HT-I`, M7-b): counted, never
/// timed. A frame may build up to three times (a lifecycle write's settle
/// build, a first-frame scheme change, a drawn toolbar strip appearing); the
/// build counters sum every build of the frame, the renderer counters are the
/// frame's. A benchmark reads these beside its own clock. MetalUI-only (`HT-B`).
public struct FrameWork: Sendable, Equatable {
    /// How many times the frame was built.
    public var builds: Int
    /// Leaf and custom-layout `sizeThatFits` calls in the root's layout runs
    /// (user code; where text shapes).
    public var layoutMeasureCalls: Int
    /// Layout measurements answered from the run's cache.
    public var layoutCacheHits: Int
    /// Layout measurement bodies run, every node kind.
    public var layoutCacheMisses: Int
    /// Device pixels rasterized on the CPU (paths, shadow and blur coverage,
    /// gradients) — cache misses only.
    public var rasterizedPixels: Int
    /// Device pixels blurred on the CPU (shadow and blur misses).
    public var blurredPixels: Int
    /// Glyph-atlas texels uploaded.
    public var atlasUploadPixels: Int
    /// Image textures the previous frame did not reference.
    public var newTextures: Int
    /// The texels of ``newTextures``.
    public var newTexturePixels: Int
    /// Rects in the presented scene.
    public var rects: Int
    /// Glyphs in the presented scene.
    public var glyphs: Int
    /// Images in the presented scene.
    public var images: Int

    /// A record with every count given; all zero by default.
    public init(builds: Int = 0, layoutMeasureCalls: Int = 0, layoutCacheHits: Int = 0,
                layoutCacheMisses: Int = 0, rasterizedPixels: Int = 0, blurredPixels: Int = 0,
                atlasUploadPixels: Int = 0, newTextures: Int = 0, newTexturePixels: Int = 0,
                rects: Int = 0, glyphs: Int = 0, images: Int = 0) {
        self.builds = builds
        self.layoutMeasureCalls = layoutMeasureCalls
        self.layoutCacheHits = layoutCacheHits
        self.layoutCacheMisses = layoutCacheMisses
        self.rasterizedPixels = rasterizedPixels
        self.blurredPixels = blurredPixels
        self.atlasUploadPixels = atlasUploadPixels
        self.newTextures = newTextures
        self.newTexturePixels = newTexturePixels
        self.rects = rects
        self.glyphs = glyphs
        self.images = images
    }

    /// Field-by-field sums: several frames' work as one record.
    public static func + (l: FrameWork, r: FrameWork) -> FrameWork {
        FrameWork(builds: l.builds + r.builds,
                  layoutMeasureCalls: l.layoutMeasureCalls + r.layoutMeasureCalls,
                  layoutCacheHits: l.layoutCacheHits + r.layoutCacheHits,
                  layoutCacheMisses: l.layoutCacheMisses + r.layoutCacheMisses,
                  rasterizedPixels: l.rasterizedPixels + r.rasterizedPixels,
                  blurredPixels: l.blurredPixels + r.blurredPixels,
                  atlasUploadPixels: l.atlasUploadPixels + r.atlasUploadPixels,
                  newTextures: l.newTextures + r.newTextures,
                  newTexturePixels: l.newTexturePixels + r.newTexturePixels,
                  rects: l.rects + r.rects, glyphs: l.glyphs + r.glyphs, images: l.images + r.images)
    }
}
