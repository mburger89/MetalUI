// SwiftUI probe: GestureState and phaseAnimator (rulings GS-* in
// docs/superpowers/2026-10-21-gesture-state-decisions.md; spec
// docs/superpowers/specs/2026-10-21-gesture-state-design.md).
//
// HOW TO RUN (compiled form):
//
//   xcrun swiftc docs/probes/swiftui-gesture-state.swift -o /tmp/gs-probe && /tmp/gs-probe
//
// THE INSTRUMENT is `swiftui-input-followups.swift`'s: a key `NSWindow` hosting
// an `NSHostingView`, `NSEvent`s through `NSWindow.sendEvent`, a run-loop spin
// between events; every callback appends to one log (with seconds since the
// arm started where timing matters).
//
// ARMS AND THEIR CONTROLS.
//   G1 is the positive control (a drag with `.updating` into a counter: the
//   body must show the counter rise and reset); G2..G5b vary the recognizer
//   (does `updating` run for a tap, a long press that ends or fails, a drag
//   below its minimum, a spatial tap); G6/G7 two states on one gesture and one
//   state on two simultaneous gestures; G8 reads the state in onChanged and
//   onEnded and sets a resetTransaction; G9 the default reset's transaction;
//   G10 a transaction set inside `updating`; G11 the `reset:` closure.
//   P1..P9: `phaseAnimator`. P1 no trigger; P2 the control (one bump); P3 the
//   SEPARATING arm for P2 (no bump: nothing may run); P4 a bump mid-run;
//   P5 a nil animation for a phase; P6 a spring; P7/P8 one phase, equal
//   phases; P9 a one second animation, to see whether the step waits for it.
//
// RECORDED 2026-10-21 by the gesture-state designer, macOS 27.0.1, Apple Swift 6.4, Xcode-beta SDK, screen
// UNLOCKED (lock probe: no CGSSessionScreenIsLocked line, `displayAsleep main: 0`). Compiled form; the first run
// (before the arm tagging and the timestamps were added) agreed on every G line it shared and showed P-arm
// cross-talk from earlier windows' still-running animators, which the `L(arm, ...)` filter removed. Times are
// seconds since the arm's `Log.t0`; a P arm's `appear=` times are on an older clock and mean nothing.
//
// RESULT (stdout of the final run, verbatim):
//
//   --- G: GestureState
//       G1 drag updating, press/move/move/release: body s=1@0.0 | body s=2@0.2 | body s=3@0.3 | body s=0@0.5
//       G2 tap updating (does the body run?): -
//       G3 long press updating, released after 0.1 s (before 0.3): upd lp true@0.0 | body s=1@0.0 | body s=0@0.1
//       G4 long press updating, held 0.6 s (past 0.3) then released: upd lp true@0.0 | body s=1@0.0 | lp ended@0.3 | body s=0@0.3
//       G5 drag minimumDistance 10, moves 3 pt then 20 pt then release: upd | body s=1@0.3 | body s=0@0.5
//       G5b SpatialTap updating: -
//       G6 two states on one gesture: upd a | upd b | body a=1 b=10 | upd a | upd b | body a=2 b=20 | upd a | upd b | body a=3 b=30 | body a=0 b=0
//       G7 one state on drag + simultaneous long press: upd lp true@0.0 | upd drag@0.0 | body a=1@0.0 | upd drag@0.2 | body a=2@0.2 | body a=0@0.3
//       G7b long press ends (0.3 s) while held, then drag moves, release: upd lp true@0.0 | upd drag@0.0 | body a=1@0.0 | body a=0@0.3 | upd drag@0.5 | body a=1@0.5 | body a=0@0.8
//       G7c drag moves at once, release at 0.1 s before the long press could end: upd lp true@0.0 | upd drag@0.0 | body a=1@0.0 | upd drag@0.1 | body a=2@0.1 | body a=0@0.1
//       G7d drag writes, simultaneous long press's body does not write (drag declared first): upd lp noop | upd drag | body a=1@0.0 | upd drag | body a=2@0.2 | body a=0@0.3
//       G7e same, long press declared first: upd drag | upd lp noop | body a=0@0.0 | upd drag | body a=1@0.2 | body a=0@0.3
//       G12 long press (0.5 s) pressed, pointer leaves maximumDistance at 0.15 s, release at 0.5 s: upd lp@0.0 | body s=1@0.0 | body s=0@0.2
//       G13 onChanged declared before updating: which runs first, what does onChanged read: changed | upd | body s=1@0.0 | changed | upd | body s=2@0.2 | changed | upd | body s=3@0.3 | body s=0@0.5
//       G8 reads in callbacks, resetTransaction easeOut: upd (txAnim=false) | changed s=1 | body s=1@0.0 | tx@0.0 anim=false | upd (txAnim=false) | changed s=2 | body s=2@0.2 | tx@0.2 anim=false | upd (txAnim=false) | changed s=3 | body s=3@0.3 | tx@0.3 anim=false | ended s=0 | body s=0@0.5 | tx@0.5 anim=true
//       G9 default reset transaction: body s=1@0.0 | tx@0.0 anim=false | body s=2@0.2 | tx@0.2 anim=false | body s=3@0.3 | tx@0.3 anim=false | body s=0@0.5 | tx@0.5 anim=false
//       G10 transaction set in updating body: body s=1@0.0 | tx@0.0 anim=true | body s=2@0.2 | tx@0.2 anim=true | body s=3@0.3 | tx@0.3 anim=true | body s=0@0.5 | tx@0.5 anim=false
//       G11 reset(_:_:) closure: body s=1@0.0 | tx@0.0 anim=false | body s=2@0.2 | tx@0.2 anim=false | body s=3@0.3 | tx@0.3 anim=false | reset closure v=3 | body s=0@0.5 | tx@0.5 anim=true
//   --- P: phaseAnimator (phases [0,1,2], animation linear 0.4 s unless noted)
//       P1 no trigger, 3.0 s: c0@0.0 | a1@0.0 | c1@0.0 | tx1 anim=true | a2@0.4 | c2@0.4 | tx2 anim=true | a0@0.8 | c0@0.8 | tx0 anim=true | a1@1.2 | c1@1.2 | tx1 anim=true | a2@1.6 | c2@1.6 | tx2 anim=true | a0@2.0 | c0@2.0 | tx0 anim=true | a1@2.4 | c1@2.4 | tx1 anim=true | a2@2.8 | c2@2.8 | tx2 anim=true
//       P2 trigger bumped once: appear=c0@3.0 | c0@3.0 then=a1@0.0 | c1@0.0 | tx1 anim=true | a2@0.4 | c2@0.4 | tx2 anim=true | a0@0.8 | c0@0.8 | tx0 anim=true | c0@1.2
//       P3 no change: appear=c0@2.5 | c0@2.5 then=-
//       P4 trigger bumped mid-run (after 0.5 s): appear=c0@1.0 | c0@1.0 then=a1@0.0 | c1@0.0 | tx1 anim=true | a2@0.4 | c2@0.4 | tx2 anim=true | a1@0.5 | c1@0.5 | tx1 anim=true | c1@0.8 | a2@0.9 | c2@0.9 | tx2 anim=true | a0@1.3 | c0@1.3 | tx0 anim=true | c0@1.7
//       P5 animation nil for phase 1, linear 0.4 else: appear=c0@3.5 | c0@3.5 then=a1@0.0 | c1@0.0 | tx1 anim=false | a2@0.0 | c2@0.0 | tx2 anim=true | a0@0.4 | c0@0.4 | tx0 anim=true | c0@0.8
//       P6 spring animation: appear=c0@2.0 | c0@2.0 then=a1@0.0 | c1@0.0 | tx1 anim=true | a2@0.5 | c2@0.5 | tx2 anim=true | a0@1.0 | c0@1.0 | tx0 anim=true | c0@1.5
//       P7 single phase: appear=c0@3.0 | c0@3.0 then=c0@0.0
//       P8 empty-ish: two equal phases [0,0]: appear=c0@1.5 | c0@1.5 then=a0@0.0 | c0@0.0 | a0@0.0 | c0@0.0 | c0@0.0
//       P9 linear 1.0 s (does the step wait for the duration?): appear=c0@2.0 | c0@2.0 then=a1@0.0 | c1@0.0 | tx1 anim=true | a2@1.0 | c2@1.0 | tx2 anim=true | a0@2.0 | c0@2.0 | tx0 anim=true | c0@3.0
//       P10 content independent of the phase, linear 0.4: -
//   --- R: Reduce Motion is an OS setting an agent cannot flip: NOT MEASURED for phaseAnimator
//
// READING.
//   G1 control: the state rises with each update and is 0 again in the body of the RELEASE event.
//   G2, G5b: `updating` on a TapGesture / SpatialTapGesture compiles and NEVER runs (no body line at all).
//   G3, G4, G12: a long press's `updating` runs once, at the press, with `true`; the reset comes at the moment the
//   gesture ENDS (G4: 0.3 s, while still held) or FAILS (G3: release before the minimum; G12: the pointer left
//   `maximumDistance` at 0.15 s, reset at 0.2 s, long before the release at 0.5 s).
//   G5: updating starts with the first recognized change (past `minimumDistance`), as `onChanged` does.
//   G6: two `updating` on one gesture run in declaration order, one body per event, both visible.
//   G7..G7e: ONE slot per GestureState. Every `updating` body of an event starts from the value committed BEFORE the
//   event (G7: the drag's `+= 1` read 0 although the long press had written 100 a moment earlier), a body that does
//   not touch its inout state still writes the copy back (G7e: the no-op long press, run last, left 0), the last body
//   run wins, and the LAST-DECLARED member of a `simultaneously(with:)` runs FIRST (G7, G7d: lp before drag). Any
//   writer ending resets the whole slot (G7b: 0.3 s, the long press ending while the drag still holds; G7c: the
//   drag's release at 0.1 s).
//   G8: the write is visible to `onChanged` declared AFTER the `updating` (`changed s=1` before the body's `s=1`);
//   the reset is applied BEFORE `onEnded` (`ended s=0`). G13: callbacks run in DECLARATION order (`.onChanged`
//   before `.updating` runs `changed` first).
//   G8, G9, G10, G11: the update's transaction has no animation unless the `updating` body sets one (G10: every update
//   carries it, the reset does not); the reset's transaction is `resetTransaction` (G8: animation true at the reset),
//   or the one the `reset:` closure writes (G11, the closure runs once at the reset with the value before it, v=3),
//   and by default has none (G9).
//   Earlier probe `swiftui-input-followups.swift` C2/C3 (cancel by disabling or removing, reset at the NEXT event) and
//   C4/C5 stand.
//   P1: a phaseAnimator with no trigger shows `phases[0]` at appear, then at once (0.0 s) steps to `phases[1]`, and
//   cycles 1, 2, 0, 1, ... forever, one step every 0.4 s = the duration of the animation the step uses. P2: with a
//   trigger, a change at 0 s runs phases 1, 2, then 0 (the first, with `animation(0)` called) at 0.0, 0.4, 0.8 s and
//   ends with one more content call at 1.2 s (no animation call); P3 (separating): no change, nothing runs. P4: a
//   change mid-run restarts at once from `phases[1]` (a1@0.5) and runs to the end. P5: a nil animation snaps its phase
//   (tx1 anim=false) and the next step follows at the same instant. P6: a spring step lasts the spring's `duration`
//   parameter (0.5). P9: a 1.0 s animation spaces steps 1.0 s apart. P7: one phase, a trigger change calls the
//   content once, no animation. P8: equal neighbouring phases step with no wait. P10: content that ignores its phase
//   was never called again (unexplained, not relied on). Every phase's content is built under a transaction whose
//   animation is `animation(phase)`: `tx<p> anim=true`.
//   R: Reduce Motion: `accessibilityReduceMotion` is read-only in SwiftUI (`.environment(\.accessibilityReduceMotion,
//   true)` does not typecheck: KeyPath, not WritableKeyPath) and the system setting is not flipped by an agent: NOT
//   MEASURED for phaseAnimator.
//   Interface census (SwiftUI.swiftinterface): GestureState has init(wrappedValue:), init(initialValue:),
//   init(wrappedValue:resetTransaction:), init(initialValue:resetTransaction:), init(wrappedValue:reset:),
//   init(initialValue:reset:), plus `where Value: ExpressibleByNilLiteral` init(resetTransaction:), init(reset:);
//   `wrappedValue` get-only, `projectedValue` is the GestureState itself; `Gesture.updating(_:body:)` returns
//   `GestureStateGesture<Self, State>`; PhaseAnimator<Phase, Content>.init(_:trigger:content:animation:) and
//   init(_:content:animation:), `View.phaseAnimator(_:trigger:content:animation:)` and `(_:content:animation:)`,
//   content receiving `PlaceholderContentView<Self>` and the Phase, `animation` defaulting to `{ _ in .default }`.
//
import SwiftUI
import AppKit

