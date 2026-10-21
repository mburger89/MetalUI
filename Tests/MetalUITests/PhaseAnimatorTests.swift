import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUI

// G1 lane 2: `phaseAnimator` and `PhaseAnimator` (rulings `GS-H`, `GS-I`, `GS-J`, `GS-K`, `GS-P`;
// spec `2026-10-21-gesture-state-design.md`). SwiftUI's answers are probe
// `docs/probes/swiftui-gesture-state.swift` arms `P1`–`P9` (recorded 2026-10-21; `P5` is
// "recorded, not re-taken" until an unlocked screen allows the re-run, `GS-O`), whose phases
// these fixtures copy: phases `[0, 1, 2]`, `animation` linear 0.4 s unless noted, `content`
// logging the phase it shows, `animation` logging the phase it is asked about.
//
// **No test sleeps** (CLAUDE.md "Animation"): each frame is a headless `Frame` built at an
// explicit timestamp over ONE shared `AnimationStore` — the window's own arrangement — so the
// clock is the argument, never a wall clock. Pins count steps and values; the one schedule pin
// (`GS-I`) reads explicit instants on that simulated clock.

@MainActor
private final class PhaseAnimLog {
    var phases: [Int] = []
    var asked: [Int] = []
    func shown(_ p: Int) -> Int { phases.append(p); return p }
    func ask(_ p: Int) { asked.append(p) }
    func reset() { phases = []; asked = [] }
}

private let linear04 = Animation.linear(duration: 0.4)

/// The probe's no-trigger host: a box that cycles `phases`, `animation` linear 0.4 s by default.
@MainActor
private func cycling(_ log: PhaseAnimLog, _ tx: TransactionLog? = nil, phases: [Int] = [0, 1, 2],
                     anim: @escaping (Int) -> Animation? = { _ in linear04 }) -> some Element {
    Column {
        Box().frame(width: Pixels(20), height: Pixels(20))
            .phaseAnimator(phases) { content, p in
                let _ = log.shown(p)
                content
                if let tx { TransactionRecorder(label: "p\(p)", log: tx) }
            } animation: { p in
                log.ask(p)
                return anim(p)
            }
    }
}

/// The probe's trigger host.
@MainActor
private func triggered(_ trigger: Int, _ log: PhaseAnimLog, _ tx: TransactionLog? = nil, phases: [Int] = [0, 1, 2],
                       anim: @escaping (Int) -> Animation? = { _ in linear04 }) -> some Element {
    Column {
        Box().frame(width: Pixels(20), height: Pixels(20))
            .phaseAnimator(phases, trigger: trigger) { content, p in
                let _ = log.shown(p)
                content
                if let tx { TransactionRecorder(label: "p\(p)", log: tx) }
            } animation: { p in
                log.ask(p)
                return anim(p)
            }
    }
}

/// Builds `root` into a frame at `time` over `store`.
@MainActor
@discardableResult
private func frame<E: Element>(_ root: E, at time: Double, _ store: AnimationStore) -> Frame {
    var root = root
    let frame = Frame(contentSize: Size(width: Pixels(200), height: Pixels(200)), scaleFactor: 1,
                      timestamp: time, animationStore: store)
    frame.render(&root)
    return frame
}

/// **P1** (`GS-I`). With no trigger the animator shows `phases[0]` at appear (no `animation` call),
/// steps to `phases[1]` at once, then to 2, 0, 1 … one step each 0.4 s. Mutation: a first step that
/// waits `animation(phases[0])`; a cycle that stops at the last phase.
@Test @MainActor func aPhaseAnimatorWithNoTriggerCyclesForeverP1() {
    let store = AnimationStore(), log = PhaseAnimLog()
    frame(cycling(log), at: 0, store)
    #expect(log.phases == [0] && log.asked.isEmpty, "appear: shows phases[0], no animation call: \(log.phases) \(log.asked)")
    frame(cycling(log), at: 0, store)
    frame(cycling(log), at: 0.2, store)
    frame(cycling(log), at: 0.4, store)
    frame(cycling(log), at: 0.8, store)
    frame(cycling(log), at: 1.2, store)
    #expect(log.phases == [0, 1, 1, 2, 0, 1], "phases \(log.phases)")
    #expect(log.asked == [1, 2, 0, 1], "animation asked once per step, for the phase entered: \(log.asked)")
}

