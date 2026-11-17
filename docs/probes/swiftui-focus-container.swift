// SwiftUI probe: `.focused(_:)` / `.focused(_:equals:)` on a container that is NOT itself focusable (Alloy's pane
// wrapper around a focusable terminal; rulings `FW-A`..`FW-C` in docs/superpowers/2026-11-17-focus-within-decisions.md).
// Question: does the container's state read true while focus is within it, and does writing it move focus in?
//
// HOW TO RUN (SA-O's compiled form):
//
//   xcrun swiftc -swift-version 6 docs/probes/swiftui-focus-container.swift -o /tmp/fc-probe
//   /tmp/fc-probe > /tmp/fc-1.txt; /tmp/fc-probe > /tmp/fc-2.txt; cmp /tmp/fc-1.txt /tmp/fc-2.txt
//
// INSTRUMENT. `swiftui-initial-focus.swift`'s harness (a `KeyWindow` over a `FirstMouseHost`, a 0.3 s run-loop spin
// before `settled`; whatever is logged before `settled` is the first-draw seat). `tickN` writes happen from an
// `onChange(of: tick)` in the view. F0/F1/F2/F4/F5 log `container=`/`inner=`/`c=`/`a=`/`b=`/`o=`; F3 logs `pane=`/`ia=`/`ib=`.
//
// RECORDED 2026-11-17, macOS 27.2.1, Apple Swift 6.4.2, run twice: stdout byte-identical (9 lines, shasum
// 245228a16b85282c6f2c35cff6999b07a064998b), exit 0.
//
//   --- F: container focus-within
//     (arm = container Bool on non-focusable VStack unless noted; tick1: inner=true; tick2: container=false; tick3: container=true)
//     F0 VStack.focused(container) { focusable.focused(inner) }: container=true,inner=true,settled,container=false,inner=false,container=true,inner=true
//     F1 VStack.focusable().focused(container) { focusable.focused(inner) }: container=true,settled,inner=true,container=false,inner=false,container=true
//     F2 container only (inner 2 focusables, 2nd unbound): tick3 first only: container=true,inner=true,settled
//     F3 two panes equals: tick1 ia, tick2 ib, tick3 pane=.a, tick4 pane=.b, tick5 pane=nil: pane=Optional(fprobe.Two.P.a),ia=true,settled,pane=Optional(fprobe.Two.P.b),ia=false,ib=true,pane=Optional(fprobe.Two.P.a),ia=true,ib=false,pane=Optional(fprobe.Two.P.b),ia=false,ib=true,pane=nil,ib=false
//     (F4: TextField inner)
//     F4 VStack.focused(container) { TextField.focused(inner) }: initial: container=true,inner=true,settled
//     F5 c{a,b}, o outside. t1 b=true, t2 c=true, t3 o=true, t4 c=false (o focused), t5 c=true: c=true,a=true,settled,a=false,b=true,a=true,b=false,c=false,a=false,o=true,c=true,a=true,o=false
//
// READING.
//  F0  The first draw seats the first focusable (inside the VStack): `container=true,inner=true` BEFORE settled: the
//      non-focusable container reads true while focus is within it. tick2 `container=false` clears focus (inner=false);
//      tick3 `container=true` moves focus to the first focusable descendant (inner=true).
//  F1  A `.focusable()` container takes the seat itself; its state is true, the inner's is not (unchanged rule).
//  F3  Two panes on one `FocusState<P?>`: `ib = true` reads `pane=.b`; `pane = .a` focuses ia; `pane = nil` clears focus.
//  F5  Container {a, b} with `o` outside. Focus on b: `c` stays true (a=false,b=true). tick2 `c = true` while focus is
//      ALREADY within, on b: focus moves to the FIRST descendant (`a=true,b=false`). tick3 `o = true`: c=false. tick4
//      `c = false` while focus is outside: nothing (focus stays on o). tick5 `c = true`: a=true, o=false.
//
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
    var dummy = 0
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

