// SwiftUI probe: hierarchical `List` (an outline), measured through the NSOutlineView SwiftUI builds on macOS (design
// docs/superpowers/specs/2026-11-15-outline-disclosure-design.md, section 7).
//
// Evidence for rulings OG-A... in docs/superpowers/2026-11-15-outline-disclosure-decisions.md. A companion probe,
// docs/probes/swiftui-disclosure-group.swift, covers the standalone DisclosureGroup.
//
// HOW TO RUN (ruling SA-O's two forms; an arm name restricts the run, e.g. `... K7 N`; no argument runs everything, about 4 minutes
// of wall time, most of it run-loop turns; run it in the foreground, a backgrounded run is throttled to a crawl):
//
//   /usr/bin/swift docs/probes/swiftui-outline.swift
//   xcrun swiftc docs/probes/swiftui-outline.swift -o /tmp/outline-probe && /tmp/outline-probe
//
// Arms: L1 L3 L4 (look and geometry, P-L1..P-L4), K K7 (keys, P-K1..P-K7), C1 (chevron click, P-C1), E5 (uncontrolled expansion
// retention, P-E5), I1 (identity across parents, P-I1), N (animation, P-N1..P-N3), A (accessibility, P-A1/P-A2), M (contextMenu and
// primaryAction, P-M1..P-M4), R1 (reveal in one transaction, P-R1). P-A3 (standalone DisclosureGroup AX) is in the companion probe.
//
// THE INSTRUMENT. A `List(selection:)` hosted in an ordered-in 300 x 400 window is a `SwiftUIOutlineListView` (an NSOutlineView
// subclass) even for a list with no hierarchy. Geometry is read from it directly: `rect(ofRow:)`, `level(forRow:)`,
// `frameOfOutlineCell(atRow:)`, `indentationPerLevel`, the row views and their layers; labels report their frame with
// `onGeometryChange(for: CGRect.self) { $0.frame(in: .global) }`. Keys and clicks are NSEvents (never CGEvents, nothing posted to the
// system): keys go to `window.sendEvent` with the outline view as first responder; a click on the disclosure triangle goes through
// the NSApp event queue (the NSButton tracks to the queued mouse-up); a click anywhere else goes to `NSOutlineView.mouseDown` with
// the mouse-up queued first, because the SwiftUI cell hosting view swallows a synthetic event. The process is not the active app, so
// the window class answers `isKeyWindow` true (a table view in a non-key window ignores clicks). Context menus are built with
// `NSOutlineView.menu(for:)`; a real right-click popup is not driven (it would run a modal menu loop).
// Binding writes are logged with the run-loop turn they happen in (a CFRunLoopObserver counts turns; "turn +N" is relative to the
// arm's reset, and jitters by 1 or 2 between runs).
// Three forms are compared everywhere: `List(_:children:)`, `List { OutlineGroup }` and (the only one with an app-owned expansion
// binding) `List { ForEach { DisclosureGroup(isExpanded:) } }` with a recursive row view and a model holding the expanded set.
// The tree: A [ A/B [ A/B/D, A/B/E ], A/C ], Z, M [ M/N ]. In a snapshot line `*` is the selected row, `+` an expanded group,
// `-` a collapsed one.
//
// POSITIVE CONTROLS / SEPARATING ARMS. P-L1's `flat` list (no `children`) is the control for "a leaf reserves no chevron slot" and
// separates the outline cell from the list. K2c and K3b (a leaf and a collapsed root) are the controls for "the key does nothing":
// they leave the snapshot and the binding untouched. P-C1's C1d (a click on the row body) is the control that the click helper
// selects at all, so that C1a/C1b (no selection change from the chevron) mean something. P-N's N4 (a bare `expandItem`) is the
// AppKit control that the sampler sees the row slide, and N2 (a bare binding write, which snaps) separates it from N3. P-R1's
// R1d and R1e (scrollTo after a settled expansion, and to an already expanded off-screen row) are the controls that `scrollTo`
// lands at all, so that R1a-R1c and R1f (it does not, in the same transaction or on the next main-queue turn) mean something.
//
// RECORDED 2026-11-15 by the outline-probes lane, macOS 27.2.1 (26B131), Apple Swift 6.4.2 (swift-6.4.2-RELEASE), arm64, screen
// UNLOCKED (lock probe: no CGSSessionScreenIsLocked key, kCGSSessionOnConsoleKey 1, IOConsoleLocked No). The full raw output of
// the compiled form is committed verbatim in docs/probes/swiftui-outline.recorded.txt (the script form printed the same lines up to
// the timing noise named below); stderr carries only AppKit's "reentrant operation in its NSTableView delegate" warning (6 lines).
// The two forms differ only in run-loop turn counts (+-2), the sampled animation series (the values, and 32 or 33 distinct) and
// frame indices in R1f (+-1): timing. This is the READ of that file, one value per fact:
//
// P-L1 / P-L2 GEOMETRY (window 300 x 400, rows of the tree above, expanded; points; every number identical in data and content forms)
//
//                        row    first row  indentation  chevron cell (level 0 / level 1)   label x (depth 0 / 1 / 2)   NSTableView.style
//   .sidebar             32     y 10        12           x 12 / 24, w 13, row height        25 / 37 / 49                sourceList (3)
//   .automatic, .inset   24     y 10        13           x 12 / 25, w 13                    25 / 38 / 51                inset (2)
//   .plain               24     y 0         13           x 2 / 15, w 12                     26 / 39 / 52                plain (4)
//   .sidebar, no children (flat control): row 32, label x 16, no chevron cell (outline cell 0 x 0 x 0).
//   .sidebar intercell spacing 3 x 0 (others 17 x 0); a SwiftUI Text label is 16 tall; rowSizeStyle 2 (medium) under .sidebar.
//   A leaf's label is at the SAME x as its sibling group's label (the leaf reserves the chevron slot: Z at 25 like A and M, A/C at 37
//   like A/B, A/B/D at 49); a leaf has no outline cell. `.automatic` and `.inset` printed identical numbers.
//
// P-L3 CHEVRON (.sidebar; ink read from a 2x snapshot of the outline, alpha above 0.35)
//   collapsed: points right, ink 5 x 8 pt at (17, 23) in the outline for the first row (the 13 x 32 cell is at (12, 10));
//   expanded: points down, ink 8.5 x 5 pt at (14.5, 26). The glyph is NOT a rotated layer: the NSButtonImageView layer's transform is
//   the identity (angle 0) in both states and the NSButton's `state` flips 0 -> 1 (the cell swaps its image; `button.image` is nil;
//   the cell's template image is 13 x 13). Colour: #808080 at alpha 0.94 (collapsed), 0.93 (expanded) in light, #7C7C7C / #7B7B7B in
//   dark: a mid grey, the sampled ink over a transparent snapshot. Data and content forms are identical.
//
// P-L4 SELECTION (.sidebar, one selected row of 32): the highlight spans x 10 to 290 of 300 (left and right inset 10), the full
//   32 pt of the row vertically (rows abut: top and bottom inset 0), corner radius about 8 pt (the 2x corner profile of the first
//   14 pixel columns is 13 9 7 6 5 4 3 2 2 1 1 1 1 0 px, which fits r = 16 px). The row view is `ListTableRowView`,
//   `layer.cornerRadius` 0 with masksToBounds, so the rounding is drawn, not a layer property. COLOUR NOT MEASURED: the snapshot
//   of the selected row is opaque black (the selection blends against the sidebar material, which `cacheDisplay` does not
//   capture) and the process is not the active app, so the drawn colour was not read; the AppKit colours printed beside it
//   (selectedContentBackground #0059D1, unemphasized #464646, accent #007AFF) are the system values, not the drawing.
//
// P-K KEYS (identical in all three forms unless stated; the key goes to the outline view as the first responder)
//   K1 down / up: moves the selection one VISIBLE row and writes the binding once per key, one turn apart (A -> A/B -> A/B/D -> A/B/E
//      -> A/B/D). Children of an expanded group are in the walk.
//   K2a right on a collapsed group: expands it, selection stays on it. K2b right on an EXPANDED group: nothing (selection does not
//      move to the first child). K2c right on a leaf: nothing.
//   K3a left on an expanded group: collapses it, selection stays. K3b left on a collapsed root: nothing. K3c left on a leaf child:
//      selection moves to the parent (one binding write). K3d left on a COLLAPSED child group: selection moves to its parent.
//      K3e left on an EXPANDED child group: collapses it, selection stays.
//   K4a option-right on a collapsed group expands it and ALL descendants at once; in the content form both isExpanded[A] and
//      isExpanded[A/B] are written in the same turn (K4d: a 5-deep chain, four bindings written in ONE turn, including the
//      descendants whose rows had never been built). K4b option-right on an already EXPANDED group: nothing (descendants stay
//      collapsed). K5 option-left collapses the group and every descendant (isExpanded[A] and [A/B] both false in one turn);
//      K5b option-left on A/B collapses A/B and leaves its parent A open.
//   K7 collapsing an ANCESTOR of the selection (selection A/B/D under A): by chevron click or programmatically the binding KEEPS the
//      hidden id (`selection` is still A/B/D, no write happens), the outline has NO selected row; the next key starts from nothing:
//      K7e down selects the FIRST row (A), K7f up selects the LAST row (M). K7c a chevron click on A/B (selection A/B/D below it)
//      likewise keeps A/B/D hidden. K7d select A, left (collapse), down: selection goes to the next visible row (Z).
//
// P-C1 CHEVRON CLICK: clicking the chevron toggles the group and does NOT change the selection (nothing selected stays nil, selection
//   Z stays Z; one isExpanded write in the content form). Option-click on the chevron of a collapsed A expands A and A/B at once
//   (both bindings written in one turn). A plain click on the row body (C1d) selects the row and does not toggle it; a double-click
//   with no primaryAction installed selects and does not toggle.
//
// P-E5 UNCONTROLLED EXPANSION: expand A, expand A/B, collapse A, re-expand A: A/B is STILL expanded (A+ | A/B+ | A/B/D | A/B/E | A/C
//   | Z | M-) in all three uncontrolled forms (List(_:children:), List { OutlineGroup }, List { ForEach { DisclosureGroup } } with no
//   isExpanded): the outline keeps descendant expansion across an ancestor's collapse.
//
// P-I1 IDENTITY: moving leaf X from A to M (the same id, a new parent) DISAPPEARS and re-APPEARS the row and its `@State` is NEW
//   (born# 3 -> 6; the unmoved sibling Y keeps 4 and the unrelated N keeps 5): a row's state does not follow it to another parent,
//   in all three forms (log: "disappear X" then "appear X @State born#6" in one turn).
//
// P-N ANIMATION (A collapsed above Z; the Z row's presentation-layer y sampled every 7 ms; its model y is 106 at once)
//   N1a/N1b chevron click (data / content): the rows below slide from y 42 to 106 over about 245 ms (starting about 15 ms after the
//     click: 15 -> 259 ms and 16 -> 254 ms), 32 distinct values, an ease-in-out shape; the chevron glyph swaps (state 0 -> 1), no rotation
//     (transform identity throughout). N2 a bare `isExpanded = true`: the rows SNAP (one value, 106). N3 `withAnimation(.easeInOut(
//     duration: 0.6)) { isExpanded = true }`: the rows slide, but over the SAME ~245 ms (15 -> 262 ms), not 600 ms: the SwiftUI
//     animation's duration and curve are ignored, AppKit's row animation runs. N3b `.linear(duration: 0.6)` around a chevron click:
//     the same ~245 ms. N4 a bare `NSOutlineView.expandItem`: slides too (16 -> 255 ms), so the AppKit default is animated and
//     a bare SwiftUI binding write is the odd one that snaps. Whether the glyph cross-fades is not sampled.
//
// P-A ACCESSIBILITY (in-process, the legacy NSAccessibility attribute API on the AppKit elements; all three forms identical)
//   Outline role AXOutline, AXRows = one `NSOutlineRow` per visible row. Row: AXRole AXRow, AXSubrole AXOutlineRow, AXRoleDescription
//   "outline row"; AXDisclosureLevel = depth (0, 1, 2; not settable); AXDisclosing 1 or 0 on a group and SETTABLE (setting it true on
//   the collapsed M expanded it and wrote isExpanded[M] = true), 0 and not settable on a leaf; AXDisclosedByRow = the parent row (nil
//   for a root); AXDisclosedRows = the direct children rows (A: 2, A/B: 2, a leaf: 0); AXSelected settable; AXIndex = row index.
//   AXExpanded is NOT an attribute of the row at all (AXDisclosing is). The row's only child is an AXCell
//   (NSTableViewCellMockElement) whose only child is an AXDisclosureTriangle (NSOutlineButtonCell): AXValue 1 expanded / 0 collapsed,
//   one action AXPress; AXPress on A's triangle collapsed A (value now 0, isExpanded[A] = false written). The SwiftUI label inside
//   the cell is NOT in the in-process tree.
//
// P-M contextMenu(forSelectionType:menu:primaryAction:) (identical in all three forms; built through `menu(for:)`)
//   M1 right-click (menu built) on an UNSELECTED row A/C while Z is selected: the menu closure receives {A/C} and the SELECTION DOES
//   NOT CHANGE (Z stays selected). M1b on the selected row: {Z}. M2 on empty space below the rows: the closure receives {} (empty
//   set) and still returns a menu. M3 double-click on a leaf row: the first click selects it (binding write), the primaryAction
//   follows ~60 ms later with {A/C}. M3b double-click on a group row A: selects A, primaryAction {A}, and the group does NOT
//   toggle. M4 Return with Z selected: primaryAction {Z}, one turn after the key; M4b Return on a group: primaryAction {A}, no
//   toggle. UNMEASURED: a real right-click popup, and whether a real rightMouseDown changes the selection.
//
// P-R1 REVEAL (content form, 3 x 3 x 20 leaves, 26 rows after expanding R2 and R2/S1, target R2/S1/L15 = row 20 at y 650 of a
//   400 high view)
//   R1a/R1b/R1c in ONE transaction (insert the two ancestors, set the selection, `proxy.scrollTo(target)` with the default,
//     .center and .top anchors): the selection is set, the rows exist (26), but the list does NOT scroll in 60 frames (about a
//     second): row 20 stays at y 650, scrollY 0. R1f the same expansion and selection with `scrollTo` on the NEXT main-queue turn
//     (0 ms): also does not scroll. With `scrollTo` 20, 60 and 120 ms later (one frame or more) the row lands at y 368 of 400
//     (scrollY 282: the row's bottom edge on the view's bottom edge, the NEAREST alignment of the default anchor). R1d (the
//     control: expand, 6 turns, then select and scrollTo) lands at y 368; R1e (already expanded and off-screen, row 166 of 192)
//     lands at y 368, scrollY 4954. The anchors .center and .top were measured only in the same-transaction arm (no scroll).
//
// UNMEASURED (and why)
//   - The selection highlight colour (see P-L4: the snapshot cannot capture it and the process is not the active app).
//   - Real mouse events through SwiftUI's own gesture path: a synthetic NSEvent sent to the window is swallowed by the cell hosting
//     view, so row clicks, the double-click and the chevron click go to the AppKit views directly (the double-click's primaryAction
//     does fire from `NSOutlineView.mouseDown` twice, so SwiftUI's double-click path is the table's).
//   - A real right-click popup and its selection side effect (modal menu loop).
//   - SwiftUI's own accessibility elements (the label inside a cell, a standalone DisclosureGroup): an AXUIElement client of this
//     process (a child process, from a thread) answered only with application-role elements in this environment, and the in-process
//     tree of the hosting view is empty without a live AX client; see the companion probe's P-A3.
//   - Whether the chevron glyph cross-fades (only its transform and state were sampled).
//   - The `.sidebar` look in dark mode beyond the chevron colour (geometry does not depend on the appearance).
//
// The legacy accessibility calls deprecate-warn on compile; they are the only way to read the AppKit elements in process.
import SwiftUI
import AppKit
import CoreGraphics

