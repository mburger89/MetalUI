// SwiftUI probe: `Table`, measured through the NSTableView SwiftUI builds on macOS (design
// docs/superpowers/specs/2026-11-18-table-design.md, section 9; plan task B0).
//
// Evidence for rulings TBL-F, TBL-G, TBL-O, TBL-Q, TBL-R, TBL-S and TBL-W in docs/superpowers/2026-11-18-table-decisions.md and for the
// constants in Sources/MetalUI/TableMetrics.swift.
//
// HOW TO RUN (ruling SA-O's two forms; an arm name restricts the run, e.g. `... G1 W2`; no argument runs everything; run it in the
// foreground, a backgrounded run is throttled to a crawl):
//
//   /usr/bin/swift docs/probes/swiftui-table.swift
//   xcrun swiftc docs/probes/swiftui-table.swift -o /tmp/table-probe && /tmp/table-probe
//
// THE INSTRUMENT. A `Table` hosted in an ordered-in 800 x 600 borderless window is a `SwiftUIOutlineTableView` (an NSTableView
// subclass). Geometry is read from it directly (`rect(ofRow:)`, `headerView`, `tableColumns`, `intercellSpacing`, the column
// `width`/`minWidth`/`maxWidth`/`resizingMask`); a cell's label reports its frame with
// `onGeometryChange(for: CGRect.self) { $0.frame(in: .global) }`. Keys and clicks are NSEvents sent to the window or the view
// (nothing posted to the system); a header click queues its mouse-up first because `NSTableHeaderView.mouseDown` runs a tracking loop.
// The window class answers `isKeyWindow` true (the process is not the active app). Output lines read `ARM key = value`.
//
// ARMS (spec section 9): G1 G2 G3 (metrics, alternating rows, nil proposal), W1 W2 W3 W4 (default width, fill, shrink, default min),
// T1 T2 (truncation, tall content), S1 S2 S3 S4 (sort clicks), K1..K7 (keys), R1 R2 R3 (reorder default, resize compensation, fixed
// width), A1 A2 (AX roles and attributes, AX under scrolling), L1 (RTL), F1 (`TableColumnForEach` count change).
//
// RECORDED 2026-11-19 by the table-b lane (PR B, task B0), macOS 27.2.1 (26B131), Apple Swift 6.4.2, arm64, an unlocked foreground
// session. The full raw output is committed verbatim in docs/probes/swiftui-table.recorded.txt (addresses and sort-descriptor UUIDs
// normalised). THE READ, one value per fact:
//
// G1 METRICS (800 x 600 window; NSTableView style `.inset` (2); the SwiftUI table is a `SwiftUIOutlineTableView` even for a flat table)
//   row height 24 (`usesAutomaticRowHeights` true: rows size to their content, T2); header 28 high; intercell spacing 17 x 0; the first
//   row sits 5 below the table's top and rows abut (row 1 at y 29); the first column starts at x 10 and a cell's label sits 6 to the right
//   of its column's left edge (label x 16, column x 10). MetalUI does not model the inset style's 10-point side margins, 5-point top
//   margin or 17-point intercell spacing: a MetalUI table is edge to edge, header 28, row 24, cell inset 6 (TBL-V).
// G2 ALTERNATING ROWS: `usesAlternatingRowBackgroundColors` true.
// G3 NIL PROPOSAL: a Table in a vertical ScrollView is 800 x 0 (the proposed width, height 0: it does not size to its rows, and it is
//   not greedy in an unbounded axis); between two Texts in a VStack it is 800 x 568 (the remainder). MetalUI answers the proposal, else 0.
// W1 DEFAULT WIDTH: ten columns with no width modifier in a 400-point table are 100 wide each (sum 1000).
// W2 FILL: fixed 100, (min 50 ideal 100 max 150), (ideal 100) in 800 give [100, 150, 484]; three columns of ideal 100 give
//   [245, 245, 244]. A surplus is split uniformly among the flexible columns, a column stops at its max and the rest goes to the others
//   (the plan's solver). The AppKit chrome (10-point margins, 17-point intercell spacing) takes about 66 of the 800, which MetalUI does not model.
// W3 SHRINK: none. Ten columns of 100 in a 400-point table stay 1000 wide and the table scrolls across (divergence 1106 stays unused).
// W4 DEFAULT MINIMUM: 10 (NSTableColumn.minWidth, no maximum); MetalUI's `defaultMinWidth` is 10 (was provisionally 20).
// T1 TRUNCATION: a one-line label in a column of width 60 is 53 wide (starting at the 6-point inset), so a long text is clipped to the
//   column and truncated; the ellipsis itself is not read here (a Text with lineLimit(1) truncates by default).
// T2 TALL CONTENT: a cell of three Texts makes its row 56 high (rows are 24 high otherwise): SwiftUI sizes the row to its content
//   (divergence 1105).
// S1..S4 SORT CLICKS (a header click through `NSTableHeaderView.mouseDown`, one binding write each):
//   S1 [] -> click Name -> [name+] (forward). S2 click Name again -> [name-] (flipped). S3 [name-] -> click Size -> [size+, name-]
//   (the new column goes first and the OLD ENTRY STAYS). S4 [size+, name-] -> click Name -> [name-, size+]: an existing entry for the
//   column moves to the front KEEPING its order (reverse), it is not flipped and not reset. A column without a comparator writes nothing.
//   The plan's wording ("remove every entry equal to p ignoring order and insert p at the front") does not match S3 (the old entry stays)
//   and S4 (the moved entry keeps its order): task C4 takes THIS read.
// K KEYS (a multi-selection table, 200 rows, keys sent to the window with the table view as first responder)
//   K1 down moves the selection one row and writes the binding once ({10} -> {11}); shift-up extends ({10, 11}).
//   K3 Home and End scroll to the ends (offset -28 -> 4415 -> -28) and write nothing; Page Up and Page Down write nothing and did not
//   scroll under the synthetic event (not measured; the plan's default "scroll only, selection unchanged" stands).
//   K4 left and right write nothing. K5 Return runs the primaryAction with the whole selection ([10, 11]). K7 command-A writes nothing.
//   K6 TYPE-SELECT: typing "name" with a deselected table selects row 0 (one write): SwiftUI type-selects (divergence 1109 is used).
// R1 REORDER DEFAULT: `allowsColumnReordering` false without a column customization: headers do not reorder by default (task D2's
//   branch: the gesture is not attached). allowsColumnResizing true.
// R2 RESIZE COMPENSATION: dragging column B's trailing divider +40 gives widths [206, 206, 100, 205] -> [206, 246, 100, 165]: the
//   last column gives the 40 back, so the table's total stays (divergence 1111 is used: a MetalUI resize does not compensate).
// R3 FIXED WIDTH: a `.width(100)` column has resizingMask 0 (not resizable) with min = max = 100; the others have mask 3.
// A1 ACCESSIBILITY (in process, the legacy attribute API): the table is AXOutline (not AXTable) with AXRows = every row (300 of 300),
//   each AXRow / AXOutlineRow with AXIndex and AXCell children carrying AXRowIndexRange and AXColumnIndexRange; AXColumns = 3 and
//   AXVisibleColumns = 3 (AXColumn elements exist); AXHeader is the header view whose children are AXButton / AXSortButton with
//   AXSortDirection (unknown, then ascending after a click on Name); AXColumnHeaderUIElements is empty. AXRowCount and AXColumnCount are nil.
// A2 AX UNDER SCROLLING: after scrolling to row 250 AXRows is still all 300 and AXVisibleRows is 25 (first AXIndex 226).
// L1 RTL: in a right-to-left environment the columns MIRROR (the first column is the rightmost, x 476, the second at 361) and the
//   userInterfaceLayoutDirection is 1 (divergence 1108 is used: MetalUI lays columns out left to right).
// F1 TableColumnForEach: appending a column keeps the survivors' @State (born# 34, 35, 36 unchanged; the new column's cells are new, 49).
//   REMOVING a column from the set aborts SwiftUI itself in this rig (SIGABRT, "precondition failure: accessing attribute in a different
//   namespace"), so only the append is measured; the survival of the remaining columns' state across a removal is MetalUI's own ruling (TBL-B).
//
// UNMEASURED: Page Up and Page Down scrolling (K3, see above); a real right-click popup; the removal half of F1; the VoiceOver reading
//   (A1/A2 read the legacy attribute API only); the selection highlight colour; whether SwiftUI's header cell cross-fades its indicator.
import SwiftUI
import AppKit

