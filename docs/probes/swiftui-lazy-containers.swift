// SwiftUI probe: LazyVStack/LazyHStack/LazyVGrid/LazyHGrid and GridItem, for
// item L1 (docs/superpowers/specs/2026-10-21-lazy-containers-design.md,
// rulings LZ-… in docs/superpowers/2026-10-21-lazy-containers-decisions.md).
// Extends docs/probes/swiftui-lazy-grid-scope.swift (LZ0-LZ7: grid columns,
// 16 of 1000 cells realised), swiftui-lifecycle.swift S2 and
// swiftui-data-and-scrolling.swift L2/T10 (a lazy stack realises only what is
// on screen; an unrealised row is a scrollTo target).
//
// HOW TO RUN (ruling SA-O):
//
//   /usr/bin/swift docs/probes/swiftui-lazy-containers.swift
//
// `/usr/bin/swift` is Apple's toolchain; a swift.org toolchain's JIT fails on
// SwiftUI symbols.
//
// METHOD. Two instruments.
// - Layout arms (`A`, `C`, `G`): the `Probe` layout of swiftui-lazy-grid-scope
//   asks the container for its size at the stated proposal and places it at
//   (0, 0); each child is an `L` leaf of fixed size recording its placed rect.
//   Every group has a CONTROL that must differ from the arm under test (the
//   eager VStack for a lazy stack; a different GridItem for a grid).
// - Realisation arms (`R`, `S`, `H`): the view is hosted in a 200x200 window
//   behind a ScrollView; every child records `body`, `onAppear` and
//   `onDisappear`; the first NSScrollView's clip view is scrolled with AppKit
//   (`ScrollViewReader.scrollTo` is a broken instrument headless, see
//   swiftui-lifecycle.swift). A child's `@State` is written once at its first
//   appearance (the serial it drew), so a later appearance showing the same
//   serial is retention and a new serial is a fresh child.
// The Cx/Rx arms print `size`, placements or sets; nothing is inferred.
//
// RECORDED 2026-10-21 by the lazy-containers design session (item L1), macOS 27.0
// (26A434), Apple Swift 6.4 (swiftlang-6.4.0.33.1), screen UNLOCKED. Compiled form
// (`xcrun swiftc -O`), run twice, exit 0, byte-identical stdout (62 lines).
//
// THE READING (each line names the arm; the figures are in WHOLE STDOUT below).
// 1. SIZE. A lazy stack answers the proposal on its cross axis whenever there is
//    one (A1 200 at 200; A5 80 at 80 although child b is 100) and its content on
//    the main axis (A1 height 40, not 200: not greedy). The control VStack
//    answers the widest child (A0 100). At a NIL cross proposal the lazy stack
//    answers the FIRST child's cross size (A3 30; A3b 100 with widths 100/30/50;
//    A3d 50 with widths 50/100/30), so the premise "the widest realised child" is
//    REFUTED: it is the first. LazyHStack is the same on the other axis (A6 180x10,
//    A7 180x200). Children align inside that size (A1 centre, A4 leading, A4t
//    trailing; b overflows centred at -35 in A3).
// 2. SPACING. Default spacing is the VStack's: 8 between leaf views (A2 = A2c);
//    two Texts take the same 32 high in both (A10 = A10c, divergence 51). A
//    ForEach element of two views is two views in sequence (A8: b at y 10, no
//    extra group spacing). An element producing NO view adds no spacing (A9: a,
//    then c at 16 = 10 + 6).
// 3. REALISATION. Inside a ScrollView along the stack's axis only the views on
//    screen are built and appear: 10 of 1000 at offset 0 (R1; 20pt rows in 200),
//    100...109 after a scroll to 2000 (the earlier ones built = 20 in all, so a
//    realised view is dropped when it leaves), and the same horizontally (R2);
//    the control VStack builds all 1000 (R0). There is NO margin: exactly the
//    on-screen rows appear, which MetalUI does not match (divergence 637). A
//    lazy stack in a scroller of the OTHER axis is not windowed (R5: all 1000
//    realised, then 900 after a clip scroll: the stack is unbounded on its own axis).
// 4. EXTENT. Unrealised children count as the measured ones' mean: 20000 for 1000
//    rows with one unrealised 120-tall row (R4; 20100 if it were measured), 15000
//    for 500 grid rows with one unrealised tall cell (G2). The width of the stack
//    in a vertical ScrollView is the viewport's (R3: 200 at both offsets).
// 5. STATE. A scrolled-out child's `@State` outlives it: child 0 appeared twice
//    with ONE serial after a 4000pt round trip (S1); the control never left (S2).
//    MetalUI's `TB-AH` retention is the same shape but bounded (divergence 84's
//    family; see LZ-H).
// 6. GRIDITEM. Tracks are item-driven, not cell-driven (LZ1 of the grid-scope
//    probe). Spacing after a column is its item's `spacing` (C7: 20 then 0; the
//    grid's `spacing:` is the row gap, 4), default 8 (C1 row gap 18 = 10 + 8).
//    Fixed columns are exact. Flexible columns: a column whose MINIMUM exceeds the
//    equal share takes its minimum and the others share what is left (C15: 150
//    and 42); otherwise the share is (available - fixed - gaps) / n, CLAMPED to
//    the maximum WITHOUT giving the excess back (C4: 67, 67 -> 40, total 173; C6:
//    96 and 30, total 134). Adaptive: n = floor((remaining + s) / (min + s)),
//    width (remaining - (n - 1) s) / n, clamped to the maximum (C1 n = 7 at 200,
//    21.71 wide; C2 n = 3; C3 spacing 20 gives n = 3, 53.33; C16 one column of 70
//    in 100; C17 beside a fixed 40, remaining 152: n = 4, 32 wide). The tracks
//    TOGETHER are aligned in the proposal by `alignment:` (C8 leading 0, C8c
//    centre 76) and the grid is `max(proposal, tracks)` wide (C5 248 at 200: the
//    minima overflow to the right from x 0; C8 200). A cell sits in its track by
//    the item's `alignment` (C9 topLeading / bottomTrailing, centre by default,
//    C10 c3 centred in a 30 tall row). A row is as tall as its tallest cell
//    (C10 48 = 10 + 8 + 30) and a LazyHGrid column as wide as its widest (C11
//    48 = 10 + 8 + 30). At a nil width the tracks come from the FIRST row's
//    cells (LZ4: 58) and an adaptive item makes one column (C12). No items: 0x0
//    (C13). A ForEach element of two views is TWO cells (C14).
// 7. PINNING. `pinnedViews: [.sectionHeaders]` held the header at the viewport
//    top (H1 minY 0 at offset 300), but the unpinned control never reported a
//    frame (H0: `onChange` of a scrolled frame did not fire headless), so the
//    arm cannot separate pinned from unpinned: a BROKEN CONTROL, kept visible. The
//    pinned behaviour is therefore unproven here and `pinnedViews` is not built
//    (LZ-N).
//
// WHOLE STDOUT:
//
//   === A: sizing and spacing outside a ScrollView (children 30x10, 100x20, 50x10)
//   A0 control VStack(spacing: 0) @200x200: size 100x40 | a (35,0 30x10) | b (0,10 100x20) | c (25,30 50x10)
//   A1 LazyVStack(spacing: 0) @200x200: size 200x40 | a (85,0 30x10) | b (50,10 100x20) | c (75,30 50x10)
//   A2 LazyVStack() default spacing @200x200: size 200x56 | a (85,0 30x10) | b (50,18 100x20) | c (75,46 50x10)
//   A2c control VStack() default spacing @200x200: size 100x56 | a (35,0 30x10) | b (0,18 100x20) | c (25,46 50x10)
//   A3 LazyVStack(spacing: 0) at nil @nilxnil: size 30x40 | a (0,0 30x10) | b (-35,10 100x20) | c (-10,30 50x10)
//   A3c control VStack(spacing: 0) at nil @nilxnil: size 100x40 | a (35,0 30x10) | b (0,10 100x20) | c (25,30 50x10)
//   A3b LazyVStack(spacing: 0) at nil, widths 100, 30, 50 (first is widest) @nilxnil: size 100x40 | a (0,0 100x10) | b (35,10 30x20) | c (25,30 50x10)
//   A3d LazyVStack(spacing: 0) at nil, widths 50, 100, 30 (middle is widest) @nilxnil: size 50x40 | a (0,0 50x10) | b (-25,10 100x20) | c (10,30 30x10)
//   A10 LazyVStack() two Texts @nilxnil: size 23x32
//   A10c control VStack() two Texts @nilxnil: size 23x32
//   A4 LazyVStack(alignment: .leading, spacing: 0) @200x200: size 200x40 | a (0,0 30x10) | b (0,10 100x20) | c (0,30 50x10)
//   A4t LazyVStack(alignment: .trailing, spacing: 0) @200x200: size 200x40 | a (170,0 30x10) | b (100,10 100x20) | c (150,30 50x10)
//   A5 LazyVStack(spacing: 4) at width 80 (narrower than child b) @80xnil: size 80x48 | a (25,0 30x10) | b (-10,14 100x20) | c (15,38 50x10)
//   A6 LazyHStack(spacing: 0) at nil (children 30x10, 100x20, 50x10) @nilxnil: size 180x10 | a (0,0 30x10) | b (30,-5 100x20) | c (130,0 50x10)
//   A6c control HStack(spacing: 0) at nil @nilxnil: size 180x20 | a (0,5 30x10) | b (30,0 100x20) | c (130,5 50x10)
//   A7 LazyHStack(alignment: .top, spacing: 0) @200x200 @200x200: size 180x200 | a (0,0 30x10) | b (30,0 100x20) | c (130,0 50x10)
//   A8 LazyVStack(spacing: 0) with a ForEach element of two views (a 30x10, b 100x20) then c @200x200: size 200x40 | a (85,0 30x10) | b (50,10 100x20) | c (75,30 50x10)
//   A9 LazyVStack(spacing: 0) with an empty ForEach element between a and c (spacing: 6) @200x200: size 200x26 | a (85,0 30x10) | c (75,16 50x10)
//   === C: GridItem resolution, LazyVGrid at 200x200 (cells 10x10 unless stated)
//   C1 .adaptive(minimum: 20, maximum: 50) x1, 8 cells @200x200: size 200.00x28 | c0 (5.86,0 10x10) | c1 (35.57,0 10x10) | c2 (65.29,0 10x10) | c3 (95.00,0 10x10) | c4 (124.71,0 10x10) | c5 (154.43,0 10x10) | c6 (184.14,0 10x10) | c7 (5.86,18 10x10)
//   C2 .adaptive(minimum: 60, maximum: 70) x1, 4 cells @200x200: size 200.00x28 | c0 (25.67,0 10x10) | c1 (95.00,0 10x10) | c2 (164.33,0 10x10) | c3 (25.67,18 10x10)
//   C3 .adaptive(minimum: 45) spacing: 20 on the item, 6 cells @200x200: size 200.00x28 | c0 (21.67,0 10x10) | c1 (95.00,0 10x10) | c2 (168.33,0 10x10) | c3 (21.67,18 10x10) | c4 (95.00,18 10x10) | c5 (168.33,18 10x10)
//   C4 .fixed(50), .flexible(), .flexible(minimum: 20, maximum: 40), 6 cells @200x200: size 200x28 | c0 (33.50,0 10x10) | c1 (100,0 10x10) | c2 (161.50,0 10x10) | c3 (33.50,18 10x10) | c4 (100,18 10x10) | c5 (161.50,18 10x10)
//   C5 .flexible(minimum: 120), .flexible(minimum: 120) (minima exceed 200), 4 cells @200x200: size 248x28 | c0 (55,0 10x10) | c1 (183,0 10x10) | c2 (55,18 10x10) | c3 (183,18 10x10)
//   C6 .flexible(), .flexible(maximum: 30), 4 cells @200x200: size 200x28 | c0 (76,0 10x10) | c1 (147,0 10x10) | c2 (76,18 10x10) | c3 (147,18 10x10)
//   C7 .fixed(30), .fixed(30) item spacing 20 then 0; grid spacing 4, 4 cells @200x200: size 200x24 | c0 (70,0 10x10) | c1 (120,0 10x10) | c2 (70,14 10x10) | c3 (120,14 10x10)
//   C8 .fixed(30) x2 with LazyVGrid(alignment: .leading) in 200 (columns narrower than the proposal) @200x200: size 200x28 | c0 (0,0 10x10) | c1 (38,0 10x10) | c2 (0,18 10x10) | c3 (38,18 10x10)
//   C8c control: the same, default alignment (.center) @200x200: size 200x28 | c0 (76,0 10x10) | c1 (114,0 10x10) | c2 (76,18 10x10) | c3 (114,18 10x10)
//   C9 GridItem(.fixed(30), alignment: .topLeading) x2, cells 10x10 and 10x20 (row 0: c0 10x10, c1 10x20) @200x200: size 200x38 | c0 (66,0 10x10) | c1 (124,0 10x20) | c2 (66,28 10x10) | c3 (124,28 10x10)
//   C10 LazyVGrid(.flexible x2) at width 100 and nil height, cells 10x10 and 10x30 in row 1 @100xnil: size 100x48 | c0 (18,0 10x10) | c1 (72,0 10x10) | c2 (18,18 10x30) | c3 (72,28 10x10)
//   C11 LazyHGrid(rows: .flexible x2) at 200x100, cells 10x10 and 30x10 in column 1 @200x100: size 48x100 | c0 (0,18 10x10) | c1 (0,72 10x10) | c2 (18,18 30x10) | c3 (28,72 10x10)
//   C12 LazyVGrid(.adaptive(minimum: 45)) at nil width, 4 cells @nilxnil: size 10x64 | c0 (0,0 10x10) | c1 (0,18 10x10) | c2 (0,36 10x10) | c3 (0,54 10x10)
//   C13 LazyVGrid(columns: []) (no items), 2 cells @200x200: size 0x0
//   C14 LazyVGrid(.fixed 40) x1, a ForEach element of two views (a, b) then c @200x200: size 200x46 | a (95,0 10x10) | b (95,18 10x10) | c (95,36 10x10)
//   C15 .flexible(minimum: 150), .flexible() (one minimum above its share), 4 cells @200x200: size 200x28 | c0 (70,0 10x10) | c1 (174,0 10x10) | c2 (70,18 10x10) | c3 (174,18 10x10)
//   C16 .adaptive(minimum: 60, maximum: 70) at width 100 (one column wider than the maximum) @100xnil: size 100x46 | c0 (45,0 10x10) | c1 (45,18 10x10) | c2 (45,36 10x10)
//   C17 .fixed(40), .adaptive(minimum: 30), 6 cells @200x200: size 200x28 | c0 (15,0 10x10) | c1 (59,0 10x10) | c2 (99,0 10x10) | c3 (139,0 10x10) | c4 (179,0 10x10) | c5 (15,18 10x10)
//   === R: realisation inside a 200x200 ScrollView (rows 20 tall, spacing 0, 1000 rows)
//   R1 LazyVStack at offset 0: built 0...9 (10), visible(onAppear) 0...9 (10)
//   R1 after scroll to 2000 (rows 100..109 on screen): built 0...109 (20), visible 100...109 (10)
//   R1 back to 0: visible 0...9 (10)
//   R0 control VStack at offset 0: built 0...999 (1000), visible 0...999 (1000)
//   R2 LazyHStack in a horizontal ScrollView at 0: built 0...9 (10), visible 0...9 (10)
//   R2 after scroll x to 2000 (columns 100..109): visible 100...109 (10)
//   R3 cross size, width = 20 + 0.5 i, ScrollView(.vertical) 200 wide: realised 0...9 (10), the stack's width 200 height 20000
//   R3 after scroll to 2000: realised 100...109 (10), the stack's width 200 height 20000
//   R4 total height with one unrealised 120-tall child among 1000 20-tall: height 20000 (all 20: 20000, if the unrealised were measured: 20100)
//   R5 LazyVStack (nil width) in a horizontal ScrollView, width = 20 + 0.5 i: realised 0...999 (1000), stack 20x20000
//   R5 after a vertical clip scroll to 2000: realised 100...999 (900), stack 20x20000
//   === S: state of a scrolled-out child (serial drawn by its @State at its first appearance)
//   S1 LazyVStack child 0: appeared 2 times, 1 distinct @State serials (1 = the state outlived leaving the screen), same as the first appearance: true
//   S2 control VStack child 0: appeared 1 time (never left)
//   === G: lazy grid realisation, 200x200 ScrollView, 2 flexible columns, cells 10x30, 1000 cells
//   G1 at 0: built 0...13 (14), visible 0...13 (14), grid size 28x15000 (500 rows x 30 = 15000 if rows are uniform)
//   G1 after scroll to 3000 (row 100 at the top: cells 200...): visible 200...213 (14)
//   G2 one tall unrealised cell (130 at index 600, row 300): grid height 15000 (500x30 = 15000; with the tall row measured 15100)
//   === H: pinnedViews (Section header 30 tall, rows 20 tall, ScrollView 200x200 scrolled to y = 300)
//   H1 at 0: header frame in the scroll view's space (0,0 200x30)
//   H1 at 300: header frame (0,0 200x30) (pinned: minY 0; unpinned: -300)
//   H0 control, no pinnedViews: header frame at 300 (0,0 0x0) (onChange only; zero means it never reported a new frame)
//   DONE
//

