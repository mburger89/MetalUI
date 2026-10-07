// SwiftUI probe: lifecycle modifiers — onAppear, onDisappear, onChange, task
// (user request 2026-10-02, gpui-gap item, not a plan task). Evidence for
// rulings LC-A… in docs/superpowers/2026-10-03-lifecycle-decisions.md; spec
// docs/superpowers/specs/2026-10-03-lifecycle-design.md.
//
// HOW TO RUN (compiled form, SA-O):
//
//   xcrun swiftc docs/probes/swiftui-lifecycle.swift -o /tmp/lifecycle-probe
//   /tmp/lifecycle-probe
//
// Headless: nothing is posted at the HID tap; windows are ordered front but
// never need to be key. Updates are driven by short run-loop turns (`spin`),
// and every arm prints the log lines in the order the actions ran, with
// `--` marker lines the harness writes between steps, so "fired inside the
// step" and "fired only after a later turn" are told apart.
//
// THE INSTRUMENTS.
// - `log(_:)`: an append-only list; each arm prints it.
// - `DrawSpy`: an NSViewRepresentable whose NSView logs `update v=` from
//   `updateNSView` and `draw v=` from `draw(_:)` — the value the view would
//   DRAW, so a write made by `onAppear` either reaches the first draw or not.
//   `host.display()` forces the draw (the screen may be locked; CA flushes are
//   not observed, AppKit's drawing is).
// - `body` lines: a root body logs each evaluation with the model's value.
//
// POSITIVE CONTROLS AND SEPARATING ARMS.
// - L0 (a hosted view logs `appear`) against L0b (the same view under
//   `if false`: nothing).
// - E1 (`if` removal: onDisappear) against E3/E4 (`.hidden()`, `.opacity(0)`:
//   the view appears and nothing disappears on a toggle).
// - S1 (`List` / S2 `LazyVStack` scrolled: rows disappear) against S3 (a plain
//   `VStack` in a `ScrollView` scrolled: nothing disappears).
// - T0 (removal with no animation) against T1 (removal under a 0.6 s linear
//   animation with a transition).
// - C1 (a change fires) against C6/C7 (a change undone within one update, a
//   write of the same value: nothing).
//
// - S1/S2 use AppKit scrolling (`appKitScroll`: the first NSScrollView's clip
//   view scrolled and reflected). The `ScrollViewReader.scrollTo` steps in the
//   same arms are a BROKEN INSTRUMENT, kept visible: the `onChange(of:
//   m.target)` inside the reader's closure never fires here (no
//   `(scrollTo …)` line is logged), so those steps scroll nothing.
// - D1: a view's own `@State` read and written from its onDisappear.
// - D2: a never-written `@State var mon = Mon()` default, its view re-initialised
//   three times (each `Mon()` evaluation logs `made Mon <serial>`): which
//   instance onAppear and onDisappear see. The `made` lines are the separating
//   arm inside the arm — the default IS re-evaluated, so a framework that kept
//   the latest evaluation would log a later serial at the disappearance.
// - W1–W3: the window ordered out, closed (`isReleasedWhenClosed = false`, the
//   host retained), and the hosting view removed from it.
// - K1/K2: `.task` and `.task(id:)` — recorded for the owner of the deferred
//   `.task` (ruling `LC-L`), not built on this branch.
//
// RECORDED 2026-10-03 by the lifecycle design session, macOS 27.0.1 (26A434),
// Apple Swift 6.4 (swiftlang-6.4.0.33.1), screen LOCKED
// (CGSSessionScreenIsLocked = 1, displayAsleep main: 1). Compiled form, run
// three times: 502 lines each, exit by the harness's kill after the last arm
// (the process has no exit of its own), stderr empty. Every line outside the
// lazy-container arms (S1, S2) is byte-identical across the three runs; in S1
// and S2 the SETS of rows appearing and disappearing at each step are
// identical, and their ORDER differs from run to run (hash order).
//
// RE-RUN 2026-10-03 by the critic pass (ruling LC-P), same machine and
// toolchain, screen LOCKED (CGSSessionScreenIsLocked = 1, displayAsleep main:
// 1). The design's arms unchanged, one run: byte-identical to the reading
// below outside S1/S2 (whose per-step row sets agree). Then arms A6, A6b and
// E2b added and the whole file run twice: 535 lines each, stderr empty, the
// process exiting on its own within 10 s of the K2 block; the two runs are
// byte-identical outside S1 and S2 (row sets equal per step, order differs).
// RE-RUN 2026-10-03 by lane 1's fix pass (divergence 125), same machine and
// toolchain, screen LOCKED (CGSSessionScreenIsLocked = 1, displayAsleep main:
// 1). Arm D2 added after D1 and the whole file run once: 555 lines, stderr
// empty; byte-identical to the reading below outside S1/S2 and the new D2
// block (spliced in below after D1).
//
// The second of those runs, verbatim:
//
//   === L0 control: a hosted view's onAppear fires
//     -- host
//     -- ordered front
//     appear x
//     -- initial settled
//   === L0b separating: the same view under `if false` never appears
//     -- host
//     -- ordered front
//     -- initial settled
//   === A1 insertion order: grandparent > parent > two children (one `if` inserts all)
//     -- host
//     -- ordered front
//     -- initial settled
//     -- show = true
//     appear child2
//     appear child1
//     appear parent
//     appear grandparent
//     -- settled after show = true
//     -- show = false
//     disappear child2
//     disappear child1
//     disappear parent
//     disappear grandparent
//     -- settled after show = false
//   === A2 siblings in one container, each its own `if`, all inserted in one update
//     -- host
//     -- ordered front
//     -- initial settled
//     -- show = true
//     appear s3
//     appear s2
//     appear s1
//     -- settled after show = true
//     -- show = false
//     disappear s1
//     disappear s2
//     disappear s3
//     -- settled after show = false
//   === A3 stacked modifiers on one view: .onAppear{a}.onAppear{b}, .onDisappear{a}.onDisappear{b}
//     -- host
//     -- ordered front
//     -- initial settled
//     -- show = true
//     appear inner(a)
//     appear outer(b)
//     -- settled after show = true
//     -- show = false
//     disappear inner(a)
//     disappear outer(b)
//     -- settled after show = false
//   === A4 if/else branch swap: does the new branch appear before the old disappears?
//     -- host
//     -- ordered front
//     appear else
//     -- initial settled
//     -- flag = true
//     appear then
//     disappear else
//     -- settled after flag = true
//     -- flag = false
//     appear else
//     disappear then
//     -- settled after flag = false
//   === A5 one update that removes one sibling and inserts another
//     -- host
//     -- ordered front
//     appear old
//     -- initial settled
//     -- flag = true
//     appear new
//     disappear old
//     -- settled after flag = true
//   === A6 .onAppear/.onDisappear on a ForEach: count 0 -> 3 -> 1 -> 0 -> 2
//     -- host
//     -- ordered front
//     -- initial settled
//     -- count = 3
//     appear foreach
//     -- settled after count = 3
//     -- count = 1
//     -- settled after count = 1
//     -- count = 0
//     disappear foreach
//     -- settled after count = 0
//     -- count = 2
//     appear foreach
//     -- settled after count = 2
//   === A6b .onAppear/.onDisappear on a Group of two views, the group under an `if`
//     -- host
//     -- ordered front
//     -- initial settled
//     -- flag = true
//     appear group
//     -- settled after flag = true
//     -- flag = false
//     disappear group
//     -- settled after flag = false
//   === F1 onAppear relative to the first update and draw; onAppear writes count = 1
//     -- host
//     body count=0
//     make v=0
//     update v=0
//     -- ordered front
//     appear (writes count=1)
//     body count=1
//     update v=1
//     draw v=1
//     -- initial settled
//     -- display()
//     -- settled after display()
//   === F2b hand-driven: contentView, layout, display, spin, display — no orderFront
//     -- contentView = host
//     body count=0
//     -- layoutSubtreeIfNeeded
//     make v=0
//     update v=0
//     appear (writes count=1)
//     body count=1
//     update v=1
//     -- display()
//     -- spin
//     draw v=1
//     -- display() again
//   === F3 re-entrancy: an onAppear that inserts content whose own onAppear inserts more
//     -- host
//     -- ordered front
//     appear first
//     first's action: more = true
//     appear second (writes count=1)
//     appear third
//     -- initial settled
//   === C1 onChange(of:) { old, new in } — v 0 -> 1
//     -- host
//     -- ordered front
//     -- initial settled
//     -- v = 1
//     change old=0 new=1
//     -- settled after v = 1
//   === C2 zero-parameter form onChange(of:) { } — v 0 -> 1
//     -- host
//     -- ordered front
//     -- initial settled
//     -- v = 1
//     change (zero-param) v=1
//     -- settled after v = 1
//   === C3 initial: true — fires on appear? with what (old, new)?
//     -- host
//     -- ordered front
//     appear
//     change old=5 new=5
//     -- initial settled
//     -- v = 6
//     change old=5 new=6
//     -- settled after v = 6
//   === C3b initial: true, onChange written INSIDE onAppear (order flips?)
//     -- host
//     -- ordered front
//     change old=5 new=5
//     appear
//     -- initial settled
//   === C4 initial: false (default) — no fire on appear
//     -- host
//     -- ordered front
//     -- initial settled
//   === C5 two writes in one update: v = 1; v = 2
//     -- host
//     -- ordered front
//     -- initial settled
//     -- v = 1; v = 2
//     change old=0 new=2
//     -- settled after v = 1; v = 2
//   === C6 a change undone within one update: v = 1; v = 0
//     -- host
//     -- ordered front
//     -- initial settled
//     -- v = 1; v = 0
//     -- settled after v = 1; v = 0
//   === C7 a write of the same value: v = 0
//     -- host
//     -- ordered front
//     -- initial settled
//     -- v = 0
//     -- settled after v = 0
//   === C8 parent vs child onChange on one value; and relative to body and draw
//     -- host
//     body v=0
//     make v=0
//     update v=0
//     -- ordered front
//     draw v=0
//     -- initial settled
//     -- v = 1
//     body v=1
//     update v=1
//     child change 0->1
//     parent change 0->1
//     draw v=1
//     -- settled after v = 1
//     -- display()
//     -- settled after display()
//   === C9 a cascade: onChange(v) writes w; onChange(w) fires in the same turn?
//     -- host
//     body v=0 w=0
//     -- ordered front
//     -- initial settled
//     -- v = 1
//     body v=1 w=0
//     change v -> 1, writes w
//     body v=1 w=10
//     change w -> 10
//     -- settled after v = 1
//   === C10 identity reset: .onChange(of: v).id(k); k and v change together
//     -- host
//     -- ordered front
//     appear k=0
//     -- initial settled
//     -- k = 1; v = 1
//     appear k=1
//     disappear
//     -- settled after k = 1; v = 1
//     -- v = 2
//     change old=1 new=2
//     -- settled after v = 2
//   === C11 sibling order on one value change
//     -- host
//     -- ordered front
//     -- initial settled
//     -- v = 1
//     change b
//     change a
//     -- settled after v = 1
//   === C12 onChange and onAppear of content inserted by the same update
//     -- host
//     -- ordered front
//     -- initial settled
//     -- show = true
//     change show (existing view)
//     appear b
//     -- settled after show = true
//   === C13 a removed view does not see the change that removes it
//     -- host
//     -- ordered front
//     -- initial settled
//     -- show = true
//     disappear b
//     -- settled after show = true
//   === E1 control: an `if` removes content
//     -- host
//     -- ordered front
//     appear x
//     -- initial settled
//     -- flag = true
//     disappear x
//     -- settled after flag = true
//   === E2 .id() change: order of the old disappear and the new appear
//     -- host
//     -- ordered front
//     appear k=0
//     -- initial settled
//     -- k = 1
//     appear k=1
//     disappear (was k=0?)
//     -- settled after k = 1
//   === E2b .id(k) then .onAppear/.onDisappear/.onChange outside it; k and v change together
//     -- host
//     -- ordered front
//     appear k=0
//     -- initial settled
//     -- k = 1; v = 1
//     change old=0 new=1
//     -- settled after k = 1; v = 1
//   === E3 .hidden(): appears while hidden; toggling an outer condition
//     -- host
//     -- ordered front
//     appear hidden
//     -- initial settled
//     -- flag = true
//     appear late-hidden
//     -- settled after flag = true
//   === E4 opacity 0: appears; 1 -> 0 -> 1 fires nothing
//     -- host
//     -- ordered front
//     appear faded
//     -- initial settled
//     -- opaque toggled
//     -- settled after opaque toggled
//     -- opaque toggled back
//     -- settled after opaque toggled back
//   === E5 zero-size frame and a clipped-out view: still appear?
//     -- host
//     -- ordered front
//     appear offscreen
//     appear zero
//     -- initial settled
//   === D1 onDisappear reads its own @State; a write there; re-inserted content starts fresh
//     -- host
//     -- ordered front
//     -- initial settled
//     -- show = true
//     appear reads n=0, writes n=7
//     -- settled after show = true
//     -- show = false
//     disappear reads n=7, writes n=99
//     -- settled after show = false
//     -- show = true again
//     appear reads n=0, writes n=7
//     -- settled after show = true again
//   === D2 a never-written @State default: onAppear and onDisappear see one instance across re-inits
//     -- host
//     -- ordered front
//     -- initial settled
//     -- show = true
//     made Mon 1
//     appear start Mon 1
//     -- settled after show = true
//     -- v = 1
//     made Mon 2
//     -- settled after v = 1
//     -- v = 2
//     made Mon 3
//     -- settled after v = 2
//     -- v = 3
//     made Mon 4
//     -- settled after v = 3
//     -- show = false
//     disappear stop Mon 1
//     -- settled after show = false
//   === S1 List(0..<200) rows in a 100 pt frame, scrolled to row 150 then back to 0
//     -- host
//     -- ordered front
//     appear row0
//     appear row1
//     appear row2
//     appear row3
//     -- initial settled
//     -- scrollTo(150)
//     -- settled after scrollTo(150)
//     -- scrollTo(0)
//     -- settled after scrollTo(0)
//     -- AppKit scroll to y = 3000
//     (appKit scroll: 1 NSScrollView(s))
//     disappear row0
//     disappear row1
//     disappear row2
//     disappear row3
//     appear row126
//     appear row123
//     appear row124
//     appear row125
//     appear row127
//     appear row128
//     -- settled after AppKit scroll to y = 3000
//     -- AppKit scroll to y = 0
//     (appKit scroll: 1 NSScrollView(s))
//     disappear row123
//     disappear row124
//     disappear row125
//     disappear row126
//     disappear row127
//     disappear row128
//     appear row2
//     appear row0
//     appear row1
//     appear row3
//     -- settled after AppKit scroll to y = 0
//   === S2 ScrollView { LazyVStack } same
//     -- host
//     -- ordered front
//     appear row4
//     appear row3
//     appear row0
//     appear row1
//     appear row6
//     appear row5
//     appear row2
//     -- initial settled
//     -- scrollTo(150)
//     -- settled after scrollTo(150)
//     -- scrollTo(0)
//     -- settled after scrollTo(0)
//     -- AppKit scroll to y = 3000
//     (appKit scroll: 1 NSScrollView(s))
//     disappear row2
//     disappear row1
//     disappear row0
//     disappear row6
//     disappear row4
//     disappear row5
//     disappear row3
//     appear row191
//     appear row189
//     appear row187
//     appear row192
//     appear row188
//     appear row193
//     appear row190
//     -- settled after AppKit scroll to y = 3000
//     -- AppKit scroll to y = 0
//     (appKit scroll: 1 NSScrollView(s))
//     disappear row193
//     disappear row187
//     disappear row192
//     disappear row188
//     disappear row190
//     disappear row189
//     disappear row191
//     appear row5
//     appear row3
//     appear row6
//     appear row1
//     appear row4
//     appear row0
//     appear row2
//     -- settled after AppKit scroll to y = 0
//   === S3 separating: ScrollView { VStack } (not lazy) — 30 rows, scrolled
//     -- host
//     -- ordered front
//     appear row29
//     appear row28
//     appear row27
//     appear row26
//     appear row25
//     appear row24
//     appear row23
//     appear row22
//     appear row21
//     appear row20
//     appear row19
//     appear row18
//     appear row17
//     appear row16
//     appear row15
//     appear row14
//     appear row13
//     appear row12
//     appear row11
//     appear row10
//     appear row9
//     appear row8
//     appear row7
//     appear row6
//     appear row5
//     appear row4
//     appear row3
//     appear row2
//     appear row1
//     appear row0
//     -- initial settled
//     -- scrollTo(25)
//     -- settled after scrollTo(25)
//     -- AppKit scroll to y = 500
//     (appKit scroll: 1 NSScrollView(s))
//     -- settled after AppKit scroll to y = 500
//   === T0 control: removal with no animation
//     -- host
//     -- ordered front
//     appear x
//     -- initial settled
//     -- flag = true (no animation)
//     disappear x
//     -- settled after flag = true (no animation)
//   === T1 removal under withAnimation(.linear(duration: 0.6)) with .transition(.opacity)
//     -- host
//     -- ordered front
//     appear x
//     -- initial settled
//     -- withAnimation(0.6) { flag = true }
//     -- settled after withAnimation(0.6) { flag = true }
//     -- spin 1.0 more
//     disappear x
//     -- settled after spin 1.0 more
//   === T2 insertion under withAnimation(.linear(duration: 0.6)) with .transition(.opacity)
//     -- host
//     -- ordered front
//     -- initial settled
//     -- withAnimation(0.6) { flag = true }
//     appear x
//     -- settled after withAnimation(0.6) { flag = true }
//   === T3 onDisappear written OUTSIDE the transition: .transition(.opacity).onDisappear
//     -- host
//     -- ordered front
//     appear x
//     -- initial settled
//     -- withAnimation(0.6) { flag = true }
//     -- settled after withAnimation(0.6) { flag = true }
//     -- spin 1.0 more
//     disappear x (outer)
//     -- settled after spin 1.0 more
//   === T4 removal under a 0.6 s fade, re-inserted 0.2 s in
//     -- host
//     -- ordered front
//     appear x
//     -- initial settled
//     -- withAnimation(0.6) { flag = true }
//     -- settled after withAnimation(0.6) { flag = true }
//     -- spin 0.15, then withAnimation(0.6) { flag = false }
//     -- settled after spin 0.15, then withAnimation(0.6) { flag = false }
//     -- spin 1.0 more
//     -- settled after spin 1.0 more
//   === T5 the parent of a fading child: parent removed under animation, child has no transition
//     -- host
//     -- ordered front
//     appear child
//     appear parent
//     -- initial settled
//     -- withAnimation(0.6) { flag = true }
//     -- settled after withAnimation(0.6) { flag = true }
//     -- spin 1.0 more
//     disappear child
//     disappear parent
//     -- settled after spin 1.0 more
//   === W1 window orderOut (hidden, not closed)
//     -- host
//     -- ordered front
//     appear x
//     -- initial settled
//     -- orderOut
//     -- settled after orderOut
//     -- orderFront
//     -- settled after orderFront
//   === W2 window close()
//     -- host
//     -- ordered front
//     appear x
//     -- initial settled
//     -- close()
//     -- settled after close()
//   === W3 contentView = nil (the hosting view leaves the window)
//     -- host
//     -- ordered front
//     appear x
//     -- initial settled
//     -- contentView = nil
//     disappear x
//     -- settled after contentView = nil
//   === K1 .task: start relative to onAppear; cancelled when an `if` removes it
//     -- host
//     -- ordered front
//     appear
//     task start
//     -- initial settled
//     -- flag = true
//     disappear
//     task cancelled: true
//     -- settled after flag = true
//   === K2 .task(id:): restarted when id changes
//     -- host
//     -- ordered front
//     task start k=0
//     -- initial settled
//     -- k = 1
//     task start k=1
//     task k=0 cancelled
//     -- settled after k = 1
//
// READING NOTES (what each ruling may rest on):
// - L0/L0b: onAppear fires for hosted content, never for content an `if false`
//   does not produce.
// - A1/A2/A3 (insertion): children before parents, later siblings before
//   earlier ones, an inner modifier before an outer one — the REVERSE of the
//   pre-order (document) walk: child2, child1, parent, grandparent; s3, s2,
//   s1; inner(a), outer(b).
// - A1/A3 (removal): the same reverse pre-order (child2, child1, parent,
//   grandparent; inner(a), outer(b)). A2 (removal, three separately removed
//   siblings): FORWARD order s1, s2, s3 — the one arm that disagrees.
// - A6/A6b (critic pass): a modifier on a ForEach or a Group fires ONCE for
//   the group, not per child, and only while the group has at least one view
//   (an empty ForEach does not appear; 3 -> 1 fires nothing; -> 0 disappears;
//   -> 2 appears again).
// - E2b (critic pass): lifecycle modifiers written OUTSIDE `.id(k)` do not
//   fire on a `k` change, and their onChange compares across the identities
//   (only `change old=0 new=1`) — the separating arm for E2/C10.
// - A4/A5/E2/C10: in one update, the new content's onAppear runs BEFORE the old
//   content's onDisappear (if/else swap, sibling swap, `.id` change).
// - F1/F2b: onAppear runs after the first body evaluation and before the first
//   draw; its write re-evaluates the body and the FIRST draw shows it
//   (`draw v=1`, never `draw v=0`). F2b: `layoutSubtreeIfNeeded()` alone runs
//   the action and the second body evaluation, synchronously.
// - F3: a chain (an onAppear inserting content whose onAppear inserts more)
//   settles to a fixed point inside one run-loop turn.
// - C1/C2: both closure forms fire on a change; C3: `initial: true` fires on
//   appearance with old == new (5, 5), in modifier order with onAppear (C3:
//   appear then change; C3b, modifiers swapped: change then appear); C4: the
//   default does not fire on appearance.
// - C5: two writes in one update fire once (0 -> 2); C6: a change undone
//   within one update fires nothing; C7: writing the same value fires nothing.
// - C8: onChange runs after the body and the representable update, before
//   the draw; child before parent. C9: a cascade (onChange writing a value
//   another onChange watches) runs inside the same turn, body re-evaluated
//   between. C11: siblings in reverse order (b, a).
// - C10: a new identity does not compare against the old identity's value
//   (k and v changed together: appear, disappear, no change); the next change
//   compares against the new identity's first value (1 -> 2).
// - C12: in one update, the existing view's onChange runs BEFORE the inserted
//   view's onAppear, and the inserted view's onChange does not fire. C13: a
//   view removed by the update does not see the change that removed it.
// - E1: an `if` removal runs onDisappear. E3: a `.hidden()` view appears
//   (also when inserted later). E4: an opacity-0 view appears, and toggling
//   opacity fires nothing. E5: a zero-size view and one offset 5000 pt outside
//   a clipped 50 pt frame both appear.
// - S1 (List) and S2 (LazyVStack): only rows near the viewport appear (4 and
//   7); scrolling away runs onDisappear for every row that left and onAppear
//   for every row that arrived; scrolling back reverses it. S3 (plain VStack
//   in a ScrollView): every row appears at once and scrolling fires nothing —
//   the separating arm. In S1/S2 the disappears are logged before the appears
//   in runs 1 and 3; run 2 interleaves them in S2 — no order is stable.
// - T0: removal with no animation runs onDisappear at once. T1: removal under
//   a 0.6 s linear animation with `.transition(.opacity)` runs onDisappear
//   only AFTER the transition (not within 0.05 s; within the next 1.0 s). T3:
//   the same with onDisappear written outside the transition. T5: a fading
//   parent and its untransitioned child both disappear after the fade, child
//   first. T2: insertion under the same animation runs onAppear at once.
// - T4: content re-inserted 0.15 s into its 0.6 s removal runs NEITHER
//   onDisappear NOR a second onAppear — SwiftUI keeps the view.
// - D1: onDisappear reads its own `@State` as it was (n = 7); its write
//   (n = 99) is lost: content inserted again starts fresh (n = 0).
// - D2: SwiftUI keeps the FIRST evaluation of a `@State` default for the
//   view's lifetime: the default is evaluated on every re-init (`made Mon 1`
//   … `made Mon 4`) and discarded, and onAppear and onDisappear both see
//   `Mon 1`. MetalUI re-seeds a never-written default every build (divergence
//   125).
// - W1: ordering a window out fires nothing; W2: `close()` with the host
//   retained fires nothing; W3: removing the hosting view from the window runs
//   onDisappear.
// - K1: `.task` starts after onAppear and is cancelled after onDisappear
//   (`Task.isCancelled` true). K2: `.task(id:)` restarts. (CORRECTED 2026-10-07, PX-V
//   item 5: the printed order "task start k=1" before "task k=0 cancelled" is
//   the old task's RESUMPTION, not its cancel; swiftui-task.swift X5 shows
//   the old body is cancelled first, then the new one starts.)

