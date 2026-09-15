// SwiftUI probe: what `.disabled(true)` (and a raw `isEnabled` write) does to
// pointer, focus and key input, measured by synthesizing AppKit events into
// real NSWindows hosting SwiftUI. Evidence for rulings EV-D (the
// environment value is the gate), EV-E (what a disabled hit target does to a
// click, by ANALOGY — see READING), EV-F (focus acquisition, key actions and
// raw key handlers) and EV-T (a press and a release across a flip) in
// docs/superpowers/2026-09-15-environment-decisions.md.
//
// HOW TO RUN. Either form; both were run on the final file and their filtered
// output is byte-identical to the recorded block below, and a second compiled
// run was identical too:
//
//   /usr/bin/swift docs/probes/swiftui-disabled-interaction.swift
//   swiftc docs/probes/swiftui-disabled-interaction.swift -o /tmp/disprobe
//   OS_ACTIVITY_DT_MODE=1 /tmp/disprobe 2>&1 | grep -v 'Connection\]\|ntents\|WindowTab'
//
// It opens and orders out one small window per arm (about 30). Exit status 0.
//
// HARNESS HISTORY, because versions of it measured nothing:
// - The first click helper queued the mouse-up and then sent the mouse-down.
//   Every `.onTapGesture` arm read 0 INCLUDING the enabled control P0, and so
//   did the default-style Button control: the disabled arms' zeros meant
//   nothing. Down, 50 ms, up, both through `NSWindow.sendEvent`, fixed the
//   gesture arms.
// - Even then taps read 0 until the hosting view accepted first mouse: the
//   script is unbundled, `NSApp.isActive` stays false, and an inactive window
//   eats its first click. `FirstMouseHost` below is that fix.
// - P2 (a disabled tappable Color over a tappable) read under 0 / over 0, but
//   so did the control P2m with an ENABLED gesture-less Color on top, so P2
//   could not say whether disabling swallows or a Color simply blocks. P2d..P2f
//   were added: an overlay whose only hit area is a contentShape. A design
//   review then added P2g/P2h (second pass, same day): the same overlay with NO
//   gesture blocks too, enabled or disabled, so P2f does not show that
//   `.disabled` swallows; it shows that `.disabled` leaves the hit shape alone.
// - K5/K6 first COUNTED the child's and the parent's `.onKeyPress`, with the
//   parent returning `.handled`. The child read 0 in the enabled control as
//   well, and the arm was recorded as "unexplained". The second pass logged
//   handler ORDER instead: the PARENT runs first on this system, so a parent
//   that returns `.handled` pre-empts the child. K5/K6 now return `.ignored`
//   from the parent, which makes the child's entry a control that can move
//   (it does: K5 lists it); K7/K8 keep the old `.handled` shape.
// - A scroll arm failed its control and was removed; see "S" below.
//
// RECORDED 2026-09-14 (second pass), macOS 26.6.2 (25G83), Apple Swift 6.4
// (swiftlang-6.4.0.33.1). Arms print enabled controls first, then the rest in
// the order the dictionary sorted them; zeros for counters that never fired are
// printed from an explicit list:
//
//   --- P: a click at the centre of a 200x200 window
//     P0 enabled onTapGesture (control): 1
//     P2c control, over has allowsHitTesting(false): under: 1
//     P2d control, Color.clear, no shape, no gesture: under: 1
//     P2e control, clear+contentShape+gesture ENABLED: over: 1
//     P3 .plain Button enabled (control): 1
//     P5 default-style Button enabled (control): 1
//     P8 .environment(isEnabled,true) inside .disabled(true): 1
//     P1 .disabled(true) onTapGesture: 0
//     P2 under a disabled tappable: over: 0
//     P2 under a disabled tappable: under: 0
//     P4 .plain Button .disabled(true): 0
//     P6 default-style Button .disabled(true): 0
//     P7 tap inside a disabled VStack: 0
//     P9 .environment(isEnabled,false), no .disabled: 0
//     P2n disabled over with NO gesture: under: 0
//     P2m control, ENABLED over with no gesture: under: 0
//     P2e control, clear+contentShape+gesture ENABLED: under: 0
//     P2f clear+contentShape+gesture .disabled(true): under: 0
//     P2f clear+contentShape+gesture .disabled(true): over: 0
//     P2g control, clear+contentShape, NO gesture, ENABLED: under: 0
//     P2h clear+contentShape, NO gesture, .disabled(true): under: 0
//   --- K: focus and key handling (focus requested in onAppear)
//     K0 enabled (control): focused=1 onKeyPress=1 firstResponder=Optional<NSResponder>
//     K1 .disabled(true) from the start: focused=never changed onKeyPress=0 firstResponder=Optional<NSResponder>
//     K2 focused, then disabled: control, onKeyPress while still enabled=1
//     K2 focused, then disabled: focused before=1 after=1 onKeyPress after disabling=1 isEnabled seen by the focused view after disabling=0
//     K2 focused, then disabled, re-enabled: focused=1
//     K5 bubble, parent enabled, parent .ignored (control): child focused=1 handler order=["parent", "child"]
//     K6 bubble, parent .disabled(true), child re-enabled, parent .ignored: child focused=1 handler order=["parent", "child"]
//     K7 bubble, parent enabled, parent .handled: child focused=1 handler order=["parent"]
//     K8 bubble, parent .disabled(true), child re-enabled, parent .handled: child focused=1 handler order=["parent"]
//     K3 keyboardShortcut cmd-k enabled (control): 1
//     K4 keyboardShortcut cmd-k .disabled(true): 0
//   --- R: press, flip .disabled, release (same timing in every arm)
//     R0 Button(.plain) enabled throughout (control): 1
//     R1 Button(.plain) pressed disabled, released enabled: 0
//     R2 Button(.plain) pressed enabled, released disabled: 0
//     R3 Button(.plain) disabled throughout: 0
//     R0 onTapGesture enabled throughout (control): 1
//     R1 onTapGesture pressed disabled, released enabled: 0
//     R2 onTapGesture pressed enabled, released disabled: 0
//     R3 onTapGesture disabled throughout: 0
//
// READING (what the rulings rely on):
// - P1, P4, P6, P7: disabling suppresses a tap gesture, a plain Button and a
//   default-style Button, including through a disabled ancestor.
// - P8, P9: the gate is the ENVIRONMENT VALUE at the gesture, not the
//   `.disabled` modifier: a raw `isEnabled = true` write inside `.disabled(true)`
//   lets the tap through, and a raw `isEnabled = false` write with no
//   `.disabled` blocks it.
// - P2d..P2h: HIT-TESTABILITY BELONGS TO THE SHAPE, AND `.disabled` DOES NOT
//   CHANGE IT. A clear overlay with no hit area passes the click down (P2d
//   under 1). Give it a contentShape and it takes the click whether it has an
//   enabled gesture (P2e over 1, under 0), a disabled gesture (P2f over 0,
//   under 0), no gesture (P2g under 0), or no gesture and `.disabled` (P2h
//   under 0). `.allowsHitTesting(false)` is the pass-through spelling (P2c
//   under 1). This probe does NOT show "a disabled target swallows" as a
//   property of `.disabled`. MetalUI's rule is a choice by analogy (EV-E),
//   because a MetalUI element's hit region is conferred by its `onClick`
//   rather than by a separate shape.
// - K1: a view disabled from the start never acquires focus and never sees a key.
// - K2: a view focused and THEN disabled keeps focus (focused stays 1, and is
//   still 1 after re-enabling) and its `.onKeyPress` still fires — while the
//   view itself reads isEnabled 0, so the disable did reach it.
// - K5..K8: `.onKeyPress` on a DISABLED parent runs exactly as on an enabled
//   one (K6 = K5, K8 = K7): raw key handlers are not gated on isEnabled. The
//   handler ORDER is parent first, then the focused child (K5), which is the
//   opposite of MetalUI's focused-element-outward bubble. Recorded, not
//   adopted (EV-Q).
// - K3/K4: a Button's `.keyboardShortcut` does not fire while disabled.
// - R0..R3: a click fires only when the control is enabled at BOTH the press
//   and the release. Pressed disabled and released enabled reads 0 (R1), and
//   so does the reverse (R2), for a plain Button and for `.onTapGesture`; the
//   enabled control at the same timing reads 1 (R0).
import SwiftUI
import AppKit

