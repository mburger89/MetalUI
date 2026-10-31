import MetalUI
import MetalUITesting
import Testing

// Ruling `HT-Z` (record §173): `runUntilIdle()` never moves the clock, and "a
// running animation does not count: it needs the clock". MetalFlow's report:
// a wheel over a `ScrollView`, then `runUntilIdle()`, threw `.notIdle(64)`.
// Measured per round (a throwaway trace, not kept): after the wheel every tick
// at `now == 0` drew a frame and left `needsRedraw == true`, with
// `hasActiveAnimations == false`; the same tree under `.scrollIndicators(.hidden)`
// was clean on the first round. The indicator's fade asked for its frames with
// `requestAnotherFrame()` — dirtying — and a frozen clock never ages it. A held
// long press and a pending tooltip measured the same `.notIdle(64)`: their
// timers dirtied the window at the end of every frame.

/// A 300 × 150 scroller over 800 pt of rows, centred in the 400 × 300 window
/// (viewport 50...350 × 75...225).
@MainActor private func scrollingWindow(indicators: ScrollIndicatorVisibility = .automatic) throws -> TestWindow {
    try harnessWindow {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    ForEach(Array(0..<40), id: \.self) { _ in
                        Box().frame(width: Pixels(100), height: Pixels(20)).background(.accent)
                    }
                }
            }
            .scrollIndicators(indicators)
            .frame(width: Pixels(300), height: Pixels(150))
        }
    }
}

/// `HT-Z` item 1 — MetalFlow's repro: a wheel, then `runUntilIdle()` returns
/// with the clock unmoved, the scroll drawn and the thumb still showing (age
/// 0). The fade is a live animation: `hasActiveAnimations`, never `needsRedraw`.
/// Mutation: `ScrollChrome.paintIndicator` raising `pass.requestAnotherFrame()`
/// instead of `pass.frame.noteActiveAnimation()` (throws `.notIdle`).
@Test @MainActor func runUntilIdleReturnsAfterAScrollWhileTheIndicatorIsStillFading() async throws {
    let window = try scrollingWindow()
    let rowsBefore = window.scene.rects.count
    window.scroll(at: pt(200, 150), byDeltaX: 0, deltaY: -2000)
    try await window.runUntilIdle()
    #expect(window.now == 0, "runUntilIdle never moves the clock")
    #expect(!window.window.needsRedraw)
    #expect(window.window.hasActiveAnimations, "the fade is still running: it needs the clock, so it does not count")
    #expect(window.scene.rects.count > rowsBefore, "the thumb is painted on top of the rows: the scroll was drawn")
    window.advance(by: 1.1)
    #expect(!window.window.hasActiveAnimations, "the fade ends once the clock passes it")
    try await window.runUntilIdle()
}

/// `HT-Z` item 1, the separating arm — the same scroll under `.hidden` was
/// always idle, so the scroll alone never kept the window dirty; and the scroll
/// moved the content (the first row's top left the viewport). Mutation: as above
/// (this arm stays green: it separates the indicator from the scroll).
@Test @MainActor func aHiddenIndicatorsScrollWasAlwaysIdle() async throws {
    let window = try scrollingWindow(indicators: .hidden)
    let top = window.scene.rects.map(\.bounds.origin.y).min()
    window.scroll(at: pt(200, 150), byDeltaX: 0, deltaY: -2000)
    try await window.runUntilIdle()
    #expect(!window.window.hasActiveAnimations)
    #expect(window.scene.rects.map(\.bounds.origin.y).min() != top, "the content moved")
}

/// `HT-Z` item 2 — a held long press is a pending timer: `runUntilIdle()`
/// returns without running it, and `advance(by:)` past its duration does.
/// Mutation: `Window.awaitsATimer` restored as an end-of-frame
/// `setNeedsRedraw()` for `gestureArena?.needsTicks` (throws `.notIdle`).
@Test @MainActor func runUntilIdleReturnsWhileALongPressIsHeldShortOfItsDuration() async throws {
    let log = HarnessLog()
    let window = try harnessWindow {
        Box().frame(width: Pixels(40), height: Pixels(40)).background(.accent)
            .onLongPressGesture(minimumDuration: 0.5) { log.add("long") }
    }
    window.send(.mouseDown(MouseEvent(position: pt(200, 150))))
    window.tick()
    try await window.runUntilIdle()
    #expect(log.entries.isEmpty, "the clock did not move, so the press has not matured")
    window.advance(by: 0.6)
    #expect(log.entries == ["long"], "the timer was kept: the next tick past its duration runs it")
}

/// `HT-Z` item 2 — a pending tooltip is a timer too: `runUntilIdle()` returns
/// with it still pending (none shown), and `advance(by:)` past the delay shows
/// it. Mutation: `Window.awaitsATimer` restored as an end-of-frame
/// `setNeedsRedraw()` for `tooltipTracker.isPending` (throws `.notIdle`).
@Test @MainActor func runUntilIdleReturnsWhileATooltipIsPending() async throws {
    let window = try harnessWindow {
        Box().frame(width: Pixels(100), height: Pixels(50)).background(.accent).help("Tip")
    }
    let rects = window.scene.rects.count
    window.hover(at: pt(200, 150))
    try await window.runUntilIdle()
    #expect(window.scene.rects.count == rects, "no tooltip panel: the delay has not passed")
    window.advance(by: 1.5)
    #expect(window.scene.rects.count > rects, "the timer was kept: a tick past the delay paints the panel")
}