struct Item: Identifiable { let id: Int; var name: String; var size: Int }
func items(_ n: Int) -> [Item] { (0..<n).map { Item(id: $0, name: "name\(($0 * 7) % n)", size: ($0 * 13) % n) } }

@MainActor var lines: [String] = []
@MainActor func out(_ arm: String, _ s: String) { let l = "\(arm) \(s)"; print(l); lines.append(l) }

final class KeyWin: NSWindow {
    override var canBecomeKey: Bool { true }
    override var isKeyWindow: Bool { true }
    override var canBecomeMain: Bool { true }
    override var isMainWindow: Bool { true }
}
func findAll<T: NSView>(_ type: T.Type, in v: NSView) -> [T] {
    ((v as? T).map { [$0] } ?? []) + v.subviews.flatMap { findAll(type, in: $0) }
}
@MainActor func spin(_ n: Int = 12, _ dt: Double = 0.02) { for _ in 0..<n { RunLoop.main.run(until: Date(timeIntervalSinceNow: dt)) } }

@MainActor final class Model: ObservableObject {
    @Published var sel: Int? = nil { didSet { selLog.append(sel.map(String.init) ?? "nil") } }
    @Published var multi: Set<Int> = [] { didSet { selLog.append(multi.sorted().map(String.init).joined(separator: ",")) } }
    @Published var sort: [KeyPathComparator<Item>] = [] { didSet { sortLog.append(Model.describe(sort)) } }
    @Published var names: [String] = ["a", "b", "c"]
    var selB: Binding<Int?> { Binding(get: { self.sel }, set: { self.sel = $0 }) }
    var multiB: Binding<Set<Int>> { Binding(get: { self.multi }, set: { self.multi = $0 }) }
    var sortB: Binding<[KeyPathComparator<Item>]> { Binding(get: { self.sort }, set: { self.sort = $0 }) }
    var selLog: [String] = []
    var sortLog: [String] = []
    var actions: [String] = []
    static func describe(_ s: [KeyPathComparator<Item>]) -> String {
        s.map { ($0.keyPath == \Item.name ? "name" : "size") + ($0.order == .forward ? "+" : "-") }.joined(separator: " ")
    }
}

