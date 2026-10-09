import Foundation
import MetalUICore

// MARK: - The window's timeline bookkeeping (rulings `KF-K` items 3–4, `KF-V` item 3)
//
// STUB (lane B red): the API compiles; every context is the reference date and
// nothing is kept, scheduled or kept running.

/// Per-window `TimelineView` state, held by the window's `AnimationStore`.
@MainActor
final class TimelineStore {
    /// Schedules `fire` at `date` and answers how to cancel it.
    typealias Scheduler = (_ date: Date, _ fire: @escaping @MainActor () -> Void) -> (() -> Void)

    /// Seconds added to a display-link timestamp to make a date.
    var clockOffset: TimeInterval?

    /// The one wake's scheduler.
    var scheduler: Scheduler = { _, _ in {} }

    /// The date the pending wake fires at, or `nil`.
    private(set) var scheduledWake: Date?

    /// Timeline positions the last completed build kept.
    var count: Int { 0 }

    init() {}

    /// The context for the timeline at `owner` this build.
    func context<S: TimelineSchedule>(owner: GlobalElementID, schedule: S, timestamp: Double,
                                      stateTable: StateTable) -> (context: TimelineViewDefaultContext, live: Bool) {
        (TimelineViewDefaultContext(date: Date(timeIntervalSinceReferenceDate: 0), cadence: .live), false)
    }

    /// Runs `body` one timeline deeper.
    func withScope<R>(_ body: () -> R) -> R { body() }

    /// Closes a build.
    func endFrame() {}
}
