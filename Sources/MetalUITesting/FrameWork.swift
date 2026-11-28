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
    /// `.equatable()` components refused for an `@Environment` reading that cannot be compared
    /// and evaluated anyway (divergence 346; a `@FocusState` is memoized by its slot since `RZ-I`).
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
    /// Redos that asked for a redo again and were built a third time with every replay off (`RK-AM`); 0 across the suite.
    public var retainedRedoEscalations: Int
    /// Builds that ran with prepaint replay suspended after a redo (`RK-D`).
    public var retainedBackoffFrames: Int
    /// Occurrences replayed at a translated position (`RK-G`).
    public var retainedTranslated: Int
    /// Occurrences that moved by a translation the gate refused, and missed (`RK-G`).
    public var retainedTranslationRefused: Int
    /// `.equatable()` occurrences whose build recursion did not run: their layout rows were copied and the build's calls
    /// on the state table applied again (`RK-B`, `RK-F`).
    public var retainedGrafts: Int
    /// Occurrences that built and could leave no graft record (`RK-F`).
    public var retainedGraftIneligible: Int
    /// The element requests the grafts stood for: ``elementRequests`` plus this is what a frame with no grafts counts
    /// (`RK-K`).
    public var retainedSkippedRequests: Int
    /// The layout nodes the grafts appended instead of registering.
    public var retainedGraftedNodes: Int
    /// The graft records the end of the frame copied rows for (`RK-AG`): an occurrence whose paint or prepaint left no record
    /// a later frame could graft with is not copied.
    public var retainedGraftCaptures: Int
    /// The occurrences that built and whose graft record was not made for that reason (`RK-AG`).
    public var retainedGraftCapturesSkipped: Int
    /// The ineligible counts (``retainedIneligible``, ``retainedPrepaintIneligible`` and ``retainedGraftIneligible``)
    /// summed by the name of the channel that refused, as `METALUI_TRACE_RETAINED=1` prints it (`stateWrite`, `surface`,
    /// `presentationAnchor`, ...): one entry per refusal, so an occurrence refused at paint, prepaint and graft counts
    /// three times. Empty when nothing was refused (`RW-M`).
    public var retainedIneligibleReasons: [String: Int]
    /// ``retainedTranslationRefused`` summed by the name of the gate that refused (`FS-F`): `accessibilityRecords`,
    /// `hitboxes`, `inexactTranslation`, `fractionalTranslation`, `maskCrossingChanged`, `unlistedKind:<kind>`, ...
    /// One entry per refusal; empty when nothing was refused (`FS-J`).
    public var retainedTranslationRefusedReasons: [String: Int]
    /// Units (children) the build's lazy containers realised: a `LazyVStack` or `LazyHStack` in a scroller
    /// along its axis realises the viewport and two on each side, every child otherwise (`LZ-I`).
    public var lazyUnitsRealized: Int
    /// Lines the lazy containers realised: a stack's children, a grid's rows (`LZ-I`).
    public var lazyLinesRealized: Int
    /// Lazy containers that realised everything: outside a scroller, in one of the other axis, under a `Deferred`,
    /// or holding an `if`, `switch` or `for` member (`LZ-I`).
    public var lazyUnbounded: Int
    /// Reads of an `OutlineGroup`'s `children` key path (`OG-K`): the rows' own (leaf or group) at a rebuild, an expanded
    /// group's and each row of the last window's at a validation. A collapsed group's contents are never read.
    public var outlineChildrenReads: Int
    /// Outline indexes rebuilt: once on the frame after an expansion or the data changes, never on a scroll (`OG-K`).
    public var outlineIndexRebuilds: Int
    /// Outline index validations: the root, each expanded group and each row of the last window (`OG-K`).
    public var outlineIndexValidations: Int
    /// A content `List`'s flatten (`OG-O`): row bodies, `ForEach` closures and group contents it evaluated.
    public var outlineContentEvaluations: Int
    /// Content flattens run (a cache miss, or a list the cache refuses).
    public var outlineContentRebuilds: Int
    /// Content flattens the cache stood in for: no row body, no `ForEach` closure below the top level (`OG-O`).
    public var outlineContentHits: Int
    /// Top-level `ForEach` closures called to compare the list's own content with the cache's.
    public var outlineContentChecks: Int
    /// Lines the `CodeView`s shaped: a miss in the two-frame line-layout cache (`CV-M`). A scroll shapes the
    /// rows that entered; a warm frame shapes none.
    public var codeLinesShaped: Int
    /// Rows the `CodeView`s painted: those intersecting the viewport.
    public var codeLinesPainted: Int
    /// Glyph sprites the `CodeView`s emitted for their text.
    public var codeGlyphsEmitted: Int
    /// Highlight runs the `CodeView`s' line styling visited.
    public var codeHighlightRunsVisited: Int
    /// Find matches the `CodeView`s' paint looked at: those in the shown rows, so a view of 10 000 matches visits
    /// the handful in the viewport (`CV-AE`).
    public var codeFindMatchesVisited: Int
    /// Selections the `CodeView`s' paint looked at: those touching the shown rows and a binary search's probes, so a
    /// view of 10 000 selections visits the handful in the viewport (`CV-BG`).
    public var codeSelectionsVisited: Int
    /// Rows the `Table`s realised: the window, never the data's count (`TBL-M`).
    public var tableRowsRealized: Int
    /// Body cells the `Table`s realised, frozen ones included and header cells excluded (`TBL-M`).
    public var tableCellsRealized: Int
    /// Column specs the `Table`s resolved: one per column per build (`TBL-M`).
    public var tableColumnsResolved: Int
    /// Calls the `Table`s made to `data[i]`: one per realised row per build (`TBL-M`).
    public var tableDataReads: Int
    /// Builds in which a `Table` planned cold, its viewport not yet known (`TBL-M`).
    public var tableColdFrames: Int
    /// Mask scopes the frame pushed, prepaint and paint together (`CM-A`, `CM-B`): one per clip that is drawn as an offscreen
    /// group multiplied by its shape instead of as the square box of its bounds. 0 for a tree with no crossing rounded clip and
    /// no shape-clipped group (an ellipse or path clip), so a nonzero value is a full masked group a guard can refuse.
    public var maskScopesPushed: Int
    /// Offscreen groups the frame multiplied by a shape clip (`CM-A`, `CM-B`): the groups a mask scope's leaves became, none for
    /// a scope that held a backdrop or exceeded the target limit. 0 for a tree with no crossing rounded clip and no
    /// shape-clipped group.
    public var groupsMasked: Int
    /// Group members the abandoned attempts of a redone frame entered (record 441): ``elementRequests`` is the adopted attempt's alone, so ``elementRequests`` + this is what the frame's builds did. 0 for a frame that was not redone.
    public var redoneElementRequests: Int {
        get { redone?.elementRequests ?? 0 }
        set { updateRedone(\.elementRequests, newValue) }
    }
    /// Elements the abandoned attempts of a redone frame prepainted (record 441): ``elementPrepaints`` counts the adopted attempt alone, which on a redo that replays the rest of the frame is far below a neighbouring frame's, so compare ``elementPrepaints`` + this. 0 for a frame that was not redone.
    public var redoneElementPrepaints: Int {
        get { redone?.elementPrepaints ?? 0 }
        set { updateRedone(\.elementPrepaints, newValue) }
    }
    /// Elements the abandoned attempts of a redone frame painted (record 441): ``elementPaints`` + this is the paint work of every attempt. 0 for a frame that was not redone.
    public var redoneElementPaints: Int {
        get { redone?.elementPaints ?? 0 }
        set { updateRedone(\.elementPaints, newValue) }
    }
    /// `sizeThatFits` calls in the root layout runs of the abandoned attempts of a redone frame (record 441), beside ``layoutMeasureCalls``, which is the adopted attempt's. 0 for a frame that was not redone.
    public var redoneLayoutMeasureCalls: Int {
        get { redone?.layoutMeasureCalls ?? 0 }
        set { updateRedone(\.layoutMeasureCalls, newValue) }
    }
    /// Layout cache hits of the abandoned attempts (record 441), beside ``layoutCacheHits``. 0 for a frame that was not redone.
    public var redoneLayoutCacheHits: Int {
        get { redone?.layoutCacheHits ?? 0 }
        set { updateRedone(\.layoutCacheHits, newValue) }
    }
    /// Layout measurement bodies the abandoned attempts ran (record 441), beside ``layoutCacheMisses``. 0 for a frame that was not redone.
    public var redoneLayoutCacheMisses: Int {
        get { redone?.layoutCacheMisses ?? 0 }
        set { updateRedone(\.layoutCacheMisses, newValue) }
    }
    /// The six `redone` counts, out of line: a frame that was not redone holds `nil` (8 bytes), so a stored record grows by a pointer and an idle frame
    /// allocates nothing (record 441); the harness's history array grows by the same schedule as before the fields existed.
    private var redone: RedoneBox?
    /// Glyph-atlas texels uploaded.
    public var atlasUploadPixels: Int
    /// Image textures the previous frame did not reference.
    public var newTextures: Int
    /// The texels of ``newTextures``.
    public var newTexturePixels: Int
    /// 1 when the frame was a surface-only frame (`TRM-P`): the last scene encoded again, only the surfaces a
    /// `SurfaceRedrawTrigger` invalidated drawn, no build — ``builds`` and ``elementRequests`` are 0.
    public var surfaceOnlyFrames: Int
    /// Rects in the presented scene.
    public var rects: Int
    /// Glyphs in the presented scene.
    public var glyphs: Int
    /// Images in the presented scene.
    public var images: Int

    /// Writes one of the six counts: nothing at all when the value is the one held (a build that was not redone adds 0), so an unredone frame never allocates.
    private mutating func updateRedone(_ field: WritableKeyPath<RedoneWork, Int>, _ value: Int) {
        var counts = redone?.counts ?? RedoneWork()
        guard counts[keyPath: field] != value else { return }
        counts[keyPath: field] = value
        redone = counts == RedoneWork() ? nil : RedoneBox(counts)
    }

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
                retainedPrepaintHits: Int = 0, retainedPrepaintIneligible: Int = 0, retainedRedos: Int = 0, retainedRedoEscalations: Int = 0,
                retainedBackoffFrames: Int = 0, retainedTranslated: Int = 0, retainedTranslationRefused: Int = 0,
                retainedGrafts: Int = 0, retainedGraftIneligible: Int = 0, retainedSkippedRequests: Int = 0,
                retainedGraftedNodes: Int = 0, retainedGraftCaptures: Int = 0, retainedGraftCapturesSkipped: Int = 0,
                retainedIneligibleReasons: [String: Int] = [:],
                retainedTranslationRefusedReasons: [String: Int] = [:],
                lazyUnitsRealized: Int = 0, lazyLinesRealized: Int = 0, lazyUnbounded: Int = 0,
                outlineChildrenReads: Int = 0, outlineIndexRebuilds: Int = 0, outlineIndexValidations: Int = 0,
                outlineContentEvaluations: Int = 0, outlineContentRebuilds: Int = 0, outlineContentHits: Int = 0,
                outlineContentChecks: Int = 0,
                codeLinesShaped: Int = 0, codeLinesPainted: Int = 0, codeGlyphsEmitted: Int = 0,
                codeHighlightRunsVisited: Int = 0, codeFindMatchesVisited: Int = 0, surfaceOnlyFrames: Int = 0,
                codeSelectionsVisited: Int = 0,
                tableRowsRealized: Int = 0, tableCellsRealized: Int = 0, tableColumnsResolved: Int = 0,
                tableDataReads: Int = 0, tableColdFrames: Int = 0,
                maskScopesPushed: Int = 0, groupsMasked: Int = 0,
                redoneElementRequests: Int = 0, redoneElementPrepaints: Int = 0, redoneElementPaints: Int = 0, redoneLayoutMeasureCalls: Int = 0, redoneLayoutCacheHits: Int = 0, redoneLayoutCacheMisses: Int = 0) {
        self.surfaceOnlyFrames = surfaceOnlyFrames
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
        self.retainedRedoEscalations = retainedRedoEscalations
        self.retainedBackoffFrames = retainedBackoffFrames
        self.retainedTranslated = retainedTranslated
        self.retainedTranslationRefused = retainedTranslationRefused
        self.retainedGrafts = retainedGrafts
        self.retainedGraftIneligible = retainedGraftIneligible
        self.retainedSkippedRequests = retainedSkippedRequests
        self.retainedGraftedNodes = retainedGraftedNodes
        self.retainedGraftCaptures = retainedGraftCaptures
        self.retainedGraftCapturesSkipped = retainedGraftCapturesSkipped
        self.retainedIneligibleReasons = retainedIneligibleReasons
        self.retainedTranslationRefusedReasons = retainedTranslationRefusedReasons
        self.lazyUnitsRealized = lazyUnitsRealized
        self.lazyLinesRealized = lazyLinesRealized
        self.lazyUnbounded = lazyUnbounded
        self.outlineChildrenReads = outlineChildrenReads
        self.outlineIndexRebuilds = outlineIndexRebuilds
        self.outlineIndexValidations = outlineIndexValidations
        self.outlineContentEvaluations = outlineContentEvaluations
        self.outlineContentRebuilds = outlineContentRebuilds
        self.outlineContentHits = outlineContentHits
        self.outlineContentChecks = outlineContentChecks
        self.codeLinesShaped = codeLinesShaped
        self.codeLinesPainted = codeLinesPainted
        self.codeGlyphsEmitted = codeGlyphsEmitted
        self.codeHighlightRunsVisited = codeHighlightRunsVisited
        self.codeFindMatchesVisited = codeFindMatchesVisited
        self.codeSelectionsVisited = codeSelectionsVisited
        self.tableRowsRealized = tableRowsRealized
        self.tableCellsRealized = tableCellsRealized
        self.tableColumnsResolved = tableColumnsResolved
        self.tableDataReads = tableDataReads
        self.tableColdFrames = tableColdFrames
        self.maskScopesPushed = maskScopesPushed
        self.groupsMasked = groupsMasked
        let redoneCounts = RedoneWork(elementRequests: redoneElementRequests, elementPrepaints: redoneElementPrepaints, elementPaints: redoneElementPaints,
                                      layoutMeasureCalls: redoneLayoutMeasureCalls, layoutCacheHits: redoneLayoutCacheHits, layoutCacheMisses: redoneLayoutCacheMisses)
        redone = redoneCounts == RedoneWork() ? nil : RedoneBox(redoneCounts)
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
                  retainedRedoEscalations: l.retainedRedoEscalations + r.retainedRedoEscalations,
                  retainedBackoffFrames: l.retainedBackoffFrames + r.retainedBackoffFrames,
                  retainedTranslated: l.retainedTranslated + r.retainedTranslated,
                  retainedTranslationRefused: l.retainedTranslationRefused + r.retainedTranslationRefused,
                  retainedGrafts: l.retainedGrafts + r.retainedGrafts,
                  retainedGraftIneligible: l.retainedGraftIneligible + r.retainedGraftIneligible,
                  retainedSkippedRequests: l.retainedSkippedRequests + r.retainedSkippedRequests,
                  retainedGraftedNodes: l.retainedGraftedNodes + r.retainedGraftedNodes,
                  retainedGraftCaptures: l.retainedGraftCaptures + r.retainedGraftCaptures,
                  retainedGraftCapturesSkipped: l.retainedGraftCapturesSkipped + r.retainedGraftCapturesSkipped,
                  retainedIneligibleReasons: l.retainedIneligibleReasons.merging(r.retainedIneligibleReasons, uniquingKeysWith: +),
                  retainedTranslationRefusedReasons: l.retainedTranslationRefusedReasons.merging(r.retainedTranslationRefusedReasons, uniquingKeysWith: +),
                  lazyUnitsRealized: l.lazyUnitsRealized + r.lazyUnitsRealized,
                  lazyLinesRealized: l.lazyLinesRealized + r.lazyLinesRealized,
                  lazyUnbounded: l.lazyUnbounded + r.lazyUnbounded,
                  outlineChildrenReads: l.outlineChildrenReads + r.outlineChildrenReads,
                  outlineIndexRebuilds: l.outlineIndexRebuilds + r.outlineIndexRebuilds,
                  outlineIndexValidations: l.outlineIndexValidations + r.outlineIndexValidations,
                  outlineContentEvaluations: l.outlineContentEvaluations + r.outlineContentEvaluations,
                  outlineContentRebuilds: l.outlineContentRebuilds + r.outlineContentRebuilds,
                  outlineContentHits: l.outlineContentHits + r.outlineContentHits,
                  outlineContentChecks: l.outlineContentChecks + r.outlineContentChecks,
                  codeLinesShaped: l.codeLinesShaped + r.codeLinesShaped,
                  codeLinesPainted: l.codeLinesPainted + r.codeLinesPainted,
                  codeGlyphsEmitted: l.codeGlyphsEmitted + r.codeGlyphsEmitted,
                  codeHighlightRunsVisited: l.codeHighlightRunsVisited + r.codeHighlightRunsVisited,
                  codeFindMatchesVisited: l.codeFindMatchesVisited + r.codeFindMatchesVisited,
                  surfaceOnlyFrames: l.surfaceOnlyFrames + r.surfaceOnlyFrames,
                  codeSelectionsVisited: l.codeSelectionsVisited + r.codeSelectionsVisited,
                  tableRowsRealized: l.tableRowsRealized + r.tableRowsRealized,
                  tableCellsRealized: l.tableCellsRealized + r.tableCellsRealized,
                  tableColumnsResolved: l.tableColumnsResolved + r.tableColumnsResolved,
                  tableDataReads: l.tableDataReads + r.tableDataReads,
                  tableColdFrames: l.tableColdFrames + r.tableColdFrames,
                  maskScopesPushed: l.maskScopesPushed + r.maskScopesPushed,
                  groupsMasked: l.groupsMasked + r.groupsMasked,
                  redoneElementRequests: l.redoneElementRequests + r.redoneElementRequests,
                  redoneElementPrepaints: l.redoneElementPrepaints + r.redoneElementPrepaints,
                  redoneElementPaints: l.redoneElementPaints + r.redoneElementPaints,
                  redoneLayoutMeasureCalls: l.redoneLayoutMeasureCalls + r.redoneLayoutMeasureCalls,
                  redoneLayoutCacheHits: l.redoneLayoutCacheHits + r.redoneLayoutCacheHits,
                  redoneLayoutCacheMisses: l.redoneLayoutCacheMisses + r.redoneLayoutCacheMisses)
    }

    /// Adds `rhs` into `lhs` field by field, the compound form of ``+(_:_:)``.
    public static func += (lhs: inout FrameWork, rhs: FrameWork) { lhs = lhs + rhs }
}

/// The six counts of the attempts a redo abandoned (record 441), as ``FrameWork`` holds them.
private struct RedoneWork: Equatable, Sendable {
    var elementRequests = 0, elementPrepaints = 0, elementPaints = 0
    var layoutMeasureCalls = 0, layoutCacheHits = 0, layoutCacheMisses = 0
}

/// ``RedoneWork`` behind one reference, compared by value, so an unredone frame's record carries a nil pointer in place of 48 bytes.
private final class RedoneBox: Equatable, Sendable {
    let counts: RedoneWork
    init(_ counts: RedoneWork) { self.counts = counts }
    var elementRequests: Int { counts.elementRequests }
    var elementPrepaints: Int { counts.elementPrepaints }
    var elementPaints: Int { counts.elementPaints }
    var layoutMeasureCalls: Int { counts.layoutMeasureCalls }
    var layoutCacheHits: Int { counts.layoutCacheHits }
    var layoutCacheMisses: Int { counts.layoutCacheMisses }
    static func == (l: RedoneBox, r: RedoneBox) -> Bool { l === r || l.counts == r.counts }
}
