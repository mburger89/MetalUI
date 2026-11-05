// SwiftUI probe: which view holds focus on a hosting view's first draw, with no input (round 4 item R4-4 PR C;
// divergence 186, rulings `FC-` in docs/superpowers/2026-11-04-focus-click-and-seat-decisions.md). It also
// reads what happens when the focused view is removed (new divergence 217) and what T1 of
// `swiftui-focus-click.swift` ("a lone `.focusable()` takes focus from any click") really is.
//
// HOW TO RUN (SA-O's compiled form; no JIT shim):
//
//   xcrun swiftc -swift-version 6 docs/probes/swiftui-initial-focus.swift -o /tmp/if-probe
//   /tmp/if-probe > /tmp/if-1.txt; /tmp/if-probe > /tmp/if-2.txt; cmp /tmp/if-1.txt /tmp/if-2.txt
//
// INSTRUMENT. `swiftui-focus-click.swift`'s: a `FirstMouseHost` (an `NSHostingView`) in a `KeyWindow`, laid out
// and shown before the first event, a run-loop spin of 0.3 s after `makeKeyAndOrderFront`. The line `settled`
// is logged AFTER that spin and BEFORE any event: whatever is logged before it is the seat. `f=<v>` is a flip
// of a `@FocusState<Int?>` (`f=nil` is a clear), `a=` / `b=` flips of `@FocusState<Bool>`. The window is
// 200 x 200 with the origin at the BOTTOM left. The arm ids follow the plan (`I..`, `LF..`, `G..`, `C8a/b`,
// `D..`, `L..`); the plan's first session was run through `swift -` and never committed, so the arm bodies are
// rebuilt from the plan's table. Mutations of the tree after show go through the `ctl` object, which an arm
// flips with the window already settled.
//
// RECORDED 2026-11-04, macOS 27.2, Apple Swift 6.4.2 (swiftlang-6.4.2.1.9), screen LOCKED
// (`CGSSessionScreenIsLocked = Yes`; the events go into the probe's own window through `NSWindow.sendEvent` and an
// `NSHostingView` is laid out before show, so the lock does not matter), Full Keyboard Access off. Compiled form,
// run three times: stdout byte-identical, exit 0, stderr empty.
//
// stdout byte-identical (64 lines, shasum dab329f74cd0cf927bc02de87f617fd619826eef):
//
//   --- I: what seats on the first draw
//     I0 lone .focusable(), key window: f=0,settled
//     I0n lone .focusable(), window NOT key: f=0,settled
//     LF7 [Button]: settled
//     I1 [Button, focusable]: f=1,settled
//     I6a [Toggle, focusable]: f=1,settled
//     I6b [Slider, focusable]: f=1,settled
//     I6c [Picker, focusable]: f=1,settled
//     I7 [.activate, focusable]: f=1,settled
//     I9 [focusable(false), focusable]: f=1,settled
//     I11 [hidden, focusable]: f=1,settled
//     LF9 [disabled, focusable]: f=1,settled
//     I8 [.edit, focusable]: f=0,settled
//     I26 [allowsHitTesting(false) focusable, focusable]: f=0,settled
//     I13 [List(selection), focusable]: settled,fr=SwiftUI.SwiftUIOutlineListView,fr=SwiftUI.SwiftUIOutlineListView
//     I14 [List, focusable]: settled,fr=SwiftUI.SwiftUIOutlineListView,fr=SwiftUI.SwiftUIOutlineListView
//   --- G: scrollers and order
//     G5 [ScrollView{focusable}]: f=0,settled
//     G6 [List{focusable row}]: settled,fr=SwiftUI.SwiftUIOutlineListView,fr=SwiftUI.SwiftUIOutlineListView
//     G7 [ScrollView{focusable}, focusable outside]: f=0,settled
//     G5o [ScrollView{focusable 400 tall} overflowing]: f=0,settled
//     G7o [ScrollView{overflowing focusable}, focusable outside]: f=0,settled
//     G5h [ScrollView(.horizontal){focusable}]: f=0,settled
//     G5v [ScrollView{VStack{Text.focusable}}]: f=0,settled
//     G5t [ScrollView{Text.focusable}], window 400 tall: f=0,settled
//     G7s [focusable above, ScrollView{focusable} below]: f=1,settled
//     G7t [ScrollView{focusable} above, focusable below]: f=0,settled
//     I13b [focusable, List]: f=0,settled,fr=SwiftUI.KeyViewProxy,fr=SwiftUI.KeyViewProxy
//     G8 [LazyVStack{focusable}] (no scroller): f=0,settled
//     G8b [ScrollView{LazyVStack{focusable}}]: f=0,settled
//     G1 [A offset down 100, B]: B is higher but later in tree order: f=1,settled
//     G2 [A positioned at y 150, B positioned at y 40]: f=1,settled
//     G3 [A, B] side by side, same top: f=0,settled
//     G4 [A, B] stacked in a ZStack, same top: f=0,settled
//     G4b [B(1) later in tree but A(0) lower, equal top via VStack alignment]: f=0,settled
//   --- C8: nested focusables (outer 0, inner 1, sibling 2)
//     C8a [outer{inner}]: f=0,settled
//     C8b [sibling 2 earlier, same top; outer{inner}]: f=2,settled
//     C8c [sibling 2 earlier, higher; outer{inner}] below it: f=2,settled
//   --- I20 / D: writes and defaultFocus
//     I20 onAppear writes f=1 over [0, 1]: f=1,settled
//     I18 defaultFocus(f, 1) over [0, 1]: f=0,settled
//     I21 defaultFocus(f, 1, priority: .userInitiated): f=0,settled
//   --- L: lifecycle
//     L1 focusable inserted after show: settled,|insert
//     L3 cleared from code after the seat (tick), then settle: f=0,settled,|clear,f=nil
//     L2 focused first removed, 1 and 2 exist: f=0,settled,|remove,f=1
//     L4 same, then a new focusable inserted (9) in the same change: f=0,settled,|remove+insert,f=1
//     L5 focused removed and a new focusable inserted ABOVE all (8) in the same change: f=0,settled,|remove+insertTop,f=1
//     L6 focused TextField (f=0, seeded by onAppear) removed: f=0,settled,fr=_TtC7SwiftUIP33_C58093E7172B0A541A997680E343D0D527_SystemTextFieldFieldEditor,|remove,fr=main.KeyWindow
//   --- LF: TextFields (hosting view laid out before show)
//     LF1 [TF]: f=0,settled
//     LF2 [TF, TF]: f=0,settled
//     LF5 [focusable, TF]: f=0,settled
//     LF5b [TF, focusable]: f=0,settled
//   --- T1: what the earlier probe's T1 is (read each against `settled`)
//     T1s lone .focusable() 50 x 50, no event at all: a=true,settled
//     T1k lone .focusable() 50 x 50, first event is a KEY (Tab), not a click: a=true,settled,|tab
//     T1 lone .focusable() 50 x 50, click OUTSIDE it: a=true,settled,|click
//     T1c lone .focusable(), RIGHT press: a=true,settled,|rclick
//     T1g lone .focusable() INSERTED AFTER show (not seated, L1), click OUTSIDE it: settled,|insert,|click
//     T1h same, click ON it: settled,|insert,|click,a=true
//     T1i same, RIGHT press OUTSIDE it: settled,|insert,|rclick
//     T1j window not key, lone .focusable() 50 x 50, click OUTSIDE it: a=true,settled,|click
//
// WHAT T1 IS (`swiftui-focus-click.swift`'s instrument trap: "a lone `.focusable()` takes focus from any click that
// lands in the window"). IT IS THE FIRST-DRAW SEAT, NOT THE CLICK. `T1s` reads `a=true` before `settled` (that is, during the
// settling spin and before any event); `T1k` (a Tab as the first event) adds nothing; `T1`, `T1c` and `T1j` (a click
// outside, a right press, a non-key window) log no flip after their event because the focus was already there. The
// proof is the separating arm `T1g`/`T1i`: the same lone focusable INSERTED AFTER SHOW is not seated (`L1`), and a click
// OUTSIDE it (`T1g`) or a right press outside it (`T1i`) takes no focus; only a click ON it does (`T1h`). So a click
// that misses a focusable takes no focus, and PR B's negative rows (read against a seeded second focusable) were right.
//
// READING AGAINST THE PLAN (r4-4-plan.md "Row 186"). Agrees: `I0n` (no key dependency), `LF7`, `I1`, `I6a`..`I6c`,
// `I7`, `I9`, `I11`, `LF9`, `I8` (`.edit` is seated), `I26`, `G1`..`G4` (topmost by final position, ties in tree order),
// `G8`, `I20` (the appear write wins: the log shows `f=1` only, where the plan's session logged `f=a,f=b`; the final
// value agrees), `I18`/`I21` (`defaultFocus` has no effect in a hosting view), `L1`, `L3`, `L2`/`L4`/`L5` (a removed
// focused `.focusable()` moves focus to the EXISTING `1`, never to a newly inserted one, even one inserted above it),
// `LF1`/`LF2` (the first field takes focus in a laid-out hosting view), `LF5` (`focusable, TextField` seats the
// focusable).
// DIFFERS from the plan:
//   * `G5`, `G7`: a focusable inside a `ScrollView` IS seated (`G5`, `G5o`, `G5h`, `G5v`, `G5t`; with a second
//     focusable outside, the one in the scroller still wins when it is first or higher, `G7`, `G7o`, `G7t`, and loses
//     only when the outside one is higher, `G7s`), whatever the content size or axis. The plan read these as "not
//     seated". Only a `List` is different (`G6`: its rows are not seated).
//   * `I13`, `I14`, `G6`: a `List` earlier in the tree HOLDS the first responder itself (`SwiftUIOutlineListView`),
//     so a focusable AFTER it is not seated either (`I13`, `I14` read no flip at all); the plan read "List skipped".
//     A focusable BEFORE the list is seated (`I13b`).
//   * `C8b`: a top-aligned earlier sibling beats the outer of a nested pair (`f=2`), as `G3`'s tie rule says; the plan's
//     "the outer wins, even over an earlier sibling" is not reproduced here. `C8a` (the outer over its own inner) and
//     `C8c` (a higher earlier sibling) agree with topmost-by-position.
//   * `LF5b`: `[TextField, focusable]` seats the TextField (`f=0`) in a laid-out hosting view; the plan recorded the
//     focusable only for a real locked `WindowGroup`. MetalUI seats neither field (the 2026-11-04 decision).
//   * `L6`: a removed focused `TextField` leaves the first responder on the window (`fr=main.KeyWindow`) but the
//     `@FocusState` flip back to `nil` is not logged within the run (the plan read `nil`).
// NOT MEASURED: an unlocked real `WindowGroup`, a truly key window (inferred), and any `NSHostingView` that is not
// laid out before show.