struct Pane: View {
    @FocusState var container: Bool
    @FocusState var inner: Bool
    let kind: Int
    var body: some View {
        Group {
            if kind == 0 {
                VStack(spacing: 0) { Color.blue.focusable().focused($inner) }.focused($container)
            } else if kind == 1 {
                VStack(spacing: 0) { TextField("t", text: .constant("")).focused($inner) }.focused($container)
            } else {
                VStack(spacing: 0) { Color.blue.focusable().focused($inner) }.focusable().focused($container)
            }
        }
        .onChange(of: container) { _, v in Log.add("container=\(v)") }
        .onChange(of: inner) { _, v in Log.add("inner=\(v)") }
    }
    func focusInner() { inner = true }
}
enum Shared2 {}
struct Two: View {
    enum P: Hashable { case a, b }
    @FocusState var pane: P?
    @FocusState var ia: Bool
    @FocusState var ib: Bool
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) { Color.blue.focusable().focused($ia) }.focused($pane, equals: .a)
            VStack(spacing: 0) { Color.green.focusable().focused($ib) }.focused($pane, equals: .b)
        }
        .onChange(of: pane) { _, v in Log.add("pane=\(String(describing: v))") }
        .onChange(of: ia) { _, v in Log.add("ia=\(v)") }
        .onChange(of: ib) { _, v in Log.add("ib=\(v)") }
        .onChange(of: Shared.ctl.tick) { _, t in
            if t == 1 { ia = true }
            if t == 2 { ib = true }
            if t == 3 { pane = .a }
            if t == 4 { pane = .b }
            if t == 5 { pane = nil }
        }
    }
}
struct ThreeWrite: View {
    @FocusState var container: Bool
    @FocusState var inner: Bool
    let kind: Int
    var body: some View {
        Group {
            if kind == 0 { VStack(spacing: 0) { Color.red.focusable().focused($inner) }.focused($container) }
            else if kind == 1 { VStack(spacing: 0) { Color.red.focusable().focused($inner) }.focusable().focused($container) }
            else { VStack(spacing: 0) { Color.red.focusable().focused($inner); Color.blue.focusable() }.focused($container) }
        }
        .onChange(of: container) { _, v in Log.add("container=\(v)") }
        .onChange(of: inner) { _, v in Log.add("inner=\(v)") }
        .onChange(of: Shared.ctl.tick) { _, t in
            if t == 1 { inner = true }
            if t == 2 { container = false }
            if t == 3 { container = true }
        }
    }
}
struct Kind: View {
    let k: Int
    var body: some View {
        switch k {
        case 0: ThreeWrite(kind: 0)
        case 1: ThreeWrite(kind: 1)
        case 2: ThreeWrite(kind: 2)
        default: EmptyView()
        }
    }
}


struct Five: View {
    @FocusState var c: Bool
    @FocusState var a: Bool
    @FocusState var b: Bool
    @FocusState var o: Bool
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) { Color.red.frame(height: 40).focusable().focused($a); Color.blue.frame(height: 40).focusable().focused($b) }.focused($c)
            Color.green.focusable().focused($o)
        }
        .onChange(of: c) { _, v in Log.add("c=\(v)") }
        .onChange(of: a) { _, v in Log.add("a=\(v)") }
        .onChange(of: b) { _, v in Log.add("b=\(v)") }
        .onChange(of: o) { _, v in Log.add("o=\(v)") }
        .onChange(of: Shared.ctl.tick) { _, t in
            if t == 1 { b = true }
            if t == 2 { c = true }
            if t == 3 { o = true }
            if t == 4 { c = false }
            if t == 5 { c = true }
        }
    }
}
@MainActor func tick(_ n: Int) { Shared.ctl.tick = n; spin(0.3) }

_ = NSApplication.shared
print("--- F: container focus-within")
print("  (arm = container Bool on non-focusable VStack unless noted; tick1: inner=true; tick2: container=false; tick3: container=true)")
arm("F0 VStack.focused(container) { focusable.focused(inner) }", ThreeWrite(kind: 0)) { _ in tick(1); tick(2); tick(3) }
arm("F1 VStack.focusable().focused(container) { focusable.focused(inner) }", ThreeWrite(kind: 1)) { _ in tick(1); tick(2); tick(3) }
arm("F2 container only (inner 2 focusables, 2nd unbound): tick3 first only", ThreeWrite(kind: 2)) { _ in tick(3) }
arm("F3 two panes equals: tick1 ia, tick2 ib, tick3 pane=.a, tick4 pane=.b, tick5 pane=nil", Two()) { _ in tick(1); tick(2); tick(3); tick(4); tick(5) }
print("  (F4: TextField inner)")
arm("F4 VStack.focused(container) { TextField.focused(inner) }: initial", Pane(kind: 1))

arm("F5 c{a,b}, o outside. t1 b=true, t2 c=true, t3 o=true, t4 c=false (o focused), t5 c=true", Five()) { _ in tick(1); tick(2); tick(3); tick(4); tick(5) }
RunLoop.main.run(until: Date().addingTimeInterval(0.1))