import AppKit
import SwiftUI

nonisolated(unsafe) var lines: [String] = []
func log(_ s: String) { lines.append(s) }
func marker(_ s: String) { lines.append("-- \(s)") }

final class M: ObservableObject {
    @Published var show = false
    @Published var flag = false
    @Published var v = 0
    @Published var w = 0
    @Published var k = 0
    @Published var count = 0
    @Published var more = false
    @Published var opaque = true
    @Published var target: Int? = nil
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

/// Hosts `content`, runs `setup` before hosting, spins, then for each step
/// writes a marker, runs it and spins. Prints the log; returns the window
/// (closed unless `keep`).
@MainActor @discardableResult
func arm<Content: View>(_ name: String, @ViewBuilder _ content: @escaping (M) -> Content,
                        setup: (M) -> Void = { _ in },
                        initialMarker: Bool = true,
                        steps: [(String, (M, NSWindow, NSHostingView<Root<Content>>) -> Void)] = [],
                        spinAfterStep: Double = 0.15,
                        keep: Bool = false) -> NSWindow {
    lines.removeAll()
    let m = M()
    setup(m)
    let host = NSHostingView(rootView: Root(m: m, c: content))
    let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                       styleMask: [.titled, .closable], backing: .buffered, defer: false)
    win.isReleasedWhenClosed = false
    marker("host")
    win.contentView = host
    win.orderFrontRegardless()
    marker("ordered front")
    spin(0.25)
    if initialMarker { marker("initial settled") }
    for (label, step) in steps {
        marker(label)
        step(m, win, host)
        spin(spinAfterStep)
        marker("settled after \(label)")
    }
    print("=== \(name)")
    for l in lines { print("  \(l)") }
    if !keep {
        win.orderOut(nil)
        win.contentView = nil
        spin(0.05)
    }
    return win
}

