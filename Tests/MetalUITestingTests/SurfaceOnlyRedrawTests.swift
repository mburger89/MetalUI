import Foundation
import MetalUI
import MetalUIPlatform
import MetalUITesting
import Testing
@testable import MetalUI

// Surface-scoped redraw (Alloy gap 5, rulings `TRM-P`…`TRM-T`, record 337): a `SurfaceRedrawTrigger` draws one
// `GPUSurface` in a frame with no build. PLAIN public API plus `window.window.testing…` reads; headless, portable,
// no sleeping: the simulated clock moves the timed requests (`TW-A`).
//
// Every test names the mutation it was shown red against. "Routed through `setNeedsRedraw`" means
// `Window.drainSurfaceTrigger` also calls `setNeedsRedraw()` — the trigger becomes a full-frame request.

private let side = sz(200, 100)

/// What a tree's builds read and what its surfaces drew.
@MainActor private final class Probe {
    var bodies = 0
    var draws: [String: Int] = [:]
    var showsSecond = true
    func count(_ name: String) -> Int { draws[name] ?? 0 }
    func draw(_ name: String) -> @MainActor (any GPUSurfaceContext) -> Void {
        { [self] _ in draws[name, default: 0] += 1 }
    }
}

/// One trigger-driven surface under a label (the label's build is the probe's `bodies`), drawing counted.
@MainActor private func surfaceWindow(_ probe: Probe, trigger: SurfaceRedrawTrigger) throws -> TestWindow {
    let w = try harnessWindow(size: side) {
        probe.bodies += 1
        return VStack(spacing: 0) {
            Text("steady")
            GPUSurface(trigger: trigger, draw: probe.draw("a")).frame(width: Pixels(80), height: Pixels(40))
        }
    }
    w.runsSurfaceDraws = true
    return w
}

/// The window settled: three redraws and the clock past any first-frame draw, counters zeroed.
@MainActor private func settle(_ w: TestWindow) {
    for _ in 0..<3 { w.window.setNeedsRedraw(); w.advance(by: 0.05) }
    w.resetFrameWork()
}

/// **1** A trigger's frame builds nothing: 0 builds, 0 element requests, one surface-only frame, the tree's content
/// closure not called again, the surface drawn once. Mutation: routed through `setNeedsRedraw` (builds 1, requests > 0,
/// no surface-only frame, the body read again).
@MainActor @Test func aTriggerDrawsItsSurfaceInAFrameWithNoBuild() throws {
    let probe = Probe(), trigger = SurfaceRedrawTrigger()
    let w = try surfaceWindow(probe, trigger: trigger)
    settle(w)
    let bodies = probe.bodies, draws = probe.count("a"), frames = w.framesDrawn
    trigger.requestRedraw()
    w.advance(by: 0.05)
    let work = w.lastFrameWork
    #expect(work.builds == 0 && work.elementRequests == 0 && work.surfaceOnlyFrames == 1, "\(work)")
    #expect(probe.bodies == bodies, "the content closure ran again")
    #expect(probe.count("a") == draws + 1, "one draw")
    #expect(w.framesDrawn == frames + 1)
}

/// **2** A hundred requests before one tick are one frame and one draw, and the frame after has nothing to do.
/// Mutation: the request is not consumed by the frame that drew it (a second frame, a second draw).
@MainActor @Test func aHundredRequestsMakeOneDrawAndTheNextTickNone() throws {
    let probe = Probe(), trigger = SurfaceRedrawTrigger()
    let w = try surfaceWindow(probe, trigger: trigger)
    settle(w)
    let draws = probe.count("a"), frames = w.framesDrawn
    for _ in 0..<100 { trigger.requestRedraw() }
    w.advance(by: 0.05)
    #expect(probe.count("a") == draws + 1 && w.framesDrawn == frames + 1)
    w.advance(by: 0.05)
    w.advance(by: 0.05)
    #expect(probe.count("a") == draws + 1 && w.framesDrawn == frames + 1, "a drawn request is done")
}

/// **3** Only the invalidated surface draws; its sibling is composited as it was. Mutation: a surface-only frame
/// forces every surface of the last frame.
@MainActor @Test func aSurfaceOnlyFrameDrawsOnlyTheInvalidatedSurface() throws {
    let probe = Probe(), first = SurfaceRedrawTrigger(), second = SurfaceRedrawTrigger()
    let w = try harnessWindow(size: side) {
        probe.bodies += 1
        return VStack(spacing: 0) {
            GPUSurface(trigger: first, draw: probe.draw("a")).frame(width: Pixels(80), height: Pixels(30))
            GPUSurface(trigger: second, draw: probe.draw("b")).frame(width: Pixels(80), height: Pixels(30))
        }
    }
    w.runsSurfaceDraws = true
    settle(w)
    let a = probe.count("a"), b = probe.count("b")
    second.requestRedraw()
    w.advance(by: 0.05)
    #expect(w.lastFrameWork.surfaceOnlyFrames == 1)
    #expect(probe.count("a") == a && probe.count("b") == b + 1, "a \(probe.count("a")) b \(probe.count("b"))")
    #expect(w.window.testingSurfaceOnlyFrames == 1)
}