final class FirstMouseHost<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

nonisolated(unsafe) var currentArm = 0
func L(_ arm: Int, _ s: String) { if arm == currentArm { Log.add(s) } }

enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    static func add(_ s: String) { lines.append(s) }
    nonisolated(unsafe) static var t0 = Date()
    static func ts() -> String { String(format: "%.1f", Date().timeIntervalSince(t0)) }
    static func take() -> String {
        defer { lines = [] }
        return lines.isEmpty ? "-" : lines.joined(separator: " | ")
    }
}

@MainActor func spin(_ s: Double = 0.15) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

let side: CGFloat = 200

final class KeyWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var canBecomeKey: Bool { true }
}

@MainActor func makeWindow<V: View>(_ view: V) -> NSWindow {
    let w = KeyWindow(contentRect: CGRect(x: 200, y: 200, width: side, height: side),
                      styleMask: [.titled], backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    w.contentView = FirstMouseHost(rootView: view)
    w.makeKeyAndOrderFront(nil)
    spin(0.6)
    return w
}

func wp(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: side - y) }

@MainActor func mouse(_ w: NSWindow, _ t: NSEvent.EventType, _ pt: CGPoint, flags: NSEvent.ModifierFlags = [],
                      clicks: Int = 1) {
    let e = NSEvent.mouseEvent(with: t, location: pt, modifierFlags: flags,
                               timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: w.windowNumber, context: nil, eventNumber: 0,
                               clickCount: clicks, pressure: t == .leftMouseUp ? 0 : 1)!
    w.sendEvent(e)
}