/// Every NSScrollView under `view`, depth first.
@MainActor func scrollViews(in view: NSView) -> [NSScrollView] {
    var found: [NSScrollView] = []
    if let s = view as? NSScrollView { found.append(s) }
    for sub in view.subviews { found += scrollViews(in: sub) }
    return found
}
/// Scrolls the first NSScrollView under `view` to `y` (the AppKit path, for
/// when `ScrollViewReader` does not move a headless list).
@MainActor func appKitScroll(_ view: NSView, to y: CGFloat) {
    let all = scrollViews(in: view)
    log("(appKit scroll: \(all.count) NSScrollView(s))")
    guard let s = all.first else { return }
    s.contentView.scroll(to: NSPoint(x: 0, y: y))
    s.reflectScrolledClipView(s.contentView)
}

struct Leaf: View {
    let name: String
    var body: some View {
        Text(name).onAppear { log("appear \(name)") }.onDisappear { log("disappear \(name)") }
    }
}

/// D2's instrument: every `Mon()` evaluation takes the next serial and logs it,
/// so a re-init of `MonLeaf` (its `v` changes) is visible as a `made` line.
nonisolated(unsafe) var monSerial = 0
final class Mon {
    let serial: Int
    init() { monSerial += 1; serial = monSerial; log("made Mon \(serial)") }
}
struct MonLeaf: View {
    let v: Int
    @State var mon = Mon()
    var body: some View {
        Text("v=\(v)").onAppear { log("appear start Mon \(mon.serial)") }
            .onDisappear { log("disappear stop Mon \(mon.serial)") }
    }
}