// MARK: tree and model

struct Node: Identifiable { let id: String; var children: [Node]? }
func leaf(_ id: String) -> Node { Node(id: id, children: nil) }
func grp(_ id: String, _ kids: [Node]) -> Node { Node(id: id, children: kids) }
func base() -> [Node] {
    [grp("A", [grp("A/B", [leaf("A/B/D"), leaf("A/B/E")]), leaf("A/C")]),
     leaf("Z"),
     grp("M", [leaf("M/N")])]
}
func label(_ id: String) -> String { String(id.split(separator: "/").last ?? "") }
func dfs(_ ns: [Node], _ d: Int = 0) -> [(Node, Int)] { ns.flatMap { [($0, d)] + dfs($0.children ?? [], d + 1) } }


@MainActor var turn = 0
@MainActor var t0 = Date()
@MainActor var logLines: [String] = []
@MainActor var turnBase = 0
@MainActor func log(_ s: String) {
    logLines.append(String(format: "  [run-loop turn +%d] ", turn - turnBase) + s)
}
@MainActor func resetLog() { logLines = []; t0 = Date(); turnBase = turn }
@MainActor func flushLog() { for l in logLines { print(l) }; logLines = [] }

@MainActor final class Model: ObservableObject {
    @Published var tree: [Node] = base()
    @Published var sel: String? = nil { didSet { log("selection = \(sel ?? "nil")") } }
    @Published var expanded: Set<String> = []
    var logExpansion = true
    func bind(_ id: String) -> Binding<Bool> {
        Binding(get: { self.expanded.contains(id) },
                set: { v in
                    if self.logExpansion { log("isExpanded[\(id)] = \(v)") }
                    if v { self.expanded.insert(id) } else { self.expanded.remove(id) } })
    }
}

