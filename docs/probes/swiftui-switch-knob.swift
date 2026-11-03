// SwiftUI probe: does the `.switch` toggle's knob slide, and on which kinds of change? (R4-1 PR A, ruling
// `SR-D`, divergence 885, `BY-I`). The row's old reading was "unmeasured: the offscreen capture is blind to
// motion". This probe reads the `presentation()` layer positions of every layer under the hosted switch,
// tick by tick on the main run loop, so motion shows as more than one distinct value.
//
// HOW TO RUN (compiled form, SA-O; needs an unlocked screen, appkit-screen-lock-state.swift):
//
//   xcrun swiftc docs/probes/swiftui-switch-knob.swift -o /tmp/knob-probe && /tmp/knob-probe 2>&1 | grep -v 'Connection\]'
//
// ARMS.
//   K0  geometry: the hosted `.switch` toggle's `fittingSize` and the frame of every layer, off and on, settled.
//   K1  an ACCESSIBILITY PRESS (`accessibilityPerformPress`: the closest a probe gets to a click, no transaction
//       written by the app), off -> on.
//   K2  a binding write with NO animation, off -> on, from outside (`model.on = true`).
//   K3  the same write inside `withAnimation(.linear(duration: 1))`, the control arm: motion must show.
//   K4  a plain `.checkbox` toggle written the same way as K2: the separating arm (the checkbox snaps).
// Each arm samples the presentation x of every layer for 0.6 s at ~60 Hz and prints the distinct x sequence of the
// layer whose x varies most. "moved" means that layer took 3 or more distinct x values.
//
// RECORDED OUTPUT: the block at the end of this file.

import AppKit
import SwiftUI
import QuartzCore

setvbuf(stdout, nil, _IOLBF, 0)
@MainActor func spin(_ s: Double) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

@Observable @MainActor final class Model { var on = false }
nonisolated(unsafe) let model = MainActor.assumeIsolated { Model() }

struct SwitchRoot: View {
    @Bindable var m: Model
    let checkbox: Bool
    var body: some View {
        if checkbox { Toggle("Wi-Fi", isOn: $m.on).toggleStyle(.checkbox).padding(10) }
        else { Toggle("Wi-Fi", isOn: $m.on).toggleStyle(.switch).padding(10) }
    }
}

