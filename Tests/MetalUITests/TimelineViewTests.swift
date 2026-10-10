import Foundation
import Testing
import Metal
import Observation
import MetalUICore
import MetalUILayout
import MetalUIPlatform
@testable import MetalUI

// `TimelineView` — key and focus scoping, lane B (rulings `KF-K`, `KF-L`,
// `KF-T`, `KF-V` items 2–4; spec
// `docs/superpowers/specs/2026-10-08-key-focus-design.md` §5.2, T1–T15).
// SwiftUI's side is `docs/probes/swiftui-key-focus.swift`, arms T1–T5.
//
// **No test sleeps**: display-link windows are driven by
// `simulateTick(timestamp:)`; the store's clock offset is set to 0 (so a
// date's `timeIntervalSinceReferenceDate` IS the frame's timestamp) and its
// scheduler is a recorder, whose wakes a test fires by hand. Red before, for
// every test: the file does not compile at `c62d6ba`; the red was taken
// against the lane-B stub (every context the reference date, nothing kept,
// scheduled or kept running), recorded in the lane's red commit.

// MARK: - Harness

/// Every date a timeline's content was built with, in order.
@MainActor final class TLLog {
    var dates: [Double] = []
    var cadences: [TimelineViewDefaultContext.Cadence] = []
    var modes: [TimelineScheduleMode] = []
    func add(_ context: TimelineViewDefaultContext) {
        dates.append(context.date.timeIntervalSinceReferenceDate)
        cadences.append(context.cadence)
    }
    /// The distinct dates, in order of first appearance.
    var distinct: [Double] {
        var seen: [Double] = []
        for d in dates where seen.last != d { seen.append(d) }
        return seen
    }
}

/// The scheduler a test installs: records each wake and each cancel.
@MainActor final class TLWakes {
    var scheduled: [(date: Double, fire: @MainActor () -> Void)] = []
    var cancels = 0
    func install(on window: Window) {
        window.animationStore.timeline.clockOffset = 0
        window.animationStore.timeline.scheduler = { [weak self] date, fire in
            self?.scheduled.append((date.timeIntervalSinceReferenceDate, fire))
            return { [weak self] in self?.cancels += 1 }
        }
    }
}

@Observable @MainActor final class TLModel {
    var shown = true
    var tick = 0
}

/// A recording leaf: notes `context` and answers a 10 × 9 tile.
@MainActor func tlLeaf(_ context: TimelineViewDefaultContext, _ log: TLLog) -> some ProposalElementGroup {
    log.add(context)
    return Rectangle().frame(width: Pixels(10), height: Pixels(9))
}

@MainActor func tlWindow<Root: Element>(size: Int = 200, startsDisplayLink: Bool = true,
                                        _ content: @escaping @MainActor () -> Root) throws
    -> (Window, FakePlatformWindow, TLWakes) {
    let (window, platform) = try makeFakeWindowOnDefaultDevice(size: size, startsDisplayLink: startsDisplayLink,
                                                               content: content)
    let wakes = TLWakes()
    wakes.install(on: window)
    return (window, platform, wakes)
}

private func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }
private func near(_ a: [Double], _ b: [Double]) -> Bool { a.count == b.count && zip(a, b).allSatisfy(near) }
private let t0 = Date(timeIntervalSinceReferenceDate: 0)

/// A custom schedule: three fixed dates, and the mode it was asked in.
private struct TLCustomSchedule: TimelineSchedule {
    let log: TLLog
    func entries(from startDate: Date, mode: Mode) -> [Date] {
        MainActor.assumeIsolated { log.modes.append(mode) }
        return [0.0, 0.25, 0.5].map { Date(timeIntervalSinceReferenceDate: $0) }
    }
}

// MARK: - `.animation` (T1–T3, T11, T12)