@MainActor var labelFrames: [String: CGRect] = [:]
@MainActor var born: [String: Int] = [:]
@MainActor var bornCounter = 0
@MainActor var logLifecycle = false

struct Lab: View {
    let id: String
    @State private var mine: Int? = nil
    var body: some View {
        Text(label(id))
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { labelFrames[id] = $0 }
            .onAppear {
                if mine == nil { bornCounter += 1; mine = bornCounter }
                born[id] = mine
                if logLifecycle { log("appear \(id) @State born#\(mine ?? -1)") }
            }
            .onDisappear { if logLifecycle { log("disappear \(id)") } }
    }
}

struct UNode: View {
    let node: Node
    var body: some View {
        if let kids = node.children {
            DisclosureGroup { ForEach(kids) { UNode(node: $0) } } label: { Lab(id: node.id) }
        } else { Lab(id: node.id) }
    }
}

struct NodeView: View {
    let node: Node
    @ObservedObject var m: Model
    var body: some View {
        if let kids = node.children {
            DisclosureGroup(isExpanded: m.bind(node.id)) {
                ForEach(kids) { NodeView(node: $0, m: m) }
            } label: { Lab(id: node.id) }
        } else {
            Lab(id: node.id)
        }
    }
}

enum Form: String { case data, outlineGroup, content, flat, uncontrolled }
enum LS: String { case sidebar, automatic, inset, plain }

struct Menus: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on {
            content.contextMenu(forSelectionType: String.self) { items in
                let _ = log("menu closure items = \(items.sorted())")
                Button("Act") {}
            } primaryAction: { items in
                log("primaryAction items = \(items.sorted())")
            }
        } else { content }
    }
}

struct Root: View {
    @ObservedObject var m: Model
    let form: Form
    let style: LS
    let menus: Bool
    var body: some View {
        ScrollViewReader { proxy in
            styled(listBody)
                .modifier(Menus(on: menus))
                .onAppear { proxies.append(proxy) }
        }
    }
    @ViewBuilder var listBody: some View {
        switch form {
        case .data:
            List(m.tree, children: \.children, selection: $m.sel) { n in Lab(id: n.id) }
        case .outlineGroup:
            List(selection: $m.sel) { OutlineGroup(m.tree, children: \.children) { n in Lab(id: n.id) } }
        case .content:
            List(selection: $m.sel) { ForEach(m.tree) { NodeView(node: $0, m: m) } }
        case .uncontrolled:
            List(selection: $m.sel) { ForEach(m.tree) { UNode(node: $0) } }
        case .flat:
            List(dfs(m.tree).map { $0.0 }, selection: $m.sel) { n in Lab(id: n.id) }
        }
    }
    func styled<V: View>(_ v: V) -> AnyView {
        switch style {
        case .sidebar: AnyView(v.listStyle(.sidebar))
        case .automatic: AnyView(v)
        case .inset: AnyView(v.listStyle(.inset))
        case .plain: AnyView(v.listStyle(.plain))
        }
    }
}
@MainActor var proxies: [ScrollViewProxy] = []

// MARK: rig

final class KeyWin: NSWindow {
    override var canBecomeKey: Bool { true }
    // the process is not the active app, so a plain window is never key and the table view ignores clicks
    override var isKeyWindow: Bool { true }
    override var canBecomeMain: Bool { true }
    override var isMainWindow: Bool { true }
}

func find<T: NSView>(_ type: T.Type, in v: NSView) -> T? {
    if let t = v as? T { return t }
    for c in v.subviews { if let f = find(type, in: c) { return f } }
    return nil
}
func findAll<T: NSView>(_ type: T.Type, in v: NSView) -> [T] {
    (v as? T).map { [$0] } ?? [] + v.subviews.flatMap { findAll(type, in: $0) }
}

@MainActor func spin(_ n: Int = 8, _ dt: Double = 0.02) {
    for _ in 0..<n { RunLoop.main.run(until: Date(timeIntervalSinceNow: dt)) }
}

@MainActor var openWindows: [NSWindow] = []
@MainActor func closeAll() { for w in openWindows { w.orderOut(nil); w.close() }; openWindows = [] }

@MainActor final class Rig {
    let m: Model
    let w: KeyWin
    let h: NSHostingView<Root>
    var o: NSOutlineView
    let form: Form
    init(_ form: Form, style: LS = .sidebar, menus: Bool = false, size: CGSize = CGSize(width: 300, height: 400),
         dark: Bool = false, model: Model? = nil) {
        self.form = form
        m = model ?? Model()
        h = NSHostingView(rootView: Root(m: m, form: form, style: style, menus: menus))
        w = KeyWin(contentRect: CGRect(x: 100, y: 100, width: size.width, height: size.height), styleMask: [.borderless],
                   backing: .buffered, defer: false)
        if dark { w.appearance = NSAppearance(named: .darkAqua) } else { w.appearance = NSAppearance(named: .aqua) }
        w.contentView = h
        w.makeKeyAndOrderFront(nil)
        openWindows.append(w)
        spin(); h.layoutSubtreeIfNeeded(); spin()
        o = find(NSOutlineView.self, in: h) ?? NSOutlineView()
        w.makeFirstResponder(o)
    }
    var hasOutline: Bool { find(NSOutlineView.self, in: h) != nil }
    func refreshOutline() { if let f = find(NSOutlineView.self, in: h) { o = f } }
    func settle() { spin(6); h.layoutSubtreeIfNeeded(); spin(4) }

