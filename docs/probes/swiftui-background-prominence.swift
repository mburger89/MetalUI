// SwiftUI probe: what `EnvironmentValues.backgroundProminence` reads in a row's content, by selection and focus
// (ruling `OG-Q`, record 408, divergence 244; Alloy's file-tree label that switches colour on a selected row).
//
// HOW TO RUN (SA-O's compiled form; no JIT shim):
//
//   xcrun swiftc -swift-version 6 docs/probes/swiftui-background-prominence.swift -o /tmp/bp-probe
//   /tmp/bp-probe > /tmp/bp-1.txt; /tmp/bp-probe > /tmp/bp-2.txt; cmp /tmp/bp-1.txt /tmp/bp-2.txt
//
// INSTRUMENT. Each arm hosts a `List` or `Table` in an `NSHostingView` in a `KeyWindow` (a window whose `isKeyWindow` the arm
// sets: a command-line process is never activated, so `becomeKey()`/`resignKey()` are called by hand after the flag flips,
// the trick of `swiftui-focus-click.swift`), spins the run loop 0.4 s and reads what each row's content logged from its
// `body`. A row logs `standard` or `increased`; `a>b` is the history (the value at first build, then after a change), and
// `-` is a row whose body did not run again (no change reached it). "Emphasized" = the window is key and the `NSTableView` is
// the first responder, set after the first draw; the arms that resign the key or move the responder read the same rows
// again. A row reads the value one container down (`HStack { Inner }`), as Apple's discussion of the property says it must
// ("nested in additional stack containers within the row"); `BP8` reads it in the row's own child, for contrast. The selected
// rows are set by the binding (`BP1`..`BP4`, `BP7`..`BP17`) or by the table's own `selectRowIndexes` (`BP5`, `BP6`).
//
// RECORDED 2026-11-24, macOS 27.2.1, Apple Swift 6.4.2 (swiftlang-6.4.2.1.9). Compiled form, run twice: stdout byte-identical
// (32 lines, shasum 53432ad7185b6bc70779fbb30646d32fcdea7d03), exit 0.
//
//   backgroundProminence probe
//   --- List, multi-select {0,2}, ForEach rows
//     BP1 selected {0,2}, window key, list first responder (emphasized): row0=standard>increased row1=standard row2=standard>increased
//     BP2 same window after resignKey (unemphasized): row0=standard row1=- row2=standard
//     BP3 window key again, then the first responder moved off the list: row0=increased>standard row1=- row2=increased>standard
//     BP4 window never key: row0=standard row1=standard row2=standard
//   --- selection changed after show (the table selects row 2, as a click does)
//     BP5 the table moves the selection 0 -> 2, emphasized: row0=standard row1=- row2=increased
//     BP6 then resignKey: row0=- row1=- row2=standard
//     BP7 .listStyle(.sidebar), selection 1, emphasized: a=standard b=standard>increased
//     BP7 .listStyle(.inset), selection 1, emphasized: a=standard b=standard>increased
//     BP7 .listStyle(.plain), selection 1, emphasized: a=standard b=standard>increased
//     BP8 the row's own child reads directly (no stack), selection 1, emphasized: a=standard b=standard
//   --- flat List, selection Int? = 1
//     BP9 flat List(selection: Int?) = 1, emphasized: a=standard b=standard>increased c=standard
//   --- List without selection
//     BP10 List without selection: a=standard b=standard
//   --- DisclosureGroup rows in a List with selection (one arm per selected row)
//     BP11 DisclosureGroup rows, selected header: header=standard>increased child=standard child2=standard leaf=standard
//     BP11 DisclosureGroup rows, selected child: header=standard child=standard child2=standard leaf=standard
//     BP11 DisclosureGroup rows, selected leaf: header=standard child=standard child2=standard leaf=standard>increased
//   --- OutlineGroup rows (root expanded by the list's own disclosure)
//     BP12 OutlineGroup, selected root: root=standard>increased
//   --- List(_, children:, selection)
//     BP13 List(_, children:), selected root: root=standard>increased
//   --- nested rows: DisclosureGroup content row child2 selected; List(children:) expanded with k1 selected
//     BP14 DisclosureGroup content row selected: child2: header=standard child=standard child2=standard leaf=standard
//     BP15 List(children:) expanded, k1 selected: root=standard k1=standard>increased k2=standard
//   --- Table rows, selection {1}
//     BP16 Table, selection {1}, emphasized: t0=standard t1=standard>increased t2=standard
//   --- plain stack and explicit override
//     BP17 outside any List, and an explicit write: plain=standard forced=increased
//
// READING.
//   - A selected row's content reads `.increased` only while the selection is emphasized (BP1: standard at first build, then
//     increased once the window is key and the list the first responder); resigning the key (BP2, BP6) or moving the first
//     responder off the list (BP3) turns it back to `.standard`; a window never key never reads `.increased` (BP4).
//     The `ListStyle` does not matter (BP7). A List with no selection never reads it (BP10).
//   - It moves with the selection: the old row `standard`, the new row `increased` (BP5), and a deselect clears it.
//   - A multi-selection marks every selected row (BP1: rows 0 and 2).
//   - A `DisclosureGroup` header and a leaf row are `.increased` when selected (BP11), an `OutlineGroup` row and a
//     `List(_:children:)` row too (BP12, BP13, BP15). A row **inside a `DisclosureGroup`'s content** reads `.standard` though
//     the table selects it (BP11 child, BP14).
//   - A `Table` row's cell reads `.increased` when selected (BP16).
//   - The row's own child read directly (no container) reads `.standard` always (BP8): the value is only in the environment
//     of what the row nests.
//   - An explicit `.environment(\.backgroundProminence, .increased)` sets it for its subtree (BP17).
//   Foreground styles (`.primary`, `.secondary`) adapt in SwiftUI under `.increased` (Apple's discussion); this probe reads the
//   value, not the drawn colour, so that half is Apple's text, not a measurement.

