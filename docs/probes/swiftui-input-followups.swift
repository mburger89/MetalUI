// SwiftUI/AppKit probe: input follow-ups (rulings IF-* in
// docs/superpowers/2026-10-10-input-followups-decisions.md; spec
// docs/superpowers/specs/2026-10-10-input-followups-design.md).
//
// HOW TO RUN (compiled form, as `swiftui-input-apis.swift`):
//
//   xcrun swiftc docs/probes/swiftui-input-followups.swift -o /tmp/if-probe && /tmp/if-probe
//
// THE INSTRUMENT is `swiftui-input-apis.swift`'s: a `KeyWindow` (reads as key)
// hosting an `NSHostingView` that accepts the first mouse, `NSEvent`s through
// `NSWindow.sendEvent` with a run-loop spin between events.
//
// ARMS AND THEIR CONTROLS.
//   M  — onModifierKeysChanged(mask:initial:_:). M0 reads what `initial: true`
//        reports with nothing pressed; M1 sends a flagsChanged (shift down, up)
//        through `sendEvent`; M2 the same with `mask: .command` (a SEPARATING
//        arm: shift must not fire); M3 sends ⌘ then ⇧ held and ⌘ released;
//        M4 `initial: false`. The positive control for the delivery path is
//        M1 itself: if it reads "-" the instrument did not deliver and M2..M4
//        prove nothing.
//   D  — click counts: does SwiftUI's `TapGesture(count: 2)` read the event's
//        clickCount or time the clicks itself? D1 (control): two clicks 50 ms
//        apart, clickCount 1 then 2. D2: clickCount 1 then 2 but 0.8 s apart
//        (past the system interval). D3: two clicks 50 ms apart, BOTH
//        clickCount 1. D4: two clicks 0.3 s apart, clickCount 1 then 2.
//   C  — cancellation: a `DragGesture(minimumDistance: 0)` with `.updating`
//        into a `@GestureState`, `.onChanged` and `.onEnded`, each line logged.
//        C1 (control) press, move, release. C2 press, move, then the gesture is
//        DISABLED (`including: .none`), then release. C3 press, move, the view
//        is REMOVED, then release. C4 press, move, the window resigns key,
//        release. C5 press, move, then a second press (no release) then
//        release. The body's `s=` line shows the GestureState at each render.
//   (No arm for SpatialTapGesture.Value / DragGesture.Value fields: the
//   interface census below is the evidence — `location` only; DragGesture.Value
//   has time, location, startLocation, translation, velocity, predictedEnd*.)
//
// RECORDED 2026-10-10 by the input-follow-ups designer, macOS 27.0.1, Apple
// Swift 6.4, Xcode-beta SDK, screen UNLOCKED (lock probe: no
// CGSSessionScreenIsLocked line, `displayAsleep main: 0`). Compiled form run
// twice: stdout byte-identical (20 lines), exit 0, stderr empty.
//
// RESULT.
//   M  NOT MEASURED. Every M arm reads "-", INCLUDING M0 (`initial: true`,
//      which must report once at appearance) and the NSApp.sendEvent arm M5;
//      M6 (a CGEvent flagsChanged posted to the session tap, with an
//      `NSEvent.addLocalMonitorForEvents(.flagsChanged)` as the delivery
//      control) reads "-" too, so a posted event never reaches this process:
//      the instrument cannot drive SwiftUI's hook, and no claim about its
//      timing rests on these lines (practice: a green "-" is a broken
//      instrument, not an answer). What IS evidence is the interface census:
//      `onModifierKeysChanged(mask: EventModifiers = .all, initial: Bool =
//      true, _ action: (old, new) -> Void)`, macOS 15, `(old, new)` both
//      EventModifiers.
//   D  SwiftUI's `SpatialTapGesture(count: 2)` TIMES THE CLICKS ITSELF and
//      reads neither the event's clickCount nor the system interval: D3 (both
//      events clickCount 1, 50 ms apart) fires; D4 (clickCount 1 then 2,
//      0.4 s apart, inside NSEvent.doubleClickInterval 0.5) does NOT; D2 (0.8 s)
//      does not; D1 (control, 50 ms) fires. So SwiftUI's own sequence window is
//      under 0.4 s — MetalUI's 0.33 s (`tapSequenceDeferral`, IX-C) is
//      SwiftUI's, not a divergence; the system interval is not SwiftUI's.
//   C  A cancelled DragGesture reports NO onEnded and resets its @GestureState
//      to its initial value: C2 (gesture disabled mid-drag) and C3 (view
//      removed mid-drag) read `updating | changed ... body s=2 | body s=2 |
//      body s=0` with no "ended" — the reset is applied at the next event
//      (the release), not at the cancelling change. C1 (control) reads
//      "ended" then `s=0`. A window that resigns key mid-drag (C4) is NOT a
//      cancellation: the release still ends the drag. A second press with no
//      release (C5) does not restart the gesture: `updating`/`changed` run for
//      it and the one release ends once.
//   Interface census (SwiftUI.swiftinterface): `SpatialTapGesture.Value` has
//      `location` only; `DragGesture.Value` has `time`, `location`,
//      `startLocation`, `translation`, `velocity`, `predictedEnd*` — no
//      modifiers, no click count. `GestureState<Value>` + `Gesture.updating(
//      _:body:)` (body: (Value, inout State, inout Transaction)).
//   B  Wheel latching: NOT PROBED. Synthetic `NSWindow.sendEvent` events skip
//      the window server's routing (where any latch would live), and the M6
//      control shows posted events do not arrive in this process. gpui is not read
//      here: see the decisions doc (IF-C) for what is and is not claimed.
//