    // ids by row, from levels and the static tree (ids are tree-wide unique)
    func ids() -> [String] {
        if form == .flat { return dfs(m.tree).map { $0.0.id } }
        let all = dfs(m.tree)
        var out: [String] = []
        var idx = 0
        let n = o.numberOfRows
        for r in 0..<n {
            guard idx < all.count else { out.append("?"); continue }
            out.append(all[idx].0.id)
            let d = all[idx].1
            if r + 1 < n, o.level(forRow: r + 1) > o.level(forRow: r) { idx += 1 }
            else { idx += 1; while idx < all.count, all[idx].1 > d { idx += 1 } }
        }
        return out
    }
    func rowOf(_ id: String) -> Int? { ids().firstIndex(of: id) }
    func isGroup(_ id: String) -> Bool { dfs(m.tree).first { $0.0.id == id }?.0.children != nil }
    func isOpen(row: Int) -> Bool { row + 1 < o.numberOfRows && o.level(forRow: row + 1) > o.level(forRow: row) }
    func snap() -> String {
        let sel = o.selectedRowIndexes
        let idl = ids()
        return idl.enumerated().map { (r, id) in
            (sel.contains(r) ? "*" : "") + id + (isGroup(id) ? (isOpen(row: r) ? "+" : "-") : "")
        }.joined(separator: " | ")
    }
    func itemExpanded(_ id: String) -> Bool? {
        guard let r = rowOf(id) else { return nil }
        return o.isItemExpanded(o.item(atRow: r))
    }
    func expandAll() {
        for _ in 0..<6 {
            var changed = false
            for r in 0..<o.numberOfRows { if let it = o.item(atRow: r), o.isExpandable(it), !o.isItemExpanded(it) { o.expandItem(it); changed = true; break } }
            spin(3)
            if !changed { break }
        }
        settle()
    }
    func expandAllContent() {
        m.logExpansion = false
        for (n, _) in dfs(m.tree) where n.children != nil { m.expanded.insert(n.id) }
        m.logExpansion = true
        settle()
    }
    /// Expands the named groups (outline: through the outline view in row order; content: through the model).
    func open(_ names: [String]) {
        if form == .content { m.logExpansion = false; for n in names { m.expanded.insert(n) }; m.logExpansion = true; settle(); return }
        for n in names { if let r = rowOf(n), let it = o.item(atRow: r) { o.expandItem(it); settle() } }
    }
    func select(_ id: String) { if let r = rowOf(id) { o.selectRowIndexes([r], byExtendingSelection: false); settle() } }

    // events
    func key(_ code: UInt16, _ chars: String, _ mods: NSEvent.ModifierFlags = []) {
        for t in [NSEvent.EventType.keyDown, .keyUp] {
            let e = NSEvent.keyEvent(with: t, location: .zero, modifierFlags: mods.union([.function, .numericPad]),
                                     timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber, context: nil,
                                     characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
            w.sendEvent(e)
        }
        spin(4)
    }
    func right(_ mods: NSEvent.ModifierFlags = []) { key(124, "\u{F703}", mods) }
    func left(_ mods: NSEvent.ModifierFlags = []) { key(123, "\u{F702}", mods) }
    func down() { key(125, "\u{F701}") }
    func up() { key(126, "\u{F700}") }
    func ret() { key(36, "\r") }

    func mouse(_ type: NSEvent.EventType, _ p: CGPoint, _ mods: NSEvent.ModifierFlags, _ count: Int) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: o.convert(p, to: nil), modifierFlags: mods,
                           timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber, context: nil,
                           eventNumber: 0, clickCount: count, pressure: type == .leftMouseUp ? 0 : 1)!
    }
    /// Click at a point in outline coordinates. The up event is queued first so a tracking loop in the target ends.
    func pump(wait: Double = 0.03) {
        while let e = NSApp.nextEvent(matching: .any, until: wait == 0 ? .distantPast : Date(timeIntervalSinceNow: wait), inMode: .default, dequeue: true) { NSApp.sendEvent(e) }
    }
    /// A chevron click that returns as soon as the click has been handled, so an animation can be sampled from its first frame.
    func quickChevronClick(_ id: String) {
        guard let r = rowOf(id) else { return }
        let p = chevronCenter(r)
        NSApp.postEvent(mouse(.leftMouseDown, p, [], 1), atStart: false)
        NSApp.postEvent(mouse(.leftMouseUp, p, [], 1), atStart: false)
        pump(wait: 0.002)
    }
    /// A click goes through the window when the hit view is a button (the disclosure triangle). Anywhere else the hit view is
    /// the SwiftUI cell hosting view, which swallows a synthetic event, so the event goes to the outline view's `mouseDown`
    /// with the matching mouse-up already queued (the table view runs a tracking loop that consumes it).
    func click(_ p: CGPoint, _ mods: NSEvent.ModifierFlags = [], count: Int = 1) {
        let hit = w.contentView?.hitTest(o.convert(p, to: nil))
        for c in 1...count {
            if hit is NSButton {
                NSApp.postEvent(mouse(.leftMouseDown, p, mods, c), atStart: false)
                NSApp.postEvent(mouse(.leftMouseUp, p, mods, c), atStart: false)
                pump()
            } else {
                NSApp.postEvent(mouse(.leftMouseUp, p, mods, c), atStart: false)
                o.mouseDown(with: mouse(.leftMouseDown, p, mods, c)); spin(2)
            }
        }
        spin(4)
    }
    func rowCenter(_ r: Int, x: CGFloat = 150) -> CGPoint { let rc = o.rect(ofRow: r); return CGPoint(x: x, y: rc.midY) }
    func chevronCenter(_ r: Int) -> CGPoint { let c = o.frameOfOutlineCell(atRow: r); return CGPoint(x: c.midX, y: c.midY) }
    func chevronClick(_ id: String, _ mods: NSEvent.ModifierFlags = []) { if let r = rowOf(id) { click(chevronCenter(r), mods) } }
    func rowClick(_ id: String, _ mods: NSEvent.ModifierFlags = [], count: Int = 1) { if let r = rowOf(id) { click(rowCenter(r), mods, count: count) } }
}

func f(_ x: CGFloat) -> String { String(format: "%g", Double((x * 100).rounded() / 100)) }
func fr(_ r: CGRect) -> String { "(\(f(r.minX)),\(f(r.minY)) \(f(r.width))x\(f(r.height)))" }

// MARK: pixels

@MainActor func snapshot(_ v: NSView) -> NSBitmapImageRep {
    // 2x backing, so sub-point edges are visible
    let r = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(v.bounds.width * 2), pixelsHigh: Int(v.bounds.height * 2),
                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    r.size = v.bounds.size
    v.cacheDisplay(in: v.bounds, to: r)
    return r
}
func rgba(_ c: NSColor?) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
    guard let c = c?.usingColorSpace(.sRGB) else { return (-1, -1, -1, -1) }
    return (c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent)
}
func hex(_ c: NSColor?) -> String {
    let (r, g, b, a) = rgba(c)
    return String(format: "#%02X%02X%02X a=%.2f", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()), Double(a))
}

// MARK: arms

@MainActor func geometry(_ rig: Rig, _ title: String) {
    let o = rig.o
    print("\(title): rows=\(o.numberOfRows) indentationPerLevel=\(f(o.indentationPerLevel)) intercell=\(fr(CGRect(origin: .zero, size: o.intercellSpacing))) rowSizeStyle=\(o.rowSizeStyle.rawValue) style=\(o.style.rawValue) autoresizesOutlineColumn=\(o.autoresizesOutlineColumn) indentationMarkerFollowsCell=\(o.indentationMarkerFollowsCell)")
    let idl = rig.ids()
    for r in 0..<o.numberOfRows {
        let rc = o.rect(ofRow: r)
        let oc = o.frameOfOutlineCell(atRow: r)
        let cell = o.view(atColumn: 0, row: r, makeIfNecessary: false)
        let cellX = cell.map { o.convert($0.frame, from: $0.superview).minX }
        let lab = labelFrames[idl[r]]
        print("  row \(r) \(idl[r])\(rig.form == .flat ? "" : (rig.isGroup(idl[r]) ? " [group]" : " [leaf]")) level=\(o.level(forRow: r)) rect=\(fr(rc)) outlineCell=\(fr(oc)) cellMinX=\(cellX.map(f) ?? "-") labelX(swiftui .global)=\(lab.map { f($0.minX) } ?? "-") labelH=\(lab.map { f($0.height) } ?? "-")")
    }
}