/// **4** A timed request fires once, at its deadline on the simulated clock. Mutation: fire at the first tick
/// (ignoring the delay) — draws at 0.5 s; or never clear the deadline — a draw on every later tick.
@MainActor @Test func aTimedRequestFiresOnceAtItsDeadline() throws {
    let probe = Probe(), trigger = SurfaceRedrawTrigger()
    let w = try surfaceWindow(probe, trigger: trigger)
    settle(w)
    let draws = probe.count("a")
    trigger.requestRedraw(after: .seconds(1))
    #expect(w.window.testingSurfaceDeadlineCount == 1)
    w.advance(by: 0.5)
    #expect(probe.count("a") == draws, "not yet")
    #expect(w.lastFrameWork.surfaceOnlyFrames == 0)
    w.advance(by: 0.4)
    #expect(probe.count("a") == draws, "0.9 s")
    w.advance(by: 0.1)
    #expect(probe.count("a") == draws + 1, "due at 1 s")
    #expect(w.lastFrameWork.builds == 0 && w.lastFrameWork.surfaceOnlyFrames == 1)
    w.advance(by: 1)
    w.advance(by: 1)
    #expect(probe.count("a") == draws + 1 && w.window.testingSurfaceDeadlineCount == 0, "once")
}

/// Runs `body` on another thread while this one waits, so no main-actor hop it queues runs until it is done.
private func callFromAnotherThread(_ body: @escaping @Sendable () -> Void) {
    let done = DispatchSemaphore(value: 0)
    DispatchQueue.global().async { body(); done.signal() }
    done.wait()
}

/// **5** The earliest deadline wins, in either order, across calls and off the main thread. Mutation: the later
/// request replaces the earlier one (in the window's `note`, or in the trigger's collected request).
@MainActor @Test func theEarliestDeadlineWins() async throws {
    let probe = Probe(), trigger = SurfaceRedrawTrigger()
    let w = try surfaceWindow(probe, trigger: trigger)
    settle(w)
    let draws = probe.count("a")
    trigger.requestRedraw(after: .seconds(3))
    trigger.requestRedraw(after: .seconds(1))
    trigger.requestRedraw(after: .seconds(2))
    w.advance(by: 1)
    #expect(probe.count("a") == draws + 1, "the 1 s request, not the last")
    w.advance(by: 5)
    #expect(probe.count("a") == draws + 1, "and nothing for the later two")

    // Off the main thread the two calls share one hop (the main thread is held until both are made): the shorter
    // delay is what arrives.
    callFromAnotherThread { trigger.requestRedraw(after: .seconds(1)); trigger.requestRedraw(after: .seconds(3)) }
    try await w.runUntilIdle()
    w.advance(by: 1)
    #expect(probe.count("a") == draws + 2, "one draw at 1 s")
    w.advance(by: 5)
    #expect(probe.count("a") == draws + 2)
}

/// **6** A trigger whose surface is not painted starts nothing: no frame, no deadline. Mutation: leave the trigger
/// bound when the next frame does not paint its surface (`didPresentFullFrame` skips `unbind()`): a pending id, a
/// deadline.
@MainActor @Test func aTriggerWhoseSurfaceIsNotPaintedIsANoOp() throws {
    let probe = Probe(), trigger = SurfaceRedrawTrigger(), other = SurfaceRedrawTrigger()
    let w = try harnessWindow(size: side) {
        probe.bodies += 1
        return VStack(spacing: 0) {
            GPUSurface(trigger: other, draw: probe.draw("other")).frame(width: Pixels(40), height: Pixels(20))
            if probe.showsSecond { GPUSurface(trigger: trigger, draw: probe.draw("a")).frame(width: Pixels(40), height: Pixels(20)) }
        }
    }
    w.runsSurfaceDraws = true
    settle(w)
    probe.showsSecond = false
    w.window.setNeedsRedraw(); w.advance(by: 0.05)
    #expect(!trigger.isBound, "the surface left the frame, and with it the trigger's binding")
    w.resetFrameWork()
    let draws = probe.count("a"), frames = w.framesDrawn
    trigger.requestRedraw()
    trigger.requestRedraw(after: .seconds(1))
    #expect(!w.window.testingHasPendingSurfaceRedraw && w.window.testingSurfaceDeadlineCount == 0)
    w.advance(by: 0.05)
    w.advance(by: 2)
    #expect(w.framesDrawn == frames && probe.count("a") == draws, "no frame, no draw")

    // A trigger never bound (no surface made with it was ever painted) is the same.
    let loose = SurfaceRedrawTrigger()
    loose.requestRedraw(); loose.requestRedraw(after: .seconds(1))
    #expect(!w.window.testingHasPendingSurfaceRedraw && w.window.testingSurfaceDeadlineCount == 0)
}

