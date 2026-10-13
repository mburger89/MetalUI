import MetalUI
import MetalUIScene
import MetalUITesting
import MetalUITextSystem
import Testing

// C14b lane 1 (`SB-A`…`SB-R`): retained subtrees through a real `Window`, on the bracket window
// (`BracketFixture.swift`). Counts, never time. Predictions are fixed before the run (spec §8.1).

/// Test 1.1's predictions, fixed before the first run (record §109): per drag frame,
/// `hits / misses / ineligible`. They held for the 11 frames from the tenth on (`.value`
/// 29 / 3 / 0, `.environment` 19 / 2 / 0, `.panels` 30 / 3 / 2). **In the nine frames before, one
/// hit less and one miss more in the arms that retain nodes, and it is correct**: the press at
/// x = 20 and the 2 pt drags keep the pointer over the status badge of node 14 (Edge Filter, flush
/// right of x = 48) until x = 38 + 2 pt per frame passes it; the badge's `.help` hitbox is the
/// subtree's own, so "the pointer is inside an owned hitbox" (`SB-F` item 4) makes it re-paint.
/// The `.environment` arm has no record for a node (it is refused), so it reads as predicted
/// throughout. The release frame (no value moves) replays every occurrence.
private struct Prediction {
    let arm: BracketArm
    let hits: Int, misses: Int, ineligible: Int
    /// Whether node bodies are retained (the `.environment` arm's nodes are refused).
    let retainsNodes: Bool
}
private let predictions = [
    Prediction(arm: .value, hits: 29, misses: 3, ineligible: 0, retainsNodes: true),
    Prediction(arm: .environment, hits: 19, misses: 2, ineligible: 0, retainsNodes: false),
    // `.value` plus the panels: the inspector replays; the graph panel (a `List` and a `ScrollView`
    // register scroll regions, `SB-J`) and the top bar (a menu `Picker`) are ineligible.
    Prediction(arm: .panels, hits: 30, misses: 3, ineligible: 2, retainsNodes: true),
]

@Test(arguments: [BracketArm.value, BracketArm.environment, BracketArm.panels]) @MainActor
func theBracketNodeDragReplaysEveryUnchangedSubtree(arm: BracketArm) throws {
    let predicted = try #require(predictions.first { $0.arm == arm })
    let on = try bracketDragFrames(arm: arm, steps: 20, retained: true)
    let off = try bracketDragFrames(arm: arm, steps: 20, retained: false)
    try #require(on.frames.count == 21)
    try #require(off.frames.count == 21)
    for index in 0..<21 {
        let f = on.frames[index], base = off.frames[index]
        // The conservation identity (`SB-Q`): every evaluated or skipped occurrence is counted once.
        #expect(f.retainedHits + f.retainedMisses + f.retainedIneligible == f.contentEvaluations + f.contentSkips)
        // Drag frames 0...8: the pointer is over node 14's badge. Frame 20: the release, nothing moved.
        let overBadge = predicted.retainsNodes && index <= 8
        if index == 20 {
            #expect(f.retainedMisses == 0)
            #expect(f.retainedHits == f.contentEvaluations + f.contentSkips - f.retainedIneligible)
        } else {
            #expect(f.retainedHits == predicted.hits - (overBadge ? 1 : 0))
            #expect(f.retainedMisses == predicted.misses + (overBadge ? 1 : 0))
        }
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
    // Text: a replayed label shapes and places nothing; a refused node (`.environment`) still does.
    if predicted.retainsNodes {
        #expect(on.counting.places < off.counting.places)
    } else {
        #expect(on.counting.places == off.counting.places)
    }
}