import AppKit
import SwiftUI

func d(_ v: CGFloat?) -> String {
    guard let v else { return "nil" }
    if v == .infinity { return "inf" }
    return v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v)
}
func fmt(_ s: CGSize) -> String { "\(d(s.width))x\(d(s.height))" }
func fmt(_ r: CGRect) -> String { "(\(d(r.minX)),\(d(r.minY)) \(d(r.width))x\(d(r.height)))" }

nonisolated(unsafe) var placed: [String: CGRect] = [:]
nonisolated(unsafe) var names: [String] = []
nonisolated(unsafe) var lastSize: CGSize = .zero

struct L: Layout {
    let name: String; let w: CGFloat; let h: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews _: Subviews, cache: inout ()) -> CGSize {
        if !names.contains(name) { names.append(name) }
        return CGSize(width: w, height: h)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        if !names.contains(name) { names.append(name) }
        placed[name] = bounds
        subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
    }
}
func fx(_ n: String, _ w: CGFloat, _ h: CGFloat) -> some View { L(name: n, w: w, h: h) { SwiftUI.Color.clear } }

struct Probe: Layout {
    let proposal: ProposedViewSize
    func sizeThatFits(proposal _: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let s = subviews[0].sizeThatFits(proposal); lastSize = s; return s
    }
    func placeSubviews(in _: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        lastSize = subviews[0].sizeThatFits(proposal)
        subviews[0].place(at: .zero, anchor: .topLeading, proposal: proposal)
    }
}
@MainActor func arm<V: View>(_ label: String, _ proposal: ProposedViewSize, @ViewBuilder _ view: () -> V) {
    placed = [:]; names = []; lastSize = CGSize(width: -1, height: -1)
    let host = NSHostingView(rootView: Probe(proposal: proposal) { view() })
    host.frame = CGRect(x: 0, y: 0, width: 1000, height: 1000)
    host.layoutSubtreeIfNeeded()
    print("\(label) @\(d(proposal.width))x\(d(proposal.height)): size \(fmt(lastSize))"
          + names.map { " | \($0) " + (placed[$0].map(fmt) ?? "not placed") }.joined())
    fflush(stdout)
}