/// **T1** (T1: every frame). An animation timeline rebuilds in every tick
/// with the frame's date (zero-offset clock: dates 0, 1/60, 2/60), and the
/// display link never pauses. Red on the stub: one evaluation date (0).
/// Mutation: drop `noteActiveAnimation()` (the link pauses: `pausesEntered`).
@MainActor
@Test func anAnimationTimelineRebuildsEveryTickWithTheFrameDate() throws {
    let log = TLLog()
    let (window, platform, _) = try tlWindow { HStack { TimelineView(.animation) { tlLeaf($0, log) } } }
    let pauses = window.pausesEntered
    for t in [0.0, 1.0 / 60, 2.0 / 60] { platform.simulateTick(timestamp: t) }
    #expect(near(log.distinct, [0, 1.0 / 60, 2.0 / 60]), "\(log.dates)")
    #expect(window.pausesEntered == pauses, "a live timeline keeps the link running")
    #expect(window.hasActiveAnimations)
}

/// **T1u** (`KF-V` item 2, `KF-Y` item 2). The untyped entry is live too: a
/// `TimelineView(.animation)` inside a legacy `Column` (laid out through
/// `requestGroupLayout`, not the typed entry) rebuilds every tick and keeps
/// the display link running. Mutation T1u: drop `noteActiveAnimation()` in
/// `requestGroupLayout` only (the link pauses, nothing animates) — T1 and
/// T11 cannot see it, both sit in a proposal stack.
@MainActor
@Test func aTimelineInALegacyColumnKeepsTheLinkRunning() throws {
    let log = TLLog()
    let (window, platform, _) = try tlWindow {
        Column { TimelineView(.animation) { tlLeaf($0, log) } }
            .frame(width: Pixels(100), height: Pixels(100))
    }
    let pauses = window.pausesEntered
    for t in [0.0, 1.0 / 60, 2.0 / 60, 3.0 / 60] { platform.simulateTick(timestamp: t) }
    #expect(near(log.distinct, [0, 1.0 / 60, 2.0 / 60, 3.0 / 60]), "\(log.dates)")
    #expect(window.pausesEntered == pauses, "a live timeline in a legacy container keeps the link running")
    #expect(window.hasActiveAnimations)
}

/// **T16** (`KF-Y` item 1). The clock offset is taken at the first NONZERO
/// timestamp: a window's first frame (timestamp 0, not on the link's
/// timebase) shows the wall clock and fixes nothing, so a later tick at
/// 5000 s still maps to about now. No clock override (the store's own
/// clock); the scheduler is a recorder. Mutation Tx: delete
/// `guard timestamp != 0 else { return now }` (the offset is taken at 0, and
/// the tick at 5000 reads 5000 s in the future).
@MainActor
@Test func aZeroTimestampFrameDoesNotFixTheClockOffset() throws {
    let log = TLLog()
    let (window, platform) = try makeFakeWindowOnDefaultDevice(size: 200, startsDisplayLink: true) {
        HStack { TimelineView(.animation) { tlLeaf($0, log) } }
    }
    window.animationStore.timeline.scheduler = { _, _ in {} }
    platform.simulateTick(timestamp: 0)
    platform.simulateTick(timestamp: 5000)
    let last = try #require(log.dates.last)
    let now = Date().timeIntervalSinceReferenceDate
    #expect(abs(last - now) < 60, "the tick at 5000 s maps to about now: \(last) vs \(now)")
}

/// **T2** (T2: paused evaluates once). A paused animation timeline is built
/// with the date it first appeared and asks for no frame: later ticks pause
/// the link and build nothing.
@MainActor
@Test func aPausedAnimationTimelineEvaluatesOnceAndAsksNoFrame() throws {
    let log = TLLog()
    let (window, platform, _) = try tlWindow {
        HStack { TimelineView(.animation(minimumInterval: nil, paused: true)) { tlLeaf($0, log) } }
    }
    platform.simulateTick(timestamp: 0.5)
    let builds = log.dates.count
    let pauses = window.pausesEntered
    for t in [0.6, 0.7] { platform.simulateTick(timestamp: t) }
    #expect(near(log.distinct, [0.5]), "\(log.dates)")
    #expect(log.dates.count == builds, "no build after the first frame")
    #expect(window.pausesEntered > pauses, "the link paused")
    #expect(!window.hasActiveAnimations)
}

