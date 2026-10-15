import Foundation
import Observation

// C14 lane 2 (`IV-B`…`IV-D`, `IV-L`): the window's content memos.

/// A liveness token for one memo session — `RedrawSentinel`'s trick, one per
/// memoized component: read inside the session, and written (the entry's serial
/// bumped first) before the next evaluation, so the previous session fires and is
/// removed instead of accumulating.
@Observable
final class ContentMemoToken {
    var tick: Int = 0
}

/// The `onChange` side of one memo session, `Sendable` so the observation
/// machinery can call it on any thread. Holds the entry and the store **weakly**
/// (`IV-S`): the closure lives in the observed model's registrar and the entry's
/// pristine content holds the model, so a strong hold is a cycle nothing breaks.
private final class ContentMemoHandle: @unchecked Sendable {
    weak var entry: ContentMemoStore.Entry?
    weak var store: ContentMemoStore?
    let serial: Int

    init(entry: ContentMemoStore.Entry, store: ContentMemoStore, serial: Int) {
        self.entry = entry
        self.store = store
        self.serial = serial
    }

    /// Both branches of `Window.markDirtyFromObservation` (`IV-C` item 2): a
    /// main-thread change is handled synchronously — load-bearing for the token
    /// write that retires the previous session — an off-thread one costs a hop.
    func fire() {
        if Thread.isMainThread {
            MainActor.assumeIsolated { self.fireOnMain() }
        } else {
            Task { @MainActor in self.fireOnMain() }
        }
    }

    @MainActor private func fireOnMain() {
        guard let store else { return }
        store.armed -= 1
        // A serial the entry has moved past is a flush (the token write before a
        // re-evaluation, or an entry that left the tree): nothing changed.
        guard let entry, entry.serial == serial else { return }
        entry.stale = true
        store.markDirty?()
    }
}

