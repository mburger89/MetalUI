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
    /// Keyed layout-memo lookups answered without measuring (`IV-E`); not in
    /// ``layoutCacheMisses``.
    public var layoutMemoHits: Int
    /// Keyed layout-memo lookups that missed.
    public var layoutMemoMisses: Int
    /// Root layout runs whose whole placement the memo restored.
    public var layoutMemoRootHits: Int
    /// Marked subtrees (retained `.equatable()` occurrences) whose placement the
    /// memo restored where they stood (`SB-AD`).
    public var layoutSubtreeHits: Int
    /// Nodes the layout runs' signature passes hashed (`IV-M`).
    public var layoutSignatureNodes: Int
    /// Device pixels rasterized on the CPU (paths, shadow and blur coverage,
    /// gradients) — cache misses only.
    public var rasterizedPixels: Int
    /// Device pixels blurred on the CPU (shadow and blur misses).
    public var blurredPixels: Int
    /// `content` getters evaluated by `.equatable()` components (`IV-B`).
    public var contentEvaluations: Int
    /// Getters an `.equatable()` component skipped (value, `@State` and
    /// observed reads unchanged).
    public var contentSkips: Int
    /// `.equatable()` components refused for an `@Environment` or `@FocusState`
    /// and evaluated anyway (divergence 346).
    public var contentRefusals: Int
    /// Group members the build entered (`SB-`): the build recursion's work, which a retained
    /// subtree still pays in full (lane 1).
    public var elementRequests: Int
    /// Elements prepainted: one per element and per modifier layer (a retained subtree prepaints in
    /// full, lane 1).
    public var elementPrepaints: Int
    /// Elements painted: one per element and per modifier layer, replayed ones excluded.
    public var elementPaints: Int
    /// `.equatable()` occurrences whose paint was replayed from a record (`SB-B`).
    public var retainedHits: Int
    /// Occurrences that painted and left a record, or painted because the pointer, a press or focus is
    /// inside them.
    public var retainedMisses: Int
    /// Occurrences that painted and could not be recorded (a paint wrote state, raised an animation,
    /// drew a surface or sat in a context the key cannot hold).
    public var retainedIneligible: Int
    /// Element prepaints a retained hit stood for: always 0 while prepaint runs in full (lane 1).
    public var retainedSkippedPrepaints: Int
    /// Element paints a retained hit stood for: `elementPaints + retainedSkippedPaints` is what the
    /// same frame costs with no retained subtree.
    public var retainedSkippedPaints: Int
    /// Ledger snapshots taken to record occurrences (two per recorded occurrence: before and after its
    /// paint).
    public var retainedLedgerSnapshots: Int
    /// Recorded scene operations replayed.
    public var retainedReplayedOps: Int
    /// `.equatable()` occurrences whose prepaint (hitboxes, focus stops, accessibility records) was
    /// replayed from a record (`RK-E`); each stands for the element prepaints counted in
    /// ``retainedSkippedPrepaints``.
    public var retainedPrepaintHits: Int
    /// Occurrences that prepainted and could not leave a prepaint record (`RK-E`).
    public var retainedPrepaintIneligible: Int
    /// Frames redone because a replayed prepaint met a paint-time ambient that differed (`RK-D`).
    public var retainedRedos: Int
    /// Builds that ran with prepaint replay suspended after a redo (`RK-D`).
    public var retainedBackoffFrames: Int
    /// Occurrences replayed at a translated position (`RK-G`).
    public var retainedTranslated: Int
    /// Occurrences that moved by a translation the gate refused, and missed (`RK-G`).
    public var retainedTranslationRefused: Int
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
                layoutCacheMisses: Int = 0, layoutMemoHits: Int = 0, layoutMemoMisses: Int = 0,
                layoutMemoRootHits: Int = 0, layoutSubtreeHits: Int = 0, layoutSignatureNodes: Int = 0, rasterizedPixels: Int = 0, blurredPixels: Int = 0,
                atlasUploadPixels: Int = 0, newTextures: Int = 0, newTexturePixels: Int = 0,
                rects: Int = 0, glyphs: Int = 0, images: Int = 0,
                contentEvaluations: Int = 0, contentSkips: Int = 0, contentRefusals: Int = 0,
                elementRequests: Int = 0, elementPrepaints: Int = 0, elementPaints: Int = 0,
                retainedHits: Int = 0, retainedMisses: Int = 0, retainedIneligible: Int = 0,
                retainedSkippedPrepaints: Int = 0, retainedSkippedPaints: Int = 0,
                retainedLedgerSnapshots: Int = 0, retainedReplayedOps: Int = 0,
                retainedPrepaintHits: Int = 0, retainedPrepaintIneligible: Int = 0, retainedRedos: Int = 0,
                retainedBackoffFrames: Int = 0, retainedTranslated: Int = 0, retainedTranslationRefused: Int = 0) {
        self.builds = builds
        self.layoutMeasureCalls = layoutMeasureCalls
        self.layoutCacheHits = layoutCacheHits
        self.layoutCacheMisses = layoutCacheMisses
        self.layoutMemoHits = layoutMemoHits
        self.layoutMemoMisses = layoutMemoMisses
        self.layoutMemoRootHits = layoutMemoRootHits
        self.layoutSubtreeHits = layoutSubtreeHits
        self.layoutSignatureNodes = layoutSignatureNodes
        self.rasterizedPixels = rasterizedPixels
        self.blurredPixels = blurredPixels
        self.atlasUploadPixels = atlasUploadPixels
        self.newTextures = newTextures
        self.newTexturePixels = newTexturePixels
        self.rects = rects
        self.glyphs = glyphs
        self.images = images
        self.contentEvaluations = contentEvaluations
        self.contentSkips = contentSkips
        self.contentRefusals = contentRefusals
        self.elementRequests = elementRequests
        self.elementPrepaints = elementPrepaints
        self.elementPaints = elementPaints
        self.retainedHits = retainedHits
        self.retainedMisses = retainedMisses
        self.retainedIneligible = retainedIneligible
        self.retainedSkippedPrepaints = retainedSkippedPrepaints
        self.retainedSkippedPaints = retainedSkippedPaints
        self.retainedLedgerSnapshots = retainedLedgerSnapshots
        self.retainedReplayedOps = retainedReplayedOps
        self.retainedPrepaintHits = retainedPrepaintHits
        self.retainedPrepaintIneligible = retainedPrepaintIneligible
        self.retainedRedos = retainedRedos
        self.retainedBackoffFrames = retainedBackoffFrames
        self.retainedTranslated = retainedTranslated
        self.retainedTranslationRefused = retainedTranslationRefused
    }

    /// Field-by-field sums: several frames' work as one record.
    public static func + (l: FrameWork, r: FrameWork) -> FrameWork {
        FrameWork(builds: l.builds + r.builds,
                  layoutMeasureCalls: l.layoutMeasureCalls + r.layoutMeasureCalls,
                  layoutCacheHits: l.layoutCacheHits + r.layoutCacheHits,
                  layoutCacheMisses: l.layoutCacheMisses + r.layoutCacheMisses,
                  layoutMemoHits: l.layoutMemoHits + r.layoutMemoHits,
                  layoutMemoMisses: l.layoutMemoMisses + r.layoutMemoMisses,
                  layoutMemoRootHits: l.layoutMemoRootHits + r.layoutMemoRootHits,
                  layoutSubtreeHits: l.layoutSubtreeHits + r.layoutSubtreeHits,
                  layoutSignatureNodes: l.layoutSignatureNodes + r.layoutSignatureNodes,
                  rasterizedPixels: l.rasterizedPixels + r.rasterizedPixels,
                  blurredPixels: l.blurredPixels + r.blurredPixels,
                  atlasUploadPixels: l.atlasUploadPixels + r.atlasUploadPixels,
                  newTextures: l.newTextures + r.newTextures,
                  newTexturePixels: l.newTexturePixels + r.newTexturePixels,
                  rects: l.rects + r.rects, glyphs: l.glyphs + r.glyphs, images: l.images + r.images,
                  contentEvaluations: l.contentEvaluations + r.contentEvaluations,
                  contentSkips: l.contentSkips + r.contentSkips,
                  contentRefusals: l.contentRefusals + r.contentRefusals,
                  elementRequests: l.elementRequests + r.elementRequests,
                  elementPrepaints: l.elementPrepaints + r.elementPrepaints,
                  elementPaints: l.elementPaints + r.elementPaints,
                  retainedHits: l.retainedHits + r.retainedHits,
                  retainedMisses: l.retainedMisses + r.retainedMisses,
                  retainedIneligible: l.retainedIneligible + r.retainedIneligible,
                  retainedSkippedPrepaints: l.retainedSkippedPrepaints + r.retainedSkippedPrepaints,
                  retainedSkippedPaints: l.retainedSkippedPaints + r.retainedSkippedPaints,
                  retainedLedgerSnapshots: l.retainedLedgerSnapshots + r.retainedLedgerSnapshots,
                  retainedReplayedOps: l.retainedReplayedOps + r.retainedReplayedOps,
                  retainedPrepaintHits: l.retainedPrepaintHits + r.retainedPrepaintHits,
                  retainedPrepaintIneligible: l.retainedPrepaintIneligible + r.retainedPrepaintIneligible,
                  retainedRedos: l.retainedRedos + r.retainedRedos,
                  retainedBackoffFrames: l.retainedBackoffFrames + r.retainedBackoffFrames,
                  retainedTranslated: l.retainedTranslated + r.retainedTranslated,
                  retainedTranslationRefused: l.retainedTranslationRefused + r.retainedTranslationRefused)
    }
}
