// SwiftUI probe, third round: the arms the accessibility-bridge design's second
// critic ran in its scratchpad (critic-probe2/3/4.swift), committed with the
// design session's added arms. Evidence for AB-F (empty text), AB-G (a
// button's combined value), AB-H (allowsHitTesting), AB-T (distribution from
// focusable and adjustable containers) and AB-Z (a disabled control is
// published) in docs/superpowers/2026-09-15-accessibility-bridge-decisions.md,
// "Second critic round".
//
// HOW TO RUN (Apple's toolchain, as the first two probes):
//
//   /usr/bin/swift docs/probes/swiftui-accessibility-bridge-critic2.swift 2>&1 \
//     | grep -v 'Connection\]\|ntents\|warning:\|deprecated\|^ *[0-9]* |\|^ *|\|note:\|WARNING: Application performed a reentrant'
//
// Arms C0–C5, P0–P2 and E0–E2 are the critic's, committed verbatim in
// substance. C5i, C6 and C7 were added by the design session:
//   C5i performs increment on each of C5's two published children, to ask
//       whether distribution kept the adjustable action on anything;
//   C6  puts a value on BOTH texts inside a button, to ask how two descendant
//       values combine (C3 has one);
//   C7  is C3 with the value on the SECOND text, to ask whether the button's
//       value follows the text that carries it or the first position.
//
// Reading method as before: KVC on the modern selectors after
// AXEnhancedUserInterface is set on NSApp; perform methods through a typed IMP
// (Swift `as? NSAccessibilityProtocol` fails on SwiftUI's nodes, AB-S item 3).
//
// POSITIVE CONTROLS.
//   1. C0 re-runs arm R3 of swiftui-accessibility-bridge-rules.swift and must
//      read its recorded two `AXStaticText value=L` before C1/C5 are believed.
//   2. P0, a plain `Button("Go")`, must press `true` and run its closure once,
//      so P1's `true, 1` is `allowsHitTesting(false)` leaving the press alone,
//      not a harness that cannot see a refusal — and P2's `false, 0` (same
//      harness) shows it CAN see one.
//   3. E0 publishes both texts, so E1's single child is the empty Text's
//      omission, not a host that drops the first child.
//   4. C5i runs the perform on the children C5 just printed and prints the
//      closure's running count after each, so a count that rises once per
//      child is the distributed action running, not one call reaching the
//      container twice through some other path.
//
// RECORDED 2026-09-15 by the accessibility-bridge design session (second
// critic round), macOS 26.6.2 (25G83), /usr/bin/swift = Apple Swift 6.4
// (swiftlang-6.4.0.33.1). Exit 0. One run's filtered output, verbatim except
// that leading and trailing blank lines are dropped:
//
//   === C0 control = R3: VStack { Text A; Text B }.accessibilityLabel(L)
//   NSHostingView role=AXGroup label=nil value=nil kids=2
//     AccessibilityNode role=AXStaticText label=nil value=L kids=0
//     AccessibilityNode role=AXStaticText label=nil value=L kids=0
//   === C1 VStack { Text A; Text B }.focusable().accessibilityLabel(L)
//   NSHostingView role=AXGroup label=nil value=nil kids=2
//     AccessibilityNode role=AXStaticText label=nil value=L kids=0
//     AccessibilityNode role=AXStaticText label=nil value=L kids=0
//   === C2 VStack { Text A; Text B }.onTapGesture{}.accessibilityLabel(L)
//   NSHostingView role=AXGroup label=nil value=nil kids=2
//     AccessibilityNode role=AXStaticText label=nil value=L kids=0
//     AccessibilityNode role=AXStaticText label=nil value=L kids=0
//   === C3 Button { HStack { Text(vol).accessibilityValue(5); Text B } }
//   NSHostingView role=AXGroup label=nil value=nil kids=1
//     AccessibilityNode role=AXButton label=vol, B value=5 kids=0
//   === C4 Button { HStack { Text A.accessibilityLabel(X); Text B } }
//   NSHostingView role=AXGroup label=nil value=nil kids=1
//     AccessibilityNode role=AXButton label=X, B value=nil kids=0
//   === C5 VStack { Text A; Text B }.accessibilityAdjustableAction{}.accessibilityLabel(L)
//   NSHostingView role=AXGroup label=nil value=nil kids=2
//     AccessibilityNode role=AXStaticText label=nil value=L kids=0
//     AccessibilityNode role=AXStaticText label=nil value=L kids=0
//   C5i child 0 increment -> true, closure runs so far 1
//   C5i child 1 increment -> true, closure runs so far 2
//   === C6 Button { HStack { Text(a).accessibilityValue(1); Text(b).accessibilityValue(2) } }
//   NSHostingView role=AXGroup label=nil value=nil kids=1
//     AccessibilityNode role=AXButton label=a, b value=1, 2 kids=0
//   === C7 Button { HStack { Text A; Text(vol).accessibilityValue(5) } }
//   NSHostingView role=AXGroup label=nil value=nil kids=1
//     AccessibilityNode role=AXButton label=A, vol value=5 kids=0
//   === P0 control: Button(Go)
//   NSHostingView role=AXGroup label=nil value=nil kids=1
//     AccessibilityNode role=AXButton label=Go value=nil kids=0
//   press -> true, ran 1; enabled=1
//   === P1 Button(Go).allowsHitTesting(false)
//   NSHostingView role=AXGroup label=nil value=nil kids=1
//     AccessibilityNode role=AXButton label=Go value=nil kids=0
//   press -> true, ran 1
//   === P2 Button(Go).disabled(true)
//   NSHostingView role=AXGroup label=nil value=nil kids=1
//     AccessibilityNode role=AXButton label=Go value=nil kids=0
//   press -> false, ran 0; enabled=0
//   === E0 control: VStack { Text A; Text B }
//   NSHostingView role=AXGroup label=nil value=nil kids=2
//     AccessibilityNode role=AXStaticText label=nil value=A kids=0
//     AccessibilityNode role=AXStaticText label=nil value=B kids=0
//   === E1 VStack { Text(""); Text B }
//   NSHostingView role=AXGroup label=nil value=nil kids=1
//     AccessibilityNode role=AXStaticText label=nil value=B kids=0
//   === E2 VStack { Text(" "); Text B }
//   NSHostingView role=AXGroup label=nil value=nil kids=2
//     AccessibilityNode role=AXStaticText label=nil value=  kids=0
//     AccessibilityNode role=AXStaticText label=nil value=B kids=0

