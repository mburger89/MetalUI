import MetalUIPlatform

// The test harness's read-back (ruling `HT-C` item 2): `package` members, in a
// file of their own, that `MetalUITesting` reads and an app cannot spell —
// `package` is unspellable outside this package (guard 3.2). Nothing here
// changes behaviour: each member reads or sets state `Window`/`App` already
// keep for test observability. **The harness owns `Window.onFrameAdopted` for
// the windows it opens** (`HT-C` item 4); nothing else in `Sources/` sets it.

/// One build's work, handed to ``Window/testingOnFrameAdopted(_:)`` after the
/// build is adopted (ruling `HT-I`): the root layout run's counts (`SA-M`)
/// and the window's CPU raster counters for the build (`GX-K`). A value, so
/// `Frame` stays internal.
package struct BuildWork: Sendable, Equatable {
    /// Leaf and custom `sizeThatFits` calls in the root's layout run.
    package var measureCalls: Int
    /// Cache hits in that run.
    package var cacheHits: Int
    /// Cache misses in that run.
    package var cacheMisses: Int
    /// Device pixels the build rasterized (`RasterCache.lastRasterizedPixels`).
    package var rasterizedPixels: Int
    /// Device pixels the build blurred (`RasterCache.lastBlurredPixels`).
    package var blurredPixels: Int
    /// Keyed memo lookups the root's layout run answered (`IV-E`).
    package var memoHits = 0
    /// Keyed memo lookups it could not answer.
    package var memoMisses = 0
    /// Root runs whose whole placement the memo restored.
    package var memoRootHits = 0
    /// Marked subtrees whose placement the memo restored (`SB-AD`).
    package var memoSubtreeHits = 0
    /// Nodes the run's signature pass hashed (`IV-M`).
    package var signatureNodesHashed = 0
    /// `content` getters the build's memoized components evaluated (`IV-B`).
    package var contentEvaluations = 0
    /// Getters a memo skipped.
    package var contentSkips = 0
    /// Memoized components refused (`@Environment`/`@FocusState`) and evaluated.
    package var contentRefusals = 0
    /// Group members the build entered, elements prepainted and painted (`SB-`).
    package var elementRequests = 0
    package var elementPrepaints = 0
    package var elementPaints = 0
    /// The retained-subtree counters of the build (`SB-`).
    package var retained = RetainedCounters()
}

extension Window {
    /// Whether every frame records its element bounds (`recordsElementBounds`).
    package var testingRecordsElementBounds: Bool {
        get { recordsElementBounds }
        set { recordsElementBounds = newValue }
    }

    /// The last build's element bounds, by identity — empty unless
    /// ``testingRecordsElementBounds``. Window content space, logical points.
    package var testingElementBounds: [GlobalElementID: Bounds<Pixels>] { lastElementBounds }

    /// Calls `observer` with each build's ``BuildWork`` after the build is
    /// adopted; `nil` removes it. Sets `onFrameAdopted`, which the harness owns.
    package func testingOnFrameAdopted(_ observer: (@MainActor (BuildWork) -> Void)?) {
        guard let observer else {
            onFrameAdopted = nil
            return
        }
        onFrameAdopted = { [weak self] frame in
            let work = frame.tree.lastNativeLayoutWork
            let rasters = self?.animationStore.rasters
            let memos = self?.stateTable.contentMemos
            observer(BuildWork(measureCalls: work.measureCalls, cacheHits: work.cacheHits,
                               cacheMisses: work.cacheMisses,
                               rasterizedPixels: rasters?.lastRasterizedPixels ?? 0,
                               blurredPixels: rasters?.lastBlurredPixels ?? 0,
                               memoHits: work.memoHits, memoMisses: work.memoMisses,
                               memoRootHits: work.memoRootHits,
                               memoSubtreeHits: work.memoSubtreeHits,
                               signatureNodesHashed: work.signatureNodesHashed,
                               contentEvaluations: memos?.lastEvaluations ?? 0,
                               contentSkips: memos?.lastSkips ?? 0,
                               contentRefusals: memos?.lastRefusals ?? 0,
                               elementRequests: frame.elementRequests,
                               elementPrepaints: frame.elementPrepaints,
                               elementPaints: frame.elementPaints,
                               retained: memos?.lastRetained ?? RetainedCounters()))
        }
    }
}

extension Window {
    /// The window's layout memo (`IV-E`), for the harness and the memo's tests.
    package var testingLayoutMemo: LayoutMemo { animationStore.layoutMemo }

    /// The window's content memos (`IV-B`), for the harness and the memo's tests.
    package var testingContentMemos: ContentMemoStore { stateTable.contentMemos }

    /// Whether `.equatable()` occurrences retain and replay their paint (`SB-B`); off is
    /// the memo-off arm of the differentials.
    package var testingRetainedSubtrees: Bool {
        get { stateTable.contentMemos.retainsSubtrees }
        set { stateTable.contentMemos.retainsSubtrees = newValue }
    }
}

extension Window {
    /// The focused text field's marked text and its selection within it
    /// (`TextEditState.composition`), `nil` when nothing is focused, the focus
    /// is not a text target or nothing is marked (ruling `IM-D`). Read-only.
    package var testingComposition: TextComposition? {
        guard let id = focusedElement, lastFocusRegistry.textTarget(for: id) != nil else { return nil }
        var composition = TextComposition.none
        stateTable.withState(id, initial: TextEditState()) { composition = $0.composition }
        return composition.text.isEmpty ? nil : composition
    }
}

extension App {
    /// The open window whose platform window is `platformWindow`, by identity
    /// — found from the renderer's first `beginFrame()`, since `openWindow`
    /// appends the window before drawing its first frame (`HT-R` item 1).
    package func testingWindow(for platformWindow: any PlatformWindow) -> Window? {
        windows.first { $0.platformWindow === platformWindow }
    }

    /// Whether `App(platform:textSystem:)` has a text system to fall back on
    /// when given none: CoreText, on Apple platforms only (ruling `HT-J`).
    package static var hasDefaultTextSystem: Bool {
        #if canImport(MetalUIText)
        true
        #else
        false
        #endif
    }
}

extension Window {
    /// The last build's hitbox list in registration order (`IV-J`): the owning
    /// identity, its window-space bounds after offsets and clips, its layer and
    /// whether it is opaque. Read-only; for the differential tests.
    package var testingHitboxes: [(id: GlobalElementID, bounds: Bounds<Pixels>, layer: Int, opaque: Bool)] {
        lastHitboxes.map { ($0.id, $0.bounds, $0.layer, $0.opaque) }
    }

    /// The last build's Tab order (`IV-J`).
    package var testingTabOrder: [GlobalElementID] { lastFocusRegistry.tabOrder }
}
