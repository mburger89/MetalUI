// SwiftUI probe: which views take focus when they are CLICKED (round 4 item R4-4 PR B; divergence 94,
// rulings `FC-` in docs/superpowers/2026-11-04-focus-click-and-seat-decisions.md). It widens the key-focus
// probe's FC arms (`swiftui-key-focus.swift`, KF-F) to controls, covered focusables, nesting, the right
// button, `.disabled`, `.allowsHitTesting(false)` and a `Button` that is also `.focusable()`.
//
// HOW TO RUN (SA-O's compiled form; no JIT shim):
//
//   xcrun swiftc -swift-version 6 docs/probes/swiftui-focus-click.swift -o /tmp/fc-probe
//   /tmp/fc-probe > /tmp/fc-1.txt; /tmp/fc-probe > /tmp/fc-2.txt; cmp /tmp/fc-1.txt /tmp/fc-2.txt
//
// INSTRUMENT. `swiftui-key-focus.swift`'s: a `FirstMouseHost` (an `NSHostingView`) in a `KeyWindow` (answers
// `isKeyWindow` true), laid out and shown before the first event (a hosting view not laid out before
// `makeKeyAndOrderFront` gives a different TextField answer, plan trap), `NSEvent`s through `NSWindow.sendEvent`
// with a run-loop spin between them. The window is 200 x 200; coordinates have the origin at the BOTTOM left.
// `@FocusState` flips are logged as `focused=`; a tap as `tap`. The line is `-` when nothing happened.
//
// INSTRUMENT TRAPS (found while transcribing; both change a reading).
//   T1. A LONE `.focusable()` takes focus from ANY click that lands in the window, even one that misses it
//       (T1) or is a right press (T1c). A negative arm ("this view does not take focus") is therefore read
//       with a SECOND focusable already focused (`Seeded`: left half focused on appear, the subject the
//       right half); a lone-subject negative proves nothing.
//   T2. A root view that does not fill the window is not centred in an `NSHostingView` here: a small `Button`
//       at the window centre is missed (no `tap`). A control arm is expanded with `.frame(maxWidth:
//       .infinity, maxHeight: .infinity)` and logs its own action (`tap`, `on=`, `v=`) so the reading
//       proves the control was hit.
//
// FKA. Full Keyboard Access is OFF on the recording machine (`isFullKeyboardAccessEnabled = false`). The `FK`
// arm cannot switch it on (an `NSApplication` subclass answering true did not make Tab move anything in the
// first session), so the FK reading is INCONCLUSIVE and no ruling rests on it; the `Button` / `Toggle` /
// `Slider` rows (C1, C3, C4) are readings "with FKA off" and divergence 80 keeps the FKA-on half.
//
// NOT MEASURED. Clicks inside a `ScrollView` / `List` (C5, C14: the first session's `ScrollView` control tap
// did not fire, so `sendEvent` does not reach the content there); they wait for a person (human group FC2).
//
// The first session's arms were run through `swift -` on stdin and never committed; this file is their
// transcription. Arm ids follow the plan; arm bodies are rebuilt from the plan's descriptions (the plan names
// C15 only in its test list, so C15 here is the two-focusables sequence the plan's
// `clickingAFocusableElementFocusesIt` expects). Controls: FC1 is `swiftui-key-focus.swift`'s FC1 and the
// key-focus FC2 / FC5 / RS4 are repeated here (FC2, C0, RS4) so one run reads against its own control.
//
// RECORDED 2026-11-04, macOS 27.2, Apple Swift 6.4.2 (swiftlang-6.4.2.1.9), screen LOCKED
// (CGSSessionScreenIsLocked = 1; the events go into the probe's own window through `NSWindow.sendEvent`, so the
// lock does not matter), FKA off. Compiled form, run twice: stdout byte-identical, exit 0, stderr empty.
//
// stdout byte-identical (36 lines, shasum cfc6d66fc3671adfae7fe03792506230bed6d6a8):
//
//   fullKeyboardAccess=false
//   --- FC: lone subject (controls), left click at the centre
//     FC1 .focusable() (control): focused=true
//     FC2 .focusable(interactions: .activate) (control): -
//     C0 .focusable(interactions: .activate) + onTapGesture: tap
//     C1 Button, FKA off: tap
//     C2 TextField: focused=true
//     C3 Toggle, FKA off: on=true
//     C4 Slider, FKA off (click the track at 25%, off the thumb): v=17
//     C6 click a Button while a focusable is focused: focused=true,|start,tap
//     C15 two focusables: click left, then right: a=true,a=false,b=true
//     RS4 TextField focused, click a .focusable() view (repeats key-focus RS4): focused=true,|start,below=true,focused=false
//   --- T1: INSTRUMENT TRAP. A lone .focusable() against clicks that miss it
//     T1 lone .focusable() 50 x 50, click OUTSIDE it: focused=true
//     T1b lone .focusable(interactions: .activate), RIGHT press: -
//     T1c lone .focusable(), RIGHT press (a false positive, see C10): focused=true
//   --- C: subject B beside a focused A (left half focused on appear, click the right half)
//     C9 B = .focusable(): a=true,|,a=false,b=true
//     C9r B = plain Color (no focusable): a=true,|
//     C10 B = .focusable(), RIGHT press: a=true,|
//     C11 B = .focusable().disabled(true): a=true,|
//     C12 B = .focusable().allowsHitTesting(false): a=true,|
//     C12b B = .allowsHitTesting(false) written BEFORE .focusable(): a=true,|
//     C13 B = Button.focusable() (tap also fires): a=true,|,a=false,b=true,tap
//     C16 B = a focusable CONTAINER of a Button, press the Button (added: not in the plan): a=true,|,a=false,b=true,tap
//     C16b same, press the container's EMPTY space (a VStack's gaps are not hit-testable): a=true,|
//     C16c same with .contentShape(Rectangle()), press the empty space: a=true,|,a=false,b=true
//     C17 B = .draggable("s").focusable(), press and release without a move: a=true,|,a=false,b=true
//   --- C7: B and something that covers it, or that it covers (read against a focused A)
//     C7 B = focusable COVERED by a tappable: a=true,|,tap
//     C7b B = focusable COVERED by a plain Color: a=true,|
//     C7c B = focusable ABOVE a tappable: a=true,|,a=false,b=true
//   --- C8a: nested focusables (inner, then the outer's own margin)
//     C8a inner focusable inside an outer one: click inner, then the outer margin: b=true,a=true,a=false
//   --- FK: Tab with FKA off (INCONCLUSIVE: FKA cannot be switched on from the process)
//     FK1 [Button, focusable], Tab: focused=true
//
// READING (against the plan: every row agrees; the arm bodies are rebuilt, so the traps above were found, not
// assumed).
//   Takes focus on the press: `.focusable()` (FC1, C9, C15), `.focusable(interactions: .edit)` (key-focus FC3),
//   a `TextField` (C2), `Button.focusable()` with its tap also firing (C13), the inner of two nested
//   focusables and then the outer on its own margin (C8a: the outer's flag reads true with the inner focused).
//   Does not: `Button` (C1), `Toggle` (C3), `Slider` (C4), each with the control's own action proven by
//   `tap` / `on=` / `v=` (FKA off); `.activate` (FC2, C0); a right press (C10); `.disabled(true)` (C11);
//   `.allowsHitTesting(false)` written either side of `.focusable()` (C12, C12b).
//   A focusable COVERED by a tappable or a plain `Color` keeps the focus where it was (C7, C7b) and the
//   tappable fires (C7). A focusable ABOVE a tappable takes focus and the tap does not fire (C7c).
//   A `Button` inside a focusable CONTAINER: pressing the button focuses the container and the tap fires (C16);
//   the container's empty space focuses it only with `.contentShape(Rectangle())` (C16b, C16c: a stack's gaps
//   are not hit-testable, which MetalUI's region, the element's whole bounds, does not copy; carried with 57).
//   A press on a `.draggable("s").focusable()` view (no move) focuses it (C17).
//   Clicking a `Button` leaves the focused view focused (C6). A focusable press resigns a focused field
//   (RS4). C9r: a press on plain content does not move focus.
//   INCONCLUSIVE (not claimed): FK1 (Tab with FKA off; FKA cannot be switched on), and C7 / C7b / C7c prove
//   WHICH of focus and tap fire, not who owns the hit test.

