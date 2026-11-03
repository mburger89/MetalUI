// SwiftUI probe: Markdown in control titles and what the accessibility tree and the pop-up menu read of
// them (R4-1 PR A, ruling `SR-C`, divergence 154). `Button("**b**")` and `Toggle("**b**", …)` draw bold
// labels (`swiftui-rich-text.swift` M30/M31); this probe asks what a control publishes for that title and
// whether a `String` VARIABLE parses.
//
// HOW TO RUN (compiled form, SA-O; needs an unlocked screen, appkit-screen-lock-state.swift):
//
//   xcrun swiftc docs/probes/swiftui-control-titles.swift -o /tmp/ct-probe && /tmp/ct-probe 2>&1 | grep -v 'Connection\]'
//
// METHOD. Each arm hosts the control in an `NSHostingView` in a real window, switches
// `AXEnhancedUserInterface` on (the hosting view publishes no accessibility children until a client is
// detected), and prints AXRole / AXTitle / AXDescription / AXValue of every node in the tree below the host.
// A menu arm opens no menu: it reads the `NSMenuItem` the pop-up holds (`title` and `attributedTitle`).
// SEPARATING ARMS. `**b**` literal against `**b**` held in a `String` variable (`v`), and against the
// plain `b` literal (the markup-free control). `AX1` is the arm the ruling rests on.
//
// RECORDED OUTPUT: the block at the end of this file.

import AppKit
import SwiftUI

setvbuf(stdout, nil, _IOLBF, 0)
@MainActor func spin(_ s: Double = 0.3) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

func q(_ v: Any?) -> String {
    guard let v else { return "nil" }
    if let s = v as? String { return "\"\(s)\"" }
    if v is NSNumber { return "\(v)" }
    if let a = v as? NSAttributedString { return "attributed\"\(a.string)\"" }
    return "<obj>"
}
func kv(_ o: NSObject, _ key: String) -> Any? {
    if o.responds(to: Selector(key)) { return o.value(forKey: key) }
    return "<n/a>"
}

@MainActor func dump(_ o: NSObject, depth: Int, _ out: inout [String]) {
    guard depth <= 7 else { return }
    if let role = kv(o, "accessibilityRole") as? String {
        out.append(String(repeating: "  ", count: depth) + "\(role) sub=\(q(kv(o, "accessibilitySubrole"))) title=\(q(kv(o, "accessibilityTitle"))) label=\(q(kv(o, "accessibilityLabel"))) value=\(q(kv(o, "accessibilityValue")))")
    }
    for k in ((kv(o, "accessibilityChildren") as? [Any]) ?? []).compactMap({ $0 as? NSObject }) { dump(k, depth: depth + 1, &out) }
}

var windows: [NSWindow] = []
@MainActor func arm<V: View>(_ label: String, _ view: V) {
    let host = NSHostingView(rootView: view)
    host.frame = CGRect(x: 0, y: 0, width: 300, height: 120)
    let w = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    w.contentView = host
    w.setFrameOrigin(NSPoint(x: 100, y: 100))
    w.orderFrontRegardless()
    w.makeKey()
    host.layoutSubtreeIfNeeded()
    windows.append(w)
    spin(0.4)
    var out: [String] = []
    dump(host, depth: 1, &out)
    print("=== \(label)")
    for l in out { print(l) }
}

/// The pop-up `NSMenuItem` titles inside a hosted `Menu` (no menu is opened).
@MainActor func menuItems(_ label: String, _ view: some View) {
    let host = NSHostingView(rootView: view)
    host.frame = CGRect(x: 0, y: 0, width: 300, height: 120)
    let w = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    w.contentView = host
    w.makeKeyAndOrderFront(nil)
    windows.append(w)
    spin()
    func walk(_ v: NSView) {
        if let p = v as? NSPopUpButton {
            for i in p.menu?.items ?? [] { print("  item title=\"\(i.title)\" attributed=\(i.attributedTitle.map { "\"\($0.string)\"" } ?? "nil")") }
            print("  button title=\"\(p.title)\"")
        }
        for s in v.subviews { walk(s) }
    }
    print("=== \(label)")
    walk(host)
}