/// The script is not a bundled app, so `NSApp.isActive` stays false and every
/// window is inactive. An inactive window's first click is consumed for
/// activation unless the view accepts first mouse: without this subclass an
/// ENABLED `.onTapGesture` read 0 (the positive control failed), so every
/// disabled arm would have read 0 for a reason unrelated to `.disabled`.
final class FirstMouseHost<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

enum Count {
    nonisolated(unsafe) static var hits: [String: Int] = [:]
    static func bump(_ k: String) { hits[k, default: 0] += 1 }
    static func read(_ k: String) -> Int { hits[k, default: 0] }
}

@MainActor func spin(_ s: Double = 0.15) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

@MainActor func makeWindow<V: View>(_ view: V, size: CGSize = CGSize(width: 200, height: 200)) -> NSWindow {
    let w = NSWindow(contentRect: CGRect(x: 200, y: 200, width: size.width, height: size.height),
                     styleMask: [.titled], backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    w.contentView = FirstMouseHost(rootView: view)
    w.makeKeyAndOrderFront(nil)
    spin()
    return w
}

/// A click at `p`, in window coordinates with the origin at the BOTTOM-left.
@MainActor func click(_ w: NSWindow, at p: CGPoint) {
    func ev(_ t: NSEvent.EventType) -> NSEvent {
        NSEvent.mouseEvent(with: t, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                           windowNumber: w.windowNumber, context: nil, eventNumber: 0,
                           clickCount: 1, pressure: t == .leftMouseDown ? 1 : 0)!
    }
    // Down, a short spin, then up, both through `sendEvent`. Posting the up to
    // the queue first (for an AppKit tracking loop) made `.onTapGesture` read 0
    // with the control enabled, so it is not used.
    w.sendEvent(ev(.leftMouseDown))
    spin(0.05)
    w.sendEvent(ev(.leftMouseUp))
    spin()
}

@MainActor func key(_ w: NSWindow, _ chars: String, modifiers: NSEvent.ModifierFlags = []) {
    let down = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber,
                                context: nil, characters: chars, charactersIgnoringModifiers: chars,
                                isARepeat: false, keyCode: 0)!
    NSApp.sendEvent(down)
    spin()
}