import SwiftUI
import AppKit

final class FirstMouseHost<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class KeyWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var canBecomeKey: Bool { true }
}

enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    static func add(_ s: String) { lines.append(s) }
    static func take() -> String {
        defer { lines = [] }
        return lines.isEmpty ? "-" : lines.joined(separator: ",")
    }
}

@MainActor func spin(_ s: Double = 0.15) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

@MainActor func makeWindow<V: View>(_ view: V, size: CGFloat = 200) -> NSWindow {
    let w = KeyWindow(contentRect: CGRect(x: 200, y: 200, width: size, height: size),
                      styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    let host = FirstMouseHost(rootView: view)
    w.contentView = host
    host.layoutSubtreeIfNeeded()
    w.makeKeyAndOrderFront(nil)
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

let centre = CGPoint(x: 100, y: 100)
let leftPoint = CGPoint(x: 25, y: 100)
let rightPoint = CGPoint(x: 175, y: 100)
let bottomPoint = CGPoint(x: 100, y: 30)

@MainActor func arm<V: View>(_ label: String, _ view: V, _ act: (NSWindow) -> Void) {
    _ = Log.take()
    let w = makeWindow(view)
    act(w)
    print("  \(label): \(Log.take())")
    w.orderOut(nil)
    w.contentView = nil
}

/// Wraps content built from a `@FocusState` binding and logs every flip.
struct ClickFocus<V: View>: View {
    @FocusState var focused: Bool
    let make: (FocusState<Bool>.Binding) -> V
    var body: some View {
        make($focused).onChange(of: focused) { _, v in Log.add("focused=\(v)") }
    }
}

struct Pair<V: View>: View {
    @FocusState var a: Bool
    @FocusState var b: Bool
    let make: (FocusState<Bool>.Binding, FocusState<Bool>.Binding) -> V
    var body: some View {
        make($a, $b)
            .onChange(of: a) { _, v in Log.add("a=\(v)") }
            .onChange(of: b) { _, v in Log.add("b=\(v)") }
    }
}

struct SwitchHost: View {
    @State var on = false
    @FocusState var f: Bool
    var body: some View {
        Toggle("t", isOn: $on).focused($f).frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: on) { _, v in Log.add("on=\(v)") }
            .onChange(of: f) { _, v in Log.add("focused=\(v)") }
    }
}

struct SliderHost: View {
    @State var v = 0.5
    @FocusState var f: Bool
    var body: some View {
        Slider(value: $v).focused($f).padding(.horizontal, 20).frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: v) { _, n in Log.add("v=\(Int(n * 100))") }
            .onChange(of: f) { _, v in Log.add("focused=\(v)") }
    }
}

