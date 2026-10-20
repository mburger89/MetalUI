import Foundation
import MetalUI
import MetalUIScene
import MetalUITesting
import Observation
import Testing

// F3 (`MO-A`…`MO-G`, record 123): an observed write made on the main actor, whatever thread runs it, is seen by
// the next frame's skip, replay and graft decisions. Off Darwin Swift Testing runs main-actor code on a pool
// thread, so `Thread.isMainThread` is false there and the old `onChange` queued its flag behind a `Task`. No test
// here calls `settle()`: the write must be visible with nothing yielded. Counts, never time.

@Observable @MainActor final class MOStore {
    var value = 0
}

/// A store a `Thread` may write (`MO-G`): not main-actor, read by a component on the main actor.
@Observable final class MOSharedStore: @unchecked Sendable {
    var value = 0
}

@MainActor final class MOBudget { var writes = 0 }

@MainActor @ElementBuilder
private func moCard(_ label: String, value: Int) -> some ElementGroup {
    VStack(spacing: 2) {
        Text(label).frame(width: Pixels(70), height: Pixels(14))
        Box().frame(width: Pixels(30), height: Pixels(8)).background(value % 2 == 0 ? Color.red : Color.accent)
    }
}

private struct MOEnvBox: Component, @MainActor Equatable {
    let rect: Int
    @Environment(MOStore.self) var store
    var content: some ElementGroup { moCard("v\(store.value)", value: store.value) }
    static func == (l: MOEnvBox, r: MOEnvBox) -> Bool { l.rect == r.rect }
}

private struct MOPlainBox: Component, @MainActor Equatable {
    let rect: Int
    let model: MOStore
    var content: some ElementGroup { moCard("v\(model.value)", value: model.value) }
    static func == (l: MOPlainBox, r: MOPlainBox) -> Bool { l.rect == r.rect }
}

private struct MOSharedBox: Component, @MainActor Equatable {
    let rect: Int
    let model: MOSharedStore
    var content: some ElementGroup { moCard("v\(model.value)", value: model.value) }
    static func == (l: MOSharedBox, r: MOSharedBox) -> Bool { l.rect == r.rect }
}

/// Reads the model in its own (non-memoized) getter, so only a retained session of an enclosing
/// `.equatable()` occurrence observes the read; optionally writes it once after reading (`MO-D`, `MO-F`).
private struct MOReader: Component {
    let model: MOStore
    let budget: MOBudget
    var content: some ElementGroup {
        let v = model.value
        let _ = {
            if budget.writes > 0 { budget.writes -= 1; model.value += 1 }
        }()
        moCard("v\(v)", value: v)
    }
}

private struct MOOuter: Component, @MainActor Equatable {
    let rect: Int
    let model: MOStore
    let budget: MOBudget
    var content: some ElementGroup { MOReader(model: model, budget: budget) }
    static func == (l: MOOuter, r: MOOuter) -> Bool { l.rect == r.rect }
}

@MainActor private func frame(_ window: TestWindow) -> FrameWork {
    window.window.setNeedsRedraw()
    window.tick()
    return window.lastFrameWork
}

@MainActor private func rectBytes(_ window: TestWindow) -> Data {
    window.scene.rects.withUnsafeBytes { Data($0) }
}

@MainActor @Suite(.serialized) struct MemoObservationThreadTests {
    /// Test 1. The MetalCreator report's shape: an `.equatable()` component reading an `@Observable` through
    /// `@Environment(Store.self)`, a write on the same instance, the very next frame. Mutation: `ContentMemoHandle.fire`
    /// sets nothing before its `Thread.isMainThread` branch.
    @Test func anObservedWriteOnTheMainActorIsSeenByTheNextFrameThroughAnEnvironmentStore() throws {
        let store = MOStore()
        let window = try harnessWindow {
            VStack(spacing: 0) { MOEnvBox(rect: 1).equatable().environment(store) }
        }
        _ = try window.element(label: "v0")
        for _ in 0..<3 { _ = frame(window) }
        var f = frame(window)
        #expect(f.contentEvaluations == 0 && f.contentSkips == 1, "a steady frame skips")
        let before = rectBytes(window)
        store.value = 1
        f = frame(window)
        #expect(f.contentEvaluations == 1, "the write is seen by the next frame")
        _ = try window.element(label: "v1")
        #expect(rectBytes(window) != before, "and painted")
    }

