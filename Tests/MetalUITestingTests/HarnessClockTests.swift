import MetalUI
import MetalUIScene
import MetalUITesting
import Observation
import Testing

// Spec §4.1 tests 1.14, 1.17, 1.20, 1.21: the simulated clock (ruling `HT-E`).
// Nothing here reads a wall clock or sleeps.

/// 1.14 — a 0.5 s long press runs only once the clock passes its duration:
/// not at `advance(by: 0.4)`, yes after 0.2 more. The arena stamps a press at
/// the first tick after it (a mouse event carries no timestamp), so the raw
/// press is followed by the frame it draws, at 0 (`HT-S` item 3). Mutation:
/// `advance` does not fire a tick.
@Test @MainActor func aLongPressRunsOnlyAfterItsDurationUnderAdvance() throws {
    let log = HarnessLog()
    let window = try harnessWindow {
        Box().frame(width: Pixels(40), height: Pixels(40)).background(.accent)
            .onLongPressGesture(minimumDuration: 0.5) { log.add("long") }
    }
    window.send(.mouseDown(MouseEvent(position: pt(200, 150))))
    window.tick()
    window.advance(by: 0.4)
    #expect(log.entries.isEmpty, "0.4 s is short of 0.5")
    window.advance(by: 0.2)
    #expect(log.entries == ["long"], "0.6 s is past it")
    #expect(abs(window.now - 0.6) < 1e-9, "the clock moved by the two advances and nothing else")
}

/// 1.17 — a raw `send` delivers one event and draws nothing; the window is left
/// dirty and the next tick draws. Mutation: `send` ticks.
@Test @MainActor func aRawSendDrawsNoFrameUntilATick() throws {
    let window = try harnessWindow {
        Box().frame(width: Pixels(40), height: Pixels(40)).background(.accent)
    }
    let drawn = window.framesDrawn
    window.send(.mouseMoved(MouseEvent(position: pt(10, 10))))
    #expect(window.framesDrawn == drawn, "send draws no frame")
    #expect(window.window.needsRedraw, "input dirtied the window")
    window.tick()
    #expect(window.framesDrawn == drawn + 1)
}

/// A main-actor model a `.task` loads, suspending twice and reading no clock.
@Observable @MainActor final class HarnessLoader {
    var value = 0
    func load() async -> Int {
        await Task.yield()
        await Task.yield()
        return 42
    }
}

/// 1.20 — a `.task` whose work is main-actor and timer-free completes under
/// `runUntilIdle()` and its write is drawn: the box is 50 wide after, 10
/// before. Mutation: `runUntilIdle` without `Task.yield()`.
@Test @MainActor func aTaskCompletesUnderRunUntilIdle() async throws {
    let loader = HarnessLoader()
    let window = try harnessWindow {
        VStack(spacing: 0) {
            Box().frame(width: Pixels(loader.value == 42 ? 50 : 10), height: Pixels(10)).background(.accent)
                .task { loader.value = await loader.load() }
        }
    }
    #expect(rects(window, height: 10).map { $0.bounds.size.width } == [10], "the task has not finished")
    try await window.runUntilIdle()
    #expect(loader.value == 42)
    #expect(rects(window, height: 10).map { $0.bounds.size.width } == [50], "its write was drawn")
}

/// A component that writes its `@State` while it builds — CLAUDE.md's
/// documented hazard ("write from input, never from a phase"): the window is
/// dirty after every frame and never goes idle.
private struct HarnessRestless: Component {
    @State var builds = 0
    var content: some ElementGroup {
        Box().frame(width: Pixels(bump()), height: Pixels(10)).background(.accent)
    }
    func bump() -> Float {
        builds += 1
        return 10
    }
}

/// 1.21 — `runUntilIdle()` is bounded: a window that redraws forever throws
/// `.notIdle(rounds: 64)` rather than looping. Mutation: the bound 64 → 65
/// (the literal reddens; the loop is never unbounded).
@Test @MainActor func runUntilIdleThrowsNotIdleForAWindowThatRedrawsForever() async throws {
    let window = try harnessWindow { VStack(spacing: 0) { HarnessRestless() } }
    // A do/catch, not `#expect(throws:)`: its async form warns "no 'async'
    // operations occur within 'await'" and the build must stay warning-free.
    do {
        try await window.runUntilIdle()
        Issue.record("runUntilIdle returned for a window that never goes clean")
    } catch let error as TestHarnessError {
        #expect(error == .notIdle(rounds: 64))
    }
}
