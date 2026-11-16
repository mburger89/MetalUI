// SwiftUI probe: two `TextEditor(text:selection:)` (macOS 15+ `Binding<TextSelection?>`) on ONE `@State String`.
// When the text changes through the shared binding (programmatically, or by typing into editor A through its
// NSTextView), does SwiftUI move editor B's selection — the `Binding<TextSelection?>` and B's underlying
// NSTextView `selectedRange`? Confirms or refutes "SwiftUI does not move the other editor's selection" (the premise of
// docs/superpowers/specs/2026-11-16-codeview-selection-state-design.md §0; record 242's SL-P probe saw it for ONE
// editor and an external replace). Companion of docs/probes/appkit-shared-storage-selection.swift (record 325).
//
// HOW TO RUN (compiled form, Apple's toolchain per SA-O; one arm per process):
//
//   xcrun swiftc docs/probes/swiftui-two-text-editors.swift -o /tmp/two-editors
//   for a in $(/tmp/two-editors --list); do /tmp/two-editors $a 2>&1 | grep -v 'Connection\]'; done
//
// Document "0123456789". B's caret/selection is set through its binding, A's likewise; the arm then edits the shared
// string and prints, for BOTH editors, the binding's offsets and the NSTextView's selectedRange, before and after.
// Arms: viaBinding-* mutate the `@State` string (A's caret at 3, B's selection varies); typing-* send
// `insertText(_:replacementRange:)` to A's NSTextView (the AppKit editing path SwiftUI wraps). Hooks stand in for a
// user: `Log.setSel` writes a binding from code, `Log.mutate` writes the string.
//
// RECORDED: see the RECORDED block at the foot of this file.

import SwiftUI
import AppKit
import Observation

@MainActor @Observable final class Store {
    var text = "0123456789"
    var selA: TextSelection?
    var selB: TextSelection?
    func offs(_ s: TextSelection?) -> String {
        guard let s else { return "nil" }
        func o(_ r: Range<String.Index>) -> String {
            "{\(text.distance(from: text.startIndex, to: r.lowerBound)),\(text.distance(from: r.lowerBound, to: r.upperBound))}"
        }
        switch s.indices {
        case .selection(let r): return o(r)
        case .multiSelection(let set): return "[" + set.ranges.map(o).joined(separator: ",") + "]"
        @unknown default: return "?"
        }
    }
    func index(_ n: Int) -> String.Index { text.index(text.startIndex, offsetBy: n) }
    func caret(_ n: Int) -> TextSelection { TextSelection(insertionPoint: index(n)) }
    func range(_ n: Int, _ len: Int) -> TextSelection { TextSelection(range: index(n)..<index(n + len)) }
}

struct Probe: View {
    @Bindable var store: Store
    var body: some View {
        HStack {
            TextEditor(text: $store.text, selection: $store.selA).frame(width: 280, height: 160)
            TextEditor(text: $store.text, selection: $store.selB).frame(width: 280, height: 160)
        }
    }
}

func spin(_ s: Double = 0.2) { RunLoop.current.run(until: Date(timeIntervalSinceNow: s)) }
func textViews(_ v: NSView, _ out: inout [NSTextView]) {
    if let t = v as? NSTextView { out.append(t) }
    for s in v.subviews { textViews(s, &out) }
}
func nsr(_ v: NSTextView) -> String { "{\(v.selectedRange().location),\(v.selectedRange().length)}" }

let armNames = [
    "binding-insert-at-A-caret", "binding-insert-before-B-caret", "binding-insert-after-B-caret",
    "binding-delete-around-B-caret", "binding-insert-before-B-selection", "binding-insert-at-A-caret-equals-B-caret",
    "typing-A-before-B-caret", "typing-A-at-B-caret", "typing-A-after-B-caret",
    "typing-A-deletes-around-B-caret", "typing-A-before-B-selection",
]

