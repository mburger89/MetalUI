import Foundation
import MetalUI
import MetalUIScene
import MetalUITesting
import Testing

// C14-i lane 2 (`RZ-H`): the reasons table of the fillet drag. Counts only.

/// One drag's frames: the sum of every frame the drag drew, and the number of frames.
@MainActor func fdDrag(_ window: TestWindow, model: FDModel, steps: Int = 8) throws -> (FrameWork, Int) {
    window.resetFrameWork()
    let (from, to) = try filletDragPoints(window, value: model.value)
    window.drag(from: from, to: to, steps: steps)
    let frames = window.frameWork
    return (frames.dropFirst().reduce(frames[0], +), frames.count)
}

func fdTable(_ title: String, _ w: FrameWork, frames: Int) -> String {
    func per(_ n: Int) -> String { String(format: "%.1f", Double(n) / Double(max(frames, 1))) }
    var lines = ["--- \(title): \(frames) frames, per frame ---"]
    lines.append("requests \(per(w.elementRequests)) (+\(per(w.retainedSkippedRequests)) skipped) prepaints \(per(w.elementPrepaints)) (+\(per(w.retainedSkippedPrepaints))) paints \(per(w.elementPaints)) (+\(per(w.retainedSkippedPaints)))")
    lines.append("contentEval \(per(w.contentEvaluations)) skips \(per(w.contentSkips)) refusals \(per(w.contentRefusals))")
    lines.append("hits \(per(w.retainedHits)) misses \(per(w.retainedMisses)) ineligible \(per(w.retainedIneligible)) prepaintHits \(per(w.retainedPrepaintHits)) prepaintIneligible \(per(w.retainedPrepaintIneligible))")
    lines.append("grafts \(per(w.retainedGrafts)) graftIneligible \(per(w.retainedGraftIneligible)) redos \(per(w.retainedRedos)) backoff \(per(w.retainedBackoffFrames)) translated \(per(w.retainedTranslated))")
    lines.append("ineligible reasons \(w.retainedIneligibleReasons.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" })")
    lines.append("translation refused \(w.retainedTranslationRefusedReasons.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" })")
    return lines.joined(separator: "\n")
}

/// F1 - the fillet drag's reasons table (`RZ-H`, `RZ-S`). Printed per arm (`METALUI_TRACE_RETAINED=1` adds the miss lines), and
/// pinned on the by-design floor: where the changing value reaches one panel (an input, an observed read, a slider in or beside
/// it, a slider in every panel over per-panel objects) the retained drag evaluates that panel's getter once a frame and nothing
/// else, no refusal and no redo, the other five replay and graft, and the frame costs under a quarter of the unretained one's
/// requests. Where the panels share one observable array property (`sliderEverywhere`) a write to one value is an observed change
/// of every panel that read the array in its slider's binding, so all six miss: **by design** (`.equatable()` observation is
/// per property), and pinned as such (`RZ-S`). Counts only.
/// Mutations (record 133 lane 2): a panel's `==` ignoring its value (the value is stale: the scene differs, caught by
/// `theFilletDragFrameEqualsAnUnretainedOne`), `retainedHits` over a record kept across an observed change (the array arm's
/// misses vanish, so its pin reddens).
@Test(.enabled(if: !rsVerifying, "METALUI_VERIFY_RETAINED=1 builds a replayed frame twice: the counts this test pins are not its to read"),
      arguments: FDArm.allCases) @MainActor
func theFilletDragReasonsAreProfiled(arm: FDArm) throws {
    let (window, model) = try filletDragWindow(arm)
    let before = model.value
    let (work, frames) = try fdDrag(window, model: model)
    print(fdTable("\(arm) retained", work, frames: frames))
    #expect(model.value != before, "the drag moved the slider: \(before) -> \(model.value)")
    let (off, offModel) = try filletDragWindow(arm, graft: false, retain: false)
    let (offWork, offFrames) = try fdDrag(off, model: offModel)
    print(fdTable("\(arm) retention off", offWork, frames: offFrames))
    #expect(frames == offFrames)
    #expect(work.retainedRedos == 0 && work.retainedBackoffFrames == 0, "no redo: \(work.retainedRedos)")
    #expect(work.contentRefusals == 0 && work.retainedIneligibleReasons.isEmpty && work.retainedTranslationRefusedReasons.isEmpty,
            "no refusal: \(work.retainedIneligibleReasons) \(work.retainedTranslationRefusedReasons)")
    if arm == .sliderEverywhere {
        #expect(work.retainedMisses >= 4 * frames, "every panel misses on the shared array: \(work.retainedMisses) over \(frames)")
        #expect(work.elementRequests * 10 >= offWork.elementRequests * 8, "almost nothing is saved: \(work.elementRequests) of \(offWork.elementRequests)")
        #expect(work.contentEvaluations <= frames, "the getters are skipped, the records are not: \(work.contentEvaluations)")
    } else {
        #expect(work.contentEvaluations == frames - 1, "one getter a drag step, panel 2's: \(work.contentEvaluations) of \(frames) frames")
        #expect(work.retainedMisses <= frames, "at most one miss a frame, the dragged panel's: \(work.retainedMisses)")
        #expect(work.retainedGrafts >= 4 * frames, "the other five graft: \(work.retainedGrafts) over \(frames)")
        #expect(work.elementRequests * 4 <= offWork.elementRequests, "a quarter of the unretained requests at most: \(work.elementRequests) of \(offWork.elementRequests)")
    }
}

/// The retained drag's last frame equals the unretained one's: scene, accessibility tree, hitboxes, in every arm.
@Test(arguments: FDArm.allCases) @MainActor
func theFilletDragFrameEqualsAnUnretainedOne(arm: FDArm) throws {
    let (on, onModel) = try filletDragWindow(arm)
    let (off, offModel) = try filletDragWindow(arm, graft: false, retain: false)
    _ = try fdDrag(on, model: onModel); _ = try fdDrag(off, model: offModel)
    for w in [on, off] { w.window.setNeedsRedraw(); w.tick() }
    let differences = try RPSnapshot(on).differences(from: RPSnapshot(off))
    #expect(differences.isEmpty, "\(arm): \(differences)")
}