// MARK: realisation instrument

@MainActor func spin(_ s: Double = 0.2) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
nonisolated(unsafe) var built = Set<Int>()
nonisolated(unsafe) var visible = Set<Int>()
nonisolated(unsafe) var serialSeen: [Int: Int] = [:]   // child -> the serial its @State drew at first appear
nonisolated(unsafe) var appearLog: [(Int, Int)] = []   // (child, serial) per appearance
nonisolated(unsafe) var nextSerial = 100
nonisolated(unsafe) var contentSize = CGSize.zero
nonisolated(unsafe) var panelWidth: CGFloat = 0

struct Item: View {
    let i: Int; let w: CGFloat; let h: CGFloat
    @State private var serial = 0
    var body: some View {
        built.insert(i)
        return SwiftUI.Color.clear.frame(width: w, height: h)
            .onAppear {
                visible.insert(i)
                if serial == 0 { nextSerial += 1; serial = nextSerial }
                appearLog.append((i, serial))
            }
            .onDisappear { visible.remove(i) }
    }
}
func range(_ s: Set<Int>) -> String {
    guard let lo = s.min(), let hi = s.max() else { return "none" }
    return "\(lo)...\(hi) (\(s.count))"
}
func resetInstrument() {
    built = []; visible = []; serialSeen = [:]; appearLog = []; nextSerial = 100; contentSize = .zero
}
@MainActor func scrollViews(in view: NSView) -> [NSScrollView] {
    var found: [NSScrollView] = []
    if let s = view as? NSScrollView { found.append(s) }
    for sub in view.subviews { found += scrollViews(in: sub) }
    return found
}
@MainActor func host<V: View>(_ v: V, width: CGFloat = 200, height: CGFloat = 200) -> (NSWindow, NSHostingView<V>) {
    let h = NSHostingView(rootView: v)
    let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                       styleMask: [.borderless], backing: .buffered, defer: false)
    win.isReleasedWhenClosed = false
    win.contentView = h
    win.orderFrontRegardless()
    spin(0.3)
    return (win, h)
}
@MainActor func scroll(_ h: NSView, x: CGFloat = 0, y: CGFloat = 0) {
    guard let s = scrollViews(in: h).first else { print("   (no NSScrollView)"); return }
    s.contentView.scroll(to: NSPoint(x: x, y: y))
    s.reflectScrolledClipView(s.contentView)
    spin(0.3)
}
struct SizeReader: ViewModifier {
    func body(content: Content) -> some View {
        content.background(GeometryReader { g in
            SwiftUI.Color.clear.onAppear { contentSize = g.size }
                .onChange(of: g.size) { _, n in contentSize = n }
        })
    }
}