/// **7** A surface that leaves the tree drops its timed request: it does not fire when the surface returns.
/// Mutation: keep deadlines of surfaces the frame did not paint.
@MainActor @Test func aDeadlineStopsWithItsSurface() throws {
    let probe = Probe(), trigger = SurfaceRedrawTrigger()
    let w = try harnessWindow(size: side) {
        probe.bodies += 1
        return VStack(spacing: 0) {
            Text("x")
            if probe.showsSecond { GPUSurface(trigger: trigger, draw: probe.draw("a")).frame(width: Pixels(40), height: Pixels(20)) }
        }
    }
    w.runsSurfaceDraws = true
    settle(w)
    trigger.requestRedraw(after: .seconds(1))
    probe.showsSecond = false
    w.window.setNeedsRedraw(); w.advance(by: 0.05)
    #expect(w.window.testingSurfaceDeadlineCount == 0)
}

/// **8** A full frame owed for another reason draws the invalidated surface too, once: the force survives the
/// table's keep rule, here for a resize (the surface's value and size are unchanged). Mutation: a full frame does
/// not force pending surfaces (no draw).
@MainActor @Test func aResizeWhilePendingIsAFullFrameThatStillDrawsTheSurface() throws {
    let probe = Probe(), trigger = SurfaceRedrawTrigger()
    let w = try surfaceWindow(probe, trigger: trigger)
    settle(w)
    let draws = probe.count("a")
    trigger.requestRedraw()
    w.resize(to: sz(220, 100))
    let work = w.lastFrameWork
    #expect(work.builds >= 1 && work.surfaceOnlyFrames == 0, "\(work)")
    #expect(probe.count("a") == draws + 1, "drawn once, by the force")
    w.advance(by: 0.05)
    #expect(probe.count("a") == draws + 1, "and not again")
}

/// **9** Same for a scale change (the table also redraws a rescaled target, so the draw count is one either way;
/// the frame must be a build). Mutation: route the scale change into a surface-only frame — reachable only through
/// the guard, pinned by test 10.
@MainActor @Test func aScaleChangeWhilePendingIsAFullFrame() throws {
    let probe = Probe(), trigger = SurfaceRedrawTrigger()
    let w = try surfaceWindow(probe, trigger: trigger)
    settle(w)
    trigger.requestRedraw()
    w.setScaleFactor(2)
    let work = w.lastFrameWork
    #expect(work.builds >= 1 && work.surfaceOnlyFrames == 0, "\(work)")
}

/// **10** The atlas was rebuilt since the last frame, with nothing dirty: the scene's glyph slots are stale, so the
/// scene cannot be encoded again and a build runs. Mutation: drop the `layoutGeneration` comparison from
/// `SurfaceRedrawState.canReuseScene` (a surface-only frame over a stale scene).
@MainActor @Test func aRebuiltAtlasMakesTheNextTriggerFrameAFullOne() throws {
    let probe = Probe(), trigger = SurfaceRedrawTrigger()
    let w = try surfaceWindow(probe, trigger: trigger)
    settle(w)
    w.window.glyphAtlas.reclaim()
    trigger.requestRedraw()
    w.advance(by: 0.05)
    let work = w.lastFrameWork
    #expect(work.builds >= 1 && work.surfaceOnlyFrames == 0, "\(work)")
    // The frame after it is surface-only again.
    trigger.requestRedraw()
    w.advance(by: 0.05)
    #expect(w.lastFrameWork.surfaceOnlyFrames == 1 && w.lastFrameWork.builds == 0)
}

/// **11** Animation or a timer in the window makes it a full frame (`TRM-P` item 2): the trigger's draw rides the
/// build. Mutation: take the surface-only branch whenever a surface is pending.
@MainActor @Test func aRunningAnimationMakesTheTriggerFrameAFullOne() throws {
    let probe = Probe(), trigger = SurfaceRedrawTrigger()
    let w = try harnessWindow(size: side) {
        probe.bodies += 1
        return VStack(spacing: 0) {
            ProgressView()
            GPUSurface(trigger: trigger, draw: probe.draw("a")).frame(width: Pixels(40), height: Pixels(20))
        }
    }
    w.runsSurfaceDraws = true
    for _ in 0..<3 { w.advance(by: 0.05) }
    let draws = probe.count("a")
    trigger.requestRedraw()
    w.advance(by: 0.05)
    #expect(w.lastFrameWork.builds >= 1 && w.lastFrameWork.surfaceOnlyFrames == 0)
    #expect(probe.count("a") == draws + 1)
}

