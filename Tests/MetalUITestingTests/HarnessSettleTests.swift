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
/// Mutations: `runUntil` without `await Task.yield()` (times out: the task
/// never runs); without the draw (the box is still 10); the condition read
/// before the draw (returns with the write undrawn: 10).
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
