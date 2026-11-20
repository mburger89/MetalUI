// AppKit probe: does `NSSecureTextField` undo typing? (ruling `SCF-I`, docs/superpowers/2026-11-19-secure-field-decisions.md;
// record docs/record/393-secure-field.md.)
//
// HOW TO RUN: `xcrun swiftc docs/probes/appkit-secure-field-undo.swift -o /tmp/sf-undo && /tmp/sf-undo` (about 1 second; ordered-in window, no computer use).
//
// RECORDED 2026-11-19, macOS 27.0, Apple Swift 6.4:
//   secure allowsUndo: true isSecure-ish class: NSSecureTextView
//   secure canUndo: Optional(true) undoName: Optional("Typing") text: 8
//   secure after undo count: 0
//   plain allowsUndo: true isSecure-ish class: NSTextView
//   plain canUndo: Optional(true) undoName: Optional("Typing") text: 8
//   plain after undo count: 0
// READING. The secure field editor (`NSSecureTextView`) undoes typing exactly as a plain one does, so MetalUI keeps undo
// while a secure field is focused and drops the snapshots when it is not (`SCF-I`). (Typing "hunter2" then "x" counts 8
// characters and one undo group removes both.)
import AppKit
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
func run(_ f: NSTextField, _ name: String) {
    let w = NSWindow(contentRect: NSRect(x:0,y:0,width:300,height:100), styleMask: [.titled], backing: .buffered, defer: false)
    w.contentView?.addSubview(f); f.frame = NSRect(x:10,y:10,width:200,height:24)
    w.makeKeyAndOrderFront(nil)
    for _ in 0..<10 { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
    w.makeFirstResponder(f)
    guard let ed = w.fieldEditor(false, for: f) as? NSTextView else { print(name, "no editor"); return }
    print(name, "allowsUndo:", ed.allowsUndo, "isSecure-ish class:", type(of: ed))
    ed.insertText("hunter2", replacementRange: NSRange(location: NSNotFound, length: 0))
    ed.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))
    let um = ed.undoManager
    print(name, "canUndo:", um?.canUndo as Any, "undoName:", um?.undoActionName as Any, "text:", ed.string.count)
    ed.undoManager?.undo()
    print(name, "after undo count:", ed.string.count)
}
run(NSSecureTextField(string: ""), "secure")
run(NSTextField(string: ""), "plain")