/// The draw of a surface in a window that is not even ticking: the trigger from another thread.
/// **12** Mutation: `Window.hop`'s off-main branch does nothing (the request never arrives).
@MainActor @Test func aTriggerFromAnotherThreadReachesTheWindow() async throws {
    let probe = Probe(), trigger = SurfaceRedrawTrigger()
    let w = try surfaceWindow(probe, trigger: trigger)
    settle(w)
    let draws = probe.count("a")
    callFromAnotherThread { trigger.requestRedraw() }
    try await w.runUntilIdle()
    #expect(probe.count("a") == draws + 1)
    #expect(w.lastFrameWork.surfaceOnlyFrames == 1 || w.window.testingSurfaceOnlyFrames >= 1)
}

// MARK: - steady-frame cost (the shared-view rule: an app not using the feature pays nothing)

@MainActor private func steadyWork<R: Element>(_ content: @escaping @MainActor () -> R) throws -> FrameWork {
    let w = try harnessWindow(size: side) { content() }
    defer { withExtendedLifetime(w) {} }
    for _ in 0..<3 { w.window.setNeedsRedraw(); w.advance(by: 0.05) }
    return w.lastFrameWork
}

/// **13** A window with a `GPUSurface` that never uses a trigger costs what it cost before the trigger existed:
/// literal steady-frame numbers (3 requests, nothing retained), the same measured on master ff73af7c (`TRM-T`). Mutation: any per-frame request, taint or
/// element the trigger path adds to `GPUSurface.paint` / `Frame.drawSurface` moves them.
@MainActor @Test func aSurfaceWithoutATriggerCostsWhatItDidOnMaster() throws {
    let work = try steadyWork {
        VStack(spacing: 0) {
            Text("steady")
            GPUSurface { _ in }.frame(width: Pixels(80), height: Pixels(40))
        }
    }
    #expect(work.builds == 1)
    #expect(work.elementRequests == 3, "elementRequests \(work.elementRequests)")
    #expect(work.retainedIneligible == 0 && work.retainedHits == 0
            && work.retainedMisses == 0,
            "ineligible \(work.retainedIneligible) hits \(work.retainedHits) misses \(work.retainedMisses) reasons \(work.retainedIneligibleReasons)")
    #expect(work.surfaceOnlyFrames == 0)
}

/// **14** And one with no surface at all.
@MainActor @Test func anAppWithNoSurfaceCostsWhatItDidOnMaster() throws {
    let work = try steadyWork {
        VStack(spacing: 0) { Text("steady"); Text("frame") }.frame(width: Pixels(80), height: Pixels(40))
    }
    #expect(work.builds == 1)
    #expect(work.elementRequests == 3, "elementRequests \(work.elementRequests)")
    #expect(work.retainedIneligible == 0 && work.surfaceOnlyFrames == 0)
}

/// A retained card holding an untriggered surface: the `"surface"` taint (`TRM-` Phase 3.3 removes it) is what a
/// steady frame pays today, and this branch must not move it.
private struct SurfaceCard: Component, @MainActor Equatable {
    let id: Int
    var content: some ElementGroup {
        GPUSurface { _ in }.frame(width: Pixels(40), height: Pixels(20))
    }
    static func == (l: SurfaceCard, r: SurfaceCard) -> Bool { l.id == r.id }
}

/// **15** The same, inside an `.equatable()` card: the surface still taints it (reason `surface`, one ineligible
/// occurrence), exactly the numbers master has.
@MainActor @Test func aRetainedCardWithAnUntriggeredSurfaceCostsWhatItDidOnMaster() throws {
    let w = try harnessWindow(size: side) { VStack(spacing: 0) { SurfaceCard(id: 1).equatable() } }
    for _ in 0..<4 { w.window.setNeedsRedraw(); w.advance(by: 0.05) }
    let f = w.lastFrameWork
    #expect(f.builds == 1 && f.elementRequests == 2, "requests \(f.elementRequests)")
    #expect(f.retainedHits == 0 && f.retainedMisses == 0
            && f.retainedIneligible == 1,
            "hits \(f.retainedHits) misses \(f.retainedMisses) ineligible \(f.retainedIneligible) reasons \(f.retainedIneligibleReasons)")
    #expect(f.retainedIneligibleReasons == ["surface": 1])
}