import AppKit
import SwiftUI

nonisolated(unsafe) var log: [String: String] = [:]

/// What a row's content reads. It is read one container down, as Apple's discussion of the property says it must be
/// ("nested in additional stack containers within the row"); `Direct` reads in the row's own child, for contrast.
struct Probe: View {
    let name: String
    var body: some View { HStack { Inner(name: name) } }
}

struct Direct: View {
    let name: String
    @Environment(\.backgroundProminence) var prominence
    var body: some View {
        let _ = { log[name, default: ""] += (log[name] == nil ? "" : ">") + (prominence == .increased ? "increased" : "standard") }()
        Text(name)
    }
}

struct Inner: View {
    let name: String
    @Environment(\.backgroundProminence) var prominence
    var body: some View {
        let _ = { log[name, default: ""] += (log[name] == nil ? "" : ">") + (prominence == .increased ? "increased" : "standard") }()
        Text(name)
    }
}

@MainActor func spin(_ s: Double = 0.4) { RunLoop.current.run(until: Date(timeIntervalSinceNow: s)) }

@MainActor func findTable(_ v: NSView) -> NSTableView? {
    if let t = v as? NSTableView { return t }
    for s in v.subviews { if let t = findTable(s) { return t } }
    return nil
}

/// A window whose key state the arm sets (a CLI process cannot activate itself; `swiftui-focus-click.swift`'s trick).
final class KeyWindow: NSWindow {
    nonisolated(unsafe) var keyed = true
    override var isKeyWindow: Bool { keyed }
    override var canBecomeKey: Bool { true }
    override var isMainWindow: Bool { keyed }
}

/// Flips the window's key state the way AppKit does: the flag, then `becomeKey`/`resignKey` (which post the notifications).
@MainActor func setKey(_ w: KeyWindow, _ on: Bool) {
    w.keyed = on
    if on { w.becomeKey(); w.becomeMain() } else { w.resignKey(); w.resignMain() }
    spin()
}

