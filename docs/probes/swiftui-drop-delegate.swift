// SwiftUI probe: `DropDelegate` (R3-10 item 5, record 192, rulings DE-A…DE-J in
// docs/superpowers/2026-11-01-drop-delegate-decisions.md) — which callbacks run
// and in what order, what `validateDrop`, `dropUpdated`'s proposal and
// `performDrop` decide, the NSDragOperation SwiftUI answers, type filtering by
// conformance, and what wins when two drop modifiers share a view.
//
// HOW TO RUN (SA-O):
//
//   /usr/bin/swift docs/probes/swiftui-drop-delegate.swift
//
// THE INSTRUMENT. Group R of docs/probes/swiftui-drag-and-drop.swift: SwiftUI's
// destination view (`_PlatformDraggingDestinationView`, found by
// `registeredDraggedTypes`) driven with a fake `NSDraggingInfo` over a private
// pasteboard. **Trusted for which callbacks run, their ORDER and the
// NSDragOperation answered. NOT trusted for spatial readings** (SwiftUI picks
// the destination from the live pointer, not `draggingLocation`) **nor for
// whether `performDrop` runs after a refusal** — the fake always calls
// prepare+perform, so an arm that shows `perf=` after `none` is the fake's
// artifact (AppKit does not call `performDragOperation` after a `none` answer).
//
// ARM LANGUAGE. Steps: e=draggingEntered, u=draggingUpdated, x=draggingExited,
// p=prepare+perform+conclude. Each step prints its answer (copy/move/none) then,
// in brackets, the delegate's callbacks since the previous step: V=validateDrop
// E=dropEntered U=dropUpdated X=dropExited P=performDrop, T=<n> a `.onDrop`/
// `.dropDestination` action. A proposal step changes what `dropUpdated`
// answers for the NEXT step: >move >copy >forbidden >cancel >nil.
//
// SEPARATING ARMS. D0 (validate true) against D1 (false). F1b (png onto [.png])
// against F1 (png onto [.plainText]). D3 (move) against D2 (nil: copy).
//
// READING. See the plan in docs/superpowers/2026-11-01-drop-delegate-decisions.md:
// DE-B (call order), DE-C (validate), DE-D (proposals), DE-E (perform), DE-G
// (coexistence). Two readings rest on the fake harness only and are labelled so
// there: F5 (a nil proposal after `.move` answers copy again) and F2 (`dropExited`
// after a `validateDrop` that answered false).
//
// RECORDED 2026-11-02, macOS 27.0, Apple Swift 6.4, by `/usr/bin/swift` (interpreted),
// run twice: stdout byte-identical (27 lines), exit 0, stderr empty both times.
// D1's trailing `[U,P]` after `none` is the fake's artifact (see THE INSTRUMENT):
// MetalUI ruling DE-E performs nothing after a refusal. Output, verbatim:
//
//   --- D: one delegate on onDrop(of: [.plainText])
//     D0 enter, move, drop: e=copy [V,E,U] u=copy [U] prep=true perf=true [U,P]
//     D0x enter, move, leave: e=copy [V,E,U] u=copy [U] x [X]
//     D1 validateDrop false: enter, move, drop, leave: e=none [V] u=none prep=true perf=true [U,P] x [X]
//     D2 dropUpdated nil: e=copy [V,E,U] u=copy [U]
//     D2b only performDrop (all defaults): e=copy u=copy prep=true perf=true [P]
//     D3 dropUpdated .move: e=move [V,E,U] u=move [U] prep=true perf=true [U,P]
//     D3b .move, source mask copy only: e=move [V,E,U]
//     D4 dropUpdated .forbidden: e=none [V,E,U] u=none [U] x [X]
//     D5 dropUpdated .cancel: e=none [V,E,U] u=none u=none x [X]
//     D7 performDrop returns false: e=copy [V,E,U] prep=true perf=false [U,P]
//     D8 two strings: e=copy [V,E,U]
//     D9 .copy, source mask move only: e=copy [V,E,U]
//   --- F: filtering, sequences, coexistence
//     F1 png onto onDrop(of: [.plainText]): e=none u=none x
//     F1b png onto onDrop(of: [.png]): e=copy [V,E,U] u=copy [U] x [X]
//     F1c plain text onto onDrop(of: [.item]): e=copy [V,E,U]
//     F2 validateDrop false, then exit: e=none [V] x [X]
//     F4 cancel, then more moves, exit: e=none [V,E,U] u=none u=none x [X]
//     F5 move, then nil: e=move [V,E,U] u=copy [U] u=copy [U]
//     F6 forbidden, then copy: e=none [V,E,U] u=copy [U]
//     F7 copy, forbidden, nil: e=copy [V,E,U] u=none [U] u=copy [U]
//     F8 .onDrop(A).onDrop(B): e=copy prep=true perf=true [B]
//     F9 .dropDestination.onDrop(B): e=copy [V,E,U] u=copy [U] prep=true perf=true [U,P]
//     F10 .onDrop(A).dropDestination: e=copy u=copy prep=true perf=true [T=B]
//     F11 item counts in dropUpdated: e=copy [V,E,U]
//     F11 hasItems=true n=2

