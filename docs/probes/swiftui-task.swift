// SwiftUI probe: `.task` and `.task(id:)` (portable-app branch, rulings PX-…
// in docs/superpowers/2026-10-07-portable-app-decisions.md; spec
// docs/superpowers/specs/2026-10-07-portable-app-design.md). Extends the
// lifecycle probe's K1/K2 (docs/probes/swiftui-lifecycle.swift, ruling LC-L)
// with the questions a build needs answered: start order against onAppear and
// the first draw, isolation, priority, cancellation order, id semantics,
// presence, nesting, and the window.
//
// HOW TO RUN (compiled form, SA-O):
//
//   xcrun swiftc docs/probes/swiftui-task.swift -o /tmp/task-probe
//   /tmp/task-probe
//
// Same harness as swiftui-lifecycle.swift: headless, short run-loop turns
// (`spin`), `--` marker lines between steps, a `DrawSpy` representable that
// logs `draw v=` from draw(_:).
//
// INSTRUMENTS. `log` is append-only and main-thread only: a task's line is
// logged from inside the task, so it lands where the task actually ran. Each
// task logs `main=` (Thread.isMainThread) on its first line. Cancellation is
// observed twice: `withTaskCancellationHandler`'s onCancel (synchronous with
// the `cancel()` call, hopped to main for the log; it records the order of
// the cancel call itself) and the sleep's thrown error after resumption.
//
// POSITIVE CONTROLS AND SEPARATING ARMS.
// - X0 (a hosted `.task` starts) against X0b (the same under `if false`:
//   nothing).
// - X5 (an id change restarts) against X6 (a write of the same id: nothing).
// - X8 (`.hidden()` content: the task starts) against X0b.
//
// RECORDED 2026-10-07 by the portable-app design session, macOS 27.0.1
// (26A434), Apple Swift 6.4 (swiftlang-6.4.0.33.1), screen LOCKED
// (CGSSessionScreenIsLocked = 1, displayAsleep main: 1). Compiled form, run
// three times: 213 lines each, byte-identical, exit 0, stderr empty.
// (Earlier drafts of X4/X5/X14 ran `longTask` nonisolated; its first line
// then logged off the main thread, after the cancel, and read as "the new
// task starts after the old is cancelled" — a broken instrument, fixed by
// making `longTask` @MainActor so its first line runs where the task starts.)
//
//   === X0 control: a hosted .task starts
//     -- host
//     -- ordered front
//     task start main=true
//     -- initial settled
//   === X0b separating: the same under `if false` never starts
//     -- host
//     -- ordered front
//     -- initial settled
//   === X1 order against onAppear and the first draw; the task writes v = 1 before its first await
//     -- host
//     make v=0
//     update v=0
//     -- ordered front
//     appear
//     task start v=0
//     task wrote v=1
//     update v=1
//     draw v=1
//     task after yield
//     -- initial settled
//   === X1b .task written INSIDE .onAppear (order flips?)
//     -- host
//     -- ordered front
//     task start
//     appear
//     -- initial settled
//   === X2 isolation: a task formed in a View body
//     -- host
//     -- ordered front
//     task main=true
//     task after yield main=true
//     task after sleep main=true
//     -- initial settled
//   === X3 priority: default, .low, .high, .background; id form default
//     -- host
//     -- ordered front
//     id-form default priority=high(25)
//     background priority=background(9)
//     high priority=high(25)
//     low priority=low(17)
//     default priority=high(25)
//     -- initial settled
//   === X4 removal: cancel order against onDisappear
//     -- host
//     -- ordered front
//     appear
//     task A start main=true
//     -- initial settled
//     -- flag = true
//     task A onCancel
//     disappear
//     task A resumed cancelled=true
//     -- settled after flag = true
//   === X5 id change: start of new, cancel of old, and whether old was cancelled when new started
//     -- host
//     -- ordered front
//     task k=0 start main=true
//     -- initial settled
//     -- k = 1
//     task k=0 onCancel
//     task k=1 start main=true
//     task k=0 resumed cancelled=true
//     -- settled after k = 1
//     -- k = 2
//     task k=1 onCancel
//     task k=2 start main=true
//     task k=1 resumed cancelled=true
//     -- settled after k = 2
//   === X6 separating: a write of the same id restarts nothing
//     -- host
//     -- ordered front
//     task start k=0
//     -- initial settled
//     -- k = 0
//     -- settled after k = 0
//   === X7 a finished task, then an id change: starts again; a body re-evaluation alone does not
//     -- host
//     -- ordered front
//     task start k=0
//     -- initial settled
//     -- v = 1 (body re-evaluated, id unchanged)
//     -- settled after v = 1 (body re-evaluated, id unchanged)
//     -- k = 1
//     task start k=1
//     -- settled after k = 1
//   === X8 presence: .hidden() and opacity(0) content start their tasks
//     -- host
//     -- ordered front
//     opacity-0 task start
//     hidden task start
//     -- initial settled
//   === X9 nesting and siblings: start order
//     -- host
//     -- ordered front
//     task child2
//     appear child2
//     task child1
//     appear child1
//     task parent
//     appear parent
//     -- initial settled
//   === X10 on a ForEach: once for the group or per child? count 0 -> 3 -> 0
//     -- host
//     -- ordered front
//     -- initial settled
//     -- count = 3
//     foreach task start
//     task fe start main=true
//     -- settled after count = 3
//     -- count = 0
//     task fe onCancel
//     task fe resumed cancelled=true
//     -- settled after count = 0
//   === X11 the window: close() with the host retained, then contentView = nil
//     -- host
//     -- ordered front
//     task W start main=true
//     -- initial settled
//     -- close()
//     -- settled after close()
//     -- contentView = nil
//     task W onCancel
//     disappear
//     task W resumed cancelled=true
//     -- settled after contentView = nil
//   === X12 an id change and an onChange of the same value in one update: order
//     -- host
//     -- ordered front
//     task start k=0
//     -- initial settled
//     -- k = 1
//     change 0->1
//     task start k=1
//     -- settled after k = 1
//   === X13 the task's name (macOS 26.4+ API) and Task.isCancelled at start
//     -- host
//     -- ordered front
//     name=View.task @ main/swiftui-task.swift:232
//     isCancelled at start=false
//     -- initial settled
//   === X14 a removal and re-insertion in one update (if/else of the same view type): new task, old cancelled
//     -- host
//     -- ordered front
//     task else start main=true
//     -- initial settled
//     -- flag = true
//     task then start main=true
//     task else onCancel
//     task else resumed cancelled=true
//     -- settled after flag = true
//   === X4b removal with the task OUTSIDE onDisappear: does the cancel still come first?
//     -- host
//     -- ordered front
//     task B start main=true
//     -- initial settled
//     -- flag = true
//     disappear
//     task B onCancel
//     task B resumed cancelled=true
//     -- settled after flag = true
//   === X12b the task(id:) INSIDE onChange: which runs first?
//     -- host
//     -- ordered front
//     task start k=0
//     -- initial settled
//     -- k = 1
//     task start k=1
//     change 0->1
//     -- settled after k = 1
//   === X14b if/else swap with onAppear/onDisappear and tasks on both branches: full order
//     -- host
//     -- ordered front
//     task else start main=true
//     -- initial settled
//     -- flag = true
//     appear then
//     task then start main=true
//     disappear else
//     task else onCancel
//     task else resumed cancelled=true
//     -- settled after flag = true
//   === X16 removal under a 0.6 s linear animation with .transition(.opacity): when is the task cancelled?
//     -- host
//     -- ordered front
//     task T start main=true
//     -- initial settled
//     -- withAnimation flag = true
//     -- settled after withAnimation flag = true
//     -- (no write) 0.05 s later
//     -- settled after (no write) 0.05 s later
//     -- (no write) after 1.0 s
//     task T onCancel
//     task T resumed cancelled=true
//     -- settled after (no write) after 1.0 s
//   === X17 re-inserted 0.15 s into its 0.6 s removal: cancelled? restarted?
//     -- host
//     -- ordered front
//     task R start main=true
//     -- initial settled
//     -- withAnimation flag = true
//     -- settled after withAnimation flag = true
//     -- withAnimation flag = false after 0.15 s
//     -- settled after withAnimation flag = false after 0.15 s
//     -- (no write) after 1.0 s
//     -- settled after (no write) after 1.0 s
//   === X15 hand-driven: synchronous start?
//     -- contentView = host
//     -- layoutSubtreeIfNeeded
//     appear
//     task body start
//     -- returned from layoutSubtreeIfNeeded
//     -- spun
//
// READING NOTES (what each ruling may rest on):
// - X0/X0b: a hosted `.task` starts; under `if false` it never does.
// - X1/X1b/X15: the task body starts SYNCHRONOUSLY, inside the update that
//   makes its view present (X15: inside layoutSubtreeIfNeeded, before it
//   returns), at its modifier's place in the onAppear order (X1: an inner
//   onAppear first; X1b: an inner task first), and its write before the first
//   `await` is in the FIRST draw (`draw v=1`). The rest runs after a
//   suspension (X1: `task after yield` after the draw).
// - X2: a closure formed in a View body runs on the main thread, before and
//   after each suspension. (A nonisolated async function it calls runs off
//   main — the broken-instrument note above.)
// - X3: default priority is .userInitiated (raw 25, printed `high(25)`: the
//   same raw value); `.low` 17, `.high` 25, `.background` 9; the id form's
//   default is the same.
// - X4/X4b/X11: removal CANCELS the task at its modifier's place in the
//   onDisappear order (X4, task inner: cancel then disappear; X4b, task outer:
//   disappear then cancel). `Task.isCancelled` is true when it resumes.
//   X11: `close()` with the host retained cancels nothing; the hosting view
//   leaving the window cancels.
// - X5/X12/X12b: an id change cancels the old task and then starts the new
//   one, synchronously, in one step at the modifier's place among onChange
//   actions (X12: an inner onChange first; X12b: an inner task first).
//   X6: a write of the same id restarts nothing; X7: a body re-evaluation
//   with the id unchanged restarts nothing, and an id change after the task
//   finished starts it again.
// - X8: `.hidden()` and opacity-0 content start their tasks (presence as for
//   onAppear, lifecycle probe E3/E4).
// - X9: siblings and parent/child start in reverse pre-order, interleaved
//   with onAppear by modifier order — the lifecycle probe's A1/A3 order.
// - X10: a `.task` on a ForEach starts once for the group, when it gets
//   content, and is cancelled when it has none (A6's rule).
// - X13: the default name is "View.task @ <fileID>:<line>" (macOS 26.4+);
//   `Task.isCancelled` is false at start.
// - X14/X14b: an if/else swap runs the new branch's onAppear and task start
//   BEFORE the old branch's onDisappear and cancel (A4's bucket order).
// - X16: under a removal transition the cancel waits until the transition
//   ends (not within 0.05 s; within the next 1.0 s) — T1's rule for
//   onDisappear. X17: content re-inserted mid-removal keeps its task: neither
//   cancelled nor restarted — T4's rule.

