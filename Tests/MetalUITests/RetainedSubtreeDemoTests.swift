import Foundation
import Testing
import MetalUI
import MetalUIScene
import MetalUITesting
@testable import MetalUIDemoContent

// The retained-subtree demo (`METALUI_RETAINED_DEMO=1`, spec §13) under the harness: dragging one node
// of eight leaves 50 occurrences (8 nodes, 7 wires, the panel strip of `RW-`: a field, a list and a picker whose state it
// only reads, and the 24 cards of the shift-and-scroll section of `FS-D`, which a node drag does not move, and the ten cards of the zoom section of
// `RZ-A`, likewise) of which the dragged node and its two wires re-run and the other forty-seven replay; with replay off none do and the drawn scene is the same.
// Mutation: `hit = false` in `retainedPrepaintDecision` reads 0 hits.

@MainActor private func dragFillet(replay: Bool) throws -> (FrameWork, [MUIRectSnapshot]) {
    retainedSubtreeDemoModel.reset()
    let window = try TestWindow(size: Size(width: Pixels(920), height: Pixels(680)), content: retainedSubtreeDemoContent)
    window.window.testingRetainedSubtrees = replay
    for _ in 0..<3 { window.window.setNeedsRedraw(); window.tick() }
    let frame = try window.element(label: "Fillet").frame
    let start = Point(x: Pixels(frame.origin.x.value + 20), y: Pixels(frame.origin.y.value + 8))
    window.drag(from: start, to: Point(x: Pixels(start.x.value + 40), y: start.y), steps: 20)
    let work = window.frameWork[window.frameWork.count / 2]
    return (work, window.scene.rects.map(MUIRectSnapshot.init))
}

struct MUIRectSnapshot: Equatable {
    let values: [Float]
    init(_ rect: MUIRect) {
        values = [rect.bounds.origin.x, rect.bounds.origin.y, rect.bounds.size.width, rect.bounds.size.height,
                  rect.background.h, rect.background.s, rect.background.l, rect.background.a]
    }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["METALUI_VERIFY_RETAINED"] != "1",
               "METALUI_VERIFY_RETAINED=1 records every hit as a hit after a fresh run: the demo's miss count reads 0 there"))
@MainActor func theRetainedSubtreeDemoReplaysEveryNodeButTheDraggedOneAndItsWires() throws {
    let (on, sceneOn) = try dragFillet(replay: true)
    let (off, sceneOff) = try dragFillet(replay: false)
    #expect(on.retainedHits + on.retainedMisses + on.retainedIneligible == 51)
    #expect(on.retainedMisses == 3, "the dragged node and its two wires: \(on.retainedMisses)")
    #expect(on.retainedHits == 48, "the panel strip, the section's cards, the geometry reader and the zoom section's ten cards replay with the nodes: \(on.retainedHits)")
    #expect(on.retainedIneligible == 0)
    #expect(off.retainedHits == 0)
    #expect(on.elementPaints + on.retainedSkippedPaints == off.elementPaints)
    #expect(sceneOn == sceneOff, "replay changes who runs, not what is drawn")
}
