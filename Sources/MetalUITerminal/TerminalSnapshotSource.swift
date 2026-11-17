import Dispatch
import Foundation

/// The hand-off between the queue that owns a ``TerminalEmulator`` and the main thread that draws it
/// (frozen signatures, `TRM-AG`).
///
/// The source takes ownership of the emulator: only `queue` touches it afterwards. ``feed(_:)`` runs the bytes
/// through the emulator, publishes a snapshot and merges its damage into one pending snapshot, and wakes the
/// bound view once; further feeds only merge until the view takes the pending snapshot, so a flood of N feeds
/// before one frame costs one take and one draw.
public final class TerminalSnapshotSource: @unchecked Sendable {
    private let emulator: TerminalEmulator
    private let queue: DispatchQueue
    private let queueKey = DispatchSpecificKey<ObjectIdentifier>()
    private let lock = NSLock()

    private var replyHandler: (@Sendable ([UInt8]) -> Void)?
    private var eventHandler: (@MainActor ([TerminalEvent]) -> Void)?
    private var pending: Merge?
    private var wakeOutstanding = false
    private var wake: (@Sendable () -> Void)?
    private var pendingSize: TerminalSize?
    private var resizeScheduled = false
    private var queuedEvents: [TerminalEvent] = []
    private var eventHopScheduled = false
    private var counters = (publishes: 0, merges: 0, wakes: 0, eventDeliveries: 0)

    /// Takes ownership of `emulator`; only `queue` touches it afterwards.
    public init(emulator: TerminalEmulator, queue: DispatchQueue) {
        self.emulator = emulator
        self.queue = queue
        queue.setSpecific(key: queueKey, value: ObjectIdentifier(self))
    }

    /// Called on `queue`, in order, for every `.reply` event; the owner writes the bytes to the child.
    public var onReply: (@Sendable ([UInt8]) -> Void)? {
        get { lock.withLock { replyHandler } }
        set { lock.withLock { replyHandler = newValue } }
    }

    /// Every other event, in order, coalesced: all the events raised before the main actor runs arrive in one
    /// call, and no call is made while one is already scheduled.
    public var onEvents: (@MainActor ([TerminalEvent]) -> Void)? {
        get { lock.withLock { eventHandler } }
        set { lock.withLock { eventHandler = newValue } }
    }

    /// Feeds `bytes` on `queue` (at once when already there, else a copy is queued), publishes, merges the
    /// damage into the pending snapshot and wakes the bound view if it is not already woken.
    public func feed(_ bytes: UnsafeRawBufferPointer) {
        guard bytes.count > 0 else { return }
        if onQueue {
            feedOnQueue(bytes)
        } else {
            let copy = Array(bytes)
            queue.async { copy.withUnsafeBytes { self.feedOnQueue($0) } }
        }
    }

    /// Asks for a resize on `queue`. A newer size replaces one still pending, so a drag costs one resize.
    public func resize(_ size: TerminalSize) {
        let schedule: Bool = lock.withLock {
            pendingSize = size
            if resizeScheduled { return false }
            resizeScheduled = true
            return true
        }
        guard schedule else { return }
        queue.async { [self] in
            let size: TerminalSize? = lock.withLock {
                resizeScheduled = false
                defer { pendingSize = nil }
                return pendingSize
            }
            guard let size else { return }
            resizeHandler(emulator, size)
            publishAndWake()
        }
    }

    /// Runs `body` on `queue` with the emulator (selection, search and `rowText` requests), then publishes.
    public func perform(_ body: @escaping @Sendable (TerminalEmulator) -> Void) {
        queue.async { [self] in
            body(emulator)
            publishAndWake()
        }
    }

    // MARK: The binding to the view (package, Phase 5)

    /// Called when a snapshot is waiting and none was before: at most once until ``takeSnapshot()``. The view
    /// binds it to its `SurfaceRedrawTrigger`. May be called on any thread.
    package var onWake: (@Sendable () -> Void)? {
        get { lock.withLock { wake } }
        set { lock.withLock { wake = newValue } }
    }

    /// What applies a resize on `queue`; `TerminalEmulator.resize` joins in Phase 1.5.
    package var resizeHandler: @Sendable (TerminalEmulator, TerminalSize) -> Void = { _, _ in }