/// The window's `Component.equatable()` memos (`IV-B`), hosted on `StateTable`
/// and swept with it. One entry per memoized component occurrence, keyed by its
/// identity and its type. On an equal value, with the component's own `@State`
/// versions unchanged and no observed read changed, ``materialize`` hands back
/// the pristine content of the last evaluation instead of running the getter.
@MainActor
package final class ContentMemoStore {
    struct Key: Hashable {
        let id: GlobalElementID
        let type: ObjectIdentifier
    }

    final class Entry {
        var previous: Any
        var pristine: Any
        var versions: [UInt64]
        let token = ContentMemoToken()
        var serial = 0
        var stale = false
        var touched = true
        // Retained subtrees (`SB-`): the occurrence's record (its paint, `SB-AA`), the observation
        // windows over its build recursion, prepaint and paint, and whether any observed property
        // changed since the record was made.
        var record: RetainedRecord?
        var observedChange = false
        /// Builds (by `ContentMemoStore.buildSerial`) before which this occurrence's prepaint is not replayed, and
        /// the exponent of the next quarantine: a redo this occurrence caused doubles it (`RK-D` item 3).
        var quarantineUntil = 0
        var redoExponent = 0
        /// What the last build of this occurrence left for a graft (`RK-B`, `RK-F`), or `nil` (ineligible, by name in
        /// `retainedGraftIneligible`).
        var graft: GraftRecord?
        /// Whether this occurrence's build and prepaint must open an observation window this frame
        /// (`SB-V`): when it has no record, or its record covers only its paint. A valid, completely
        /// covered record keeps the sessions of the frame it was made in armed, so a steady hit opens none.
        @MainActor var needsObservation: Bool { record == nil || record?.coverageComplete == false }
        let buildSession = RetainedSession("build")
        let prepaintSession = RetainedSession("prepaint")
        let paintSession = RetainedSession("paint")
        init(previous: Any, pristine: Any, versions: [UInt64]) {
            self.previous = previous
            self.pristine = pristine
            self.versions = versions
        }
    }

    private var entries: [Key: Entry] = [:]

    /// The build journal of this window (`RK-F`): every funnel a graft window must replay appends to it while a
    /// window is open.
    let journal = BuildJournal()

    /// Keeps the memo entry at `key` for this build without evaluating anything (a graft standing for a nested
    /// occurrence's build). Journalled so an enclosing window sees it.
    func touch(_ key: Key) {
        journal.record(.memoTouch(key))
        entries[key]?.touched = true
    }

    /// Test switch: off, every memoized component takes the miss path without
    /// retaining anything (the lane-0 baseline).
    package var isEnabled = true

    /// Test switch (`SB-B`): off, an `.equatable()` occurrence's paint runs every frame and
    /// no record is made; the memo-off arm of the retained-subtree tests'
    /// differentials. Independent of ``isEnabled`` (the getter memo).
    package var retainsSubtrees = true

    /// Test switch (`RK-E`): off, an occurrence's prepaint runs every frame and records nothing for
    /// replay; paint replay is `SB-B`'s, unchanged. The `fb9a7e42` arm of the prepaint differentials.
    package var replaysPrepaint = ProcessInfo.processInfo.environment["METALUI_RETAINED_PREPAINT"] != "0"

    /// Test switch (`RK-B`): off, no occurrence skips its build recursion (the `fb9a7e42` arm after lane 1: prepaint replay
    /// stays, the graft goes). `METALUI_RETAINED_GRAFT=0` reads it when each window is made.
    package var graftsBuild = ProcessInfo.processInfo.environment["METALUI_RETAINED_GRAFT"] != "0"

    /// Whether an occurrence may skip its build recursion in the build in progress (`RK-B`, `RK-M`): grafting is on,
    /// prepaint replay is in force (a graft's prepaint and paint are replays) and the build is not a redo.
    var graftAllowed: Bool { graftsBuild && retainsSubtrees && prepaintReplayAllowed }

    /// Whether builds record what a graft needs: on whenever grafting is switched on, so a redo or a backed-off
    /// build still leaves records for the next one.
    var recordsGrafts: Bool { graftsBuild && replaysPrepaint && retainsSubtrees && windowRedoes }

    /// Builds completed (`endFrame`), the window-wide backoff's clock (`RK-D` item 3), the first build at which
    /// prepaint replay may run again, and whether the build in progress is a redo.
    var buildSerial = 0
    var prepaintSuspendedUntil = 0
    var redoInProgress = false
    /// Whether a window drives this store's frames and so builds an abandoned frame again (`RK-D`): a bare
    /// `Frame.render` has no one to redo it, so it never replays a prepaint.
    var windowRedoes = false
    /// How many entries held a prepaint ledger at the last `endFrame`: with none, a build cannot replay a prepaint
    /// and so cannot be redone, and the window takes no checkpoint (`RK-M`).
    private(set) var ledgerEntries = 0

    /// The retained-subtree counters of the build in progress, snapshotted by `endFrame()`.
    var retained = RetainedCounters()
    package private(set) var lastRetained = RetainedCounters()

    // Counters of the build in progress, snapshotted by `endFrame()`.
    private var evaluations = 0

    /// Content evaluations so far this build: a retained subtree reads it around its build recursion
    /// to learn that a descendant's content ran, which its own observation did not subscribe to when
    /// that descendant was skipped in the frame the record was made (`SB-AC`).
    var evaluationsSoFar: Int { evaluations }
    private var skips = 0
    private var refusals = 0
    package private(set) var lastEvaluations = 0
    package private(set) var lastSkips = 0
    package private(set) var lastRefusals = 0

    /// Sessions armed and not yet fired: never above ``entryCount`` (test 2.7).
    package fileprivate(set) var armed = 0
    package var armedSessions: Int { armed }
    package var entryCount: Int { entries.count }

    /// Dirties the window through `Window.markDirtyFromObservation`.
    var markDirty: (@MainActor () -> Void)?

    func noteRefusal() { refusals += 1 }

    /// The memo entry of an occurrence, or `nil` (retained subtrees, `SB-`).
    func entry(for key: Key) -> Entry? { entries[key] }

    /// The content of `component` for this build: the pristine copy of the last
    /// evaluation when nothing it depends on changed, else the getter's result,
    /// evaluated inside this entry's own observation session.
    func materialize<C: Component & Equatable>(_ component: C, id: GlobalElementID,
                                               stateIDs: [GlobalElementID], table: StateTable,
                                               getter: () -> C.Content) -> C.Content {
        guard isEnabled else {
            evaluations += 1
            return getter()
        }
        let key = Key(id: id, type: ObjectIdentifier(C.self))
        journal.record(.memoTouch(key))   // `RK-F`: a nested occurrence's entry must survive a grafting parent
        var versions: [UInt64] = []
        versions.reserveCapacity(stateIDs.count)
        for stateID in stateIDs { versions.append(table.entryVersion(stateID)) }

        if let entry = entries[key] {
            entry.touched = true
            if !entry.stale, entry.versions == versions,
               let previous = entry.previous as? C, previous == component,
               let pristine = entry.pristine as? C.Content {
                skips += 1
                return pristine
            }
        }

        evaluations += 1
        let entry: Entry
        if let existing = entries[key] {
            entry = existing
        } else {
            entry = Entry(previous: component, pristine: (), versions: versions)
            entries[key] = entry
        }
        // Retire the previous session first (`IV-L` item 5): the serial moves on,
        // then the token write fires it, and its handler finds a stale serial.
        entry.serial &+= 1
        entry.token.tick &+= 1
        let handle = ContentMemoHandle(entry: entry, store: self, serial: entry.serial)
        armed += 1
        let content = withObservationTracking {
            _ = entry.token.tick
            return getter()
        } onChange: {
            handle.fire()
        }
        // The pristine copy is the getter's result, taken before `requestGroupLayout`
        // runs on the caller's copy (`IV-J`).
        entry.previous = component
        entry.pristine = content
        entry.versions = versions
        entry.stale = false
        return content
    }

    /// The keys of the entries a component touched this build (`RK-N`): what the sweep at `endFrame` keeps.
    var keptKeys: Set<Key> { Set(entries.filter { $0.value.touched }.map(\.key)) }

    /// Calls `body` on every stored graft record and answers how many there were (`RK-N`'s exit tests).
    func mutateGraftRecords(_ body: (GraftRecord) -> Void) -> Int {
        var count = 0
        for entry in entries.values { if let graft = entry.graft { body(graft); count += 1 } }
        return count
    }

    /// Why occurrences could leave no graft record in the build in progress and in the last one, one name each (`RK-F`).
    var graftRefusals: [String] = []
    package private(set) var lastGraftRefusals: [String] = []

    /// Calls `body` on every stored prepaint ledger and answers how many there were (`RK-N`'s exit tests).
    func mutatePrepaintLedgers(_ body: (PrepaintLedger) -> Void) -> Int {
        var count = 0
        for entry in entries.values { if let ledger = entry.record?.prepaint { body(ledger); count += 1 } }
        return count
    }

    /// The build in progress's counters, and the means to make a later build report them (`RK-N`): verify mode
    /// builds a frame twice and the build it presents reports the work of the first (the replayed one), so the
    /// counts the suite pins are the counts of the build under test.
    struct BuildCounters {
        let retained: RetainedCounters
        let evaluations: Int, skips: Int, refusals: Int
    }

    var buildCounters: BuildCounters {
        BuildCounters(retained: retained, evaluations: evaluations, skips: skips, refusals: refusals)
    }

    func reportLast(_ counters: BuildCounters) {
        lastRetained = counters.retained
        lastEvaluations = counters.evaluations; lastSkips = counters.skips; lastRefusals = counters.refusals
    }

    /// Starts this build's counters over (`RK-D`): the abandoned attempt's work was thrown away.
    func resetBuildCounters() {
        retained = RetainedCounters()
        graftRefusals = []
        evaluations = 0; skips = 0; refusals = 0
    }

    /// The end of a build (`StateTable.sweep()`): snapshot the counters, and drop
    /// every entry no component touched, firing its session so it is spent.
    func endFrame() {
        if replaysPrepaint, retainsSubtrees, buildSerial < prepaintSuspendedUntil { retained.backoffFrames = 1 }
        buildSerial &+= 1
        lastEvaluations = evaluations; lastSkips = skips; lastRefusals = refusals
        lastRetained = retained; retained = RetainedCounters()
        lastGraftRefusals = graftRefusals; graftRefusals = []
        evaluations = 0; skips = 0; refusals = 0
        guard !entries.isEmpty else { ledgerEntries = 0; return }
        var gone: [Key] = []
        var withLedger = 0
        for (key, entry) in entries {
            if entry.record?.prepaint != nil { withLedger += 1 }
            if entry.touched {
                entry.touched = false
            } else {
                gone.append(key)
            }
        }
        ledgerEntries = withLedger
        for key in gone {
            guard let entry = entries.removeValue(forKey: key) else { continue }
            entry.serial &+= 1
            entry.token.tick &+= 1
        }
    }
}