/// **GS-I.** The cycle raises `noteActiveAnimation()` and never `requestAnotherFrame()`; one phase,
/// or a trigger at rest, raises neither. Mutation: `requestAnotherFrame()` in place of the note.
@Test @MainActor func theCycleNotesAnActiveAnimationAndNeverRequestsAnotherFrameGSI() {
    let store = AnimationStore(), log = PhaseAnimLog()
    for t in [0.0, 0.0, 0.2, 0.4] {
        let f = frame(cycling(log), at: t, store)
        #expect(f.hasActiveAnimations, "a cycling animator keeps the window drawing at \(t)")
        #expect(!f.wantsAnotherFrame, "and never requests another frame at \(t)")
    }
    let single = frame(cycling(PhaseAnimLog(), phases: [0]), at: 0, AnimationStore())
    #expect(!single.hasActiveAnimations && !single.wantsAnotherFrame, "one phase runs nothing (P7)")
    let rest = frame(triggered(0, PhaseAnimLog()), at: 0, AnimationStore())
    #expect(!rest.hasActiveAnimations && !rest.wantsAnotherFrame, "a trigger at rest runs nothing")
}

/// **P2, P3** (`GS-I`). A trigger change runs phases 1, 2 then 0, each held 0.4 s, and ends; a frame
/// with no change runs nothing and calls `animation` never. Mutation: the run stops at the last
/// phase (no return to 0); a run that continues past 0.
@Test @MainActor func aTriggerRunsEveryPhaseOnceAndReturnsToTheFirstP2P3() {
    let store = AnimationStore(), log = PhaseAnimLog()
    for t in [0.0, 0.5, 1.0] { frame(triggered(0, log), at: t, store) }
    #expect(log.phases == [0, 0, 0] && log.asked.isEmpty, "P3: no change, no run: \(log.phases) \(log.asked)")
    log.reset()
    var active: [Bool] = []
    for t in [1.0, 1.2, 1.4, 1.8, 2.2, 3.0] { active.append(frame(triggered(1, log), at: t, store).hasActiveAnimations) }
    #expect(log.phases == [1, 1, 2, 0, 0, 0], "P2: phases \(log.phases)")
    #expect(log.asked == [1, 2, 0], "P2: animation asked for 1, 2, 0 and then never: \(log.asked)")
    #expect(active == [true, true, true, false, false, false], "active while the run lasts: \(active)")
}

/// **P4** (`GS-I`). A trigger change mid-run restarts at once from `phases[1]`. Mutation: the change
/// is ignored until the run ends; the restart continues from the current phase.
@Test @MainActor func aTriggerChangeMidRunRestartsFromTheSecondPhaseP4() {
    let store = AnimationStore(), log = PhaseAnimLog()
    frame(triggered(0, log), at: 0, store)
    frame(triggered(1, log), at: 1.0, store)
    frame(triggered(1, log), at: 1.4, store)
    #expect(log.phases == [0, 1, 2])
    log.reset()
    frame(triggered(2, log), at: 1.5, store)
    #expect(log.phases == [1] && log.asked == [1], "restart at once from phases[1]: \(log.phases) \(log.asked)")
    frame(triggered(2, log), at: 1.9, store)
    frame(triggered(2, log), at: 2.3, store)
    #expect(log.phases == [1, 2, 0], "and runs to the end: \(log.phases)")
}

/// **P5** (`GS-I`, recorded and not re-taken, `GS-O`). A nil animation snaps its phase and the next
/// step follows at once: the phase is built under a nil animation, the following build steps.
/// Mutation: a nil animation waits `.default`'s duration.
@Test @MainActor func aNilAnimationSnapsAndTheNextStepFollowsAtOnceP5() {
    let store = AnimationStore(), log = PhaseAnimLog(), tx = TransactionLog()
    let anim: (Int) -> Animation? = { $0 == 1 ? nil : linear04 }
    frame(triggered(0, log, tx, anim: anim), at: 0, store)
    log.reset()
    frame(triggered(1, log, tx, anim: anim), at: 1, store)
    guard case .some(.none) = tx.layout["p1"] else {
        Issue.record("phase 1 is built under a nil animation: \(String(describing: tx.layout["p1"]))"); return
    }
    frame(triggered(1, log, tx, anim: anim), at: 1, store)
    #expect(log.phases == [1, 2], "the next build steps with no wait: \(log.phases)")
    frame(triggered(1, log, tx, anim: anim), at: 1.4, store)
    #expect(log.phases == [1, 2, 0], "and 2 holds its 0.4 s: \(log.phases)")
}