var windows: [NSWindow] = []
@MainActor func hostWindow(checkbox: Bool) -> NSHostingView<SwitchRoot> {
    model.on = false
    let h = NSHostingView(rootView: SwitchRoot(m: model, checkbox: checkbox))
    h.frame = CGRect(x: 0, y: 0, width: 200, height: 60)
    let w = NSWindow(contentRect: h.frame, styleMask: [.titled], backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    w.contentView = h
    w.setFrameOrigin(NSPoint(x: 100, y: 100))
    w.orderFrontRegardless(); w.makeKey()
    h.layoutSubtreeIfNeeded()
    windows.append(w)
    spin(0.5)
    return h
}

func layers(_ l: CALayer, path: String = "", _ out: inout [(String, CALayer)]) {
    out.append((path + "/" + String(describing: type(of: l)), l))
    for (i, s) in (l.sublayers ?? []).enumerated() { layers(s, path: path + "/" + String(describing: type(of: l)) + "#\(i)", &out) }
}

@MainActor func sample(_ label: String, _ h: NSView, _ act: () -> Void) {
    var ls: [(String, CALayer)] = []
    layers(h.layer!, &ls)
    var series: [[CGFloat]] = Array(repeating: [], count: ls.count)
    var times: [Double] = []
    let t0 = Date()
    func take() {
        times.append(Date().timeIntervalSince(t0))
        for (i, e) in ls.enumerated() {
            let p = e.1.presentation() ?? e.1
            series[i].append((p.position.x * 100).rounded() / 100)
        }
    }
    take()
    act()
    let end = Date().addingTimeInterval(0.6)
    while Date() < end { spin(1.0 / 60); take() }
    var best = (-1, 0)
    var rows: [String] = []
    for (i, s) in series.enumerated() {
        var distinct: [CGFloat] = []
        for v in s where distinct.last != v { distinct.append(v) }
        if distinct.count > 1 { rows.append("    \(ls[i].0): \(distinct.prefix(14))\(distinct.count > 14 ? "... (\(distinct.count) values)" : "")") }
        if distinct.count > best.1 { best = (i, distinct.count) }
    }
    print("=== \(label): the most-varying layer took \(best.1) distinct x values -> \(best.1 >= 3 ? "MOVED (slid)" : "snapped")")
    for r in rows { print(r) }
    if best.0 >= 0 {
        // the settle time: the first sample at which the best layer reaches its final value (+-0.05)
        let s = series[best.0]
        let final = s.last!
        if let i = s.firstIndex(where: { abs($0 - final) < 0.05 }) { print("    settles (within 0.05 of \(final)) at t=\(String(format: "%.3f", times[i] - times[1])) s after the first sample following the change; peak x = \(s.max()!)") }
    }
}

@MainActor func run() {
    NSApplication.shared.setActivationPolicy(.regular)
    NSApp.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))

    let h0 = hostWindow(checkbox: false)
    print("K0 .switch fittingSize \(h0.fittingSize)")
    var ls: [(String, CALayer)] = []
    layers(h0.layer!, &ls)
    for (n, l) in ls { print("   \(n) frame=\(l.frame)") }

    let h1 = hostWindow(checkbox: false)
    func press(_ o: NSObject) -> Bool {
        if let kids = o.value(forKey: "accessibilityChildren") as? [Any] {
            for k in kids.compactMap({ $0 as? NSObject }) {
                if (k.value(forKey: "accessibilityRole") as? String) == "AXCheckBox", k.responds(to: Selector(("accessibilityPerformPress"))) {
                    return (k.perform(Selector(("accessibilityPerformPress")))?.takeUnretainedValue() as? Bool) ?? true
                }
                if press(k) { return true }
            }
        }
        return false
    }
    sample("K1 accessibility press (no app transaction), off -> on", h1) { print("   pressed=\(press(h1)) model.on=\(model.on)") }

    let h2 = hostWindow(checkbox: false)
    sample("K2 binding write, no animation, off -> on", h2) { model.on = true }

    let h3 = hostWindow(checkbox: false)
    sample("K3 withAnimation(.linear(duration: 1)) write, off -> on", h3) { withAnimation(.linear(duration: 1)) { model.on = true } }

    let h4 = hostWindow(checkbox: true)
    sample("K4 .checkbox binding write, no animation (separating arm)", h4) { model.on = true }
}

MainActor.assumeIsolated { run() }

// RECORDED 2026-11-03 (R4-1 PR A, ruling `SR-D`; macOS 27.2, Apple Swift 6.4, screen unlocked, compiled form; the K lines are
// stable to the printed precision, settle times vary by a frame).
//   K0 .switch Toggle("Wi-Fi") fittingSize (115.0, 44.0); the switch control is 54 x 24 (frame (51,10,54,24) in a 10-padded host);
//      its knob layers are 32 x 20 at x = 2 (off) and x = 20 (on) inside it: SwiftUI's track is 54x24, knob 32x20, inset 2
//      (MetalUI's 38x22 / 18 / 2 are not these).
//   K1 accessibility press (no app transaction)            knob x 2.0 -> 20.0 over 17-19 distinct values, settles at ~0.31 s, peak 20.54  -> SLID
//   K2 binding write, no animation                          the same curve, settles at ~0.27 s, peak 20.54                                  -> SLID
//   K3 withAnimation(.linear(duration: 1)) write            the same curve, settles at ~0.27 s (NOT 1 s, not linear)                          -> SLID
//   K4 .checkbox binding write (separating arm)             1 distinct value                                                                   -> snapped
//
// READING. The `.switch` knob slides on EVERY change, a click, an un-animated write and an animated one alike, with the control's
// own spring-like curve (ease out, ~0.27-0.31 s, a 0.54 point overshoot). **The app's transaction does not drive it**: K3's linear
// one-second animation is ignored, which K4's checkbox (a snap) separates from "nothing animates". The old reading "unmeasured: the
// offscreen capture is blind to motion" is replaced by this one.
