import Foundation
@testable import MetalUI
import MetalUIPlatform
import MetalUIScene
import MetalUITesting
import Testing

// C14-k (`AM-A`, `AM-B`): an occurrence that misses on its key alone (a fractional device-pixel move the translation refuses, the `.moved`
// arm of `DoubleMissFixture`) leaves a record that hits the next frame. Counts only; the oracle is a retention-off twin.
//
// **Red before the change** (measured, record 146): `aMovedOccurrenceCostsOneMissAndTheNextFrameHits` read settle h4 m4 (the frame after
// each moved miss named `coverage.build, coverage.prepaint` among its reasons).

/// A class the root reads each frame: a custom environment value written above the occurrences (an ambient difference).
@MainActor final class AMEnvBox { var n = 0 }

@MainActor func ambientMissWindow() throws -> (TestWindow, DMModel, AMEnvBox) {
    let model = DMModel()
    let box = AMEnvBox()
    let options = HeadlessPlatformWindow.Options(appearance: .light, scaleFactor: 2, accessibilityClientActive: true)
    let window = try TestWindow(size: sz(900, 120), colorScheme: .light, scaleFactor: 2, options: options, textSystem: harnessTextSystem) {
        VStack(spacing: 0) { DMParent(model: model, arm: .plain).environment(\.eeInt, box.n) }
    }
    window.window.testingRetainedGraft = true
    window.window.testingRetainedSubtrees = true
    for _ in 0..<4 { window.window.setNeedsRedraw(); window.tick() }
    return (window, model, box)
}

@Suite(.serialized) @MainActor
struct RetainedMoveMissTests {
    /// 1 - a moved occurrence costs one miss and the frame after hits everything. `.moved`, nodes 1 and 4 change by a fractional width:
    /// the change frame misses four (the two changed, two moved later ones), the settle frame **h8 m0**, a third frame the same.
    /// **Mutations:** the predictor off (`prepaintObserved` as before: names `coverage.prepaint`), the inheritance off (names `coverage.build`).
    @Test(.enabled(if: !rsVerifying, "METALUI_VERIFY_RETAINED=1 paints a hit as a miss")) func aMovedOccurrenceCostsOneMissAndTheNextFrameHits() throws {
        let (window, model) = try doubleMissWindow(.moved)
        var reasons: [[String]] = []
        var step = DMStep(change: FrameWork(), settle: FrameWork())
        let lines = collectTrace {
            let s = doubleMissStep(window, model, arm: .moved, changed: [1, 4], to: 3)
            step = DMStep(change: s.change, settle: s.settle)
        }
        _ = lines.compactMap(traceReasons).map { reasons.append($0) }
        window.resetFrameWork()
        window.window.setNeedsRedraw(); window.tick()
        let third = try #require(window.frameWork.last)
        #expect(step.change.retainedMisses == 4 && step.change.retainedHits == 4, "change: h\(step.change.retainedHits) m\(step.change.retainedMisses)")
        #expect(step.settle.retainedMisses == 0 && step.settle.retainedHits == 8, "settle: h\(step.settle.retainedHits) m\(step.settle.retainedMisses) \(reasons)")
        #expect(third.retainedMisses == 0 && third.retainedHits == 8, "third: h\(third.retainedHits) m\(third.retainedMisses)")
        // Over the script each moved or changed occurrence missed exactly once.
        #expect(step.change.retainedMisses + step.settle.retainedMisses + third.retainedMisses == 4)
    }

    /// 2 - the oracle (not the instrument): every step of a script on the moved arms equals a retention-off twin: scene, hitboxes,
    /// accessibility, tallies, bounds.
    @Test(arguments: [DMArm.moved, .movedPlain]) func theMovedFrameEqualsRetentionOff(arm: DMArm) throws {
        let (on, onModel) = try doubleMissWindow(arm)
        let (off, offModel) = try doubleMissWindow(arm, retain: false)
        for (k, set) in [[1, 4], [0], [2, 3, 5], [7], [1, 4]].enumerated() {
            let value = Double(k + 2)
            _ = doubleMissStep(on, onModel, arm: arm, changed: set, to: value)
            _ = doubleMissStep(off, offModel, arm: arm, changed: set, to: value)
            let difference = try RPSnapshot(on).differences(from: RPSnapshot(off))
            #expect(difference.isEmpty, "\(arm) step \(k): \(difference)")
        }
    }