/// **T3** (T3: stepped). `minimumInterval` steps the date in whole intervals
/// from the first appearance: ticks 0, 0.05, 0.12, 0.25 build dates 0, 0,
/// 0.1, 0.2. Red on the stub: one date. Mutation: pass the frame date
/// unstepped.
@MainActor
@Test func minimumIntervalStepsTheDateInWholeIntervals() throws {
    let log = TLLog()
    let (window, platform, _) = try tlWindow {
        HStack { TimelineView(.animation(minimumInterval: 0.1)) { tlLeaf($0, log) } }
    }
    for t in [0.0, 0.05, 0.12, 0.25] { platform.simulateTick(timestamp: t) }
    #expect(near(log.distinct, [0, 0.1, 0.2]), "\(log.dates)")
    withExtendedLifetime(window) {}
}

/// **T11** (M4-b (2)). An overlay above a `.continuous` `MetalView` follows a
/// time-driven camera through `TimelineView(.animation)`: the label (a rect
/// 9 tall after a spacer 1 + 60·t wide) moves one point per 1/60 s tick.
/// Red at `c62d6ba`: does not compile; on the stub the label never moves.
/// Mutation: T1's.
@MainActor
@Test func anOverlayFollowsAContinuousSurfaceThroughATimeline() throws {
    let (window, platform, _) = try tlWindow {
        ZStack(alignment: .topLeading) {
            MetalView(redraw: .continuous) { _ in }.frame(width: Pixels(200), height: Pixels(200))
            TimelineView(.animation) { context in
                HStack(spacing: Pixels(0)) {
                    Rectangle().frame(width: Pixels(Float(1 + (context.date.timeIntervalSinceReferenceDate * 60)
                                                               .rounded())),
                                      height: Pixels(1))
                    Box().frame(width: Pixels(10), height: Pixels(9)).background(.accent)
                }
            }
        }
    }
    var xs: [Float] = []
    for t in [0.0, 1.0 / 60, 2.0 / 60, 3.0 / 60] {
        platform.simulateTick(timestamp: t)
        let label = window.lastScene.rects.filter { $0.bounds.size.height == 9 }
        try #require(label.count == 1, "one label rect per frame")
        xs.append(label[0].bounds.origin.x)
    }
    #expect(zip(xs, xs.dropFirst()).allSatisfy { $1 - $0 == 1 }, "the label moves one point a tick: \(xs)")
}

/// **T12** (`KF-K` item 2). A timeline never requests another frame — it
/// keeps the link running through `noteActiveAnimation`, never by dirtying:
/// after every tick the window is clean and animating.
@MainActor
@Test func aTimelineNeverRequestsAnotherFrame() throws {
    let log = TLLog()
    let (window, platform, _) = try tlWindow { HStack { TimelineView(.animation) { tlLeaf($0, log) } } }
    for t in [0.0, 1.0 / 60, 2.0 / 60] {
        platform.simulateTick(timestamp: t)
        #expect(!window.needsRedraw, "tick \(t): the timeline dirtied the window")
    }
    #expect(window.hasActiveAnimations)
}

// MARK: - Scheduled timelines (T4–T7, T10)

/// **T4** (T4: dates − start 0.00, 0.10, …: the schedule's entry, not the
/// clock). A periodic timeline at tick 0.37 shows the entry 0.30. Red on the
/// stub: the reference date (0). Mutation: report the clock (0.37).
@MainActor
@Test func aPeriodicTimelineReportsTheEntryNotTheClock() throws {
    let log = TLLog()
    let (window, platform, _) = try tlWindow {
        HStack { TimelineView(.periodic(from: t0, by: 0.1)) { tlLeaf($0, log) } }
    }
    platform.simulateTick(timestamp: 0)
    window.setNeedsRedraw()
    platform.simulateTick(timestamp: 0.37)
    #expect(near(log.distinct, [0, 0.1 * 3]), "\(log.dates)")
}