@MainActor func host<V: View>(_ view: V, focus: Bool = true, then: (KeyWindow) -> Void = { _ in }) -> KeyWindow {
    let w = KeyWindow(contentRect: NSRect(x: 100, y: 100, width: 300, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    let h = NSHostingView(rootView: view)
    w.contentView = h
    w.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    spin()
    if focus, let t = findTable(h) { w.makeFirstResponder(t) }
    if focus { setKey(w, true) }   // AppKit's own `becomeKey`: a CLI process is never activated, so it is posted by hand
    spin()
    then(w)
    if let t = findTable(h) {
        ()
    }
    return w
}

@MainActor func report(_ arm: String, _ keys: [String]) {
    print("  \(arm): " + keys.map { "\($0)=\(log[$0] ?? "-")" }.joined(separator: " "))
    log = [:]
}

struct ListArm: View {
    @State var sel: Set<Int>
    var body: some View {
        List(selection: $sel) {
            ForEach(0..<3, id: \.self) { i in Probe(name: "row\(i)").tag(i) }
        }
    }
}

struct FlatArm: View {
    @State var sel: Int? = 1
    var body: some View {
        List(selection: $sel) { Probe(name: "a").tag(0); Probe(name: "b").tag(1); Probe(name: "c").tag(2) }
    }
}

struct StyledArm: View {
    let style: Int
    @State var sel: Int? = 1
    var body: some View {
        switch style {
        case 0: List(selection: $sel) { Probe(name: "a").tag(0); Probe(name: "b").tag(1) }.listStyle(.sidebar)
        case 1: List(selection: $sel) { Probe(name: "a").tag(0); Probe(name: "b").tag(1) }.listStyle(.inset)
        default: List(selection: $sel) { Probe(name: "a").tag(0); Probe(name: "b").tag(1) }.listStyle(.plain)
        }
    }
}

struct NoSelArm: View {
    var body: some View { List { Probe(name: "a"); Probe(name: "b") } }
}

struct OutlineArm: View {
    @State var sel: Set<String>
    var body: some View {
        List(selection: $sel) {
            DisclosureGroup(isExpanded: .constant(true)) {
                Probe(name: "child").tag("child")
                Probe(name: "child2").tag("child2")
            } label: { Probe(name: "header").tag("header") }
            Probe(name: "leaf").tag("leaf")
        }
    }
}

struct OutlineGroupArm: View {
    struct Node: Identifiable { let id: String; var kids: [Node]? }
    @State var sel: Set<String>
    let tree = [Node(id: "root", kids: [Node(id: "k1", kids: nil), Node(id: "k2", kids: nil)])]
    var body: some View {
        List(selection: $sel) {
            OutlineGroup(tree, children: \.kids) { n in Probe(name: n.id).tag(n.id) }
        }
    }
}

struct ChildrenListArm: View {
    struct Node: Identifiable { let id: String; var kids: [Node]? }
    @State var sel: String?
    let tree = [Node(id: "root", kids: [Node(id: "k1", kids: nil), Node(id: "k2", kids: nil)])]
    var body: some View {
        List(tree, children: \.kids, selection: $sel) { n in Probe(name: n.id) }
    }
}

struct TableArm: View {
    struct Row: Identifiable { let id: Int }
    @State var sel: Set<Int> = [1]
    var body: some View {
        Table(of: Row.self, selection: $sel) {
            TableColumn("c") { (r: Row) in Probe(name: "t\(r.id)") }
        } rows: { ForEach([Row(id: 0), Row(id: 1), Row(id: 2)]) { TableRow($0) } }
    }
}

struct DirectArm: View {
    @State var sel: Int? = 1
    var body: some View { List(selection: $sel) { Direct(name: "a").tag(0); Direct(name: "b").tag(1) } }
}

struct ModifierArm: View {
    var body: some View {
        VStack {
            Probe(name: "plain")
            Probe(name: "forced").environment(\.backgroundProminence, .increased)
        }
    }
}

NSApplication.shared.setActivationPolicy(.regular)
print("backgroundProminence probe")
print("--- List, multi-select {0,2}, ForEach rows")
var w = host(ListArm(sel: [0, 2]))
report("BP1 selected {0,2}, window key, list first responder (emphasized)", ["row0", "row1", "row2"])
setKey(w, false)
report("BP2 same window after resignKey (unemphasized)", ["row0", "row1", "row2"])
setKey(w, true); w.makeFirstResponder(w.contentView); spin()
report("BP3 window key again, then the first responder moved off the list", ["row0", "row1", "row2"])
log = [:]
_ = host(ListArm(sel: [0, 2]), focus: false) { setKey($0, false) }
report("BP4 window never key", ["row0", "row1", "row2"])
log = [:]
print("--- selection changed after show (the table selects row 2, as a click does)")
log = [:]
w = host(ListArm(sel: [0])) { _ in }
log = [:]
if let t = findTable(w.contentView!) { t.selectRowIndexes([2], byExtendingSelection: false); spin() }
report("BP5 the table moves the selection 0 -> 2, emphasized", ["row0", "row1", "row2"])
log = [:]
setKey(w, false)
report("BP6 then resignKey", ["row0", "row1", "row2"])
for (i, n) in ["sidebar", "inset", "plain"].enumerated() {
    log = [:]
    _ = host(StyledArm(style: i))
    report("BP7 .listStyle(.\(n)), selection 1, emphasized", ["a", "b"])
}
log = [:]
_ = host(DirectArm())
report("BP8 the row's own child reads directly (no stack), selection 1, emphasized", ["a", "b"])
print("--- flat List, selection Int? = 1")
_ = host(FlatArm())
report("BP9 flat List(selection: Int?) = 1, emphasized", ["a", "b", "c"])
print("--- List without selection")
_ = host(NoSelArm())
report("BP10 List without selection", ["a", "b"])
print("--- DisclosureGroup rows in a List with selection (one arm per selected row)")
for pick in ["header", "child", "leaf"] {
    log = [:]
    _ = host(OutlineArm(sel: [pick]))
    report("BP11 DisclosureGroup rows, selected \(pick)", ["header", "child", "child2", "leaf"])
}
print("--- OutlineGroup rows (root expanded by the list's own disclosure)")
for pick in ["root"] {
    log = [:]
    _ = host(OutlineGroupArm(sel: [pick]))
    report("BP12 OutlineGroup, selected \(pick)", ["root"])
}
print("--- List(_, children:, selection)")
log = [:]
_ = host(ChildrenListArm(sel: "root"))
report("BP13 List(_, children:), selected root", ["root"])
print("--- nested rows: DisclosureGroup content row child2 selected; List(children:) expanded with k1 selected")
log = [:]
_ = host(OutlineArm(sel: ["child2"]))
report("BP14 DisclosureGroup content row selected: child2", ["header", "child", "child2", "leaf"])
log = [:]
do {
    let w = host(ChildrenListArm(sel: "k1"))
    if let t = findTable(w.contentView!) as? NSOutlineView {
        if let item = t.item(atRow: 0) { t.expandItem(item) }; spin()
        t.selectRowIndexes([1], byExtendingSelection: false); spin()
        setKey(w, true)
    }
    report("BP15 List(children:) expanded, k1 selected", ["root", "k1", "k2"])
}
print("--- Table rows, selection {1}")
_ = host(TableArm())
report("BP16 Table, selection {1}, emphasized", ["t0", "t1", "t2"])
print("--- plain stack and explicit override")
_ = host(ModifierArm(), focus: false)
report("BP17 outside any List, and an explicit write", ["plain", "forced"])