@MainActor func run(_ arm: String) {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let sess = CGSessionCopyCurrentDictionary() as? [String: Any]
    print("arm=\(arm) screenLocked=\(sess?["CGSSessionScreenIsLocked"] ?? "absent")")
    let store = Store()
    let host = NSHostingView(rootView: Probe(store: store))
    let win = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 580, height: 180), styleMask: [.titled], backing: .buffered, defer: false)
    win.contentView = host
    win.makeKeyAndOrderFront(nil)
    app.activate(ignoringOtherApps: true)
    spin(0.6)
    var tvs: [NSTextView] = []
    textViews(host, &tvs)
    tvs.sort { $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX }
    guard tvs.count == 2 else { print("found \(tvs.count) NSTextViews; cannot measure"); exit(1) }
    let a = tvs[0], b = tvs[1]
    func show(_ tag: String) {
        print("\(tag): A bind=\(store.offs(store.selA)) ns=\(nsr(a)) | B bind=\(store.offs(store.selB)) ns=\(nsr(b)) | text='\(store.text)'")
    }
    /// Place both selections through the AppKit views (what a user does); SwiftUI mirrors them into the bindings.
    func place(_ ar: NSRange, _ br: NSRange) {
        win.makeFirstResponder(b); b.setSelectedRange(br); spin()
        win.makeFirstResponder(a); a.setSelectedRange(ar); spin()
    }
    func bindingInsert(_ s: String, at n: Int, delete len: Int = 0) {
        let i = store.index(n)
        store.text.replaceSubrange(i..<store.text.index(i, offsetBy: len), with: s)
    }
    func typeInA(_ s: String, _ loc: Int, _ len: Int) {
        a.insertText(s, replacementRange: NSRange(location: loc, length: len))
    }
    switch arm {
    case "binding-insert-at-A-caret":          place(.init(location: 3, length: 0), .init(location: 6, length: 0)); show("before"); bindingInsert("XY", at: 3)
    case "binding-insert-before-B-caret":      place(.init(location: 8, length: 0), .init(location: 6, length: 0)); show("before"); bindingInsert("XY", at: 1)
    case "binding-insert-after-B-caret":       place(.init(location: 1, length: 0), .init(location: 3, length: 0)); show("before"); bindingInsert("XY", at: 8)
    case "binding-delete-around-B-caret":      place(.init(location: 1, length: 0), .init(location: 5, length: 0)); show("before"); bindingInsert("", at: 2, delete: 6)
    case "binding-insert-before-B-selection":  place(.init(location: 1, length: 0), .init(location: 5, length: 3)); show("before"); bindingInsert("XY", at: 1)
    case "binding-insert-at-A-caret-equals-B-caret": place(.init(location: 6, length: 0), .init(location: 6, length: 0)); show("before"); bindingInsert("XY", at: 6)
    case "typing-A-before-B-caret":            place(.init(location: 1, length: 0), .init(location: 6, length: 0)); show("before"); typeInA("XY", 1, 0)
    case "typing-A-at-B-caret":                place(.init(location: 6, length: 0), .init(location: 6, length: 0)); show("before"); typeInA("XY", NSNotFound, 0)
    case "typing-A-after-B-caret":             place(.init(location: 8, length: 0), .init(location: 3, length: 0)); show("before"); typeInA("XY", NSNotFound, 0)
    case "typing-A-deletes-around-B-caret":    place(.init(location: 2, length: 0), .init(location: 5, length: 0)); show("before"); typeInA("", 2, 6)
    case "typing-A-before-B-selection":        place(.init(location: 1, length: 0), .init(location: 5, length: 3)); show("before"); typeInA("XY", 1, 0)
    default: print("unknown arm"); exit(2)
    }
    spin(0.4)
    show("after")
    exit(0)
}

let args = CommandLine.arguments
if args.count > 1 && args[1] == "--list" { armNames.forEach { print($0) }; exit(0) }
guard args.count > 1 else { print("usage: --list | <arm>"); exit(2) }
MainActor.assumeIsolated { run(args[1]) }

