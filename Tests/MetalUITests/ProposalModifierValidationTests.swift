import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUI

// Lane 3 ("robustness") of `docs/superpowers/specs/2026-09-14-native-kernel-completion-design.md`:
// the proposal MODIFIERS accept what the kernel accepts (ruling SA-K item 4).
// `.layoutPriority` and `.aspectRatio` repeated the kernel's old preconditions
// at construction; if the two layers disagree, an element spelling traps where
// the kernel registrar would not.

private final class ModifierProbe: @unchecked Sendable {
    var boundsByName: [String: Bounds<Pixels>] = [:]
}

/// A leaf answering `min(ideal, proposal.width ?? ideal)` × 10, or its proposal
/// when `echoes`, recording its prepaint bounds by name.
private struct ModifierProbeLeaf: ProposalElement {
    let ideal: Double
    let echoes: Bool
    let name: String
    let probe: ModifierProbe

    func requestProposalLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (ProposalNodeID, Void) {
        let ideal = ideal
        let echoes = echoes
        return (pass.requestNativeLeaf { proposal in
            echoes
                ? LayoutMeasurement(size: SizeD(width: proposal.width ?? ideal, height: proposal.height ?? 10))
                : LayoutMeasurement(size: SizeD(width: Swift.min(ideal, proposal.width ?? ideal), height: 10))
        }, ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                  pass: inout PrepaintPass) {
        probe.boundsByName[name] = bounds
    }

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
               prepaint: inout Void, pass: inout PaintPass) {}
}


/// `Rectangle().layoutPriority(.infinity)` and `.aspectRatio(-2)` construct and
/// render through a real `Frame`, and the kernel gives SwiftUI's answers.
///
/// **An exit `.success` test**, because its red run is a trap at construction,
/// which in-process would abort the whole `MetalUITests` process.
///
/// By hand, in a 140×90 frame:
/// - an `HStack(spacing: 0)` of two leaves capped at ideal 100, the first
///   under `.layoutPriority(.infinity)`: natural 200 overflows 140; +∞ takes
///   its 100 first and the priority-0 leaf gets the remaining 40. The stack is
///   140 × 10, centred vertically at y 40: (0, 40, 100, 10) and
///   (100, 40, 40, 10). At priority 0 both would be 70.
/// - a `ZStack(alignment: .topLeading)` offering 140×90 to a proposal-echoing
///   leaf under `.aspectRatio(-2)`: `.fit` compares `140 / −2 = −70 <= 90`, the
///   width branch, so the ratio answers 140 × −70 (P8's shape) and stores its
///   child at the stack's origin at that size: (0, 0, 140, −70). The same
///   stack holds `Rectangle().layoutPriority(.infinity)` and
///   `Rectangle().aspectRatio(-2)`, which must render too.
///
/// Red after under "leave `NativeModifiedContent.swift`'s preconditions
/// unchanged".
@Test func theProposalModifiersAcceptWhatTheKernelAccepts() async {
    await #expect(processExitsWith: .success) {
        await MainActor.run {
            let priority = ModifierProbe()
            var stack = HStack(spacing: Pixels(0)) {
                ModifierProbeLeaf(ideal: 100, echoes: false, name: "prioritized", probe: priority)
                    .layoutPriority(.infinity)
                ModifierProbeLeaf(ideal: 100, echoes: false, name: "other", probe: priority)
            }
            Frame(contentSize: Size(width: Pixels(140), height: Pixels(90)), scaleFactor: 1).render(&stack)
            let prioritized = priority.boundsByName["prioritized"]
            let other = priority.boundsByName["other"]
            precondition(prioritized == Bounds(origin: Point(x: Pixels(0), y: Pixels(40)),
                                               size: Size(width: Pixels(100), height: Pixels(10))),
                         "the +∞-priority leaf rendered at \(String(describing: prioritized))")
            precondition(other == Bounds(origin: Point(x: Pixels(100), y: Pixels(40)),
                                         size: Size(width: Pixels(40), height: Pixels(10))),
                         "the priority-0 leaf rendered at \(String(describing: other))")

            let ratio = ModifierProbe()
            var overlay = ZStack(alignment: .topLeading) {
                Rectangle().layoutPriority(.infinity)
                Rectangle().aspectRatio(-2)
                ModifierProbeLeaf(ideal: 10, echoes: true, name: "ratio", probe: ratio).aspectRatio(-2)
            }
            Frame(contentSize: Size(width: Pixels(140), height: Pixels(90)), scaleFactor: 1).render(&overlay)
            let ratioBounds = ratio.boundsByName["ratio"]
            precondition(ratioBounds == Bounds(origin: Point(x: Pixels(0), y: Pixels(0)),
                                               size: Size(width: Pixels(140), height: Pixels(-70))),
                         "the −2 ratio's child rendered at \(String(describing: ratioBounds))")
        }
    }
}
