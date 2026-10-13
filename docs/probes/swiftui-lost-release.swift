// SwiftUI probe: a lost mouse-up, then a second primary press on the same view
// (item C26, ruling GC-A in docs/superpowers/2026-10-12-continuing-press-cancel-decisions.md).
//
// The question: when a DragGesture has reported onChanged and its mouseUp never
// arrives, what does the next mouseDown on the same view do to the first drag
// (onEnded? a GestureState reset?) and does the second press start a new drag?
// SwiftUI's DragGesture has no onCancelled; the only observable of a cancel is
// a GestureState(reset:) closure ("reset") and the absence of "end".
//
// HOW TO RUN:  xcrun swiftc docs/probes/swiftui-lost-release.swift -o /tmp/lr && /tmp/lr
// THE INSTRUMENT is swiftui-gesture-presentation-arena.swift's (NSEvent through
// NSWindow.sendEvent, FirstMouseHost, spin between events).
// POSITIVE CONTROL: L0 (an ordinary drag) must read chg, end and reset.
// NOT MEASURED: a double-click beside the drag. A first D0 arm (simultaneous
// SpatialTapGesture(count: 2), two quick clicks) read "-" even for the drag, so
// the instrument was broken for it and the arm was removed, not read.
//
// RECORDED 2026-10-12, macOS 27.0.1, Swift 6.4, screen LOCKED (lock probe:
// CGSSessionScreenIsLocked = 1, displayAsleep main: 1). Run twice, stdout
// byte-identical, stderr empty.
//
//   --- L: lost release (no mouseUp), then a primary press on the SAME view
//     L0 control: down, drag, up: chg,chg,reset,end
//     L1 down, drag, [release lost], down, up: chg,chg,reset,chg,reset,end
//     L2 down, drag, [release lost], down, drag, up: chg,chg,reset,chg,chg,reset,end
//     L3 down, drag, [release lost], mouseMoved, then nothing: chg,chg
//
// RESULT. The second press CANCELS the first drag (its GestureState resets, NO
// "end") and then STARTS A NEW DRAG that ends normally (L1, L2: reset, chg ...
// reset, end). A mouseMoved with no button cancels nothing (L3).
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
        return lines.isEmpty ? "-" : lines.joined(separator: ",")
    }
}

@MainActor func spin(_ s: Double = 0.15) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

@MainActor func makeWindow<V: View>(_ view: V, size: CGFloat = 200) -> NSWindow {
    let w = NSWindow(contentRect: CGRect(x: 200, y: 200, width: size, height: size),
                     styleMask: [.titled], backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    w.contentView = FirstMouseHost(rootView: view)
    w.makeKeyAndOrderFront(nil)
    spin(0.6)
    return w
}

@MainActor func mouse(_ w: NSWindow, _ t: NSEvent.EventType, _ p: CGPoint) {
    let e = NSEvent.mouseEvent(with: t, location: p, modifierFlags: [],
                               timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: w.windowNumber, context: nil, eventNumber: 0,
                               clickCount: 1, pressure: t == .leftMouseUp ? 0 : 1)!
    w.sendEvent(e)
}

@MainActor func click(_ w: NSWindow, at p: CGPoint) {
    mouse(w, .leftMouseDown, p); spin(0.05)
    mouse(w, .leftMouseUp, p); spin(0.6)
}


struct Target: View {
    @GestureState(reset: { _, _ in Log.add("reset") }) var held = false
    let tap2: Bool
    var body: some View {
        let drag = DragGesture(minimumDistance: 0)
            .updating($held) { _, s, _ in s = true }
            .onChanged { _ in Log.add("chg") }
            .onEnded { _ in Log.add("end") }
        Color.green.frame(width: 100, height: 100)
            .gesture(drag)
            .modifier(Tap2(on: tap2))
    }
}
struct Tap2: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on { content.simultaneousGesture(SpatialTapGesture(count: 2).onEnded { _ in Log.add("tap2") }) } else { content }
    }
}

@MainActor func mouseN(_ w: NSWindow, _ t: NSEvent.EventType, _ p: CGPoint, count: Int = 1) {
    let e = NSEvent.mouseEvent(with: t, location: p, modifierFlags: [],
                               timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: w.windowNumber, context: nil, eventNumber: 0,
                               clickCount: count, pressure: t == .leftMouseUp ? 0 : 1)!
    w.sendEvent(e)
}

@MainActor func arm(_ label: String, tap2: Bool = false, _ steps: (NSWindow, CGPoint) -> Void) {
    _ = Log.take()
    let w = makeWindow(Target(tap2: tap2), size: 100)
    let c = CGPoint(x: 50, y: 50)
    steps(w, c)
    spin(0.6)
    print("  \(label): \(Log.take())")
    w.orderOut(nil)
}

@MainActor func run() {
    let c2 = { (p: CGPoint) in CGPoint(x: p.x + 10, y: p.y) }
    print("--- L: lost release (no mouseUp), then a primary press on the SAME view")
    arm("L0 control: down, drag, up") { w, c in
        mouseN(w, .leftMouseDown, c); spin(0.05); mouseN(w, .leftMouseDragged, c2(c)); spin(0.05); mouseN(w, .leftMouseUp, c2(c)) }
    arm("L1 down, drag, [release lost], down, up") { w, c in
        mouseN(w, .leftMouseDown, c); spin(0.05); mouseN(w, .leftMouseDragged, c2(c)); spin(0.05)
        mouseN(w, .leftMouseDown, c); spin(0.05); mouseN(w, .leftMouseUp, c) }
    arm("L2 down, drag, [release lost], down, drag, up") { w, c in
        mouseN(w, .leftMouseDown, c); spin(0.05); mouseN(w, .leftMouseDragged, c2(c)); spin(0.05)
        mouseN(w, .leftMouseDown, c); spin(0.05); mouseN(w, .leftMouseDragged, c2(c)); spin(0.05); mouseN(w, .leftMouseUp, c2(c)) }
    arm("L3 down, drag, [release lost], mouseMoved, then nothing") { w, c in
        mouseN(w, .leftMouseDown, c); spin(0.05); mouseN(w, .leftMouseDragged, c2(c)); spin(0.05); mouseN(w, .mouseMoved, c) }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.activate(ignoringOtherApps: true)
    run()
}
exit(0)