/// **T5** (`KF-K` item 3). A periodic timeline schedules ONE wake, at its
/// next entry (0.4 after a build at 0.37), and does not keep the link
/// running. Red on the stub: no wake. Mutation: schedule no wake.
@MainActor
@Test func aPeriodicTimelineSchedulesOneWakeAtTheNextEntry() throws {
    let log = TLLog()
    let (window, platform, wakes) = try tlWindow {
        HStack { TimelineView(.periodic(from: t0, by: 0.1)) { tlLeaf($0, log) } }
    }
    platform.simulateTick(timestamp: 0)
    try #require(wakes.scheduled.count == 1 && near(wakes.scheduled[0].date, 0.1), "\(wakes.scheduled.map(\.date))")
    window.setNeedsRedraw()
    platform.simulateTick(timestamp: 0.37)
    #expect(wakes.scheduled.count == 2, "\(wakes.scheduled.map(\.date))")
    #expect(near(wakes.scheduled.last?.date ?? -1, 0.1 * 4))
    #expect(wakes.cancels == 1, "the earlier wake was replaced")
    #expect(!window.hasActiveAnimations, "a periodic timeline does not keep the link running")
}

/// **T5b** (`KF-K` item 3). An equal earliest entry keeps the pending wake:
/// redraws at 0, 0.2 and 0.4 under a 1 s period all have the next entry 1,
/// so ONE wake is scheduled and none is cancelled. Mutation T5b: delete
/// `guard pendingWake?.date != earliest else { return }` (every build
/// cancels and reschedules the same wake).
@MainActor
@Test func anEqualEarliestEntryKeepsThePendingWake() throws {
    let log = TLLog()
    let (window, platform, wakes) = try tlWindow {
        HStack { TimelineView(.periodic(from: t0, by: 1)) { tlLeaf($0, log) } }
    }
    for t in [0.0, 0.2, 0.4] {
        window.setNeedsRedraw()
        platform.simulateTick(timestamp: t)
    }
    try #require(log.dates.count >= 3, "three builds: \(log.dates)")
    #expect(wakes.scheduled.count == 1, "\(wakes.scheduled.map(\.date))")
    #expect(near(wakes.scheduled.first?.date ?? -1, 1))
    #expect(wakes.cancels == 0, "the equal wake was kept")
}

/// **T6** (`KF-K` item 3). Firing the wake dirties the window through the
/// `@State` write path (`StateTable.onWrite`), from outside every phase.
/// Mutation: have the wake call nothing.
@MainActor
@Test func theWakeDirtiesTheWindowThroughTheStateWritePath() throws {
    let log = TLLog()
    let (window, platform, wakes) = try tlWindow {
        HStack { TimelineView(.periodic(from: t0, by: 0.1)) { tlLeaf($0, log) } }
    }
    platform.simulateTick(timestamp: 0)
    try #require(!window.needsRedraw)
    let fire = try #require(wakes.scheduled.last?.fire)
    fire()
    #expect(window.needsRedraw, "the wake dirtied the window")
    platform.simulateTick(timestamp: 0.1)
    #expect(near(log.distinct, [0, 0.1]), "\(log.dates)")
}