import AppKit
import SwiftUI

nonisolated(unsafe) var lines: [String] = []
func log(_ s: String) {
    if Thread.isMainThread { lines.append(s) } else { DispatchQueue.main.async { lines.append(s + " (logged via main)") } }
}
func onMain() -> Bool { pthread_main_np() != 0 }
func marker(_ s: String) { lines.append("-- \(s)") }

final class M: ObservableObject {
    @Published var flag = false
    @Published var k = 0
    @Published var count = 0
    @Published var v = 0
}

final class SpyView: NSView {
    var v = -1
    override func draw(_ dirtyRect: NSRect) { log("draw v=\(v)") }
}
struct DrawSpy: NSViewRepresentable {
    let v: Int
    func makeNSView(context: Context) -> SpyView { let s = SpyView(); s.v = v; log("make v=\(v)"); return s }
    func updateNSView(_ nsView: SpyView, context: Context) {
        log("update v=\(v)"); nsView.v = v; nsView.needsDisplay = true
    }
}

struct Root<C: View>: View {
    @ObservedObject var m: M
    let c: (M) -> C
    var body: some View {
        ZStack(alignment: .topLeading) { c(m) }.frame(width: 300, height: 200, alignment: .topLeading)
    }
}

@MainActor func spin(_ s: Double = 0.1) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