@MainActor func flags(_ w: NSWindow, _ f: NSEvent.ModifierFlags, key: UInt16) {
    let e = NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: f,
                             timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber,
                             context: nil, characters: "", charactersIgnoringModifiers: "",
                             isARepeat: false, keyCode: key)!
    if viaApp { NSApp.sendEvent(e) } else { w.sendEvent(e) }
    spin(0.15)
}
nonisolated(unsafe) var viaApp = false

func name(_ m: EventModifiers) -> String {
    var parts: [String] = []
    if m.contains(.shift) { parts.append("shift") }
    if m.contains(.command) { parts.append("command") }
    if m.contains(.option) { parts.append("option") }
    if m.contains(.control) { parts.append("control") }
    return parts.isEmpty ? "[]" : "[" + parts.joined(separator: ",") + "]"
}


// MARK: - G: GestureState

struct GView<G: Gesture>: View {
    @GestureState var s: Int
    let make: (GestureState<Int>) -> G
    let initial: Int
    var body: some View {
        let _ = Log.add("body s=\(s)@\(Log.ts())")
        Color.orange.frame(width: side, height: side).gesture(make($s))
    }
}

// Two states, one gesture; one state, two gestures.
struct TwoStates: View {
    @GestureState var a = 0
    @GestureState var b = 0
    var body: some View {
        let _ = Log.add("body a=\(a) b=\(b)")
        Color.orange.frame(width: side, height: side).gesture(
            DragGesture(minimumDistance: 0)
                .updating($a) { _, st, _ in st += 1; Log.add("upd a") }
                .updating($b) { _, st, _ in st += 10; Log.add("upd b") })
    }
}
struct NoopShared: View {
    @GestureState var a = 0
    let dragFirst: Bool
    var body: some View {
        let _ = Log.add("body a=\(a)@\(Log.ts())")
        let drag = DragGesture(minimumDistance: 0).updating($a) { _, st, _ in st += 1; Log.add("upd drag") }
        let lp = LongPressGesture(minimumDuration: 5, maximumDistance: 100).updating($a) { _, st, _ in Log.add("upd lp noop") }
        Color.orange.frame(width: side, height: side).gesture(dragFirst ? AnyGesture(drag.simultaneously(with: lp).map { _ in () }) : AnyGesture(lp.simultaneously(with: drag).map { _ in () }))
    }
}
struct SharedState: View {
    @GestureState var a = 0
    var body: some View {
        let _ = Log.add("body a=\(a)@\(Log.ts())")
        Color.orange.frame(width: side, height: side).gesture(
            DragGesture(minimumDistance: 0).updating($a) { _, st, _ in st += 1; Log.add("upd drag@\(Log.ts())") }
                .simultaneously(with: LongPressGesture(minimumDuration: 0.3, maximumDistance: 100)
                    .updating($a) { v, st, _ in st += 100; Log.add("upd lp \(v)@\(Log.ts())") }))
    }
}
// Reads in the callbacks: live value at onEnded, and resetTransaction.
struct ReadsView: View {
    @GestureState(resetTransaction: Transaction(animation: .easeOut(duration: 0.3))) var s = 0
    var body: some View {
        let _ = Log.add("body s=\(s)@\(Log.ts())")
        Color.orange.opacity(1 - Double(s) / 20).frame(width: side, height: side)
            .transaction { t in Log.add("tx@\(Log.ts()) anim=\(t.animation != nil)") }
            .gesture(DragGesture(minimumDistance: 0)
                .updating($s) { _, st, t in st += 1; Log.add("upd (txAnim=\(t.animation != nil))") }
                .onChanged { _ in Log.add("changed s=\(s)") }
                .onEnded { _ in Log.add("ended s=\(s)") })
    }
}
struct PlainResetView: View {
    @GestureState var s = 0
    var body: some View {
        let _ = Log.add("body s=\(s)@\(Log.ts())")
        Color.orange.opacity(1 - Double(s) / 20).frame(width: side, height: side)
            .transaction { t in Log.add("tx@\(Log.ts()) anim=\(t.animation != nil)") }
            .gesture(DragGesture(minimumDistance: 0).updating($s) { _, st, _ in st += 1 })
    }
}
struct UpdatingTxView: View {
    @GestureState var s = 0
    var body: some View {
        let _ = Log.add("body s=\(s)@\(Log.ts())")
        Color.orange.opacity(1 - Double(s) / 20).frame(width: side, height: side)
            .transaction { t in Log.add("tx@\(Log.ts()) anim=\(t.animation != nil)") }
            .gesture(DragGesture(minimumDistance: 0).updating($s) { _, st, t in st += 1; t.animation = .linear(duration: 1) })
    }
}
struct ResetClosureView: View {
    @GestureState(reset: { v, t in Log.add("reset closure v=\(v)"); t.animation = .linear(duration: 1) }) var s = 0
    var body: some View {
        let _ = Log.add("body s=\(s)@\(Log.ts())")
        Color.orange.opacity(1 - Double(s) / 20).frame(width: side, height: side)
            .transaction { t in Log.add("tx@\(Log.ts()) anim=\(t.animation != nil)") }
            .gesture(DragGesture(minimumDistance: 0).updating($s) { _, st, _ in st += 1 })
    }
}
// The reset's @State write count: a counter bumped by onChanged of a second state.
@MainActor func gArm<G: Gesture>(_ label: String, _ make: @escaping (GestureState<Int>) -> G,
                                 _ steps: (NSWindow) -> Void) {
    let w = makeWindow(GView(s: 0, make: make, initial: 0))
    _ = Log.take(); Log.t0 = Date()
    steps(w)
    print("    \(label): \(Log.take())")
    w.close()
}
@MainActor func viewArm<V: View>(_ label: String, _ v: V, _ steps: (NSWindow) -> Void) {
    let w = makeWindow(v)
    _ = Log.take(); Log.t0 = Date()
    steps(w)
    print("    \(label): \(Log.take())")
    w.close()
}
@MainActor func pressMoveRelease(_ w: NSWindow) {
    mouse(w, .leftMouseDown, wp(50, 50)); spin(0.15)
    mouse(w, .leftMouseDragged, wp(70, 60)); spin(0.15)
    mouse(w, .leftMouseDragged, wp(80, 60)); spin(0.15)
    mouse(w, .leftMouseUp, wp(80, 60)); spin(0.3)
}