@MainActor func armL1() {
    print("--- P-L1 / P-L2: row height, indentation, chevron cell, label x (window 300x400, expanded A, A/B, M)")
    for st in [LS.sidebar, .automatic, .inset, .plain] {
        for form in [Form.data, .content] {
            labelFrames = [:]
            let rig = Rig(form, style: st)
            if form == .data { rig.expandAll() } else { rig.expandAllContent() }
            rig.settle()
            geometry(rig, "\(st.rawValue)/\(form.rawValue)")
            closeAll()
        }
    }
    // plain-list control: one level, no outline column use
    labelFrames = [:]
    let rig = Rig(.flat, style: .sidebar)
    geometry(rig, "sidebar/flat (control: List of rows without children)")
    print("  flat control NSOutlineView? \(rig.hasOutline)  NSTableView? \(find(NSTableView.self, in: rig.h) != nil)")
    closeAll()
}

@MainActor func darkestPixel(_ rep: NSBitmapImageRep, _ r: CGRect, scale: CGFloat) -> (NSColor?, CGRect) {
    var best: NSColor? = nil; var bestA: CGFloat = 0
    var minX = Int.max, maxX = -1, minY = Int.max, maxY = -1
    for y in Int(r.minY * scale)..<Int(r.maxY * scale) {
        for x in Int(r.minX * scale)..<Int(r.maxX * scale) {
            guard x >= 0, y >= 0, x < rep.pixelsWide, y < rep.pixelsHigh, let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
            if c.alphaComponent > 0.35 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
            if c.alphaComponent > bestA { bestA = c.alphaComponent; best = c }
        }
    }
    if maxX < 0 { return (nil, .zero) }
    return (best, CGRect(x: CGFloat(minX) / scale, y: CGFloat(minY) / scale, width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxY - minY + 1) / scale))
}

@MainActor func armL3() {
    print("--- P-L3: chevron glyph, colour, angle (sidebar, light then dark)")
    for dark in [false, true] {
        for form in [Form.data, .content] {
            let rig = Rig(form, dark: dark)
            let o = rig.o
            let r = rig.rowOf("A")!
            let collapsedBox = o.frameOfOutlineCell(atRow: r)
            let row = o.rowView(atRow: r, makeIfNecessary: false)!
            let btn = findAll(NSButton.self, in: row).first
            func describe(_ tag: String) {
                let rep = snapshot(o)
                let scale = CGFloat(rep.pixelsWide) / o.bounds.width
                let box = o.frameOfOutlineCell(atRow: r)
                let (c, bb) = darkestPixel(rep, box, scale: scale)
                let iv = btn.flatMap { find(NSImageView.self, in: $0) }
                let layer = iv?.layer
                let t = layer?.transform ?? CATransform3DIdentity
                let ang = atan2(t.m12, t.m11) * 180 / .pi
                if !dark && form == .data {
                    let b = box.insetBy(dx: 0, dy: 9)
                    for y in Int(b.minY * scale)..<Int(b.maxY * scale) {
                        var line = ""
                        for x in Int(b.minX * scale)..<Int(b.maxX * scale) {
                            let a = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)?.alphaComponent ?? 0
                            line += a > 0.6 ? "#" : (a > 0.15 ? "+" : ".")
                        }
                        print("      \(tag) |\(line)|")
                    }
                }
                print("  \(dark ? "dark" : "light")/\(form.rawValue) \(tag): cell=\(fr(box)) glyph bbox=\(fr(bb)) (w x h) colour=\(hex(c)) imageView layer angle=\(f(ang))° button image=\(String(describing: btn?.image?.name())) symbol desc=\(btn?.image?.accessibilityDescription ?? "-") button state=\(btn?.state.rawValue ?? -1) isTemplate=\(btn?.image?.isTemplate ?? false) imageSize=\(btn?.image.map { "\($0.size)" } ?? "-")")
            }
            _ = collapsedBox
            describe("collapsed")
            if form == .data { rig.o.expandItem(rig.o.item(atRow: r)); rig.settle() } else { rig.m.expanded.insert("A"); rig.settle() }
            describe("expanded")
            closeAll()
        }
    }
}

@MainActor func armL4() {
    print("--- P-L4: selection highlight (sidebar, key window), scanning an outline snapshot at 2x")
    for dark in [false, true] {
        let rig = Rig(.data, dark: dark)
        rig.expandAll()
        let o = rig.o
        rig.select("A/C")
        logLines = []
        let r = rig.rowOf("A/C")!
        let rc = o.rect(ofRow: r)
        let rep = snapshot(o)
        let scale = CGFloat(rep.pixelsWide) / o.bounds.width
        func alpha(_ x: Int, _ y: Int) -> CGFloat { rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)?.alphaComponent ?? -1 }
        let midY = Int(rc.midY * scale)
        var first = -1, last = -1
        for x in 0..<rep.pixelsWide { if alpha(x, midY) > 0.05 { if first < 0 { first = x }; last = x } }
        let mx = (first + last) / 2
        var top = -1, bottom = -1
        for y in Int(rc.minY * scale) - 6..<Int(rc.maxY * scale) + 6 { if alpha(mx, y) > 0.05 { if top < 0 { top = y }; bottom = y } }
        // corner: for the first 14 pixel columns, offset of the first highlighted pixel from `top`
        var corner: [Int] = []
        for k in 0..<14 { var fy = -1; for y in top..<bottom { if alpha(first + k, y) > 0.5 * alpha(mx, (top + bottom) / 2) { fy = y; break } }; corner.append(fy - top) }
        let selCol = rep.colorAt(x: mx, y: (top + bottom) / 2)
        print("  \(dark ? "dark" : "light"): row rect=\(fr(rc)) highlight x \(f(CGFloat(first) / scale))...\(f(CGFloat(last + 1) / scale)) (left inset \(f(CGFloat(first) / scale)), right inset \(f(o.bounds.width - CGFloat(last + 1) / scale))), y \(f(CGFloat(top) / scale))...\(f(CGFloat(bottom + 1) / scale)) (top inset \(f(CGFloat(top) / scale - rc.minY)), bottom inset \(f(rc.maxY - CGFloat(bottom + 1) / scale)))")
        print("       corner profile (2x px offset of first lit pixel for the first 14 columns): \(corner) snapshot pixel=\(hex(selCol)) (NOT the drawn colour: the selection blends against the sidebar material, which a snapshot does not capture) windowIsKey=\(rig.w.isKeyWindow) selectionHighlightStyle=\(o.selectionHighlightStyle.rawValue)")
        let row = o.rowView(atRow: r, makeIfNecessary: false)!
        print("       rowView=\(type(of: row)) isEmphasized=\(row.isEmphasized) isSelected=\(row.isSelected) interiorBackgroundStyle=\(row.interiorBackgroundStyle.rawValue) layer.cornerRadius=\(f(row.layer?.cornerRadius ?? -1)) layer.masksToBounds=\(row.layer?.masksToBounds ?? false)")
        print("       AppKit colours for the same states (not read from the drawing): selectedContentBackground=\(hex(NSColor.selectedContentBackgroundColor)) unemphasizedSelectedContentBackground=\(hex(NSColor.unemphasizedSelectedContentBackgroundColor)) controlAccent=\(hex(NSColor.controlAccentColor))")
        closeAll()
    }
}


let formNames: [(Form, String)] = [(.data, "List(_:children:)"), (.outlineGroup, "List { OutlineGroup }"), (.content, "List { ForEach { DisclosureGroup(isExpanded:) } }")]