struct StateLeaf: View {
    @State var n = 0
    var body: some View {
        Text("n").onAppear { log("appear reads n=\(n), writes n=7"); n = 7 }
            .onDisappear { log("disappear reads n=\(n), writes n=99"); n = 99 }
    }
}

MainActor.assumeIsolated {
NSApplication.shared.setActivationPolicy(.accessory)

// ------------------------------------------------------------ L: controls
arm("L0 control: a hosted view's onAppear fires", { _ in Leaf(name: "x") })
arm("L0b separating: the same view under `if false` never appears", { _ in
    if false { Leaf(name: "x") }
})

// ------------------------------------------------------------ A: order
arm("A1 insertion order: grandparent > parent > two children (one `if` inserts all)", { m in
    if m.show {
        VStack {
            VStack {
                Leaf(name: "child1")
                Leaf(name: "child2")
            }
            .onAppear { log("appear parent") }.onDisappear { log("disappear parent") }
        }
        .onAppear { log("appear grandparent") }.onDisappear { log("disappear grandparent") }
    }
}, steps: [("show = true", { m, _, _ in m.show = true }),
           ("show = false", { m, _, _ in m.show = false })])

arm("A2 siblings in one container, each its own `if`, all inserted in one update", { m in
    VStack {
        if m.show { Leaf(name: "s1") }
        if m.show { Leaf(name: "s2") }
        if m.show { Leaf(name: "s3") }
    }
}, steps: [("show = true", { m, _, _ in m.show = true }),
           ("show = false", { m, _, _ in m.show = false })])

arm("A3 stacked modifiers on one view: .onAppear{a}.onAppear{b}, .onDisappear{a}.onDisappear{b}", { m in
    if m.show {
        Text("x").onAppear { log("appear inner(a)") }.onAppear { log("appear outer(b)") }
            .onDisappear { log("disappear inner(a)") }.onDisappear { log("disappear outer(b)") }
    }
}, steps: [("show = true", { m, _, _ in m.show = true }),
           ("show = false", { m, _, _ in m.show = false })])

arm("A4 if/else branch swap: does the new branch appear before the old disappears?", { m in
    if m.flag { Leaf(name: "then") } else { Leaf(name: "else") }
}, steps: [("flag = true", { m, _, _ in m.flag = true }),
           ("flag = false", { m, _, _ in m.flag = false })])

arm("A5 one update that removes one sibling and inserts another", { m in
    VStack {
        if !m.flag { Leaf(name: "old") }
        if m.flag { Leaf(name: "new") }
    }
}, steps: [("flag = true", { m, _, _ in m.flag = true })])

// Added by the critic pass (ruling LC-P): a lifecycle modifier on a group of
// several views — once for the group, or once per child?
arm("A6 .onAppear/.onDisappear on a ForEach: count 0 -> 3 -> 1 -> 0 -> 2", { m in
    VStack {
        ForEach(0..<m.count, id: \.self) { i in Text("r\(i)") }
            .onAppear { log("appear foreach") }.onDisappear { log("disappear foreach") }
    }
}, steps: [("count = 3", { m, _, _ in m.count = 3 }),
           ("count = 1", { m, _, _ in m.count = 1 }),
           ("count = 0", { m, _, _ in m.count = 0 }),
           ("count = 2", { m, _, _ in m.count = 2 })])

arm("A6b .onAppear/.onDisappear on a Group of two views, the group under an `if`", { m in
    VStack {
        if m.flag {
            Group { Text("a"); Text("b") }
                .onAppear { log("appear group") }.onDisappear { log("disappear group") }
        }
    }
}, steps: [("flag = true", { m, _, _ in m.flag = true }),
           ("flag = false", { m, _, _ in m.flag = false })])

// ------------------------------------------------------------ F: first frame
arm("F1 onAppear relative to the first update and draw; onAppear writes count = 1", { m in
    let _ = log("body count=\(m.count)")
    DrawSpy(v: m.count).frame(width: 20, height: 20)
        .onAppear { log("appear (writes count=1)"); m.count = 1 }
}, steps: [("display()", { _, _, host in host.display() })])

// F2 needs a hand-driven host: no spin between hosting and the first draw.
do {
    lines.removeAll()
    let m = M()
    let host = NSHostingView(rootView: Root(m: m, c: { (m: M) -> AnyView in
        log("body count=\(m.count)")
        return AnyView(DrawSpy(v: m.count).frame(width: 20, height: 20)
            .onAppear { log("appear (writes count=1)"); m.count = 1 })
    }))
    let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                       styleMask: [.titled], backing: .buffered, defer: false)
    marker("contentView = host")
    win.contentView = host
    marker("layoutSubtreeIfNeeded")
    host.layoutSubtreeIfNeeded()
    marker("display()")
    host.display()
    marker("spin")
    spin(0.25)
    marker("display() again")
    host.display()
    print("=== F2b hand-driven: contentView, layout, display, spin, display — no orderFront")
    for l in lines { print("  \(l)") }
    win.contentView = nil
    spin(0.05)
}

