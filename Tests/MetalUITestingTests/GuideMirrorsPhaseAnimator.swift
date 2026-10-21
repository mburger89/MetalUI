import MetalUI
import MetalUITesting
import Testing

// G1 lane 2 — the mirror of the `phaseAnimator` block of `docs/guides/drawing-and-gpu.md` (item G1; `GS-M`, `DG-C`,
// `DG-D`): copied BY HAND between the `// guide:` and `// end guide` markers, byte for byte, so the ordinary build
// compiles it on every platform; `GuideDocCheck.swift` compares it with the guide. Below it, the test the guide pins.
// Mutations: delete `.phaseAnimator(...)` from either struct (the bars never move); delete `trigger: taps` (the swing
// becomes a cycle and moves with no change of `taps`).

// guide: drawing-and-gpu #8
/// A badge that pulses for ever, and a bar that swings once each time `taps` changes.
struct DrawingPulse: Component {
    var content: some ElementGroup {
        Rectangle().frame(width: Pixels(40), height: Pixels(20))
            .accessibilityIdentifier("pulse")
            .phaseAnimator([Pixels(0), Pixels(10)]) { content, shift in
                content.offset(x: shift)
            } animation: { _ in .linear(duration: 0.2) }
    }
}

struct DrawingSwing: Component {
    let taps: Int

    var content: some ElementGroup {
        Rectangle().frame(width: Pixels(40), height: Pixels(20))
            .accessibilityIdentifier("swing")
            .phaseAnimator([Pixels(0), Pixels(12), Pixels(-12)], trigger: taps) { content, shift in
                content.offset(x: shift)
            } animation: { _ in .linear(duration: 0.1) }
    }
}
// end guide

@MainActor private final class DrawingTaps { var n = 0 }

/// The pulse moves and returns while nothing else happens; the swing sits still until `taps` changes, then goes out
/// to +12, to -12 and home, and sits still again.
@Test @MainActor func theDrawingGuideAPulseCyclesAndASwingRunsOncePerTrigger() throws {
    let taps = DrawingTaps()
    let window = try harnessWindow { Column { DrawingPulse(); DrawingSwing(taps: taps.n) } }
    let pulseHome = try window.element(identifier: "pulse").frame.origin.x.value
    let swingHome = try window.element(identifier: "swing").frame.origin.x.value
    var pulse: [Float] = [], swing: [Float] = []
    for _ in 0..<24 {
        window.advance(by: 0.05)
        pulse.append(try window.element(identifier: "pulse").frame.origin.x.value - pulseHome)
        swing.append(try window.element(identifier: "swing").frame.origin.x.value - swingHome)
    }
    #expect((pulse.max() ?? 0) > 5 && (pulse.min() ?? 0) < 5, "the pulse goes out and comes back: \(pulse)")
    #expect(swing.allSatisfy { $0 == 0 }, "no change of taps, no swing: \(swing)")
    taps.n += 1
    window.window.setNeedsRedraw()
    var run: [Float] = []
    for _ in 0..<12 {
        window.advance(by: 0.05)
        run.append(try window.element(identifier: "swing").frame.origin.x.value - swingHome)
    }
    #expect((run.max() ?? 0) > 6 && (run.min() ?? 0) < -6, "the swing goes out to +12 and to -12: \(run)")
    #expect(abs(run.last ?? 99) < 0.5, "and ends at home: \(run)")
}