@MainActor func scenario(_ title: String, tree: [Node]? = nil, open: [String] = [], select: String? = nil, _ act: (Rig) -> Void) {
    for (form, fname) in formNames {
        let model = Model()
        if let t = tree { model.tree = t }
        let rig = Rig(form, model: model)
        rig.open(open)
        if let s = select { rig.select(s) }
        rig.settle()
        let before = rig.snap()
        print("  \(title) [\(fname)]\n      before: \(before)")
        resetLog()
        act(rig)
        rig.settle()
        print("      after:  \(rig.snap())")
        if form == .content { print("      model.expanded = \(rig.m.expanded.sorted())  model.sel = \(rig.m.sel ?? "nil")") }
        else { print("      model.sel = \(rig.m.sel ?? "nil")") }
        flushLog()
        closeAll()
    }
}

@MainActor func armK() {
    print("--- P-K1..K7: keys (events sent to the window with NSEvent; first responder = the outline view)")
    scenario("K1 down,down,down,up from A (A, A/B open)", open: ["A", "A/B"], select: "A") { r in
        r.down(); print("      after down: \(r.snap())"); r.down(); print("      after down: \(r.snap())"); r.down(); print("      after down: \(r.snap())"); r.up()
    }
    scenario("K2a right on collapsed A", select: "A") { $0.right() }
    scenario("K2b right on expanded A", open: ["A"], select: "A") { $0.right() }
    scenario("K2c right on leaf Z", select: "Z") { $0.right() }
    scenario("K3a left on expanded A", open: ["A"], select: "A") { $0.left() }
    scenario("K3b left on collapsed A (a root)", select: "A") { $0.left() }
    scenario("K3c left on leaf child A/C", open: ["A"], select: "A/C") { $0.left() }
    scenario("K3d left on collapsed child group A/B", open: ["A"], select: "A/B") { $0.left() }
    scenario("K3e left on expanded child group A/B", open: ["A", "A/B"], select: "A/B") { $0.left() }
    scenario("K4a option-right on collapsed A (descendants collapsed)", select: "A") { r in r.right(.option); print("      after 1 settle: \(r.snap())"); spin(30); }
    scenario("K4b option-right on expanded A (A/B collapsed)", open: ["A"], select: "A") { r in r.right(.option); spin(30) }
    scenario("K4c option-right on collapsed A, no settle between turns (log shows turn spread)", select: "A") { r in r.right(.option); spin(60) }
    let deep = [grp("A", [grp("A/B", [grp("A/B/F", [grp("A/B/F/G", [leaf("A/B/F/G/H")])])]), leaf("A/C")]), leaf("Z")]
    scenario("K4d option-right on collapsed A over a 5-deep chain", tree: deep, select: "A") { r in
        r.right(.option); print("      after the key + 4 turns: \(r.snap())"); spin(40)
    }
    scenario("K5 option-left on A (A, A/B open)", open: ["A", "A/B"], select: "A") { r in r.left(.option); spin(30) }
    scenario("K5b option-left on A/B (A, A/B open): descendants only", open: ["A", "A/B"], select: "A/B") { r in r.left(.option); spin(30) }
}

@MainActor func armK7() {
    print("--- P-K7: collapsing an ancestor of the selection (A, A/B open, selection A/B/D)")
    scenario("K7a chevron click on A", open: ["A", "A/B"], select: "A/B/D") { r in r.chevronClick("A") }
    scenario("K7b programmatic collapse of A", open: ["A", "A/B"], select: "A/B/D") { r in
        if r.form == .content { r.m.expanded.remove("A") } else { r.o.collapseItem(r.o.item(atRow: r.rowOf("A")!)) }
    }
    scenario("K7c chevron click on A/B (selection A/B/D, one level down)", open: ["A", "A/B"], select: "A/B/D") { r in r.chevronClick("A/B") }
    scenario("K7e the selection is hidden by a chevron click on A, then down arrow", open: ["A", "A/B"], select: "A/B/D") { r in r.chevronClick("A"); print("      after the chevron click: \(r.snap()) model.sel = \(r.m.sel ?? "nil")"); r.down() }
    scenario("K7f the selection is hidden by a chevron click on A, then up arrow", open: ["A", "A/B"], select: "A/B/D") { r in r.chevronClick("A"); r.up() }
    scenario("K7d keyboard: select A, collapse with left, then down (is a collapsed A's selection kept?)", open: ["A", "A/B"], select: "A") { r in r.left(); r.down() }
}

@MainActor func armC1() {
    print("--- P-C1: does a chevron click select the row? option-click on a chevron?")
    scenario("C1a chevron click on A, nothing selected", select: nil) { $0.chevronClick("A") }
    scenario("C1b chevron click on A, selection on Z", select: "Z") { $0.chevronClick("A") }
    scenario("C1c option-click on the chevron of A (descendants collapsed)", select: "Z") { r in r.chevronClick("A", .option); spin(30) }
    scenario("C1d plain click on the row of A (not the chevron), selection Z", select: "Z") { $0.rowClick("A") }
    scenario("C1e double-click on the row of A, no primaryAction installed", select: "Z") { $0.rowClick("A", count: 2) }
}

@MainActor func armE5() {
    print("--- P-E5: uncontrolled expansion retention (chevron clicks): expand A, expand A/B, collapse A, re-expand A")
    for (form, name) in [(Form.data, "List(_:children:)"), (.outlineGroup, "List { OutlineGroup }"), (.uncontrolled, "List { ForEach { DisclosureGroup } } (no isExpanded)")] {
        let rig = Rig(form)
        print("  E5 [\(name)]")
        print("      start:               \(rig.snap())")
        rig.chevronClick("A"); rig.settle(); print("      expand A:            \(rig.snap())")
        rig.chevronClick("A/B"); rig.settle(); print("      expand A/B:          \(rig.snap())")
        rig.chevronClick("A"); rig.settle(); print("      collapse A:          \(rig.snap())")
        rig.chevronClick("A"); rig.settle(); print("      re-expand A:         \(rig.snap())")
        closeAll()
    }
}

@MainActor func armI1() {
    print("--- P-I1: move a node between parents; does a row's @State reset? (born#n = the n-th @State created; X moves A -> M)")
    logLifecycle = true
    for (form, name) in formNames {
        let model = Model()
        model.tree = [grp("A", [leaf("X"), leaf("Y")]), grp("M", [leaf("N")])]
        bornCounter = 0; born = [:]
        let rig = Rig(form, model: model)
        rig.open(["A", "M"])
        rig.settle()
        let before = born
        print("  I1 [\(name)]\n      before: \(rig.snap())  born#: X=\(before["X"] ?? -1) Y=\(before["Y"] ?? -1) N=\(before["N"] ?? -1)")
        resetLog()
        if form == .content || form == .data || form == .outlineGroup {
            model.tree = [grp("A", [leaf("Y")]), grp("M", [leaf("N"), leaf("X")])]
        }
        rig.settle(); spin(20)
        print("      after:  \(rig.snap())  born# (last appear): X=\(born["X"] ?? -1) Y=\(born["Y"] ?? -1) N=\(born["N"] ?? -1)  (counter now \(bornCounter))")
        flushLog()
        closeAll()
    }
    logLifecycle = false
}

func uniq(_ v: [CGFloat]) -> [CGFloat] { var out: [CGFloat] = []; for x in v where out.last != x { out.append(x) }; return out }