let center = CGPoint(x: 100, y: 100)

// MARK: - P: pointer

@MainActor func tapArm(_ label: String, _ view: some View) {
    let w = makeWindow(view)
    click(w, at: center)
    w.orderOut(nil)
}

@MainActor func armP() {
    print("--- P: a click at the centre of a 200x200 window")
    tapArm("P0", Color.blue.onTapGesture { Count.bump("P0 enabled onTapGesture (control)") })
    tapArm("P1", Color.blue.onTapGesture { Count.bump("P1 .disabled(true) onTapGesture") }.disabled(true))
    tapArm("P2", ZStack {
        Color.red.onTapGesture { Count.bump("P2 under a disabled tappable: under") }
        Color.blue.onTapGesture { Count.bump("P2 under a disabled tappable: over") }.disabled(true)
    })
    tapArm("P2c", ZStack {
        Color.red.onTapGesture { Count.bump("P2c control, over has allowsHitTesting(false): under") }
        Color.blue.onTapGesture { Count.bump("P2c control, over has allowsHitTesting(false): over") }
            .allowsHitTesting(false)
    })
    tapArm("P2m", ZStack {
        Color.red.onTapGesture { Count.bump("P2m control, ENABLED over with no gesture: under") }
        Color.blue
    })
    // P2m shows a plain enabled Color already blocks the tap beneath it, so P2
    // cannot tell "disabled swallows" from "a Color is hit-testable". P2d..P2f
    // use an overlay whose only hit area is its contentShape.
    tapArm("P2d", ZStack {
        Color.red.onTapGesture { Count.bump("P2d control, Color.clear, no shape, no gesture: under") }
        Color.clear
    })
    tapArm("P2e", ZStack {
        Color.red.onTapGesture { Count.bump("P2e control, clear+contentShape+gesture ENABLED: under") }
        Color.clear.contentShape(Rectangle())
            .onTapGesture { Count.bump("P2e control, clear+contentShape+gesture ENABLED: over") }
    })
    tapArm("P2f", ZStack {
        Color.red.onTapGesture { Count.bump("P2f clear+contentShape+gesture .disabled(true): under") }
        Color.clear.contentShape(Rectangle())
            .onTapGesture { Count.bump("P2f clear+contentShape+gesture .disabled(true): over") }
            .disabled(true)
    })
    tapArm("P2n", ZStack {
        Color.red.onTapGesture { Count.bump("P2n disabled over with NO gesture: under") }
        Color.blue.disabled(true)
    })
    // P2g/P2h: the P2e/P2f overlay with its gesture REMOVED. If P2g's enabled,
    // gesture-less contentShape already blocks, then P2f's swallow is the hit
    // shape's doing and not `.disabled`'s: disabling changes whether the
    // gesture runs, not whether the view is hit-testable.
    tapArm("P2g", ZStack {
        Color.red.onTapGesture { Count.bump("P2g control, clear+contentShape, NO gesture, ENABLED: under") }
        Color.clear.contentShape(Rectangle())
    })
    tapArm("P2h", ZStack {
        Color.red.onTapGesture { Count.bump("P2h clear+contentShape, NO gesture, .disabled(true): under") }
        Color.clear.contentShape(Rectangle()).disabled(true)
    })
    tapArm("P3", Button { Count.bump("P3 .plain Button enabled (control)") } label: { Color.blue }
        .buttonStyle(.plain))
    tapArm("P4", Button { Count.bump("P4 .plain Button .disabled(true)") } label: { Color.blue }
        .buttonStyle(.plain).disabled(true))
    tapArm("P5", Button("Default") { Count.bump("P5 default-style Button enabled (control)") }
        .frame(width: 200, height: 200))
    tapArm("P6", Button("Default") { Count.bump("P6 default-style Button .disabled(true)") }
        .disabled(true).frame(width: 200, height: 200))
    tapArm("P7", VStack { Color.blue.onTapGesture { Count.bump("P7 tap inside a disabled VStack") } }
        .disabled(true))
    tapArm("P8", Color.blue.onTapGesture { Count.bump("P8 .environment(isEnabled,true) inside .disabled(true)") }
        .environment(\.isEnabled, true).disabled(true))
    tapArm("P9", Color.blue.onTapGesture { Count.bump("P9 .environment(isEnabled,false), no .disabled") }
        .environment(\.isEnabled, false))
    for k in Count.hits.keys.sorted() where k.hasPrefix("P") { print("  \(k): \(Count.read(k))") }
    for k in ["P1 .disabled(true) onTapGesture", "P2 under a disabled tappable: over",
              "P2 under a disabled tappable: under", "P4 .plain Button .disabled(true)",
              "P6 default-style Button .disabled(true)", "P7 tap inside a disabled VStack",
              "P9 .environment(isEnabled,false), no .disabled",
              "P8 .environment(isEnabled,true) inside .disabled(true)",
              "P2n disabled over with NO gesture: under",
              "P2m control, ENABLED over with no gesture: under",
              "P2d control, Color.clear, no shape, no gesture: under",
              "P2e control, clear+contentShape+gesture ENABLED: under",
              "P2e control, clear+contentShape+gesture ENABLED: over",
              "P2f clear+contentShape+gesture .disabled(true): under",
              "P2f clear+contentShape+gesture .disabled(true): over",
              "P2g control, clear+contentShape, NO gesture, ENABLED: under",
              "P2h clear+contentShape, NO gesture, .disabled(true): under"] where Count.hits[k] == nil {
        print("  \(k): 0")
    }
}

