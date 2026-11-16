// SwiftUI probe: `.accessibilityLabel` (and its siblings) on a menu item (Alloy request, 2026-11-15)
// — where SwiftUI honours it in the `NSMenu` it builds from a `.contextMenu` (on the
// Button, the Label, the Text, the Image) and how it reaches the `NSMenuItem`
// (`accessibilityLabel()` against `title`/`attributedTitle`). Evidence for ruling
// MN-AQ in docs/superpowers/2026-10-02-menus-popovers-decisions.md; record 328.
//
// HOW TO RUN (compiled form, SA-O):
//
//   xcrun swiftc docs/probes/swiftui-menu-item-accessibility.swift -o /tmp/menu-ax-probe
//   /tmp/menu-ax-probe
//
// Headless and self-exiting (as swiftui-menu-label-items.swift: the NSMenu is read
// from the hit view under a synthesized right-mouse event; nothing is shown).
//
// RECORDED 2026-11-15, macOS 27.0, Apple Swift 6.4; compiled form, run twice, stdout
// byte-identical, exit 0. The NSMenu SwiftUI builds from `.contextMenu` holds
// `SwiftUIMenuItem`s (an NSMenuItem subclass); each is read with the public
// `accessibilityLabel()`, `accessibilityTitle()`, `accessibilityHelp()`,
// `accessibilityIdentifier()`, `toolTip`, `attributedTitle`, and
// `accessibilityAttributeValue(.description)`, both from the closed menu (A-arms) and
// while it is open under `popUp` (O-arms: tracking started, read by a timer, cancelled).
//
// FINDINGS (read before resting a ruling on them):
// - NONE of `.accessibilityLabel`, `.accessibilityHint`, `.accessibilityIdentifier` or
//   `.accessibilityValue` reaches the NSMenuItem, wherever it is written: on the Button
//   (A1, A4, A14), the Button after `.tint` (A1b, Alloy's spelling), the Label (A2), the
//   Text (A3, A5), the Image icon (A6), a Toggle (A11), a Menu (A12), a disabled item
//   (A15), an empty label (A13). In every arm `accessibilityLabel()` and
//   `accessibilityTitle()` equal the title, `accessibilityHelp()` is nil,
//   `accessibilityIdentifier()` is "", `title` is unchanged and `attributedTitle` is nil.
//   The same holds read while the menu is open (O1, O2).
// - `.help` (A10) IS honoured: `toolTip`. (Control: the harness reads what it should.)
// - So SwiftUI's context-menu NSMenuItem gives VoiceOver the visible title only; the
//   modifier is accepted and has no menu effect through this API. Not measured: the
//   real AX tree (querying this process through AXUIElement returned no role even with
//   the process trusted), a pull-down `Menu` button's menu (P1 found no NSMenu to read),
//   and the app's main menu bar (`CommandMenu`).
//
// OUTPUT, verbatim:
//
//   === A0 control: Button { Label(name, systemImage:) }
//     title="Name" axLabel="Name" axTitle="Name" axHelp=nil axId="" toolTip=nil class=SwiftUIMenuItem view=false rep=nil axDesc=nil axRole="AXMenuItem" image=true attributedTitle=false
//   === A1 .accessibilityLabel on the Button, Label label
//     title="Name" axLabel="Name" axTitle="Name" axHelp=nil axId="" toolTip=nil class=SwiftUIMenuItem view=false rep=nil axDesc=nil axRole="AXMenuItem" image=true attributedTitle=false
//   === A1b Alloy: Label + .tint(.green) + .accessibilityLabel on the Button
//     title="Name" axLabel="Name" axTitle="Name" axHelp=nil axId="" toolTip=nil class=SwiftUIMenuItem view=false rep=nil axDesc=nil axRole="AXMenuItem" image=true attributedTitle=false
//   === A2 .accessibilityLabel on the Label inside the label
//     title="Name" axLabel="Name" axTitle="Name" axHelp=nil axId="" toolTip=nil class=SwiftUIMenuItem view=false rep=nil axDesc=nil axRole="AXMenuItem" image=true attributedTitle=false
//   === A3 .accessibilityLabel on the Text inside a Label(title:icon:)
//     title="Name" axLabel="Name" axTitle="Name" axHelp=nil axId="" toolTip=nil class=SwiftUIMenuItem view=false rep=nil axDesc=nil axRole="AXMenuItem" image=true attributedTitle=false
//   === A4 Button(Name) { } .accessibilityLabel on the Button (Text label)
//     title="Name" axLabel="Name" axTitle="Name" axHelp=nil axId="" toolTip=nil class=SwiftUIMenuItem view=false rep=nil axDesc=nil axRole="AXMenuItem" image=false attributedTitle=false
//   === A5 Button { Text } label: .accessibilityLabel on the Text
//     title="Name" axLabel="Name" axTitle="Name" axHelp=nil axId="" toolTip=nil class=SwiftUIMenuItem view=false rep=nil axDesc=nil axRole="AXMenuItem" image=false attributedTitle=false
//   === A6 .accessibilityLabel on the Image icon only
//     title="Name" axLabel="Name" axTitle="Name" axHelp=nil axId="" toolTip=nil class=SwiftUIMenuItem view=false rep=nil axDesc=nil axRole="AXMenuItem" image=true attributedTitle=false
//   === A7 .accessibilityHint on the Button
//     title="Name" axLabel="Name" axTitle="Name" axHelp=nil axId="" toolTip=nil class=SwiftUIMenuItem view=false rep=nil axDesc=nil axRole="AXMenuItem" image=false attributedTitle=false
//   === A8 .accessibilityIdentifier on the Button
//     title="Name" axLabel="Name" axTitle="Name" axHelp=nil axId="" toolTip=nil class=SwiftUIMenuItem view=false rep=nil axDesc=nil axRole="AXMenuItem" image=false attributedTitle=false
//   === A9 .accessibilityValue on the Button
//     title="Name" axLabel="Name" axTitle="Name" axHelp=nil axId="" toolTip=nil class=SwiftUIMenuItem view=false rep=nil axDesc=nil axRole="AXMenuItem" image=false attributedTitle=false
//   === A10 .help on the Button (control)
//     title="Name" axLabel="Name" axTitle="Name" axHelp=nil axId="" toolTip="help text" class=SwiftUIMenuItem view=false rep=nil axDesc=nil axRole="AXMenuItem" image=false attributedTitle=false
//   === A11 Toggle .accessibilityLabel
//     title="Name" axLabel="Name" axTitle="Name" axHelp=nil axId="" toolTip=nil class=SwiftUIMenuItem view=false rep=nil axDesc=nil axRole="AXMenuItem" image=false attributedTitle=false
//   === A12 Menu submenu .accessibilityLabel on the Menu
//     title="Name" axLabel="Name" axTitle="Name" axHelp=nil axId="" toolTip=nil class=SwiftUIMenuItem view=false rep=nil axDesc=nil axRole="AXMenuItem" image=false attributedTitle=false
//       title="Sub" axLabel="Sub" axTitle="Sub" axHelp=nil axId="" toolTip=nil class=SwiftUIMenuItem view=false rep=nil axDesc=nil axRole="AXMenuItem" image=false attributedTitle=false
//   === A13 .accessibilityLabel empty string on the Button
//     title="Name" axLabel="Name" axTitle="Name" axHelp=nil axId="" toolTip=nil class=SwiftUIMenuItem view=false rep=nil axDesc=nil axRole="AXMenuItem" image=false attributedTitle=false
//   === A14 .accessibilityLabel on the Button, Label with Button(_:systemImage:)
//     title="Name" axLabel="Name" axTitle="Name" axHelp=nil axId="" toolTip=nil class=SwiftUIMenuItem view=false rep=nil axDesc=nil axRole="AXMenuItem" image=true attributedTitle=false
//   === A15 .disabled item with .accessibilityLabel
//     title="Name" axLabel="Name" axTitle="Name" axHelp=nil axId="" toolTip=nil class=SwiftUIMenuItem view=false rep=nil axDesc=nil axRole="AXMenuItem" image=false attributedTitle=false
//   === O1 Button { Label } .accessibilityLabel on the Button [read while open]
//     title="Name" axLabel="Name" axTitle="Name" axHelp=nil axId="" toolTip=nil class=SwiftUIMenuItem view=false rep=nil axDesc=nil axRole="AXMenuItem" image=true attributedTitle=false
//   === O2 Button(Name) .accessibilityLabel/.accessibilityHint/.accessibilityIdentifier [read while open]
//     title="Name" axLabel="Name" axTitle="Name" axHelp=nil axId="" toolTip=nil class=SwiftUIMenuItem view=false rep=nil axDesc=nil axRole="AXMenuItem" image=false attributedTitle=false
//   === P1 Menu(T) { Button(Name) .accessibilityLabel } as a pull-down button
//     menus found: 0
//   --- end
//
import SwiftUI
import AppKit