    /// 3 - soundness: a write of a plain child's observed read after a moved miss (and again after the hit that replayed it) is seen: the
    /// written occurrence misses and the frame equals the twin. **Mutation:** inherit the build coverage on every miss (drops the geometry-only and
    /// `valid` guards): the ambient arm of test 4 reddens; this arm is the soundness control for the guarded inheritance.
    @Test(arguments: [false, true]) func aWriteAfterAMovedMissIsStillSeen(afterAHit: Bool) throws {
        let (on, onModel) = try doubleMissWindow(.movedPlain)
        let (off, offModel) = try doubleMissWindow(.movedPlain, retain: false)
        for (model, window) in [(onModel, on), (offModel, off)] {
            model.values[1] = 3   // nodes after 1 move by a fractional device pixel: key-only misses
            window.window.setNeedsRedraw(); window.tick()
        }
        if afterAHit {
            for window in [on, off] { window.window.setNeedsRedraw(); window.tick() }
        }
        on.resetFrameWork()
        for (model, window) in [(onModel, on), (offModel, off)] {
            model.params[5].radius = 6   // lands on the build session the moved miss's record kept armed
            window.window.setNeedsRedraw(); window.tick()
        }
        let work = try #require(on.frameWork.last)
        if !rsVerifying { #expect(work.retainedMisses == 1, "the written occurrence misses: \(work.retainedMisses)") }
        let difference = try RPSnapshot(on).differences(from: RPSnapshot(off))
        #expect(difference.isEmpty, "\(difference)")
    }

    /// 4 - the inheritance is geometry-only: a miss whose key differs in `ambient.environment` (a custom environment key written above the
    /// occurrences) does not inherit the build coverage, so the frame after still names `coverage.build` (an ambient difference may read a
    /// different observable). **Mutation:** inherit on every miss (`coverage.build` disappears from the settle frame's reasons).
    @Test(.enabled(if: !rsVerifying, "METALUI_VERIFY_RETAINED=1 paints a hit as a miss")) func anAmbientMissDoesNotInheritBuildCoverage() throws {
        let (window, _, box) = try ambientMissWindow()
        var settleReasons: [[String]] = []
        let lines = collectTrace {
            box.n = 1
            window.window.setNeedsRedraw(); window.tick()   // the change frame: every occurrence misses on key.ambient.environment
            window.window.setNeedsRedraw(); window.tick()   // the settle frame
        }
        settleReasons = lines.filter { $0.hasPrefix("retained paint miss") }.compactMap(traceReasons)
        let named = settleReasons.filter { $0.contains("coverage.build") }
        #expect(!named.isEmpty, "an ambient miss's record still lacks the build half: \(settleReasons)")
        #expect(settleReasons.contains { $0.contains { $0.hasPrefix("key.ambient") } }, "\(settleReasons)")
    }

    /// 5 - a steady hit frame opens no observation window: the predictor reads the geometry the prepaint already has and says "same".
    /// **Mutation:** the predictor always true (`prepaintWindowsOpened` is 8 a frame).
    @Test func aSteadyFrameOpensNoMoveWindow() throws {
        let (window, _) = try doubleMissWindow(.moved)
        RetainedTestingHooks.buildWindowsOpened = 0; RetainedTestingHooks.prepaintWindowsOpened = 0
        for _ in 0..<3 { window.window.setNeedsRedraw(); window.tick() }
        #expect(RetainedTestingHooks.buildWindowsOpened == 0, "build windows: \(RetainedTestingHooks.buildWindowsOpened)")
        #expect(RetainedTestingHooks.prepaintWindowsOpened == 0, "prepaint windows: \(RetainedTestingHooks.prepaintWindowsOpened)")
    }
}
