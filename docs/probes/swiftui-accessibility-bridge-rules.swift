// SwiftUI probe, second round: the label/value, wrapper, container, hidden and
// activation arms the accessibility-bridge critic raised against the first
// probe (docs/probes/swiftui-accessibility-bridge.swift). Evidence for AB-B,
// AB-F, AB-G, AB-O, AB-T…AB-Z in
// docs/superpowers/2026-09-15-accessibility-bridge-decisions.md.
//
// HOW TO RUN (Apple's toolchain; see the first probe's header):
//
//   /usr/bin/swift docs/probes/swiftui-accessibility-bridge-rules.swift 2>&1 \
//     | grep -v 'Connection\]\|ntents\|warning:\|deprecated\|^ *[0-9]* |\|^ *|\|note:\|WARNING: Application performed a reentrant'
//
// Arms R0–R7 and Q are the critic's (scratchpad critic-probe.swift), committed
// verbatim in substance; R8–R16 were added by the design session to settle the
// rules those arms forced. Reading method as in the first probe: KVC on the
// modern selectors after AXEnhancedUserInterface is set on NSApp.
//
// POSITIVE CONTROLS.
//   1. Q: the spy records nothing through a key window, first-responder
//      changes, synthesized mouse and key events and a resize, and DOES record
//      the in-process window and view queries made right after — so its empty
//      log is AppKit's answer, not a spy that cannot see.
//   2. R0 re-runs the first probe's arm 11 and must match its recorded
//      `label=vol value=5` before any other R arm is believed.
//   3. R13 prints `isVoiceOverEnabled` through a KVO observation installed with
//      `.initial`, so a missing line means the observation did not install.
//   4. R9's `Shown`, a plain Text beside the two hidden ones, is published, so
//      H1's and H2's absence is `.hidden()`'s effect, not a host that exposes
//      nothing.
//   5. R17 counts the realized children that DO intersect the scroll area too
//      (25 - 12 = 13), so "wholly outside" is not an intersection test that
//      rejects everything.
//
// RECORDED 2026-09-15 by the accessibility-bridge design session (critic
// round), macOS 26.6.2 (25G83), /usr/bin/swift = Apple Swift 6.4
// (swiftlang-6.4.0.33.1). Exit 0. One run's filtered output, verbatim except
// that leading and trailing blank lines are dropped:
//
//   === Q control-free AppKit window: accessibility calls on the content view with no client: []
//   === Q positive control after in-process window/view queries: ["isElement", "focused", "isElement", "children", "role"]
//   === R13 NSWorkspace.isVoiceOverEnabled (KVO, .initial): false
//   === R0 control: arm 11 as committed
//   NSHostingView role=AXGroup label=nil value=nil kids=1
//     AccessibilityNode role=AXStaticText label=vol value=5 kids=0
//   === R1 Text(vol).accessibilityValue(5), no adjustable action
//   NSHostingView role=AXGroup label=nil value=nil kids=1
//     AccessibilityNode role=AXStaticText label=vol value=5 kids=0
//   === R2 Text(vol).accessibilityLabel(L).accessibilityValue(5)
//   NSHostingView role=AXGroup label=nil value=nil kids=1
//     AccessibilityNode role=AXStaticText label=L value=5 kids=0
//   === R3 VStack { Text A; Text B }.accessibilityLabel(L)
//   NSHostingView role=AXGroup label=nil value=nil kids=2
//     AccessibilityNode role=AXStaticText label=nil value=L kids=0
//     AccessibilityNode role=AXStaticText label=nil value=L kids=0
//   === R4 Text(Go).padding().accessibilityLabel(X)
//   NSHostingView role=AXGroup label=nil value=nil kids=1
//     AccessibilityNode role=AXStaticText label=nil value=X kids=0
//   === R5 Button{Text Go}.padding().accessibilityLabel(X)
//   NSHostingView role=AXGroup label=nil value=nil kids=1
//     AccessibilityNode role=AXButton label=X value=nil kids=0
//   === R6 Color.frame(0 height).accessibilityLabel(Divider)
//   NSHostingView role=AXGroup label=nil value=nil kids=1
//     AccessibilityNode role=AXUnknown label=Divider value=nil kids=0
//   === R7 Button{ HStack{Text A; Toggle B} }
//   NSHostingView role=AXGroup label=nil value=nil kids=1
//     AccessibilityNode role=AXCheckBox label=A value=1 kids=0
//   === R8 Text(Go).accessibilityLabel(In).padding().accessibilityLabel(Out)
//   NSHostingView role=AXGroup label=nil value=nil kids=1
//     AccessibilityNode role=AXStaticText label=nil value=Out kids=0
//   === R9 VStack { Text(H1).hidden(); VStack{Text(H2)}.hidden(); Text(Shown) }
//   NSHostingView role=AXGroup label=nil value=nil kids=1
//     AccessibilityNode role=AXStaticText label=nil value=Shown kids=0
//   === R10 Text(Go).frame(width: 120).accessibilityLabel(X)
//   NSHostingView role=AXGroup label=nil value=nil kids=1
//     AccessibilityNode role=AXStaticText label=nil value=X kids=0
//   === R11 VStack { Color.frame(20) }.accessibilityLabel(L)
//   NSHostingView role=AXGroup label=nil value=nil kids=1
//     AccessibilityNode role=AXUnknown label=L value=nil kids=0
//   === R12 Button(vol).accessibilityValue(5)
//   NSHostingView role=AXGroup label=nil value=nil kids=1
//     AccessibilityNode role=AXButton label=vol value=5 kids=0
//   === R14 VStack { Text A; Button B }.accessibilityLabel(L)
//   NSHostingView role=AXGroup label=nil value=nil kids=2
//     AccessibilityNode role=AXStaticText label=nil value=L kids=0
//     AccessibilityNode role=AXButton label=L value=nil kids=0
//   === R15 VStack { Text A.accessibilityLabel(Own); Text B }.accessibilityLabel(L)
//   NSHostingView role=AXGroup label=nil value=nil kids=2
//     AccessibilityNode role=AXStaticText label=nil value=L kids=0
//     AccessibilityNode role=AXStaticText label=nil value=L kids=0
//   === R16 List(0..<500).accessibilityLabel(Contacts)
//   NSHostingView role=AXGroup label=nil value=nil kids=1
//     ListCoreScrollView role=AXScrollArea label=nil value=nil kids=2
//       SwiftUIOutlineListView role=AXOutline label=Contacts value=nil kids=501 rows=500
//       NSScroller role=AXScrollBar label=nil value=0 kids=5
//   === R17 ScrollView { LazyVStack { ForEach(0..<500) } } — every realized child's frame
//   scroll area (100.0, 100.0, 300.0, 200.0); realized 25; wholly outside the area: 12; heights outside: [16.0, 16.0, 16.0, 16.0, 16.0, 16.0, 16.0, 16.0, 16.0, 16.0, 16.0, 16.0]; last child frame (227.25, -513.0, 45.5, 16.0)
//   === R18 VStack { Text A; Text B }.accessibilityValue(V)
//   NSHostingView role=AXGroup label=nil value=nil kids=2
//     AccessibilityNode role=AXStaticText label=A value=V kids=0
//     AccessibilityNode role=AXStaticText label=B value=V kids=0
//
// WHAT THE ARMS SETTLE (the rulings cite them; this is a reading aid):
//   R0 = arm 11, so the round's reads are comparable with the first probe.
//   R1, R2, R12: a declared value keeps the Text's (or Button's) own string as
//     the label unless a label is declared (AB-F).
//   R3, R14, R15, R18: a label or value on a plain container is DISTRIBUTED to
//     each accessible child, overriding a child's own label (AB-T).
//   R4, R5, R10, R8: the same distribution through .padding/.frame; the
//     OUTERMOST declaration wins (AB-T).
//   R6, R11: a zero-height labelled view and a labelled container of an
//     inaccessible leaf are both published (AB-O).
//   R9: .hidden() content is not published, beside a published control (AB-O).
//   R7: a Button whose label holds a Toggle collapses into the Toggle (AB-G's
//     recorded divergence).
//   R13: NSWorkspace.isVoiceOverEnabled is public and KVO-observable (AB-B).
//   R16: a labelled List keeps its table-like role and row count (AB-L).
//   R17: 12 of 25 realized lazy children lie wholly outside the scroll area and
//     report full 16pt frames, so children's frames are unclipped (AB-E).
//   Q: AppKit itself sends no accessibility query to a content view with no
//     client (AB-B).