struct FieldResign<Below: View>: View {
    @State var text = "abc"
    @FocusState var focused: Bool
    let below: Below
    var body: some View {
        VStack(spacing: 0) {
            TextField("f", text: $text).focused($focused).frame(height: 30)
            below
        }
        .onAppear { focused = true }
        .onChange(of: focused) { _, v in Log.add("focused=\(v)") }
    }
}

struct FocusableBelow: View {
    @FocusState var f: Bool
    var body: some View {
        Color.blue.focusable().focused($f).onChange(of: f) { _, v in Log.add("below=\(v)") }
    }
}

struct FieldHost: View {
    @State var text = "abc"
    @FocusState var f: Bool
    var body: some View {
        TextField("f", text: $text).focused($f).frame(height: 30)
            .frame(maxHeight: .infinity, alignment: .center)
            .onChange(of: f) { _, v in Log.add("focused=\(v)") }
    }
}

/// A focused focusable above a `Button`; reads whether a click on the button moves focus (C6).
struct FocusedAboveButton: View {
    @FocusState var f: Bool
    var body: some View {
        VStack(spacing: 0) {
            Color.blue.focusable().focused($f)
            Button("b") { Log.add("tap") }.frame(height: 60)
        }
        .onAppear { f = true }
        .onChange(of: f) { _, v in Log.add("focused=\(v)") }
    }
}