// MARK: - K: focus and keys

@MainActor final class FocusModel: ObservableObject {
    @Published var disabled = false
}

struct FocusProbe: View {
    let label: String
    @ObservedObject var model: FocusModel
    @FocusState var focused: Bool
    let start: Bool
    var body: some View {
        EnabledReader(label: label)
            .focusable()
            .focused($focused)
            .onKeyPress { _ in Count.bump("\(label) onKeyPress"); return .handled }
            .disabled(model.disabled)
            .onAppear { if start { focused = true } }
            .onChange(of: focused) { _, v in Count.hits["\(label) focused"] = v ? 1 : 0 }
    }
}

/// Records what `isEnabled` the focusable view itself sees, so K2 can show the
/// `.disabled` change actually reached it (the control for K2's "after").
struct EnabledReader: View {
    let label: String
    @Environment(\.isEnabled) var isEnabled
    var body: some View {
        Count.hits["\(label) isEnabled"] = isEnabled ? 1 : 0
        return Color.blue
    }
}

/// K5..K8: a focused, RE-ENABLED child that ignores the key, inside a parent
/// whose own onKeyPress sits inside or outside `.disabled(true)`. Each handler
/// APPENDS ITS NAME to one ordered log, so the arm shows who ran and in what
/// order. The first version counted instead, with the parent returning
/// `.handled`, and the child read 0 in the enabled control too: the parent runs
/// FIRST on this system, so a parent that handles pre-empts the child. K5/K6
/// therefore return `.ignored` from the parent (so the child's reading is a
/// positive control that can move), and K7/K8 keep the `.handled` shape.
enum Seq { nonisolated(unsafe) static var log: [String: [String]] = [:] }

