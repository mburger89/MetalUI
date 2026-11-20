// SwiftUI probe: `SecureField` (ruling `SCF-F`, docs/superpowers/2026-11-19-secure-field-decisions.md; record
// docs/record/393-secure-field.md).
//
// HOW TO RUN (ruling SA-O's two forms; about 2 seconds; opens one ordered-in window and exits itself; no computer use):
//
//   /usr/bin/swift docs/probes/swiftui-secure-field.swift
//   xcrun swiftc docs/probes/swiftui-secure-field.swift -o /tmp/secure-field-probe && /tmp/secure-field-probe
//
// THE INSTRUMENT. A `SecureField("Pass", text:)` holding "hunter2" and a `TextField("Name", text:)` holding "abc", each in an
// `NSHostingView` in a 400 x 300 window. SwiftUI's fields are `NSTextField`s on macOS (the secure one an `AppKitSecureTextField`, an `NSSecureTextField`); the
// probe finds them in the view tree and reads what the accessibility server reads: through the cell's `accessibilityAttributeValue`
// (the view's own modern protocol answers `AXUnknown` outside the server).
//
// ARMS. A: the secure field's view and cell classes and its AX role, subrole and value (as scalars). B: the plain field, the control.

// RECORDED 2026-11-19 by the SecureField session, macOS 27.0, Apple Swift 6.4, compiled form, run twice, stdout byte-identical:
//
//   --- A: SecureField "Pass" holding "hunter2"
//     view=AppKitSecureTextField cell=NSSecureTextFieldCell
//     AXRole=AXTextField AXSubrole=AXSecureTextField
//     AXValue=7 scalars [f79a, f79a, f79a, f79a, f79a, f79a, f79a] (the text is never in it)
//   --- B: TextField "Name" holding "abc"
//     view=AppKitTextField cell=_SystemTextFieldCell
//     AXRole=AXTextField AXSubrole=-
//     AXValue="abc"
//
// READING. A SwiftUI `SecureField` is `AXTextField` with subrole `AXSecureTextField`; its value is one U+F79A (a private-use
// glyph AppKit draws as a bullet) per character and never the text. `NSSecureTextFieldCell` is the source of both.
import AppKit
import SwiftUI

struct Fixture: View {
    @State var secret = "hunter2"
    @State var name = "abc"
    var body: some View {
        VStack {
            SecureField("Pass", text: $secret)
            TextField("Name", text: $name)
        }.padding()
    }
}

func read(_ o: AnyObject, _ a: String) -> Any? {
    let sel = NSSelectorFromString("accessibilityAttributeValue:")
    return o.responds(to: sel) ? o.perform(sel, with: a)?.takeUnretainedValue() : nil
}
func fields(_ v: NSView) -> [NSTextField] {
    (v as? NSTextField).map { [$0] } ?? v.subviews.flatMap(fields)
}
func scalars(_ s: String) -> String { "\(s.unicodeScalars.count) scalars [" + s.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: ", ") + "]" }

MainActor.assumeIsolated {
    do {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let win = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        let host = NSHostingView(rootView: Fixture())
        host.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        win.contentView = host
        win.orderBack(nil)
        for _ in 0..<20 { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        host.layoutSubtreeIfNeeded()
        for _ in 0..<20 { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        let all = fields(host)
        for (arm, title, field) in [("A", "SecureField \"Pass\" holding \"hunter2\"", all.first { $0 is NSSecureTextField }),
                                    ("B", "TextField \"Name\" holding \"abc\"", all.first { !($0 is NSSecureTextField) })] {
            print("--- \(arm): \(title)")
            guard let field, let cell = field.cell else { print("  field not found (\(all.count) text fields)"); continue }
            print("  view=\(type(of: field)) cell=\(type(of: cell))")
            print("  AXRole=\(read(cell, "AXRole").map { "\($0)" } ?? "-") AXSubrole=\(read(cell, "AXSubrole").map { "\($0)" } ?? "-")")
            let value = read(cell, "AXValue") as? String
            print("  AXValue=" + (arm == "A" ? value.map(scalars) ?? "-" : value.map { "\"\($0)\"" } ?? "-"))
        }
        win.orderOut(nil)
        exit(0)
    }
}