// ====================================================================================================
// RECORDED 2026-11-15 (record 325, lane 1), macOS 27.2.1 (26B131), Apple Swift 6.4.2, compiled form, every arm its own process,
// run twice, stdout byte-identical. Screen LOCKED (CGSSessionScreenIsLocked=1), no input sent; windows opened, editing is
// method calls (`place` sets selectedRange through the first responder, `typeInA` is NSTextView.insertText).
//
//   arm=binding-insert-at-A-caret screenLocked=1
//   before: A bind={3,0} ns={3,0} | B bind={6,0} ns={6,0} | text='0123456789'
//   after: A bind={3,0} ns={3,0} | B bind={6,0} ns={6,0} | text='012XY3456789'
//   arm=binding-insert-before-B-caret screenLocked=1
//   before: A bind={8,0} ns={8,0} | B bind={6,0} ns={6,0} | text='0123456789'
//   after: A bind={8,0} ns={8,0} | B bind={6,0} ns={6,0} | text='0XY123456789'
//   arm=binding-insert-after-B-caret screenLocked=1
//   before: A bind={1,0} ns={1,0} | B bind={3,0} ns={3,0} | text='0123456789'
//   after: A bind={1,0} ns={1,0} | B bind={3,0} ns={3,0} | text='01234567XY89'
//   arm=binding-delete-around-B-caret screenLocked=1
//   before: A bind={1,0} ns={1,0} | B bind={5,0} ns={5,0} | text='0123456789'
//   after: A bind={1,0} ns={1,0} | B bind={4,0} ns={4,0} | text='0189'
//   arm=binding-insert-before-B-selection screenLocked=1
//   before: A bind={1,0} ns={1,0} | B bind={5,3} ns={5,3} | text='0123456789'
//   after: A bind={1,0} ns={1,0} | B bind={5,3} ns={5,3} | text='0XY123456789'
//   arm=binding-insert-at-A-caret-equals-B-caret screenLocked=1
//   before: A bind={6,0} ns={6,0} | B bind={6,0} ns={6,0} | text='0123456789'
//   after: A bind={6,0} ns={6,0} | B bind={6,0} ns={6,0} | text='012345XY6789'
//   arm=typing-A-before-B-caret screenLocked=1
//   before: A bind={1,0} ns={1,0} | B bind={6,0} ns={6,0} | text='0123456789'
//   after: A bind={3,0} ns={3,0} | B bind={6,0} ns={6,0} | text='0XY123456789'
//   arm=typing-A-at-B-caret screenLocked=1
//   before: A bind={6,0} ns={6,0} | B bind={6,0} ns={6,0} | text='0123456789'
//   after: A bind={8,0} ns={8,0} | B bind={6,0} ns={6,0} | text='012345XY6789'
//   arm=typing-A-after-B-caret screenLocked=1
//   before: A bind={8,0} ns={8,0} | B bind={3,0} ns={3,0} | text='0123456789'
//   after: A bind={10,0} ns={10,0} | B bind={3,0} ns={3,0} | text='01234567XY89'
//   arm=typing-A-deletes-around-B-caret screenLocked=1
//   before: A bind={2,0} ns={2,0} | B bind={5,0} ns={5,0} | text='0123456789'
//   after: A bind={2,0} ns={2,0} | B bind={4,0} ns={4,0} | text='0189'
//   arm=typing-A-before-B-selection screenLocked=1
//   before: A bind={1,0} ns={1,0} | B bind={5,3} ns={5,3} | text='0123456789'
//   after: A bind={3,0} ns={3,0} | B bind={5,3} ns={5,3} | text='0XY123456789'

// RESULT. SwiftUI does NOT move the other editor's selection. Whether the string changes through the shared binding or by typing
// into A, B's `Binding<TextSelection?>` and its NSTextView.selectedRange keep the OLD offsets (an insertion before B's caret
// leaves B at 6, not 8), clamped only to the new length (deleting 2..8 from a 10-character text leaves B's caret 5 -> 4, the new
// end). Both views agree with each other in every row (binding == NSTextView). Positive control: typing into A moves A's own
// selection (typing-A-* rows, A 1 -> 3). The AppKit shared-storage behaviour (probe appkit-shared-storage-selection) is NOT
// SwiftUI's, so CodeView follows AppKit/Xcode without a divergence (class M).