import AppKit
import SwiftUI

setvbuf(stdout, nil, _IOLBF, 0)
@MainActor func spin(_ s: Double = 0.3) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
func str(_ v: Any?) -> String { v.map { "\($0)" } ?? "nil" }
func kv(_ o: NSObject, _ key: String) -> Any? { o.value(forKey: key) }
@MainActor func kids(_ o: NSObject) -> [NSObject] { ((kv(o, "accessibilityChildren") as? [Any]) ?? []).compactMap { $0 as? NSObject } }
@MainActor func line(_ o: NSObject) -> String {
    "\(type(of: o))".components(separatedBy: "<").first! + " role=\(str(kv(o, "accessibilityRole"))) label=\(str(kv(o, "accessibilityLabel"))) value=\(str(kv(o, "accessibilityValue"))) kids=\(kids(o).count)"
}
@MainActor func describe(_ o: NSObject, _ d: Int = 0, maxDepth: Int = 3, maxKids: Int = 4) {
    print(String(repeating: "  ", count: d) + line(o))
    if d < maxDepth { for k in kids(o).prefix(maxKids) { describe(k, d + 1, maxDepth: maxDepth, maxKids: maxKids) } }
}
@MainActor func perform(_ e: NSObject, _ sel: String) -> Bool {
    typealias Fn = @convention(c) (AnyObject, Selector) -> Bool
    return unsafeBitCast(e.method(for: Selector(sel)), to: Fn.self)(e, Selector(sel))
}
final class Counter: @unchecked Sendable { var n = 0 }