struct BubbleProbe: View {
    let label: String
    let parentDisabled: Bool
    let parentResult: KeyPress.Result
    @FocusState var focused: Bool
    var body: some View {
        VStack {
            Color.blue
                .focusable()
                .focused($focused)
                .onKeyPress { _ in Seq.log[label, default: []].append("child"); return .ignored }
                .environment(\.isEnabled, true)
        }
        .onKeyPress { _ in Seq.log[label, default: []].append("parent"); return parentResult }
        .disabled(parentDisabled)
        .onAppear { focused = true }
        .onChange(of: focused) { _, v in Count.hits["\(label) focused"] = v ? 1 : 0 }
    }
}

/// R: a press and a release with the `.disabled` value flipped between them,
/// through an `@ObservedObject` so the view re-renders mid-press.
@MainActor final class PressModel: ObservableObject { @Published var disabled = false }

struct PressProbe: View {
    let label: String
    let button: Bool
    @ObservedObject var model: PressModel
    var body: some View {
        if button {
            Button { Count.bump(label) } label: { Color.blue }.buttonStyle(.plain).disabled(model.disabled)
        } else {
            Color.blue.onTapGesture { Count.bump(label) }.disabled(model.disabled)
        }
    }
}

@MainActor func pressFlip(_ label: String, button: Bool, before: Bool, after: Bool) {
    let m = PressModel(); m.disabled = before
    let w = makeWindow(PressProbe(label: label, button: button, model: m))
    func ev(_ t: NSEvent.EventType) -> NSEvent {
        NSEvent.mouseEvent(with: t, location: center, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                           windowNumber: w.windowNumber, context: nil, eventNumber: 0,
                           clickCount: 1, pressure: t == .leftMouseDown ? 1 : 0)!
    }
    w.sendEvent(ev(.leftMouseDown))
    spin(0.05)
    m.disabled = after
    spin(0.2)
    w.sendEvent(ev(.leftMouseUp))
    spin()
    print("  \(label): \(Count.read(label))")
    w.orderOut(nil)
}

