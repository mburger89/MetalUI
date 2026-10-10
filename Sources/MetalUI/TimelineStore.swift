import Foundation
import MetalUICore

// MARK: - The window's timeline bookkeeping (rulings `KF-K` items 2–4, `KF-V` item 3, `KF-Y`)

/// Per-window `TimelineView` state, held by the window's `AnimationStore` — so
/// a `Window`'s frames share one and a headless `renderFrame` or a test-built
/// `Frame` gets a fresh one (`LC-D`'s reason).
///
/// Per timeline position (`$timeline<depth>` under the view's position, plus
/// `#<n>` when the key is touched again in one build, `KF-V` item 3): the date
/// it first appeared, and — a schedule other than `.animation` — an iterator
/// over `entries(from:)`, the entry shown and the next one. **Every position a
/// build does not touch is dropped at the end of that build** (`AN-AB`'s rule),
/// so a timeline that returns starts over. Nothing here is a `StateTable`
/// entry, a `$`-slot or a reserved name.
///
/// **One wake** (`KF-K` item 3): after each build the earliest next entry
/// across the window's scheduled timelines is handed to `scheduler`, which
/// fires the window's `@State` write path (`StateTable.onWrite`) from outside
/// every phase; a newer earliest entry replaces the pending wake, an equal one
/// keeps it, and a build with no scheduled timeline cancels it. `.animation`
/// takes no wake: it keeps the display link running through
/// `Frame.noteActiveAnimation()`.
@MainActor
final class TimelineStore {
    /// Schedules `fire` at `date` (this store's clock) and answers how to
    /// cancel it. Tests install a recorder (they never sleep).
    typealias Scheduler = (_ date: Date, _ fire: @escaping @MainActor () -> Void) -> (() -> Void)

    /// Seconds added to a display-link timestamp to make a date (`KF-K` item
    /// 4): successive dates differ exactly by tick differences. `nil` until
    /// taken — at the first NONZERO timestamp, as `Date.now − timestamp`
    /// (`KF-Y` item 1: a window's first frame, drawn before its first tick,
    /// carries timestamp 0, which is not on the link's timebase); until then a
    /// date is the wall clock. Tests set it (0: a date's
    /// `timeIntervalSinceReferenceDate` is the timestamp).
    var clockOffset: TimeInterval?

    /// The one wake's scheduler; by default a main-actor `Task` that sleeps
    /// until the date and fires.
    var scheduler: Scheduler = TimelineStore.taskScheduler

    private struct Cursor {
        let scheduleType: ObjectIdentifier
        let start: Date
        var iterator: AnyIterator<Date>?
        var shown: Date
        var next: Date?
    }

    private var cursors: [GlobalElementID: Cursor] = [:]
    private var touched: Set<GlobalElementID> = []
    /// Timelines noted this build per base key — the occurrence ordinal.
    private var occurrences: [GlobalElementID: Int] = [:]
    /// The window's state table, whose `onWrite` a wake fires — the last one
    /// a build handed in; weak, as the table's owner holds this store.
    private weak var stateTable: StateTable?
    private var pendingWake: (date: Date, cancel: () -> Void)?

    /// How many timelines enclose the one being laid out — the depth in its
    /// key (`LC-C` item 2's reason).
    private(set) var depth = 0

    /// The most entries one build advances a cursor by: a schedule whose
    /// entries never pass now (equal past dates, forever) cannot hang a build.
    static let maximumAdvance = 10_000

    init() {}

    /// The date the pending wake fires at, or `nil` — test observability.
    var scheduledWake: Date? { pendingWake?.date }

    /// Timeline positions the last completed build kept — test observability.
    var count: Int { cursors.count }

    /// `timestamp` as a date (`KF-K` item 4, `KF-Y` item 1).
    func date(at timestamp: Double) -> Date {
        if let clockOffset { return Date(timeIntervalSinceReferenceDate: timestamp + clockOffset) }
        let now = Date()
        guard timestamp != 0 else { return now }
        clockOffset = now.timeIntervalSinceReferenceDate - timestamp
        return now
    }