    /// Takes the merged snapshot of every publish since the previous take, or nil when nothing is waiting, and
    /// re-arms the wake. Cheap, and safe on any thread: one merge result per take.
    package func takeSnapshot() -> TerminalSnapshot? {
        lock.withLock {
            wakeOutstanding = false
            guard let merge = pending else { return nil }
            pending = nil
            counters.merges += 1
            return merge.snapshot
        }
    }

    /// How the source has been used, for tests: snapshots published, merged hand-offs taken, wakes sent and
    /// event batches delivered.
    package var statistics: (publishes: Int, takes: Int, wakes: Int, eventDeliveries: Int) {
        lock.withLock { (counters.publishes, counters.merges, counters.wakes, counters.eventDeliveries) }
    }

    /// How a batch of events reaches the main actor; tests replace it.
    package var eventHop: @Sendable (@escaping @Sendable () -> Void) -> Void = { block in
        DispatchQueue.main.async(execute: block)
    }

    // MARK: Queue side

    private var onQueue: Bool { DispatchQueue.getSpecific(key: queueKey) == ObjectIdentifier(self) }

    private func feedOnQueue(_ bytes: UnsafeRawBufferPointer) {
        emulator.feed(bytes)
        publishAndWake()
    }

    private func publishAndWake() {
        let snapshot = emulator.publishSnapshot()
        let events = emulator.drainEvents()
        var others: [TerminalEvent] = []
        var replies: [[UInt8]] = []
        for event in events {
            if case .reply(let bytes) = event { replies.append(bytes) } else { others.append(event) }
        }
        let (replyHandler, wakeNow, hop): ((@Sendable ([UInt8]) -> Void)?, (@Sendable () -> Void)?, Bool) = lock.withLock {
            counters.publishes += 1
            pending = pending.map { $0.merging(snapshot) } ?? Merge(snapshot)
            var wakeNow: (@Sendable () -> Void)?
            if !wakeOutstanding {
                wakeOutstanding = true
                counters.wakes += 1
                wakeNow = wake
            }
            queuedEvents.append(contentsOf: others.prefix(max(0, 1024 - queuedEvents.count)))
            let hop = !queuedEvents.isEmpty && !eventHopScheduled && eventHandler != nil
            if hop { eventHopScheduled = true }
            return (self.replyHandler, wakeNow, hop)
        }
        if let replyHandler { for bytes in replies { replyHandler(bytes) } }
        wakeNow?()
        if hop {
            eventHop { [self] in
                MainActor.assumeIsolated { deliverEvents() }
            }
        }
    }

    @MainActor private func deliverEvents() {
        let (batch, handler): ([TerminalEvent], (@MainActor ([TerminalEvent]) -> Void)?) = lock.withLock {
            eventHopScheduled = false
            defer { queuedEvents.removeAll() }
            if !queuedEvents.isEmpty { counters.eventDeliveries += 1 }
            return (queuedEvents, eventHandler)
        }
        if !batch.isEmpty { handler?(batch) }
    }
}

/// The damage of several publishes folded into one snapshot.
private struct Merge {
    var latest: TerminalSnapshot
    var rows: [Int: TerminalRow]
    var full: Bool

    init(_ snapshot: TerminalSnapshot) {
        latest = snapshot
        rows = Dictionary(uniqueKeysWithValues: snapshot.damagedRows.map { ($0.index, $0.row) })
        full = snapshot.isFullFrame
    }

    /// A later publish overrides the rows it lists; a change of size or a full frame makes the result full.
    func merging(_ next: TerminalSnapshot) -> Merge {
        var merged = self
        merged.full = full || next.isFullFrame || next.size != latest.size
        if next.isFullFrame { merged.rows.removeAll(keepingCapacity: true) }
        for damaged in next.damagedRows { merged.rows[damaged.index] = damaged.row }
        merged.latest = next
        return merged
    }

    var snapshot: TerminalSnapshot {
        let damaged = rows.keys.sorted().map { TerminalDamagedRow(index: $0, row: rows[$0]!) }
        return TerminalSnapshot(version: latest.version, size: latest.size, viewportOffset: latest.viewportOffset,
                                damagedRows: damaged, isFullFrame: full, cursor: latest.cursor, modes: latest.modes,
                                selection: latest.selection, links: latest.links)
    }
}
