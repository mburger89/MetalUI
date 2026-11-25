import Testing
import Metal
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// Plan task 10, part 2, lane 3: `ForEach(_: Binding<C>)` (ruling `DD-AA`; spec
// tests 3.17, 3.18). Each element's content receives a `Binding<C.Element>`
// that reads and writes `items[index]`, identified by the element's id — and a
// binding kept past a change of the collection checks that the element at its
// index still has its id: if not, a write is dropped and a read returns the
// last value it read. That stale rule is **MetalUI's own** (SwiftUI's answer is
// unprobed; `DD-AA`). Helpers are `ButtonTests.swift`'s `control…`.

private struct Task: Identifiable, Equatable {
    let id: String
    var done: Bool
}

@MainActor
private final class Tasks {
    var items: [Task] = [Task(id: "a", done: false), Task(id: "b", done: false), Task(id: "c", done: false)]
    var writes = 0
    var binding: Binding<[Task]> {
        Binding(get: { self.items }, set: { self.items = $0; self.writes += 1 })
    }
}

/// Where the content closure hands out each element's binding, by id.
@MainActor
private final class Captured {
    var bindings: [String: Binding<Task>] = [:]
}

/// A column of one click target per task: a click toggles its `done`.
@MainActor
private func taskColumn(_ tasks: Tasks, _ captured: Captured) -> some Element {
    Column {
        ForEach(tasks.binding) { $task in
            let _ = captured.bindings[task.id] = $task
            Box().cssWidth(controlPx(40)).cssHeight(controlPx(20))
                .onClick { $task.wrappedValue.done.toggle() }
        }
    }
    .cssWidth(controlPx(400)).cssHeight(controlPx(200))
}

/// **3.17.** Toggling element 1 writes `items[1].done` only: one write, the
/// other two untouched, and the element's own binding reads the new value.
/// M3o (every slot bound to index 0) must redden it.
@Test @MainActor func aForEachOverABindingHandsEachElementItsOwnBinding() throws {
    let tasks = Tasks()
    let captured = Captured()
    let (window, platform) = try controlWindow { taskColumn(tasks, captured) }
    let targets = window.lastHitboxes.filter { $0.handlers.onClick != nil }
        .sorted { $0.bounds.origin.y.value < $1.bounds.origin.y.value }
    try #require(targets.count == 3, "three click targets, read \(targets.count)")
    controlClick(platform, at: controlCentre(targets[1].bounds))
    #expect(tasks.items.map(\.done) == [false, true, false], "only b toggled: \(tasks.items)")
    #expect(tasks.writes == 1, "one write: \(tasks.writes)")
    let b = try #require(captured.bindings["b"])
    #expect(b.wrappedValue.done, "b's binding reads the write")
    #expect(!(try #require(captured.bindings["a"])).wrappedValue.done, "a's binding reads a")
}

/// **3.18.** A handler captured before its element was removed: its write is
/// dropped (no trap, the element now at its index untouched) and its read
/// returns the last value it read. M3p (the id check removed — the write lands
/// on the element now at that index) must redden it.
@Test @MainActor func aStaleElementBindingDropsItsWriteAndKeepsItsLastRead() throws {
    let tasks = Tasks()
    let captured = Captured()
    let (window, _) = try controlWindow { taskColumn(tasks, captured) }
    let stale = try #require(captured.bindings["b"], "b's binding was handed out")
    try #require(stale.wrappedValue == Task(id: "b", done: false), "control: it reads b")
    // b is removed; c now sits at b's index.
    tasks.items.remove(at: 1)
    controlRedraw(window)
    tasks.writes = 0
    stale.wrappedValue = Task(id: "b", done: true)
    #expect(tasks.writes == 0, "the stale write is dropped: \(tasks.writes)")
    #expect(tasks.items == [Task(id: "a", done: false), Task(id: "c", done: false)],
            "c, now at b's index, is untouched: \(tasks.items)")
    #expect(stale.wrappedValue == Task(id: "b", done: false), "the stale read is b's last value")
    // Control: a live binding still writes.
    let live = try #require(captured.bindings["c"])
    live.wrappedValue.done = true
    #expect(tasks.items[1].done && tasks.writes == 1, "control: c's binding writes c")
}
