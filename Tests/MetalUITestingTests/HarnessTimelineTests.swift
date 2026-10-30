import Foundation
import MetalUI
import MetalUIScene
import MetalUITesting
import Testing

// `TimelineView(.periodic)` under the harness's simulated clock (ruling `DX-A`,
// `docs/superpowers/2026-10-30-dashboard-text-timeline-decisions.md`). Nothing
// here reads a wall clock or sleeps: `advance(by:)` alone moves the timeline.

/// What a periodic timeline's content saw: each build's whole seconds past `start`.
@MainActor private final class TimelineSeen {
    let start = Date()
    var steps: [Int] = []
    func note(_ date: Date) -> Text {
        steps.append(Int(date.timeIntervalSince(start).rounded()))
        return Text("t")
    }
}

/// **DX-A 1.** `advance(by:)` alone re-evaluates a periodic timeline: no
/// `setNeedsRedraw()`, no anchoring `tick()` first. The report: a periodic
/// timeline only picked up `advance(by:)` after a `setNeedsRedraw()` plus
/// `tick()` had anchored the timeline clock. Red before: the first `advance`
/// anchored the clock instead of moving it, and no wake ever dirtied the
/// window (the wake slept on the wall clock). Mutations: **MX-A** install no
/// simulated wake scheduler; **MX-B** do not fire due wakes in `tick()`;
/// **MX-C** leave the timeline clock to anchor at the first nonzero tick; **MX-D** fire the held wake
/// without the due-date guard (reddens the "nothing drew" arm).
@Test @MainActor func advanceAloneReevaluatesAPeriodicTimeline() throws {
    let seen = TimelineSeen()
    let window = try harnessWindow {
        VStack(spacing: 0) {
            TimelineView(.periodic(from: seen.start, by: 1)) { context in seen.note(context.date) }
        }
    }
    #expect(seen.steps.last == 0, "the first frame shows the schedule's first entry")
    let first = window.framesDrawn
    window.advance(by: 0.4)
    #expect(window.framesDrawn == first, "0.4 s is short of the next entry: nothing drew")
    window.advance(by: 1.1)
    #expect(seen.steps.last == 1, "1.5 s: the second entry, from advance alone: \(seen.steps)")
    window.advance(by: 1.0)
    #expect(seen.steps.last == 2, "2.5 s: the third entry: \(seen.steps)")
}

/// **DX-A 2.** One `advance` across several entries shows the last one not
/// after now, and the next advance still moves on (the wake is re-armed from
/// the build). Reddened by MX-A, MX-B and MX-C above.
@Test @MainActor func oneAdvanceAcrossSeveralEntriesShowsTheLatestAndKeepsGoing() throws {
    let seen = TimelineSeen()
    let window = try harnessWindow {
        VStack(spacing: 0) {
            TimelineView(.periodic(from: seen.start, by: 1)) { context in seen.note(context.date) }
        }
    }
    window.advance(by: 3.5)
    #expect(seen.steps.last == 3, "\(seen.steps)")
    window.advance(by: 1.0)
    #expect(seen.steps.last == 4, "\(seen.steps)")
}

/// **DX-A 3.** A timeline that leaves the tree stops waking the window: after
/// it goes, an advance past its entries draws nothing. Green before the fix
/// (no wake existed); a pin. Mutation: **MX-E** `TimelineStore.endFrame` keeps
/// the wake when no timeline is left.
@Test @MainActor func aTimelineThatLeftTheTreeWakesNothing() throws {
    let seen = TimelineSeen()
    final class Flag { var shown = true }
    let flag = Flag()
    let window = try harnessWindow {
        VStack(spacing: 0) {
            if flag.shown {
                TimelineView(.periodic(from: seen.start, by: 1)) { context in seen.note(context.date) }
            } else {
                Text("gone")
            }
        }
    }
    flag.shown = false
    window.window.setNeedsRedraw()
    window.tick()
    let drawn = window.framesDrawn
    window.advance(by: 5)
    #expect(window.framesDrawn == drawn, "no timeline, no wake")
}
