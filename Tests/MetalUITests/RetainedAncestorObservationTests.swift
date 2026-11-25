import Testing
import Observation
import MetalUICore
import MetalUILayout
import MetalUIScene
import MetalUITesting
@testable import MetalUI

// `SB-AF` (record 403): a write to an `@Observable` that only a replayed descendant's prepaint read must redraw, though the ancestor
// re-armed its own windows in a frame where that descendant replayed. Alloy's `CodeDecorations` write under two nested
// `.equatable()` occurrences, distilled to a custom element.

@Observable @MainActor private final class ToneModel { var tone = 0 }
@Observable @MainActor private final class GateModel { var count = 0 }

/// Reads `tone` in `prepaint` only; paint draws what prepaint read (as `CodeView` draws its plan).
private struct PrepaintTone: Element {
    let model: ToneModel
    var elementID: ElementID? { nil }

    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 20)) }.layoutNodeID, ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, pass: inout PrepaintPass) -> Hsla {
        model.tone == 0 ? Hsla(h: 0.6, s: 1, l: 0.5, a: 1) : Hsla(h: 0.0, s: 1, l: 0.5, a: 1)
    }

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, prepaint: inout Hsla, pass: inout PaintPass) {
        pass.fill(bounds, color: prepaint)
    }
}

private struct InnerTone: Component, @MainActor Equatable {
    let model: ToneModel
    var content: some ElementGroup { PrepaintTone(model: model) }
    static func == (l: InnerTone, r: InnerTone) -> Bool { l.model === r.model }
}

/// Equal to its last value, yet its getter reads `gate`: a write to `gate` re-arms this occurrence's windows while the
/// inner occurrence, unchanged, replays.
private struct OuterGate: Component, @MainActor Equatable {
    let gate: GateModel
    let model: ToneModel
    var content: some ElementGroup {
        let _: Int = gate.count
        VStack(spacing: 0) { InnerTone(model: model).equatable() }
    }
    static func == (l: OuterGate, r: OuterGate) -> Bool { l.gate === r.gate && l.model === r.model }
}

/// A tone write after the outer occurrence re-armed over a replaying inner one draws the new tone, and the window is
/// dirtied by the write itself. **Mutation:** `flagAncestorsOfFires` returning at once: the write fires the inner session
/// alone, the outer record replays, and the old colour stays.
@MainActor @Test(arguments: [0, 1, 3]) func aWriteReadOnlyByAReplayedDescendantsPrepaintRedraws(gateWrites: Int) async throws {
    let gate = GateModel(), model = ToneModel()
    let window = try TestWindow(size: Size(width: Pixels(100), height: Pixels(60))) {
        VStack(spacing: 0) { OuterGate(gate: gate, model: model).equatable() }
    }
    for _ in 0..<4 { window.window.setNeedsRedraw(); window.tick() }
    #expect(window.lastFrameWork.retainedHits >= 1, "settled and replaying")
    for _ in 0..<gateWrites {
        gate.count += 1                                  // the outer occurrence misses and re-arms; the inner one replays
        for _ in 0..<3 { await Task.yield() }
        window.tick()
        for _ in 0..<2 { window.window.setNeedsRedraw(); window.tick() }
    }
    let before = window.scene.rects.last?.background
    model.tone = 1
    for _ in 0..<4 { await Task.yield() }   // off Apple platforms the dirty arrives a turn after the write (`IV-Q`)
    #expect(window.window.needsRedraw, "the write dirtied the window")
    window.tick()
    let after = window.scene.rects.last?.background
    let beforeTone = try #require(before, "the tone drawn before the write: \(String(describing: before)) \(String(describing: after))")
    let afterTone = try #require(after, "the tone drawn after the write: \(String(describing: before)) \(String(describing: after))")
    #expect(afterTone.h != beforeTone.h, "the new tone was drawn: \(String(describing: before)) \(String(describing: after))")
}