/// **T7** (`KF-K` items 2–3). A timeline leaving the tree cancels its wake
/// and stops the link: no wake is pending and the window pauses.
/// Mutation: keep untouched keys.
@MainActor
@Test func aTimelineLeavingTheTreeCancelsItsWakeAndStopsTheLink() throws {
    let log = TLLog(), m = TLModel()
    let (window, platform, wakes) = try tlWindow {
        HStack {
            if m.shown {
                TimelineView(.periodic(from: t0, by: 0.1)) { tlLeaf($0, log) }
                TimelineView(.animation) { tlLeaf($0, log) }
            }
            Rectangle().frame(width: Pixels(5), height: Pixels(5))
        }
    }
    platform.simulateTick(timestamp: 0)
    try #require(wakes.scheduled.count == 1 && window.hasActiveAnimations)
    m.shown = false
    platform.simulateTick(timestamp: 1.0 / 60)
    #expect(wakes.cancels == 1, "the wake was cancelled")
    #expect(window.animationStore.timeline.scheduledWake == nil)
    #expect(window.animationStore.timeline.count == 0)
    let pauses = window.pausesEntered
    platform.simulateTick(timestamp: 2.0 / 60)
    #expect(window.pausesEntered == pauses + 1, "the link paused")
}

/// **T10** (`KF-K` item 3). A custom and an explicit schedule are evaluated
/// through their entries: at tick 0.3 the custom one (0, 0.25, 0.5) shows
/// 0.25 and the explicit one (0.1, 0.2) shows 0.2. Red on the stub: both 0.
/// Mutation: special-case only periodic (any other schedule shows its start).
@MainActor
@Test func aCustomAndAnExplicitScheduleAreEvaluatedThroughTheirEntries() throws {
    let custom = TLLog(), explicit = TLLog()
    let (window, platform, wakes) = try tlWindow {
        HStack {
            TimelineView(TLCustomSchedule(log: custom)) { tlLeaf($0, custom) }
            TimelineView(.explicit([0.1, 0.2].map { Date(timeIntervalSinceReferenceDate: $0) })) {
                tlLeaf($0, explicit)
            }
        }
    }
    platform.simulateTick(timestamp: 0.05)
    window.setNeedsRedraw()
    platform.simulateTick(timestamp: 0.3)
    #expect(near(custom.dates.last ?? -1, 0.25), "\(custom.dates)")
    #expect(near(explicit.distinct, [0.05, 0.2]), "before its first entry the explicit one shows its start: \(explicit.dates)")
    #expect(near(wakes.scheduled.last?.date ?? -1, 0.5), "the earliest next entry: \(wakes.scheduled.map(\.date))")
}

// MARK: - Identity and values (T8, T9, T14, T15)

/// A component with `@State`, for the identity test.
private struct TLCounter: Component {
    @State var n = 0
    var content: some ProposalElementGroup {
        Rectangle().frame(width: Pixels(10 + Float(n)), height: Pixels(10))
    }
}

@MainActor private func tlIdentity<E: Element>(_ element: E) -> (bounds: Set<GlobalElementID>,
                                                                 table: Set<GlobalElementID>) {
    var root = element
    let table = StateTable()
    let frame = Frame(contentSize: Size(width: Pixels(300), height: Pixels(300)), scaleFactor: 1,
                      stateTable: table, recordsElementBounds: true)
    frame.render(&root)
    return (Set(frame.elementBounds.keys), table.ids)
}

/// **T8** (`KF-L`). A `TimelineView` is identity-transparent: the ids a tree
/// records (element bounds, and `StateTable` entries) are the same with and
/// without one around the content — the counter component's id, under which
/// its `@State` lives, included — so adding it resets no `@State`. Mutation:
/// give it a cursor index.
@MainActor
@Test func aTimelineIsIdentityTransparent() throws {
    let bare = tlIdentity(HStack { TLCounter(); Rectangle().frame(width: Pixels(5), height: Pixels(5)) })
    let wrapped = tlIdentity(HStack {
        TimelineView(.animation) { _ in TLCounter() }
        Rectangle().frame(width: Pixels(5), height: Pixels(5))
    })
    try #require(bare.bounds.count >= 3, "the stack, the counter's rectangle and the spacer recorded: \(bare.bounds)")
    #expect(bare.bounds == wrapped.bounds)
    #expect(bare.table == wrapped.table)
}

