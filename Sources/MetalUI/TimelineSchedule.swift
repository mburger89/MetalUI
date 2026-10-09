import Foundation

// MARK: - Timeline schedules (rulings `KF-K`, `KF-T`)
//
// SwiftUI's `TimelineSchedule` protocol and its four built-in schedules,
// spelled as the MacOSX27.0 SDK spells them. A schedule is a value: the
// window's `TimelineStore` iterates its entries (`KF-K` item 3), except
// `AnimationTimelineSchedule`, which it recognizes by type (`KF-K` item 2).

/// Whether a schedule is asked for its entries at the normal rate or a reduced
/// one — SwiftUI's `TimelineScheduleMode`. **MetalUI always asks `.normal`**:
/// its windows never enter a low-frequency mode (`KF-K` item 1, T5).
public enum TimelineScheduleMode: Sendable, Hashable {
    /// Entries at the schedule's own rate.
    case normal
    /// A reduced rate (an always-on display, in SwiftUI); never asked here.
    case lowFrequency
}

/// A sequence of dates at which a `TimelineView` rebuilds its content —
/// SwiftUI's `TimelineSchedule` (ruling `KF-K` item 1). A conformer writes one
/// method; `Mode` is SwiftUI's nested name for `TimelineScheduleMode`
/// (`KF-T`), so a schedule ported from SwiftUI spelling `mode: Mode` compiles.
public protocol TimelineSchedule {
    /// SwiftUI's nested name for the mode a schedule is asked in (`KF-T`).
    typealias Mode = TimelineScheduleMode

    /// The dates the schedule produces.
    associatedtype Entries: Sequence where Entries.Element == Date

    /// The schedule's dates from `startDate` on — the date a `TimelineView`
    /// first appeared. The view shows the last entry not after now (T4); a
    /// date before the first entry shows `startDate`.
    func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries
}

/// Every frame, or every `minimumInterval` — SwiftUI's
/// `AnimationTimelineSchedule`, written `.animation` or
/// `.animation(minimumInterval:paused:)`. A `TimelineView` on it rebuilds in
/// every frame while present and not paused, keeping the display link running
/// through the frame's active-animation answer, never by dirtying the window
/// (`KF-K` item 2).
public struct AnimationTimelineSchedule: TimelineSchedule, Sendable {
    let minimumInterval: Double?
    let paused: Bool

    /// A schedule that steps at most every `minimumInterval` seconds (every
    /// frame when `nil`) and, when `paused`, does not step at all.
    public init(minimumInterval: Double? = nil, paused: Bool = false) {
        self.minimumInterval = minimumInterval
        self.paused = paused
    }

    /// A date every `minimumInterval` (1/60 s when `nil`) from `startDate` —
    /// SwiftUI's shape, for a caller that iterates it. A `TimelineView` does
    /// not: it reads the frame's date (`KF-K` item 2).
    public func entries(from startDate: Date, mode: TimelineScheduleMode) -> UnfoldSequence<Date, Int> {
        let step = minimumInterval.flatMap { $0 > 0 && $0.isFinite ? $0 : nil } ?? 1.0 / 60
        return sequence(state: 0) { index in
            defer { index += 1 }
            return startDate.addingTimeInterval(Double(index) * step)
        }
    }
}

/// A date every `interval` seconds from a start — SwiftUI's
/// `PeriodicTimelineSchedule`, written `.periodic(from:by:)`.
public struct PeriodicTimelineSchedule: TimelineSchedule, Sendable {
    let startDate: Date
    let interval: TimeInterval

    /// Entries at `startDate + n × interval`. A non-positive or non-finite
    /// interval produces `startDate` alone.
    public init(from startDate: Date, by interval: TimeInterval) {
        self.startDate = startDate
        self.interval = interval
    }

    /// The entries from the last one not after `startDate` (this schedule's
    /// own start when that is later), each computed from its index so no
    /// error accumulates.
    public func entries(from startDate: Date, mode: TimelineScheduleMode) -> UnfoldSequence<Date, Int> {
        let origin = self.startDate
        let interval = self.interval
        guard interval > 0, interval.isFinite else {
            return sequence(state: 0) { index in
                defer { index += 1 }
                return index == 0 ? origin : nil
            }
        }
        let elapsed = startDate.timeIntervalSince(origin)
        let first = elapsed > 0 ? Int((elapsed / interval).rounded(.down)) : 0
        return sequence(state: first) { index in
            defer { index += 1 }
            return origin.addingTimeInterval(Double(index) * interval)
        }
    }
}

/// A date at the start of every minute — SwiftUI's
/// `EveryMinuteTimelineSchedule`, written `.everyMinute`.
public struct EveryMinuteTimelineSchedule: TimelineSchedule, Sendable {
    /// The every-minute schedule.
    public init() {}

    /// The minute boundary not after `startDate`, then every 60 seconds.
    public func entries(from startDate: Date, mode: TimelineScheduleMode) -> UnfoldSequence<Date, Int> {
        let first = Int((startDate.timeIntervalSinceReferenceDate / 60).rounded(.down))
        return sequence(state: first) { minute in
            defer { minute += 1 }
            return Date(timeIntervalSinceReferenceDate: Double(minute) * 60)
        }
    }
}

/// The dates it was given — SwiftUI's `ExplicitTimelineSchedule`, written
/// `.explicit(_:)`.
public struct ExplicitTimelineSchedule<Entries: Sequence>: TimelineSchedule where Entries.Element == Date {
    let dates: Entries

    /// A schedule of exactly `dates`, in their order.
    public init(_ dates: Entries) {
        self.dates = dates
    }

    /// `dates`, whatever `startDate` is.
    public func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries {
        dates
    }
}

extension TimelineSchedule where Self == AnimationTimelineSchedule {
    /// Every frame (SwiftUI's `.animation`).
    public static var animation: AnimationTimelineSchedule { AnimationTimelineSchedule() }

    /// Every frame, stepping the date at most every `minimumInterval`, or not
    /// at all while `paused` (SwiftUI's `.animation(minimumInterval:paused:)`).
    public static func animation(minimumInterval: Double? = nil, paused: Bool = false)
        -> AnimationTimelineSchedule {
        AnimationTimelineSchedule(minimumInterval: minimumInterval, paused: paused)
    }
}

extension TimelineSchedule where Self == PeriodicTimelineSchedule {
    /// A date every `interval` seconds from `startDate` (SwiftUI's
    /// `.periodic(from:by:)`).
    public static func periodic(from startDate: Date, by interval: TimeInterval) -> PeriodicTimelineSchedule {
        PeriodicTimelineSchedule(from: startDate, by: interval)
    }
}

extension TimelineSchedule where Self == EveryMinuteTimelineSchedule {
    /// A date at the start of every minute (SwiftUI's `.everyMinute`).
    public static var everyMinute: EveryMinuteTimelineSchedule { EveryMinuteTimelineSchedule() }
}

extension TimelineSchedule {
    /// Exactly `dates` (SwiftUI's `.explicit(_:)`).
    public static func explicit<S>(_ dates: S) -> ExplicitTimelineSchedule<S> where Self == ExplicitTimelineSchedule<S> {
        ExplicitTimelineSchedule(dates)
    }
}
