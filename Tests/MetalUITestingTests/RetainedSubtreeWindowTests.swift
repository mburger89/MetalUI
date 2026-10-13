import MetalUI
import MetalUIScene
import MetalUITesting
import MetalUITextSystem
import Testing

// C14b lane 1 (`SB-A`…`SB-R`): retained subtrees through a real `Window`, on the bracket window
// (`BracketFixture.swift`). Counts, never time. Predictions are fixed before the run (spec §8.1).

/// The predictions of test 1.1 (written before replay existed; the observed values are in record
/// §109): per drag frame, `hits / misses / ineligible`.
private struct Prediction {
    let arm: BracketArm
    let hits: Int, misses: Int, ineligible: Int
}
private let predictions = [
    // 29 unchanged occurrences (10 nodes, 19 wires) replay; the dragged node's two wires and its
    // own... (the dragged node's `==` is false: its value carries the position) re-evaluate.
    Prediction(arm: .value, hits: 29, misses: 3, ineligible: 0),
    // The refused nodes (divergence 346) have no memo entry and so no record; the 19 unchanged wires replay.
    Prediction(arm: .environment, hits: 19, misses: 2, ineligible: 0),
    // `.value` plus the panels: the inspector replays; the graph panel (a `List` and a `ScrollView`
    // register scroll regions, `SB-J`) and the top bar (a menu `Picker`) are ineligible.
    Prediction(arm: .panels, hits: 30, misses: 3, ineligible: 2),
]

@Test(arguments: [BracketArm.value, BracketArm.environment, BracketArm.panels]) @MainActor
func theBracketNodeDragReplaysEveryUnchangedSubtree(arm: BracketArm) throws {
    let predicted = try #require(predictions.first { $0.arm == arm })
    let on = try bracketDragFrames(arm: arm, steps: 20, retained: true)
    let off = try bracketDragFrames(arm: arm, steps: 20, retained: false)
    try #require(on.frames.count == 21)
    try #require(off.frames.count == 21)
    for index in 2..<20 {
        let f = on.frames[index], base = off.frames[index]
        // The conservation identity (`SB-Q`): every evaluated or skipped occurrence is counted once.
        #expect(f.retainedHits + f.retainedMisses + f.retainedIneligible == f.contentEvaluations + f.contentSkips)
        #expect(f.retainedHits == predicted.hits)
        #expect(f.retainedMisses == predicted.misses)
        #expect(f.retainedIneligible == predicted.ineligible)
        // The work a hit stands for is the work memo-off does: prepaint and paint, element by element.
        #expect(f.elementPrepaints + f.retainedSkippedPrepaints == base.elementPrepaints)
        #expect(f.elementPaints + f.retainedSkippedPaints == base.elementPaints)
        #expect(f.elementPaints < base.elementPaints)
        // The build recursion is still paid in full (lane 1).
        #expect(f.elementRequests == base.elementRequests)
        #expect(f.layoutMeasureCalls == base.layoutMeasureCalls)
        // The scene is the same scene, and the two changed wires are still rasterized.
        #expect(f.rects == base.rects)
        #expect(f.glyphs == base.glyphs)
        #expect(f.images == base.images)
        #expect(f.rasterizedPixels == base.rasterizedPixels)
        #expect(f.newTextures == base.newTextures)
    }
    // Text: a replayed label shapes and places nothing.
    #expect(on.counting.places < off.counting.places)
}