@MainActor @discardableResult
func arm<Content: View>(_ name: String, @ViewBuilder _ content: @escaping (M) -> Content,
                        steps: [(String, (M, NSWindow, NSHostingView<Root<Content>>) -> Void)] = [],
                        spinAfterStep: Double = 0.2) -> NSWindow {
    lines.removeAll()
    let m = M()
    let host = NSHostingView(rootView: Root(m: m, c: content))
    let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                       styleMask: [.titled, .closable], backing: .buffered, defer: false)
    win.isReleasedWhenClosed = false
    marker("host")
    win.contentView = host
    win.orderFrontRegardless()
    marker("ordered front")
    spin(0.3)
    marker("initial settled")
    for (label, step) in steps {
        marker(label)
        step(m, win, host)
        spin(spinAfterStep)
        marker("settled after \(label)")
    }
    print("=== \(name)")
    for l in lines { print("  \(l)") }
    win.orderOut(nil)
    win.contentView = nil
    spin(0.1)
    return win
}

func priorityName(_ p: TaskPriority) -> String {
    switch p {
    case .high: "high(\(p.rawValue))"
    case .userInitiated: "userInitiated(\(p.rawValue))"
    case .medium: "medium(\(p.rawValue))"
    case .low: "low(\(p.rawValue))"
    case .background: "background(\(p.rawValue))"
    default: "raw(\(p.rawValue))"
    }
}