@MainActor func spin(_ t: Double) { RunLoop.current.run(until: Date().addingTimeInterval(t)) }
var windows: [NSWindow] = []
@MainActor func host<V: View>(_ name: String, _ v: V) -> NSHostingView<V> {
    let w = NSWindow(contentRect: NSRect(x: 300, y: 400, width: 300, height: 200), styleMask: [.titled],
                     backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    let h = NSHostingView(rootView: v)
    w.contentView = h
    w.orderFrontRegardless(); w.makeKey(); h.layoutSubtreeIfNeeded(); spin(0.3)
    print("=== \(name)"); windows.append(w)
    return h
}
@MainActor func menuOf<V: View>(_ h: NSHostingView<V>) -> NSMenu? {
    let w = h.window!
    let pt = CGPoint(x: h.bounds.midX, y: h.bounds.midY)
    let e = NSEvent.mouseEvent(with: .rightMouseDown, location: pt, modifierFlags: [],
                               timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber,
                               context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    return (h.hitTest(h.convert(pt, from: nil)) ?? h).menu(for: e)
}
@MainActor func pixel(_ image: NSImage) -> String {
    let s = 64
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: s, pixelsHigh: s, bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return "?" }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: s, height: s))
    NSGraphicsContext.restoreGraphicsState()
    // The most opaque pixel stands for the glyph's colour.
    var best: NSColor?
    for y in 0..<s { for x in 0..<s {
        if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), c.alphaComponent > (best?.alphaComponent ?? 0.5) { best = c }
    } }
    guard let c = best else { return "transparent" }
    return String(format: "rgba=(%.2f,%.2f,%.2f,%.2f)", c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent)
}
@MainActor func dump(_ m: NSMenu?, _ d: Int = 1) {
    guard let m else { print("  menu: nil"); return }
    for item in m.items {
        let pad = String(repeating: "  ", count: d)
        if item.isSeparatorItem { print(pad + "----"); continue }
        var s = pad + "title=\"\(item.title)\""
        s += " axLabel=\(q(item.accessibilityLabel()))"
        s += " axTitle=\(q(item.accessibilityTitle()))"
        s += " axHelp=\(q(item.accessibilityHelp()))"
        s += " axId=\(q(item.accessibilityIdentifier()))"
        s += " toolTip=\(q(item.toolTip))"
        s += " class=\(type(of: item)) view=\(item.view != nil) rep=\(item.representedObject.map { "\(type(of: $0))" } ?? "nil")"
        s += " axDesc=\(q(item.accessibilityAttributeValue(.description) as? String))"
        s += " axRole=\(q(item.accessibilityRole()?.rawValue))"
        s += " image=\(item.image != nil)"
        s += " attributedTitle=\(item.attributedTitle != nil)"
        print(s)
        if let sub = item.submenu { dump(sub, d + 1) }
    }
}
func q(_ s: String?) -> String { s.map { "\"\($0)\"" } ?? "nil" }