var windows: [NSWindow] = []
@MainActor func host<V: View>(_ name: String, _ v: V, size: CGSize = CGSize(width: 300, height: 300)) -> NSHostingView<V> {
    let w = NSWindow(contentRect: NSRect(x: 100, y: 100, width: size.width, height: size.height),
                     styleMask: [.titled], backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    let h = NSHostingView(rootView: v)
    w.contentView = h
    w.orderFrontRegardless(); h.layoutSubtreeIfNeeded(); spin(0.5)
    print("=== \(name)"); windows.append(w)
    return h
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
MainActor.assumeIsolated {
    NSApp.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
    spin(0.5)

    // --- C: distribution from focusable/adjustable containers; button value.
    describe(host("C0 control = R3: VStack { Text A; Text B }.accessibilityLabel(L)",
                  VStack { Text("A"); Text("B") }.accessibilityLabel("L")))
    describe(host("C1 VStack { Text A; Text B }.focusable().accessibilityLabel(L)",
                  VStack { Text("A"); Text("B") }.focusable().accessibilityLabel("L")))
    describe(host("C2 VStack { Text A; Text B }.onTapGesture{}.accessibilityLabel(L)",
                  VStack { Text("A"); Text("B") }.onTapGesture {}.accessibilityLabel("L")))
    describe(host("C3 Button { HStack { Text(vol).accessibilityValue(5); Text B } }",
                  Button {} label: { HStack { Text("vol").accessibilityValue("5"); Text("B") } }))
    describe(host("C4 Button { HStack { Text A.accessibilityLabel(X); Text B } }",
                  Button {} label: { HStack { Text("A").accessibilityLabel("X"); Text("B") } }))
    let adjusted = Counter()
    let h5 = host("C5 VStack { Text A; Text B }.accessibilityAdjustableAction{}.accessibilityLabel(L)",
                  VStack { Text("A"); Text("B") }.accessibilityAdjustableAction { _ in adjusted.n += 1 }
                      .accessibilityLabel("L"))
    describe(h5)
    for (i, child) in kids(h5).enumerated() {
        let answer = perform(child, "accessibilityPerformIncrement")
        print("C5i child \(i) increment -> \(answer), closure runs so far \(adjusted.n)")
    }
    describe(host("C6 Button { HStack { Text(a).accessibilityValue(1); Text(b).accessibilityValue(2) } }",
                  Button {} label: { HStack { Text("a").accessibilityValue("1"); Text("b").accessibilityValue("2") } }))
    describe(host("C7 Button { HStack { Text A; Text(vol).accessibilityValue(5) } }",
                  Button {} label: { HStack { Text("A"); Text("vol").accessibilityValue("5") } }))

    // --- P: press under allowsHitTesting(false) and disabled.
    let c = Counter()
    let h0 = host("P0 control: Button(Go)", Button("Go") { c.n += 1 })
    describe(h0)
    if let n = kids(h0).first { print("press -> \(perform(n, "accessibilityPerformPress")), ran \(c.n); enabled=\(str(kv(n, "accessibilityEnabled")))") }
    let a = Counter()
    let h1 = host("P1 Button(Go).allowsHitTesting(false)", Button("Go") { a.n += 1 }.allowsHitTesting(false))
    describe(h1)
    if let n = kids(h1).first { print("press -> \(perform(n, "accessibilityPerformPress")), ran \(a.n)") }
    let d = Counter()
    let h2 = host("P2 Button(Go).disabled(true)", Button("Go") { d.n += 1 }.disabled(true))
    describe(h2)
    if let n = kids(h2).first { print("press -> \(perform(n, "accessibilityPerformPress")), ran \(d.n); enabled=\(str(kv(n, "accessibilityEnabled")))") }

    // --- E: empty and blank text.
    describe(host("E0 control: VStack { Text A; Text B }", VStack { Text("A"); Text("B") }))
    describe(host("E1 VStack { Text(\"\"); Text B }", VStack { Text(""); Text("B") }))
    describe(host("E2 VStack { Text(\" \"); Text B }", VStack { Text(" "); Text("B") }))
    spin(0.2)
}