import AppKit
import SwiftUI
import UniformTypeIdentifiers

setvbuf(stdout, nil, _IOLBF, 0)

enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    static func add(_ s: String) { lines.append(s) }
    static func take() -> String { defer { lines = [] }; return lines.isEmpty ? "-" : lines.joined(separator: ",") }
}
@MainActor func spin(_ s: Double = 0.2) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

final class FirstMouseHost<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - fake dragging info (group R of swiftui-drag-and-drop.swift)

final class FakeDrag: NSObject, NSDraggingInfo {
    let window: NSWindow
    var location: NSPoint
    let pb: NSPasteboard
    var mask: NSDragOperation = .every
    init(window: NSWindow, location: NSPoint, pb: NSPasteboard) { self.window = window; self.location = location; self.pb = pb }
    var draggingDestinationWindow: NSWindow? { window }
    var draggingSourceOperationMask: NSDragOperation { mask }
    var draggingLocation: NSPoint { location }
    var draggedImageLocation: NSPoint { location }
    var draggedImage: NSImage? { nil }
    var draggingPasteboard: NSPasteboard { pb }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 7 }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination: Bool = false
    var numberOfValidItemsForDrop: Int = 1
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?,
                                classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:],
                                using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func resetSpringLoading() {}
}

nonisolated(unsafe) var pasteboardCounter = 0
func pasteboard(_ fill: (NSPasteboard) -> Void) -> NSPasteboard {
    pasteboardCounter += 1
    let pb = NSPasteboard(name: NSPasteboard.Name("metalui-drop-delegate-probe-\(getpid())-\(pasteboardCounter)"))
    pb.clearContents()
    fill(pb)
    return pb
}
let pbString = { pasteboard { _ = $0.writeObjects(["hello" as NSString]) } }
let pbTwoStrings = { pasteboard { _ = $0.writeObjects(["one" as NSString, "two" as NSString]) } }
let pbPNG = { pasteboard { $0.setData(Data([0x89, 0x50, 0x4e, 0x47]), forType: .png) } }

@MainActor func makeWindow<V: View>(_ view: V) -> NSWindow {
    let w = NSWindow(contentRect: CGRect(x: 200, y: 200, width: 200, height: 200),
                     styleMask: [.titled], backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    w.contentView = FirstMouseHost(rootView: view)
    w.level = .floating
    w.makeKeyAndOrderFront(nil)
    w.contentView!.layoutSubtreeIfNeeded()
    spin()
    return w
}
@MainActor func allViews(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(allViews) }
@MainActor func destinationView(_ w: NSWindow) -> NSView {
    allViews(w.contentView!).first { !$0.registeredDraggedTypes.isEmpty } ?? w.contentView!
}
func op(_ o: NSDragOperation) -> String {
    if o.isEmpty { return "none" }
    var s: [String] = []
    if o.contains(.copy) { s.append("copy") }
    if o.contains(.link) { s.append("link") }
    if o.contains(.generic) { s.append("generic") }
    if o.contains(.move) { s.append("move") }
    return s.joined(separator: "+")
}

// MARK: - the delegate under test

final class Probe: DropDelegate {
    nonisolated(unsafe) static var proposal: DropProposal? = nil
    nonisolated(unsafe) static var validates = true
    nonisolated(unsafe) static var performs = true
    nonisolated(unsafe) static var itemCount = ""
    func validateDrop(info: DropInfo) -> Bool { Log.add("V"); return Probe.validates }
    func dropEntered(info: DropInfo) { Log.add("E") }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        Log.add("U")
        Probe.itemCount = "hasItems=\(info.hasItemsConforming(to: [.plainText])) n=\(info.itemProviders(for: [.plainText]).count)"
        return Probe.proposal
    }
    func dropExited(info: DropInfo) { Log.add("X") }
    func performDrop(info: DropInfo) -> Bool { Log.add("P"); return Probe.performs }
}
/// Only `performDrop`: every other method is the protocol's default.
final class Minimal: DropDelegate {
    func performDrop(info: DropInfo) -> Bool { Log.add("P"); return true }
}

@MainActor func reset() {
    Probe.proposal = nil; Probe.validates = true; Probe.performs = true; _ = Log.take()
}

let C = CGPoint(x: 100, y: 100)