import SwiftUI
import AppKit

final class FirstMouseHost<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class KeyWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var canBecomeKey: Bool { true }
}

final class NotKeyWindow: NSWindow {
    override var isKeyWindow: Bool { false }
    override var canBecomeKey: Bool { false }
}

enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    static func add(_ s: String) { lines.append(s) }
    static func take() -> String {
        defer { lines = [] }
        return lines.isEmpty ? "-" : lines.joined(separator: ",")
    }
}

@Observable @MainActor final class Ctl {
    var shown = true
    var extra = false
    var tick = 0
    var top = false
}
enum Shared { @MainActor static let ctl = Ctl() }

@MainActor func spin(_ s: Double = 0.15) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

@MainActor func makeWindow<V: View>(_ view: V, key: Bool = true, size: CGFloat = 200) -> NSWindow {
    let rect = CGRect(x: 200, y: 200, width: size, height: size)
    let w: NSWindow = key
        ? KeyWindow(contentRect: rect, styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        : NotKeyWindow(contentRect: rect, styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    let host = FirstMouseHost(rootView: view)
    w.contentView = host
    host.layoutSubtreeIfNeeded()
    if key { w.makeKeyAndOrderFront(nil) } else { w.orderFront(nil) }
    spin(0.3)
    return w
}

@MainActor func mouse(_ w: NSWindow, _ t: NSEvent.EventType, _ p: CGPoint) {
    let pressure: Float = (t == .leftMouseUp || t == .rightMouseUp) ? 0 : 1
    let e = NSEvent.mouseEvent(with: t, location: p, modifierFlags: [],
                               timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: w.windowNumber, context: nil, eventNumber: 0,
                               clickCount: 1, pressure: pressure)!
    w.sendEvent(e)
}
@MainActor func click(_ w: NSWindow, at p: CGPoint) {
    mouse(w, .leftMouseDown, p); spin(0.05); mouse(w, .leftMouseUp, p); spin()
}
@MainActor func rightClick(_ w: NSWindow, at p: CGPoint) {
    mouse(w, .rightMouseDown, p); spin(0.05); mouse(w, .rightMouseUp, p); spin()
}
@MainActor func key(_ w: NSWindow, _ chars: String, keyCode: UInt16) {
    for type in [NSEvent.EventType.keyDown, .keyUp] {
        let e = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [],
                                 timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber,
                                 context: nil, characters: chars, charactersIgnoringModifiers: chars,
                                 isARepeat: false, keyCode: keyCode)!
        NSApp.sendEvent(e)
        spin()
    }
}

/// Runs the arm: builds the window, logs `settled` after the first spin, runs `act`, prints the line.
@MainActor func arm<V: View>(_ label: String, key isKey: Bool = true, fr: Bool = false, _ view: V, _ act: (NSWindow) -> Void = { _ in }) {
    _ = Log.take()
    Shared.ctl.shown = true; Shared.ctl.extra = false; Shared.ctl.tick = 0; Shared.ctl.top = false
    let w = makeWindow(view, key: isKey)
    Log.add("settled")
    if fr { Log.add("fr=" + (w.firstResponder.map { NSStringFromClass(type(of: $0)) } ?? "nil")) }
    act(w)
    if fr { Log.add("fr=" + (w.firstResponder.map { NSStringFromClass(type(of: $0)) } ?? "nil")) }
    print("  \(label): \(Log.take())")
    w.orderOut(nil)
    w.contentView = nil
}

/// A tree of Int?-focus items. `make` receives the `@FocusState<Int?>` binding; every flip is logged.
struct Multi<V: View>: View {
    @FocusState var f: Int?
    let make: (FocusState<Int?>.Binding) -> V
    var body: some View {
        make($f).onChange(of: f) { _, v in Log.add("f=\(v.map(String.init) ?? "nil")") }
    }
}

struct Flag<V: View>: View {
    @FocusState var a: Bool
    let make: (FocusState<Bool>.Binding) -> V
    var body: some View {
        make($a).onChange(of: a) { _, v in Log.add("a=\(v)") }
    }
}

extension View {
    func item(_ f: FocusState<Int?>.Binding, _ i: Int, _ h: CGFloat = 40) -> some View {
        Color.blue.frame(height: h).focusable().focused(f, equals: i)
    }
}

let centre = CGPoint(x: 100, y: 100)
let outside = CGPoint(x: 10, y: 190)

@MainActor func armSeat() {
    print("--- I: what seats on the first draw")
    arm("I0 lone .focusable(), key window", Multi { f in Color.blue.focusable().focused(f, equals: 0) })
    arm("I0n lone .focusable(), window NOT key", key: false, Multi { f in Color.blue.focusable().focused(f, equals: 0) })
    arm("LF7 [Button]", Multi { f in Button("b") { }.focused(f, equals: 0) })
    arm("I1 [Button, focusable]", Multi { f in VStack(spacing: 0) { Button("b") { }.frame(height: 40); Color.blue.focusable().focused(f, equals: 1) } })
    arm("I6a [Toggle, focusable]", Multi { f in VStack(spacing: 0) { Toggle("t", isOn: .constant(false)).frame(height: 40); Color.blue.focusable().focused(f, equals: 1) } })
    arm("I6b [Slider, focusable]", Multi { f in VStack(spacing: 0) { Slider(value: .constant(0.5)).frame(height: 40); Color.blue.focusable().focused(f, equals: 1) } })
    arm("I6c [Picker, focusable]", Multi { f in VStack(spacing: 0) {
        Picker("p", selection: .constant(0)) { Text("a").tag(0); Text("b").tag(1) }.frame(height: 40)
        Color.blue.focusable().focused(f, equals: 1) } })
    arm("I7 [.activate, focusable]", Multi { f in VStack(spacing: 0) {
        Color.red.frame(height: 40).focusable(interactions: .activate).focused(f, equals: 0)
        Color.blue.focusable().focused(f, equals: 1) } })
    arm("I9 [focusable(false), focusable]", Multi { f in VStack(spacing: 0) {
        Color.red.frame(height: 40).focusable(false).focused(f, equals: 0)
        Color.blue.focusable().focused(f, equals: 1) } })
    arm("I11 [hidden, focusable]", Multi { f in VStack(spacing: 0) {
        Color.red.frame(height: 40).focusable().focused(f, equals: 0).hidden()
        Color.blue.focusable().focused(f, equals: 1) } })
    arm("LF9 [disabled, focusable]", Multi { f in VStack(spacing: 0) {
        Color.red.frame(height: 40).focusable().focused(f, equals: 0).disabled(true)
        Color.blue.focusable().focused(f, equals: 1) } })
    arm("I8 [.edit, focusable]", Multi { f in VStack(spacing: 0) {
        Color.red.frame(height: 40).focusable(interactions: .edit).focused(f, equals: 0)
        Color.blue.focusable().focused(f, equals: 1) } })
    arm("I26 [allowsHitTesting(false) focusable, focusable]", Multi { f in VStack(spacing: 0) {
        Color.red.frame(height: 40).focusable().focused(f, equals: 0).allowsHitTesting(false)
        Color.blue.focusable().focused(f, equals: 1) } })
    arm("I13 [List(selection), focusable]", fr: true, Multi { f in VStack(spacing: 0) {
        List(selection: .constant(Optional(0))) { Text("a").tag(0); Text("b").tag(1) }.frame(height: 100)
        Color.blue.focusable().focused(f, equals: 1) } })
    arm("I14 [List, focusable]", fr: true, Multi { f in VStack(spacing: 0) {
        List { Text("a"); Text("b") }.frame(height: 100)
        Color.blue.focusable().focused(f, equals: 1) } })
    print("--- G: scrollers and order")
    arm("G5 [ScrollView{focusable}]", Multi { f in ScrollView { Color.blue.frame(height: 40).focusable().focused(f, equals: 0) } })
    arm("G6 [List{focusable row}]", fr: true, Multi { f in List { Color.blue.frame(height: 40).focusable().focused(f, equals: 0) } })
    arm("G7 [ScrollView{focusable}, focusable outside]", Multi { f in VStack(spacing: 0) {
        ScrollView { Color.blue.frame(height: 40).focusable().focused(f, equals: 0) }.frame(height: 80)
        Color.green.focusable().focused(f, equals: 1) } })
    arm("G5o [ScrollView{focusable 400 tall} overflowing]", Multi { f in ScrollView { Color.blue.frame(height: 400).focusable().focused(f, equals: 0) } })
    arm("G7o [ScrollView{overflowing focusable}, focusable outside]", Multi { f in VStack(spacing: 0) {
        ScrollView { Color.blue.frame(height: 400).focusable().focused(f, equals: 0) }.frame(height: 80)
        Color.green.focusable().focused(f, equals: 1) } })
    arm("G5h [ScrollView(.horizontal){focusable}]", Multi { f in ScrollView(.horizontal) { Color.blue.frame(width: 400, height: 40).focusable().focused(f, equals: 0) } })
    arm("G5v [ScrollView{VStack{Text.focusable}}]", Multi { f in ScrollView { VStack { Text("x").focusable().focused(f, equals: 0) } } })
    arm("G5t [ScrollView{Text.focusable}], window 400 tall", Multi { f in ScrollView { Text("x").padding().focusable().focused(f, equals: 0) } })
    arm("G7s [focusable above, ScrollView{focusable} below]", Multi { f in VStack(spacing: 0) {
        Color.green.frame(height: 40).focusable().focused(f, equals: 1)
        ScrollView { Color.blue.frame(height: 400).focusable().focused(f, equals: 0) }.frame(height: 80) } })
    arm("G7t [ScrollView{focusable} above, focusable below]", Multi { f in VStack(spacing: 0) {
        ScrollView { Color.blue.frame(height: 400).focusable().focused(f, equals: 0) }.frame(height: 80)
        Color.green.frame(height: 40).focusable().focused(f, equals: 1) } })
    arm("I13b [focusable, List]", fr: true, Multi { f in VStack(spacing: 0) {
        Color.blue.frame(height: 40).focusable().focused(f, equals: 0)
        List { Text("a"); Text("b") }.frame(height: 100) } })
    arm("G6s [List{ScrollView{focusable}}]", fr: true, Multi { f in List { ScrollView { Color.blue.frame(height: 40).focusable().focused(f, equals: 0) }.frame(height: 60) } })
    arm("I13s [List, focusable] side by side, same top, List earlier", fr: true, Multi { f in HStack(alignment: .top, spacing: 0) {
        List { Text("a"); Text("b") }.frame(width: 100, height: 100)
        Color.blue.frame(width: 50, height: 100).focusable().focused(f, equals: 0) } })
    arm("I13t [focusable, List] side by side, same top, focusable earlier", fr: true, Multi { f in HStack(alignment: .top, spacing: 0) {
        Color.blue.frame(width: 50, height: 100).focusable().focused(f, equals: 0)
        List { Text("a"); Text("b") }.frame(width: 100, height: 100) } })
    arm("I13u [List 50 tall, focusable 100 tall] bottom-aligned: List earlier and LOWER", fr: true, Multi { f in HStack(alignment: .bottom, spacing: 0) {
        List { Text("a") }.frame(width: 100, height: 50)
        Color.blue.frame(width: 50, height: 100).focusable().focused(f, equals: 0) } })
    arm("I13v [focusable 50 tall, List 100 tall] bottom-aligned: focusable earlier and LOWER", fr: true, Multi { f in HStack(alignment: .bottom, spacing: 0) {
        Color.blue.frame(width: 50, height: 50).focusable().focused(f, equals: 0)
        List { Text("a"); Text("b") }.frame(width: 100, height: 100) } })
    arm("G8 [LazyVStack{focusable}] (no scroller)", Multi { f in LazyVStack(spacing: 0) { Color.blue.frame(height: 40).focusable().focused(f, equals: 0) } })
    arm("G8b [ScrollView{LazyVStack{focusable}}]", Multi { f in ScrollView { LazyVStack(spacing: 0) { Color.blue.frame(height: 40).focusable().focused(f, equals: 0) } } })
    arm("G1 [A offset down 100, B]: B is higher but later in tree order", Multi { f in ZStack(alignment: .top) {
        Color.blue.frame(width: 50, height: 50).focusable().focused(f, equals: 0).offset(y: 100)
        Color.green.frame(width: 50, height: 50).focusable().focused(f, equals: 1) } })
    arm("G2 [A positioned at y 150, B positioned at y 40]", Multi { f in ZStack {
        Color.blue.frame(width: 50, height: 50).focusable().focused(f, equals: 0).position(x: 100, y: 150)
        Color.green.frame(width: 50, height: 50).focusable().focused(f, equals: 1).position(x: 100, y: 40) } })
    arm("G3 [A, B] side by side, same top", Multi { f in HStack(spacing: 0) {
        Color.blue.focusable().focused(f, equals: 0); Color.green.focusable().focused(f, equals: 1) } })
    arm("G4 [A, B] stacked in a ZStack, same top", Multi { f in ZStack {
        Color.blue.frame(width: 80, height: 80).focusable().focused(f, equals: 0)
        Color.green.frame(width: 80, height: 80).focusable().focused(f, equals: 1) } })
    arm("G4b [B(1) later in tree but A(0) lower, equal top via VStack alignment]", Multi { f in HStack(alignment: .top, spacing: 0) {
        Color.blue.frame(width: 50, height: 80).focusable().focused(f, equals: 0)
        Color.green.frame(width: 50, height: 40).focusable().focused(f, equals: 1) } })
    print("--- C8: nested focusables (outer 0, inner 1, sibling 2)")
    arm("C8a [outer{inner}]", Multi { f in
        Color.blue.focusable().focused(f, equals: 1).padding(40).background(Color.red).contentShape(Rectangle())
            .focusable().focused(f, equals: 0) })
    arm("C8b [sibling 2 earlier, same top; outer{inner}]", Multi { f in HStack(alignment: .top, spacing: 0) {
        Color.gray.frame(width: 50, height: 40).focusable().focused(f, equals: 2)
        Color.blue.frame(width: 50, height: 40).focusable().focused(f, equals: 1).padding(20).background(Color.red).contentShape(Rectangle())
            .focusable().focused(f, equals: 0) } })
    arm("C8c [sibling 2 earlier, higher; outer{inner}] below it", Multi { f in VStack(spacing: 0) {
        Color.gray.frame(height: 40).focusable().focused(f, equals: 2)
        Color.blue.focusable().focused(f, equals: 1).padding(20).background(Color.red).contentShape(Rectangle())
            .focusable().focused(f, equals: 0) } })
}

struct AppearWrite: View {
    @FocusState var f: Int?
    var body: some View {
        VStack(spacing: 0) {
            Color.red.frame(height: 40).focusable().focused($f, equals: 0)
            Color.blue.focusable().focused($f, equals: 1)
        }
        .onAppear { f = 1 }
        .onChange(of: f) { _, v in Log.add("f=\(v.map(String.init) ?? "nil")") }
    }
}

struct DefaultFocusHost: View {
    @FocusState var f: Int?
    let priority: Int
    var body: some View {
        VStack(spacing: 0) {
            Color.red.frame(height: 40).focusable().focused($f, equals: 0)
            Color.blue.focusable().focused($f, equals: 1)
        }
        .defaultFocus($f, 1, priority: priority == 0 ? .automatic : .userInitiated)
        .onChange(of: f) { _, v in Log.add("f=\(v.map(String.init) ?? "nil")") }
    }
}

struct Dynamic: View {
    @FocusState var f: Int?
    var c: Ctl
    let showFirstAtStart: Bool
    var body: some View {
        VStack(spacing: 0) {
            if c.top { Color.orange.frame(height: 40).focusable().focused($f, equals: 8) }
            if c.shown && showFirstAtStart { Color.red.frame(height: 40).focusable().focused($f, equals: 0) }
            Color.blue.frame(height: 40).focusable().focused($f, equals: 1)
            Color.green.frame(height: 40).focusable().focused($f, equals: 2)
            if c.extra { Color.orange.frame(height: 40).focusable().focused($f, equals: 9) }
            Spacer()
        }
        .onChange(of: c.tick) { _, _ in f = nil }
        .onChange(of: f) { _, v in Log.add("f=\(v.map(String.init) ?? "nil")") }
    }
}

struct LateInsert: View {
    @FocusState var f: Int?
    var c: Ctl
    var body: some View {
        VStack(spacing: 0) {
            Color.gray.frame(height: 40)
            if c.extra { Color.blue.frame(height: 40).focusable().focused($f, equals: 0) }
            Spacer()
        }
        .onChange(of: f) { _, v in Log.add("f=\(v.map(String.init) ?? "nil")") }
    }
}

struct FieldRemoval: View {
    @FocusState var f: Int?
    @State var t = "abc"
    var c: Ctl
    var body: some View {
        VStack(spacing: 0) {
            if c.shown { TextField("f", text: $t).focused($f, equals: 0).frame(height: 30) }
            Color.blue.frame(height: 40).focusable().focused($f, equals: 1)
        }
        .onAppear { f = 0 }
        .onChange(of: f) { _, v in Log.add("f=\(v.map(String.init) ?? "nil")") }
    }
}

@MainActor func armOrderAndLifecycle() {
    print("--- I20 / D: writes and defaultFocus")
    arm("I20 onAppear writes f=1 over [0, 1]", AppearWrite())
    arm("I18 defaultFocus(f, 1) over [0, 1]", DefaultFocusHost(priority: 0))
    arm("I21 defaultFocus(f, 1, priority: .userInitiated)", DefaultFocusHost(priority: 1))
    print("--- L: lifecycle")
    arm("L1 focusable inserted after show", LateInsert(c: Shared.ctl)) { _ in
        Log.add("|insert"); Shared.ctl.extra = true; spin(0.3) }
    arm("L3 cleared from code after the seat (tick), then settle", Dynamic(c: Shared.ctl, showFirstAtStart: true)) { _ in
        Log.add("|clear"); Shared.ctl.tick += 1; spin(0.3) }
    arm("L2 focused first removed, 1 and 2 exist", Dynamic(c: Shared.ctl, showFirstAtStart: true)) { _ in
        Log.add("|remove"); Shared.ctl.shown = false; spin(0.3) }
    arm("L4 same, then a new focusable inserted (9) in the same change", Dynamic(c: Shared.ctl, showFirstAtStart: true)) { _ in
        Log.add("|remove+insert"); Shared.ctl.shown = false; Shared.ctl.extra = true; spin(0.3) }
    arm("L5 focused removed and a new focusable inserted ABOVE all (8) in the same change", Dynamic(c: Shared.ctl, showFirstAtStart: true)) { _ in
        Log.add("|remove+insertTop"); Shared.ctl.shown = false; Shared.ctl.top = true; spin(0.3) }
    arm("L6 focused TextField (f=0, seeded by onAppear) removed", fr: true, FieldRemoval(c: Shared.ctl)) { _ in
        Log.add("|remove"); Shared.ctl.shown = false; spin(1.0) }
}

struct TF: View {
    @State var t = "abc"
    var body: some View { TextField("f", text: $t).frame(height: 30) }
}

@MainActor func armFields() {
    print("--- LF: TextFields (hosting view laid out before show)")
    arm("LF1 [TF]", Multi { f in VStack(spacing: 0) { TF().focused(f, equals: 0) } })
    arm("LF2 [TF, TF]", Multi { f in VStack(spacing: 0) { TF().focused(f, equals: 0); TF().focused(f, equals: 1) } })
    arm("LF5 [focusable, TF]", Multi { f in VStack(spacing: 0) {
        Color.blue.frame(height: 40).focusable().focused(f, equals: 0); TF().focused(f, equals: 1) } })
    arm("LF5b [TF, focusable]", Multi { f in VStack(spacing: 0) {
        TF().focused(f, equals: 0); Color.blue.frame(height: 40).focusable().focused(f, equals: 1) } })
}

/// T1's separation. Is "a lone `.focusable()` takes focus from any click" the click, or the first-draw seat?
@MainActor func armT1() {
    print("--- T1: what the earlier probe's T1 is (read each against `settled`)")
    arm("T1s lone .focusable() 50 x 50, no event at all", Flag { a in Color.blue.frame(width: 50, height: 50).focusable().focused(a) })
    arm("T1k lone .focusable() 50 x 50, first event is a KEY (Tab), not a click", Flag { a in
        Color.blue.frame(width: 50, height: 50).focusable().focused(a) }) { w in Log.add("|tab"); key(w, "\t", keyCode: 48) }
    arm("T1 lone .focusable() 50 x 50, click OUTSIDE it", Flag { a in
        Color.blue.frame(width: 50, height: 50).focusable().focused(a) }) { w in Log.add("|click"); click(w, at: outside) }
    arm("T1c lone .focusable(), RIGHT press", Flag { a in Color.blue.focusable().focused(a) }) { w in
        Log.add("|rclick"); rightClick(w, at: centre) }
    arm("T1g lone .focusable() INSERTED AFTER show (not seated, L1), click OUTSIDE it", LateInsertFlag(c: Shared.ctl)) { w in
        Log.add("|insert"); Shared.ctl.extra = true; spin(0.3)
        Log.add("|click"); click(w, at: CGPoint(x: 10, y: 10)) }
    arm("T1h same, click ON it", LateInsertFlag(c: Shared.ctl)) { w in
        Log.add("|insert"); Shared.ctl.extra = true; spin(0.3)
        Log.add("|click"); click(w, at: CGPoint(x: 100, y: 130)) }
    arm("T1i same, RIGHT press OUTSIDE it", LateInsertFlag(c: Shared.ctl)) { w in
        Log.add("|insert"); Shared.ctl.extra = true; spin(0.3)
        Log.add("|rclick"); rightClick(w, at: CGPoint(x: 10, y: 10)) }
    arm("T1j window not key, lone .focusable() 50 x 50, click OUTSIDE it", key: false, Flag { a in
        Color.blue.frame(width: 50, height: 50).focusable().focused(a) }) { w in Log.add("|click"); click(w, at: outside) }
}

struct LateInsertFlag: View {
    @FocusState var a: Bool
    var c: Ctl
    var body: some View {
        VStack(spacing: 0) {
            Color.gray.frame(height: 40)
            if c.extra { Color.blue.frame(width: 50, height: 50).focusable().focused($a) }
            Spacer()
        }
        .onChange(of: a) { _, v in Log.add("a=\(v)") }
    }
}

setbuf(stdout, nil)
let app = NSApplication.shared
app.setActivationPolicy(.regular)
armSeat(); armOrderAndLifecycle(); armFields(); armT1()