    /// Test 2. The same with a plain observed model captured by the component.
    @Test func anObservedWriteOnTheMainActorIsSeenByTheNextFrameThroughAPlainObservedModel() throws {
        let model = MOStore()
        let window = try harnessWindow {
            VStack(spacing: 0) { MOPlainBox(rect: 1, model: model).equatable() }
        }
        _ = try window.element(label: "v0")
        for _ in 0..<3 { _ = frame(window) }
        var f = frame(window)
        #expect(f.contentEvaluations == 0 && f.contentSkips == 1)
        model.value = 1
        f = frame(window)
        #expect(f.contentEvaluations == 1)
        _ = try window.element(label: "v1")
    }

    /// Test 3. The retained replay and the graft: the occurrence's getter reads nothing, a descendant's does, so
    /// only the retained sessions observe the write. Mutation: `RetainedHandle.fire` sets nothing before its branch.
    @Test func anObservedWriteOnTheMainActorIsSeenByTheRetainedReplayAndTheGraft() throws {
        let model = MOStore()
        let budget = MOBudget()
        let window = try harnessWindow {
            VStack(spacing: 0) { MOOuter(rect: 1, model: model, budget: budget).equatable() }
        }
        _ = try window.element(label: "v0")
        for _ in 0..<4 { _ = frame(window) }
        var f = frame(window)
        try #require(f.retainedHits + f.retainedGrafts > 0, "a steady frame replays or grafts")
        let before = rectBytes(window)
        model.value = 1
        f = frame(window)
        #expect(f.retainedHits == 0 && f.retainedGrafts == 0, "the changed subtree is neither replayed nor grafted")
        #expect(f.elementPaints > 0)
        _ = try window.element(label: "v1")
        #expect(rectBytes(window) != before)
    }

    /// Test 4. A write from a real second thread, joined without yielding the main actor: the flag is set before the
    /// writer returns. Red on macOS too (the hop has not run). Mutation: as test 1.
    @Test func aWriteFromAnotherThreadIsSeenBeforeTheWriterReturns() throws {
        let model = MOSharedStore()
        let window = try harnessWindow {
            VStack(spacing: 0) { MOSharedBox(rect: 1, model: model).equatable() }
        }
        _ = try window.element(label: "v0")
        for _ in 0..<3 { _ = frame(window) }
        var f = frame(window)
        #expect(f.contentEvaluations == 0 && f.contentSkips == 1)
        let done = DispatchSemaphore(value: 0)
        let writer = Thread { model.value = 1; done.signal() }
        writer.start()
        done.wait()
        f = frame(window)
        #expect(f.contentEvaluations == 1)
        _ = try window.element(label: "v1")
    }

    /// Test 6. A retired session never marks the entry: after several evaluations a steady frame skips. (The
    /// `armed` counter is bookkeeping that lags behind a hop off Darwin, `MO-C`, so it is not asserted here.) Dropping the serial compare in
    /// `MemoFlags.fireMemo` does NOT redden this test (checker, record 123 §10); `isMainThread`-only flag setting does, in the Linux image.
    @Test func aRetiredSessionsFireChangesNothing() throws {
        let model = MOStore()
        let window = try harnessWindow {
            VStack(spacing: 0) { MOPlainBox(rect: 1, model: model).equatable() }
        }
        for step in 1...3 {
            model.value = step
            let f = frame(window)
            #expect(f.contentEvaluations == 1)
        }
        for _ in 0..<2 {
            let f = frame(window)
            #expect(f.contentEvaluations == 0 && f.contentSkips == 1, "a retired session left the entry stale")
        }
    }

    /// Test 8 (`MO-F`). A change that lands between a record's sessions arming and the record's own clear is not
    /// erased by it: the next frame does not replay. Mutation: the plain `observedChange = false` at the clear.
    @Test func aChangeDuringARecordsFrameIsNotErasedByItsClear() throws {
        let model = MOStore()
        let budget = MOBudget()
        budget.writes = 1
        let window = try harnessWindow {
            VStack(spacing: 0) { MOOuter(rect: 1, model: model, budget: budget).equatable() }
        }
        let f = frame(window)
        #expect(f.retainedHits == 0 && f.retainedGrafts == 0, "the frame after a mid-build write replays nothing")
        _ = try window.element(label: "v1")
    }
}