arm("F3 re-entrancy: an onAppear that inserts content whose own onAppear inserts more", { m in
    VStack {
        Leaf(name: "first").onAppear { log("first's action: more = true"); m.more = true }
        if m.more {
            Text("second").onAppear { log("appear second (writes count=1)"); m.count = 1 }
        }
        if m.count == 1 { Leaf(name: "third") }
    }
})

// ------------------------------------------------------------ C: onChange
arm("C1 onChange(of:) { old, new in } — v 0 -> 1", { m in
    Text("x").onChange(of: m.v) { old, new in log("change old=\(old) new=\(new)") }
}, steps: [("v = 1", { m, _, _ in m.v = 1 })])

arm("C2 zero-parameter form onChange(of:) { } — v 0 -> 1", { m in
    Text("x").onChange(of: m.v) { log("change (zero-param) v=\(m.v)") }
}, steps: [("v = 1", { m, _, _ in m.v = 1 })])

arm("C3 initial: true — fires on appear? with what (old, new)?", { m in
    Text("x").onAppear { log("appear") }
        .onChange(of: m.v, initial: true) { old, new in log("change old=\(old) new=\(new)") }
}, setup: { m in m.v = 5 }, steps: [("v = 6", { m, _, _ in m.v = 6 })])

arm("C3b initial: true, onChange written INSIDE onAppear (order flips?)", { m in
    Text("x").onChange(of: m.v, initial: true) { old, new in log("change old=\(old) new=\(new)") }
        .onAppear { log("appear") }
}, setup: { m in m.v = 5 })