@MainActor func run() {
    NSApplication.shared.setActivationPolicy(.regular)
    NSApp.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
    let v = "**b**"
    let on = Binding.constant(false)
    arm("AX1 Button(\"**b**\") literal", Button("**b**") {})
    arm("AX1v Button(v) String variable", Button(v) {})
    arm("AX1p Button(\"b\") plain literal", Button("b") {})
    arm("AX2 Toggle(\"**b**\") literal", Toggle("**b**", isOn: on))
    arm("AX2v Toggle(v) String variable", Toggle(v, isOn: on))
    arm("AX3 Stepper(\"**b**\") literal", Stepper("**b**", value: .constant(1)))
    arm("AX3v Stepper(v) String variable", Stepper(v, value: .constant(1)))
    arm("AX4 Picker(\"**b**\") literal", Picker("**b**", selection: .constant(0)) { Text("A").tag(0); Text("B").tag(1) })
    arm("AX4v Picker(v) String variable", Picker(v, selection: .constant(0)) { Text("A").tag(0); Text("B").tag(1) })
    arm("AX5 ColorPicker(\"**b**\") literal", ColorPicker("**b**", selection: .constant(.red)))
    arm("AX5v ColorPicker(v) String variable", ColorPicker(v, selection: .constant(.red)))
    arm("AX6 ProgressView(\"**b**\", value:) literal", ProgressView("**b**", value: 0.5))
    arm("AX6v ProgressView(v, value:) String variable", ProgressView(v, value: 0.5))
    arm("AX7 TextField(\"**b**\") placeholder literal", TextField("**b**", text: .constant("")))
    arm("AX7v TextField(v) placeholder String variable", TextField(v, text: .constant("")))
    arm("AX8 Menu(\"**b**\") literal", Menu("**b**") { Button("x") {} })
    menuItems("MN1 Menu { Button(\"**b**\") } item titles", Menu("m") { Button("**b**") {}; Button("c") {} })
    menuItems("MN1v Menu { Button(v) } item titles", Menu("m") { Button(v) {}; Button("c") {} })
}

MainActor.assumeIsolated { run() }

// RECORDED 2026-11-03 (R4-1 PR A, ruling `SR-C`; macOS 27.2, Apple Swift 6.4, screen unlocked, compiled form). Each arm's tree is
// `AXGroup sub=AXHostingView` over the lines below (the `title=`/`value=` columns that are `nil` are omitted).
//
//   AX1  Button("**b**") literal            AXButton      label="b"          <- markup-free text
//   AX1v Button(v) String variable          AXButton      label="**b**"      <- verbatim: the separating arm
//   AX1p Button("b")                        AXButton      label="b"
//   AX2  Toggle("**b**") literal            AXCheckBox    label="b"          AX2v String variable   label="**b**"
//   AX3  Stepper("**b**") literal           AXStaticText  value="b"          AX3v String variable   value="**b**"
//   AX4  Picker("**b**") literal            AXStaticText  value="b" + AXPopUpButton value="A"      AX4v value="**b**"
//   AX5  ColorPicker("**b**") literal       AXStaticText  value="b"          AX5v String variable   value="**b**"
//   AX6  ProgressView("**b**", value:)      AXProgressIndicator label="b"    AX6v String variable   label="**b**"
//   AX7  TextField("**b**") placeholder     AXTextField   (no title, label or placeholder is published, literal or variable)
//   AX8  Menu("**b**") literal              AXMenuButton  title=attributed"b"
//   MN1  Menu { Button("**b**") } items     NOT MEASURED: no NSPopUpButton is hosted by a closed Menu, so no NSMenuItem was read.
//
// READING. Every control in the fix set parses a string LITERAL and publishes the concatenated, markup-free text (`b`); a `String`
// variable is verbatim in every one. That is `Text`'s own overload shape (a `LocalizedStringKey` initialiser and a disfavoured
// `StringProtocol` one). A native menu item's title and a `TextField` placeholder were not read: `SR-C` leaves both as plain strings.