@MainActor func sampleExpand(_ title: String, form: Form, _ act: (Rig) -> Void) {
    let rig = Rig(form)
    rig.settle()
    let zRowBefore = rig.rowOf("Z")!
    let o = rig.o
    var tms: [Int] = [], model: [CGFloat] = [], pres: [CGFloat] = [], rows: [Int] = [], ang: [CGFloat] = [], gstate: [Int] = []
    let btn = o.rowView(atRow: rig.rowOf("A")!, makeIfNecessary: false).flatMap { findAll(NSButton.self, in: $0).first }
    let ivw = btn.flatMap { find(NSImageView.self, in: $0) }
    resetLog()
    let start = Date()
    // a timer samples every 7 ms through the click itself (its run loop turns included), so no early frame is missed
    let timer = Timer(timeInterval: 0.007, repeats: true) { _ in
        MainActor.assumeIsolated {
            let n = o.numberOfRows
            let zr = n - 2
            tms.append(Int(Date().timeIntervalSince(start) * 1000))
            model.append(o.rect(ofRow: zr).minY)
            pres.append(o.rowView(atRow: zr, makeIfNecessary: false)?.layer?.presentation()?.frame.minY ?? -1)
            rows.append(n)
            let t = ivw?.layer?.presentation()?.transform ?? CATransform3DIdentity
            ang.append((atan2(t.m12, t.m11) * 180 / .pi * 10).rounded() / 10)
            gstate.append(btn?.state.rawValue ?? -9)
        }
    }
    RunLoop.main.add(timer, forMode: .common)
    act(rig)
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.0))
    timer.invalidate()
    func fmt(_ a: [CGFloat], _ cap: Int = 14) -> String {
        let u = uniq(a.map { ($0 * 2).rounded() / 2 }); return (u.count > cap ? Array(u.prefix(cap)) : u).map { f($0) }.joined(separator: " ") + (u.count > cap ? " ... (\(u.count) distinct)" : " (\(u.count) distinct)")
    }
    let firstChange = model.firstIndex { $0 != model[0] }.map { tms[$0] }
    let lastChange = model.lastIndex { $0 != model.last! }.map { tms[$0 + 1] }
    print("  \(title): Z row \(zRowBefore) -> \(rows.last! - 2)  rows \(fmt(rows.map { CGFloat($0) }))")
    print("      Z row y in the outline (rect(ofRow:)): \(fmt(model))  first change at \(firstChange.map { "\($0) ms" } ?? "none"), settled at \(lastChange.map { "\($0) ms" } ?? "none")")
    let pFirst = pres.firstIndex { $0 != pres[0] }.map { tms[$0] }
    let pLast = pres.lastIndex { $0 != pres.last! }.map { tms[min($0 + 1, tms.count - 1)] }
    print("      Z row view presentation-layer y:       \(fmt(pres))  moving from \(pFirst.map { "\($0)" } ?? "-") ms to \(pLast.map { "\($0)" } ?? "-") ms")
    print("      chevron image-view presentation transform angle: \(fmt(ang))  button.state: \(uniq(gstate.map { CGFloat($0) }).map { f($0) }.joined(separator: " "))")
    flushLog()
    closeAll()
}

@MainActor func armN() {
    print("--- P-N1..N3: animation (A collapsed above Z; samples every ~7 ms for ~1 s)")
    sampleExpand("N1a chevron click, List(_:children:)", form: .data) { $0.chevronClick("A") }
    sampleExpand("N1b chevron click, content form", form: .content) { $0.chevronClick("A") }
    sampleExpand("N2  bare isExpanded = true (content form)", form: .content) { $0.m.expanded.insert("A") }
    sampleExpand("N3  withAnimation(.easeInOut(duration: 0.6)) { isExpanded = true } (content form)", form: .content) { r in
        withAnimation(.easeInOut(duration: 0.6)) { _ = r.m.expanded.insert("A") }
    }
    sampleExpand("N3b withAnimation(.linear(duration: 0.6)) around a chevron click (content form)", form: .content) { r in
        withAnimation(.linear(duration: 0.6)) { r.chevronClick("A") }
    }
    sampleExpand("N4  bare NSOutlineView.expandItem (data form, AppKit control)", form: .data) { r in r.o.expandItem(r.o.item(atRow: r.rowOf("A")!)) }
}

// MARK: accessibility

func axs(_ v: Any?, depth: Int = 0) -> String {
    guard let v = v else { return "nil" }
    if let a = (v as? NSArray).map({ $0.map { $0 } }) { return "[\(a.count)\(a.isEmpty ? "" : ": " + a.prefix(3).map { axs($0, depth: depth + 1) }.joined(separator: ", "))\(a.count > 3 ? ", ..." : "")]" }
    if let o = v as? NSObject, o.responds(to: Selector(("accessibilityAttributeValue:"))) {
        return "<\(type(of: o)) \(axv(o, "AXRole")) \(axv(o, "AXLabel"))>"
    }
    return "\(v)"
}
func axv(_ o: NSObject, _ a: String) -> String {
    guard let x = o.accessibilityAttributeValue(NSAccessibility.Attribute(rawValue: a)) else { return "-" }
    return "\(x)"
}
func axKids(_ o: NSObject) -> [NSObject] {
    ((o.accessibilityAttributeValue(.children) as? NSArray) ?? []).compactMap { $0 as? NSObject }
}

@MainActor func dumpAX(_ obj: NSObject, _ title: String, attrs: [String]) {
    let names = (obj.accessibilityAttributeNames() ?? []).map { $0.rawValue }
    print("    \(title) (\(type(of: obj))): attributes = \(names.joined(separator: " "))")
    for a in attrs where names.contains(a) {
        let name = NSAccessibility.Attribute(rawValue: a)
        print("        \(a) = \(axs(obj.accessibilityAttributeValue(name))) settable=\(obj.accessibilityIsAttributeSettable(name))")
    }
    let acts = obj.accessibilityActionNames().map { $0.rawValue }
    print("        actions = \(acts.joined(separator: " "))")
}

@MainActor func armA() {
    print("--- P-A1/A2: AX of outline rows, the disclosure triangle, and settable AXExpanded (macOS legacy attribute API in-process)")
    let attrs = ["AXRole", "AXSubrole", "AXRoleDescription", "AXDisclosureLevel", "AXDisclosing", "AXDisclosedByRow", "AXDisclosedRows", "AXExpanded", "AXSelected", "AXIndex", "AXLabel", "AXValue", "AXEnabled", "AXChildren", "AXHelp"]
    for (form, name) in formNames {
        let rig = Rig(form)
        rig.open(["A", "A/B"])
        rig.settle()
        print("  A [\(name)]  snap: \(rig.snap())")
        let o = rig.o
        dumpAX(o, "outline", attrs: ["AXRole", "AXSubrole", "AXRows", "AXColumns", "AXSelectedRows", "AXVisibleRows"])
        let rows = ((o.accessibilityAttributeValue(NSAccessibility.Attribute(rawValue: "AXRows")) as? NSArray) ?? []).compactMap { $0 as? NSObject }
        print("    AXRows count = \(rows.count)")
        for id in ["A", "A/B", "A/C", "A/B/D"] {
            guard let r = rig.rowOf(id), r < rows.count else { continue }
            dumpAX(rows[r], "row \(id)", attrs: attrs)
            let kids = axKids(rows[r])
            if id == "A", let cell = kids.first {
                for (i, g) in axKids(cell).enumerated() {
                    print("        cell child[\(i)] \(type(of: g)) role=\(axv(g, "AXRole")) label=\(axv(g, "AXLabel")) value=\(axv(g, "AXValue")) title=\(axv(g, "AXTitle"))")
                }
                print("        cell attributes = \((cell.accessibilityAttributeNames() ?? []).map { $0.rawValue }.joined(separator: " "))")
            }
            for (i, k) in kids.enumerated() {
                print("        child[\(i)] \(type(of: k)) role=\(axv(k, "AXRole")) subrole=\(axv(k, "AXSubrole")) label=\(axv(k, "AXLabel")) value=\(axv(k, "AXValue")) actions=\(k.accessibilityActionNames().map { $0.rawValue })")
            }
        }
        // settable AXExpanded: write through the row, observe
        if let r = rig.rowOf("M"), r < rows.count {
            let row = rows[r]
            resetLog()
            let names = (row.accessibilityAttributeNames() ?? []).map { $0.rawValue }
            print("    AXExpanded among the row's attributes: \(names.contains("AXExpanded"))")
            let ok = row.accessibilityIsAttributeSettable(NSAccessibility.Attribute(rawValue: "AXDisclosing"))
            row.accessibilitySetValue(true as NSNumber, forAttribute: NSAccessibility.Attribute(rawValue: "AXDisclosing"))
            rig.settle()
            print("    set AXDisclosing=true on row M (settable=\(ok)): \(rig.snap())")
            flushLog()
        }
        // press on the disclosure triangle (a child of the row's cell) of A
        if let r = rig.rowOf("A"), r < rows.count, let cell = axKids(rows[r]).first,
           let tri = axKids(cell).first(where: { axv($0, "AXRole") == "AXDisclosureTriangle" }) {
            print("    triangle: \(type(of: tri)) subrole=\(axv(tri, "AXSubrole")) value=\(axv(tri, "AXValue")) title=\(axv(tri, "AXTitle")) description=\(axv(tri, "AXDescription")) actions=\(tri.accessibilityActionNames().map { $0.rawValue }) attributes=\((tri.accessibilityAttributeNames() ?? []).map { $0.rawValue }.joined(separator: " "))")
            resetLog()
            tri.accessibilityPerformAction(.press)
            rig.settle()
            print("    press on A's AXDisclosureTriangle: \(rig.snap())  (triangle value now \(axv(tri, "AXValue")))")
            flushLog()
        } else { print("    no AXDisclosureTriangle under row A's cell") }
        closeAll()
    }
}

