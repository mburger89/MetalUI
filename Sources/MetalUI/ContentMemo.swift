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
/// machinery can call it on any thread. Holds the entry and the store strongly
/// until it fires (the session is one-shot; a spent one is released).
private final class ContentMemoHandle: @unchecked Sendable {
    let entry: ContentMemoStore.Entry
    let store: ContentMemoStore
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
        store.armed -= 1
        // A serial the entry has moved past is a flush (the token write before a
        // re-evaluation, or an entry that left the tree): nothing changed.
        guard entry.serial == serial else { return }
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

    /// Test switch: off, every memoized component takes the miss path without
    /// retaining anything (the lane-0 baseline).
    package var isEnabled = true

    /// Test switch (`SB-B`): off, an `.equatable()` occurrence's paint runs every frame and
    /// no record is made; the memo-off arm of the retained-subtree tests'
    /// differentials. Independent of ``isEnabled`` (the getter memo).
    package var retainsSubtrees = true

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

    /// The end of a build (`StateTable.sweep()`): snapshot the counters, and drop
    /// every entry no component touched, firing its session so it is spent.
    func endFrame() {
        lastEvaluations = evaluations; lastSkips = skips; lastRefusals = refusals
        lastRetained = retained; retained = RetainedCounters()
        evaluations = 0; skips = 0; refusals = 0
        guard !entries.isEmpty else { return }
        var gone: [Key] = []
        for (key, entry) in entries {
            if entry.touched {
                entry.touched = false
            } else {
                gone.append(key)
            }
        }
        for key in gone {
            guard let entry = entries.removeValue(forKey: key) else { continue }
            entry.serial &+= 1
            entry.token.tick &+= 1
        }
    }
}