import AppKit
import SwiftUI

setvbuf(stdout, nil, _IOLBF, 0)
@MainActor func spin(_ s: Double = 0.3) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
func str(_ v: Any?) -> String { v.map { "\($0)" } ?? "nil" }
func kv(_ o: NSObject, _ key: String) -> Any? { o.value(forKey: key) }
@MainActor func kids(_ o: NSObject) -> [NSObject] { ((kv(o, "accessibilityChildren") as? [Any]) ?? []).compactMap { $0 as? NSObject } }
@MainActor func line(_ o: NSObject) -> String {
    var extra = ""
    if let table = o as? NSTableView { extra = " rows=\(table.accessibilityRows()?.count ?? -1)" }
    return "\(type(of: o))".components(separatedBy: "<").first! + " role=\(str(kv(o, "accessibilityRole"))) label=\(str(kv(o, "accessibilityLabel"))) value=\(str(kv(o, "accessibilityValue"))) kids=\(kids(o).count)\(extra)"
}
@MainActor func describe(_ o: NSObject, _ d: Int = 0, maxDepth: Int = 3, maxKids: Int = 4) {
    print(String(repeating: "  ", count: d) + line(o))
    if d < maxDepth { for k in kids(o).prefix(maxKids) { describe(k, d + 1, maxDepth: maxDepth, maxKids: maxKids) } }
}