/// A scripted drag over `w`: see the header's arm language.
@MainActor func script(_ w: NSWindow, _ pb: NSPasteboard, _ steps: [String], mask: NSDragOperation = .every) -> String {
    let dest = destinationView(w)
    let h = w.contentView!.bounds.height
    let info = FakeDrag(window: w, location: NSPoint(x: C.x, y: h - C.y), pb: pb)
    info.mask = mask
    var out: [String] = []
    _ = Log.take()
    for s in steps {
        switch s {
        case "e": out.append("e=\(op(dest.draggingEntered(info)))")
        case "u": out.append("u=\(op(dest.draggingUpdated(info)))")
        case "x": dest.draggingExited(info); out.append("x")
        case "p":
            let prep = dest.prepareForDragOperation(info)
            let perf = dest.performDragOperation(info)
            dest.concludeDragOperation(info)
            out.append("prep=\(prep) perf=\(perf)")
        case ">move": Probe.proposal = DropProposal(operation: .move)
        case ">copy": Probe.proposal = DropProposal(operation: .copy)
        case ">forbidden": Probe.proposal = DropProposal(operation: .forbidden)
        case ">cancel": Probe.proposal = DropProposal(operation: .cancel)
        case ">nil": Probe.proposal = nil
        default: break
        }
        spin(0.25)
        let l = Log.take()
        if l != "-" { out.append("[\(l)]") }
    }
    return out.joined(separator: " ")
}

@MainActor func arm<V: View>(_ label: String, _ view: V, _ pb: NSPasteboard, _ steps: [String],
                             mask: NSDragOperation = .every, setup: () -> Void = {}) {
    reset()
    setup()
    let w = makeWindow(view)
    print("  \(label): \(script(w, pb, steps, mask: mask))")
    w.orderOut(nil)
}

func box() -> some View { Color.blue.frame(width: 200, height: 200) }
func delegateBox(_ types: [UTType] = [.plainText]) -> some View { box().onDrop(of: types, delegate: Probe()) }

@MainActor func run() {
    print("--- D: one delegate on onDrop(of: [.plainText])")
    arm("D0 enter, move, drop", delegateBox(), pbString(), ["e", "u", "p"])
    arm("D0x enter, move, leave", delegateBox(), pbString(), ["e", "u", "x"])
    arm("D1 validateDrop false: enter, move, drop, leave", delegateBox(), pbString(), ["e", "u", "p", "x"], setup: { Probe.validates = false })
    arm("D2 dropUpdated nil", delegateBox(), pbString(), ["e", "u"])
    arm("D2b only performDrop (all defaults)", box().onDrop(of: [.plainText], delegate: Minimal()), pbString(), ["e", "u", "p"])
    arm("D3 dropUpdated .move", delegateBox(), pbString(), [">move", "e", "u", "p"])
    arm("D3b .move, source mask copy only", delegateBox(), pbString(), [">move", "e"], mask: .copy)
    arm("D4 dropUpdated .forbidden", delegateBox(), pbString(), [">forbidden", "e", "u", "x"])
    arm("D5 dropUpdated .cancel", delegateBox(), pbString(), [">cancel", "e", "u", "u", "x"])
    arm("D7 performDrop returns false", delegateBox(), pbString(), ["e", "p"], setup: { Probe.performs = false })
    arm("D8 two strings", delegateBox(), pbTwoStrings(), ["e"])
    arm("D9 .copy, source mask move only", delegateBox(), pbString(), [">copy", "e"], mask: .move)
    print("--- F: filtering, sequences, coexistence")
    arm("F1 png onto onDrop(of: [.plainText])", delegateBox(), pbPNG(), ["e", "u", "x"])
    arm("F1b png onto onDrop(of: [.png])", delegateBox([.png]), pbPNG(), ["e", "u", "x"])
    arm("F1c plain text onto onDrop(of: [.item])", delegateBox([.item]), pbString(), ["e"])
    arm("F2 validateDrop false, then exit", delegateBox(), pbString(), ["e", "x"], setup: { Probe.validates = false })
    arm("F4 cancel, then more moves, exit", delegateBox(), pbString(), [">cancel", "e", "u", "u", "x"])
    arm("F5 move, then nil", delegateBox(), pbString(), [">move", "e", ">nil", "u", "u"])
    arm("F6 forbidden, then copy", delegateBox(), pbString(), [">forbidden", "e", ">copy", "u"])
    arm("F7 copy, forbidden, nil", delegateBox(), pbString(), [">copy", "e", ">forbidden", "u", ">nil", "u"])
    arm("F8 .onDrop(A).onDrop(B)", box().onDrop(of: [.plainText], delegate: Probe()).onDrop(of: [.plainText], isTargeted: nil) { _, _ in Log.add("B"); return true },
        pbString(), ["e", "p"])
    arm("F9 .dropDestination.onDrop(B)", box().dropDestination(for: String.self, action: { _, _ in Log.add("T=A"); return true }).onDrop(of: [.plainText], delegate: Probe()),
        pbString(), ["e", "u", "p"])
    arm("F10 .onDrop(A).dropDestination", box().onDrop(of: [.plainText], delegate: Probe()).dropDestination(for: String.self, action: { _, _ in Log.add("T=B"); return true }),
        pbString(), ["e", "u", "p"])
    arm("F11 item counts in dropUpdated", delegateBox(), pbTwoStrings(), ["e"])
    print("  F11 \(Probe.itemCount)")
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
MainActor.assumeIsolated {
    app.activate(ignoringOtherApps: true)
    run()
}