// MARK: context menu

@MainActor func armM() {
    print("--- P-M1..M4: contextMenu(forSelectionType:menu:primaryAction:) (menus built with NSOutlineView.menu(for:); right-click popups are not driven)")
    for (form, name) in formNames {
        let rig = Rig(form, menus: true)
        rig.open(["A"])
        rig.select("Z"); rig.settle()
        let o = rig.o
        print("  M [\(name)]  start: \(rig.snap())")
        func rightClick(_ title: String, _ p: CGPoint) {
            resetLog()
            let e = NSEvent.mouseEvent(with: .rightMouseDown, location: o.convert(p, to: nil), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: rig.w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            let menu = o.menu(for: e)
            spin(6)
            print("    \(title): menu = \(menu.map { "\($0.items.map { $0.title })" } ?? "nil"); snap: \(rig.snap()); model.sel = \(rig.m.sel ?? "nil")")
            flushLog()
        }
        rightClick("M1  right-click on unselected row A/C", rig.rowCenter(rig.rowOf("A/C")!))
        rightClick("M1b right-click on the selected row", rig.rowCenter(rig.rowOf(rig.m.sel ?? "Z") ?? 0))
        rightClick("M2  right-click on empty space below the rows", CGPoint(x: 150, y: 380))
        rig.select("Z"); resetLog()
        rig.rowClick("A/C", count: 2)
        print("    M3  double-click on leaf row A/C: snap \(rig.snap()); model.sel = \(rig.m.sel ?? "nil")"); flushLog()
        rig.select("Z"); resetLog()
        rig.rowClick("A", count: 2)
        print("    M3b double-click on group row A: snap \(rig.snap()); model.sel = \(rig.m.sel ?? "nil")"); flushLog()
        rig.select("Z"); resetLog()
        rig.ret()
        print("    M4  Return with Z selected: model.sel = \(rig.m.sel ?? "nil")"); flushLog()
        rig.select("A"); resetLog()
        rig.ret()
        print("    M4b Return with group A selected: snap \(rig.snap())"); flushLog()
        closeAll()
    }
}

// MARK: reveal

@MainActor func bigTree() -> [Node] {
    (0..<3).map { i in
        grp("R\(i)", (0..<3).map { j in grp("R\(i)/S\(j)", (0..<20).map { k in leaf("R\(i)/S\(j)/L\(k)") }) })
    }
}

@MainActor func armR1() {
    print("--- P-R1: in one transaction: ancestors isExpanded = true, selection = id, ScrollViewReader.scrollTo(id) (content form, 3 x 3 x 20 leaves, window 300x400)")
    let target = "R2/S1/L15"
    func run(_ title: String, anchor: UnitPoint?, sameTransaction: Bool, preexpand: Bool = false, deferScroll: Bool = false, delayMs: Int = 0) {
        proxies = []
        let model = Model(); model.tree = bigTree()
        let rig = Rig(.content, model: model)
        guard let proxy = proxies.last else { print("  \(title): no ScrollViewReader proxy"); closeAll(); return }
        if preexpand { rig.expandAllContent(); spin(10) }
        let clip = find(NSScrollView.self, in: rig.h)!.contentView
        resetLog()
        let t = Date()
        func reveal() {
            if !preexpand { model.expanded.formUnion(["R2", "R2/S1"]) }
            model.sel = target
            if let a = anchor { proxy.scrollTo(target, anchor: a) } else { proxy.scrollTo(target) }
        }
        if deferScroll {
            model.expanded.formUnion(["R2", "R2/S1"]); model.sel = target
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delayMs)) { proxy.scrollTo(target) }
        } else if sameTransaction { reveal() } else {
            model.expanded.formUnion(["R2", "R2/S1"]); spin(6); model.sel = target
            if let a = anchor { proxy.scrollTo(target, anchor: a) } else { proxy.scrollTo(target) }
        }
        print("  \(title)")
        var last = ""
        for k in 0..<60 {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.016))
            let o = rig.o
            let r = rig.rowOf(target)
            let line: String
            if let r = r {
                let rc = o.rect(ofRow: r)
                let y = rc.minY - clip.bounds.origin.y
                line = "row \(r) at y=\(f(y)) of \(f(clip.bounds.height)) (\(y >= 0 && y + rc.height <= clip.bounds.height ? "in view" : "out of view")) scrollY=\(f(clip.bounds.origin.y)) rows=\(o.numberOfRows)"
            } else { line = "row absent (rows=\(o.numberOfRows), scrollY=\(f(clip.bounds.origin.y)))" }
            if line != last { print("      +\(Int(Date().timeIntervalSince(t) * 1000)) ms (frame \(k)): \(line)"); last = line }
        }
        print("      model.sel = \(model.sel ?? "nil")")
        flushLog()
        closeAll()
    }
    run("R1a same transaction, scrollTo(id) default anchor", anchor: nil, sameTransaction: true)
    run("R1b same transaction, anchor .center", anchor: .center, sameTransaction: true)
    run("R1c same transaction, anchor .top", anchor: .top, sameTransaction: true)
    run("R1d control: expand, 6 turns, then selection + scrollTo", anchor: nil, sameTransaction: false)
    for d in [0, 20, 60, 120] {
        run("R1f expansion + selection in one transaction, scrollTo \(d) ms later (main queue)", anchor: nil, sameTransaction: true, deferScroll: true, delayMs: d)
    }
    run("R1e control: already expanded and offscreen, selection + scrollTo", anchor: nil, sameTransaction: true, preexpand: true)
}

struct Probe {
    @MainActor static func main() {
        setvbuf(stdout, nil, _IOLBF, 0)
        // no App Nap: with offscreen windows a background run is throttled to a crawl otherwise
        let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical], reason: "probe")
        _ = activity
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let obs = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeTimers.rawValue, true, 0) { _, _ in
            MainActor.assumeIsolated { turn += 1 }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), obs, .commonModes)
        app.activate()
        let want = Set(CommandLine.arguments.dropFirst())
        func on(_ k: String) -> Bool { want.isEmpty || want.contains(k) }
        let arms: [(String, @MainActor () -> Void)] = [("L1", armL1), ("L3", armL3), ("L4", armL4), ("K", armK), ("K7", armK7), ("C1", armC1), ("E5", armE5), ("I1", armI1), ("N", armN), ("A", armA), ("M", armM), ("R1", armR1)]
        for (k, a) in arms where on(k) { a(); flushLog() }
        exit(0)
    }
}

MainActor.assumeIsolated { Probe.main() }