// --- Arm Q: does AppKit query a plain NSView's accessibility with NO client?
final class Spy: NSView {
    var log: [String] = []
    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }
    override func accessibilityChildren() -> [Any]? { log.append("children"); return super.accessibilityChildren() }
    override func accessibilityHitTest(_ point: NSPoint) -> Any? { log.append("hitTest"); return super.accessibilityHitTest(point) }
    override var accessibilityFocusedUIElement: Any? { log.append("focused"); return super.accessibilityFocusedUIElement }
    override func isAccessibilityElement() -> Bool { log.append("isElement"); return true }
    override func accessibilityRole() -> NSAccessibility.Role? { log.append("role"); return .group }
    override func keyDown(with event: NSEvent) {}
    override func mouseDown(with event: NSEvent) {}
}

var windows: [NSWindow] = []
@MainActor func host<V: View>(_ name: String, _ v: V, size: CGSize = CGSize(width: 300, height: 300)) -> NSHostingView<V> {
    let w = NSWindow(contentRect: NSRect(x: 100, y: 100, width: size.width, height: size.height), styleMask: [.titled], backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    let h = NSHostingView(rootView: v)
    w.contentView = h
    w.orderFrontRegardless(); h.layoutSubtreeIfNeeded(); spin(0.5)
    print("=== \(name)"); windows.append(w)
    return h
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
var observation: NSKeyValueObservation?

MainActor.assumeIsolated {
    let w = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 300, height: 300), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    let spy = Spy(frame: .zero)
    w.contentView = spy
    app.activate(ignoringOtherApps: true)
    w.makeKeyAndOrderFront(nil)
    w.makeFirstResponder(spy)
    spin(0.5)
    let loc = NSPoint(x: 150, y: 150)
    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
        if let e = NSEvent.mouseEvent(with: type, location: loc, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) { w.sendEvent(e) }
    }
    if let k = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0) { w.sendEvent(k) }
    w.setFrame(NSRect(x: 120, y: 120, width: 320, height: 280), display: true)
    w.makeFirstResponder(nil); w.makeFirstResponder(spy)
    spin(1.0)
    print("=== Q control-free AppKit window: accessibility calls on the content view with no client: \(spy.log)")
    _ = w.accessibilityChildren()
    _ = w.accessibilityFocusedUIElement
    _ = spy.accessibilityChildren()
    print("=== Q positive control after in-process window/view queries: \(spy.log)")
    w.orderOut(nil)

    // --- R13: the public VoiceOver signal, observed before anything is switched on.
    observation = NSWorkspace.shared.observe(\.isVoiceOverEnabled, options: [.initial, .new]) { ws, _ in
        print("=== R13 NSWorkspace.isVoiceOverEnabled (KVO, .initial): \(ws.isVoiceOverEnabled)")
    }

    NSApp.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
    spin(0.5)
    describe(host("R0 control: arm 11 as committed", Text("vol").accessibilityValue("5").accessibilityAdjustableAction { _ in }))
    describe(host("R1 Text(vol).accessibilityValue(5), no adjustable action", Text("vol").accessibilityValue("5")))
    describe(host("R2 Text(vol).accessibilityLabel(L).accessibilityValue(5)", Text("vol").accessibilityLabel("L").accessibilityValue("5")))
    describe(host("R3 VStack { Text A; Text B }.accessibilityLabel(L)", VStack { Text("A"); Text("B") }.accessibilityLabel("L")))
    describe(host("R4 Text(Go).padding().accessibilityLabel(X)", Text("Go").padding().accessibilityLabel("X")))
    describe(host("R5 Button{Text Go}.padding().accessibilityLabel(X)", Button { } label: { Text("Go") }.padding().accessibilityLabel("X")))
    describe(host("R6 Color.frame(0 height).accessibilityLabel(Divider)", Color.red.frame(width: 20, height: 0).accessibilityLabel("Divider")))
    describe(host("R7 Button{ HStack{Text A; Toggle B} }", Button { } label: { HStack { Text("A"); Toggle("B", isOn: .constant(true)) } }))

    // --- R8: an inner label and an outer label across a wrapper: which wins.
    describe(host("R8 Text(Go).accessibilityLabel(In).padding().accessibilityLabel(Out)",
                  Text("Go").accessibilityLabel("In").padding().accessibilityLabel("Out")))
    // --- R9: hidden content, with a visible control beside it.
    describe(host("R9 VStack { Text(H1).hidden(); VStack{Text(H2)}.hidden(); Text(Shown) }",
                  VStack { Text("H1").hidden(); VStack { Text("H2") }.hidden(); Text("Shown") }))
    // --- R10: .frame is a wrapper like .padding.
    describe(host("R10 Text(Go).frame(width: 120).accessibilityLabel(X)", Text("Go").frame(width: 120).accessibilityLabel("X")))
    // --- R11: a labelled container with no accessible child.
    describe(host("R11 VStack { Color.frame(20) }.accessibilityLabel(L)", VStack { Color.red.frame(width: 20, height: 20) }.accessibilityLabel("L")))
    // --- R12: a Button with a value keeps its own label.
    describe(host("R12 Button(vol).accessibilityValue(5)", Button("vol") {}.accessibilityValue("5")))
    // --- R14: a label on a container holding a Text and a Button: distributed to both?
    describe(host("R14 VStack { Text A; Button B }.accessibilityLabel(L)", VStack { Text("A"); Button("B") {} }.accessibilityLabel("L")))
    // --- R15: a label on a container of two texts, one of which declares its own.
    describe(host("R15 VStack { Text A.accessibilityLabel(Own); Text B }.accessibilityLabel(L)",
                  VStack { Text("A").accessibilityLabel("Own"); Text("B") }.accessibilityLabel("L")))
    // --- R16: a labelled List keeps its outline role and row count.
    describe(host("R16 List(0..<500).accessibilityLabel(Contacts)",
                  List(0..<500, id: \.self) { Text("Row \($0)") }.accessibilityLabel("Contacts"),
                  size: CGSize(width: 300, height: 200)), maxDepth: 2, maxKids: 2)
    // --- R17: is a lazy container's realized-but-offscreen child's frame clipped?
    // Prints every realized child's screen frame against the scroll area's.
    let lh = host("R17 ScrollView { LazyVStack { ForEach(0..<500) } } — every realized child's frame",
                  ScrollView { LazyVStack { ForEach(0..<500, id: \.self) { Text("Row \($0)") } } },
                  size: CGSize(width: 300, height: 200))
    if let area = kids(lh).first, let lazy = kids(area).first {
        let areaFrame = (kv(area, "accessibilityFrame") as? NSValue)?.rectValue ?? .zero
        let rows = kids(lazy)
        let frames = rows.map { (kv($0, "accessibilityFrame") as? NSValue)?.rectValue ?? .zero }
        let outside = frames.filter { !$0.intersects(areaFrame) }
        print("scroll area \(areaFrame); realized \(rows.count); wholly outside the area: \(outside.count); heights outside: \(outside.map { $0.height }); last child frame \(frames.last ?? .zero)")
    }
    // --- R18: a value on a container of two texts.
    describe(host("R18 VStack { Text A; Text B }.accessibilityValue(V)", VStack { Text("A"); Text("B") }.accessibilityValue("V")))
    spin(0.2)
}