/// **T9** (T5: cadence `live`; `KF-K` item 1, `KF-V` item 4). The context's
/// cadence is `.live` and a schedule is asked in `.normal` mode. Mutation:
/// report `.seconds`.
@MainActor
@Test func cadenceIsLiveAndModeIsNormal() throws {
    let log = TLLog()
    let (window, platform, _) = try tlWindow {
        HStack {
            TimelineView(.animation) { tlLeaf($0, log) }
            TimelineView(TLCustomSchedule(log: log)) { tlLeaf($0, log) }
        }
    }
    platform.simulateTick(timestamp: 0)
    try #require(!log.cadences.isEmpty && !log.modes.isEmpty)
    #expect(log.cadences.allSatisfy { $0 == .live }, "\(log.cadences)")
    #expect(log.modes.allSatisfy { $0 == .normal }, "\(log.modes)")
    withExtendedLifetime(window) {}
}

/// **T14** (`KF-V` item 2). Both entries are pinned: a `TimelineView` in a
/// legacy `Column` whose content carries `.flexGrow(1)` is consumed by the
/// `Column` (the untyped entry; a reporting frame's report is empty), and
/// one in an `HStack` keeps its proposal node (the typed entry: the stack is
/// its content's 30 wide). The ruling's named mutation — route the untyped
/// entry through the typed one — is **equivalent** (`KF-Y` item 2, `LR-X`):
/// the `.flexGrow(1)` box sits in `LegacyContent`, whose typed entry carries
/// its item record to the `Column` unchanged, so nothing is lost or reported
/// (full suite at `e540c60`: nothing reddened). The untyped entry's live
/// behaviour is pinned by T1u.
@MainActor
@Test func theTimelinesTypedAndUntypedEntriesAreEachPinned() throws {
    var untyped = Column {
        TimelineView(.animation) { _ in Box().flexGrow(1).background(.accent) }
        Box().frame(width: Pixels(10), height: Pixels(10))
    }.frame(width: Pixels(100), height: Pixels(100))
    let frame = Frame(contentSize: Size(width: Pixels(300), height: Pixels(300)), scaleFactor: 1,
                      reportsUnlowerableFields: true, recordsElementBounds: true)
    frame.render(&untyped)
    #expect(frame.unlowerableFields.isEmpty, "\(frame.unlowerableFields.map(\.description))")

    var typed = HStack(spacing: Pixels(0)) {
        TimelineView(.animation) { _ in Rectangle().frame(width: Pixels(30), height: Pixels(10)) }
    }
    let typedFrame = Frame(contentSize: Size(width: Pixels(300), height: Pixels(300)), scaleFactor: 1,
                           reportsUnlowerableFields: true, recordsElementBounds: true)
    typedFrame.render(&typed)
    #expect(typedFrame.unlowerableFields.isEmpty)
    let root = GlobalElementID.child(of: nil, at: 0, name: nil)
    #expect(typedFrame.elementBounds[root]?.size.width.value == 30,
            "\(String(describing: typedFrame.elementBounds[root]))")
}

/// **T15** (`KF-V` item 3). A `TimelineView` whose content takes no slot,
/// followed by a sibling at the same cursor, does not share its schedule:
/// at 0.37 the second (every 0.1) shows 0.3 while the first (every 1) is
/// built with 0. Mutation: drop the occurrence ordinal.
@MainActor
@Test func anEmptyTimelineDoesNotShareItsScheduleWithTheNext() throws {
    let first = TLLog(), second = TLLog()
    let (window, platform, _) = try tlWindow {
        HStack {
            TimelineView(.periodic(from: t0, by: 1)) { context -> EmptyGroup in
                first.add(context)
                return EmptyGroup()
            }
            TimelineView(.periodic(from: t0, by: 0.1)) { tlLeaf($0, second) }
        }
    }
    platform.simulateTick(timestamp: 0)
    window.setNeedsRedraw()
    platform.simulateTick(timestamp: 0.37)
    #expect(near(first.distinct, [0]), "\(first.dates)")
    #expect(near(second.distinct, [0, 0.1 * 3]), "\(second.dates)")
}
