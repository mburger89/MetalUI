import MetalUICore

// MARK: - `.task` and `.task(id:)` (rulings `PX-F`, `PX-G`)
//
// Probe `docs/probes/swiftui-task.swift`. One more `LifecycleWrite` case on the
// lifecycle machinery (`LC-B`…`LC-J`): the start is an appearance event, the
// cancel a disappearance event, an id restart a change event, each at the
// scope's place in its bucket; the running task lives in the store entry's
// box, carried across builds that keep the key (`PX-F` item 10).

/// The closure a `.task` stores — SwiftUI's type, boxed so a scope value can
/// hold it. `@unchecked Sendable`: the closure is `sending` into the
/// modifier, stored once, and only ever run by `TaskStart.start` on the main
/// actor (probe `swift-task-modifier-isolation.swift`).
struct TaskAction: @unchecked Sendable {
    let run: @isolated(any) () async -> Void
}

/// What one `.task` scope contributes (`PX-F`): the action, its priority and
/// name, and for the id form the id and its comparison.
struct TaskSpec {
    /// The `task(id:)` value, `nil` for the plain form.
    let id: Any?
    /// Whether a stored id equals this one; `nil` for the plain form.
    let isEqual: ((Any) -> Bool)?
    let priority: TaskPriority
    /// `name ?? "View.task @ <fileID>:<line>"` — SwiftUI's default (`X13`).
    let name: String
    let action: TaskAction
}

/// A scope's running task, carried from build to build while its key stays
/// (`PX-F` item 10) — and across a removal ghost the key returns from
/// (`X17`). A store box, never a `StateTable` entry.
@MainActor
final class RunningTask {
    var handle: Task<Void, Never>?
}

/// Starts a `.task`'s body (ruling `PX-G`).
@MainActor
enum TaskStart {
    /// The `@testable` seam (`PX-G` item 3): `true` selects the deferred
    /// start macOS 14–25 gets, so both branches are pinned on one machine.
    nonisolated(unsafe) static var forcesDeferredStart = false

    /// `Task.immediate` where the runtime has it — always off Apple — so the
    /// body runs synchronously, inside the lifecycle drain and under its
    /// `StateDispatch`, until its first suspension (`PX-F` item 3); otherwise
    /// an unnamed `Task`, whose body starts on a later main-queue turn
    /// (divergence 137).
    static func start(_ spec: TaskSpec) -> Task<Void, Never> {
        let action = spec.action
        if !forcesDeferredStart, #available(macOS 26.0, *) {
            return Task.immediate(name: spec.name, priority: spec.priority) { await action.run() }
        }
        return Task(priority: spec.priority) { await action.run() }
    }
}

extension ElementGroup {
    /// Starts `action` when this group appears and cancels it when the group
    /// disappears (SwiftUI's `task(name:priority:file:line:_:)`; rulings
    /// `PX-F`, `PX-G`).
    ///
    /// The start is an appearance: after the frame that first builds this
    /// group with content, at `onAppear(perform:)`'s place (children first;
    /// an inner `onAppear` first). The body runs synchronously until its
    /// first suspension, dispatched to this group, so a `@State` write there
    /// is presented in that same frame; everything after the first `await`
    /// runs as an ordinary main-actor job. On macOS 14–25 the body starts on
    /// the next main-queue turn instead (divergence 137). The closure inherits
    /// the caller's isolation — main-actor in an element.
    ///
    /// Cancellation is cooperative and is a disappearance: removal (after an
    /// animated removal's transition ends), or the window closing, calls
    /// `cancel()` and never waits. Hidden or transparent content is present
    /// and runs its task. `name` defaults to SwiftUI's
    /// `"View.task @ <file>:<line>"`; `priority` to `.userInitiated`.
    public func task(name: String? = nil, priority: TaskPriority = .userInitiated,
                     file: String = #fileID, line: Int = #line,
                     @_inheritActorContext _ action: sending @escaping @isolated(any) () async -> Void)
        -> LifecycleScope<Self> {
        LifecycleScope(content: self, write: .task(TaskSpec(
            id: nil, isEqual: nil, priority: priority,
            name: name ?? "View.task @ \(file):\(line)", action: TaskAction(run: action))))
    }

    /// Starts `action` when this group appears, cancels it when the group
    /// disappears, and — when `value` differs from the one this group was
    /// built with in the last frame — cancels the running task and starts a
    /// new one, in that order (SwiftUI's `task(id:name:priority:file:line:_:)`;
    /// rulings `PX-F`, `PX-G`).
    ///
    /// `value` is compared with `==` once per frame, like
    /// `onChange(of:initial:_:)`: the same value, or a rebuild for other
    /// state, restarts nothing, and the restart runs at this group's place
    /// among the frame's `onChange` actions. Otherwise as `task(name:priority:file:line:_:)`.
    public func task<T: Equatable>(id value: T, name: String? = nil,
                                   priority: TaskPriority = .userInitiated,
                                   file: String = #fileID, line: Int = #line,
                                   @_inheritActorContext _ action: sending @escaping @isolated(any) () async -> Void)
        -> LifecycleScope<Self> {
        LifecycleScope(content: self, write: .task(TaskSpec(
            id: value, isEqual: { ($0 as? T) == value }, priority: priority,
            name: name ?? "View.task @ \(file):\(line)", action: TaskAction(run: action))))
    }
}