/// **P6, P9** (`GS-I`). A step lasts its animation's duration: a spring step its `duration:`, a
/// 1 s linear one 1 s. Mutation: every step takes a fixed 0.4 s.
@Test @MainActor func aStepLastsItsAnimationsDurationP6P9() {
    let spring = Animation.spring(duration: 0.3, bounce: 0)
    var store = AnimationStore(), log = PhaseAnimLog()
    frame(cycling(log, anim: { _ in spring }), at: 0, store)
    frame(cycling(log, anim: { _ in spring }), at: 0, store)
    for t in [0.29, 0.3, 0.59, 0.6] { frame(cycling(log, anim: { _ in spring }), at: t, store) }
    #expect(log.phases == [0, 1, 1, 2, 2, 0], "spring 0.3 s steps: \(log.phases)")
    store = AnimationStore(); log = PhaseAnimLog()
    let long = Animation.linear(duration: 1)
    frame(cycling(log, anim: { _ in long }), at: 0, store)
    frame(cycling(log, anim: { _ in long }), at: 0, store)
    for t in [0.9, 1.0, 1.9, 2.0] { frame(cycling(log, anim: { _ in long }), at: t, store) }
    #expect(log.phases == [0, 1, 1, 2, 2, 0], "linear 1 s steps: \(log.phases)")
}

/// **P7, P8** (`GS-I`). One phase runs nothing even on a trigger change; two equal phases step with
/// no wait. Mutation: equal neighbours wait their animation.
@Test @MainActor func onePhaseRunsNothingAndEqualNeighboursStepWithoutWaitP7P8() {
    var store = AnimationStore(), log = PhaseAnimLog()
    frame(triggered(0, log, phases: [0]), at: 0, store)
    frame(triggered(1, log, phases: [0]), at: 0.1, store)
    #expect(log.asked.isEmpty && log.phases == [0, 0], "P7: one phase: \(log.phases) \(log.asked)")
    store = AnimationStore(); log = PhaseAnimLog()
    frame(triggered(0, log, phases: [0, 0]), at: 0, store)
    log.reset()
    frame(triggered(1, log, phases: [0, 0]), at: 1, store)
    frame(triggered(1, log, phases: [0, 0]), at: 1, store)
    frame(triggered(1, log, phases: [0, 0]), at: 1, store)
    #expect(log.asked == [1, 0], "P8: both steps in one instant: \(log.asked)")
}

/// **GS-J, P-tx.** Each phase's content is built under a transaction whose animation is
/// `animation(phase)`: at layout and at paint, on the build that took the step. Mutation: the
/// content is built under the inherited transaction (`anim=false`); paint reads the live top.
@Test @MainActor func eachPhasesContentIsBuiltUnderItsAnimationGSJ() {
    let store = AnimationStore(), log = PhaseAnimLog(), tx = TransactionLog()
    let anim: (Int) -> Animation? = { $0 == 1 ? .linear(duration: 0.4) : .linear(duration: 0.7) }
    frame(triggered(0, log, tx, anim: anim), at: 0, store)
    guard case .some(.none) = tx.layout["p0"] else {
        Issue.record("appear: the inherited transaction (no animation): \(String(describing: tx.layout["p0"]))"); return
    }
    frame(triggered(1, log, tx, anim: anim), at: 1, store)
    #expect(tx.layout["p1"] == .some(.some(.linear(duration: 0.4))), "layout: \(String(describing: tx.layout["p1"]))")
    #expect(tx.paint["p1"] == .some(.some(.linear(duration: 0.4))), "paint: \(String(describing: tx.paint["p1"]))")
    frame(triggered(1, log, tx, anim: anim), at: 1.4, store)
    #expect(tx.layout["p2"] == .some(.some(.linear(duration: 0.7))), "layout p2: \(String(describing: tx.layout["p2"]))")
    // A build that took no step keeps the inherited transaction: a value mid-flight keeps its
    // own baseline's animation.
    tx.layout = [:]
    frame(triggered(1, log, tx, anim: anim), at: 1.5, store)
    guard case .some(.none) = tx.layout["p2"] else {
        Issue.record("a non-step build is under the inherited transaction: \(String(describing: tx.layout["p2"]))"); return
    }
}

/// **GS-I schedule.** A step's start is its scheduled time, so a late frame does not drift the
/// next step, and a stall of a whole step takes one step and restarts the schedule at `now`.
/// Mutation: `stepStart = now` every step (the 0.805 frame no longer steps); a stall that steps
/// once per missed interval.
@Test @MainActor func aLateFrameDoesNotDriftTheScheduleAndAStallTakesOneStepGSI() {
    let store = AnimationStore(), log = PhaseAnimLog()
    frame(cycling(log), at: 0, store)
    frame(cycling(log), at: 0, store)
    frame(cycling(log), at: 0.41, store)   // 1 -> 2, scheduled at 0.4
    #expect(log.phases == [0, 1, 2])
    frame(cycling(log), at: 0.805, store)  // 0.8 is the scheduled next; drift (0.81) would not step
    #expect(log.phases == [0, 1, 2, 0], "scheduled, not drifted: \(log.phases)")
    frame(cycling(log), at: 5.0, store)    // a stall: one step, no burst
    #expect(log.phases == [0, 1, 2, 0, 1], "one step after a stall: \(log.phases)")
    frame(cycling(log), at: 5.2, store)
    #expect(log.phases.count == 6 && log.phases.last == 1, "the next waits a full step from the stall: \(log.phases)")
    frame(cycling(log), at: 5.4, store)
    #expect(log.phases.last == 2, "and then steps: \(log.phases)")
}

