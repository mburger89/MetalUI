import Dispatch
import MetalUI
import MetalUIScene
import MetalUITesting
import Observation
import Testing

// Ruling `HT-Y` (record §171): a settle that does not depend on the machine's
// load. MetalFlow's quit tests threw `.notIdle(rounds: 64)` under load because
// an approved termination closed the window mid-settle with a frame owed, and
// a closed window draws nothing more, so `needsRedraw` stayed `true` for every
// remaining round. Nothing here sleeps; the work that lands late is a
// main-actor task that yields a fixed number of times.

/// A main-actor model the trees below read.
@Observable @MainActor final class SettleModel {
    var width: Float = 10
}

/// A model written off the main thread: its observation callback runs on the
/// writing thread, so the window's invalidation hops to the main actor a turn
/// later (`Window.markDirtyFromObservation`'s off-main arm) — on every platform,
/// the shape Linux gives a main-actor write too.
@Observable final class OffMainSettleModel: @unchecked Sendable {
    var width: Float = 10
}

/// Runs `body` after `yields` main-actor turns — work that comes back after
/// `runUntilIdle()` has started, as a detached save's hop does.
@MainActor private func later(after yields: Int, _ body: @escaping @MainActor () -> Void) {
    Task { @MainActor in
        for _ in 0..<yields { await Task.yield() }
        body()
    }
}

/// `HT-Y` item 1 — the MetalFlow shape: a quit held `.later`, then a model
/// write and the approved reply landing two turns into `runUntilIdle()`. The
/// reply closes every window (`endEverything`) with the write's frame not yet
/// drawn; `runUntilIdle()` returns rather than throwing `.notIdle`. Mutation:
/// `isDirtyAndOpen` without `&& !platformWindow.isClosed` (throws `.notIdle`).
@Test @MainActor func runUntilIdleReturnsWhenAnApprovedTerminationClosesTheWindowMidSettle() async throws {
    let model = SettleModel()
    let window = try harnessWindow {
        VStack(spacing: 0) { Box().frame(width: Pixels(model.width), height: Pixels(10)).background(.accent) }
    }
    let app = window.testApp.app
    app.onTerminateRequest = { .later }
    #expect(window.testApp.platform.simulateTerminateRequest() == .later)
    try await window.runUntilIdle()
    later(after: 2) {
        model.width = 50
        app.replyToTerminateRequest(true)
    }
    try await window.runUntilIdle()
    #expect(window.platformWindow.isClosed, "the approved termination closed the window")
    #expect(window.window.needsRedraw, "the write's frame is owed and never drawn: the separating arm")
    #expect(window.testApp.platform.terminateReplies == [true])
}

/// `HT-Y` item 1, the bare case — a window dirtied after it closed is clean to
/// `runUntilIdle()`. Mutation: as above.
@Test @MainActor func runUntilIdleTreatsAClosedDirtyWindowAsIdle() async throws {
    let window = try harnessWindow {
        VStack(spacing: 0) { Box().frame(width: Pixels(10), height: Pixels(10)).background(.accent) }
    }
    window.close()
    window.window.setNeedsRedraw()
    let drawn = window.framesDrawn
    try await window.runUntilIdle()
    #expect(window.framesDrawn == drawn, "a closed window draws nothing")
}

/// `HT-Y` item 2 — `runUntil` waits for work `runUntilIdle()` cannot: a write
/// 1000 turns away lands after `runUntilIdle()` has returned (separating arm),
/// and `runUntil` returns with it written **and drawn** (the box 50 wide).
/// Mutation: `runUntil` without `await Task.yield()` (times out: the task
/// never runs).
@Test @MainActor func runUntilWaitsForLateWorkAndDrawsIt() async throws {
    let model = SettleModel()
    let window = try harnessWindow {
        VStack(spacing: 0) { Box().frame(width: Pixels(model.width), height: Pixels(10)).background(.accent) }
    }
    func drawn() -> [Float] { rects(window, height: 10).map { $0.bounds.size.width } }
    later(after: 1000) { model.width = 50 }
    try await window.runUntilIdle()
    #expect(model.width == 10, "runUntilIdle returned before the late write")
    try await window.runUntil { model.width == 50 }
    #expect(drawn() == [50], "the write was drawn before runUntil returned")
}