/// A long task that logs its start, the cancel call (onCancel) and the thrown
/// cancellation.
@MainActor func longTask(_ label: String) async {
    log("task \(label) start main=\(onMain())")
    await withTaskCancellationHandler {
        do { try await Task.sleep(for: .seconds(5)); log("task \(label) finished") }
        catch { log("task \(label) resumed cancelled=\(Task.isCancelled)") }
    } onCancel: {
        log("task \(label) onCancel")
    }
}

MainActor.assumeIsolated {
NSApplication.shared.setActivationPolicy(.accessory)

// ------------------------------------------------------------ X: controls, order
arm("X0 control: a hosted .task starts", { _ in
    Text("x").task { log("task start main=\(onMain())") }
})
arm("X0b separating: the same under `if false` never starts", { _ in
    if false { Text("x").task { log("task start") } }
})

arm("X1 order against onAppear and the first draw; the task writes v = 1 before its first await", { m in
    DrawSpy(v: m.v)
        .onAppear { log("appear") }
        .task {
            log("task start v=\(m.v)")
            m.v = 1
            log("task wrote v=1")
            await Task.yield()
            log("task after yield")
        }
})

arm("X1b .task written INSIDE .onAppear (order flips?)", { _ in
    Text("x").task { log("task start") }.onAppear { log("appear") }
})

arm("X2 isolation: a task formed in a View body", { _ in
    Text("x").task {
        log("task main=\(onMain())")
        await Task.yield()
        log("task after yield main=\(onMain())")
        try? await Task.sleep(for: .milliseconds(20))
        log("task after sleep main=\(onMain())")
    }
})

arm("X3 priority: default, .low, .high, .background; id form default", { m in
    VStack {
        Text("a").task { log("default priority=\(priorityName(Task.currentPriority))") }
        Text("b").task(priority: .low) { log("low priority=\(priorityName(Task.currentPriority))") }
        Text("c").task(priority: .high) { log("high priority=\(priorityName(Task.currentPriority))") }
        Text("d").task(priority: .background) { log("background priority=\(priorityName(Task.currentPriority))") }
        Text("e").task(id: m.k) { log("id-form default priority=\(priorityName(Task.currentPriority))") }
    }
})

arm("X4 removal: cancel order against onDisappear", { m in
    if !m.flag {
        Text("x").onAppear { log("appear") }
            .task { await longTask("A") }
            .onDisappear { log("disappear") }
    }
}, steps: [("flag = true", { m, _, _ in m.flag = true })])

arm("X5 id change: start of new, cancel of old, and whether old was cancelled when new started", { m in
    Text("x").task(id: m.k) {
        let k = m.k
        await longTask("k=\(k)")
    }
}, steps: [("k = 1", { m, _, _ in m.k = 1 }),
           ("k = 2", { m, _, _ in m.k = 2 })])

arm("X6 separating: a write of the same id restarts nothing", { m in
    Text("x").task(id: m.k) { log("task start k=\(m.k)") }
}, steps: [("k = 0", { m, _, _ in m.k = 0 })])

arm("X7 a finished task, then an id change: starts again; a body re-evaluation alone does not", { m in
    Text("v=\(m.v)").task(id: m.k) { log("task start k=\(m.k)") }
}, steps: [("v = 1 (body re-evaluated, id unchanged)", { m, _, _ in m.v = 1 }),
           ("k = 1", { m, _, _ in m.k = 1 })])

arm("X8 presence: .hidden() and opacity(0) content start their tasks", { _ in
    VStack {
        Text("h").hidden().task { log("hidden task start") }
        Text("o").opacity(0).task { log("opacity-0 task start") }
    }
})

arm("X9 nesting and siblings: start order", { _ in
    VStack {
        Text("c1").task { log("task child1") }.onAppear { log("appear child1") }
        Text("c2").task { log("task child2") }.onAppear { log("appear child2") }
    }
    .task { log("task parent") }.onAppear { log("appear parent") }
})

arm("X10 on a ForEach: once for the group or per child? count 0 -> 3 -> 0", { m in
    VStack {
        ForEach(0..<m.count, id: \.self) { i in Text("r\(i)") }
            .task { log("foreach task start"); await longTask("fe") }
    }
}, steps: [("count = 3", { m, _, _ in m.count = 3 }),
           ("count = 0", { m, _, _ in m.count = 0 })])

arm("X11 the window: close() with the host retained, then contentView = nil", { _ in
    Text("x").task { await longTask("W") }.onDisappear { log("disappear") }
}, steps: [("close()", { _, win, _ in win.close() }),
           ("contentView = nil", { _, win, _ in win.contentView = nil })])

arm("X12 an id change and an onChange of the same value in one update: order", { m in
    Text("x")
        .onChange(of: m.k) { old, new in log("change \(old)->\(new)") }
        .task(id: m.k) { log("task start k=\(m.k)") }
}, steps: [("k = 1", { m, _, _ in m.k = 1 })])

arm("X13 the task's name (macOS 26.4+ API) and Task.isCancelled at start", { _ in
    Text("x").task {
        if #available(macOS 26.4, *) { log("name=\(Task.name ?? "nil")") } else { log("name: API unavailable") }
        log("isCancelled at start=\(Task.isCancelled)")
    }
})

arm("X14 a removal and re-insertion in one update (if/else of the same view type): new task, old cancelled", { m in
    if m.flag { Text("a").task { await longTask("then") } } else { Text("a").task { await longTask("else") } }
}, steps: [("flag = true", { m, _, _ in m.flag = true })])

// ------------------------------------------------------------ separating arms for the order
arm("X4b removal with the task OUTSIDE onDisappear: does the cancel still come first?", { m in
    if !m.flag {
        Text("x").onDisappear { log("disappear") }.task { await longTask("B") }
    }
}, steps: [("flag = true", { m, _, _ in m.flag = true })])

arm("X12b the task(id:) INSIDE onChange: which runs first?", { m in
    Text("x")
        .task(id: m.k) { log("task start k=\(m.k)") }
        .onChange(of: m.k) { old, new in log("change \(old)->\(new)") }
}, steps: [("k = 1", { m, _, _ in m.k = 1 })])

arm("X14b if/else swap with onAppear/onDisappear and tasks on both branches: full order", { m in
    if m.flag {
        Text("a").onAppear { log("appear then") }.task { await longTask("then") }
    } else {
        Text("a").onDisappear { log("disappear else") }.task { await longTask("else") }
    }
}, steps: [("flag = true", { m, _, _ in m.flag = true })])

// Transitions (lifecycle probe T1/T4's shape): is the cancel deferred to the
// end of a removal transition, and does a re-insertion mid-removal keep the
// task?
arm("X16 removal under a 0.6 s linear animation with .transition(.opacity): when is the task cancelled?", { m in
    if !m.flag {
        Text("x").transition(.opacity).task { await longTask("T") }
    }
}, steps: [("withAnimation flag = true", { m, _, _ in withAnimation(.linear(duration: 0.6)) { m.flag = true } }),
           ("(no write) 0.05 s later", { _, _, _ in }),
           ("(no write) after 1.0 s", { _, _, _ in spin(1.0) })], spinAfterStep: 0.05)

arm("X17 re-inserted 0.15 s into its 0.6 s removal: cancelled? restarted?", { m in
    if !m.flag {
        Text("x").transition(.opacity).task { await longTask("R") }
    }
}, steps: [("withAnimation flag = true", { m, _, _ in withAnimation(.linear(duration: 0.6)) { m.flag = true } }),
           ("withAnimation flag = false after 0.15 s", { m, _, _ in
               spin(0.1); withAnimation(.linear(duration: 0.6)) { m.flag = false } }),
           ("(no write) after 1.0 s", { _, _, _ in spin(1.0) })], spinAfterStep: 0.05)

// Hand-driven (lifecycle probe F2b's shape): does the task body start inside
// layoutSubtreeIfNeeded(), synchronously, or only on a later run-loop turn?
do {
    lines.removeAll()
    let m = M()
    let host = NSHostingView(rootView: Root(m: m, c: { _ in
        Text("x").onAppear { log("appear") }.task { log("task body start") }
    }))
    let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                       styleMask: [.titled], backing: .buffered, defer: false)
    win.isReleasedWhenClosed = false
    marker("contentView = host")
    win.contentView = host
    marker("layoutSubtreeIfNeeded")
    host.layoutSubtreeIfNeeded()
    marker("returned from layoutSubtreeIfNeeded")
    spin(0.2)
    marker("spun")
    print("=== X15 hand-driven: synchronous start?")
    for l in lines { print("  \(l)") }
    win.contentView = nil
    spin(0.1)
}

exit(0)
}