@MainActor var frames: [String: CGRect] = [:]
@MainActor var born: [String: Int] = [:]
@MainActor var bornCounter = 0
struct Lab: View {
    let id: String
    let text: String
    @State private var mine: Int? = nil
    var body: some View {
        Text(text).lineLimit(1)
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { frames[id] = $0 }
            .onAppear { if mine == nil { bornCounter += 1; mine = bornCounter }; born[id] = mine }
    }
}

@MainActor final class Rig {
    let m = Model()
    let w: KeyWin
    let t: NSTableView
    init<V: View>(size: CGSize = CGSize(width: 800, height: 600), @ViewBuilder _ content: (Model) -> V) {
        frames = [:]
        let h = NSHostingView(rootView: AnyView(content(m)))
        w = KeyWin(contentRect: CGRect(x: 100, y: 100, width: size.width, height: size.height), styleMask: [.borderless], backing: .buffered, defer: false)
        w.contentView = h
        w.orderFrontRegardless()
        spin(30)
        t = findAll(NSTableView.self, in: h).first ?? NSTableView()
        spin(10)
    }
    func close() { w.orderOut(nil); w.close() }
    func key(_ code: UInt16, _ chars: String, flags: NSEvent.ModifierFlags = []) {
        w.makeFirstResponder(t)
        for down in [true, false] {
            if let e = NSEvent.keyEvent(with: down ? .keyDown : .keyUp, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: w.windowNumber,
                                        context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code) { w.sendEvent(e) }
        }
        spin(8)
    }
    /// A click on the header of column `i` (the mouse-up is queued first: the header runs a tracking loop on mouse-down).
    func headerClick(_ i: Int, dx: CGFloat = 0) {
        guard let hv = t.headerView else { return }
        let r = hv.headerRect(ofColumn: i)
        let p = hv.convert(CGPoint(x: r.midX, y: r.midY), to: nil)
        let up = NSEvent.mouseEvent(with: .leftMouseUp, location: CGPoint(x: p.x + dx, y: p.y), modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0)!
        let down = NSEvent.mouseEvent(with: .leftMouseDown, location: p, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        NSApp.postEvent(up, atStart: false)
        hv.mouseDown(with: down)
        spin(10)
    }
    var widths: [CGFloat] { t.tableColumns.map { $0.width } }
}

func f(_ v: CGFloat) -> String { String(format: "%.1f", Double(v)) }
func fr(_ r: CGRect) -> String { "(\(f(r.minX)), \(f(r.minY)), \(f(r.width)), \(f(r.height)))" }

// MARK: arms

@MainActor func armG(_ arms: Set<String>) {
    let rig = Rig { m in
        Table(items(40), selection: m.selB) {
            TableColumn("Name") { Lab(id: "n\($0.id)", text: "name\($0.id)") }
            TableColumn("Size") { Text("\($0.size)") }
        }
    }
    let t = rig.t
    if arms.contains("G1") {
        out("G1", "table class = \(type(of: t)) style = \(t.style.rawValue) rowHeight = \(f(t.rowHeight)) intercell = \(f(t.intercellSpacing.width)) x \(f(t.intercellSpacing.height))")
        out("G1", "header frame = \(t.headerView.map { fr($0.frame) } ?? "nil") header height = \(t.headerView.map { f($0.frame.height) } ?? "nil")")
        out("G1", "row0 rect = \(fr(t.rect(ofRow: 0))) row1 rect = \(fr(t.rect(ofRow: 1))) enclosing clip frame = \(t.enclosingScrollView.map { fr($0.frame) } ?? "nil") contentInsets = \(t.enclosingScrollView.map { "\($0.contentInsets)" } ?? "nil")")
        out("G1", "column 0 frame = \(fr(t.rect(ofColumn: 0))) column 1 frame = \(fr(t.rect(ofColumn: 1)))")
        out("G1", "label n0 frame = \(frames["n0"].map(fr) ?? "nil") (cell inset = label x - column x)")
        out("G1", "header cell font = \(t.headerView?.subviews.first.map { "\($0)" } ?? "nil")")
        out("G1", "gridStyleMask = \(t.gridStyleMask.rawValue) usesAutomaticRowHeights = \(t.usesAutomaticRowHeights)")
    }
    if arms.contains("G2") {
        out("G2", "usesAlternatingRowBackgroundColors = \(t.usesAlternatingRowBackgroundColors)")
    }
    rig.close()
}

@MainActor func armG3() {
    // A Table in a vertical ScrollView: the table is greedy and self-scrolling (nil proposal).
    let rig = Rig(size: CGSize(width: 800, height: 600)) { _ in
        ScrollView {
            Table(items(10)) { TableColumn("Name", value: \.name); TableColumn("Size") { Text("\($0.size)") } }
                .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { frames["table"] = $0 }
        }
    }
    out("G3", "Table in a vertical ScrollView, 10 rows: frame = \(frames["table"].map(fr) ?? "nil") (rows 10 x 24 + header 28 = 268; a greedy table would be 600 or 0)")
    rig.close()
    let rig2 = Rig(size: CGSize(width: 800, height: 600)) { _ in
        VStack(alignment: .leading, spacing: 0) {
            Text("above")
            Table(items(10)) { TableColumn("Name", value: \.name) }
                .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { frames["table"] = $0 }
            Text("below")
        }
    }
    out("G3", "Table in a VStack between two Texts in 800 x 600: frame = \(frames["table"].map(fr) ?? "nil")")
    rig2.close()
}

@MainActor func armW(_ arms: Set<String>) {
    if arms.contains("W1") || arms.contains("W4") {
        // Ten columns with no width modifier in 400: a column's default (ideal) width and minimum.
        let rig = Rig(size: CGSize(width: 400, height: 300)) { _ in
            Table(items(5)) {
                TableColumn("A") { Text("\($0.id)") }; TableColumn("B") { Text("\($0.id)") }; TableColumn("C") { Text("\($0.id)") }
                TableColumn("D") { Text("\($0.id)") }; TableColumn("E") { Text("\($0.id)") }; TableColumn("F") { Text("\($0.id)") }
                TableColumn("G") { Text("\($0.id)") }; TableColumn("H") { Text("\($0.id)") }; TableColumn("I") { Text("\($0.id)") }
                TableColumn("J") { Text("\($0.id)") }
            }
        }
        out("W1", "10 columns, no width, viewport 400: widths = \(rig.widths.map(f))")
        out("W4", "minWidth = \(rig.t.tableColumns.map { f($0.minWidth) }) maxWidth = \(rig.t.tableColumns.map { f($0.maxWidth) })")
        out("W3", "10 columns in 400: sum of widths = \(f(rig.widths.reduce(0, +))) (shrinks to the viewport if <= 400) document width = \(rig.t.enclosingScrollView.map { f($0.documentView?.frame.width ?? -1) } ?? "nil")")
        rig.close()
    }
    if arms.contains("W2") {
        let rig = Rig(size: CGSize(width: 800, height: 300)) { _ in
            Table(items(5)) {
                TableColumn("A") { Text("\($0.id)") }.width(100)
                TableColumn("B") { Text("\($0.id)") }.width(min: 50, ideal: 100, max: 150)
                TableColumn("C") { Text("\($0.id)") }.width(ideal: 100)
            }
        }
        out("W2", "fixed 100, (min 50 ideal 100 max 150), (ideal 100) in 800: widths = \(rig.widths.map(f)) (the plan's solver would give [100, 150, 550])")
        rig.close()
        let rig2 = Rig(size: CGSize(width: 800, height: 300)) { _ in
            Table(items(5)) {
                TableColumn("A") { Text("\($0.id)") }.width(ideal: 100)
                TableColumn("B") { Text("\($0.id)") }.width(ideal: 100)
                TableColumn("C") { Text("\($0.id)") }.width(ideal: 100)
            }
        }
        out("W2", "three columns ideal 100 in 800: widths = \(rig2.widths.map(f)) intercell = \(f(rig2.t.intercellSpacing.width))")
        rig2.close()
    }
}

@MainActor func armT(_ arms: Set<String>) {
    let rig = Rig(size: CGSize(width: 400, height: 400)) { _ in
        Table(items(4)) {
            TableColumn("Narrow") { Lab(id: "t\($0.id)", text: "abcdefghijklmnopqrstuvwxyz abcdefghijklmnopqrstuvwxyz") }.width(60)
            TableColumn("Tall") { r in
                VStack(alignment: .leading, spacing: 0) {
                    Text("line one").onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { frames["tall1.\(r.id)"] = $0 }
                    Text("line two"); Text("line three")
                }
            }.width(200)
        }
    }
    if arms.contains("T1") {
        out("T1", "narrow column width 60: label frame row 0 = \(frames["t0"].map(fr) ?? "nil"), column 0 rect = \(fr(rig.t.rect(ofColumn: 0))) (a label of one truncated line: height ~ 16, width <= column - 2 x inset)")
    }
    if arms.contains("T2") {
        out("T2", "VStack of three Texts in a row: row 0 rect = \(fr(rig.t.rect(ofRow: 0))) row 1 rect = \(fr(rig.t.rect(ofRow: 1))) first line frame = \(frames["tall1.0"].map(fr) ?? "nil") usesAutomaticRowHeights = \(rig.t.usesAutomaticRowHeights)")
    }
    rig.close()
}

@MainActor func armS(_ arms: Set<String>) {
    let rig = Rig { m in
        Table(items(30), sortOrder: m.sortB) {
            TableColumn("Name", value: \.name)
            TableColumn("Size", value: \.size) { Text("\($0.size)") }
            TableColumn("Plain") { Text("\($0.id)") }
        }
    }
    let m = rig.m
    m.sortLog = []
    rig.headerClick(0); out("S1", "click Name (nothing sorted): writes = \(m.sortLog)")
    m.sortLog = []
    rig.headerClick(0); out("S2", "click Name again: writes = \(m.sortLog)")
    m.sortLog = []
    rig.headerClick(1); out("S3", "click Size (sort is [name-]): writes = \(m.sortLog)")
    m.sortLog = []
    rig.headerClick(0); out("S4", "click Name (sort is [size+]): writes = \(m.sortLog); then the order array held = \(Model.describe(m.sort))")
    m.sortLog = []
    rig.headerClick(2); out("S4", "click Plain (no comparator): writes = \(m.sortLog)")
    out("S1", "sortDescriptors on the table = \(rig.t.sortDescriptors.map { "\($0.key ?? "?")\($0.ascending ? "+" : "-")" })")
    rig.close()
}

@MainActor func armK(_ arms: Set<String>) {
    let rig = Rig(size: CGSize(width: 800, height: 400)) { m in
        Table(items(200), selection: m.multiB) {
            TableColumn("Name", value: \.name)
            TableColumn("Size") { Text("\($0.size)") }
        }
        .contextMenu(forSelectionType: Int.self) { _ in Button("Act") {} } primaryAction: { ids in
            m.actions.append("primary \(ids.sorted())")
        }
    }
    let m = rig.m
    let sv = rig.t.enclosingScrollView
    func y() -> String { f(sv?.contentView.bounds.origin.y ?? -1) }
    // select row 10 first
    m.selLog = []
    rig.t.selectRowIndexes(IndexSet(integer: 10), byExtendingSelection: false); spin()
    m.selLog = []
    rig.key(125, "\u{F701}"); out("K1", "down from row 10: writes = \(m.selLog)")
    m.selLog = []
    rig.key(126, "\u{F700}", flags: NSEvent.ModifierFlags.shift); out("K1", "shift-up: writes = \(m.selLog)")
    m.selLog = []; let y0 = y()
    rig.key(121, "\u{F72D}"); out("K3", "page down: writes = \(m.selLog) scroll y \(y0) -> \(y())")
    m.selLog = []; let y1 = y()
    rig.key(116, "\u{F72C}"); out("K3", "page up: writes = \(m.selLog) scroll y \(y1) -> \(y())")
    m.selLog = []; let y2 = y()
    rig.key(119, "\u{F72B}"); out("K3", "end: writes = \(m.selLog) scroll y \(y2) -> \(y())")
    m.selLog = []; let y3 = y()
    rig.key(115, "\u{F729}"); out("K3", "home: writes = \(m.selLog) scroll y \(y3) -> \(y())")
    m.selLog = []
    rig.key(123, "\u{F702}"); rig.key(124, "\u{F703}"); out("K4", "left then right: writes = \(m.selLog)")
    m.actions = []
    rig.key(36, "\r"); out("K5", "return: actions = \(m.actions)")
    m.selLog = []
    rig.key(0, "a", flags: NSEvent.ModifierFlags.command); out("K7", "command-A: writes = \(m.selLog) (count of rows selected: \(rig.t.numberOfSelectedRows))")
    m.selLog = []
    rig.t.deselectAll(nil); spin(); m.selLog = []
    rig.key(17, "n"); rig.key(14, "a"); rig.key(46, "m"); rig.key(14, "e")
    out("K6", "type 'name' with a row-name column: writes = \(m.selLog) selected row = \(rig.t.selectedRow) (type-select would select a row whose first column text starts with \"name\")")
    rig.close()
}

@MainActor func armR(_ arms: Set<String>) {
    let rig = Rig { m in
        Table(items(10)) {
            TableColumn("A", value: \.name)
            TableColumn("B") { Text("\($0.id)") }.width(min: 50, ideal: 100, max: 300)
            TableColumn("C") { Text("\($0.id)") }.width(100)
            TableColumn("D") { Text("\($0.id)") }
        }
    }
    let t = rig.t
    out("R1", "allowsColumnReordering = \(t.allowsColumnReordering) allowsColumnResizing = \(t.allowsColumnResizing) columnAutoresizingStyle = \(t.columnAutoresizingStyle.rawValue)")
    out("R3", "resizingMasks = \(t.tableColumns.map { $0.resizingMask.rawValue }) (1 = autoresizing, 2 = user resizing) widths = \(rig.widths.map(f)) min = \(t.tableColumns.map { f($0.minWidth) }) max = \(t.tableColumns.map { f($0.maxWidth) })")
    // R2: a user resize of column B: do the others give way? Drive it through the header divider with a queued drag.
    let before = rig.widths
    if let hv = t.headerView {
        let r = hv.headerRect(ofColumn: 1)
        let start = hv.convert(CGPoint(x: r.maxX - 1, y: r.midY), to: nil)
        let drag = NSEvent.mouseEvent(with: .leftMouseDragged, location: CGPoint(x: start.x + 40, y: start.y), modifierFlags: [], timestamp: 0, windowNumber: rig.w.windowNumber, context: nil, eventNumber: 3, clickCount: 1, pressure: 1)!
        let up = NSEvent.mouseEvent(with: .leftMouseUp, location: CGPoint(x: start.x + 40, y: start.y), modifierFlags: [], timestamp: 0, windowNumber: rig.w.windowNumber, context: nil, eventNumber: 4, clickCount: 1, pressure: 0)!
        let down = NSEvent.mouseEvent(with: .leftMouseDown, location: start, modifierFlags: [], timestamp: 0, windowNumber: rig.w.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 1)!
        NSApp.postEvent(drag, atStart: false); NSApp.postEvent(up, atStart: false)
        hv.mouseDown(with: down); spin(10)
    }
    out("R2", "drag column B's trailing divider +40: widths before = \(before.map(f)) after = \(rig.widths.map(f)) (neighbours give way if the sum stays the viewport)")
    rig.close()
}

@MainActor func armA(_ arms: Set<String>) {
    let rig = Rig { m in
        Table(items(300), selection: m.selB, sortOrder: m.sortB) {
            TableColumn("Name", value: \.name)
            TableColumn("Size", value: \.size) { Text("\($0.size)") }
            TableColumn("Plain") { Text("\($0.id)") }
        }
    }
    let t = rig.t
    rig.t.selectRowIndexes(IndexSet(integer: 2), byExtendingSelection: false); spin()
    func raw(_ o: Any?, _ a: String) -> Any? {
        guard let obj = o as? NSObject else { return nil }
        return obj.accessibilityAttributeValue(NSAccessibility.Attribute(rawValue: a))
    }
    func attr(_ o: Any?, _ a: String) -> String { raw(o, a).map { "\($0)" } ?? "nil" }
    func list(_ o: Any?, _ a: String) -> [Any] { (raw(o, a) as? NSArray).map { $0.map { $0 as Any } } ?? [] }
    out("A1", "table class = \(type(of: t)) AXRole = \(attr(t, "AXRole")) AXSubrole = \(attr(t, "AXSubrole")) AXRowCount = \(attr(t, "AXRowCount")) AXColumnCount = \(attr(t, "AXColumnCount"))")
    let rows = list(t, "AXRows")
    out("A1", "AXRows = \(rows.count) first row class = \(rows.first.map { String(describing: type(of: $0)) } ?? "nil")")
    if let r0 = rows.first {
        out("A1", "row 0 AXRole = \(attr(r0, "AXRole")) AXSubrole = \(attr(r0, "AXSubrole")) AXIndex = \(attr(r0, "AXIndex")) AXChildren count = \(list(r0, "AXChildren").count)")
        if let c0 = list(r0, "AXChildren").first {
            out("A1", "row 0 child 0 class = \(type(of: c0)) AXRole = \(attr(c0, "AXRole")) AXRowIndexRange = \(attr(c0, "AXRowIndexRange")) AXColumnIndexRange = \(attr(c0, "AXColumnIndexRange"))")
        }
    }
    out("A1", "AXColumns = \(list(t, "AXColumns").count) AXVisibleColumns = \(list(t, "AXVisibleColumns").count) AXHeader = \(attr(t, "AXHeader")) AXColumnHeaderUIElements = \(list(t, "AXColumnHeaderUIElements").count)")
    out("A1", "AXSelectedRows count = \(list(t, "AXSelectedRows").count) AXVisibleRows count = \(list(t, "AXVisibleRows").count)")
    let heads = list(t, "AXColumnHeaderUIElements")
    out("A1", "header cells: \(heads.map { attr($0, "AXRole") + "/" + attr($0, "AXSubrole") + "/" + attr($0, "AXSortDirection") })")
    out("A1", "header view AXChildren: \(list(t.headerView, "AXChildren").map { attr($0, "AXRole") + "/" + attr($0, "AXSubrole") + "/" + attr($0, "AXSortDirection") })")
    rig.headerClick(0)
    out("A1", "after clicking Name: header view AXChildren: \(list(t.headerView, "AXChildren").map { attr($0, "AXRole") + "/" + attr($0, "AXSubrole") + "/" + attr($0, "AXSortDirection") })")
    out("A1", "after clicking Name: header cells: \(list(t, "AXColumnHeaderUIElements").map { attr($0, "AXRole") + "/" + attr($0, "AXSubrole") + "/" + attr($0, "AXSortDirection") })")
    // A2: AX under scrolling: the rows reported after a scroll.
    t.scrollRowToVisible(250); spin()
    let vis = list(t, "AXVisibleRows")
    out("A2", "after scrolling to row 250: AXRows = \(list(t, "AXRows").count) AXVisibleRows = \(vis.count) first visible AXIndex = \(vis.first.map { attr($0, "AXIndex") } ?? "nil")")
    rig.close()
}

@MainActor func armL() {
    let rig = Rig(size: CGSize(width: 600, height: 300)) { _ in
        Table(items(5)) {
            TableColumn("A") { Lab(id: "a\($0.id)", text: "a\($0.id)") }.width(100)
            TableColumn("B") { Text("\($0.id)") }.width(100)
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
    out("L1", "layoutDirection rightToLeft: column rects = \((0..<2).map { fr(rig.t.rect(ofColumn: $0)) }) first-column label = \(frames["a0"].map(fr) ?? "nil") userInterfaceLayoutDirection = \(rig.t.userInterfaceLayoutDirection.rawValue) (0 LTR, 1 RTL)")
    rig.close()
}

struct ForEachRoot: View {
    @ObservedObject var m: Model
    var body: some View {
        Table(items(5)) {
            TableColumnForEach(m.names, id: \.self) { n in
                TableColumn(n) { r in Lab(id: "\(n)\(r.id)", text: "\(n)\(r.id)") }
            }
        }
    }
}

@MainActor func armF() {
    let rig = Rig { m in ForEachRoot(m: m) }
    out("F1", "columns a b c: titles = \(rig.t.tableColumns.map { $0.title }) born a0 = \(born["a0"] ?? -1) b0 = \(born["b0"] ?? -1) c0 = \(born["c0"] ?? -1)")
    // Removing a column (["b", "c", "d"], or ["a", "b"]) aborts SwiftUI itself in this rig ("precondition failure: accessing attribute in a
    // different namespace", SIGABRT), so only an APPEND is measured.
    rig.m.names = ["a", "b", "c", "d"]; spin(30)
    out("F1", "columns a b c d (append): titles = \(rig.t.tableColumns.map { $0.title }) born a0 = \(born["a0"] ?? -1) b0 = \(born["b0"] ?? -1) c0 = \(born["c0"] ?? -1) d0 = \(born["d0"] ?? -1) (a surviving column keeps its @State when its born number is unchanged)")
    out("F1", "removing a column (names [b, c, d]) aborts SwiftUI in this rig (SIGABRT, precondition failure); not measured")
    rig.close()
}

@MainActor func main() {
    setvbuf(stdout, nil, _IOLBF, 0)
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let args = Set(CommandLine.arguments.dropFirst())
    func want(_ a: String...) -> Set<String> { args.isEmpty ? Set(a) : Set(a).intersection(args) }
    let g = want("G1", "G2"); if !g.isEmpty { armG(g) }
    if want("G3").count > 0 { armG3() }
    let w = want("W1", "W2", "W3", "W4"); if !w.isEmpty { armW(w) }
    let t = want("T1", "T2"); if !t.isEmpty { armT(t) }
    let s = want("S1", "S2", "S3", "S4"); if !s.isEmpty { armS(s) }
    let k = want("K1", "K2", "K3", "K4", "K5", "K6", "K7"); if !k.isEmpty { armK(k) }
    let r = want("R1", "R2", "R3"); if !r.isEmpty { armR(r) }
    let a = want("A1", "A2"); if !a.isEmpty { armA(a) }
    if want("L1").count > 0 { armL() }
    if want("F1").count > 0 { armF() }
}
MainActor.assumeIsolated { main() }
