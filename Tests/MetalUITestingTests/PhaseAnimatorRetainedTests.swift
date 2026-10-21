import Foundation
import MetalUI
import MetalUIScene
import MetalUITesting
import Testing

// G1 lane 2, `GS-P`: a `phaseAnimator` inside an `.equatable()` component, through a real
// `TestWindow` (the simulated clock). `keyframeAnimator`'s idle case is `SB-J`'s; this pins what
// the phase animator does there as it is — and carries any gap to C14-i (this item edits no
// `Retained*.swift`).

@MainActor private final class PhaseSeen { var phases: [Int] = [] }

private struct PulseHost: Component, @MainActor Equatable {
    let seen: PhaseSeen
    var content: some ElementGroup {
        Box().frame(width: Pixels(40), height: Pixels(10)).background(.accent)
            .phaseAnimator([0, 1, 2]) { content, p in
                let _ = seen.phases.append(p)
                content.opacity(p == 1 ? 0.5 : 1)
            } animation: { _ in .linear(duration: 0.4) }
    }
    static func == (l: PulseHost, r: PulseHost) -> Bool { true }
}

/// `GS-P`. A cycling animator inside an `.equatable()` component whose value never changes keeps
/// stepping: the occurrence is never skipped or replayed while a phase is due, so the phases seen
/// are the whole cycle in order. Mutation: the note of the active animation removed from
/// `PhaseAnimator.resolveStep` (the animator stalls at its first step after the frames stop coming).
@Test @MainActor func aPhaseAnimatorInsideAnEquatableComponentKeepsSteppingGSP() throws {
    let seen = PhaseSeen()
    let window = try TestWindow(size: Size(width: Pixels(200), height: Pixels(80)), textSystem: harnessTextSystem) {
        VStack(spacing: 4) { PulseHost(seen: seen).equatable() }
    }
    var f = window.lastFrameWork
    var trace: [String] = []
    var perTick: [Int] = []
    for _ in 0..<8 {
        window.tick()
        f = window.lastFrameWork
        perTick.append(seen.phases.last ?? -1)
        trace.append("\(seen.phases.last ?? -1) hits=\(f.retainedHits) miss=\(f.retainedMisses) inel=\(f.retainedIneligible) why=\(f.retainedIneligibleReasons) evals=\(f.contentEvaluations)")
        window.advance(by: 0.4)
    }
    print("GS-P trace: \(trace)")
    #expect(perTick == [1, 2, 0, 1, 2, 0, 1, 2], "one step per 0.4 s tick, in order: \(perTick)")
    #expect(f.retainedHits == 0 && f.retainedIneligible == 1, "never replayed, counted ineligible: \(trace.last ?? "")")
    #expect(f.retainedIneligibleReasons["timeVarying", default: 0] > 0, "refused by name, timeVarying: \(f.retainedIneligibleReasons)")
}
