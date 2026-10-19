import MetalUI
import MetalUIScene
import MetalUITesting
import MetalUITextSystem
import Testing

// C14b lane 1 (`SB-A`…`SB-R`): retained subtrees through a real `Window`, on the bracket window
// (`BracketFixture.swift`). Counts, never time. Predictions are fixed before the run (spec §8.1).

/// Test 1.1's predictions, fixed before the first run (record §109): per drag frame,
/// `hits / misses / ineligible`. They held for the 11 frames from the tenth on of the **first design**
/// (prepaint and paint replayed; `.value` 29 / 3 / 0, `.environment` 19 / 2 / 0, `.panels` 30 / 3 / 2; the third arm's last figure was a mispredicted ineligible top bar, see below) and,
/// after `SB-AA` moved the decision to paint with an exact "the hovered element is under me" rule, for all
/// of them: the nine earlier frames' extra miss (the pointer over node 14's status badge) is gone, because
/// the hovered element there is the node on top, not node 14. The release frame (no value moves) replays
/// every occurrence.
private struct Prediction {
    let arm: BracketArm
    let hits: Int, misses: Int, ineligible: Int
    /// Whether node bodies are retained (the `.environment` arm's nodes are refused).
    let retainsNodes: Bool
}
private let predictions = [
    Prediction(arm: .value, hits: 29, misses: 3, ineligible: 0, retainsNodes: true),
    // C14-c (`EE-J`): the `.environment` arm's nodes are memoized by their reading now, so it retains what `.value` does.
    Prediction(arm: .environment, hits: 29, misses: 3, ineligible: 0, retainsNodes: true),
    // `.environmentObject` is not predicted here (its per-node scope is one more element); `EnvironmentEpochBracketTests` B3.
    // `.value` plus the panels: the inspector and the top bar replay; the graph panel (a `List`, a `ScrollView`
    // and a `TextField` paint through `withState`, `SB-J`) is ineligible. Predicted 30 / 3 / 2 (the top bar
    // ineligible for its menu `Picker`): a Picker's paint writes nothing a record cannot replay.
    Prediction(arm: .panels, hits: 31, misses: 3, ineligible: 1, retainsNodes: true),
]

@Test(.enabled(if: !rsVerifying, "METALUI_VERIFY_RETAINED=1 paints a hit as a miss: the paint-skipped counts this test pins are not its to read"), arguments: [BracketArm.value, BracketArm.environment, BracketArm.panels]) @MainActor
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
        // Frame 20 is the release: nothing moved. The occurrences that changed in frame 19 replay if their
        // record there was fully observed and record once more if it covered only its paint (a record made on
        // a frame whose valid record missed does, `SB-V`): so 0...3 misses, never more than a drag frame's.
        if index == 20 {
            #expect(f.retainedHits >= predicted.hits)
            #expect(f.retainedMisses <= predicted.misses)
        } else {
            #expect(f.retainedHits == predicted.hits)
            #expect(f.retainedMisses == predicted.misses)
        }
        #expect(f.retainedIneligible == predicted.ineligible)
        // Paint and prepaint are the work a hit stands for, element by element (`RK-E`: prepaint replays too);
        // the build runs in full.
        #expect(f.elementPaints + f.retainedSkippedPaints == base.elementPaints)
        #expect(f.elementPaints < base.elementPaints)
        #expect(f.elementPrepaints + f.retainedSkippedPrepaints == base.elementPrepaints)
        if predicted.retainsNodes && index > 0 { #expect(f.retainedSkippedPrepaints > 0, "frame \(index) replayed no prepaint") }
        #expect(f.elementRequests == base.elementRequests)
        // Layout is the placement memo's (`SB-AD`): restored subtrees are not measured again, never more.
        if index == 0 {
            // The press frame: measure entries under a restored subtree are not refreshed by the restore, so
            // they have aged out (two frames) by the first miss, and that miss measures its subtree once (`SB-AD`).
            #expect(f.layoutMeasureCalls == (predicted.retainsNodes ? 135 : 52) && base.layoutMeasureCalls == 52, "frame 0: \(f.layoutMeasureCalls) vs \(base.layoutMeasureCalls)")
        } else {
            #expect(f.layoutMeasureCalls <= base.layoutMeasureCalls, "frame \(index): \(f.layoutMeasureCalls) vs \(base.layoutMeasureCalls)")
        }
        // The scene is the same scene, and the two changed wires are still rasterized.
        #expect(f.rects == base.rects)
        #expect(f.glyphs == base.glyphs)
        #expect(f.images == base.images)
        #expect(f.rasterizedPixels == base.rasterizedPixels)
        #expect(f.newTextures == base.newTextures)
    }
    // Text: a replayed label shapes and places nothing; a node that is not retained would still do (none is, since C14-c).
    if predicted.retainsNodes {
        #expect(on.counting.places < off.counting.places)
    } else {
        #expect(on.counting.places == off.counting.places)
    }
}