    /// The context for the timeline at `owner` this build, and whether it is
    /// live (`.animation`, not paused: the caller notes an active animation).
    ///
    /// - `.animation` (`KF-K` item 2): the frame's date; paused, the date it
    ///   first appeared; with `minimumInterval`, stepped in whole intervals
    ///   from the first appearance.
    /// - every other schedule (`KF-K` item 3): the last entry not after now —
    ///   the first appearance until the first entry arrives. A schedule of
    ///   another type at a known position starts over.
    func context<S: TimelineSchedule>(owner: GlobalElementID, schedule: S, timestamp: Double,
                                      stateTable: StateTable) -> (context: TimelineViewDefaultContext, live: Bool) {
        self.stateTable = stateTable
        let base = GlobalElementID.child(of: owner, at: 0, name: ElementID("$timeline\(depth)"))
        let occurrence = occurrences[base, default: 0]
        occurrences[base] = occurrence + 1
        let key = occurrence == 0
            ? base
            : GlobalElementID.child(of: owner, at: 0, name: ElementID("$timeline\(depth)#\(occurrence)"))
        touched.insert(key)

        let now = date(at: timestamp)
        let type = ObjectIdentifier(S.self)
        if let animation = schedule as? AnimationTimelineSchedule {
            let start: Date
            if let cursor = cursors[key], cursor.scheduleType == type {
                start = cursor.start
            } else {
                start = now
                cursors[key] = Cursor(scheduleType: type, start: now, iterator: nil, shown: now, next: nil)
            }
            if animation.paused { return (TimelineViewDefaultContext(date: start, cadence: .live), false) }
            guard let interval = animation.minimumInterval, interval > 0, interval.isFinite else {
                return (TimelineViewDefaultContext(date: now, cadence: .live), true)
            }
            let steps = (now.timeIntervalSince(start) / interval).rounded(.down)
            return (TimelineViewDefaultContext(date: start.addingTimeInterval(max(0, steps) * interval),
                                               cadence: .live), true)
        }

        var cursor: Cursor
        if let known = cursors[key], known.scheduleType == type {
            cursor = known
        } else {
            let iterator = AnyIterator(schedule.entries(from: now, mode: .normal).makeIterator())
            cursor = Cursor(scheduleType: type, start: now, iterator: iterator, shown: now, next: iterator.next())
        }
        var advanced = 0
        while let next = cursor.next, next <= now, advanced < Self.maximumAdvance {
            cursor.shown = next
            cursor.next = cursor.iterator?.next()
            advanced += 1
        }
        cursors[key] = cursor
        return (TimelineViewDefaultContext(date: cursor.shown, cadence: .live), false)
    }

    /// Runs `body` one timeline deeper.
    func withScope<R>(_ body: () -> R) -> R {
        depth += 1
        defer { depth -= 1 }
        return body()
    }

    /// Closes a build (`AnimationStore.endFrame()`): drops every position it
    /// did not touch, then schedules, keeps or cancels the one wake.
    func endFrame() {
        defer {
            touched.removeAll(keepingCapacity: true)
            occurrences.removeAll(keepingCapacity: true)
        }
        if touched.count != cursors.count {
            cursors = cursors.filter { touched.contains($0.key) }
        }
        let earliest = cursors.values.compactMap(\.next).min()
        guard let earliest else {
            pendingWake?.cancel()
            pendingWake = nil
            return
        }
        guard pendingWake?.date != earliest else { return }
        pendingWake?.cancel()
        let cancel = scheduler(earliest) { [weak self] in
            guard let self else { return }
            self.pendingWake = nil
            self.stateTable?.onWrite?()
        }
        pendingWake = (earliest, cancel)
    }

    /// The default scheduler: a main-actor `Task` that sleeps until `date`
    /// (the store's clock, which tracks the wall clock) and fires unless
    /// cancelled.
    nonisolated static func taskScheduler(_ date: Date, _ fire: @escaping @MainActor () -> Void) -> (() -> Void) {
        let task = Task { @MainActor in
            let delay = date.timeIntervalSinceNow
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            guard !Task.isCancelled else { return }
            fire()
        }
        return { task.cancel() }
    }
}