// MARK: - P: phaseAnimator

struct PhNoTrigger: View {
    let arm = currentArm
    var body: some View {
        Color.red.frame(width: side, height: side)
            .phaseAnimator([0, 1, 2]) { c, p in
                let _ = L(arm, "c\(p)@\(Log.ts())")
                c.opacity(p == 0 ? 1 : p == 1 ? 0.5 : 0.2)
                    .transaction { t in L(arm, "tx\(p) anim=\(t.animation != nil)") }
            } animation: { p in
                L(arm, "a\(p)@\(Log.ts())")
                return .linear(duration: 0.4)
            }
    }
}
final class TModel: ObservableObject { @Published var t = 0 }
struct PhTrigger: View {
    let arm = currentArm
    @ObservedObject var m: TModel
    var phases: [Int] = [0, 1, 2]
    var anim: (Int) -> Animation? = { _ in .linear(duration: 0.4) }
    var body: some View {
        Color.red.frame(width: side, height: side)
            .phaseAnimator(phases, trigger: m.t) { c, p in
                let _ = L(arm, "c\(p)@\(Log.ts())")
                c.opacity(p == 0 ? 1 : p == 1 ? 0.5 : 0.2)
                    .transaction { t in L(arm, "tx\(p) anim=\(t.animation != nil)") }
            } animation: { p in
                L(arm, "a\(p)@\(Log.ts())")
                return anim(p)
            }
    }
}
struct PhConstant: View {
    @ObservedObject var m: TModel
    let arm = currentArm
    var body: some View {
        Color.red.frame(width: side, height: side)
            .phaseAnimator([0, 1, 2], trigger: m.t) { c, p in
                let _ = L(arm, "c\(p)@\(Log.ts())")
                c   // the content does not depend on the phase
            } animation: { p in
                L(arm, "a\(p)@\(Log.ts())")
                return .linear(duration: 0.4)
            }
    }
}
struct PhReduce: View {
    var body: some View {
        Color.red.frame(width: side, height: side)
            .phaseAnimator([0, 1], trigger: 0) { c, p in
                let _ = Log.add("c\(p)@\(Log.ts())")
                c.opacity(p == 0 ? 1 : 0.5)
            } animation: { p in .linear(duration: 0.4) }
            .transformEnvironment(\.self) { _ in }
    }
}
@MainActor func phArm(_ label: String, wait: Double, anim: @escaping (Int) -> Animation? = { _ in .linear(duration: 0.4) },
                      phases: [Int] = [0, 1, 2], steps: (TModel) -> Void) {
    currentArm += 1
    let m = TModel()
    let w = makeWindow(PhTrigger(m: m, phases: phases, anim: anim))
    Log.t0 = Date()
    let appear = Log.take()
    steps(m)
    spin(wait)
    print("    \(label): appear=\(appear) then=\(Log.take())")
    w.close()
}

