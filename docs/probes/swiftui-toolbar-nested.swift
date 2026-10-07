// SwiftUI probe: where a `.toolbar` below the window's root view goes — the
// evidence for MD-S (port-gaps-medium; MetalUI's `.toolbar` cannot be a window
// root, divergence 120's rule, so it is written on a nested element).
//
// QUESTIONS.
// - NT: does a `.toolbar` on a nested view (not the hosting controller's root)
//   reach the window's NSToolbar, and in what order are several merged (an
//   outer one on a VStack and one on each of two children)?
// - IF: a nested `.toolbar` under an `if false` contributes nothing.
// - PO: a `.toolbar` inside a presented `.popover`'s content — does it reach
//   the main window's toolbar?
//
// INSTRUMENTS. A real NSWindow per arm (unlocked screen —
// appkit-screen-lock-state.swift), an `NSHostingController` with
// `sceneBridgingOptions = [.toolbars, .title]`, a 1.0 s spin, then the window
// toolbar's item labels in `items` order. Each item is a segmented `Picker`
// whose title is the item's name, because a Picker's title becomes the
// NSToolbarItem's `label` (swiftui-toolbar.swift TB1: label "Mode"), so each
// item is identifiable by label.
//
// POSITIVE CONTROL. NT0: the root view's own `.toolbar { A }` → one item "A".
// SEPARATING ARM. IF0 (`if true`, the nested item present) vs IF1 (`if false`,
// absent); NT1 (three toolbars) vs NT0 (one).
//
// HOW TO RUN (compiled form, SA-O):
//
//   xcrun swiftc docs/probes/swiftui-toolbar-nested.swift -o /tmp/md-toolbar-nested && /tmp/md-toolbar-nested
//
// RECORDED and READING: the block at the end of this file.

import AppKit
import SwiftUI

@MainActor func spin(_ s: Double = 1.0) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

struct Item: ToolbarContent {
    let name: String
    var body: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Picker(name, selection: .constant(0)) { Text(name).tag(0) }.pickerStyle(.segmented)
        }
    }
}

struct Child: View {
    let name: String
    var body: some View { Color.gray.opacity(0.2).frame(width: 100, height: 50).toolbar { Item(name: name) } }
}

var windows: [NSWindow] = []
@MainActor func open<V: View>(_ label: String, _ v: V) {
    let c = NSHostingController(rootView: v.frame(width: 400, height: 200))
    c.sceneBridgingOptions = [.toolbars, .title]
    let w = NSWindow(contentViewController: c)
    w.isReleasedWhenClosed = false
    w.title = label
    w.setFrameOrigin(NSPoint(x: 100, y: 100))
    w.makeKeyAndOrderFront(nil)
    spin()
    windows.append(w)
    let labels = w.toolbar?.items.map { $0.label.isEmpty ? "<\($0.itemIdentifier.rawValue.hasPrefix("NSToolbar") ? $0.itemIdentifier.rawValue : "unlabelled")>" : $0.label }
    print("\(label): \(labels.map { "items=\($0)" } ?? "toolbar nil")")
}

@MainActor func run() {
    NSApplication.shared.setActivationPolicy(.regular)
    NSApplication.shared.activate()
    open("NT0 root toolbar A", Color.clear.toolbar { Item(name: "A") })
    open("NT1 outer A on VStack { B-child; C-child }",
         VStack { Child(name: "B"); Child(name: "C") }.toolbar { Item(name: "A") })
    open("NT2 nested only B-child, C-child", VStack { Child(name: "B"); Child(name: "C") })
    open("IF0 if true { B-child }", VStack { if true { Child(name: "B") }; Color.clear })
    open("IF1 if false { B-child }", VStack { if false { Child(name: "B") }; Color.clear })
    open("PO popover content has P; root has A",
         Color.clear
            .popover(isPresented: .constant(true)) { Child(name: "P").padding() }
            .toolbar { Item(name: "A") })
    let popovers = NSApp.windows.filter { "\(type(of: $0))".contains("Popover") && $0.isVisible }
    print("PO popover windows visible=\(popovers.count) toolbars on them=\(popovers.filter { $0.toolbar != nil }.count)")
}

MainActor.assumeIsolated { run() }

// RECORDED 2026-10-06 on macOS 27.0.1 (26A434), Apple Swift 6.4
// (swiftlang-6.4.0.33.1), screen unlocked (appkit-screen-lock-state.swift: no
// CGSSessionScreenIsLocked line, displayAsleep main: 0), compiled form. Run three
// times by the critic session; the three outputs (7 lines) are byte-identical.
//
// READING (the authority for MD-S and for MD-I item 5's order):
// - NT0 (positive control): the root's own toolbar -> ["A"].
// - NT1: an outer `.toolbar` on a VStack and one on each child merge into one
//   NSToolbar in pre-order: outer first, then the children in declaration order
//   (["A", "B", "C"]). NT2: nested toolbars alone reach the window.
// - IF0/IF1 (separating arm): a nested toolbar under `if true` contributes; under
//   `if false` there is no toolbar at all.
// - PO: a popover is presented (one visible popover window) and the `.toolbar`
//   inside its content reaches neither the main window's toolbar (["A"] only)
//   nor the popover's window (no toolbar on it).
//
// OUTPUT:
// NT0 root toolbar A: items=["A"]
// NT1 outer A on VStack { B-child; C-child }: items=["A", "B", "C"]
// NT2 nested only B-child, C-child: items=["B", "C"]
// IF0 if true { B-child }: items=["B"]
// IF1 if false { B-child }: toolbar nil
// PO popover content has P; root has A: items=["A"]
// PO popover windows visible=1 toolbars on them=0