@MainActor func armR() {
    print("--- R: press, flip .disabled, release (same timing in every arm)")
    for button in [true, false] {
        let k = button ? "Button(.plain)" : "onTapGesture"
        pressFlip("R0 \(k) enabled throughout (control)", button: button, before: false, after: false)
        pressFlip("R1 \(k) pressed disabled, released enabled", button: button, before: true, after: false)
        pressFlip("R2 \(k) pressed enabled, released disabled", button: button, before: false, after: true)
        pressFlip("R3 \(k) disabled throughout", button: button, before: true, after: true)
    }
}

@MainActor func armK() {
    print("--- K: focus and key handling (focus requested in onAppear)")
    for (label, disabled) in [("K0 enabled (control)", false), ("K1 .disabled(true) from the start", true)] {
        let m = FocusModel(); m.disabled = disabled
        let w = makeWindow(FocusProbe(label: label, model: m, start: true))
        spin(0.3)
        key(w, "a")
        print("  \(label): focused=\(Count.hits["\(label) focused"].map(String.init) ?? "never changed") " +
              "onKeyPress=\(Count.read("\(label) onKeyPress")) firstResponder=\(type(of: w.firstResponder as Any))")
        w.orderOut(nil)
    }
    let label = "K2 focused, then disabled"
    let m = FocusModel()
    let w = makeWindow(FocusProbe(label: label, model: m, start: true))
    spin(0.3)
    let before = Count.hits["\(label) focused"]
    let keysBefore = Count.read("\(label) onKeyPress")
    key(w, "a")
    print("  \(label): control, onKeyPress while still enabled=\(Count.read("\(label) onKeyPress") - keysBefore)")
    m.disabled = true
    spin(0.3)
    Count.hits["\(label) onKeyPress"] = 0
    key(w, "a")
    print("  \(label): focused before=\(before.map(String.init) ?? "never changed") " +
          "after=\(Count.hits["\(label) focused"].map(String.init) ?? "never changed") " +
          "onKeyPress after disabling=\(Count.read("\(label) onKeyPress")) " +
          "isEnabled seen by the focused view after disabling=\(Count.read("\(label) isEnabled"))")
    m.disabled = false
    spin(0.3)
    print("  \(label), re-enabled: focused=\(Count.hits["\(label) focused"].map(String.init) ?? "never changed")")
    w.orderOut(nil)

    for (l, disabled, result) in [
        ("K5 bubble, parent enabled, parent .ignored (control)", false, KeyPress.Result.ignored),
        ("K6 bubble, parent .disabled(true), child re-enabled, parent .ignored", true, KeyPress.Result.ignored),
        ("K7 bubble, parent enabled, parent .handled", false, KeyPress.Result.handled),
        ("K8 bubble, parent .disabled(true), child re-enabled, parent .handled", true, KeyPress.Result.handled)] {
        let w = makeWindow(BubbleProbe(label: l, parentDisabled: disabled, parentResult: result))
        spin(0.3)
        key(w, "a")
        print("  \(l): child focused=\(Count.hits["\(l) focused"].map(String.init) ?? "never changed") " +
              "handler order=\(Seq.log[l] ?? [])")
        w.orderOut(nil)
    }

    for (l, disabled) in [("K3 keyboardShortcut cmd-k enabled (control)", false),
                          ("K4 keyboardShortcut cmd-k .disabled(true)", true)] {
        let w = makeWindow(Button("Shortcut") { Count.bump(l) }
            .keyboardShortcut("k", modifiers: .command).disabled(disabled))
        key(w, "k", modifiers: .command)
        print("  \(l): \(Count.read(l))")
        w.orderOut(nil)
    }
}

// MARK: - S: scrolling — attempted, NOT measured
//
// The first version of this file had a scroll arm (one pixel-unit wheel event
// through `sendEvent`), and a scratch copy tried four strategies (window
// `sendEvent` and a direct `scrollWheel(with:)` on the hit view, each with and
// without continuous began/changed/ended phases). Every one left an ENABLED
// ScrollView's
// content at minY 0, so its positive control failed and a disabled reading
// would have meant nothing. Whether `.disabled` stops wheel scrolling on macOS
// is therefore not established by this file.

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.activate(ignoringOtherApps: true)
    armP(); armK(); armR()
}
