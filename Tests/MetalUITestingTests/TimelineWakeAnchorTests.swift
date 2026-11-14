import Foundation
import MetalUI
import MetalUIScene
import MetalUITesting
import Testing

// The timeline clock is anchored on the frame, not on a deadline (ruling `TW-A`, record 301): a code view's caret
// blink asks for a frame half a second ahead, and when that ask was the first thing to read the clock it fixed the
// clock that much early, so every wake fired before the frame's own clock reached the deadline and the frame it drew
// asked again at once: a frame per tick, and a key arriving at a dirty window is paced. PLAIN imports; the pins read
// the recorded wake date, never sleep.

private struct BackdropHolder: Component, @MainActor Equatable {
    let tag: Int
    var content: some ElementGroup {
        Color.clear.frame(width: Pixels(80), height: Pixels(40)).glassEffect(.regular)
    }
}

@MainActor private func blinkWindow(buffer: CodeBuffer, backdrop: Bool) throws -> TestWindow {
    try harnessWindow(size: sz(400, 200)) {
        VStack(spacing: 0) {
            CodeView(buffer: buffer, decorations: CodeDecorations(buffer: buffer)).font(size: 12)
            if backdrop { BackdropHolder(tag: 1).equatable() }
        }
    }
}

@MainActor private func focus(_ window: TestWindow, _ buffer: CodeBuffer) {
    window.click(at: pt(60, 6))
    buffer.selections = [CodeSelection(caret: 0)]
    window.window.setNeedsRedraw(); window.tick()
}

/// 1 — the first frame, drawn at timestamp 0 (it is not on the display link's clock), asks for its blink frame at
/// the real clock plus the half second to the toggle, not at the real clock. **Mutation:** `noteDeadline` anchoring
/// the clock on the deadline (the old `date(at: timestamp)`): the wake is due at once.
@Test @MainActor func aFrameAtTimestampZeroWakesAHalfSecondOut() throws {
    let buffer = CodeBuffer("hello\n")
    let window = try blinkWindow(buffer: buffer, backdrop: false)
    window.window.testingAnchorTimelineOnWallClock()
    focus(window, buffer)
    let wake = try #require(window.window.testingTimelineWakeDate)
    let delay = wake.timeIntervalSinceNow
    #expect(delay > 0.3 && delay <= 0.5, "the toggle is half a second out: \(delay)")
}

/// 2 — a later frame anchors the clock on its own timestamp: a key at timestamp 100 restarts the blink there, and its
/// wake is half a second out, whatever the deadline's distance was when the clock was first read. **Mutation:** as 1.
@Test @MainActor func aKeyLateInTheRunWakesAHalfSecondOutAndNotAtOnce() throws {
    let buffer = CodeBuffer("hello\n")
    let window = try blinkWindow(buffer: buffer, backdrop: true)
    focus(window, buffer)
    window.window.testingAnchorTimelineOnWallClock()
    window.advance(by: 100)
    window.typeText("a")
    let wake = try #require(window.window.testingTimelineWakeDate)
    let delay = wake.timeIntervalSinceNow
    #expect(delay > 0.3 && delay <= 0.5, "the toggle is half a second out: \(delay)")
}

/// 3 — with a backdrop on screen a spaced key is one frame, the caret is on right after it, hidden after the half
/// second and on again after the next: the blink keeps its schedule. (A guard: the simulated clock was always
/// anchored, so this passes before `TW-A` as well; the pins above are the red ones.)
@Test @MainActor func aSpacedKeyUnderABackdropIsOneFrameAndTheCaretStillBlinks() throws {
    let buffer = CodeBuffer("hello\n")
    let window = try blinkWindow(buffer: buffer, backdrop: true)
    focus(window, buffer)
    for _ in 0..<4 {
        window.advance(by: 0.2)
        let before = window.framesDrawn
        window.typeText("a")
        window.tick()
        #expect(window.framesDrawn - before == 1, "one frame for the key: \(window.framesDrawn - before)")
        #expect(caretBars(window).count == 1, "the caret is on right after a key")
    }
    window.advance(by: 0.5)
    #expect(caretBars(window).isEmpty, "off in the second half")
    window.advance(by: 0.5)
    #expect(caretBars(window).count == 1, "on again")
}
