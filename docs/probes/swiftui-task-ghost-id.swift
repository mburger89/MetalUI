// SwiftUI probe: a `.task(id:)` (and an `.onChange(of:)`) whose content is
// re-inserted from a removal transition with a CHANGED id (task-followups
// branch, ruling TF-A in docs/superpowers/2026-10-08-task-followups-decisions.md;
// spec docs/superpowers/specs/2026-10-08-task-followups-design.md). Extends
// swiftui-task.swift's X17 (re-inserted mid-removal with the same id: kept,
// neither cancelled nor restarted), which PX-V item 1 left unprobed for a
// changed id.
//
// HOW TO RUN (compiled form, SA-O):
//
//   xcrun swiftc docs/probes/swiftui-task-ghost-id.swift -o /tmp/task-ghost-id
//   /tmp/task-ghost-id
//
// Harness: swiftui-task.swift's (headless NSHostingView in an ordered-front
// window, short run-loop turns, `--` marker lines between steps; a task logs
// its start, its onCancel — synchronous with the cancel() call — and its
// thrown cancellation). Every arm's content is
//
//   if !m.flag { Text("x").transition(.opacity)
//                    .task(id: m.k) { longTask("k=<k>") }
//                    .onChange(of: m.k) { change <old>-><new> } }
//
// under a 0.6 s linear removal, re-inserted 0.15 s in.
//
// POSITIVE CONTROLS AND SEPARATING ARMS.
// - Y0 (control, X17's shape with an id): re-inserted with k unchanged —
//   nothing runs (no cancel, no restart, no change).
// - Y3 (control): k = 1 with no removal — the instrument sees an id change
//   (cancel k=0, start k=1, change 0->1), X5/X12's reading.
// - Y1 (separating against Y0): the re-insertion's own transaction also
//   writes k = 1.
// - Y2 (separating against Y0): k = 1 written while the content is a removal
//   ghost, then re-inserted with no further write.
// - Y4 (separating against Y1): the content is removed WITHOUT a transition
//   (no ghost) and re-inserted with k = 1 — an ordinary new appearance, which
//   starts k=1 and runs no change.
//
// RECORDED 2026-10-07 by the task-followups design session, macOS 27.0.1
// (26A434), Apple Swift 6.4 (swiftlang-6.4.0.33.1), screen unlocked (no
// CGSSessionScreenIsLocked line, displayAsleep main: 0). Compiled form, run
// three times: 65 lines each, byte-identical, exit 0.
//
//   === Y0 control: re-inserted 0.15 s into its removal, k unchanged
//     -- host
//     task k=0 start
//     -- initial settled
//     -- withAnimation flag = true
//     -- settled after withAnimation flag = true
//     -- withAnimation flag = false after 0.15 s
//     -- settled after withAnimation flag = false after 0.15 s
//     -- (no write) after 1.0 s
//     -- settled after (no write) after 1.0 s
//   === Y3 control: k = 1 with no removal
//     -- host
//     task k=0 start
//     -- initial settled
//     -- k = 1
//     task k=0 onCancel
//     task k=1 start
//     change 0->1
//     task k=0 resumed cancelled=true
//     -- settled after k = 1
//     -- (no write) after 0.3 s
//     -- settled after (no write) after 0.3 s
//   === Y1 separating: re-inserted with k = 1 in the same transaction
//     -- host
//     task k=0 start
//     -- initial settled
//     -- withAnimation flag = true
//     -- settled after withAnimation flag = true
//     -- withAnimation flag = false, k = 1 after 0.15 s
//     task k=0 onCancel
//     task k=1 start
//     change 0->1
//     task k=0 resumed cancelled=true
//     -- settled after withAnimation flag = false, k = 1 after 0.15 s
//     -- (no write) after 1.0 s
//     -- settled after (no write) after 1.0 s
//   === Y2 separating: k = 1 written while a ghost, then re-inserted
//     -- host
//     task k=0 start
//     -- initial settled
//     -- withAnimation flag = true
//     -- settled after withAnimation flag = true
//     -- k = 1 after 0.1 s (ghost alive)
//     -- settled after k = 1 after 0.1 s (ghost alive)
//     -- withAnimation flag = false
//     task k=0 onCancel
//     task k=1 start
//     change 0->1
//     task k=0 resumed cancelled=true
//     -- settled after withAnimation flag = false
//     -- (no write) after 1.0 s
//     -- settled after (no write) after 1.0 s
//   === Y4 separating: removed with no transition, re-inserted with k = 1
//     -- host
//     task k=0 start
//     -- initial settled
//     -- flag = true
//     task k=0 onCancel
//     task k=0 resumed cancelled=true
//     -- settled after flag = true
//     -- flag = false, k = 1
//     task k=1 start
//     -- settled after flag = false, k = 1
//     -- (no write) after 0.3 s
//     -- settled after (no write) after 0.3 s
//
// READING NOTES (what TF-A rests on):
// - Y0/Y3: the instrument separates — a re-insertion with the id unchanged
//   runs nothing (X17's reading, now with an id and an onChange); an id
//   change with no removal cancels k=0, starts k=1 and fires change 0->1.
// - Y1/Y2: content re-inserted from a live removal ghost with a CHANGED id
//   compares it against the id it left with: the old task is cancelled, the
//   new one started (cancel before start, X5's order), and the onChange
//   fires old->new — in the re-insertion's own update, exactly as Y3. A
//   write made while the content is a ghost (Y2) is seen at the return,
//   not before (nothing ran at the ghost-time write).
// - Y4: with no transition there is no ghost; the re-insertion is a new
//   appearance — k=1 starts, no change fires, the old task was cancelled at
//   the removal.
// - So SwiftUI keeps the departed view's task id AND onChange baseline
//   across a removal ghost, and compares both at the return.

