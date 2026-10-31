import Foundation
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
    /// What the build's lazy containers realised (`LZ-I`): units, lines, and containers that realised everything.
    package var lazyUnitsRealized = 0
    package var lazyLinesRealized = 0
    package var lazyUnbounded = 0
}

extension Window {
    /// How many times the window computed its drag regions (`CW-J`: a platform that declines them, and a
    /// standard-style window with no handle, cost none).
    package var testingChromeCarveCount: Int { chromeCarveCount }

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
                               retained: memos?.lastRetained ?? RetainedCounters(),
                               lazyUnitsRealized: frame.lazyWork.unitsRealized,
                               lazyLinesRealized: frame.lazyWork.linesRealized,
                               lazyUnbounded: frame.lazyWork.unbounded))
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

// C14b-2 (`RK-`): read-backs for the prepaint-replay differentials.
extension Window {
    /// Whether `.equatable()` occurrences replay their prepaint (`RK-E`); off is the paint-only replay of
    /// `fb9a7e42`. Independent of ``testingRetainedSubtrees``.
    package var testingRetainedPrepaint: Bool {
        get { stateTable.contentMemos.replaysPrepaint }
        set { stateTable.contentMemos.replaysPrepaint = newValue }
    }

    /// The prepaint ledgers moved to a new position since the window was made (`FS-F`), cumulative.
    package var testingLedgerMoves: Int { stateTable.contentMemos.ledgerMoves }

    /// Whether an occurrence whose layout origin or scroll offset moved replays translated (`FS-D`); off, it misses as it did before
    /// C14-d. Independent of the render-effect translation of `RK-G`, which stays.
    package var testingRetainedTranslation: Bool {
        get { stateTable.contentMemos.translatesLayout }
        set { stateTable.contentMemos.translatesLayout = newValue }
    }

    /// Whether `.equatable()` occurrences skip their build recursion (`RK-B`); off, prepaint and paint replay as at lane 1's tree.
    package var testingRetainedGraft: Bool {
        get { stateTable.contentMemos.graftsBuild }
        set { stateTable.contentMemos.graftsBuild = newValue }
    }

    /// The `@State` entries with their versions and liveness, sorted: compared across two windows by the graft's
    /// sweep differential (`RK-F`).
    package var testingStateEntries: [String] { stateTable.entryDigest }

    /// A write of `value` to the entry at `id` as an input would make it (`RW-`): bumps the version, dirties the window.
    package func testingWriteState<S>(_ id: GlobalElementID, _ value: S) { stateTable.write(id, value) }

    /// The presentation anchors the last frame recorded, sorted, as strings (`RW-K`).
    package var testingPresentationAnchors: [String] {
        lastPresentationAnchors.map { "\($0.key) \($0.value)" }.sorted()
    }

    /// The version of the entry at `id` (0 when absent) and whether it is live (`RW-`).
    package func testingStateVersion(_ id: GlobalElementID) -> UInt64 { stateTable.entryVersion(id) }
    package func testingStateIsLive(_ id: GlobalElementID) -> Bool { stateTable.isLive(id) }

    /// Every field of the last build's hitboxes that is not a closure, in registration order, as one string
    /// each: identity, bounds, layer, opacity, scroll axis, origin, shape, transform, the contextual flag and
    /// which handler members were present (`RK-E`).
    package var testingHitboxFingerprints: [String] {
        lastHitboxes.map(\.fingerprint)
    }

    /// The retained accessibility node of the element behind `id` (the `$ax` slot a declared node writes) and whether
    /// it is live, or `nil` (`AT-A`: a replay writes the recomputed node there too).
    package func testingAXRetainedNode(_ id: GlobalElementID) -> (frame: Bounds<Pixels>, isValid: Bool)? {
        let slot = Frame.axRetentionSlot(for: id)
        guard let node = stateTable.peek(slot, as: AXNode.self) else { return nil }
        return (node.frame, stateTable.isLive(slot))
    }

    /// The last build's region tallies: hover, pointer style, key, focus-on-press, resign (`RK-E`).
    package var testingRegionTallies: [Int] {
        [lastHoverRegionCount, lastPointerStyleRegionCount, lastKeyRegionCount, lastFocusOnPressCount,
         lastResignRegionCount]
    }

    /// The identities that registered a context menu, and the press-only accessibility actions, in the last
    /// build, sorted by description (`RK-E`).
    package var testingContextMenuAndPressOnlyIDs: [String] {
        lastContextMenus.keys.map { "menu \($0)" }.sorted() + lastAccessibilityPressOnly.keys.map { "press \($0)" }.sorted()
    }
}