@MainActor func probes() {
    let p200 = ProposedViewSize(width: 200, height: 200)
    let none = ProposedViewSize(width: nil, height: nil)

    print("=== A: sizing and spacing outside a ScrollView (children 30x10, 100x20, 50x10)")
    func kids() -> some View { Group { fx("a", 30, 10); fx("b", 100, 20); fx("c", 50, 10) } }
    arm("A0 control VStack(spacing: 0)", p200) { VStack(spacing: 0) { kids() } }
    arm("A1 LazyVStack(spacing: 0)", p200) { LazyVStack(spacing: 0) { kids() } }
    arm("A2 LazyVStack() default spacing", p200) { LazyVStack { kids() } }
    arm("A2c control VStack() default spacing", p200) { VStack { kids() } }
    arm("A3 LazyVStack(spacing: 0) at nil", none) { LazyVStack(spacing: 0) { kids() } }
    arm("A3c control VStack(spacing: 0) at nil", none) { VStack(spacing: 0) { kids() } }
    arm("A3b LazyVStack(spacing: 0) at nil, widths 100, 30, 50 (first is widest)", none) { LazyVStack(spacing: 0) { fx("a", 100, 10); fx("b", 30, 20); fx("c", 50, 10) } }
    arm("A3d LazyVStack(spacing: 0) at nil, widths 50, 100, 30 (middle is widest)", none) { LazyVStack(spacing: 0) { fx("a", 50, 10); fx("b", 100, 20); fx("c", 30, 10) } }
    arm("A10 LazyVStack() two Texts", none) { LazyVStack { Text("one"); Text("two") } }
    arm("A10c control VStack() two Texts", none) { VStack { Text("one"); Text("two") } }
    arm("A4 LazyVStack(alignment: .leading, spacing: 0)", p200) { LazyVStack(alignment: .leading, spacing: 0) { kids() } }
    arm("A4t LazyVStack(alignment: .trailing, spacing: 0)", p200) { LazyVStack(alignment: .trailing, spacing: 0) { kids() } }
    arm("A5 LazyVStack(spacing: 4) at width 80 (narrower than child b)", ProposedViewSize(width: 80, height: nil)) { LazyVStack(spacing: 4) { kids() } }
    arm("A6 LazyHStack(spacing: 0) at nil (children 30x10, 100x20, 50x10)", none) { LazyHStack(spacing: 0) { kids() } }
    arm("A6c control HStack(spacing: 0) at nil", none) { HStack(spacing: 0) { kids() } }
    arm("A7 LazyHStack(alignment: .top, spacing: 0) @200x200", p200) { LazyHStack(alignment: .top, spacing: 0) { kids() } }
    arm("A8 LazyVStack(spacing: 0) with a ForEach element of two views (a 30x10, b 100x20) then c", p200) {
        LazyVStack(spacing: 0) { ForEach(0..<1, id: \.self) { _ in fx("a", 30, 10); fx("b", 100, 20) }; fx("c", 50, 10) }
    }
    arm("A9 LazyVStack(spacing: 0) with an empty ForEach element between a and c (spacing: 6)", p200) {
        LazyVStack(spacing: 6) { fx("a", 30, 10); ForEach(0..<1, id: \.self) { _ in if false { fx("x", 5, 5) } }; fx("c", 50, 10) }
    }

    print("=== C: GridItem resolution, LazyVGrid at 200x200 (cells 10x10 unless stated)")
    func cells(_ n: Int, w: CGFloat = 10, h: CGFloat = 10) -> some View {
        ForEach(0..<n, id: \.self) { fx("c\($0)", w, h) }
    }
    arm("C1 .adaptive(minimum: 20, maximum: 50) x1, 8 cells", p200) { LazyVGrid(columns: [GridItem(.adaptive(minimum: 20, maximum: 50))]) { cells(8) } }
    arm("C2 .adaptive(minimum: 60, maximum: 70) x1, 4 cells", p200) { LazyVGrid(columns: [GridItem(.adaptive(minimum: 60, maximum: 70))]) { cells(4) } }
    arm("C3 .adaptive(minimum: 45) spacing: 20 on the item, 6 cells", p200) { LazyVGrid(columns: [GridItem(.adaptive(minimum: 45), spacing: 20)]) { cells(6) } }
    arm("C4 .fixed(50), .flexible(), .flexible(minimum: 20, maximum: 40), 6 cells", p200) {
        LazyVGrid(columns: [GridItem(.fixed(50)), GridItem(.flexible()), GridItem(.flexible(minimum: 20, maximum: 40))]) { cells(6) }
    }
    arm("C5 .flexible(minimum: 120), .flexible(minimum: 120) (minima exceed 200), 4 cells", p200) {
        LazyVGrid(columns: [GridItem(.flexible(minimum: 120)), GridItem(.flexible(minimum: 120))]) { cells(4) }
    }
    arm("C6 .flexible(), .flexible(maximum: 30), 4 cells", p200) {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible(maximum: 30))]) { cells(4) }
    }
    arm("C7 .fixed(30), .fixed(30) item spacing 20 then 0; grid spacing 4, 4 cells", p200) {
        LazyVGrid(columns: [GridItem(.fixed(30), spacing: 20), GridItem(.fixed(30), spacing: 0)], spacing: 4) { cells(4) }
    }
    arm("C8 .fixed(30) x2 with LazyVGrid(alignment: .leading) in 200 (columns narrower than the proposal)", p200) {
        LazyVGrid(columns: [GridItem(.fixed(30)), GridItem(.fixed(30))], alignment: .leading) { cells(4) }
    }
    arm("C8c control: the same, default alignment (.center)", p200) {
        LazyVGrid(columns: [GridItem(.fixed(30)), GridItem(.fixed(30))]) { cells(4) }
    }
    arm("C9 GridItem(.fixed(30), alignment: .topLeading) x2, cells 10x10 and 10x20 (row 0: c0 10x10, c1 10x20)", p200) {
        LazyVGrid(columns: [GridItem(.fixed(30), alignment: .topLeading), GridItem(.fixed(30), alignment: .bottomTrailing)]) {
            fx("c0", 10, 10); fx("c1", 10, 20); fx("c2", 10, 10); fx("c3", 10, 10)
        }
    }
    arm("C10 LazyVGrid(.flexible x2) at width 100 and nil height, cells 10x10 and 10x30 in row 1", ProposedViewSize(width: 100, height: nil)) {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())]) { fx("c0", 10, 10); fx("c1", 10, 10); fx("c2", 10, 30); fx("c3", 10, 10) }
    }
    arm("C11 LazyHGrid(rows: .flexible x2) at 200x100, cells 10x10 and 30x10 in column 1", ProposedViewSize(width: 200, height: 100)) {
        LazyHGrid(rows: [GridItem(.flexible()), GridItem(.flexible())]) { fx("c0", 10, 10); fx("c1", 10, 10); fx("c2", 30, 10); fx("c3", 10, 10) }
    }
    arm("C12 LazyVGrid(.adaptive(minimum: 45)) at nil width, 4 cells", none) { LazyVGrid(columns: [GridItem(.adaptive(minimum: 45))]) { cells(4) } }
    arm("C13 LazyVGrid(columns: []) (no items), 2 cells", p200) { LazyVGrid(columns: []) { cells(2) } }
    arm("C14 LazyVGrid(.fixed 40) x1, a ForEach element of two views (a, b) then c", p200) {
        LazyVGrid(columns: [GridItem(.fixed(40))]) { ForEach(0..<1, id: \.self) { _ in fx("a", 10, 10); fx("b", 10, 10) }; fx("c", 10, 10) }
    }

    arm("C15 .flexible(minimum: 150), .flexible() (one minimum above its share), 4 cells", p200) {
        LazyVGrid(columns: [GridItem(.flexible(minimum: 150)), GridItem(.flexible())]) { cells(4) }
    }
    arm("C16 .adaptive(minimum: 60, maximum: 70) at width 100 (one column wider than the maximum)", ProposedViewSize(width: 100, height: nil)) {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 60, maximum: 70))]) { cells(3) }
    }
    arm("C17 .fixed(40), .adaptive(minimum: 30), 6 cells", p200) {
        LazyVGrid(columns: [GridItem(.fixed(40)), GridItem(.adaptive(minimum: 30))]) { cells(6) }
    }
    print("=== R: realisation inside a 200x200 ScrollView (rows 20 tall, spacing 0, 1000 rows)")
    do {
        resetInstrument()
        let (w, h) = host(ScrollView { LazyVStack(spacing: 0) { ForEach(0..<1000, id: \.self) { Item(i: $0, w: 50, h: 20) } } })
        print("R1 LazyVStack at offset 0: built \(range(built)), visible(onAppear) \(range(visible))")
        scroll(h, y: 2000)
        print("R1 after scroll to 2000 (rows 100..109 on screen): built \(range(built)), visible \(range(visible))")
        scroll(h, y: 0)
        print("R1 back to 0: visible \(range(visible))")
        w.orderOut(nil); w.contentView = nil; spin(0.05)
    }
    do {
        resetInstrument()
        let (w, h) = host(ScrollView { VStack(spacing: 0) { ForEach(0..<1000, id: \.self) { Item(i: $0, w: 50, h: 20) } } })
        print("R0 control VStack at offset 0: built \(range(built)), visible \(range(visible))")
        w.orderOut(nil); w.contentView = nil; spin(0.05); _ = h
    }
    do {
        resetInstrument()
        let (w, h) = host(ScrollView(.horizontal) { LazyHStack(spacing: 0) { ForEach(0..<1000, id: \.self) { Item(i: $0, w: 20, h: 50) } } })
        print("R2 LazyHStack in a horizontal ScrollView at 0: built \(range(built)), visible \(range(visible))")
        scroll(h, x: 2000)
        print("R2 after scroll x to 2000 (columns 100..109): visible \(range(visible))")
        w.orderOut(nil); w.contentView = nil; spin(0.05)
    }
    do {
        resetInstrument()
        let (w, h) = host(ScrollView { LazyVStack(spacing: 0) { ForEach(0..<1000, id: \.self) { Item(i: $0, w: 20 + CGFloat($0) * 0.5, h: 20) } }.modifier(SizeReader()) })
        print("R3 cross size, width = 20 + 0.5 i, ScrollView(.vertical) 200 wide: realised \(range(visible)), the stack's width \(d(contentSize.width)) height \(d(contentSize.height))")
        scroll(h, y: 2000)
        print("R3 after scroll to 2000: realised \(range(visible)), the stack's width \(d(contentSize.width)) height \(d(contentSize.height))")
        w.orderOut(nil); w.contentView = nil; spin(0.05)
    }
    do {
        resetInstrument()
        let (w, h) = host(ScrollView { LazyVStack(spacing: 0) { ForEach(0..<1000, id: \.self) { Item(i: $0, w: $0 == 500 ? 500 : 50, h: 20 + ($0 == 500 ? 100 : 0)) } }.modifier(SizeReader()) })
        print("R4 total height with one unrealised 120-tall child among 1000 20-tall: height \(d(contentSize.height)) (all 20: 20000, if the unrealised were measured: 20100)")
        w.orderOut(nil); w.contentView = nil; spin(0.05); _ = h
    }

    do {
        resetInstrument()
        let (w, h) = host(ScrollView(.horizontal) { LazyVStack(spacing: 0) { ForEach(0..<1000, id: \.self) { Item(i: $0, w: 20 + CGFloat($0) * 0.5, h: 20) } }.modifier(SizeReader()) })
        print("R5 LazyVStack (nil width) in a horizontal ScrollView, width = 20 + 0.5 i: realised \(range(visible)), stack \(d(contentSize.width))x\(d(contentSize.height))")
        scroll(h, y: 2000)
        print("R5 after a vertical clip scroll to 2000: realised \(range(visible)), stack \(d(contentSize.width))x\(d(contentSize.height))")
        w.orderOut(nil); w.contentView = nil; spin(0.05)
    }
    print("=== S: state of a scrolled-out child (serial drawn by its @State at its first appearance)")
    do {
        resetInstrument()
        let (w, h) = host(ScrollView { LazyVStack(spacing: 0) { ForEach(0..<1000, id: \.self) { Item(i: $0, w: 50, h: 20) } } })
        let first = appearLog.filter { $0.0 == 0 }.map(\.1)
        scroll(h, y: 4000)
        scroll(h, y: 0)
        let again = appearLog.filter { $0.0 == 0 }.map(\.1)
        print("S1 LazyVStack child 0: appeared \(again.count) times, \(Set(again).count) distinct @State serials (1 = the state outlived leaving the screen), same as the first appearance: \(Set(again) == Set(first))")
        w.orderOut(nil); w.contentView = nil; spin(0.05)
    }
    do {
        resetInstrument()
        let (w, h) = host(ScrollView { VStack(spacing: 0) { ForEach(0..<1000, id: \.self) { Item(i: $0, w: 50, h: 20) } } })
        scroll(h, y: 4000); scroll(h, y: 0)
        print("S2 control VStack child 0: appeared \(appearLog.filter { $0.0 == 0 }.count) time (never left)")
        w.orderOut(nil); w.contentView = nil; spin(0.05)
    }

    print("=== G: lazy grid realisation, 200x200 ScrollView, 2 flexible columns, cells 10x30, 1000 cells")
    do {
        resetInstrument()
        let (w, h) = host(ScrollView { LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 0) { ForEach(0..<1000, id: \.self) { Item(i: $0, w: 10, h: 30) } }.modifier(SizeReader()) })
        print("G1 at 0: built \(range(built)), visible \(range(visible)), grid size \(d(contentSize.width))x\(d(contentSize.height)) (500 rows x 30 = 15000 if rows are uniform)")
        scroll(h, y: 3000)
        print("G1 after scroll to 3000 (row 100 at the top: cells 200...): visible \(range(visible))")
        w.orderOut(nil); w.contentView = nil; spin(0.05)
    }
    do {
        resetInstrument()
        let (w, h) = host(ScrollView { LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 0) { ForEach(0..<1000, id: \.self) { Item(i: $0, w: 10, h: $0 == 600 ? 130 : 30) } }.modifier(SizeReader()) })
        print("G2 one tall unrealised cell (130 at index 600, row 300): grid height \(d(contentSize.height)) (500x30 = 15000; with the tall row measured 15100)")
        w.orderOut(nil); w.contentView = nil; spin(0.05); _ = h
    }

    print("=== H: pinnedViews (Section header 30 tall, rows 20 tall, ScrollView 200x200 scrolled to y = 300)")
    do {
        resetInstrument()
        struct Hdr: View {
            var body: some View {
                SwiftUI.Color.red.frame(height: 30)
                    .background(GeometryReader { g in SwiftUI.Color.clear.onAppear { hdrFrame = g.frame(in: .named("sc")) }
                        .onChange(of: g.frame(in: .named("sc"))) { _, n in hdrFrame = n } })
            }
        }
        let (w, h) = host(ScrollView { LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
            Section(header: Hdr()) { ForEach(0..<200, id: \.self) { Item(i: $0, w: 50, h: 20) } } } }.coordinateSpace(name: "sc"))
        print("H1 at 0: header frame in the scroll view's space \(fmt(hdrFrame))")
        scroll(h, y: 300)
        print("H1 at 300: header frame \(fmt(hdrFrame)) (pinned: minY 0; unpinned: -300)")
        w.orderOut(nil); w.contentView = nil; spin(0.05)
    }
    do {
        let (w, h) = host(ScrollView { LazyVStack(spacing: 0) {
            Section(header: Color.red.frame(height: 30)
                .background(GeometryReader { g in SwiftUI.Color.clear.onChange(of: g.frame(in: .named("sc"))) { _, n in hdrFrame = n } })) {
                ForEach(0..<200, id: \.self) { Item(i: $0, w: 50, h: 20) } } } }.coordinateSpace(name: "sc"))
        hdrFrame = .zero
        scroll(h, y: 300)
        print("H0 control, no pinnedViews: header frame at 300 \(fmt(hdrFrame)) (onChange only; zero means it never reported a new frame)")
        w.orderOut(nil); w.contentView = nil; spin(0.05)
    }
    fflush(stdout)
}
nonisolated(unsafe) var hdrFrame = CGRect.zero

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
MainActor.assumeIsolated { probes() }
print("DONE")