/// **GS-H.** A record no build touches for a frame is dropped, so content that leaves and returns
/// starts at `phases[0]` (`LK-I` item 12's sweep).
/// Mutation: the sweep keeps the record.
@Test @MainActor func contentThatLeavesAndReturnsStartsAtTheFirstPhaseGSH() {
    let store = AnimationStore(), log = PhaseAnimLog()
    func host(_ shown: Bool) -> some Element {
        Column { if shown { Box().frame(width: Pixels(20), height: Pixels(20)).phaseAnimator([0, 1, 2], content: { c, p in let _ = log.shown(p); c }) } }
    }
    frame(host(true), at: 0, store)
    frame(host(true), at: 0, store)
    #expect(log.phases == [0, 1])
    frame(host(false), at: 0.1, store)
    frame(host(true), at: 0.2, store)
    #expect(log.phases == [0, 1, 0], "back at phases[0]: \(log.phases)")
}

/// **GS-H.** Two animators stacked at one position keep two records (the shared depth counter
/// names `$phase1`, `$phase2`) and a keyframe animator among them keeps its own. Mutation: the
/// record key ignores the depth.
@Test @MainActor func stackedAnimatorsKeepSeparateRecordsGSH() {
    let store = AnimationStore(), outer = PhaseAnimLog(), inner = PhaseAnimLog()
    func host() -> some Element {
        Column {
            Box().frame(width: Pixels(20), height: Pixels(20))
                .phaseAnimator([5, 6], content: { c, p in let _ = inner.shown(p); c }, animation: { _ in linear04 })
                .phaseAnimator([0, 1, 2], content: { c, p in let _ = outer.shown(p); c }, animation: { _ in linear04 })
        }
    }
    for t in [0.0, 0.0, 0.4, 0.8] { frame(host(), at: t, store) }
    #expect(outer.phases == [0, 1, 2, 0], "outer: \(outer.phases)")
    #expect(inner.phases == [5, 6, 5, 6], "inner cycles on its own record: \(inner.phases)")
}

/// **GS-H.** The typed entry is a line-for-line copy of the untyped one: the same schedule, the
/// same transaction, on proposal content in an `HStack`. Mutation: the typed entry drops the
/// transaction scope.
@Test @MainActor func phaseAnimatorKeepsProposalContentProposalGSH() {
    let store = AnimationStore(), log = PhaseAnimLog(), tx = TransactionLog()
    func host(_ trigger: Int) -> some Element {
        HStack {
            ProposalText("a")
                .phaseAnimator([0, 1, 2], trigger: trigger, content: { c, p in
                    let _ = log.shown(p)
                    c
                    TransactionRecorder(label: "p\(p)", log: tx)
                }, animation: { _ in linear04 })
        }
    }
    frame(host(0), at: 0, store)
    frame(host(1), at: 1, store)
    frame(host(1), at: 1.4, store)
    frame(host(1), at: 1.8, store)
    #expect(log.phases == [0, 1, 2, 0], "typed entry's schedule: \(log.phases)")
    #expect(tx.layout["p1"] == .some(.some(.linear(duration: 0.4))), "typed entry's transaction")
}

/// **GS-H.** `PhaseAnimator` the view, both initialisers, content receiving the phase only.
@Test @MainActor func thePhaseAnimatorViewBuildsBothFormsGSH() {
    let log = PhaseAnimLog()
    let store = AnimationStore()
    func host(_ trigger: Int) -> some Element {
        Column {
            PhaseAnimator([0, 1], trigger: trigger) { p in
                let _ = log.shown(p)
                Text("t\(p)")
            } animation: { _ in linear04 }
            PhaseAnimator([7, 8]) { p in Text("c\(p)") }
        }
    }
    frame(host(0), at: 0, store)
    frame(host(1), at: 1, store)
    frame(host(1), at: 1.4, store)
    #expect(log.phases == [0, 1, 0], "view with a trigger: \(log.phases)")
}
