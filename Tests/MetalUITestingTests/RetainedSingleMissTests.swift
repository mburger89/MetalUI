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
    @Test(arguments: [DMArm.value, .observed, .nested], [1, 3]) func aChangedOccurrenceCostsOneMissAndTheNextFrameHits(arm: DMArm, changed: Int) throws {
        let (window, model) = try doubleMissWindow(arm)
        // Steady frames hit everything (the control: the instrument sees eight hits and no miss when nothing changes).
        window.resetFrameWork()
        window.window.setNeedsRedraw(); window.tick()
        let steady = try #require(window.frameWork.last)
        // The nested arm: a changed inner misses and kills its ancestor's record (`SB-AC`): two misses per change on the change frame
        // (the inner's replayed-away occurrences count no hit), none after (`DM-L`).
        let total = 8, per = arm == .nested ? 2 : 1
        try #require(steady.retainedHits == total && steady.retainedMisses == 0, "steady: \(steady.retainedHits) hits \(steady.retainedMisses) misses")
        let set = Array(0..<changed).map { $0 * 2 }
        let step = doubleMissStep(window, model, arm: arm, changed: set, to: 3)
        #expect(step.change.retainedMisses == changed * per, "\(arm): the change frame misses the changed ones: \(step.change.retainedMisses)")
        #expect(step.change.retainedHits == total - changed)
        #expect(step.settle.retainedMisses == 0, "\(arm): the frame after a change hits (was \(changed) before DM-C): \(step.settle.retainedMisses)")
        #expect(step.settle.retainedHits == total)
        // Over the pair, misses equal changed occurrences and hits are up by the same amount.
        #expect(step.change.retainedMisses + step.settle.retainedMisses == changed * per)
        #expect(step.change.retainedHits + step.settle.retainedHits == 2 * total - changed)
    }

    /// 2 - the two coverage halves are recorded separately (`DM-M`): with the prepaint window closed by the seam the record's build half is
    /// observed and its prepaint half is not, so the frame after a change misses naming **exactly** `coverage.prepaint`; then it hits.
    /// **Mutations:** `record.coveragePrepaint = phase.build.observed` (the frame after hits: red) and `record.coverageBuild =
    /// phase.prepaintObserved` (names `coverage.build` too: red).
    @Test(.enabled(if: !rsVerifying, "METALUI_VERIFY_RETAINED=1 paints a hit as a miss")) func theCoverageHalvesAreRecordedSeparately() throws {
        let (window, model) = try doubleMissWindow(.value)
        RetainedTestingHooks.closesPrepaintWindow = true
        defer { RetainedTestingHooks.closesPrepaintWindow = false }
        var settle = FrameWork()
        let lines = collectTrace {
            let step = doubleMissStep(window, model, arm: .value, changed: [1], to: 3)
            settle = step.settle
        }
        let second = lines.filter { $0.hasPrefix("retained paint miss") }.compactMap(traceReasons).filter { $0.contains { $0.hasPrefix("coverage") } }
        #expect(second == [["coverage.prepaint"]], "exactly the prepaint half is named: \(second)")
        #expect(settle.retainedMisses == 1)
    }

    /// 2b - the key-only arm is carried, not fixed (`DM-D`, to C14-k): a fractional-width change moves every later node by a delta the translation refuses,
    /// so the change frame and the frame after each miss four of eight (measured: h4 m4 and h4 m4, the second naming `coverage.build, coverage.prepaint`
    /// among key differences). The twin pin (3) holds on this arm. **Mutation:** none (a count of a carried cost); it reddens when C14-k lands.
    @Test func theKeyOnlyArmStillCostsTwoFramesOfMisses() throws {
        let (window, model) = try doubleMissWindow(.moved)
        let step = doubleMissStep(window, model, arm: .moved, changed: [1, 4], to: 3)
        #expect(step.change.retainedMisses == 4 && step.change.retainedHits == 4, "change: h\(step.change.retainedHits) m\(step.change.retainedMisses)")
        #expect(step.settle.retainedMisses == 4 && step.settle.retainedHits == 4, "settle: h\(step.settle.retainedHits) m\(step.settle.retainedMisses)")
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
    /// settle between), and again after a hit frame that replayed it, must miss and draw what the retention-off twin draws; a record
    /// declared complete without its windows would replay the old scene. **Mutation (measured, C14-j lane 2 verify):** `needsObservation`
    /// without the certain-miss terms **and** `coverageBuild`/`coveragePrepaint` set `true` at the record (windows closed, coverage
    /// declared): the immediate write alone did NOT redden (the standing record's sessions still cover it), the write after the hit does.
    @Test(arguments: [false, true]) func aStaleSessionStillFiresAfterTheSameFrameRecord(afterAHit: Bool) throws {
        let (on, onModel) = try doubleMissWindow(.observed)
        let (off, offModel) = try doubleMissWindow(.observed, retain: false)
        for (model, window) in [(onModel, on), (offModel, off)] {
            model.params[2].radius = 4
            window.window.setNeedsRedraw(); window.tick()
        }
        if afterAHit {
            for window in [on, off] { window.window.setNeedsRedraw(); window.tick() }   // the settle frame: a hit on the retained twin
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