struct Target<C: View>: View {
    let c: C
    var body: some View { Text("Target").frame(width: 200, height: 100).contextMenu { c } }
}
@MainActor func arm<C: View>(_ name: String, @ViewBuilder _ c: () -> C) {
    let h = host(name, Target(c: c())); dump(menuOf(h))
}
/// The same menu read while it is open (tracking started, then cancelled by a timer),
/// in case SwiftUI's items answer accessibility only once the menu is on screen.
@MainActor func armOpen<C: View>(_ name: String, @ViewBuilder _ c: () -> C) {
    let h = host(name + " [read while open]", Target(c: c()))
    guard let m = menuOf(h) else { print("  menu: nil"); return }
    let t = Timer(timeInterval: 0.6, repeats: false) { _ in
        MainActor.assumeIsolated { dump(Optional(m)); m.cancelTracking() }
    }
    RunLoop.current.add(t, forMode: .common)
    RunLoop.current.add(t, forMode: .eventTracking)
    m.popUp(positioning: nil, at: CGPoint(x: 20, y: 20), in: h)
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
MainActor.assumeIsolated {
    arm("A0 control: Button { Label(name, systemImage:) }") {
        Button { } label: { Label("Name", systemImage: "circle.fill") } }
    arm("A1 .accessibilityLabel on the Button, Label label") {
        Button { } label: { Label("Name", systemImage: "circle.fill") }.accessibilityLabel("Name, busy") }
    arm("A1b Alloy: Label + .tint(.green) + .accessibilityLabel on the Button") {
        Button { } label: { Label("Name", systemImage: "circle.fill") }.tint(.green).accessibilityLabel("Name, busy") }
    arm("A2 .accessibilityLabel on the Label inside the label") {
        Button { } label: { Label("Name", systemImage: "circle.fill").accessibilityLabel("Name, busy") } }
    arm("A3 .accessibilityLabel on the Text inside a Label(title:icon:)") {
        Button { } label: { Label { Text("Name").accessibilityLabel("Name, busy") } icon: { Image(systemName: "circle.fill") } } }
    arm("A4 Button(Name) { } .accessibilityLabel on the Button (Text label)") {
        Button("Name") {}.accessibilityLabel("Name, busy") }
    arm("A5 Button { Text } label: .accessibilityLabel on the Text") {
        Button { } label: { Text("Name").accessibilityLabel("Name, busy") } }
    arm("A6 .accessibilityLabel on the Image icon only") {
        Button { } label: { Label { Text("Name") } icon: { Image(systemName: "circle.fill").accessibilityLabel("dot") } } }
    arm("A7 .accessibilityHint on the Button") {
        Button("Name") {}.accessibilityHint("hint text") }
    arm("A8 .accessibilityIdentifier on the Button") {
        Button("Name") {}.accessibilityIdentifier("the-id") }
    arm("A9 .accessibilityValue on the Button") {
        Button("Name") {}.accessibilityValue("val") }
    arm("A10 .help on the Button (control)") {
        Button("Name") {}.help("help text") }
    arm("A11 Toggle .accessibilityLabel") {
        Toggle("Name", isOn: .constant(true)).accessibilityLabel("Name, busy") }
    arm("A12 Menu submenu .accessibilityLabel on the Menu") {
        Menu("Name") { Button("Sub") {} }.accessibilityLabel("Name, busy") }
    arm("A13 .accessibilityLabel empty string on the Button") {
        Button("Name") {}.accessibilityLabel("") }
    arm("A14 .accessibilityLabel on the Button, Label with Button(_:systemImage:)") {
        Button("Name", systemImage: "circle.fill") {}.accessibilityLabel("Name, busy") }
    arm("A15 .disabled item with .accessibilityLabel") {
        Button("Name") {}.accessibilityLabel("Name, busy").disabled(true) }
    armOpen("O1 Button { Label } .accessibilityLabel on the Button") {
        Button { } label: { Label("Name", systemImage: "circle.fill") }.tint(.green).accessibilityLabel("Name, busy") }
    armOpen("O2 Button(Name) .accessibilityLabel/.accessibilityHint/.accessibilityIdentifier") {
        Button("Name") {}.accessibilityLabel("Name, busy").accessibilityHint("hint").accessibilityIdentifier("the-id") }
    // The Menu button's own menu (a pull-down), not a context menu: find the NSMenu the control holds.
    let hm = host("P1 Menu(T) { Button(Name) .accessibilityLabel } as a pull-down button", Menu("T") {
        Button("Name") {}.accessibilityLabel("Name, busy").accessibilityHint("hint") })
    func menus(_ v: NSView, _ out: inout [NSMenu]) {
        if let b = v as? NSPopUpButton, let mm = b.menu { out.append(mm) }
        else if let mm = v.menu { out.append(mm) }
        for k in v.subviews { menus(k, &out) }
    }
    var found: [NSMenu] = []; menus(hm, &found)
    print("  menus found: \(found.count)")
    for mm in found { dump(Optional(mm)) }
    print("--- end")
}
exit(0)
