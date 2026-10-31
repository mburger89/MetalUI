// SwiftUI probe (DA-): what an NSHostingView publishes as AXIdentifier when an
// identifier is written on a container AND on its descendants, and when a
// modifier (.disabled, .opacity, .help ...) sits between the identifier and
// the view. Evidence for DA-A/DA-B in
// docs/superpowers/2026-10-30-dashboard-ax-decisions.md.
//
// HOW TO RUN (Apple's toolchain; needs a window server, not a unlocked screen):
//
//   /usr/bin/swift docs/probes/swiftui-accessibility-identifier-nesting.swift 2>&1 \
//     | grep -v 'Connection\]\|ntents\|warning:\|deprecated\|^ *[0-9]* |\|^ *|\|note:\|WARNING: Application performed a reentrant'
//
// RECORDED OUTPUT (macOS, 2026-10-30; HostingView line and kids counts dropped):
//   X1 VStack { Text a(id a); Button b(id b) }.accessibilityIdentifier(screen)
//     StaticText value=a id=screen ; Button label=b id=screen      (container id OVERWRITES)
//   X2 same + .accessibilityElement(children: .contain)
//     Group id=screen kids=2 { StaticText a id=a ; Button b id=b }  (own ids kept)
//   X3 VStack { Text a(id a); Text c }.accessibilityIdentifier(screen)
//     StaticText a id=screen ; StaticText c id=screen
//   M1 Button.disabled(true).accessibilityIdentifier(x)   Button id=x disabled
//   M2 Button.accessibilityIdentifier(x).disabled(true)   Button id=x disabled
//   M3 Text.opacity(0.5).accessibilityIdentifier(x)       StaticText id=x
//   M4 Text.help(h).accessibilityIdentifier(x)            StaticText help=h id=x

import AppKit
import SwiftUI

setvbuf(stdout, nil, _IOLBF, 0)
@MainActor func spin(_ s: Double = 0.3) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
func str(_ v: Any?) -> String { v.map { "\($0)" } ?? "nil" }
/// KVC, guarded: AppKit's own row/cell mock elements are not KVC-compliant for
/// the accessibility keys, and an undefined key raises.
func kv(_ o: NSObject, _ key: String) -> Any? {
    let isKey = "is" + key.prefix(1).uppercased() + key.dropFirst()
    guard o.responds(to: Selector(key)) || o.responds(to: Selector(isKey)) else { return nil }
    return o.value(forKey: key)
}
@MainActor func kids(_ o: NSObject) -> [NSObject] { ((kv(o, "accessibilityChildren") as? [Any]) ?? []).compactMap { $0 as? NSObject } }
@MainActor func customActions(_ o: NSObject) -> [NSAccessibilityCustomAction] {
    (kv(o, "accessibilityCustomActions") as? [NSAccessibilityCustomAction]) ?? []
}
@MainActor func line(_ o: NSObject) -> String {
    var s = "\(type(of: o))".components(separatedBy: "<").first!
    s += " role=\(str(kv(o, "accessibilityRole"))) sub=\(str(kv(o, "accessibilitySubrole")))"
    s += " label=\(str(kv(o, "accessibilityLabel"))) value=\(str(kv(o, "accessibilityValue")))"
    if let help = kv(o, "accessibilityHelp") as? String, !help.isEmpty { s += " help=\(help)" }
    if let ident = kv(o, "accessibilityIdentifier") as? String, !ident.isEmpty { s += " id=\(ident)" }
    if (kv(o, "accessibilitySelected") as? Bool) == true { s += " selected" }
    if (kv(o, "accessibilityEnabled") as? Bool) == false { s += " disabled" }
    let names = customActions(o).map(\.name)
    if !names.isEmpty { s += " custom=\(names)" }
    if str(kv(o, "accessibilityRole")) == "AXOutline" { s += " rows=\((kv(o, "accessibilityRows") as? [Any])?.count ?? -1)" }
    s += " kids=\(kids(o).count)"
    return s
}
@MainActor func describe(_ o: NSObject, _ d: Int = 0, maxDepth: Int = 4, maxKids: Int = 5) {
    print(String(repeating: "  ", count: d) + line(o))
    if d < maxDepth { for k in kids(o).prefix(maxKids) { describe(k, d + 1, maxDepth: maxDepth, maxKids: maxKids) } }
}
@MainActor func perform(_ e: NSObject, _ sel: String) -> Bool {
    typealias Fn = @convention(c) (AnyObject, Selector) -> Bool
    return unsafeBitCast(e.method(for: Selector(sel)), to: Fn.self)(e, Selector(sel))
}
/// Depth-first, first node with this role.
@MainActor func find(_ o: NSObject, role: String) -> NSObject? {
    if str(kv(o, "accessibilityRole")) == role { return o }
    for k in kids(o) { if let f = find(k, role: role) { return f } }
    return nil
}
final class Counter: @unchecked Sendable { var n = 0; var log: [String] = [] }
var windows: [NSWindow] = []
@MainActor func host<V: View>(_ name: String, _ v: V, size: CGSize = CGSize(width: 300, height: 300)) -> NSHostingView<V> {
    let w = NSWindow(contentRect: NSRect(x: 100, y: 100, width: size.width, height: size.height),
                     styleMask: [.titled], backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    let h = NSHostingView(rootView: v)
    w.contentView = h
    w.orderFrontRegardless(); w.makeKey(); h.layoutSubtreeIfNeeded(); spin(0.5)
    print("=== \(name)"); windows.append(w)
    return h
}
@MainActor func show<V: View>(_ name: String, _ v: V, size: CGSize = CGSize(width: 300, height: 300)) {
    describe(host(name, v, size: size))
}
NSApplication.shared.setActivationPolicy(.accessory)
NSApp.setValue(true, forKey: "accessibilityEnhancedUserInterface")
@MainActor func run() {
    show("X1 VStack { Text a(id a); Button b(id b) }.accessibilityIdentifier(screen)",
         VStack { Text("a").accessibilityIdentifier("a"); Button("b") {}.accessibilityIdentifier("b") }.accessibilityIdentifier("screen"))
    show("X2 same, container .accessibilityElement(children: .contain)",
         VStack { Text("a").accessibilityIdentifier("a"); Button("b") {}.accessibilityIdentifier("b") }
            .accessibilityElement(children: .contain).accessibilityIdentifier("screen"))
    show("X3 VStack { Text a(id a); Text c }.accessibilityIdentifier(screen)",
         VStack { Text("a").accessibilityIdentifier("a"); Text("c") }.accessibilityIdentifier("screen"))
    show("M1 Button.disabled(true).accessibilityIdentifier(x)", Button("b") {}.disabled(true).accessibilityIdentifier("x"))
    show("M2 Button.accessibilityIdentifier(x).disabled(true)", Button("b") {}.accessibilityIdentifier("x").disabled(true))
    show("M3 Text.opacity(0.5).accessibilityIdentifier(x)", Text("t").opacity(0.5).accessibilityIdentifier("x"))
    show("M4 Text.help(h).accessibilityIdentifier(x)", Text("t").help("h").accessibilityIdentifier("x"))
    spin(0.2)
}
MainActor.assumeIsolated { run() }
