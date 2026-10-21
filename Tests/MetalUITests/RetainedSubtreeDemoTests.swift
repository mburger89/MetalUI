import Testing
import MetalUI
import MetalUIScene
import MetalUITesting
@testable import MetalUIDemoContent

// The retained-subtree demo (`METALUI_RETAINED_DEMO=1`, spec §13) under the harness: dragging one node
// of eight leaves 40 occurrences (8 nodes, 7 wires, the panel strip of `RW-`: a field, a list and a picker whose state it
// only reads, and the 24 cards of the shift-and-scroll section of `FS-D`, which a node drag does not move) of which the dragged node
// and its two wires re-run and the other thirty-seven replay; with replay off none do and the drawn scene is the same.
// Mutation: `hit = false` in `retainedPrepaintDecision` reads 0 hits.

@MainActor private func dragFillet(replay: Bool) throws -> (FrameWork, [MUIRectSnapshot]) {
    retainedSubtreeDemoModel.reset()
    let window = try TestWindow(size: Size(width: Pixels(920), height: Pixels(560)), content: retainedSubtreeDemoContent)
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

@Test @MainActor func theRetainedSubtreeDemoReplaysEveryNodeButTheDraggedOneAndItsWires() throws {
    let (on, sceneOn) = try dragFillet(replay: true)
    let (off, sceneOff) = try dragFillet(replay: false)
    #expect(on.retainedHits + on.retainedMisses + on.retainedIneligible == 41)
    #expect(on.retainedMisses == 3, "the dragged node and its two wires: \(on.retainedMisses)")
    #expect(on.retainedHits == 38, "the panel strip, the section's cards and the geometry reader replay with the nodes: \(on.retainedHits)")
    #expect(on.retainedIneligible == 0)
    #expect(off.retainedHits == 0)
    #expect(on.elementPaints + on.retainedSkippedPaints == off.elementPaints)
    #expect(sceneOn == sceneOff, "replay changes who runs, not what is drawn")
}