@MainActor func run() {
  _ = NSApplication.shared
  NSApp.setActivationPolicy(.regular)
  NSApp.activate(ignoringOtherApps: true)
  spin(0.5)
  print("--- G: GestureState")
  gArm("G1 drag updating, press/move/move/release", { s in DragGesture(minimumDistance: 0).updating(s) { _, st, _ in st += 1 } }, pressMoveRelease)
  gArm("G2 tap updating (does the body run?)", { s in TapGesture().updating(s) { _, st, _ in st += 1; Log.add("upd tap") } }) { w in
      mouse(w, .leftMouseDown, wp(50, 50)); spin(0.15); mouse(w, .leftMouseUp, wp(50, 50)); spin(0.5)
  }
  gArm("G3 long press updating, released after 0.1 s (before 0.3)", { s in LongPressGesture(minimumDuration: 0.3).updating(s) { v, st, _ in st = v ? 1 : 0; Log.add("upd lp \(v)@\(Log.ts())") } }) { w in
      mouse(w, .leftMouseDown, wp(50, 50)); spin(0.1); mouse(w, .leftMouseUp, wp(50, 50)); spin(0.5)
  }
  gArm("G4 long press updating, held 0.6 s (past 0.3) then released", { s in LongPressGesture(minimumDuration: 0.3).updating(s) { v, st, _ in st = v ? 1 : 0; Log.add("upd lp \(v)@\(Log.ts())") }.onEnded { _ in Log.add("lp ended@\(Log.ts())") } }) { w in
      mouse(w, .leftMouseDown, wp(50, 50)); spin(0.6); mouse(w, .leftMouseUp, wp(50, 50)); spin(0.5)
  }
  gArm("G5 drag minimumDistance 10, moves 3 pt then 20 pt then release", { s in DragGesture(minimumDistance: 10).updating(s) { _, st, _ in st += 1; Log.add("upd") } }) { w in
      mouse(w, .leftMouseDown, wp(50, 50)); spin(0.15); mouse(w, .leftMouseDragged, wp(53, 50)); spin(0.15)
      mouse(w, .leftMouseDragged, wp(70, 50)); spin(0.15); mouse(w, .leftMouseUp, wp(70, 50)); spin(0.3)
  }
  gArm("G5b SpatialTap updating", { s in SpatialTapGesture().updating(s) { _, st, _ in st += 1; Log.add("upd spatial") } }) { w in
      mouse(w, .leftMouseDown, wp(50, 50)); spin(0.15); mouse(w, .leftMouseUp, wp(50, 50)); spin(0.5)
  }
  viewArm("G6 two states on one gesture", TwoStates(), pressMoveRelease)
  viewArm("G7 one state on drag + simultaneous long press", SharedState()) { w in
      mouse(w, .leftMouseDown, wp(50, 50)); spin(0.15); mouse(w, .leftMouseDragged, wp(55, 50)); spin(0.5)
      mouse(w, .leftMouseUp, wp(55, 50)); spin(0.3)
  }
  viewArm("G7b long press ends (0.3 s) while held, then drag moves, release", SharedState()) { w in
      mouse(w, .leftMouseDown, wp(50, 50)); spin(0.5); mouse(w, .leftMouseDragged, wp(55, 50)); spin(0.3)
      mouse(w, .leftMouseUp, wp(55, 50)); spin(0.3)
  }
  viewArm("G7c drag moves at once, release at 0.1 s before the long press could end", SharedState()) { w in
      mouse(w, .leftMouseDown, wp(50, 50)); spin(0.05); mouse(w, .leftMouseDragged, wp(55, 50)); spin(0.05)
      mouse(w, .leftMouseUp, wp(55, 50)); spin(0.6)
  }
  viewArm("G7d drag writes, simultaneous long press's body does not write (drag declared first)", NoopShared(dragFirst: true)) { w in
      mouse(w, .leftMouseDown, wp(50, 50)); spin(0.15); mouse(w, .leftMouseDragged, wp(55, 50)); spin(0.15)
      mouse(w, .leftMouseUp, wp(55, 50)); spin(0.3)
  }
  viewArm("G7e same, long press declared first", NoopShared(dragFirst: false)) { w in
      mouse(w, .leftMouseDown, wp(50, 50)); spin(0.15); mouse(w, .leftMouseDragged, wp(55, 50)); spin(0.15)
      mouse(w, .leftMouseUp, wp(55, 50)); spin(0.3)
  }
  gArm("G12 long press (0.5 s) pressed, pointer leaves maximumDistance at 0.15 s, release at 0.5 s", { s in LongPressGesture(minimumDuration: 0.5, maximumDistance: 10).updating(s) { v, st, _ in st = 1; Log.add("upd lp@\(Log.ts())") } }) { w in
      mouse(w, .leftMouseDown, wp(50, 50)); spin(0.15); mouse(w, .leftMouseDragged, wp(120, 50)); spin(0.35)
      mouse(w, .leftMouseUp, wp(120, 50)); spin(0.3)
  }
  gArm("G13 onChanged declared before updating: which runs first, what does onChanged read", { s in DragGesture(minimumDistance: 0).onChanged { _ in Log.add("changed") }.updating(s) { _, st, _ in st += 1; Log.add("upd") } }, pressMoveRelease)
  viewArm("G8 reads in callbacks, resetTransaction easeOut", ReadsView(), pressMoveRelease)
  viewArm("G9 default reset transaction", PlainResetView(), pressMoveRelease)
  viewArm("G10 transaction set in updating body", UpdatingTxView(), pressMoveRelease)
  viewArm("G11 reset(_:_:) closure", ResetClosureView(), pressMoveRelease)
  print("--- P: phaseAnimator (phases [0,1,2], animation linear 0.4 s unless noted)")
  do {
    currentArm += 1; Log.t0 = Date(); _ = Log.take(); let w = makeWindow(PhNoTrigger()); spin(2.4)
    print("    P1 no trigger, 3.0 s: \(Log.take())"); w.close()
  }
  phArm("P2 trigger bumped once", wait: 2.5) { m in m.t += 1 }
  phArm("P3 no change", wait: 1.0) { _ in }
  phArm("P4 trigger bumped mid-run (after 0.5 s)", wait: 3.0) { m in m.t += 1; spin(0.5); m.t += 1 }
  phArm("P5 animation nil for phase 1, linear 0.4 else", wait: 2.0, anim: { $0 == 1 ? nil : .linear(duration: 0.4) }) { m in m.t += 1 }
  phArm("P6 spring animation", wait: 3.0, anim: { _ in .spring(duration: 0.5, bounce: 0) }) { m in m.t += 1 }
  phArm("P7 single phase", wait: 1.5, phases: [0]) { m in m.t += 1 }
  phArm("P8 empty-ish: two equal phases [0,0]", wait: 2.0, phases: [0, 0]) { m in m.t += 1 }
  phArm("P9 linear 1.0 s (does the step wait for the duration?)", wait: 4.0, anim: { _ in .linear(duration: 1.0) }) { m in m.t += 1 }
  do {
    currentArm += 1
    let m = TModel(); let w = makeWindow(PhConstant(m: m)); Log.t0 = Date(); _ = Log.take()
    m.t += 1; spin(2.0)
    print("    P10 content independent of the phase, linear 0.4: \(Log.take())"); w.close()
  }
  print("--- R: Reduce Motion is an OS setting an agent cannot flip: NOT MEASURED for phaseAnimator")
}
MainActor.assumeIsolated { run() }