/// `HT-Y` item 3 — a condition about the model can hold before the window
/// knows it is dirty: the write is made on another thread (the main actor
/// waits for it), so the window's invalidation is a hop queued behind
/// `runUntil`'s next turn. `runUntil` settles after the condition holds and
/// returns with the write drawn. Linux CI's failure of the test above, on
/// macOS. Mutation: `runUntil` without its closing `runUntilIdle()` (10).
@Test @MainActor func runUntilDrawsAWriteWhoseInvalidationHops() async throws {
    let model = OffMainSettleModel()
    let window = try harnessWindow {
        VStack(spacing: 0) { Box().frame(width: Pixels(model.width), height: Pixels(10)).background(.accent) }
    }
    func drawn() -> [Float] { rects(window, height: 10).map { $0.bounds.size.width } }
    later(after: 3) {
        // `async` plus a wait, not `sync`: `sync` runs the block on the calling (main) thread.
        let written = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            model.width = 50
            written.signal()
        }
        written.wait()
    }
    try await window.runUntil { model.width == 50 }
    #expect(drawn() == [50], "the hopped invalidation's frame was drawn before runUntil returned")
}

/// `HT-Y` item 2 — a condition about the drawn window: the loop draws while it
/// waits, so a write's frame satisfies it. Mutation: `runUntil` without its
/// per-round draw (times out: only the closing settle draws, and it is never
/// reached). The order "draw, then read" is not separately observable: reading
/// first finds the frame one round later.
@Test @MainActor func runUntilDrawsWhileItWaitsForADrawnCondition() async throws {
    let model = SettleModel()
    let window = try harnessWindow {
        VStack(spacing: 0) { Box().frame(width: Pixels(model.width), height: Pixels(10)).background(.accent) }
    }
    func drawn() -> [Float] { rects(window, height: 10).map { $0.bounds.size.width } }
    later(after: 10) { model.width = 50 }
    try await window.runUntil(timeout: .seconds(2)) { drawn() == [50] }
    #expect(model.width == 50)
}

/// `HT-Y` items 1 and 3 — `runUntil`'s closing settle returns for a window an
/// approved termination closed with a frame owed. Mutation: `isDirtyAndOpen`
/// without `&& !platformWindow.isClosed` (the settle throws `.notIdle`).
@Test @MainActor func runUntilReturnsWhenAnApprovedTerminationClosesTheWindow() async throws {
    let model = SettleModel()
    let window = try harnessWindow {
        VStack(spacing: 0) { Box().frame(width: Pixels(model.width), height: Pixels(10)).background(.accent) }
    }
    let app = window.testApp.app
    app.onTerminateRequest = { .later }
    #expect(window.testApp.platform.simulateTerminateRequest() == .later)
    later(after: 5) {
        model.width = 50
        app.replyToTerminateRequest(true)
    }
    try await window.runUntil { window.testApp.platform.terminateReplies == [true] }
    #expect(window.platformWindow.isClosed)
    #expect(window.window.needsRedraw, "the frame is owed and never drawn")
}

/// `HT-Y` item 2 — a condition that never holds throws `.timedOut(after:)`
/// once the real-time bound passes, rather than looping. Mutation: the
/// deadline arm returns instead of throwing.
@Test @MainActor func runUntilThrowsTimedOutWhenTheConditionNeverHolds() async throws {
    let window = try harnessWindow {
        VStack(spacing: 0) { Box().frame(width: Pixels(10), height: Pixels(10)).background(.accent) }
    }
    do {
        try await window.runUntil(timeout: .milliseconds(20)) { false }
        Issue.record("runUntil returned for a condition that never holds")
    } catch let error as TestHarnessError {
        #expect(error == .timedOut(after: .milliseconds(20)))
    }
}
