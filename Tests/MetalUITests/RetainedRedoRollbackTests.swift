import Foundation
import Testing
import MetalUICore
import MetalUILayout
import MetalUIScene
@testable import MetalUI

// C14b-2 lane 1 (`RK-U`, `RK-M`): what a redo puts back, store by store. The window-level differentials
// (`RetainedPrepaintTests`) run a lifecycle appear, a focus request, a transition, a timeline and an implicit animation
// across a redo; these pin each store's rollback directly, each with a control that shows the twin build **would** have
// read the leftover, so the rollback is what separates them. Counts and values, never time.

private func id(_ index: Int, _ name: String? = nil) -> GlobalElementID {
    GlobalElementID.child(of: nil, at: index, name: name.map { ElementID($0) })
}

/// A scope noted twice reads as two keys (the second an appearance): the rollback is what keeps it one. Mutation:
/// `LifecycleStore.rollbackBuild` made a no-op reads 2 events.
@MainActor @Test func theLifecycleRollbackKeepsATwinBuildToOneAppearance() {
    func appearances(rollingBack: Bool) -> Int {
        let store = LifecycleStore()
        var ran = 0
        let write = LifecycleWrite.appear { ran += 1 }
        let scope = id(0, "$lifecycle0")
        func build() { store.note(write, scope: scope, owner: id(0), order: store.reserveOrder()) }
        build()
        if rollingBack { store.rollbackBuild() }
        build()
        store.endFrame(liveGhosts: [], departed: nil)
        return store.takeEvents().count
    }
    #expect(appearances(rollingBack: false) == 2, "the control: a twin build with no rollback doubles the key")
    #expect(appearances(rollingBack: true) == 1)
}

/// A timeline counted twice reads a new cursor whose first appearance is now: an `.animation(minimumInterval:)` timeline steps
/// from its first appearance, so the twin's date is the clock, not the step. Mutation: `TimelineStore.rollbackBuild` made a
/// no-op reads 2.9.
@MainActor @Test func theTimelineRollbackKeepsATwinBuildOnTheSameCursor() {
    let schedule: AnimationTimelineSchedule = .animation(minimumInterval: 1)
    func date(rollingBack: Bool) -> Double {
        let store = TimelineStore(), table = StateTable()
        store.clockOffset = 0   // a date's reference seconds are the timestamp (`KF-K` item 4)
        let owner = id(0)
        _ = store.context(owner: owner, schedule: schedule, timestamp: 0.5, stateTable: table)
        store.endFrame()
        _ = store.context(owner: owner, schedule: schedule, timestamp: 2.9, stateTable: table)   // the build to abandon
        if rollingBack { store.rollbackBuild() }
        return store.context(owner: owner, schedule: schedule, timestamp: 2.9, stateTable: table).context.date
            .timeIntervalSinceReferenceDate
    }
    #expect(date(rollingBack: true) == 2.5, "the date steps from the first appearance: \(date(rollingBack: true))")
    #expect(date(rollingBack: false) == 2.9, "the control: a twin build counts a new position that appears now")
}

/// A claimed group is claimed again by the twin build only after the rollback. Mutation: `TransitionStore.rollbackBuild`
/// made a no-op reads `false` for the second claim.
@MainActor @Test func theTransitionRollbackLetsATwinBuildClaimTheGroupAgain() {
    let store = TransitionStore()
    let saved = store.checkpoint()
    let slot = id(0)
    let key = TransitionStore.key(under: slot, at: 0)
    func claim() -> Bool {
        store.noteOptional(slot, produced: true, animation: .linear(duration: 1))
        return store.claim(key: key, under: slot, at: 0, transition: .opacity, reduceMotion: false)
    }
    #expect(claim())
    #expect(!claim(), "the control: the twin build's claim answers false while the first build's record stands")
    store.rollbackBuild(saved)
    #expect(claim())
}

/// A surface's occurrence is counted from zero again. Mutation: `SurfaceRegistry.rollbackBuild` made a no-op reads 1.
@MainActor @Test func theSurfaceRollbackCountsATwinBuildFromZero() {
    let registry = SurfaceRegistry()
    let element = id(0)
    #expect(registry.occurrence(for: element) == 0)
    #expect(registry.occurrence(for: element) == 1, "the control: counted twice")
    registry.rollbackBuild()
    #expect(registry.occurrence(for: element) == 0)
}

/// An animation entry the abandoned build stored is put back. Mutation: `entries = saved.entries` removed reads 2.
@MainActor @Test func theAnimationStoreRollbackRestoresTheEntriesAndForgetsWhatWasTouched() {
    let store = AnimationStore()
    let key = id(0, "$anim")
    store.set(1, at: key)
    store.endFrame()
    let saved = store.checkpoint()
    store.set(2, at: key)
    store.rollbackBuild(saved)
    #expect(store.value(at: key, as: Int.self) == 1)
}

/// A frame abandoned for a redo took the window's `scrollTo` requests; the redo needs them again, once. Mutation:
/// `ScrollRequestQueue.restore` made a no-op reads an empty queue.
@MainActor @Test func theScrollQueueGivesBackWhatAnAbandonedFrameTook() {
    let queue = ScrollRequestQueue()
    queue.enqueue(ScrollRequest(scope: id(0), key: AnyHashable("row"), anchor: nil))
    let snapshot = queue.pending
    #expect(queue.take().count == 1)
    #expect(queue.pending.isEmpty)
    queue.restore(snapshot)
    #expect(queue.pending.count == 1)
    #expect(queue.take().count == 1, "and the redo takes them once")
}
