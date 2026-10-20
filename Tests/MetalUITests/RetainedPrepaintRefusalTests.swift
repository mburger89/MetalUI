import Foundation
import Testing
import MetalUICore
import MetalUILayout
import MetalUIScene
import MetalUITesting
@testable import MetalUI

// C14b-2 lane 1 (`RK-E`): the prepaint refusals that nothing else guards. A scroll view, a text field, a presented popover and a
// drag source are also ineligible at **paint** (their paint writes state or pushes a capturing scope), so the kinds test in
// `MetalUITestingTests` cannot tell the prepaint refusal from the paint one for them; an element whose **prepaint alone**
// writes can. Counts only.

enum PrepaintWrite: String, CaseIterable, Sendable {
    /// Replayable: writes nothing (the separating control).
    case nothing
    /// `withState` in prepaint (not the accessibility node's own retention slot).
    case stateWrite
    /// A noted live animation or another-frame request in prepaint.
    case anotherFrame
    /// A presentation anchor: replayed now (`RW-K`), so it behaves as the control does.
    case anchor

    /// Whether the occurrence's prepaint replays.
    var replays: Bool { self == .nothing || self == .anchor }
}

private struct PrepaintWriter: Element {
    let write: PrepaintWrite
    var elementID: ElementID? { nil }

    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 20)) }.layoutNodeID, ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, pass: inout PrepaintPass) {
        switch write {
        case .nothing: break
        case .stateWrite: pass.withState(id, initial: 0) { $0 += 1 }
        case .anotherFrame: pass.frame.requestAnotherFrame()
        case .anchor: pass.frame.recordPresentationAnchor(id, bounds: bounds)
        }
    }

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, prepaint: inout Void,
               pass: inout PaintPass) {
        pass.fill(bounds, color: Hsla(h: 0.6, s: 1, l: 0.5, a: 1))
    }
}

private struct PrepaintWriterHolder: Component, @MainActor Equatable {
    let write: PrepaintWrite
    var content: some ElementGroup { PrepaintWriter(write: write) }
    static func == (l: PrepaintWriterHolder, r: PrepaintWriterHolder) -> Bool { l.write == r.write }
}

private struct PrepaintControlHolder: Component, @MainActor Equatable {
    var content: some ElementGroup { PrepaintWriter(write: .nothing) }
    static func == (l: PrepaintControlHolder, r: PrepaintControlHolder) -> Bool { true }
}

/// 7b — an occurrence whose **prepaint alone** writes a channel a ledger does not replay (state, a live-animation note, a
/// presentation anchor, which `RW-K` made replayable: that arm now replays like the control) paints from a record (`retainedHits == 2`) and runs its prepaint every frame, counted ineligible by
/// name; its control neighbour replays both. Mutation, per arm: that channel's audit or taint removed (`StateTable.withState`'s
/// taint; `PrepaintAudit.movedChannel`'s `timeVarying`, `anchors`) — the arm's occurrence replays its prepaint
/// (`retainedPrepaintHits == 2`).
@Test(arguments: PrepaintWrite.allCases) @MainActor
func aPrepaintThatAloneWritesAChannelRunsEveryFrame(write: PrepaintWrite) async throws {
    let window = try TestWindow(size: Size(width: Pixels(120), height: Pixels(80))) {
        VStack(spacing: 4) {
            PrepaintControlHolder().equatable()
            PrepaintWriterHolder(write: write).equatable()
        }
    }
    for _ in 0..<5 { window.window.setNeedsRedraw(); window.tick() }
    window.window.setNeedsRedraw(); window.tick()
    let f = window.lastFrameWork
    #expect(f.retainedHits == 2, "both paint from a record: \(f.retainedHits)/\(f.retainedMisses)/\(f.retainedIneligible)")
    if write.replays {
        #expect(f.retainedPrepaintHits == 2, "\(write.rawValue) replays: \(f.retainedPrepaintHits)")
        #expect(f.retainedPrepaintIneligible == 0)
    } else {
        #expect(f.retainedPrepaintHits == 1, "only the control replays prepaint: \(f.retainedPrepaintHits)")
        #expect(f.retainedPrepaintIneligible == 1, "the writer is refused by name: \(f.retainedPrepaintIneligible)")
    }
}