/// Focusable `A` (left half) is focused on appear; the SUBJECT `B` is the right half. A negative arm must
/// be read this way: a LONE `.focusable()` takes focus from any click that lands in the window (T1), so
/// "no `focused=true`" can only be read against a window that already has a focused view to move.
struct Seeded<V: View>: View {
    @FocusState var a: Bool
    @FocusState var b: Bool
    let subject: (FocusState<Bool>.Binding) -> V
    var body: some View {
        HStack(spacing: 0) {
            Color.blue.focusable().focused($a)
            subject($b)
        }
        .onAppear { a = true }
        .onChange(of: a) { _, v in Log.add("a=\(v)") }
        .onChange(of: b) { _, v in Log.add("b=\(v)") }
    }
}

@MainActor func clickB(_ w: NSWindow) { Log.add("|"); click(w, at: rightPoint) }
@MainActor func clickBCentre(_ w: NSWindow) { Log.add("|"); click(w, at: CGPoint(x: 150, y: 100)) }

@MainActor func armFC() {
    print("--- FC: lone subject (controls), left click at the centre")
    arm("FC1 .focusable() (control)", ClickFocus { f in Color.blue.focusable().focused(f) }) { click($0, at: centre) }
    arm("FC2 .focusable(interactions: .activate) (control)", ClickFocus { f in
        Color.blue.focusable(interactions: .activate).focused(f) }) { click($0, at: centre) }
    arm("C0 .focusable(interactions: .activate) + onTapGesture", ClickFocus { f in
        Color.blue.focusable(interactions: .activate).focused(f).onTapGesture { Log.add("tap") } }) {
        click($0, at: centre)
    }
    arm("C1 Button, FKA off", ClickFocus { f in Button("x") { Log.add("tap") }.focused(f).frame(maxWidth: .infinity, maxHeight: .infinity) }) {
        click($0, at: centre)
    }
    arm("C2 TextField", FieldHost()) { click($0, at: centre) }
    arm("C3 Toggle, FKA off", SwitchHost()) { click($0, at: centre) }
    arm("C4 Slider, FKA off (click the track at 25%, off the thumb)", SliderHost()) { click($0, at: CGPoint(x: 55, y: 100)) }
    arm("C6 click a Button while a focusable is focused", FocusedAboveButton()) { w in
        Log.add("|start"); click(w, at: bottomPoint)
    }
    arm("C15 two focusables: click left, then right", Pair { a, b in
        HStack(spacing: 0) { Color.blue.focusable().focused(a); Color.green.focusable().focused(b) } }) { w in
        click(w, at: leftPoint); click(w, at: rightPoint)
    }
    arm("RS4 TextField focused, click a .focusable() view (repeats key-focus RS4)",
        FieldResign(below: FocusableBelow())) { w in Log.add("|start"); click(w, at: bottomPoint) }
    print("--- T1: INSTRUMENT TRAP. A lone .focusable() against clicks that miss it")
    arm("T1 lone .focusable() 50 x 50, click OUTSIDE it", ClickFocus { f in
        Color.blue.focusable().focused(f).frame(width: 50, height: 50) }) { click($0, at: CGPoint(x: 10, y: 190)) }
    arm("T1b lone .focusable(interactions: .activate), RIGHT press", ClickFocus { f in
        Color.blue.focusable(interactions: .activate).focused(f) }) { rightClick($0, at: centre) }
    arm("T1c lone .focusable(), RIGHT press (a false positive, see C10)", ClickFocus { f in
        Color.blue.focusable().focused(f) }) { rightClick($0, at: centre) }
    print("--- C: subject B beside a focused A (left half focused on appear, click the right half)")
    arm("C9 B = .focusable()", Seeded { b in Color.green.focusable().focused(b) }, clickB)
    arm("C9r B = plain Color (no focusable)", Seeded { _ in Color.green }, clickB)
    arm("C10 B = .focusable(), RIGHT press", Seeded { b in Color.green.focusable().focused(b) }) { w in
        Log.add("|"); rightClick(w, at: rightPoint)
    }
    arm("C11 B = .focusable().disabled(true)", Seeded { b in Color.green.focusable().focused(b).disabled(true) }, clickB)
    arm("C12 B = .focusable().allowsHitTesting(false)", Seeded { b in
        Color.green.focusable().focused(b).allowsHitTesting(false) }, clickB)
    arm("C12b B = .allowsHitTesting(false) written BEFORE .focusable()", Seeded { b in
        Color.green.allowsHitTesting(false).focusable().focused(b) }, clickB)
    arm("C13 B = Button.focusable() (tap also fires)", Seeded { b in
        Button("x") { Log.add("tap") }.focusable().focused(b).frame(maxWidth: .infinity, maxHeight: .infinity) }, clickBCentre)
    arm("C16 B = a focusable CONTAINER of a Button, press the Button (added: not in the plan)", Seeded { b in
        VStack { Button("x") { Log.add("tap") } }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .focusable().focused(b) }, clickBCentre)
    arm("C16b same, press the container's EMPTY space (a VStack's gaps are not hit-testable)", Seeded { b in
        VStack { Button("x") { Log.add("tap") } }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .focusable().focused(b) }) { w in Log.add("|"); click(w, at: CGPoint(x: 110, y: 20)) }
    arm("C16c same with .contentShape(Rectangle()), press the empty space", Seeded { b in
        VStack { Button("x") { Log.add("tap") } }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle()).focusable().focused(b) }) { w in Log.add("|"); click(w, at: CGPoint(x: 110, y: 20)) }
    arm("C17 B = .draggable(\"s\").focusable(), press and release without a move", Seeded { b in
        Color.green.draggable("s").focusable().focused(b) }, clickB)
}