import SwiftUI
import AppKit

final class FirstMouseHost<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    static func add(_ s: String) { lines.append(s) }
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

// MARK: - M: onModifierKeysChanged

struct ModView: View {
    let mask: EventModifiers
    let initial: Bool
    var body: some View {
        Color.blue.frame(width: side, height: side).focusable()
            .onModifierKeysChanged(mask: mask, initial: initial) { old, new in
                Log.add("\(name(old))->\(name(new))")
            }
    }
}

@MainActor func modArm(_ label: String, mask: EventModifiers, initial: Bool,
                       _ steps: (NSWindow) -> Void) {
    let w = makeWindow(ModView(mask: mask, initial: initial))
    w.makeFirstResponder(w.contentView)
    spin(0.3)
    let atAppear = Log.take()
    steps(w)
    print("    \(label) mask=\(name(mask)) initial=\(initial): appear=\(atAppear) then=\(Log.take())")
    w.close()
}

// MARK: - D: click counts

struct TapView: View {
    var body: some View {
        Color.green.frame(width: side, height: side)
            .gesture(SpatialTapGesture(count: 2).onEnded { v in Log.add("tap2@\(Int(v.location.x)),\(Int(v.location.y))") })
    }
}

@MainActor func tapArm(_ label: String, gap: Double, counts: (Int, Int)) {
    let w = makeWindow(TapView())
    let pt = wp(100, 100)
    mouse(w, .leftMouseDown, pt, clicks: counts.0); mouse(w, .leftMouseUp, pt, clicks: counts.0)
    spin(gap)
    mouse(w, .leftMouseDown, pt, clicks: counts.1); mouse(w, .leftMouseUp, pt, clicks: counts.1)
    spin(0.8)
    print("    \(label) gap=\(gap)s counts=\(counts): \(Log.take())")
    w.close()
}

// MARK: - C: cancellation

struct DragView: View {
    @GestureState var s: Int = 0
    var enabled: Bool
    var present: Bool
    var body: some View {
        let _ = Log.add("body s=\(s)")
        Group {
            if present {
                Color.orange.frame(width: side, height: side)
                    .gesture(DragGesture(minimumDistance: 0)
                        .updating($s) { v, st, _ in st += 1; Log.add("updating") }
                        .onChanged { _ in Log.add("changed") }
                        .onEnded { _ in Log.add("ended") },
                        including: enabled ? .all : .none)
            } else {
                Color.gray.frame(width: side, height: side)
            }
        }
    }
}