import AppKit
import SwiftUI

nonisolated(unsafe) var lines: [String] = []
func log(_ s: String) {
    if Thread.isMainThread { lines.append(s) } else { DispatchQueue.main.async { lines.append(s + " (logged via main)") } }
}
func marker(_ s: String) { lines.append("-- \(s)") }

final class M: ObservableObject {
    @Published var flag = false
    @Published var k = 0
}

struct Root<C: View>: View {
    @ObservedObject var m: M
    let c: (M) -> C
    var body: some View {
        ZStack(alignment: .topLeading) { c(m) }.frame(width: 300, height: 200, alignment: .topLeading)
    }
}

@MainActor func spin(_ s: Double = 0.1) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

@MainActor
func arm<Content: View>(_ name: String, @ViewBuilder _ content: @escaping (M) -> Content,
                        steps: [(String, (M) -> Void)], spinAfterStep: Double = 0.05) {
    lines.removeAll()
    let m = M()
    let host = NSHostingView(rootView: Root(m: m, c: content))
    let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                       styleMask: [.titled, .closable], backing: .buffered, defer: false)
    win.isReleasedWhenClosed = false
    marker("host")
    win.contentView = host
    win.orderFrontRegardless()
    spin(0.3)
    marker("initial settled")
    for (label, step) in steps {
        marker(label)
        step(m)
        spin(spinAfterStep)
        marker("settled after \(label)")
    }
    print("=== \(name)")
    for l in lines { print("  \(l)") }
    win.orderOut(nil)
    win.contentView = nil
    spin(0.1)
}

/// A long task that logs its start, the cancel call (onCancel) and the thrown
/// cancellation.
@MainActor func longTask(_ label: String) async {
    log("task \(label) start")
    await withTaskCancellationHandler {
        do { try await Task.sleep(for: .seconds(5)); log("task \(label) finished") }
        catch { log("task \(label) resumed cancelled=\(Task.isCancelled)") }
    } onCancel: {
        log("task \(label) onCancel")
    }
}

/// The content every arm shows while `flag` is false.
@MainActor @ViewBuilder func subject(_ m: M, transition: Bool = true) -> some View {
    if !m.flag {
        let k = m.k
        Text("x").transition(transition ? .opacity : .identity)
            .task(id: k) { await longTask("k=\(k)") }
            .onChange(of: k) { old, new in log("change \(old)->\(new)") }
    }
}

let removal = Animation.linear(duration: 0.6)

MainActor.assumeIsolated {
NSApplication.shared.setActivationPolicy(.accessory)

arm("Y0 control: re-inserted 0.15 s into its removal, k unchanged", { m in subject(m) },
    steps: [("withAnimation flag = true", { m in withAnimation(removal) { m.flag = true } }),
            ("withAnimation flag = false after 0.15 s", { m in spin(0.1); withAnimation(removal) { m.flag = false } }),
            ("(no write) after 1.0 s", { _ in spin(1.0) })])

arm("Y3 control: k = 1 with no removal", { m in subject(m) },
    steps: [("k = 1", { m in m.k = 1 }),
            ("(no write) after 0.3 s", { _ in spin(0.3) })])

arm("Y1 separating: re-inserted with k = 1 in the same transaction", { m in subject(m) },
    steps: [("withAnimation flag = true", { m in withAnimation(removal) { m.flag = true } }),
            ("withAnimation flag = false, k = 1 after 0.15 s", { m in
                spin(0.1); withAnimation(removal) { m.flag = false; m.k = 1 } }),
            ("(no write) after 1.0 s", { _ in spin(1.0) })])

arm("Y2 separating: k = 1 written while a ghost, then re-inserted", { m in subject(m) },
    steps: [("withAnimation flag = true", { m in withAnimation(removal) { m.flag = true } }),
            ("k = 1 after 0.1 s (ghost alive)", { m in spin(0.05); m.k = 1 }),
            ("withAnimation flag = false", { m in withAnimation(removal) { m.flag = false } }),
            ("(no write) after 1.0 s", { _ in spin(1.0) })])

arm("Y4 separating: removed with no transition, re-inserted with k = 1", { m in subject(m, transition: false) },
    steps: [("flag = true", { m in m.flag = true }),
            ("flag = false, k = 1", { m in m.flag = false; m.k = 1 }),
            ("(no write) after 0.3 s", { _ in spin(0.3) })])

exit(0)
}