extension Window {
    /// Damages every stored prepaint ledger in one named channel and answers how many it damaged (`RK-N`): the
    /// exit tests of verify mode need a replay that differs from a fresh prepaint to see it trap.
    @discardableResult
    package func testingCorruptPrepaintLedgers(_ channel: String) -> Int {
        stateTable.contentMemos.mutatePrepaintLedgers { ledger in
            switch channel {
            case "hitboxes": ledger.hitboxes.reverse(); if ledger.hitboxes.count > 1 { ledger.hitboxes.removeLast() }
            case "tallies": ledger.tallies.hover += 1
            case "focus": ledger.focus.removeAll()
            case "accessibility": ledger.axEmissions.removeAll()
            case "elementBounds": ledger.elementBounds.removeAll()
            case "contextMenus": ledger.contextMenus.removeAll()
            case "pressOnly": ledger.pressOnly.removeAll()
            default: preconditionFailure("unknown ledger channel \(channel)")
            }
        }
    }
}

extension Window {
    /// Damages every stored graft record in one named channel and answers how many it damaged (`RK-N`): the exit tests of
    /// verify mode need a graft that differs from a build to see it trap. Channels: `marks`, `produced`, `named`,
    /// `loops`, `memoTouches` (calls dropped from the journal) and `leafKeys` (dropped from the rows).
    @discardableResult
    package func testingCorruptGraftRecords(_ channel: String) -> Int {
        stateTable.contentMemos.mutateGraftRecords { graft in
            switch channel {
            case "marks": graft.events.removeAll { if case .mark = $0 { true } else { false } }
            case "produced": graft.events.removeAll { if case .produced = $0 { true } else { false } }
            case "named": graft.events.removeAll { if case .named = $0 { true } else { false } }
            case "loops": graft.events.removeAll { if case .loop = $0 { true } else { false } }
            case "lifecycleNotes": graft.events.removeAll { if case .lifecycleNote = $0 { true } else { false } }
            case "memoTouches": graft.events.removeAll { if case .memoTouch = $0 { true } else { false } }
            case "leafKeys": graft.segment = graft.segment.testingDroppingLeafKeys()
            default: preconditionFailure("unknown graft channel \(channel)")
            }
        }
    }

    /// Calls `body` on every stored graft record and answers how many there were (internal tests only).
    @discardableResult
    func testingStoredGraftRecords(_ body: (GraftRecord) -> Void) -> Int {
        stateTable.contentMemos.mutateGraftRecords(body)
    }

    /// Why occurrences left no graft record in the last build, one name each (`RK-F`).
    package var testingGraftRefusals: [String] { stateTable.contentMemos.lastGraftRefusals }
}

extension Window {
    /// Calls `body` on every stored prepaint ledger and answers how many there were (`RK-O` item 1's scan, internal tests only).
    @discardableResult
    func testingStoredPrepaintLedgers(_ body: (PrepaintLedger) -> Void) -> Int {
        stateTable.contentMemos.mutatePrepaintLedgers(body)
    }
}

extension Window {
    /// The seconds the window's `TimelineView` clock adds to a frame timestamp (`KF-K` item 4), `nil`
    /// until the window's first non-zero tick anchors it to the real wall clock (`KF-Y`). A test that
    /// compares two windows' timelines pins both (`RK-AD`): the anchor is read from `Date()` per window.
    package var testingTimelineClockOffset: Double? {
        get { animationStore.timeline.clockOffset }
        set {
            animationStore.timeline.clockOffset = newValue
            // The first frame (timestamp 0) read the wall clock and anchored every cursor on it (`RK-AE`).
            animationStore.timeline.resetCursors()
        }
    }
}

extension Window {
    /// Puts the window's `TimelineView` clock on the harness's simulated one (`DX-A`): dates are `anchor` plus the
    /// frame timestamp, and a periodic timeline's wake waits for ``testingFireDueTimelineWake(atTimestamp:)`` instead
    /// of sleeping on the wall clock.
    package func testingSimulateTimelineClock(anchor: Date) {
        animationStore.timeline.useSimulatedClock(anchor: anchor)
    }

    /// Fires the timeline wake if the simulated clock has reached it (`DX-A`).
    package func testingFireDueTimelineWake(atTimestamp timestamp: Double) {
        animationStore.timeline.fireDueSimulatedWake(atTimestamp: timestamp)
    }
}