arm("C4 initial: false (default) — no fire on appear", { m in
    Text("x").onChange(of: m.v) { old, new in log("change old=\(old) new=\(new)") }
}, setup: { m in m.v = 5 })

arm("C5 two writes in one update: v = 1; v = 2", { m in
    Text("x").onChange(of: m.v) { old, new in log("change old=\(old) new=\(new)") }
}, steps: [("v = 1; v = 2", { m, _, _ in m.v = 1; m.v = 2 })])

arm("C6 a change undone within one update: v = 1; v = 0", { m in
    Text("x").onChange(of: m.v) { old, new in log("change old=\(old) new=\(new)") }
}, steps: [("v = 1; v = 0", { m, _, _ in m.v = 1; m.v = 0 })])

arm("C7 a write of the same value: v = 0", { m in
    Text("x").onChange(of: m.v) { old, new in log("change old=\(old) new=\(new)") }
}, steps: [("v = 0", { m, _, _ in m.v = 0 })])

arm("C8 parent vs child onChange on one value; and relative to body and draw", { m in
    let _ = log("body v=\(m.v)")
    VStack {
        DrawSpy(v: m.v).frame(width: 20, height: 20)
            .onChange(of: m.v) { old, new in log("child change \(old)->\(new)") }
    }
    .onChange(of: m.v) { old, new in log("parent change \(old)->\(new)") }
}, steps: [("v = 1", { m, _, _ in m.v = 1 }),
           ("display()", { _, _, host in host.display() })])

