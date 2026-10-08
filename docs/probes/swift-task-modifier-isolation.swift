// Swift probe: can a MetalUI `.task` take SwiftUI's closure type —
// `@_inheritActorContext sending @escaping @isolated(any) () async -> Void` —
// store it in a scope value, and start it later with `Task.immediate` so its
// prefix runs synchronously on the main actor? (ruling PX-F item 1, PX-G;
// docs/superpowers/2026-10-07-portable-app-decisions.md)
//
// HOW TO RUN:
//   xcrun swiftc -swift-version 6 docs/probes/swift-task-modifier-isolation.swift -o /tmp/task-iso
//   /tmp/task-iso
//
// A stand-in `@MainActor protocol EG` plays `ElementGroup`; `Scope` plays
// `LifecycleScope`; `TaskAction` is the `@unchecked Sendable` box the store
// would hold. `V.body` forms a closure in a main-actor context that captures
// a non-Sendable struct and calls a `@MainActor` method synchronously — what
// an app writes in an element.
//
// RECORDED 2026-10-07 by the portable-app design session, macOS 27.0.1,
// Apple Swift 6.4 (swiftlang-6.4.0.33.1), Swift 6 language mode: compiles
// with NO diagnostic; prints
//   ["after start n=1", "done n=1", "prio=17 name=named"]
// READING: the closure inherited main-actor isolation (the synchronous
// `m.go()` call compiled); `Task.immediate` ran its prefix before `start`
// returned (`n=1` already); priority and name pass through. Removing
// `@_inheritActorContext` is the mutation the external-module guard (spec
// guard 3.G1) must catch.

@MainActor protocol EG {}
struct Leaf: EG {}
struct Scope<C: EG>: EG { var c: C; let action: TaskAction }
struct TaskAction: @unchecked Sendable { let run: @isolated(any) () async -> Void }
extension EG {
    func task(name: String? = nil, priority: TaskPriority = .userInitiated,
              @_inheritActorContext _ action: sending @escaping @isolated(any) () async -> Void) -> Scope<Self> {
        Scope(c: self, action: TaskAction(run: action))
    }
}
@MainActor final class Model { var n = 0; func go() { n += 1 } }
struct NotSendable { var x = 0 }
struct V: EG {
    var m: Model
    var ns = NotSendable()
    var body: Scope<Leaf> {
        Leaf().task {
            m.go()                      // synchronous main-actor call: needs main isolation
            let y = ns.x
            await Task.yield()
            m.n += y
        }
    }
}
nonisolated(unsafe) var log: [String] = []
@MainActor func start(_ a: TaskAction, priority: TaskPriority, name: String?) -> Task<Void, Never> {
    if #available(macOS 26, *) {
        return Task.immediate(name: name, priority: priority) { await a.run() }
    }
    return Task(priority: priority) { await a.run() }
}
@MainActor func run() async {
    let m = Model()
    let s = V(m: m).body
    let t = start(s.action, priority: .low, name: "n")
    log.append("after start n=\(m.n)")   // immediate: 1 here
    await t.value
    log.append("done n=\(m.n)")
    let probe = Leaf().task { log.append("prio=\(Task.currentPriority.rawValue) name=\(Task.name ?? "nil")") }
    let t2 = start(probe.action, priority: .low, name: "named")
    await t2.value
    print(log)
}
await run()