@MainActor func armC7() {
    print("--- C7: B and something that covers it, or that it covers (read against a focused A)")
    arm("C7 B = focusable COVERED by a tappable", Seeded { b in
        ZStack {
            Color.green.focusable().focused(b)
            Color.clear.contentShape(Rectangle()).onTapGesture { Log.add("tap") }
        } }, clickB)
    arm("C7b B = focusable COVERED by a plain Color", Seeded { b in
        ZStack { Color.green.focusable().focused(b); Color.red } }, clickB)
    arm("C7c B = focusable ABOVE a tappable", Seeded { b in
        ZStack {
            Color.red.onTapGesture { Log.add("tap") }
            Color.green.focusable().focused(b)
        } }, clickB)
}

@MainActor func armC8() {
    print("--- C8a: nested focusables (inner, then the outer's own margin)")
    arm("C8a inner focusable inside an outer one: click inner, then the outer margin", Pair { inner, outer in
        Color.blue.focusable().focused(inner).padding(40).background(Color.red).contentShape(Rectangle())
            .focusable().focused(outer) }) { w in
        click(w, at: centre); click(w, at: CGPoint(x: 10, y: 100))
    }
}

@MainActor func armFK() {
    print("--- FK: Tab with FKA off (INCONCLUSIVE: FKA cannot be switched on from the process)")
    arm("FK1 [Button, focusable], Tab", ClickFocus { f in
        VStack(spacing: 0) { Button("b") { Log.add("tap") }.frame(maxWidth: .infinity).frame(height: 60); Color.blue.focusable().focused(f) } }) {
        key($0, "\t", keyCode: 48)
    }
}

setbuf(stdout, nil)
let app = NSApplication.shared
app.setActivationPolicy(.regular)
print("fullKeyboardAccess=\(NSApp.isFullKeyboardAccessEnabled)")
armFC(); armC7(); armC8(); armFK()
