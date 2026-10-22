import Foundation
@testable import MetalUI
import MetalUIPlatform
import MetalUIScene
import MetalUITesting
import Testing

// C14-j lane 2 (`DM-B`, `DM-C`, `DM-J`): a changed `.equatable()` occurrence costs one miss, not two. The record a change frame's
// miss makes must be `coverageComplete` the same frame (its build and prepaint windows opened because the frame was a certain
// miss), so the next unchanged frame hits. Counts only; the oracle is a retention-off twin.
//
// **Red before the change** (measured, record 140): `aChangedOccurrenceCostsOneMissAndTheNextFrameHits` read 2 misses per change
// (the settle frame missed every changed occurrence, naming `coverage.build, coverage.prepaint`).

/// What a script step costs: the change frame and the settle frame after it.
struct DMStep { let change: FrameWork; let settle: FrameWork }

@Suite(.serialized) @MainActor
struct RetainedSingleMissTests {
    /// 1 - one miss per changed occurrence, on the arms that change a value or an observed read: the change frame misses exactly the
    /// changed ones, the settle frame misses none and hits all eight, so over the pair misses == changed and hits are up by the same
    /// count (conservation: hits + misses is 8 a frame). **Mutation:** restore `needsObservation` to
    /// `record == nil || record?.coverageComplete == false` (reddens `.value` and `.observed`).
    @Test(arguments: [DMArm.value, .observed], [1, 3]) func aChangedOccurrenceCostsOneMissAndTheNextFrameHits(arm: DMArm, changed: Int) throws {
        let (window, model) = try doubleMissWindow(arm)
        // Steady frames hit everything (the control: the instrument sees eight hits and no miss when nothing changes).
        window.resetFrameWork()
        window.window.setNeedsRedraw(); window.tick()
        let steady = try #require(window.frameWork.last)
        try #require(steady.retainedHits == 8 && steady.retainedMisses == 0, "steady: \(steady.retainedHits) hits \(steady.retainedMisses) misses")
        let set = Array(0..<changed).map { $0 * 2 }
        let step = doubleMissStep(window, model, arm: arm, changed: set, to: 3)
        #expect(step.change.retainedMisses == changed, "\(arm): the change frame misses the changed ones: \(step.change.retainedMisses)")
        #expect(step.change.retainedHits == 8 - changed)
        #expect(step.settle.retainedMisses == 0, "\(arm): the frame after a change hits (was \(changed) before DM-C): \(step.settle.retainedMisses)")
        #expect(step.settle.retainedHits == 8)
        // Over the pair, misses equal changed occurrences and hits are up by the same amount.
        #expect(step.change.retainedMisses + step.settle.retainedMisses == changed)
        #expect(step.change.retainedHits + step.settle.retainedHits == 16 - changed)
    }

    /// 3 - the single-miss frames equal a retention-off twin: scene, hitboxes, accessibility, tallies, bounds, every script frame.
    /// **Mutation:** record the change frame's record as complete with its windows closed (`aStaleSession...` and this one redden).
    @Test(arguments: DMArm.allCases) func theSingleMissFrameEqualsRetentionOff(arm: DMArm) throws {
        let (on, onModel) = try doubleMissWindow(arm)
        let (off, offModel) = try doubleMissWindow(arm, retain: false)
        for (k, set) in [[1, 4], [0], [2, 3, 5], [7]].enumerated() {
            let value = Double(k + 2)
            _ = doubleMissStep(on, onModel, arm: arm, changed: set, to: value)
            _ = doubleMissStep(off, offModel, arm: arm, changed: set, to: value)
            let difference = try RPSnapshot(on).differences(from: RPSnapshot(off))
            #expect(difference.isEmpty, "\(arm) step \(k): \(difference)")
        }
    }

    /// 4 - soundness: the record the change frame made is armed. A write of the observed read right after the change frame (no
    /// settle between) must miss and draw what the retention-off twin draws; a record declared complete without its windows would
    /// replay the old scene. **Mutation:** mark `coverageComplete = true` on the change frame without opening the windows.
    @Test func aStaleSessionStillFiresAfterTheSameFrameRecord() throws {
        let (on, onModel) = try doubleMissWindow(.observed)
        let (off, offModel) = try doubleMissWindow(.observed, retain: false)
        for (model, window) in [(onModel, on), (offModel, off)] {
            model.params[2].radius = 4
            window.window.setNeedsRedraw(); window.tick()
        }
        on.resetFrameWork()
        for (model, window) in [(onModel, on), (offModel, off)] {
            model.params[2].radius = 6   // lands on the session the change frame's record armed
            window.window.setNeedsRedraw(); window.tick()
        }
        let work = try #require(on.frameWork.last)
        #expect(work.retainedMisses == 1, "the written occurrence misses (its session fired): \(work.retainedMisses)")
        let difference = try RPSnapshot(on).differences(from: RPSnapshot(off))
        #expect(difference.isEmpty, "\(difference)")
    }
}