final class Model: ObservableObject { @Published var enabled = true; @Published var present = true }
struct DragHost: View {
    @ObservedObject var m: Model
    var body: some View { DragView(enabled: m.enabled, present: m.present) }
}

@MainActor func dragArm(_ label: String, _ mid: (NSWindow, Model) -> Void) {
    let m = Model()
    let w = makeWindow(DragHost(m: m))
    _ = Log.take()
    mouse(w, .leftMouseDown, wp(50, 50)); spin(0.1)
    mouse(w, .leftMouseDragged, wp(70, 60)); spin(0.1)
    mid(w, m)
    spin(0.2)
    mouse(w, .leftMouseUp, wp(70, 60)); spin(0.2)
    print("    \(label): \(Log.take())")
    w.close()
}

// MARK: - Run

@MainActor func run() {
  _ = NSApplication.shared
  NSApp.setActivationPolicy(.regular)
  NSApp.activate(ignoringOtherApps: true)
  spin(0.5)
  print("--- M: onModifierKeysChanged (macOS 15 interface: mask default .all, initial default true)")
  modArm("M0 appear only", mask: .all, initial: true) { _ in }
  modArm("M1 shift down, up", mask: .all, initial: false) { w in
      flags(w, [.shift], key: 56); flags(w, [], key: 56)
  }
  modArm("M2 shift down, up", mask: .command, initial: false) { w in
      flags(w, [.shift], key: 56); flags(w, [], key: 56)
  }
  modArm("M3 cmd, cmd+shift, shift", mask: .all, initial: false) { w in
      flags(w, [.command], key: 55); flags(w, [.command, .shift], key: 56); flags(w, [.shift], key: 55)
  }
  modArm("M3b cmd, cmd+shift, shift", mask: .command, initial: false) { w in
      flags(w, [.command], key: 55); flags(w, [.command, .shift], key: 56); flags(w, [.shift], key: 55)
  }
  modArm("M4 initial false, appear", mask: .all, initial: false) { _ in }

  viaApp = true
  modArm("M5 via NSApp.sendEvent shift down, up", mask: .all, initial: true) { w in
    flags(w, [.shift], key: 56); flags(w, [], key: 56)
  }
  viaApp = false
  // M6: a real session-level flagsChanged (CGEvent posted to the session tap),
  // with a local monitor as the delivery control.
  do {
    let w = makeWindow(ModView(mask: .all, initial: false))
    _ = Log.take()
    let mon = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { e in Log.add("monitor:\(name(EventModifiers(rawValue: 0)))\(e.modifierFlags.contains(.shift))"); return e }
    for down in [true, false] {
      let ev = CGEvent(keyboardEventSource: nil, virtualKey: 56, keyDown: down)!
      ev.type = .flagsChanged
      ev.flags = down ? .maskShift : []
      ev.post(tap: .cgSessionEventTap)
      spin(0.4)
    }
    if let mon { NSEvent.removeMonitor(mon) }
    print("    M6 session-tap flagsChanged shift down, up: \(Log.take())")
    w.close()
  }
  print("--- D: TapGesture count 2 vs the event's clickCount (NSEvent.doubleClickInterval=\(NSEvent.doubleClickInterval))")
  tapArm("D1 control", gap: 0.05, counts: (1, 2))
  tapArm("D2 late", gap: 0.8, counts: (1, 2))
  tapArm("D3 counts lie", gap: 0.05, counts: (1, 1))
  tapArm("D4 inside system, outside 0.33", gap: 0.4, counts: (1, 2))

  print("--- C: cancellation of a DragGesture(minimumDistance: 0) with .updating($s)")
  dragArm("C1 control") { _, _ in }
  dragArm("C2 disabled mid-drag") { _, m in m.enabled = false }
  dragArm("C3 removed mid-drag") { _, m in m.present = false }
  dragArm("C4 resign key mid-drag") { w, _ in w.resignKey(); NSApp.deactivate() }
  dragArm("C5 second press mid-drag") { w, _ in mouse(w, .leftMouseDown, wp(10, 10)) }
}
MainActor.assumeIsolated { run() }