arm("C9 a cascade: onChange(v) writes w; onChange(w) fires in the same turn?", { m in
    let _ = log("body v=\(m.v) w=\(m.w)")
    Text("x")
        .onChange(of: m.v) { _, new in log("change v -> \(new), writes w"); m.w = new * 10 }
        .onChange(of: m.w) { _, new in log("change w -> \(new)") }
}, steps: [("v = 1", { m, _, _ in m.v = 1 })])

arm("C10 identity reset: .onChange(of: v).id(k); k and v change together", { m in
    Text("x").onAppear { log("appear k=\(m.k)") }.onDisappear { log("disappear") }
        .onChange(of: m.v) { old, new in log("change old=\(old) new=\(new)") }
        .id(m.k)
}, steps: [("k = 1; v = 1", { m, _, _ in m.k = 1; m.v = 1 }),
           ("v = 2", { m, _, _ in m.v = 2 })])

arm("C11 sibling order on one value change", { m in
    VStack {
        Text("a").onChange(of: m.v) { log("change a") }
        Text("b").onChange(of: m.v) { log("change b") }
    }
}, steps: [("v = 1", { m, _, _ in m.v = 1 })])

arm("C12 onChange and onAppear of content inserted by the same update", { m in
    VStack {
        Text("a").onChange(of: m.show) { log("change show (existing view)") }
        if m.show {
            Text("b").onAppear { log("appear b") }
                .onChange(of: m.show) { log("change show (inserted view)") }
        }
    }
}, steps: [("show = true", { m, _, _ in m.show = true })])

arm("C13 a removed view does not see the change that removes it", { m in
    VStack {
        if !m.show {
            Text("b").onDisappear { log("disappear b") }
                .onChange(of: m.show) { log("change show (removed view)") }
        }
    }
}, steps: [("show = true", { m, _, _ in m.show = true })])

// ------------------------------------------------------------ E: disappearance
arm("E1 control: an `if` removes content", { m in
    if !m.flag { Leaf(name: "x") }
}, steps: [("flag = true", { m, _, _ in m.flag = true })])

arm("E2 .id() change: order of the old disappear and the new appear", { m in
    Text("x").onAppear { log("appear k=\(m.k)") }.onDisappear { log("disappear (was k=\(m.k - 1)?)") }
        .id(m.k)
}, steps: [("k = 1", { m, _, _ in m.k = 1 })])

// Added by the critic pass (ruling LC-P): the lifecycle modifiers written
// OUTSIDE `.id` — the order CLAUDE.md's ".id() outermost" rule forbids in
// MetalUI, but which compiles in both. The separating arm for E2/C10.
arm("E2b .id(k) then .onAppear/.onDisappear/.onChange outside it; k and v change together", { m in
    Text("x").id(m.k)
        .onAppear { log("appear k=\(m.k)") }.onDisappear { log("disappear") }
        .onChange(of: m.v) { old, new in log("change old=\(old) new=\(new)") }
}, steps: [("k = 1; v = 1", { m, _, _ in m.k = 1; m.v = 1 })])

arm("E3 .hidden(): appears while hidden; toggling an outer condition", { m in
    VStack {
        Leaf(name: "hidden").hidden()
        if m.flag { Leaf(name: "late-hidden").hidden() }
    }
}, steps: [("flag = true", { m, _, _ in m.flag = true })])

arm("E4 opacity 0: appears; 1 -> 0 -> 1 fires nothing", { m in
    Leaf(name: "faded").opacity(m.opaque ? 0 : 1)
}, steps: [("opaque toggled", { m, _, _ in m.opaque.toggle() }),
           ("opaque toggled back", { m, _, _ in m.opaque.toggle() })])

arm("E5 zero-size frame and a clipped-out view: still appear?", { m in
    VStack {
        Leaf(name: "zero").frame(width: 0, height: 0)
        Leaf(name: "offscreen").offset(x: 5000)
    }.frame(width: 50, height: 50).clipped()
})

arm("D1 onDisappear reads its own @State; a write there; re-inserted content starts fresh", { m in
    if m.show { StateLeaf() }
}, steps: [("show = true", { m, _, _ in m.show = true }),
           ("show = false", { m, _, _ in m.show = false }),
           ("show = true again", { m, _, _ in m.show = true })])

arm("D2 a never-written @State default: onAppear and onDisappear see one instance across re-inits", { m in
    if m.show { MonLeaf(v: m.v) }
}, setup: { _ in monSerial = 0 },
   steps: [("show = true", { m, _, _ in m.show = true }),
           ("v = 1", { m, _, _ in m.v = 1 }),
           ("v = 2", { m, _, _ in m.v = 2 }),
           ("v = 3", { m, _, _ in m.v = 3 }),
           ("show = false", { m, _, _ in m.show = false })])

// ------------------------------------------------------------ S: scrolling
arm("S1 List(0..<200) rows in a 100 pt frame, scrolled to row 150 then back to 0", { m in
    ScrollViewReader { proxy in
        List(0..<200, id: \.self) { i in Leaf(name: "row\(i)") }
            .frame(width: 200, height: 100)
            .onChange(of: m.target) { _, t in log("(scrollTo \(t.map(String.init) ?? "nil"))"); if let t { proxy.scrollTo(t, anchor: .top) } }
    }
}, steps: [("scrollTo(150)", { m, _, _ in m.target = 150 }),
           ("scrollTo(0)", { m, _, _ in m.target = 0 }),
           ("AppKit scroll to y = 3000", { _, _, host in appKitScroll(host, to: 3000) }),
           ("AppKit scroll to y = 0", { _, _, host in appKitScroll(host, to: 0) })], spinAfterStep: 0.4)

arm("S2 ScrollView { LazyVStack } same", { m in
    ScrollViewReader { proxy in
        ScrollView { LazyVStack { ForEach(0..<200, id: \.self) { i in Leaf(name: "row\(i)").id(i) } } }
            .frame(width: 200, height: 100)
            .onChange(of: m.target) { _, t in log("(scrollTo \(t.map(String.init) ?? "nil"))"); if let t { proxy.scrollTo(t, anchor: .top) } }
    }
}, steps: [("scrollTo(150)", { m, _, _ in m.target = 150 }),
           ("scrollTo(0)", { m, _, _ in m.target = 0 }),
           ("AppKit scroll to y = 3000", { _, _, host in appKitScroll(host, to: 3000) }),
           ("AppKit scroll to y = 0", { _, _, host in appKitScroll(host, to: 0) })], spinAfterStep: 0.4)

arm("S3 separating: ScrollView { VStack } (not lazy) — 30 rows, scrolled", { m in
    ScrollViewReader { proxy in
        ScrollView { VStack { ForEach(0..<30, id: \.self) { i in Leaf(name: "row\(i)").id(i) } } }
            .frame(width: 200, height: 100)
            .onChange(of: m.target) { _, t in log("(scrollTo \(t.map(String.init) ?? "nil"))"); if let t { proxy.scrollTo(t, anchor: .top) } }
    }
}, steps: [("scrollTo(25)", { m, _, _ in m.target = 25 }),
           ("AppKit scroll to y = 500", { _, _, host in appKitScroll(host, to: 500) })], spinAfterStep: 0.4)

// ------------------------------------------------------------ T: transitions
arm("T0 control: removal with no animation", { m in
    if !m.flag { Leaf(name: "x").transition(.opacity) }
}, steps: [("flag = true (no animation)", { m, _, _ in m.flag = true })], spinAfterStep: 0.05)

arm("T1 removal under withAnimation(.linear(duration: 0.6)) with .transition(.opacity)", { m in
    if !m.flag { Leaf(name: "x").transition(.opacity) }
}, steps: [("withAnimation(0.6) { flag = true }", { m, _, _ in
               withAnimation(.linear(duration: 0.6)) { m.flag = true } }),
           ("spin 1.0 more", { _, _, _ in spin(1.0) })], spinAfterStep: 0.05)

arm("T2 insertion under withAnimation(.linear(duration: 0.6)) with .transition(.opacity)", { m in
    if m.flag { Leaf(name: "x").transition(.opacity) }
}, steps: [("withAnimation(0.6) { flag = true }", { m, _, _ in
               withAnimation(.linear(duration: 0.6)) { m.flag = true } })], spinAfterStep: 0.05)

arm("T3 onDisappear written OUTSIDE the transition: .transition(.opacity).onDisappear", { m in
    if !m.flag {
        Text("x").transition(.opacity).onAppear { log("appear x") }.onDisappear { log("disappear x (outer)") }
    }
}, steps: [("withAnimation(0.6) { flag = true }", { m, _, _ in
               withAnimation(.linear(duration: 0.6)) { m.flag = true } }),
           ("spin 1.0 more", { _, _, _ in spin(1.0) })], spinAfterStep: 0.05)

arm("T4 removal under a 0.6 s fade, re-inserted 0.2 s in", { m in
    if !m.flag { Leaf(name: "x").transition(.opacity) }
}, steps: [("withAnimation(0.6) { flag = true }", { m, _, _ in
               withAnimation(.linear(duration: 0.6)) { m.flag = true } }),
           ("spin 0.15, then withAnimation(0.6) { flag = false }", { m, _, _ in
               spin(0.15); withAnimation(.linear(duration: 0.6)) { m.flag = false } }),
           ("spin 1.0 more", { _, _, _ in spin(1.0) })], spinAfterStep: 0.05)

arm("T5 the parent of a fading child: parent removed under animation, child has no transition", { m in
    if !m.flag {
        VStack { Leaf(name: "child") }.transition(.opacity)
            .onAppear { log("appear parent") }.onDisappear { log("disappear parent") }
    }
}, steps: [("withAnimation(0.6) { flag = true }", { m, _, _ in
               withAnimation(.linear(duration: 0.6)) { m.flag = true } }),
           ("spin 1.0 more", { _, _, _ in spin(1.0) })], spinAfterStep: 0.05)

// ------------------------------------------------------------ W: window
arm("W1 window orderOut (hidden, not closed)", { _ in Leaf(name: "x") },
    steps: [("orderOut", { _, win, _ in win.orderOut(nil) }),
            ("orderFront", { _, win, _ in win.orderFrontRegardless() })])

arm("W2 window close()", { _ in Leaf(name: "x") },
    steps: [("close()", { _, win, _ in win.close() })])

arm("W3 contentView = nil (the hosting view leaves the window)", { _ in Leaf(name: "x") },
    steps: [("contentView = nil", { _, win, _ in win.contentView = nil })])

// ------------------------------------------------------------ K: task
arm("K1 .task: start relative to onAppear; cancelled when an `if` removes it", { m in
    if !m.flag {
        Text("x").onAppear { log("appear") }
            .task {
                log("task start")
                do { try await Task.sleep(for: .seconds(5)); log("task finished") }
                catch { log("task cancelled: \(Task.isCancelled)") }
            }
            .onDisappear { log("disappear") }
    }
}, steps: [("flag = true", { m, _, _ in m.flag = true })])

arm("K2 .task(id:): restarted when id changes", { m in
    Text("x").task(id: m.k) {
        let k = m.k
        log("task start k=\(k)")
        do { try await Task.sleep(for: .seconds(5)) } catch { log("task k=\(k) cancelled") }
    }
}, steps: [("k = 1", { m, _, _ in m.k = 1 })])
}
